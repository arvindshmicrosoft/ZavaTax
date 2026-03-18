"""
Load data from Azure Blob Storage to Azure SQL Database.
All data is read directly from blob storage by SQL Server - no local files needed.

IRS CONTENT NOTICE: Knowledge-base data originates from IRS publications —
U.S. Government Works (17 U.S.C. § 105), freely usable per
https://www.irs.gov/about-irs/use-of-content-from-irsgov.
Neither this application nor Microsoft is affiliated with or endorsed by the IRS.

Uses:
- BULK INSERT for CSV files
- OPENROWSET + JSON functions for JSON files with embeddings
- Managed identity for authentication - no hardcoded credentials

Prerequisites:
1. Upload CSV and JSON files to the blob storage container
2. Run this script to configure SQL external data source and load data

Usage:
    pip install mssql-python
    python 07_load_to_azure_sql.py \
        --server <your-server>.database.windows.net \
        --database zavataxdb \
        --storage-account <your-storage-account> \
        --container csvdata \
        --identity-client-id <client-id-of-user-assigned-identity>
"""

import argparse
import os
import sys
import concurrent.futures

# Add parent dir so config.py can be found when run from repo root
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from config import SQL_SERVER, SQL_DATABASE, STORAGE_ACCOUNT, STORAGE_CONTAINER, IDENTITY_CLIENT_ID
import time
import subprocess
import json
from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor

try:
    import mssql_python
except ImportError:
    print("❌ mssql-python not installed. Install with: pip install mssql-python")
    exit(1)


def get_connection(server: str, database: str):
    """Create database connection using mssql-python with Entra ID authentication.
    
    Uses ActiveDirectoryDefault which automatically tries:
    - Environment variables (AZURE_CLIENT_ID, etc.)
    - Managed Identity (in Azure)
    - Azure CLI credentials (az login)
    - Visual Studio / VS Code credentials
    """
    conn_str = (
        f"Server={server};"
        f"Database={database};"
        f"Authentication=ActiveDirectoryDefault;"
        f"Encrypt=yes;"
    )
    conn = mssql_python.connect(conn_str)
    conn.setautocommit(True)
    return conn


def setup_external_data_source(conn, storage_account: str, container: str, identity_client_id: str):
    """Configure Azure SQL to access blob storage via user-assigned managed identity."""
    cursor = conn.cursor()
    blob_endpoint = f"https://{storage_account}.blob.core.windows.net/{container}"
    
    print("🔧 Setting up external data source for blob storage...")
    print(f"   Identity Client ID: {identity_client_id[:8]}...{identity_client_id[-4:]}")
    
    # Create database master key if not exists
    try:
        cursor.execute("SELECT COUNT(*) FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##'")
        has_master_key = cursor.fetchone()[0] > 0
    except Exception:
        has_master_key = False

    if has_master_key:
        print("   ✅ Master key already exists")
    else:
        mk_password = os.environ.get('SQL_MASTER_KEY_PASSWORD')
        if not mk_password:
            raise ValueError("SQL_MASTER_KEY_PASSWORD environment variable is required (no master key exists in the database)")
        try:
            cursor.execute(
                "CREATE MASTER KEY ENCRYPTION BY PASSWORD = ?",
                (mk_password,)
            )
            print("   ✅ Master key created")
        except Exception as e:
            print(f"   ⚠️ Master key creation failed: {e}")
    
    # First drop external data source (must be dropped before credential since it references it)
    datasource_name = "AzureBlobStorage"
    credential_name = "ManagedIdentityCredential"
    
    try:
        cursor.execute(f"IF EXISTS (SELECT * FROM sys.external_data_sources WHERE name = '{datasource_name}') DROP EXTERNAL DATA SOURCE [{datasource_name}]")
        print(f"   ✅ External data source '{datasource_name}' dropped (if existed)")
    except Exception as e:
        print(f"   ⚠️ Could not drop external data source: {e}")
    
    # Now drop and recreate credential (safe now that data source is gone)
    try:
        cursor.execute(f"IF EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = '{credential_name}') DROP DATABASE SCOPED CREDENTIAL [{credential_name}]")
        cursor.execute(f"""
            CREATE DATABASE SCOPED CREDENTIAL [{credential_name}]
            WITH IDENTITY = 'Managed Identity', SECRET = '{identity_client_id}'
        """)
        print(f"   ✅ Database scoped credential '{credential_name}' created with user-assigned identity")
    except Exception as e:
        print(f"   ⚠️ Credential: {e}")
    
    # Create external data source for OPENROWSET BULK operations
    try:
        cursor.execute(f"""
            CREATE EXTERNAL DATA SOURCE [{datasource_name}]
            WITH (
                TYPE = BLOB_STORAGE,
                LOCATION = '{blob_endpoint}',
                CREDENTIAL = [{credential_name}]
            )
        """)
        print(f"   ✅ External data source '{datasource_name}' created: {blob_endpoint}")
    except Exception as e:
        print(f"   ⚠️ External data source: {e}")
    
    return datasource_name


