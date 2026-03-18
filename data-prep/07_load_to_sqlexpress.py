"""
Load generated CSV data to SQL Express local instance.
Uses the new Microsoft mssql-python driver (no ODBC required).

IRS CONTENT NOTICE: Knowledge-base data originates from IRS publications —
U.S. Government Works (17 U.S.C. § 105), freely usable per
https://www.irs.gov/about-irs/use-of-content-from-irsgov.
Neither this application nor Microsoft is affiliated with or endorsed by the IRS.

Usage:
    pip install mssql-python
    python 07_load_to_sqlexpress.py
"""

import csv
import json
import concurrent.futures
import time
from pathlib import Path
from tqdm import tqdm

try:
    import mssql_python
except ImportError:
    print("❌ mssql-python not installed. Install with: pip install mssql-python")
    exit(1)

# Configuration
DATA_DIR = Path(__file__).parent / "data" / "output"
# mssql-python uses semicolon-delimited connection string format
CONN_STRING = "SERVER=.\\SQLEXPRESS;DATABASE=ZavaTax;Trusted_Connection=yes;TrustServerCertificate=yes;Encrypt=no;"


def get_connection():
    """Create database connection using mssql-python."""
    return mssql_python.connect(CONN_STRING)


def clear_tables(conn):
    """Clear existing data in correct order (respect FK constraints).
    
    Note: Vector indexes must be dropped before calling this function.
    """
    cursor = conn.cursor()
    print("🗑️  Clearing existing data...")
    
    # Disable FK checks temporarily for TRUNCATE
    try:
        # Use TRUNCATE for faster clearing (resets identity too)
        # But TRUNCATE doesn't work with FK constraints, so we need to be careful
        
        # Clear in reverse dependency order using DELETE
        tables = ['TaxReturns', 'TaxScenarios', 'TaxKnowledgeBase', 'Customers', 'TaxProfessionals', 'Branches']
        for table in tables:
            try:
                # Try TRUNCATE first (faster, resets identity)
                cursor.execute(f"TRUNCATE TABLE {table}")
                conn.commit()
                print(f"   Truncated {table}")
            except Exception:
                # Fall back to DELETE if TRUNCATE fails (FK constraints)
                try:
                    cursor.execute(f"DELETE FROM {table}")
                    conn.commit()
                    print(f"   Cleared {table}")
                except Exception as e:
                    print(f"   Skipping {table}: {e}")
    except Exception as e:
        print(f"   Error clearing tables: {e}")


