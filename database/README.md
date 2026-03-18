# Zava Tax Database Scripts

SQL scripts for creating and loading the Zava Tax demo database on Azure SQL DB Hyperscale or SQL Server 2025 Express.

## Local Development (SQL Server 2025 Express)

### Quick Start

```powershell
# 1. Create database and schema
sqlcmd -S ".\SQLEXPRESS" -i "scripts/local_dev_setup.sql"

# 2. Load data (from data-prep folder)
cd ../data-prep
python 07_load_to_sqlexpress.py

# 3. Deploy OLTP workflow stored procedures
#    Required for New Return wizard, load simulator, and return submission
cd ../database
sqlcmd -S ".\SQLEXPRESS" -d ZavaTax -i "06_oltp_procedures.sql"

# 4. Deploy security features (Ledger, RLS, DDM, classification)
#    Required for Security Dashboard and AI interaction logging
sqlcmd -S ".\SQLEXPRESS" -d ZavaTax -i "10_security_features.sql"

# 5. (Optional) Enable Azure OpenAI for vector search
# Edit scripts/setup_openai_local.sql and add your API key on line 57
sqlcmd -S ".\SQLEXPRESS" -i "scripts/setup_openai_local.sql"

# 6. Re-run local_dev_setup to update stored procedures
sqlcmd -S ".\SQLEXPRESS" -d ZavaTax -i "scripts/local_dev_setup.sql"
```

### Local Scripts

| Script | Purpose |
|--------|---------|
| [scripts/local_dev_setup.sql](scripts/local_dev_setup.sql) | Creates ZavaTax database with all tables, indexes, and stored procedures |
| [06_oltp_procedures.sql](06_oltp_procedures.sql) | OLTP workflow stored procedures (New Return wizard, submit, update) |
| [scripts/setup_openai_local.sql](scripts/setup_openai_local.sql) | Enables Azure OpenAI for real vector search (requires API key) |

### Azure OpenAI Configuration (for Vector Search + AI Assistant)

Without Azure OpenAI, the knowledge base search uses keyword matching. To enable true semantic/vector search and AI assistant:

**Required Azure OpenAI Resources:**

| Resource | Purpose | Deployment Name |
|----------|---------|-----------------|
| Embeddings | Vector search (SQL Server 2025 native) | `text-embedding-3-small` |
| Chat | RAG + LLM assistant | `gpt-4o` or similar |

**Note:** These can be the same Azure OpenAI resource or separate resources.

1. **Copy the template to create your local config:**
   ```powershell
   copy scripts\setup_openai_local.sql scripts\setup_openai_local.actual.sql
   notepad scripts\setup_openai_local.actual.sql
   ```
   The `.actual.sql` file is gitignored and safe for your credentials.

2. **Update your credentials in the copied file:**
   - Your embeddings resource name and API key
   - Your chat resource name and API key

3. **Run the script:**
   ```powershell
   sqlcmd -S ".\SQLEXPRESS" -d ZavaTax -i "scripts/setup_openai_local.actual.sql"
   ```

   This script:
   - Enables `external rest endpoint enabled` configuration
   - Creates database-scoped credentials for both embeddings and chat
   - Creates an `EXTERNAL MODEL` for embeddings
   - Creates `AskTaxAssistant` stored procedure (RAG + LLM via REST)
   - Tests the configuration with `AI_GENERATE_EMBEDDINGS()`

4. **Update stored procedures:**
   ```powershell
   sqlcmd -S ".\SQLEXPRESS" -d ZavaTax -i "scripts/local_dev_setup.sql"
   ```

**Note:** SQL Server 2025 uses:
- `CREATE EXTERNAL MODEL` with `MODEL_TYPE = EMBEDDINGS` for vector generation
- `sp_invoke_external_rest_endpoint` for chat completions (MODEL_TYPE = CHAT not yet supported)

---

## Azure SQL DB Hyperscale

### Important: Azure SQL DB Loading Options

**Azure SQL DB (including Hyperscale) does NOT support BULK INSERT from local file paths.** 

You have two options for loading data:

| Method | Pros | Cons |
|--------|------|------|
| **Python Loader** (Recommended) | Works from any client, no blob setup | Slower for very large datasets |
| **BULK INSERT from Blob** | Fast for large datasets | Requires Azure Storage setup |

## Scripts

**Execution Order** (important for dependencies):

| Order | Script | Purpose |
|-------|--------|---------|
| 1 | [01_create_schema.sql](01_create_schema.sql) | Creates tables, views, indexes, and basic stored procedures |
| 2 | [02_load_csv_data.sql](02_load_csv_data.sql) | Loads reference data from Azure Blob Storage (using managed identity) |
| 3 | [03_load_json_data.sql](03_load_json_data.sql) | Loads knowledge base and scenarios with embeddings |
| 4 | [04_validation_queries.sql](04_validation_queries.sql) | Validates data load and tests demo queries |
| 5 | [05_setup_azure_openai_endpoint.sql](05_setup_azure_openai_endpoint.sql) | Creates external model for Azure OpenAI + AI stored procedures |
| 6 | [06_oltp_procedures.sql](06_oltp_procedures.sql) | OLTP workflow stored procedures (create/update/submit returns) |
| 7 | [07_partition_taxreturns.sql](07_partition_taxreturns.sql) | Partition TaxReturns by TaxYear — **Azure SQL / Enterprise only** |
| 8 | [08_generate_filing_details.sql](08_generate_filing_details.sql) | Generate P0+P1 filing detail data (~300+ GB) — **Azure SQL only** (exceeds Express 10 GB limit) |
| 8a | [08a_truncate_filing_details.sql](08a_truncate_filing_details.sql) | Truncate filing detail tables (reset before regeneration) — **Azure SQL only** |
| 9 | [09_ncci_analytics_migration.sql](09_ncci_analytics_migration.sql) | NCCI analytics migration (columnstore index tuning) — **Azure SQL / Enterprise only** (requires partitioning from script 07) |
| 10 | [10_security_features.sql](10_security_features.sql) | Security audit log, SQL injection detection, and monitoring stored procedures |

> **Note:** Script 05 must run AFTER script 01 (which creates tables it depends on). Script 06 can run at any time after 01. Script 08 must run AFTER data is loaded into TaxReturns.
>
> **When deploying via deploy.ps1:** The script automates execution order — 01 and 06 run pre-DAB, then 05 runs after OpenAI deployment. You do not need to run these manually.

## Authentication

**All components use Managed Identity - no passwords or API keys required.**

| Component | Identity Used |
|-----------|---------------|
| Python scripts → SQL DB | DefaultAzureCredential (user identity or managed identity) |
| SQL DB → Blob Storage | SQL Server system-assigned managed identity |
| SQL DB → Azure OpenAI | SQL Server system-assigned managed identity |
| Container Apps → SQL DB | User-assigned managed identity |

## Quick Start

### 1. Create the Database

```sql
-- Run on master database
CREATE DATABASE [zavatax-2026]
(
    EDITION = 'Hyperscale',
    SERVICE_OBJECTIVE = 'HS_PRMS_8',  -- Hyperscale premium-series (adjust vCores as needed)
    MAXSIZE = 1 TB
);
```

### 2. Run Schema Script

```powershell
# Using sqlcmd
sqlcmd -S your-server.database.windows.net -d zavatax-2026 -G -i 01_create_schema.sql
```

### 3. Load Data

#### Option A: Python Loader (Recommended for Demo)
```powershell
cd ../data-prep
# Configure .env with your SQL connection
python 07_load_to_azure_sql.py
```

#### Option B: BULK INSERT from Azure Blob Storage
```powershell
# 1. Create storage account and container
az storage account create -n zavataxstorage -g your-rg -l eastus --sku Standard_LRS
az storage container create -n zavatax-data --account-name zavataxstorage

# 2. Upload CSV files
az storage blob upload-batch --account-name zavataxstorage --destination zavatax-data --source "data-prep/data/output"

# 3. Get SAS token
az storage container generate-sas --account-name zavataxstorage --name zavatax-data --permissions rl --expiry 2026-12-31 --output tsv

# 4. Update 02_load_csv_data.sql with your storage account and SAS token
# 5. Run the script
sqlcmd -S your-server.database.windows.net -d zavatax-2026 -G -i 02_load_csv_data.sql
```