def load_branches(conn, datasource: str):
    """Load branches.csv from blob storage using OPENROWSET SINGLE_CLOB + line parsing.
    
    Uses the same OPENROWSET pattern as JSON loading, but parses CSV lines.
    CSV columns: branch_id,branch_name,address,city,state,zip_code,phone,manager_name
    """
    cursor = conn.cursor()
    
    cursor.execute("SELECT COUNT(*) FROM Branches")
    existing_count = cursor.fetchone()[0]
    if existing_count > 0:
        print(f"   ⏭️ Branches: {existing_count:,} rows already exist, skipping")
        return
    
    print("   Loading Branches from branches.csv...")
    
    # Read CSV as single blob, split into lines, parse each line using STRING_SPLIT with ordinal
    # The enable_ordinal=1 feature requires SQL Server 2022+ / Azure SQL
    try:
        # Enable IDENTITY_INSERT to allow explicit ID values from CSV
        cursor.execute("SET IDENTITY_INSERT Branches ON")
        cursor.execute(f"""
            WITH csv_lines AS (
                SELECT 
                    lines.value AS line,
                    lines.ordinal AS line_num
                FROM OPENROWSET(
                    BULK 'branches.csv',
                    DATA_SOURCE = '{datasource}',
                    SINGLE_CLOB
                ) AS raw
                CROSS APPLY STRING_SPLIT(REPLACE(raw.BulkColumn, CHAR(13), ''), CHAR(10), 1) AS lines
                WHERE lines.ordinal > 1  -- Skip header
                  AND LEN(TRIM(lines.value)) > 0
            ),
            parsed AS (
                SELECT 
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 1) AS branch_id,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 2) AS branch_name,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 3) AS address,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 4) AS city,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 5) AS state,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 6) AS zip_code,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 7) AS phone,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 8) AS manager_name
                FROM csv_lines
            )
            INSERT INTO Branches (BranchId, BranchName, Address, City, State, StateAbbr, ZipCode, Phone, ManagerName)
            SELECT 
                TRY_CAST(branch_id AS INT),
                branch_name,
                address,
                city,
                state,
                LEFT(state, 2),
                zip_code,
                phone,
                manager_name
            FROM parsed
            WHERE TRY_CAST(branch_id AS INT) IS NOT NULL
        """)
        cursor.execute("SET IDENTITY_INSERT Branches OFF")
        cursor.execute("UPDATE STATISTICS Branches")
        cursor.execute("SELECT COUNT(*) FROM Branches")
        print(f"   ✅ Branches: {cursor.fetchone()[0]} rows")
    except Exception as e:
        try:
            cursor.execute("SET IDENTITY_INSERT Branches OFF")
        except:
            pass
        print(f"   ❌ Branches load failed: {e}")
        raise


def load_professionals(conn, datasource: str):
    """Load tax_professionals.csv from blob storage using OPENROWSET SINGLE_CLOB + line parsing.
    
    CSV columns: professional_id,branch_id,first_name,last_name,email,phone,hire_date,certification,years_experience,hourly_rate,avg_returns_per_day
    """
    cursor = conn.cursor()
    
    cursor.execute("SELECT COUNT(*) FROM TaxProfessionals")
    existing_count = cursor.fetchone()[0]
    if existing_count > 0:
        print(f"   ⏭️ TaxProfessionals: {existing_count:,} rows already exist, skipping")
        return
    
    print("   Loading TaxProfessionals from tax_professionals.csv...")
    
    try:
        # Enable IDENTITY_INSERT to allow explicit ID values from CSV
        cursor.execute("SET IDENTITY_INSERT TaxProfessionals ON")
        cursor.execute(f"""
            WITH csv_lines AS (
                SELECT 
                    lines.value AS line,
                    lines.ordinal AS line_num
                FROM OPENROWSET(
                    BULK 'tax_professionals.csv',
                    DATA_SOURCE = '{datasource}',
                    SINGLE_CLOB
                ) AS raw
                CROSS APPLY STRING_SPLIT(REPLACE(raw.BulkColumn, CHAR(13), ''), CHAR(10), 1) AS lines
                WHERE lines.ordinal > 1
                  AND LEN(TRIM(lines.value)) > 0
            ),
            parsed AS (
                SELECT 
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 1) AS professional_id,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 2) AS branch_id,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 3) AS first_name,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 4) AS last_name,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 5) AS email,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 6) AS phone,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 7) AS hire_date,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 8) AS certification,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 9) AS years_experience,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 10) AS hourly_rate,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 11) AS avg_returns_per_day
                FROM csv_lines
            )
            INSERT INTO TaxProfessionals (ProfessionalId, BranchId, FirstName, LastName, Email, Phone, HireDate, Certification, YearsExperience, IsActive, HourlyRate, AvgReturnsPerDay)
            SELECT 
                TRY_CAST(professional_id AS INT),
                TRY_CAST(branch_id AS INT),
                first_name,
                last_name,
                email,
                phone,
                TRY_CAST(hire_date AS DATE),
                certification,
                TRY_CAST(years_experience AS INT),
                1,
                TRY_CAST(hourly_rate AS DECIMAL(8,2)),
                TRY_CAST(avg_returns_per_day AS DECIMAL(5,1))
            FROM parsed
            WHERE TRY_CAST(professional_id AS INT) IS NOT NULL
        """)
        cursor.execute("SET IDENTITY_INSERT TaxProfessionals OFF")
        cursor.execute("UPDATE STATISTICS TaxProfessionals")
        cursor.execute("SELECT COUNT(*) FROM TaxProfessionals")
        print(f"   ✅ TaxProfessionals: {cursor.fetchone()[0]} rows")
    except Exception as e:
        try:
            cursor.execute("SET IDENTITY_INSERT TaxProfessionals OFF")
        except:
            pass
        print(f"   ❌ TaxProfessionals load failed: {e}")
        raise