def load_branches(conn):
    """Load branches.csv."""
    csv_path = DATA_DIR / "branches.csv"
    if not csv_path.exists():
        print(f"   ⚠️ {csv_path} not found")
        return 0
    
    cursor = conn.cursor()
    
    # Check if data already exists
    cursor.execute("SELECT COUNT(*) FROM Branches")
    existing = cursor.fetchone()[0]
    if existing > 0:
        print(f"   ⚠️ Branches already has {existing} rows, skipping")
        return existing
    
    # Enable identity insert
    cursor.execute("SET IDENTITY_INSERT Branches ON")
    conn.commit()
    
    count = 0
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in tqdm(reader, desc="   Branches"):
            cursor.execute("""
                INSERT INTO Branches (BranchId, BranchName, Address, City, State, StateAbbr, ZipCode, Phone, ManagerName)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, 
                int(row['branch_id']),
                row['branch_name'],
                row['address'],
                row['city'],
                row['state'],
                row.get('state_abbr', '')[:2],
                row['zip_code'],
                row['phone'] or None,
                row['manager_name']
            )
            count += 1
    
    cursor.execute("SET IDENTITY_INSERT Branches OFF")
    conn.commit()
    return count


def load_single_customer_file(filepath):
    """Worker to load a single customers file."""
    conn = None
    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SET IDENTITY_INSERT Customers ON")
        conn.commit()
        
        count = 0
        batch_size = 1000
        batch = []
        
        with open(filepath, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            
            for row in reader:
                is_active = 1 if row.get('is_active', 'True') in (True, 'True', 'true', '1') else 0
                val = (
                    int(row['customer_id']),
                    row['first_name'],
                    row['last_name'],
                    row['email'],
                    row.get('phone') or None,
                    row.get('address', ''),
                    row['city'],
                    row['state'],
                    row.get('state_abbr', '')[:2],
                    row['zip_code'],
                    row.get('date_of_birth') or None,
                    str(row.get('ssn_last_four', ''))[:4] or None,
                    row.get('created_date') or None,
                    row.get('preferred_language', 'English'),
                    row.get('preferred_contact', 'Email'),
                    is_active
                )
                batch.append(val)
                
                if len(batch) >= batch_size:
                    cursor.executemany("""
                        INSERT INTO Customers (
                            CustomerId, FirstName, LastName, Email, Phone, Address,
                            City, State, StateAbbr, ZipCode, DateOfBirth,
                            SSNLastFour, CreatedDate, PreferredLanguage, PreferredContact, IsActive
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, batch)
                    conn.commit()
                    count += len(batch)
                    batch = []

            if batch:
                cursor.executemany("""
                    INSERT INTO Customers (
                        CustomerId, FirstName, LastName, Email, Phone, Address,
                        City, State, StateAbbr, ZipCode, DateOfBirth,
                        SSNLastFour, CreatedDate, PreferredLanguage, PreferredContact, IsActive
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, batch)
                conn.commit()
                count += len(batch)

        cursor.execute("SET IDENTITY_INSERT Customers OFF")
        conn.commit()
        return count
    except Exception as e:
        print(f"      ❌ Error processing {filepath.name}: {e}")
        return 0
    finally:
        if conn:
            conn.close()


def load_customers(conn):
    """Load customers data from potentially multiple chunk files."""
    cursor = conn.cursor()
    
    # Check if data already exists
    cursor.execute("SELECT COUNT(*) FROM Customers")
    existing = cursor.fetchone()[0]
    if existing > 0:
        print(f"   ⚠️ Customers already has {existing} rows, skipping")
        return existing

    # Find files
    files = list(DATA_DIR.glob("customers_part_*.csv"))
    if not files:
        f = DATA_DIR / "customers.csv"
        if f.exists():
            files = [f]
    
    if not files:
        print(f"   ⚠️ No customers files found in {DATA_DIR}")
        return 0

    print(f"   Found {len(files)} customer files. Loading in parallel...")
    
    total_rows = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        futures = {executor.submit(load_single_customer_file, f): f for f in files}
        for future in tqdm(concurrent.futures.as_completed(futures), total=len(files), desc="   Loading Customers"):
            try:
                total_rows += future.result()
            except Exception as e:
                print(f"      Worker failed: {e}")
                
    return total_rows


def load_professionals(conn):
    """Load tax_professionals.csv."""
    csv_path = DATA_DIR / "tax_professionals.csv"
    if not csv_path.exists():
        print(f"   ⚠️ {csv_path} not found")
        return 0
    
    cursor = conn.cursor()
    
    # Check if data already exists
    cursor.execute("SELECT COUNT(*) FROM TaxProfessionals")
    existing = cursor.fetchone()[0]
    if existing > 0:
        print(f"   ⚠️ TaxProfessionals already has {existing} rows, skipping")
        return existing
    
    cursor.execute("SET IDENTITY_INSERT TaxProfessionals ON")
    conn.commit()
    
    count = 0
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in tqdm(reader, desc="   Professionals"):
            cursor.execute("""
                INSERT INTO TaxProfessionals (
                    ProfessionalId, BranchId, FirstName, LastName, Email, Phone,
                    HireDate, Certification, YearsExperience, IsActive,
                    HourlyRate, AvgReturnsPerDay
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
                int(row['professional_id']),
                int(row['branch_id']),
                row['first_name'],
                row['last_name'],
                row['email'],
                row.get('phone') or None,
                row.get('hire_date') or None,
                row.get('certification', ''),
                int(row['years_experience']) if row.get('years_experience') else None,
                1 if row.get('is_active', 'True') in (True, 'True', 'true', '1') else 0,
                float(row['hourly_rate']) if row.get('hourly_rate') else None,
                float(row['avg_returns_per_day']) if row.get('avg_returns_per_day') else None
            )
            count += 1
    
    cursor.execute("SET IDENTITY_INSERT TaxProfessionals OFF")
    conn.commit()
    return count


def load_single_tax_return_file(filepath):
    """Worker to load a single tax returns file."""
    conn = None
    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SET IDENTITY_INSERT TaxReturns ON")
        conn.commit()
        
        count = 0
        batch_size = 1000
        batch = []
        
        with open(filepath, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            
            for row in reader:
                val = (
                    int(row['return_id']),
                    int(row['customer_id']),
                    int(row['branch_id']),
                    int(row['professional_id']),
                    int(row['tax_year']),
                    row.get('filing_date') or None,
                    row['filing_status'],
                    int(row['gross_income']) if row.get('gross_income') else None,
                    int(row['adjusted_gross_income']) if row.get('adjusted_gross_income') else None,
                    int(row['total_deductions']) if row.get('total_deductions') else None,
                    int(row['taxable_income']) if row.get('taxable_income') else None,
                    int(row['tax_liability']) if row.get('tax_liability') else None,
                    int(row['total_withholding']) if row.get('total_withholding') else None,
                    int(row['refund_amount']) if row.get('refund_amount') else 0,
                    int(row['amount_owed']) if row.get('amount_owed') else 0,
                    row.get('status', 'Filed'),
                    1 if row.get('is_itemized') in (True, 'True', 'true', '1') else 0,
                    int(row['num_dependents']) if row.get('num_dependents') else 0,
                    int(row['processing_time_minutes']) if row.get('processing_time_minutes') else None,
                    int(row['document_count']) if row.get('document_count') else None,
                    int(row['ai_assistance_count']) if row.get('ai_assistance_count') else 0,
                    1 if row.get('is_amended') in (True, 'True', 'true', '1') else 0,
                    1 if row.get('is_extension') in (True, 'True', 'true', '1') else 0,
                    1 if row.get('has_foreign_accounts') in (True, 'True', 'true', '1') else 0,
                    int(row['foreign_account_max_value']) if row.get('foreign_account_max_value') else 0,
                    1 if row.get('has_pfic') in (True, 'True', 'true', '1') else 0,
                    int(row['pfic_value']) if row.get('pfic_value') else 0,
                    int(row['pfic_income']) if row.get('pfic_income') else 0,
                    1 if row.get('has_foreign_trust') in (True, 'True', 'true', '1') else 0,
                    int(row['foreign_trust_value']) if row.get('foreign_trust_value') else 0,
                    1 if row.get('has_foreign_corporation') in (True, 'True', 'true', '1') else 0,
                    int(row['foreign_corp_ownership_pct']) if row.get('foreign_corp_ownership_pct') else 0,
                    1 if row.get('has_foreign_partnership') in (True, 'True', 'true', '1') else 0,
                    int(row['foreign_gifts_received']) if row.get('foreign_gifts_received') else 0,
                    int(row['foreign_taxes_paid']) if row.get('foreign_taxes_paid') else 0
                )
                batch.append(val)
                
                if len(batch) >= batch_size:
                    cursor.executemany("""
                        INSERT INTO TaxReturns (
                            ReturnId, CustomerId, BranchId, ProfessionalId, TaxYear,
                            FilingDate, FilingStatus,
                            GrossIncome, AdjustedGrossIncome, TotalDeductions,
                            TaxableIncome, TaxLiability, TotalWithheld,
                            RefundAmount, AmountOwed, Status,
                            IsItemized, NumDependents,
                            ProcessingTimeMinutes, DocumentCount, AIAssistanceCount,
                            IsAmended, IsExtension,
                            HasForeignAccounts, ForeignAccountMaxValue,
                            HasPFIC, PFICValue, PFICIncome,
                            HasForeignTrust, ForeignTrustValue,
                            HasForeignCorporation, ForeignCorpOwnershipPct,
                            HasForeignPartnership, ForeignGiftsReceived, ForeignTaxesPaid
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, batch)
                    conn.commit()
                    count += len(batch)
                    batch = []

            if batch:
                cursor.executemany("""
                    INSERT INTO TaxReturns (
                        ReturnId, CustomerId, BranchId, ProfessionalId, TaxYear,
                        FilingDate, FilingStatus,
                        GrossIncome, AdjustedGrossIncome, TotalDeductions,
                        TaxableIncome, TaxLiability, TotalWithheld,
                        RefundAmount, AmountOwed, Status,
                        IsItemized, NumDependents,
                        ProcessingTimeMinutes, DocumentCount, AIAssistanceCount,
                        IsAmended, IsExtension,
                        HasForeignAccounts, ForeignAccountMaxValue,
                        HasPFIC, PFICValue, PFICIncome,
                        HasForeignTrust, ForeignTrustValue,
                        HasForeignCorporation, ForeignCorpOwnershipPct,
                        HasForeignPartnership, ForeignGiftsReceived, ForeignTaxesPaid
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, batch)
                conn.commit()
                count += len(batch)

        cursor.execute("SET IDENTITY_INSERT TaxReturns OFF")
        conn.commit()
        return count
    except Exception as e:
        print(f"      ❌ Error processing {filepath.name}: {e}")
        return 0
    finally:
        if conn:
            conn.close()


def load_tax_returns(conn, limit=10000):
    """Load tax_returns data from potentially multiple chunk files."""
    cursor = conn.cursor()
    
    # Check if data already exists
    cursor.execute("SELECT COUNT(*) FROM TaxReturns")
    existing = cursor.fetchone()[0]
    if existing > 0:
        print(f"   ⚠️ TaxReturns already has {existing} rows, skipping")
        return existing

    # Find files
    files = list(DATA_DIR.glob("tax_returns_part_*.csv"))
    if not files:
        f = DATA_DIR / "tax_returns.csv"
        if f.exists():
            files = [f]
    
    if not files:
        print(f"   ⚠️ No tax_returns files found in {DATA_DIR}")
        return 0

    print(f"   Found {len(files)} tax_returns files. Loading in parallel...")
    
    total_rows = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        futures = {executor.submit(load_single_tax_return_file, f): f for f in files}
        for future in tqdm(concurrent.futures.as_completed(futures), total=len(files), desc="   Loading TaxReturns"):
            try:
                total_rows += future.result()
            except Exception as e:
                print(f"      Worker failed: {e}")
                
    return total_rows


def load_knowledge_base(conn):
    """Load knowledge_base_embedded.json with vector embeddings."""
    json_path = DATA_DIR / "knowledge_base_embedded.json"
    if not json_path.exists():
        print(f"   ⚠️ {json_path} not found")
        return 0
    
    cursor = conn.cursor()
    
    with open(json_path, 'r', encoding='utf-8') as f:
        chunks = json.load(f)
    
    count = 0
    for chunk in tqdm(chunks, desc="   Knowledge Base"):
        try:
            embedding = chunk.get('embedding')
            embedding_str = json.dumps(embedding) if embedding else None
            
            cursor.execute("""
                INSERT INTO TaxKnowledgeBase (
                    ChunkId, PublicationId, PublicationTitle, Section, Subsection,
                    Content, TokenEstimate, SourceUrl, ChunkIndex, ContentEmbedding
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, CAST(? AS VECTOR(1536)))
            """,
                chunk.get('chunk_id', f"chunk_{count}"),
                chunk.get('publication_id', ''),
                chunk.get('publication_title', ''),
                chunk.get('section', ''),
                chunk.get('subsection', ''),
                chunk.get('content', ''),
                chunk.get('token_estimate', 0),
                chunk.get('source_url', ''),
                chunk.get('chunk_index', count),
                embedding_str
            )
            count += 1
            
            if count % 100 == 0:
                conn.commit()
                
        except Exception as e:
            tqdm.write(f"\n   Error on chunk {count}: {e}")
            continue
    
    conn.commit()
    return count


def load_scenarios(conn):
    """Load tax_scenarios_embedded.json with vector embeddings."""
    json_path = DATA_DIR / "tax_scenarios_embedded.json"
    if not json_path.exists():
        print(f"   ⚠️ {json_path} not found")
        return 0
    
    cursor = conn.cursor()
    
    # Check if data already exists
    cursor.execute("SELECT COUNT(*) FROM TaxScenarios")
    existing = cursor.fetchone()[0]
    if existing > 0:
        print(f"   ⚠️ TaxScenarios already has {existing} rows, skipping")
        return existing
    
    cursor = conn.cursor()
    
    with open(json_path, 'r', encoding='utf-8') as f:
        scenarios = json.load(f)
    
    count = 0
    for scenario in tqdm(scenarios, desc="   Tax Scenarios"):
        try:
            embedding = scenario.get('embedding')
            embedding_str = json.dumps(embedding) if embedding else None
            
            cursor.execute("""
                INSERT INTO TaxScenarios (
                    ScenarioId, TaxYear, ScenarioType, TaxpayerProfile,
                    IncomeSources, Deductions, Credits, SpecialSituations,
                    ScenarioSummary, ScenarioEmbedding
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, CAST(? AS VECTOR(1536)))
            """,
                scenario.get('scenario_id', f"scenario_{count}"),
                scenario.get('tax_year', 2025),
                scenario.get('scenario_type', ''),
                json.dumps(scenario.get('taxpayer_profile', {})),
                json.dumps(scenario.get('income_sources', {})),
                json.dumps(scenario.get('deductions', {})),
                json.dumps(scenario.get('credits', {})),
                json.dumps(scenario.get('special_situations', [])),
                scenario.get('summary', ''),
                embedding_str
            )
            count += 1
            
            if count % 100 == 0:
                conn.commit()
                
        except Exception as e:
            tqdm.write(f"\n   Error on scenario {count}: {e}")
            continue
    
    conn.commit()
    return count


def drop_vector_indexes(conn):
    """Drop vector indexes to allow data modification."""
    cursor = conn.cursor()
    print("📉 Dropping vector indexes...")
    
    # Query for actual vector index names on our tables
    tables_to_check = ['TaxKnowledgeBase', 'TaxScenarios']
    
    for table in tables_to_check:
        try:
            # Find all indexes on this table (vector indexes are type 9 in some versions)
            # But safer to just drop all non-PK indexes on vector columns
            cursor.execute(f"""
                SELECT i.name 
                FROM sys.indexes i
                JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
                JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
                WHERE i.object_id = OBJECT_ID('{table}')
                AND i.is_primary_key = 0
                AND c.name LIKE '%Embedding%'
            """)
            rows = cursor.fetchall()
            
            for row in rows:
                index_name = row[0]
                try:
                    cursor.execute(f"DROP INDEX [{index_name}] ON [{table}]")
                    conn.commit()
                    print(f"   Dropped {index_name} on {table}")
                except Exception as e:
                    print(f"   Failed to drop {index_name}: {e}")
            
            if not rows:
                # Try dropping by common name pattern anyway
                for suffix in ['_Vector', '_VectorIndex', '']:
                    try:
                        idx_name = f"IX_{table}{suffix}"
                        cursor.execute(f"DROP INDEX IF EXISTS [{idx_name}] ON [{table}]")
                        conn.commit()
                    except:
                        pass
                print(f"   No vector indexes found on {table}")
                
        except Exception as e:
            print(f"   Error checking {table}: {e}")

def run_db_task(task_name, table_name, func, *args, **kwargs):
    """Helper to run a load task in its own connection."""
    conn = None
    try:
        conn = get_connection()
        print(f"   🚀 Starting {task_name}...")
        count = func(conn, *args, **kwargs)
        
        print(f"   📊 Updating statistics for {table_name}...")
        cursor = conn.cursor()
        cursor.execute(f"UPDATE STATISTICS {table_name}")
        conn.commit()
        
        return f"✅ {task_name} completed: {count} rows"
    except Exception as e:
        print(f"   ❌ {task_name} failed: {e}")
        raise e
    finally:
        if conn:
            conn.close()

def create_vector_indexes(conn):
    """Create vector indexes after data is loaded.
    
    Note: CREATE VECTOR INDEX cannot be inside a transaction,
    so we need to use autocommit mode.
    """
    print("📈 Creating vector indexes...")
    
    indexes = [
        ('TaxKnowledgeBase', 'IX_TaxKnowledgeBase_Vector', 'ContentEmbedding'),
        ('TaxScenarios', 'IX_TaxScenarios_Vector', 'ScenarioEmbedding')
    ]
    
    # Create a new connection with autocommit=True for DDL operations
    autocommit_conn = mssql_python.connect(CONN_STRING, autocommit=True)
    cursor = autocommit_conn.cursor()
    
    for table, index_name, vector_col in indexes:
        try:
            # Check row count - need data for vector index
            cursor.execute(f"SELECT COUNT(*) FROM {table}")
            row_count = cursor.fetchone()[0]
            
            if row_count == 0:
                print(f"   Skipping {index_name} - {table} is empty")
                continue
            
            # Drop if exists first
            try:
                cursor.execute(f"DROP INDEX IF EXISTS [{index_name}] ON [{table}]")
            except:
                pass
            
            # Create the index
            cursor.execute(f"""
                CREATE VECTOR INDEX {index_name} ON {table}({vector_col})
                WITH (METRIC = 'cosine', TYPE = 'DISKANN')
            """)
            print(f"   Created {index_name} on {table} ({row_count} rows)")
            
        except Exception as e:
            print(f"   {index_name}: {e}")
    
    autocommit_conn.close()


def main():
    print("\n" + "="*60)
    print("📦 Loading Data to SQL Express (using mssql-python)")
    print("="*60)
    
    try:
        conn = get_connection()
        print("✅ Connected to SQL Express")
    except Exception as e:
        print(f"❌ Connection failed: {e}")
        print("\nMake sure:")
        print("  1. SQL Express is running")
        print("  2. ZavaTax database exists (run local_dev_setup.sql first)")
        print("  3. mssql-python is installed: pip install mssql-python")
        return
    
    start_time = time.time()

    # Drop vector indexes first (required for DML operations in SQL Server 2025)
    drop_vector_indexes(conn)
    
    # Clear existing data
    clear_tables(conn)
    conn.close() # Close main connection before starting threads
    
    print("\n📥 Starting Parallel Data Load...")
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
        # Batch 1: Independent tables
        print("   🚀 Batch 1: Loading independent tables...")
        futures1 = {
            executor.submit(run_db_task, "Branches Load", "Branches", load_branches): "Branches",
            executor.submit(run_db_task, "Customers Load", "Customers", load_customers): "Customers",
            executor.submit(run_db_task, "KnowledgeBase Load", "TaxKnowledgeBase", load_knowledge_base): "TaxKnowledgeBase",
            executor.submit(run_db_task, "Scenarios Load", "TaxScenarios", load_scenarios): "TaxScenarios"
        }
        for future in concurrent.futures.as_completed(futures1):
            try:
                print(f"   {future.result()}")
            except Exception:
                pass # Error printed in run_db_task

        # Batch 2: Professionals (Depends on Branches)
        print("   🚀 Batch 2: Loading dependent tables (Professionals)...")
        futures2 = {
            executor.submit(run_db_task, "Professionals Load", "TaxProfessionals", load_professionals): "TaxProfessionals"
        }
        for future in concurrent.futures.as_completed(futures2):
            try:
                print(f"   {future.result()}")
            except Exception:
                pass

        # Batch 3: TaxReturns (Depends on Professionals, Customers, Branches)
        print("   🚀 Batch 3: Loading highly dependent tables (TaxReturns)...")
        futures3 = {
            executor.submit(run_db_task, "TaxReturns Load", "TaxReturns", load_tax_returns, limit=10000): "TaxReturns"
        }
        for future in concurrent.futures.as_completed(futures3):
            try:
                print(f"   {future.result()}")
            except Exception:
                pass

    # Recreate vector indexes after loading
    # Needs a new connection since main conn was closed
    conn = get_connection()
    create_vector_indexes(conn)
    conn.close()
    
    print(f"\n   ⏱️ Total load time: {time.time() - start_time:.2f} seconds")
    print("\n" + "="*60)
    print("✅ Data load complete!")
    print("="*60)


if __name__ == "__main__":
    main()
