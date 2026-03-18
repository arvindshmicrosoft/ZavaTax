"""
Analytics Load Simulator for Hyperscale Named Replica

Generates synthetic read load on analytics stored procedures to demonstrate:
- Named replica auto-scaling with serverless compute
- Columnstore index performance under concurrent analytical queries
- Branch manager and executive dashboard workloads

Uses mssql-python native driver with Azure AD authentication - no hardcoded credentials.

Usage:
    python analytics_load_test.py --connections 10 --duration 300
    python analytics_load_test.py --connections 50 --duration 600 --server myserver.database.windows.net
    python analytics_load_test.py --ramp-up --max-connections 100
"""

import argparse
import multiprocessing as mp
import re
import time
import random
import os
import sys
from datetime import datetime, timedelta
from typing import List, Dict, Optional, Callable, TypeVar
from dataclasses import dataclass, field
import threading
from collections import defaultdict
from functools import wraps

try:
    import mssql_python
except ImportError:
    print("❌ Error: mssql-python not installed")
    print("   Install with: pip install mssql-python")
    sys.exit(1)

# ============================================================================
# Retry Logic for Transient Errors
# ============================================================================

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
                        print(f"[Worker {getattr(self, 'worker_id', 0)}] {func.__name__} FAILED after {max_retries + 1} attempts: {str(e)[:150]}")
                        raise
                    
                    if not is_transient_error(e):
                        # Not a transient error, don't retry
                        raise
                    
                    # Transient error, retry with backoff
                    print(f"[Worker {getattr(self, 'worker_id', 0)}] {func.__name__} transient error (attempt {attempt + 1}/{max_retries + 1}), retrying in {delay:.1f}s: {str(e)[:100]}")
                    
                    # Force connection reset on transient errors
                    if hasattr(self, 'conn'):
                        try:
                            if hasattr(self, 'cursor') and self.cursor:
                                self.cursor.close()
                            if self.conn:
                                self.conn.close()
                        except:
                            pass
                        self.conn = None
                        self.cursor = None
                    
                    time.sleep(delay)
                    delay = min(delay * 2, max_delay)  # Exponential backoff with cap
                    
                    # Try to reconnect - must succeed or will fail on next attempt
                    if hasattr(self, 'connect'):
                        try:
                            self.connect()
                            print(f"[Worker {getattr(self, 'worker_id', 0)}] Reconnected successfully")
                        except Exception as reconnect_error:
                            print(f"[Worker {getattr(self, 'worker_id', 0)}] Reconnect failed: {reconnect_error}")
            
            raise last_error
        return wrapper
    return decorator

# ============================================================================
# Configuration
# ============================================================================

@dataclass
class TestConfig:
    """Load test configuration."""
    server: str
    database: str
    connections: int
    duration_seconds: int
    query_mix: Dict[str, float]  # Procedure name -> weight
    ramp_up: bool = False
    max_connections: int = 100
    ramp_up_step: int = 10
    ramp_up_interval: int = 30
    think_time_ms: int = 100
    verbose: bool = False
    branch_id_min: int = 1
    branch_id_max: int = 500


# ============================================================================
# Analytics Query Definitions
# ============================================================================