def discover_files(account: str, container: str, prefix: str):
    """Discover files in Azure Blob Storage matching a prefix."""
    try:
        # On Windows, 'az' is a batch file (az.cmd), so we must invoke it explicitly to avoid WinError 2
        az_cli = "az.cmd" if os.name == "nt" else "az"
        
        cmd = [
            az_cli, "storage", "blob", "list",
            "--account-name", account,
            "--container-name", container,
            "--prefix", prefix,
            "--query", "[].name",
            "-o", "json",
            "--auth-mode", "login"
        ]
        
        # Suppress stderr to avoid clutter if not logged in or other issues, unless debugging
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            # Fallback for when az cli is not ready or permissions fail
            # print(f"      Debug: Azure CLI failed: {result.stderr}")
            raise Exception("Azure CLI command failed")
            
        files = json.loads(result.stdout)
        # Filter for the specific pattern to avoid partial matches on other datasets
        matched = [f for f in files if f.startswith(prefix) and f.endswith(".csv")]
        # If sharded files exist (e.g. customers_001.csv), exclude the monolithic
        # base file (customers.csv) since shards are its partitions and overlap
        shards = [f for f in matched if f != f"{prefix}.csv"]
        return shards if shards else matched
    except Exception as e:
        print(f"   ⚠️ Autoscaling discovery failed (using default file '{prefix}.csv'): {e}")
        return [f"{prefix}.csv"]


def load_single_customer_file(server, database, datasource, filename):
    """Load a single customer CSV file (worker function)."""
    conn = None
    try:
        # Print before connecting to show concurrency (connection setup might be slow/serialized)
        print(f"      Processing {filename}...")
        
        conn = get_connection(server, database)
        cursor = conn.cursor()
        
        cursor.execute("SET IDENTITY_INSERT Customers ON")
        cursor.execute(f"""
            WITH csv_lines AS (
                SELECT 
                    lines.value AS line,
                    lines.ordinal AS line_num
                FROM OPENROWSET(
                    BULK '{filename}',
                    DATA_SOURCE = '{datasource}',
                    SINGLE_CLOB
                ) AS raw
                CROSS APPLY STRING_SPLIT(REPLACE(raw.BulkColumn, CHAR(13), ''), CHAR(10), 1) AS lines
                WHERE lines.ordinal > 1
                  AND LEN(TRIM(lines.value)) > 0
            ),
            parsed AS (
                SELECT 
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 1) AS customer_id,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 2) AS first_name,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 3) AS last_name,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 4) AS email,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 5) AS phone,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 6) AS address,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 7) AS city,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 8) AS state,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 9) AS state_abbr,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 10) AS zip_code,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 11) AS date_of_birth,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 12) AS ssn_last_four,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 13) AS created_date,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 14) AS preferred_language,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 15) AS preferred_contact,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 16) AS is_active
                FROM csv_lines
            )
            INSERT INTO Customers (CustomerId, FirstName, LastName, Email, Phone, Address, City, State, StateAbbr, ZipCode, DateOfBirth, SSNLastFour, CreatedDate, PreferredLanguage, PreferredContact, IsActive)
            SELECT 
                TRY_CAST(customer_id AS INT),
                first_name,
                last_name,
                email,
                phone,
                address,
                city,
                state,
                state_abbr,
                zip_code,
                TRY_CAST(date_of_birth AS DATE),
                ssn_last_four,
                TRY_CAST(created_date AS DATE),
                COALESCE(preferred_language, 'English'),
                COALESCE(preferred_contact, 'Email'),
                CASE WHEN is_active = 'True' THEN 1 ELSE 0 END
            FROM parsed
            WHERE TRY_CAST(customer_id AS INT) IS NOT NULL
        """)
        cursor.execute("SET IDENTITY_INSERT Customers OFF")
        conn.commit()
    except Exception as e:
        print(f"      ❌ Failed to load {filename}: {e}")
        raise e
    finally:
        if conn:
            conn.close()


