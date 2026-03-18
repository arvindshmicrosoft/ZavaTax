"""
Zava Tax Load Simulator - Database Worker

Simulates realistic OLTP workflow using stored procedures with connection reuse.
Workflow: AddCustomer → SaveTaxReturnDraft → UpdateTaxReturn (0-5x) → SubmitTaxReturn
Read Operations: View customer list, view tax returns, view professionals (from HA read replica)

Connection Management:
- Each worker maintains two connections:
  * Primary (read/write) - for write operations
  * HA read replica - for read operations with ApplicationIntent=ReadOnly
- Autocommit mode enabled (standard OLTP pattern)
- Staggered startup prevents authentication token stampede with many workers
"""

import time
import random
from typing import Optional, Callable, TypeVar, Any
from contextlib import contextmanager
from dataclasses import dataclass
from functools import wraps
import structlog

try:
    import mssql_python
except ImportError:
    print("❌ mssql-python not installed. Install with: pip install mssql-python")
    exit(1)

from .config import Config
from .data_generator import WorkflowGenerator, WorkflowSimulation, Customer, TaxReturn

logger = structlog.get_logger()

T = TypeVar('T')

# Transient error codes that should trigger retry
TRANSIENT_ERROR_CODES = {
    'IMC06',  # Connection broken and recovery not possible
    '08S01',  # Communication link failure
    '08001',  # Unable to connect
    '40001',  # Deadlock victim
    '40197',  # Service unavailable
    '40501',  # Service busy
    '40613',  # Database unavailable
    '49918',  # Cannot process request
    '49919',  # Cannot process create/update
    '49920',  # Cannot process delete
}

def is_transient_error(error: Exception) -> bool:
    """Check if error is a transient SQL error that should be retried."""
    error_str = str(error).upper()
    # Check for SQLSTATE codes
    for code in TRANSIENT_ERROR_CODES:
        if code in error_str:
            return True
    # Check for common transient messages
    transient_messages = [
        'CONNECTION IS BROKEN',
        'CONNECTION WAS LOST',
        'COMMUNICATION LINK',
        'TIMEOUT',
        'DEADLOCK',
        'SERVICE UNAVAILABLE',
    ]
    return any(msg in error_str for msg in transient_messages)

def with_retry(max_retries: int = 10, initial_delay: float = 0.1, max_delay: float = 10.0):
    """
    Decorator for retrying database operations with exponential backoff.
    Only retries on transient connection errors.
    Delays: 0.1s → 0.2s → 0.4s → 0.8s → 1.6s → 3.2s → 6.4s → 10s → 10s → 10s
    """
    def decorator(func: Callable[..., T]) -> Callable[..., T]:
        @wraps(func)
        def wrapper(self, *args, **kwargs) -> T:
            last_error = None
            delay = initial_delay
            
            for attempt in range(max_retries + 1):
                try:
                    return func(self, *args, **kwargs)
                except Exception as e:
                    last_error = e
                    
                    if attempt == max_retries:
                        # Final attempt failed
                        error_msg = str(e)[:150]
                        if "Login failed" in error_msg or "authentication" in error_msg.lower():
                            logger.error(f"{func.__name__} authentication failed", worker_id=getattr(self, 'worker_id', 0))
                        else:
                            logger.error(f"{func.__name__} failed after {max_retries + 1} attempts", worker_id=getattr(self, 'worker_id', 0), error=error_msg)
                        raise
                    
                    if not is_transient_error(e):
                        # Not a transient error, don't retry
                        error_msg = str(e)[:100]
                        if "Login failed" not in error_msg and "authentication" not in error_msg.lower():
                            logger.error(f"{func.__name__} non-transient error", worker_id=getattr(self, 'worker_id', 0), error=error_msg)
                        raise
                    
                    # Transient error, retry with backoff
                    if attempt == 0 or attempt % 3 == 0:  # Log every 3rd retry to reduce noise
                        logger.warning(
                            f"{func.__name__} transient error (attempt {attempt + 1}/{max_retries + 1}), retrying in {delay:.1f}s",
                            worker_id=getattr(self, 'worker_id', 0),
                            error=str(e)[:80]
                        )
                    
                    # Force connection reset on transient errors
                    if hasattr(self, '_connection'):
                        self._connection = None
                    if hasattr(self, '_readonly_connection'):
                        self._readonly_connection = None
                    
                    time.sleep(delay)
                    delay = min(delay * 2, max_delay)  # Exponential backoff with cap
            
            raise last_error
        return wrapper
    return decorator