ANALYTICS_QUERIES = {
    # Branch Manager Queries (40% of load)
    "GetBranchAnalytics": {
        "weight": 0.25,
        "sql": "EXEC dbo.GetBranchAnalytics @BranchId = {branch_id};",
        "params": {"branch_id": "branch_id_range"},
        "description": "Branch performance analytics (NCCI scan)"
    },
    "GetBranchLeaderboard": {
        "weight": 0.15,
        "sql": "EXEC dbo.GetBranchLeaderboard @BranchId = {branch_id};",
        "params": {"branch_id": "branch_id_range"},
        "description": "Branch professional leaderboard"
    },
    
    # Executive Queries (40% of load)
    "GetExecutiveKPIs": {
        "weight": 0.20,
        "sql": "EXEC dbo.GetExecutiveKPIs;",
        "params": {},
        "description": "Executive KPIs (full CCI scan)"
    },
    "GetTopBranches": {
        "weight": 0.15,
        "sql": "EXEC dbo.GetTopBranches @TopN = {top_n}, @TaxYear = {tax_year};",
        "params": {"top_n": lambda: random.choice([5, 10, 20]), "tax_year": lambda: random.choice([2023, 2024, 2025])},
        "description": "Top performing branches"
    },
    "GetFilingStatusDistribution": {
        "weight": 0.05,
        "sql": "EXEC dbo.GetFilingStatusDistribution;",
        "params": {},
        "description": "Filing status breakdown"
    },
    
    # Trend Analysis Queries (10% of load)
    "GetReturnsByYear": {
        "weight": 0.10,
        "sql": "EXEC dbo.GetReturnsByYear;",
        "params": {},
        "description": "Multi-year trend analysis"
    },
    
    # System Monitoring (10% of load)
    "GetHyperscaleResourceStats": {
        "weight": 0.10,
        "sql": "EXEC dbo.GetHyperscaleResourceStats;",
        "params": {},
        "description": "Hyperscale resource utilization"
    },

    # Filing Detail Analytics (NCCI scans on detail tables via named replica)
    "GetFilingDetailOverview": {
        "weight": 0.05,
        "sql": "EXEC dbo.GetFilingDetailOverview @TaxYear = {tax_year};",
        "params": {"tax_year": lambda: random.choice([2023, 2024, 2025])},
        "description": "Cross-table filing detail row counts"
    },
    "GetEFileStatusSummary": {
        "weight": 0.05,
        "sql": "EXEC dbo.GetEFileStatusSummary @TaxYear = {tax_year};",
        "params": {"tax_year": lambda: random.choice([2023, 2024, 2025])},
        "description": "E-file acceptance/rejection rates"
    },
    "GetW2Summary": {
        "weight": 0.05,
        "sql": "EXEC dbo.GetW2Summary @TaxYear = {tax_year};",
        "params": {"tax_year": lambda: random.choice([2023, 2024, 2025])},
        "description": "W-2 wage and withholding analytics"
    },
    "GetForm1099Summary": {
        "weight": 0.03,
        "sql": "EXEC dbo.GetForm1099Summary @TaxYear = {tax_year};",
        "params": {"tax_year": lambda: random.choice([2023, 2024, 2025])},
        "description": "1099 type distribution analytics"
    },
    "GetCapitalGainsSummary": {
        "weight": 0.03,
        "sql": "EXEC dbo.GetCapitalGainsSummary @TaxYear = {tax_year};",
        "params": {"tax_year": lambda: random.choice([2023, 2024, 2025])},
        "description": "Capital gains/losses analytics"
    },
    "GetScheduleCSummary": {
        "weight": 0.02,
        "sql": "EXEC dbo.GetScheduleCSummary @TaxYear = {tax_year};",
        "params": {"tax_year": lambda: random.choice([2023, 2024, 2025])},
        "description": "Schedule C self-employment analytics"
    },
    "GetStateTaxSummary": {
        "weight": 0.02,
        "sql": "EXEC dbo.GetStateTaxSummary @TaxYear = {tax_year};",
        "params": {"tax_year": lambda: random.choice([2023, 2024, 2025])},
        "description": "State tax filing analytics"
    },
    "GetScheduleESummary": {
        "weight": 0.02,
        "sql": "EXEC dbo.GetScheduleESummary @TaxYear = {tax_year};",
        "params": {"tax_year": lambda: random.choice([2023, 2024, 2025])},
        "description": "Schedule E rental & royalty analytics"
    },
    "GetScheduleBSummary": {
        "weight": 0.02,
        "sql": "EXEC dbo.GetScheduleBSummary @TaxYear = {tax_year};",
        "params": {"tax_year": lambda: random.choice([2023, 2024, 2025])},
        "description": "Schedule B interest & dividend analytics"
    },
    "GetDocumentSummary": {
        "weight": 0.02,
        "sql": "EXEC dbo.GetDocumentSummary @TaxYear = {tax_year};",
        "params": {"tax_year": lambda: random.choice([2023, 2024, 2025])},
        "description": "Tax form document analytics"
    }
}