def load_customers(server, database, datasource, storage_account, container):
    """Orchestrate parallel loading of customers files."""
    conn = get_connection(server, database)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM Customers")
        existing_count = cursor.fetchone()[0]
        if existing_count > 0:
            print(f"   ⏭️ Customers: {existing_count:,} rows already exist, skipping")
            return
    finally:
        conn.close()

    print("   Discovering Customers files...")
    files = discover_files(storage_account, container, "customers")
    print(f"   Found {len(files)} files for Customers. Starting parallel load...")

    # Use ProcessPoolExecutor to avoid GIL contention during SQL connection/auth
    with ProcessPoolExecutor(max_workers=16) as executor:
        futures = {executor.submit(load_single_customer_file, server, database, datasource, f): f for f in files}
        
        for future in concurrent.futures.as_completed(futures):
            filename = futures[future]
            try:
                future.result()
            except Exception:
                pass # Error logged in worker

    conn = get_connection(server, database)
    try:
        cursor = conn.cursor()
        cursor.execute("UPDATE STATISTICS Customers")
        cursor.execute("SELECT COUNT(*) FROM Customers")
        print(f"   ✅ Customers: {cursor.fetchone()[0]} rows")
    finally:
        conn.close()


def load_single_tax_return_file(server, database, datasource, filename):
    """Load a single tax_returns CSV file (worker function)."""
    conn = None
    try:
        # Print before connecting to show concurrency
        print(f"      Processing {filename}...")
        
        conn = get_connection(server, database)
        cursor = conn.cursor()
        
        cursor.execute("SET IDENTITY_INSERT TaxReturns ON")
        cursor.execute(f"""
            WITH csv_lines AS (
                SELECT lines.value AS line, lines.ordinal AS line_num
                FROM OPENROWSET(BULK '{filename}', DATA_SOURCE = '{datasource}', SINGLE_CLOB) AS raw
                CROSS APPLY STRING_SPLIT(REPLACE(raw.BulkColumn, CHAR(13), ''), CHAR(10), 1) AS lines
                WHERE lines.ordinal > 1 AND LEN(TRIM(lines.value)) > 0
            ),
            parsed AS (
                SELECT 
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 1) AS return_id,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 2) AS customer_id,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 3) AS branch_id,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 4) AS professional_id,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 5) AS tax_year,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 6) AS filing_date,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 7) AS filing_status,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 8) AS gross_income,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 9) AS adjusted_gross_income,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 10) AS total_deductions,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 11) AS taxable_income,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 12) AS tax_liability,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 13) AS total_withholding,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 14) AS refund_amount,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 15) AS amount_owed,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 16) AS status,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 17) AS is_itemized,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 18) AS num_dependents,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 19) AS processing_time_minutes,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 20) AS document_count,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 21) AS ai_assistance_count,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 22) AS is_amended,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 23) AS is_extension,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 24) AS has_foreign_accounts,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 25) AS foreign_account_max_value,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 26) AS has_pfic,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 27) AS pfic_value,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 28) AS pfic_income,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 29) AS has_foreign_trust,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 30) AS foreign_trust_value,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 31) AS has_foreign_corporation,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 32) AS foreign_corp_ownership_pct,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 33) AS has_foreign_partnership,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 34) AS foreign_gifts_received,
                    (SELECT value FROM STRING_SPLIT(line, ',', 1) WHERE ordinal = 35) AS foreign_taxes_paid
                FROM csv_lines
            )
            INSERT INTO TaxReturns (
                ReturnId, CustomerId, BranchId, ProfessionalId, TaxYear,
                FilingDate, FilingStatus, GrossIncome, AdjustedGrossIncome,
                TotalDeductions, TaxableIncome, TaxLiability, TotalWithheld,
                RefundAmount, AmountOwed, Status, IsItemized, NumDependents,
                ProcessingTimeMinutes, DocumentCount, AIAssistanceCount,
                IsAmended, IsExtension,
                HasForeignAccounts, ForeignAccountMaxValue,
                HasPFIC, PFICValue, PFICIncome,
                HasForeignTrust, ForeignTrustValue,
                HasForeignCorporation, ForeignCorpOwnershipPct,
                HasForeignPartnership, ForeignGiftsReceived, ForeignTaxesPaid
            )
            SELECT 
                CAST(return_id AS BIGINT),
                CAST(customer_id AS INT),
                CAST(branch_id AS INT),
                CAST(professional_id AS INT),
                CAST(tax_year AS INT),
                TRY_CAST(filing_date AS DATETIME2),
                filing_status,
                TRY_CAST(gross_income AS INT),
                TRY_CAST(adjusted_gross_income AS INT),
                TRY_CAST(total_deductions AS INT),
                TRY_CAST(taxable_income AS INT),
                TRY_CAST(tax_liability AS INT),
                TRY_CAST(total_withholding AS INT),
                TRY_CAST(refund_amount AS INT),
                TRY_CAST(amount_owed AS INT),
                status,
                CASE WHEN is_itemized = 'True' THEN 1 ELSE 0 END,
                TRY_CAST(num_dependents AS TINYINT),
                TRY_CAST(processing_time_minutes AS INT),
                TRY_CAST(document_count AS INT),
                TRY_CAST(COALESCE(NULLIF(ai_assistance_count, ''), '0') AS INT),
                CASE WHEN is_amended = 'True' THEN 1 ELSE 0 END,
                CASE WHEN is_extension = 'True' THEN 1 ELSE 0 END,
                CASE WHEN has_foreign_accounts = 'True' THEN 1 ELSE 0 END,
                TRY_CAST(foreign_account_max_value AS INT),
                CASE WHEN has_pfic = 'True' THEN 1 ELSE 0 END,
                TRY_CAST(pfic_value AS INT),
                TRY_CAST(pfic_income AS INT),
                CASE WHEN has_foreign_trust = 'True' THEN 1 ELSE 0 END,
                TRY_CAST(foreign_trust_value AS INT),
                CASE WHEN has_foreign_corporation = 'True' THEN 1 ELSE 0 END,
                TRY_CAST(foreign_corp_ownership_pct AS TINYINT),
                CASE WHEN has_foreign_partnership = 'True' THEN 1 ELSE 0 END,
                TRY_CAST(foreign_gifts_received AS INT),
                TRY_CAST(foreign_taxes_paid AS INT)
            FROM parsed
            WHERE TRY_CAST(return_id AS BIGINT) IS NOT NULL
        """)
        cursor.execute("SET IDENTITY_INSERT TaxReturns OFF")
        conn.commit()
    except Exception as e:
        print(f"      ❌ Failed to load {filename}: {e}")
        raise e
    finally:
        if conn:
            conn.close()