### 4. Validate

```powershell
sqlcmd -S your-server.database.windows.net -d zavatax-2026 -G -i 04_validation_queries.sql
```

## Schema Overview

### Reference Tables
- **Branches** - Franchise locations (500 rows)
- **TaxProfessionals** - Tax preparers (2,000 rows)
- **Customers** - Client records (10M+ rows)
- **TaxForms** - IRS form metadata per tax year (~70 rows)
- **FormLineDefinitions** - Line-level definitions for each form (~1,400 rows)

### Vector Search Tables
- **TaxKnowledgeBase** - IRS publication chunks with embeddings (500+ rows)
- **TaxScenarios** - Historical cases with embeddings (5,000 rows)

### Core HTAP Tables
- **TaxReturns** - Transactional tax returns (rowstore + NCCI, partitioned by TaxYear) (47M+ rows)

### P0: Filing Detail Tables
- **FormLineItems** - Individual 1040 line items (~1.3B rows, ~28 lines per return)
- **StateTaxReturns** - State-level tax filings for income-tax states (~40M rows)
- **StateFormLineItems** - State form line items (~480M rows)
- **EFileSubmissions** - IRS e-file submission tracking (~47M rows)
- **EFileStatusHistory** - State machine history for each submission (~140M rows)

### P1: Income Documents & Schedules
- **W2Documents** - W-2 wage statements with all box fields (~70M rows)
- **Form1099** - 1099-INT/DIV/NEC/MISC income documents (~65M rows)
- **CapitalGainTransactions** - Schedule D trade details (~280M rows)
- **ScheduleC_Businesses** - Schedule C business profiles (~7M rows)
- **ScheduleC_Expenses** - Schedule C expense line items (~50M rows)
- **CharitableContributions** - Schedule A charitable donations (~42M rows)

### P1: Audit & Compliance
- **AuditLog** - Complete audit trail for all entity changes (~140M+ rows)

### Inline Population
When a tax return is submitted via `SubmitTaxReturn`, the `PopulateFilingDetails` stored procedure automatically generates all associated detail records (form line items, state return, e-file submission, W-2s, 1099s, schedule details, and audit trail). This simulates a real tax platform's filing pipeline.

## Key Features Demonstrated

### Vector Indexes (DiskANN)
```sql
CREATE VECTOR INDEX IX_TaxKnowledge_Embedding
ON TaxKnowledgeBase(ContentEmbedding)
WITH (METRIC = 'cosine', TYPE = 'DISKANN');
```

### Columnstore for HTAP
```sql
CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_TaxReturns_Analytics
ON TaxReturns (...)
```

### JSON Support
```sql
TotalIncome AS CAST(JSON_VALUE(TaxOutcome, '$.total_income') AS INT) PERSISTED
```

### Vector Search Stored Procedure
```sql
EXEC SearchKnowledgeBase @QueryEmbedding = @embedding, @TopK = 5;
```

## Named Replicas Configuration

After creating the database, add named replicas for workload isolation:

```sql
-- RAG Replica (low-latency reads for AI queries)
ALTER DATABASE [zavatax-2026]
ADD SECONDARY ON SERVER [your-server]
AS REPLICA [zavatax-2026-rag]
WITH (
    SERVICE_OBJECTIVE = 'HS_PRMS_2',
    SECONDARY_TYPE = 'Named'
);

-- Analytics Replica (heavy reporting queries)
ALTER DATABASE [zavatax-2026]
ADD SECONDARY ON SERVER [your-server]
AS REPLICA [zavatax-2026-analytics]
WITH (
    SERVICE_OBJECTIVE = 'HS_PRMS_4',
    SECONDARY_TYPE = 'Named'
);
```

## Database Monitoring

```sql
-- Check resource utilization (updates every 15 seconds)
SELECT TOP 10
    end_time,
    avg_cpu_percent,
    avg_data_io_percent,
    avg_log_write_percent,
    max_worker_percent,
    max_session_percent
FROM sys.dm_db_resource_stats
ORDER BY end_time DESC;

-- Check replica status
SELECT * FROM sys.dm_hadr_database_replica_states;
```