# ============================================================================
# Worker Process
# ============================================================================

class QueryExecutor:
    """Executes analytics queries using mssql-python native driver."""
    
    def __init__(self, worker_id: int, config: TestConfig, stats_queue: mp.Queue):
        self.worker_id = worker_id
        self.config = config
        self.stats_queue = stats_queue
        self.running = False
        self.conn = None
        self.cursor = None
        
    def connect(self):
        """Establish database connection using Azure AD authentication."""
        # Close existing connections first
        try:
            if self.cursor:
                self.cursor.close()
            if self.conn:
                self.conn.close()
        except:
            pass
        
        self.conn = None
        self.cursor = None
        
        if self.config.verbose:
            print(f"[Worker {self.worker_id}] Attempting connection to {self.config.server}/{self.config.database}...")
        
        conn_str = (
            f"Server={self.config.server};"
            f"Database={self.config.database};"
            f"Authentication=ActiveDirectoryDefault;"
            f"Encrypt=yes;"
        )
        self.conn = mssql_python.connect(conn_str, timeout=30)
        self.cursor = self.conn.cursor()
        
        if self.config.verbose:
            print(f"[Worker {self.worker_id}] Connection successful!")
            print(f"[Worker {self.worker_id}] Connected to analytics replica")
    
    def is_connection_alive(self) -> bool:
        """Check if connection is still alive with a simple query."""
        try:
            if self.conn is None:
                return False
            test_cursor = self.conn.cursor()
            test_cursor.execute("SELECT 1")
            test_cursor.fetchone()
            test_cursor.close()
            return True
        except:
            return False
    
    def disconnect(self):
        """Close database connection."""
        if self.cursor:
            self.cursor.close()
        if self.conn:
            self.conn.close()
    
    @with_retry(max_retries=10)
    def execute_query(self, query_name: str, query_def: Dict) -> Dict:
        """Execute a single query and return timing stats."""
        start_time = time.time()
        
        # Validate connection - force reconnect if dead
        if not self.is_connection_alive():
            if self.config.verbose:
                print(f"[Worker {self.worker_id}] Connection dead, reconnecting...")
            self.connect()
        
        # Create fresh cursor for this query to avoid stale cursor issues
        query_cursor = self.conn.cursor()
        query_cursor.timeout = 60  # 60 second execution timeout for analytics queries
        
        try:
            # Generate parameters
            params = {}
            for k, v in query_def["params"].items():
                if v == "branch_id_range":
                    params[k] = random.randint(self.config.branch_id_min, self.config.branch_id_max)
                elif callable(v):
                    params[k] = v()
                else:
                    params[k] = v

            # Build parameterized query: replace {name} placeholders with ?
            # and pass values as a tuple to avoid SQL injection
            param_names = re.findall(r'\{(\w+)\}', query_def["sql"])
            query_sql = re.sub(r'\{\w+\}', '?', query_def["sql"])
            param_values = tuple(params[name] for name in param_names)
            
            # Execute query using fresh cursor with parameterized values
            query_cursor.execute(query_sql, param_values)
            
            # Fetch results to complete query execution
            rows = query_cursor.fetchall()
            row_count = len(rows)
            
            duration_ms = (time.time() - start_time) * 1000
            
            return {
                "worker_id": self.worker_id,
                "query_name": query_name,
                "duration_ms": duration_ms,
                "success": True,
                "row_count": row_count,
                "error": None,
                "timestamp": datetime.utcnow().isoformat()
            }
        finally:
            # Always close the query cursor
            try:
                query_cursor.close()
            except:
                pass
    
    def select_query(self) -> tuple:
        """Select a query based on configured weights."""
        queries = []
        weights = []
        for name, query_def in ANALYTICS_QUERIES.items():
            if name in self.config.query_mix:
                queries.append((name, query_def))
                weights.append(self.config.query_mix[name])
        
        if not queries:
            raise ValueError(f"No queries available! query_mix: {self.config.query_mix}, ANALYTICS_QUERIES keys: {list(ANALYTICS_QUERIES.keys())}")
        
        return random.choices(queries, weights=weights)[0]
    
    def run(self, stop_event: mp.Event):
        """Main worker loop."""
        self.running = True
        query_count = 0
        
        try:
            # Connect to database (each worker has its own connection)
            self.connect()
            
            if self.config.verbose:
                print(f"[Worker {self.worker_id}] Connected and starting analytics load generation")
            
            while self.running and not stop_event.is_set():
                # Select and execute query
                query_name, query_def = self.select_query()
                
                try:
                    stats = self.execute_query(query_name, query_def)
                except Exception as e:
                    # Query failed even after retries
                    if self.config.verbose:
                        print(f"[Worker {self.worker_id}] Query {query_name} failed after retries: {e}")
                    stats = {
                        "worker_id": self.worker_id,
                        "query_name": query_name,
                        "duration_ms": 0.0,
                        "success": False,
                        "row_count": 0,
                        "error": str(e)[:200],
                        "timestamp": datetime.utcnow().isoformat()
                    }
                
                # Send stats to main process
                self.stats_queue.put(stats)
                query_count += 1
                
                # Think time (simulate user reading results)
                if self.config.think_time_ms > 0:
                    time.sleep(self.config.think_time_ms / 1000.0)
        
        except Exception as e:
            print(f"[Worker {self.worker_id}] Fatal error: {e}")
            import traceback
            traceback.print_exc()
        
        finally:
            self.disconnect()
            if self.config.verbose:
                print(f"[Worker {self.worker_id}] Completed {query_count} queries")