def load_tax_returns(server, database, datasource, storage_account, container):
    """Orchestrate parallel loading of tax_returns files."""
    conn = get_connection(server, database)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM TaxReturns")
        existing_count = cursor.fetchone()[0]
        if existing_count > 0:
            print(f"   ⏭️ TaxReturns: {existing_count:,} rows already exist, skipping")
            return
    finally:
        conn.close()

    print("   Discovering TaxReturns files...")
    files = discover_files(storage_account, container, "tax_returns")
    print(f"   Found {len(files)} files for TaxReturns. Starting parallel load...")

    # Use ProcessPoolExecutor to avoid GIL contention during SQL connection/auth
    with ProcessPoolExecutor(max_workers=16) as executor:
        futures = {executor.submit(load_single_tax_return_file, server, database, datasource, f): f for f in files}
        
        for future in concurrent.futures.as_completed(futures):
            filename = futures[future]
            try:
                future.result()
            except Exception:
                pass

    conn = get_connection(server, database)
    try:
        cursor = conn.cursor()
        cursor.execute("UPDATE STATISTICS TaxReturns")
        cursor.execute("SELECT COUNT(*) FROM TaxReturns")
        print(f"   ✅ TaxReturns: {cursor.fetchone()[0]} rows")
    finally:
        conn.close()


