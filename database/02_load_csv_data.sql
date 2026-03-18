/*
 * Zava Tax - Load Data from Azure Blob Storage
 * 
 * IMPORTANT: Azure SQL DB and Hyperscale do NOT support BULK INSERT from 
 * local file paths. Files MUST be in Azure Blob Storage.
 * 
 * Prerequisites:
 * 1. Create Azure Storage Account and container
 * 2. Upload data files to blob storage (use AzCopy or Azure Portal)
 * 3. Generate SAS token with read permissions
 * 4. Run the credential/data source setup below
 * 5. Run the BULK INSERT statements
 * 
 * ALTERNATIVE: Use the Python loader:
 *   Local dev:  python data-prep/07_load_to_sqlexpress.py
 *   Azure SQL:  python data-prep/07_load_to_azure_sql.py --server ... --database ...
 */

SET NOCOUNT ON;

-- ============================================================================
-- STEP 1: Setup External Data Source with Managed Identity (Run Once)
-- ============================================================================

/*
PREREQUISITE: Grant the SQL Server managed identity access to your storage account

1. Get the SQL Server's managed identity:
   - Azure Portal > SQL Server > Identity > System assigned > Object ID

2. Grant Storage Blob Data Reader role:
   az role assignment create \
     --assignee <sql-server-managed-identity-object-id> \
     --role "Storage Blob Data Reader" \
     --scope /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Storage/storageAccounts/<storage-account>
*/

-- Drop and recreate credential if updating
IF EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'ZavaTaxBlobCredential')
BEGIN
    DROP DATABASE SCOPED CREDENTIAL ZavaTaxBlobCredential;
END
GO

-- Create credential using Managed Identity
-- No secrets needed - uses the SQL Server's system-assigned managed identity
CREATE DATABASE SCOPED CREDENTIAL ZavaTaxBlobCredential
WITH IDENTITY = 'Managed Identity';
GO

-- Drop and recreate external data source if updating
IF EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'ZavaTaxDataSource')
BEGIN
    DROP EXTERNAL DATA SOURCE ZavaTaxDataSource;
END
GO

-- Create external data source pointing to your container
-- Replace with your actual storage account and container names
CREATE EXTERNAL DATA SOURCE ZavaTaxDataSource
WITH (
    TYPE = BLOB_STORAGE,
    LOCATION = 'https://yourstorageaccount.blob.core.windows.net/zavatax-data',
    CREDENTIAL = ZavaTaxBlobCredential
);
GO

PRINT 'External data source configured with Managed Identity.';
PRINT '';

-- ============================================================================
-- STEP 2: Upload Files to Blob Storage
-- ============================================================================
/*
Before running BULK INSERT, upload your CSV files to blob storage:

# Using AzCopy (recommended for large files)
azcopy copy "data-prep\data\output\*" "https://yourstorageaccount.blob.core.windows.net/zavatax-data?<sas-token>" --recursive

# Or using Azure CLI
az storage blob upload-batch --account-name yourstorageaccount --destination zavatax-data --source "data-prep\data\output"

Expected files in blob container:
  - branches.csv
  - tax_professionals.csv  
  - customers.csv
  - tax_returns_fact.csv
*/

-- ============================================================================
-- STEP 3: Load Reference Data from Blob Storage
-- ============================================================================

-- Load Branches
PRINT 'Loading Branches...';
SET IDENTITY_INSERT Branches ON;
BULK INSERT Branches
FROM 'branches.csv'
WITH (
    DATA_SOURCE = 'ZavaTaxDataSource',
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    TABLOCK,
    ERRORFILE = 'errors/branches_errors.csv',
    ERRORFILE_DATA_SOURCE = 'ZavaTaxDataSource'
);
SET IDENTITY_INSERT Branches OFF;
PRINT CONCAT('Branches loaded: ', @@ROWCOUNT, ' rows');
GO

-- Load Tax Professionals
PRINT 'Loading Tax Professionals...';
SET IDENTITY_INSERT TaxProfessionals ON;
BULK INSERT TaxProfessionals
FROM 'tax_professionals.csv'
WITH (
    DATA_SOURCE = 'ZavaTaxDataSource',
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    TABLOCK,
    ERRORFILE = 'errors/professionals_errors.csv',
    ERRORFILE_DATA_SOURCE = 'ZavaTaxDataSource'
);
SET IDENTITY_INSERT TaxProfessionals OFF;
PRINT CONCAT('Tax Professionals loaded: ', @@ROWCOUNT, ' rows');
GO