def worker_process(worker_id: int, config: TestConfig, stop_event: mp.Event, stats_queue: mp.Queue):
    """Worker process entry point."""
    try:
        executor = QueryExecutor(worker_id, config, stats_queue)
        executor.run(stop_event)
    except Exception as e:
        print(f"[Worker {worker_id}] FATAL: Worker crashed: {e}")
        import traceback
        traceback.print_exc()



# ============================================================================
# Statistics Collector
# ============================================================================

class StatsCollector:
    """Collects and displays real-time statistics."""
    
    def __init__(self):
        self.query_stats = defaultdict(lambda: {"count": 0, "total_ms": 0, "errors": 0})
        self.total_queries = 0
        self.total_errors = 0
        self.error_messages = []  # Store recent error messages
        self.start_time = None
        self.lock = threading.Lock()
    
    def process_stat(self, stat: Dict):
        """Process a single query stat."""
        with self.lock:
            query_name = stat["query_name"]
            self.query_stats[query_name]["count"] += 1
            self.query_stats[query_name]["total_ms"] += stat["duration_ms"]
            
            if not stat["success"]:
                self.query_stats[query_name]["errors"] += 1
                self.total_errors += 1
                # Store error message (keep last 50 unique errors)
                error_detail = stat.get('error', 'Unknown error')
                if error_detail:  # Only store if there's actual error text
                    error_msg = f"[{query_name}] {error_detail}"
                    if error_msg not in self.error_messages:
                        self.error_messages.append(error_msg)
                        if len(self.error_messages) > 50:
                            self.error_messages.pop(0)
            
            self.total_queries += 1
    
    def get_summary(self) -> Dict:
        """Get current statistics summary."""
        with self.lock:
            elapsed = time.time() - self.start_time if self.start_time else 0
            qps = self.total_queries / elapsed if elapsed > 0 else 0
            
            query_breakdown = {}
            for query_name, stats in self.query_stats.items():
                avg_ms = stats["total_ms"] / stats["count"] if stats["count"] > 0 else 0
                query_breakdown[query_name] = {
                    "count": stats["count"],
                    "avg_ms": round(avg_ms, 2),
                    "errors": stats["errors"]
                }
            
            return {
                "elapsed_seconds": round(elapsed, 1),
                "total_queries": self.total_queries,
                "queries_per_second": round(qps, 2),
                "total_errors": self.total_errors,
                "error_rate": round(self.total_errors / max(self.total_queries, 1) * 100, 2),
                "query_breakdown": query_breakdown
            }
    
    def print_summary(self):
        """Print formatted statistics summary."""
        summary = self.get_summary()
        
        print("\n" + "="*70)
        print(f"Elapsed: {summary['elapsed_seconds']}s | "
              f"Queries: {summary['total_queries']} | "
              f"QPS: {summary['queries_per_second']} | "
              f"Errors: {summary['total_errors']} ({summary['error_rate']}%)")
        print("="*70)
        print(f"{'Query':<30} {'Count':>10} {'Avg (ms)':>12} {'Errors':>10}")
        print("-"*70)
        
        for query_name, stats in sorted(summary['query_breakdown'].items()):
            print(f"{query_name:<30} {stats['count']:>10} {stats['avg_ms']:>12.2f} {stats['errors']:>10}")
        
        print("="*70)
        
        # Show recent error messages if any
        if self.error_messages:
            print("\n⚠️  Recent Error Messages:")
            print("-"*70)
            for error_msg in self.error_messages[-10:]:  # Show last 10 unique errors
                print(f"   {error_msg}")
            if len(self.error_messages) > 10:
                print(f"   ... and {len(self.error_messages) - 10} more unique error(s)")
            print("-"*70)