def load_knowledge_base_from_json(conn, datasource: str):
    """Load knowledge_base_embedded.json from blob storage using OPENROWSET + JSON functions."""
    cursor = conn.cursor()
    
    cursor.execute("SELECT COUNT(*) FROM TaxKnowledgeBase")
    existing_count = cursor.fetchone()[0]
    if existing_count > 0:
        print(f"   ⏭️ TaxKnowledgeBase: {existing_count:,} rows already exist, skipping")
        return
    
    print("   Loading TaxKnowledgeBase from knowledge_base_embedded.json...")
    
    # Drop ALL vector indexes (can't INSERT with vector index)
    # Query for actual index names since they may differ
    print("      Finding and dropping vector indexes...")
    try:
        cursor.execute("""
            SELECT i.name 
            FROM sys.indexes i
            JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
            JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
            WHERE i.object_id = OBJECT_ID('TaxKnowledgeBase')
            AND c.name = 'ContentEmbedding'
            AND i.name IS NOT NULL
        """)
        indexes = [row[0] for row in cursor.fetchall()]
        for idx_name in indexes:
            print(f"      Dropping index: {idx_name}")
            cursor.execute(f"DROP INDEX [{idx_name}] ON TaxKnowledgeBase")
        if indexes:
            print(f"      ✅ Dropped {len(indexes)} vector index(es)")
        else:
            print("      ✅ No vector indexes found")
    except Exception as e:
        print(f"      ⚠️ Drop index warning: {e}")
    
    # Use OPENROWSET to read JSON from blob, parse with OPENJSON, insert directly
    # NOTE: JSON_VALUE has a 4000 char limit - use OPENJSON with explicit schema for NVARCHAR(MAX) columns
    try:
        cursor.execute(f"""
            INSERT INTO TaxKnowledgeBase (
                ChunkId, PublicationId, PublicationTitle, Section, Subsection,
                Content, TokenEstimate, SourceUrl, ChunkIndex, ContentEmbedding
            )
            SELECT 
                j.chunk_id,
                j.publication_id,
                j.publication_title,
                j.section,
                j.subsection,
                j.content,
                COALESCE(j.token_estimate, 0),
                j.source_url,
                COALESCE(j.chunk_index, 0),
                CAST(j.embedding AS VECTOR(1536))
            FROM OPENROWSET(
                BULK 'knowledge_base_embedded.json',
                DATA_SOURCE = '{datasource}',
                SINGLE_NCLOB
            ) AS raw
            CROSS APPLY OPENJSON(raw.BulkColumn) WITH (
                chunk_id          NVARCHAR(200)  '$.chunk_id',
                publication_id    NVARCHAR(50)   '$.publication_id',
                publication_title NVARCHAR(500)  '$.publication_title',
                section           NVARCHAR(500)  '$.section',
                subsection        NVARCHAR(500)  '$.subsection',
                content           NVARCHAR(MAX)  '$.content',
                token_estimate    INT            '$.token_estimate',
                source_url        NVARCHAR(1000) '$.source_url',
                chunk_index       INT            '$.chunk_index',
                embedding         NVARCHAR(MAX)  '$.embedding' AS JSON
            ) AS j
        """)
        
        cursor.execute("SELECT COUNT(*) FROM TaxKnowledgeBase")
        count = cursor.fetchone()[0]
        print(f"      ✅ Inserted {count} rows")
    except Exception as e:
        print(f"      ❌ Failed: {e}")
        raise
    
    # Recreate vector index using proper VECTOR INDEX syntax
    print("      Recreating vector index...")
    try:
        cursor.execute("""
            CREATE VECTOR INDEX IX_TaxKnowledgeBase_Embedding 
            ON TaxKnowledgeBase(ContentEmbedding)
            WITH (metric = 'cosine', type = 'diskann')
        """)
        print("      ✅ Vector index created")
    except Exception as e:
        print(f"      ⚠️ Could not create vector index: {e}")
    
    cursor.execute("UPDATE STATISTICS TaxKnowledgeBase")
    cursor.execute("SELECT COUNT(*) FROM TaxKnowledgeBase")
    print(f"   ✅ TaxKnowledgeBase: {cursor.fetchone()[0]} rows")