@dataclass
class WorkflowResult:
    """Result of a complete workflow execution."""
    success: bool
    customer_id: Optional[int]
    return_id: Optional[int]
    num_edits_executed: int
    num_reads_executed: int
    total_duration_ms: float
    bytes_written: int
    error: Optional[str] = None


class DatabaseWorker:
    """
    Database worker that simulates realistic OLTP workflow.
    
    Write operations (Primary):
    1. AddCustomer - creates customer, returns CustomerId
    2. SaveTaxReturnDraft - creates draft tax return
    3. UpdateTaxReturn - simulates edit cycles (0-5 times)
    4. SubmitTaxReturn - final submission
    
    Read operations (HA read replica with ApplicationIntent=ReadOnly):
    1. GetRecentTaxReturns - view recent returns
    2. GetCustomersByProfessional - view client list
    3. GetProfessionalsByBranch - view team roster
    """
    
    def __init__(self, config: Config, worker_id: int = 0):
        self.config = config
        self.worker_id = worker_id
        self.connection_string = config.db.connection_string
        self.readonly_connection_string = config.db.readonly_connection_string
        self._connection = None  # Primary connection (read/write)
        self._readonly_connection = None  # HA read replica connection
        self.is_debug = config.log_level == 'DEBUG'
        self.read_percentage = config.load.read_percentage
        self.generator = WorkflowGenerator(
            num_branches=config.load.num_branches,
            num_professionals=config.load.num_professionals,
            worker_id=worker_id
        )
        
    @contextmanager
    def get_connection(self):
        """Get primary database connection with auto-reconnect. Connection is reused across workflows."""
        try:
            if self._connection is None:
                self._connect_primary()
            yield self._connection
        except Exception as e:
            if is_transient_error(e):
                logger.warning("Primary connection error, will retry", 
                             worker_id=self.worker_id, error=str(e))
                self._connection = None
            raise
    
    @contextmanager
    def get_readonly_connection(self):
        """Get readonly database connection with auto-reconnect. Connection is reused across workflows."""
        try:
            if self._readonly_connection is None:
                self._connect_readonly()
            yield self._readonly_connection
        except Exception as e:
            if is_transient_error(e):
                logger.warning("Readonly connection error, will retry", 
                             worker_id=self.worker_id, error=str(e))
                self._readonly_connection = None
            raise
    
    def connect(self):
        """Establish database connections (primary and HA read replica). Called during staggered startup."""
        if self._connection is None:
            self._connect_primary()
        if self._readonly_connection is None:
            self._connect_readonly()
    
    def _connect_primary(self):
        """Establish primary connection (read/write)."""
        logger.info("Connecting to primary", worker_id=self.worker_id)
        self._connection = mssql_python.connect(self.connection_string, timeout=self.config.db.connection_timeout)
        self._connection.autocommit = True
        logger.info("Primary connection established", worker_id=self.worker_id)
    
    def _connect_readonly(self):
        """Establish HA read replica connection."""
        logger.info("Connecting to HA read replica", worker_id=self.worker_id)
        self._readonly_connection = mssql_python.connect(self.readonly_connection_string, timeout=self.config.db.connection_timeout)
        self._readonly_connection.autocommit = True
        logger.info("Read replica connection established", worker_id=self.worker_id)
    
    def _connect(self):
        """Internal connection establishment using mssql-python with autocommit."""
        self._connect_primary()
        self._connect_readonly()
    
    def close(self):
        """Close database connections."""
        if self._connection:
            try:
                self._connection.close()
            except:
                pass
            self._connection = None
        
        if self._readonly_connection:
            try:
                self._readonly_connection.close()
            except:
                pass
            self._readonly_connection = None
    
    @with_retry(max_retries=10)
    def add_customer(self, customer: Customer) -> Optional[int]:
        """
        Call AddCustomer stored procedure.
        Returns CustomerId on success, None on failure.
        """
        if self.is_debug:
            print(f"[Worker {self.worker_id}] Calling AddCustomer...")
        
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                EXEC dbo.AddCustomer
                    @FirstName = ?,
                    @LastName = ?,
                    @Email = ?,
                    @Phone = ?,
                    @Address = ?,
                    @City = ?,
                    @State = ?,
                    @StateAbbr = ?,
                    @ZipCode = ?,
                    @DateOfBirth = ?,
                    @SSNLastFour = ?,
                    @PreferredLanguage = ?,
                    @PreferredContact = ?
            """, (
                customer.first_name,
                customer.last_name,
                customer.email,
                customer.phone,
                customer.address,
                customer.city,
                customer.state,
                customer.state_abbr,
                customer.zip_code,
                customer.date_of_birth,
                customer.ssn_last_four,
                customer.preferred_language,
                customer.preferred_contact
            ))
            
            result = cursor.fetchone()
            customer_id = result[0] if result else None
            cursor.close()
            
            if self.is_debug:
                print(f"[Worker {self.worker_id}] AddCustomer returned: {customer_id}")
            
            return customer_id
    
    @with_retry(max_retries=10)
    def save_draft(self, tax_return: TaxReturn) -> Optional[int]:
        """
        Call SaveTaxReturnDraft stored procedure.
        Returns ReturnId on success, None on failure.
        """
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                    EXEC dbo.SaveTaxReturnDraft
                        @CustomerId = ?,
                        @BranchId = ?,
                        @ProfessionalId = ?,
                        @TaxYear = ?,
                        @FilingStatus = ?,
                        @GrossIncome = ?,
                        @AdjustedGrossIncome = ?,
                        @TotalDeductions = ?,
                        @TaxableIncome = ?,
                        @TaxLiability = ?,
                        @TotalWithheld = ?,
                        @RefundAmount = ?,
                        @AmountOwed = ?,
                        @IsItemized = ?,
                        @NumDependents = ?,
                        @ProcessingTimeMinutes = ?,
                        @DocumentCount = ?,
                        @AIAssistanceCount = ?,
                        @IsAmended = ?,
                        @IsExtension = ?,
                        @HasForeignAccounts = ?,
                        @ForeignAccountMaxValue = ?,
                        @HasPFIC = ?,
                        @PFICValue = ?,
                        @PFICIncome = ?,
                        @HasForeignTrust = ?,
                        @ForeignTrustValue = ?,
                        @HasForeignCorporation = ?,
                        @ForeignCorpOwnershipPct = ?,
                        @HasForeignPartnership = ?,
                        @ForeignGiftsReceived = ?,
                        @ForeignTaxesPaid = ?
                """, (
                    tax_return.customer_id,
                    tax_return.branch_id,
                    tax_return.professional_id,
                    tax_return.tax_year,
                    tax_return.filing_status,
                    tax_return.gross_income,
                    tax_return.adjusted_gross_income,
                    tax_return.total_deductions,
                    tax_return.taxable_income,
                    tax_return.tax_liability,
                    tax_return.total_withheld,
                    tax_return.refund_amount,
                    tax_return.amount_owed,
                    tax_return.is_itemized,
                    tax_return.num_dependents,
                    tax_return.processing_time_minutes,
                    tax_return.document_count,
                    tax_return.ai_assistance_count,
                    tax_return.is_amended,
                    tax_return.is_extension,
                    tax_return.has_foreign_accounts,
                    tax_return.foreign_account_max_value,
                    tax_return.has_pfic,
                    tax_return.pfic_value,
                    tax_return.pfic_income,
                    tax_return.has_foreign_trust,
                    tax_return.foreign_trust_value,
                    tax_return.has_foreign_corporation,
                    tax_return.foreign_corp_ownership_pct,
                    tax_return.has_foreign_partnership,
                    tax_return.foreign_gifts_received,
                    tax_return.foreign_taxes_paid
                ))
                
            result = cursor.fetchone()
            return_id = result[0] if result else None
            
            cursor.close()  # Autocommit enabled
            
            return return_id
    def update_return(self, tax_return: TaxReturn, return_id: int) -> bool:
        """
        Call UpdateTaxReturn stored procedure (simulates editing).
        Returns True on success.
        """
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                    EXEC dbo.UpdateTaxReturn
                        @ReturnId = ?,
                        @GrossIncome = ?,
                        @AdjustedGrossIncome = ?,
                        @TotalDeductions = ?,
                        @TaxableIncome = ?,
                        @TaxLiability = ?,
                        @TotalWithheld = ?,
                        @RefundAmount = ?,
                        @AmountOwed = ?,
                        @ProcessingTimeMinutes = ?,
                        @DocumentCount = ?,
                        @AIAssistanceCount = ?
                """, (
                    return_id,
                    tax_return.gross_income,
                    tax_return.adjusted_gross_income,
                    tax_return.total_deductions,
                    tax_return.taxable_income,
                    tax_return.tax_liability,
                    tax_return.total_withheld,
                    tax_return.refund_amount,
                    tax_return.amount_owed,
                    tax_return.processing_time_minutes,
                    tax_return.document_count,
                    tax_return.ai_assistance_count
                ))
            
            cursor.fetchone()  # Consume result
            cursor.close()  # Autocommit enabled
            
            return True
    
    @with_retry(max_retries=10)
    def submit_return(self, return_id: int) -> bool:
        """
        Call SubmitTaxReturn stored procedure (final submission).
        Returns True on success.
        """
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("EXEC dbo.SubmitTaxReturn @ReturnId = ?", (return_id,))
            
            cursor.fetchone()  # Consume result
            cursor.close()  # Autocommit enabled
            
            return True
    
    # ========================================
    # Read Operations (HA Read Replica)
    # ========================================
    
    @with_retry(max_retries=10)
    def get_recent_returns(self, professional_id: int, limit: int = 20) -> bool:
        """
        Read operation: Get recent tax returns for a professional.
        Uses HA read replica with ApplicationIntent=ReadOnly.
        """
        with self.get_readonly_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                    SELECT TOP (?) 
                        ReturnId, CustomerId, TaxYear, FilingStatus, 
                        GrossIncome, TaxLiability, RefundAmount
                    FROM TaxReturns
                    WHERE ProfessionalId = ?
                    ORDER BY FilingDate DESC
                """, (limit, professional_id))
                
            rows = cursor.fetchall()
            cursor.close()
            
            if self.is_debug:
                print(f"[Worker {self.worker_id}] Read {len(rows)} recent returns from HA replica")
            
            return True
    @with_retry(max_retries=10)
    def get_customers_by_professional(self, professional_id: int, limit: int = 50) -> bool:
        """
        Read operation: Get customer list for a professional.
        Uses HA read replica with ApplicationIntent=ReadOnly.
        """
        with self.get_readonly_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                    SELECT DISTINCT TOP (?)
                        c.CustomerId, c.FirstName, c.LastName, c.Email, 
                        c.Phone, c.City, c.StateAbbr
                    FROM Customers c
                    INNER JOIN TaxReturns tr ON c.CustomerId = tr.CustomerId
                    WHERE tr.ProfessionalId = ?
                    ORDER BY c.LastName, c.FirstName
                """, (limit, professional_id))
                
            rows = cursor.fetchall()
            cursor.close()
            
            if self.is_debug:
                print(f"[Worker {self.worker_id}] Read {len(rows)} customers from HA replica")
            
            return True
    @with_retry(max_retries=10)
    def get_professionals_by_branch(self, branch_id: int) -> bool:
        """
        Read operation: Get professionals roster for a branch.
        Uses HA read replica with ApplicationIntent=ReadOnly.
        """
        with self.get_readonly_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                    SELECT 
                        ProfessionalId, FirstName, LastName, Email,
                        Certification, YearsExperience, IsActive
                    FROM TaxProfessionals
                    WHERE BranchId = ? AND IsActive = 1
                    ORDER BY LastName, FirstName
                """, (branch_id,))
                
            rows = cursor.fetchall()
            cursor.close()
            
            if self.is_debug:
                print(f"[Worker {self.worker_id}] Read {len(rows)} professionals from HA replica")
            
            return True
    @with_retry(max_retries=10)
    def get_return_details(self, return_id: int) -> bool:
        """
        Read operation: Get detailed tax return information.
        Uses HA read replica with ApplicationIntent=ReadOnly.
        """
        with self.get_readonly_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                    SELECT 
                        tr.ReturnId, tr.CustomerId, tr.ProfessionalId, tr.TaxYear,
                        tr.FilingStatus, tr.GrossIncome, tr.TotalDeductions,
                        tr.TaxableIncome, tr.TaxLiability, tr.RefundAmount,
                        c.FirstName, c.LastName, c.Email,
                        p.FirstName AS ProfFirstName, p.LastName AS ProfLastName
                    FROM TaxReturns tr
                    INNER JOIN Customers c ON tr.CustomerId = c.CustomerId
                    INNER JOIN TaxProfessionals p ON tr.ProfessionalId = p.ProfessionalId
                    WHERE tr.ReturnId = ?
                """, (return_id,))
                
            row = cursor.fetchone()
            cursor.close()
            
            if self.is_debug and row:
                print(f"[Worker {self.worker_id}] Read return details from HA replica")
            
            return row is not None
    
    def execute_read_operations(self, professional_id: int, branch_id: int) -> int:
        """
        Execute multiple read operations from HA read replica.
        Returns number of successful reads.
        """
        successful_reads = 0
        
        # Mix of different read operations
        read_ops = [
            lambda: self.get_recent_returns(professional_id, random.randint(10, 30)),
            lambda: self.get_customers_by_professional(professional_id, random.randint(20, 50)),
            lambda: self.get_professionals_by_branch(branch_id),
            lambda: self.get_return_details(random.randint(1, 100000)),
        ]
        
        # Execute 2-4 random read operations
        num_reads = random.randint(2, 4)
        for _ in range(num_reads):
            op = random.choice(read_ops)
            if op():
                successful_reads += 1
        
        return successful_reads
    
    def execute_workflow(self) -> WorkflowResult:
        """
        Execute a complete workflow simulation with read/write mix.
        
        Write Steps (Primary):
        1. Generate customer data
        2. AddCustomer (get CustomerId)
        3. Generate tax return data
        4. SaveTaxReturnDraft (get ReturnId)
        5. UpdateTaxReturn (0-5 times with mutations)
        6. SubmitTaxReturn
        
        Read Steps (HA Read Replica): Executed probabilistically based on read_percentage
        - Before workflow: View recent returns, customer lists
        - During edits: View return details
        - After submission: View updated lists
        
        Returns result with timing and status.
        """
        if self.is_debug:
            print(f"[Worker {self.worker_id}] Starting workflow...")
        
        start_time = time.perf_counter()
        bytes_written = 0
        reads_executed = 0
        
        try:
            # Generate workflow data
            workflow = self.generator.generate_workflow()
            
            # Read operations BEFORE write (simulating user browsing before creating)
            if random.randint(0, 100) < self.read_percentage:
                reads_executed += self.execute_read_operations(
                    workflow.tax_return.professional_id,
                    workflow.tax_return.branch_id
                )
            
            # Step 1-2: Create customer
            customer_id = self.add_customer(workflow.customer)
            
            if customer_id is None:
                return WorkflowResult(
                    success=False,
                    customer_id=None,
                    return_id=None,
                    num_edits_executed=0,
                    num_reads_executed=reads_executed,
                    total_duration_ms=(time.perf_counter() - start_time) * 1000,
                    bytes_written=0,
                    error="Failed to create customer"
                )
            
            bytes_written += 500  # Estimate customer record size
            
            # Step 3-4: Create draft tax return
            workflow.tax_return.customer_id = customer_id
            return_id = self.save_draft(workflow.tax_return)
            
            if return_id is None:
                return WorkflowResult(
                    success=False,
                    customer_id=customer_id,
                    return_id=None,
                    num_edits_executed=0,
                    num_reads_executed=reads_executed,
                    total_duration_ms=(time.perf_counter() - start_time) * 1000,
                    bytes_written=bytes_written,
                    error="Failed to create tax return draft"
                )
            
            bytes_written += 800  # Estimate tax return record size
            
            # Step 5: Edit cycles (0-5 times) with interspersed reads
            edits_completed = 0
            for _ in range(workflow.num_edits):
                # Read operation during editing (like viewing current state)
                if random.randint(0, 100) < self.read_percentage:
                    if self.get_return_details(return_id):
                        reads_executed += 1
                
                workflow.tax_return.mutate_for_edit()
                if self.update_return(workflow.tax_return, return_id):
                    edits_completed += 1
                    bytes_written += 50  # Estimate update size
                else:
                    break
            
            # Step 6: Submit
            if not self.submit_return(return_id):
                return WorkflowResult(
                    success=False,
                    customer_id=customer_id,
                    return_id=return_id,
                    num_edits_executed=edits_completed,
                    num_reads_executed=reads_executed,
                    total_duration_ms=(time.perf_counter() - start_time) * 1000,
                    bytes_written=bytes_written,
                    error="Failed to submit tax return"
                )
            
            bytes_written += 50  # Estimate submission update size
            
            # Read operations AFTER submit (simulating checking updated status)
            if random.randint(0, 100) < self.read_percentage:
                reads_executed += self.execute_read_operations(
                    workflow.tax_return.professional_id,
                    workflow.tax_return.branch_id
                )
            
            return WorkflowResult(
                success=True,
                customer_id=customer_id,
                return_id=return_id,
                num_edits_executed=edits_completed,
                num_reads_executed=reads_executed,
                total_duration_ms=(time.perf_counter() - start_time) * 1000,
                bytes_written=bytes_written
            )
            
        except Exception as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            error_msg = str(e)[:100]
            # Only log non-authentication errors to reduce noise
            if "Login failed" not in error_msg and "authentication" not in error_msg.lower():
                logger.error("Workflow execution failed", worker_id=self.worker_id, error=error_msg)
            return WorkflowResult(
                success=False,
                customer_id=None,
                return_id=None,
                num_edits_executed=0,
                num_reads_executed=reads_executed,
                total_duration_ms=duration_ms,
                bytes_written=bytes_written,
                error=error_msg
            )


def create_worker(config: Config, worker_id: int = 0) -> DatabaseWorker:
    """Factory function to create a database worker."""
    return DatabaseWorker(config, worker_id)