# ============================================================================
# Main Test Orchestrator
# ============================================================================

class AnalyticsLoadTest:
    """Orchestrates the analytics load test."""
    
    def __init__(self, config: TestConfig):
        self.config = config
        self.workers: List[mp.Process] = []
        self.stop_event = mp.Event()
        self.stats_queue = mp.Queue()
        self.stats_collector = StatsCollector()
    
    def start_workers(self, num_workers: int):
        """Start worker processes."""
        for i in range(num_workers):
            worker_id = len(self.workers) + 1
            p = mp.Process(
                target=worker_process,
                args=(worker_id, self.config, self.stop_event, self.stats_queue)
            )
            p.start()
            self.workers.append(p)
            time.sleep(0.1)  # Brief stagger for cleaner startup
    
    def stop_workers(self):
        """Stop all worker processes."""
        self.stop_event.set()
        for p in self.workers:
            p.join(timeout=5)
            if p.is_alive():
                p.terminate()
        self.workers.clear()
    
    def collect_stats(self):
        """Collect statistics from workers."""
        while not self.stats_queue.empty():
            try:
                stat = self.stats_queue.get_nowait()
                self.stats_collector.process_stat(stat)
            except:
                break
    
    def run_steady_state(self):
        """Run test with steady number of connections."""
        print(f"\n🚀 Starting analytics load test")
        print(f"   Server: {self.config.server}")
        print(f"   Database: {self.config.database}")
        print(f"   Connections: {self.config.connections}")
        print(f"   Duration: {self.config.duration_seconds}s")
        print(f"   Think time: {self.config.think_time_ms}ms")
        print(f"   Branch ID range: {self.config.branch_id_min}-{self.config.branch_id_max}")
        print(f"\n📊 Query Mix:")
        for query_name, weight in self.config.query_mix.items():
            desc = ANALYTICS_QUERIES[query_name]["description"]
            print(f"   {query_name:<30} {weight*100:>5.1f}%  - {desc}")
        
        self.stats_collector.start_time = time.time()
        self.start_workers(self.config.connections)
        
        # Monitor and report progress
        report_interval = 10  # seconds
        last_report = time.time()
        
        try:
            while time.time() - self.stats_collector.start_time < self.config.duration_seconds:
                time.sleep(1)
                self.collect_stats()
                
                if time.time() - last_report >= report_interval:
                    self.stats_collector.print_summary()
                    last_report = time.time()
        
        except KeyboardInterrupt:
            print("\n\n⚠️  Test interrupted by user")
        
        finally:
            print("\n🛑 Stopping workers...")
            self.stop_workers()
            time.sleep(1)
            self.collect_stats()  # Final collection
    
    def run_ramp_up(self):
        """Run test with ramping connection count."""
        print(f"\n🚀 Starting ramp-up analytics load test")
        print(f"   Server: {self.config.server}")
        print(f"   Database: {self.config.database}")
        print(f"   Starting connections: {self.config.ramp_up_step}")
        print(f"   Max connections: {self.config.max_connections}")
        print(f"   Ramp-up interval: {self.config.ramp_up_interval}s")
        print(f"   Total duration: {self.config.duration_seconds}s")
        print(f"   Branch ID range: {self.config.branch_id_min}-{self.config.branch_id_max}")
        
        self.stats_collector.start_time = time.time()
        current_connections = 0
        
        try:
            while time.time() - self.stats_collector.start_time < self.config.duration_seconds:
                # Ramp up connections
                if current_connections < self.config.max_connections:
                    new_connections = min(
                        self.config.ramp_up_step,
                        self.config.max_connections - current_connections
                    )
                    print(f"\n📈 Adding {new_connections} connections (total: {current_connections + new_connections})")
                    self.start_workers(new_connections)
                    current_connections += new_connections
                
                # Run for interval
                interval_start = time.time()
                while time.time() - interval_start < self.config.ramp_up_interval:
                    time.sleep(2)
                    self.collect_stats()
                
                self.stats_collector.print_summary()
        
        except KeyboardInterrupt:
            print("\n\n⚠️  Test interrupted by user")
        
        finally:
            print("\n🛑 Stopping all workers...")
            self.stop_workers()
            time.sleep(1)
            self.collect_stats()
    
    def run(self):
        """Run the appropriate test mode."""
        if self.config.ramp_up:
            self.run_ramp_up()
        else:
            self.run_steady_state()
        
        # Final report
        print("\n\n")
        print("="*70)
        print(" FINAL RESULTS")
        print("="*70)
        self.stats_collector.print_summary()
        
        summary = self.stats_collector.get_summary()
        print(f"\n✅ Test completed successfully")
        print(f"   Total queries executed: {summary['total_queries']}")
        print(f"   Average QPS: {summary['queries_per_second']}")
        print(f"   Error rate: {summary['error_rate']}%")