def load_scenarios_from_json(conn, datasource: str):
    """Load tax_scenarios_embedded.json from blob storage using OPENROWSET + JSON functions."""
    cursor = conn.cursor()
    
    cursor.execute("SELECT COUNT(*) FROM TaxScenarios")
    existing_count = cursor.fetchone()[0]
    if existing_count > 0:
        print(f"   ⏭️ TaxScenarios: {existing_count:,} rows already exist, skipping")
        return
    
    print("   Loading TaxScenarios from tax_scenarios_embedded.json...")
    
    # Drop ALL vector indexes (can't INSERT with vector index)
    # Query for actual index names since they may differ
    print("      Finding and dropping vector indexes...")
    try:
        cursor.execute("""
            SELECT i.name 
            FROM sys.indexes i
            JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
            JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
            WHERE i.object_id = OBJECT_ID('TaxScenarios')
            AND c.name = 'ScenarioEmbedding'
            AND i.name IS NOT NULL
        """)
        indexes = [row[0] for row in cursor.fetchall()]
        for idx_name in indexes:
            print(f"      Dropping index: {idx_name}")
            cursor.execute(f"DROP INDEX [{idx_name}] ON TaxScenarios")
        if indexes:
            print(f"      ✅ Dropped {len(indexes)} vector index(es)")
        else:
            print("      ✅ No vector indexes found")
    except Exception as e:
        print(f"      ⚠️ Drop index warning: {e}")
    
    # Use OPENROWSET to read JSON from blob, parse with OPENJSON, insert directly
    try:
        cursor.execute(f"""
            INSERT INTO TaxScenarios (
                ScenarioId, TaxYear, ScenarioType, TaxpayerProfile,
                IncomeSources, Deductions, Credits, SpecialSituations,
                ScenarioSummary, ScenarioEmbedding
            )
            SELECT 
                JSON_VALUE(j.value, '$.scenario_id'),
                COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.tax_year') AS INT), 2025),
                JSON_VALUE(j.value, '$.scenario_type'),
                JSON_QUERY(j.value, '$.taxpayer_profile'),
                JSON_QUERY(j.value, '$.income_sources'),
                JSON_QUERY(j.value, '$.deductions'),
                JSON_QUERY(j.value, '$.credits'),
                JSON_QUERY(j.value, '$.special_situations'),
                JSON_VALUE(j.value, '$.summary'),
                CAST(JSON_QUERY(j.value, '$.embedding') AS VECTOR(1536))
            FROM OPENROWSET(
                BULK 'tax_scenarios_embedded.json',
                DATA_SOURCE = '{datasource}',
                SINGLE_NCLOB
            ) AS raw
            CROSS APPLY OPENJSON(raw.BulkColumn) AS j
        """)
        
        cursor.execute("SELECT COUNT(*) FROM TaxScenarios")
        count = cursor.fetchone()[0]
        print(f"      ✅ Inserted {count} rows")
    except Exception as e:
        print(f"      ❌ Failed: {e}")
        raise
    
    # Recreate vector index using proper VECTOR INDEX syntax
    print("      Recreating vector index...")
    try:
        cursor.execute("""
            CREATE VECTOR INDEX IX_TaxScenarios_Embedding 
            ON TaxScenarios(ScenarioEmbedding)
            WITH (metric = 'cosine', type = 'diskann')
        """)
        print("      ✅ Vector index created")
    except Exception as e:
        print(f"      ⚠️ Could not create vector index: {e}")
    
    cursor.execute("UPDATE STATISTICS TaxScenarios")
    cursor.execute("SELECT COUNT(*) FROM TaxScenarios")
    print(f"   ✅ TaxScenarios: {cursor.fetchone()[0]} rows")


def run_load_task(load_func, server, database, datasource):
    """Helper to run a load function in its own connection."""
    conn = None
    try:
        conn = get_connection(server, database)
        load_func(conn, datasource)
    except Exception as e:
        print(f"   ❌ {load_func.__name__} failed: {e}")
        raise e
    finally:
        if conn:
            conn.close()