-- Load Customers
PRINT 'Loading Customers...';
SET IDENTITY_INSERT Customers ON;
BULK INSERT Customers
FROM 'customers.csv'
WITH (
    DATA_SOURCE = 'ZavaTaxDataSource',
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    TABLOCK,
    ERRORFILE = 'errors/customers_errors.csv',
    ERRORFILE_DATA_SOURCE = 'ZavaTaxDataSource'
);
SET IDENTITY_INSERT Customers OFF;
PRINT CONCAT('Customers loaded: ', @@ROWCOUNT, ' rows');
GO

-- Load Tax Returns Fact (large table - use batches)
PRINT 'Loading Tax Returns Fact (this may take several minutes)...';
SET IDENTITY_INSERT TaxReturns ON;
BULK INSERT TaxReturns
FROM 'tax_returns_fact.csv'
WITH (
    DATA_SOURCE = 'ZavaTaxDataSource',
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    TABLOCK,
    BATCHSIZE = 100000,
    ERRORFILE = 'errors/returns_errors.csv',
    ERRORFILE_DATA_SOURCE = 'ZavaTaxDataSource'
);
SET IDENTITY_INSERT TaxReturns OFF;
PRINT CONCAT('Tax Returns Fact loaded: ', @@ROWCOUNT, ' rows');
GO

-- ============================================================================
-- STEP 4: Load JSON Data (Knowledge Base and Scenarios)
-- ============================================================================

/*
For JSON files with embeddings, use one of these approaches:

OPTION A: Python Loader (RECOMMENDED)
  cd data-prep
  python 07_load_to_azure_sql.py --server <server> --database <db> ...
  
  This reads from Azure Blob Storage via OPENROWSET.
  For local dev, use: python 07_load_to_sqlexpress.py

OPTION B: Load JSON from Blob using OPENROWSET
  See example below - requires JSON files in blob storage.
*/

-- Example: Load knowledge base JSON from blob storage
/*
INSERT INTO TaxKnowledgeBase (
    ChunkId, PublicationId, PublicationTitle, Section, Subsection,
    Content, TokenEstimate, SourceUrl, ChunkIndex, ContentEmbedding
)
SELECT 
    JSON_VALUE(doc.value, '$.chunk_id'),
    JSON_VALUE(doc.value, '$.publication_id'),
    JSON_VALUE(doc.value, '$.publication_title'),
    JSON_VALUE(doc.value, '$.section'),
    JSON_VALUE(doc.value, '$.subsection'),
    JSON_VALUE(doc.value, '$.content'),
    CAST(JSON_VALUE(doc.value, '$.token_estimate') AS INT),
    JSON_VALUE(doc.value, '$.url'),
    CAST(JSON_VALUE(doc.value, '$.chunk_index') AS INT),
    CAST(JSON_QUERY(doc.value, '$.embedding') AS VECTOR(1536))
FROM OPENROWSET(
    BULK 'knowledge_base_embedded.json',
    DATA_SOURCE = 'ZavaTaxDataSource',
    SINGLE_CLOB
) AS raw
CROSS APPLY OPENJSON(raw.BulkColumn) AS doc;
*/

GO

-- ============================================================================
-- STEP 5: Update Statistics
-- ============================================================================

PRINT 'Updating statistics...';

UPDATE STATISTICS Branches;
UPDATE STATISTICS TaxProfessionals;
UPDATE STATISTICS Customers;
UPDATE STATISTICS TaxReturns;

PRINT 'Statistics updated.';
GO

-- ============================================================================
-- STEP 6: Verify Loads
-- ============================================================================

PRINT '';
PRINT '=== Data Load Summary ===';

SELECT 'Branches' AS TableName, COUNT_BIG(*) AS RowCount FROM Branches
UNION ALL
SELECT 'TaxProfessionals', COUNT_BIG(*) FROM TaxProfessionals
UNION ALL
SELECT 'Customers', COUNT_BIG(*) FROM Customers
UNION ALL
SELECT 'TaxReturns', COUNT_BIG(*) FROM TaxReturns
UNION ALL
SELECT 'TaxKnowledgeBase', COUNT_BIG(*) FROM TaxKnowledgeBase
UNION ALL
SELECT 'TaxScenarios', COUNT_BIG(*) FROM TaxScenarios;

GO

PRINT 'Data load complete!';
PRINT '';
PRINT '=== NEXT STEPS ===';
PRINT '1. Run 03_load_json_data.sql or use Python: python data-prep/07_load_to_azure_sql.py';
PRINT '2. Run 04_validation_queries.sql to verify the demo is ready';
GO