# ============================================================================
# Database Initialization
# ============================================================================

def test_connection(server: str, database: str, verbose: bool = False) -> bool:
    """Test database connection before starting workers."""
    try:
        if verbose:
            print(f"🔐 Testing connection to {server}...")
        
        conn_str = (
            f"Server={server};"
            f"Database={database};"
            f"Authentication=ActiveDirectoryDefault;"
            f"Encrypt=yes;"
        )
        conn = mssql_python.connect(conn_str, timeout=30)
        cursor = conn.cursor()
        cursor.execute("SELECT 1 AS Test")
        cursor.fetchall()
        cursor.close()
        conn.close()
        
        if verbose:
            print(f"✅ Connection successful")
        return True
            
    except Exception as e:
        print(f"⚠️  Connection failed: {e}")
        return False


def get_branch_id_range(server: str, database: str, verbose: bool = False) -> tuple:
    """Query database for actual branch ID range."""
    try:
        if verbose:
            print(f"🔍 Querying branch ID range from {database}...")
        
        conn_str = (
            f"Server={server};"
            f"Database={database};"
            f"Authentication=ActiveDirectoryDefault;"
            f"Encrypt=yes;"
        )
        conn = mssql_python.connect(conn_str, timeout=30)
        cursor = conn.cursor()
        
        cursor.execute("SELECT MIN(BranchId) AS MinId, MAX(BranchId) AS MaxId FROM dbo.Branches")
        row = cursor.fetchone()
        
        cursor.close()
        conn.close()
        
        if row and row[0] is not None and row[1] is not None:
            min_id = int(row[0])
            max_id = int(row[1])
            
            if verbose:
                print(f"✅ Branch ID range: {min_id} to {max_id}")
            
            return (min_id, max_id)
        else:
            if verbose:
                print(f"⚠️  No branches found in database")
                print(f"   Using default range: 1-500")
            return (1, 500)
            
    except Exception as e:
        if verbose:
            print(f"⚠️  Error querying branch range: {e}")
            print(f"   Using default range: 1-500")
        return (1, 500)