def main():
    parser = argparse.ArgumentParser(description='Load data to Azure SQL from blob storage (all data from blob, no local files)')
    parser.add_argument('--server', default=SQL_SERVER, help='Azure SQL server FQDN (default: from .env)')
    parser.add_argument('--database', default=SQL_DATABASE, help='Database name (default: from .env)')
    parser.add_argument('--storage-account', default=STORAGE_ACCOUNT, help='Storage account name (default: from .env)')
    parser.add_argument('--container', default=STORAGE_CONTAINER, help='Blob container name (default: from .env)')
    parser.add_argument('--identity-client-id', default=IDENTITY_CLIENT_ID, help='Client ID of user-assigned managed identity (default: from .env)')
    parser.add_argument('--force', action='store_true', help='Drop vector indexes, truncate all tables, and reload from scratch')
    args = parser.parse_args()

    missing = []
    if not args.server: missing.append('--server (or SQL_SERVER in .env)')
    if not args.database: missing.append('--database (or SQL_DATABASE in .env)')
    if not args.storage_account: missing.append('--storage-account (or STORAGE_ACCOUNT in .env)')
    if not args.container: missing.append('--container (or STORAGE_CONTAINER in .env)')
    if not args.identity_client_id: missing.append('--identity-client-id (or IDENTITY_CLIENT_ID in .env)')
    if missing:
        parser.error('Missing required arguments: ' + ', '.join(missing))
    
    print("=" * 70)
    print("📊 ZavaTax Azure SQL Data Loader (All Data from Blob Storage)")
    print("=" * 70)
    print(f"Server: {args.server}")
    print(f"Database: {args.database}")
    print(f"Storage Account: {args.storage_account}")
    print(f"Container: {args.container}")
    if args.force:
        print(f"Mode: FORCE (truncate and reload)")
    print()
    
    # Connect
    print("🔌 Connecting to Azure SQL...")
    try:
        conn = get_connection(args.server, args.database)
        print("   ✅ Connected successfully")
    except Exception as e:
        print(f"   ❌ Connection failed: {e}")
        return
    
    # Setup external data source with user-assigned managed identity
    datasource = setup_external_data_source(conn, args.storage_account, args.container, args.identity_client_id)
    
    # Force mode: drop vector indexes, then truncate all tables in FK-safe order
    if args.force:
        print("\n🗑️  Force mode: clearing all tables...")
        cursor = conn.cursor()
        # Drop vector indexes first (can't truncate tables with vector indexes)
        for table, col in [('TaxKnowledgeBase', 'ContentEmbedding'), ('TaxScenarios', 'ScenarioEmbedding')]:
            try:
                cursor.execute(f"""
                    SELECT i.name FROM sys.indexes i
                    INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
                    INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
                    WHERE i.object_id = OBJECT_ID('{table}') AND c.name = '{col}'
                """)
                for row in cursor.fetchall():
                    print(f"   Dropping vector index {row[0]} on {table}")
                    cursor.execute(f"DROP INDEX [{row[0]}] ON {table}")
            except Exception as e:
                print(f"   ⚠️ Vector index drop warning ({table}): {e}")
        
        # Truncate in reverse FK order
        for table in ['TaxReturns', 'TaxScenarios', 'TaxKnowledgeBase', 'Customers', 'TaxProfessionals', 'Branches']:
            try:
                cursor.execute(f"TRUNCATE TABLE {table}")
                print(f"   ✅ Truncated {table}")
            except Exception as e:
                # TRUNCATE fails if table is referenced by FK - use DELETE instead
                try:
                    cursor.execute(f"DELETE FROM {table}")
                    print(f"   ✅ Deleted all rows from {table}")
                except Exception as e2:
                    print(f"   ⚠️ Could not clear {table}: {e2}")
        print("   Done clearing tables.")
    
    # Parallel execution batches to respect Foreign Keys
    print("\n📥 Starting Parallel Data Load...")
    start_time = time.time()

    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
        # Batch 1: Independent tables
        print("   🚀 Batch 1: Loading independent tables...")
        futures1 = {
            executor.submit(run_load_task, load_branches, args.server, args.database, datasource): "Branches",
            executor.submit(load_customers, args.server, args.database, datasource, args.storage_account, args.container): "Customers",
            executor.submit(run_load_task, load_knowledge_base_from_json, args.server, args.database, datasource): "TaxKnowledgeBase",
            executor.submit(run_load_task, load_scenarios_from_json, args.server, args.database, datasource): "TaxScenarios"
        }
        for future in concurrent.futures.as_completed(futures1):
            name = futures1[future]
            try:
                future.result()
            except Exception:
                print(f"      ❌ Batch 1 task failed: {name}")

        # Batch 2: Professionals (Depends on Branches)
        print("   🚀 Batch 2: Loading dependent tables (Professionals)...")
        futures2 = {
            executor.submit(run_load_task, load_professionals, args.server, args.database, datasource): "TaxProfessionals"
        }
        for future in concurrent.futures.as_completed(futures2):
            name = futures2[future]
            try:
                future.result()
            except Exception:
                print(f"      ❌ Batch 2 task failed: {name}")

        # Batch 3: TaxReturns (Depends on Professionals, Customers, Branches)
        print("   🚀 Batch 3: Loading highly dependent tables (TaxReturns)...")
        futures3 = {
            executor.submit(load_tax_returns, args.server, args.database, datasource, args.storage_account, args.container): "TaxReturns"
        }
        for future in concurrent.futures.as_completed(futures3):
            name = futures3[future]
            try:
                future.result()
            except Exception:
                print(f"      ❌ Batch 3 task failed: {name}")

    print(f"   ⏱️ Total load time: {time.time() - start_time:.2f} seconds")
    
    # Summary
    print("\n" + "=" * 70)
    print("📊 Load Summary")
    print("=" * 70)
    cursor = conn.cursor()
    for table in ['Branches', 'TaxProfessionals', 'Customers', 'TaxReturns', 'TaxKnowledgeBase', 'TaxScenarios']:
        try:
            cursor.execute(f"SELECT COUNT(*) FROM {table}")
            count = cursor.fetchone()[0]
            print(f"   {table}: {count:,} rows")
        except:
            print(f"   {table}: (error)")
    
    print("\n✅ Data load complete!")
    
    conn.close()


if __name__ == "__main__":
    main()