# ============================================================================
# CLI Entry Point
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Analytics Load Simulator for Hyperscale Named Replica",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Steady state test with 10 connections for 5 minutes
  python analytics_load_test.py --connections 10 --duration 300

  # Ramp-up test from 0 to 100 connections
  python analytics_load_test.py --ramp-up --max-connections 100 --duration 600

  # Custom server and minimal think time
  python analytics_load_test.py -s myserver.database.windows.net -d mydb -c 25 -t 50

Query Mix (default balanced):
  Branch Manager queries: 28% (GetBranchAnalytics, GetBranchLeaderboard)
  Executive queries: 27% (GetExecutiveKPIs, GetTopBranches, GetFilingStatusDistribution)
  Filing Detail Analytics: 31% (Overview, EFile, W2, 1099, CapGains, SchedC, State)
  Trend analysis: 7% (GetReturnsByYear)
  System monitoring: 7% (GetHyperscaleResourceStats)
        """
    )
    
    # Connection parameters
    parser.add_argument("-s", "--server",
                        default=os.getenv("SQL_SERVER", "localhost"),
                        help="SQL Server hostname (default: SQL_SERVER env var or localhost)")
    parser.add_argument("-d", "--database",
                        default=os.getenv("SQL_DATABASE", "zavatax"),
                        help="Database name (default: SQL_DATABASE env var or zavatax)")
    
    # Load parameters
    parser.add_argument("-c", "--connections",
                        type=int,
                        default=10,
                        help="Number of parallel connections (default: 10)")
    parser.add_argument("--duration",
                        type=int,
                        default=300,
                        help="Test duration in seconds (default: 300)")
    parser.add_argument("-t", "--think-time",
                        type=int,
                        default=100,
                        help="Think time between queries in milliseconds (default: 100)")
    
    # Ramp-up parameters
    parser.add_argument("--ramp-up",
                        action="store_true",
                        help="Enable ramp-up mode (gradually increase connections)")
    parser.add_argument("--max-connections",
                        type=int,
                        default=100,
                        help="Max connections for ramp-up mode (default: 100)")
    parser.add_argument("--ramp-up-step",
                        type=int,
                        default=10,
                        help="Connections to add per interval (default: 10)")
    parser.add_argument("--ramp-up-interval",
                        type=int,
                        default=30,
                        help="Seconds between ramp-up steps (default: 30)")
    
    # Query mix customization
    parser.add_argument("--executive-heavy",
                        action="store_true",
                        help="Executive-heavy query mix (70%% executive, 30%% branch)")
    parser.add_argument("--branch-heavy",
                        action="store_true",
                        help="Branch-heavy query mix (70%% branch, 30%% executive)")
    
    # Other options
    parser.add_argument("-v", "--verbose",
                        action="store_true",
                        help="Verbose output")
    
    args = parser.parse_args()
    
    # Build query mix
    if args.executive_heavy:
        query_mix = {
            "GetExecutiveKPIs": 0.22,
            "GetTopBranches": 0.12,
            "GetFilingStatusDistribution": 0.04,
            "GetBranchAnalytics": 0.08,
            "GetBranchLeaderboard": 0.04,
            "GetReturnsByYear": 0.04,
            "GetFilingDetailOverview": 0.05,
            "GetEFileStatusSummary": 0.05,
            "GetW2Summary": 0.05,
            "GetForm1099Summary": 0.04,
            "GetCapitalGainsSummary": 0.04,
            "GetScheduleCSummary": 0.03,
            "GetStateTaxSummary": 0.02,
            "GetScheduleESummary": 0.03,
            "GetScheduleBSummary": 0.03,
            "GetDocumentSummary": 0.02,
            "GetHyperscaleResourceStats": 0.10,
        }
    elif args.branch_heavy:
        query_mix = {
            "GetBranchAnalytics": 0.26,
            "GetBranchLeaderboard": 0.17,
            "GetExecutiveKPIs": 0.08,
            "GetTopBranches": 0.04,
            "GetReturnsByYear": 0.04,
            "GetFilingStatusDistribution": 0.04,
            "GetFilingDetailOverview": 0.04,
            "GetEFileStatusSummary": 0.04,
            "GetW2Summary": 0.04,
            "GetForm1099Summary": 0.03,
            "GetCapitalGainsSummary": 0.03,
            "GetScheduleCSummary": 0.03,
            "GetStateTaxSummary": 0.02,
            "GetScheduleESummary": 0.03,
            "GetScheduleBSummary": 0.03,
            "GetDocumentSummary": 0.02,
            "GetHyperscaleResourceStats": 0.06,
        }
    else:
        # Default balanced mix
        query_mix = {
            "GetBranchAnalytics": 0.16,
            "GetBranchLeaderboard": 0.09,
            "GetExecutiveKPIs": 0.13,
            "GetTopBranches": 0.09,
            "GetFilingStatusDistribution": 0.03,
            "GetReturnsByYear": 0.06,
            "GetHyperscaleResourceStats": 0.07,
            "GetFilingDetailOverview": 0.05,
            "GetEFileStatusSummary": 0.05,
            "GetW2Summary": 0.04,
            "GetForm1099Summary": 0.04,
            "GetCapitalGainsSummary": 0.04,
            "GetScheduleCSummary": 0.03,
            "GetStateTaxSummary": 0.03,
            "GetScheduleESummary": 0.03,
            "GetScheduleBSummary": 0.03,
            "GetDocumentSummary": 0.03,
        }
    
    config = TestConfig(
        server=args.server,
        database=args.database,
        connections=args.connections,
        duration_seconds=args.duration,
        query_mix=query_mix,
        ramp_up=args.ramp_up,
        max_connections=args.max_connections,
        ramp_up_step=args.ramp_up_step,
        ramp_up_interval=args.ramp_up_interval,
        think_time_ms=args.think_time,
        verbose=args.verbose
    )
    
    # Test database connection
    if not test_connection(config.server, config.database, config.verbose):
        print("❌ Failed to connect to database")
        print("   Make sure you have:")
        print("   1. Installed mssql-python: pip install mssql-python")
        print("   2. Logged in to Azure: az login")
        print("   3. Network access to the SQL server")
        sys.exit(1)
    
    # Query database for branch ID range
    branch_id_min, branch_id_max = get_branch_id_range(config.server, config.database, config.verbose)
    config.branch_id_min = branch_id_min
    config.branch_id_max = branch_id_max
    
    # Run test
    test = AnalyticsLoadTest(config)
    test.run()


if __name__ == "__main__":
    # Ensure multiprocessing works properly on Windows
    mp.freeze_support()
    main()
