/*
 * Zava Tax - Validation Queries
 * 
 * Run these queries to validate the demo is working correctly.
 */

SET NOCOUNT ON;

PRINT '=== ZAVA TAX DEMO VALIDATION ===';
PRINT '';

-- ============================================================================
-- 1. DATA VOLUME CHECK
-- ============================================================================

PRINT '1. Data Volume Check';
PRINT '--------------------';

SELECT 
    t.name AS TableName,
    p.rows AS RowCount,
    CAST(SUM(a.total_pages) * 8 / 1024.0 AS DECIMAL(10,2)) AS SizeMB
FROM sys.tables t
INNER JOIN sys.indexes i ON t.object_id = i.object_id
INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
WHERE t.name IN ('Branches', 'TaxProfessionals', 'Customers', 
                  'TaxReturns', 'TaxKnowledgeBase', 'TaxScenarios',
                  'FormLineItems', 'StateTaxReturns', 'StateFormLineItems',
                  'EFileSubmissions', 'EFileStatusHistory', 'W2Documents',
                  'Form1099', 'AuditLog', 'CapitalGainTransactions',
                  'ScheduleC_Businesses', 'ScheduleC_Expenses', 'CharitableContributions',
                  'ScheduleE_Properties', 'ScheduleE_Income',
                  'ScheduleB_InterestDividends', 'TaxFormDocuments')
GROUP BY t.name, p.rows
ORDER BY p.rows DESC;

GO

-- ============================================================================
-- 2. VECTOR SEARCH TEST (Knowledge Base RAG)
-- ============================================================================

PRINT '';
PRINT '2. Vector Search Test (Knowledge Base)';
PRINT '--------------------------------------';

-- Test with a sample embedding (replace with actual embedding for real test)
-- This query validates the vector index is working
DECLARE @TestQuery NVARCHAR(MAX) = 'Can I deduct my home office expenses?';

-- In production, you'd generate the embedding via Azure OpenAI
-- For now, just verify the index exists and structure is correct
SELECT TOP 5
    ChunkId,
    PublicationId,
    LEFT(Content, 100) AS ContentPreview,
    Section
FROM TaxKnowledgeBase
WHERE ContentEmbedding IS NOT NULL;

GO

-- ============================================================================
-- 3. SIMILAR CASE SEARCH TEST
-- ============================================================================

PRINT '';
PRINT '3. Similar Case Search Test';
PRINT '---------------------------';

SELECT TOP 5
    ScenarioId,
    ScenarioType,
    FilingStatus,
    ComplexityScore,
    LEFT(ScenarioSummary, 100) AS SummaryPreview
FROM TaxScenarios
WHERE ScenarioEmbedding IS NOT NULL
ORDER BY ComplexityScore DESC;

GO

-- ============================================================================
-- 4. COLUMNSTORE AGGREGATION TEST (HTAP)
-- ============================================================================

PRINT '';
PRINT '4. Columnstore Aggregation Test (HTAP)';
PRINT '--------------------------------------';

SET STATISTICS TIME ON;
SET STATISTICS IO ON;

-- This should use the columnstore index
SELECT 
    TaxYear,
    FilingStatus,
    COUNT_BIG(*) AS ReturnCount,
    SUM(RefundAmount) AS TotalRefunds,
    AVG(GrossIncome) AS AvgIncome,
    AVG(CAST(ProcessingTimeMinutes AS BIGINT)) AS AvgProcessingTime
FROM TaxReturns
GROUP BY TaxYear, FilingStatus
ORDER BY TaxYear, ReturnCount DESC;

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;

GO

-- ============================================================================
-- 5. INDEX VALIDATION
-- ============================================================================

PRINT '';
PRINT '5. Index Validation';
PRINT '-------------------';

SELECT 
    t.name AS TableName,
    i.name AS IndexName,
    i.type_desc AS IndexType,
    CASE WHEN i.type_desc = 'CLUSTERED COLUMNSTORE' THEN 'HTAP Ready'
         WHEN i.name LIKE '%Vector%' OR i.name LIKE '%Embedding%' THEN 'Vector Search'
         ELSE 'Standard' END AS Purpose
FROM sys.indexes i
JOIN sys.tables t ON i.object_id = t.object_id
WHERE t.name IN ('TaxReturns', 'TaxKnowledgeBase', 'TaxScenarios',
                  'FormLineItems', 'StateTaxReturns', 'StateFormLineItems',
                  'EFileSubmissions', 'W2Documents', 'Form1099',
                  'AuditLog', 'CapitalGainTransactions', 'ScheduleC_Businesses',
                  'ScheduleC_Expenses', 'CharitableContributions',
                  'ScheduleE_Properties', 'ScheduleE_Income',
                  'ScheduleB_InterestDividends', 'TaxFormDocuments')
  AND i.name IS NOT NULL
ORDER BY t.name, i.type_desc;

GO

-- ============================================================================
-- 6. HYPERSCALE METRICS (if available)
-- ============================================================================

PRINT '';
PRINT '6. Hyperscale Metrics';
PRINT '---------------------';
PRINT 'Hyperscale log stats are monitored via sys.dm_db_resource_stats';
PRINT 'See GetHyperscaleResourceStats stored procedure for real-time metrics';
PRINT '---------------------';

GO

-- ============================================================================
-- 7. SAMPLE QUERIES FOR DEMO
-- ============================================================================

PRINT '';
PRINT '7. Sample Demo Queries';
PRINT '----------------------';

-- Branch performance (real-time)
PRINT 'Branch Performance Query:';
SELECT TOP 10
    b.BranchName,
    b.City,
    b.StateAbbr,
    COUNT_BIG(*) AS ReturnsProcessed,
    SUM(f.RefundAmount) AS TotalRefunds,
    AVG(CAST(f.ProcessingTimeMinutes AS BIGINT)) AS AvgMinutes
FROM TaxReturns f
JOIN Branches b ON f.BranchId = b.BranchId
WHERE f.TaxYear = 2025
GROUP BY b.BranchName, b.City, b.StateAbbr
ORDER BY ReturnsProcessed DESC;

GO

-- ============================================================================
-- 8. FILING DETAIL TABLES VALIDATION (P0 + P1)
-- ============================================================================

PRINT '';
PRINT '8. Filing Detail Tables Validation';
PRINT '----------------------------------';

-- Verify row counts and ratios make sense
SELECT
    'FormLineItems' AS TableName,
    COUNT_BIG(*) AS [RowCount],
    COUNT_BIG(DISTINCT ReturnId) AS UniqueReturns,
    CAST(COUNT_BIG(*) * 1.0 / NULLIF(COUNT_BIG(DISTINCT ReturnId), 0) AS DECIMAL(5,1)) AS AvgLinesPerReturn
FROM FormLineItems
UNION ALL
SELECT 'StateTaxReturns', COUNT_BIG(*), COUNT_BIG(DISTINCT FederalReturnId), NULL
FROM StateTaxReturns
UNION ALL
SELECT 'EFileSubmissions', COUNT_BIG(*), COUNT_BIG(DISTINCT ReturnId), NULL
FROM EFileSubmissions
UNION ALL
SELECT 'W2Documents', COUNT_BIG(*), COUNT_BIG(DISTINCT ReturnId),
    CAST(COUNT_BIG(*) * 1.0 / NULLIF(COUNT_BIG(DISTINCT ReturnId), 0) AS DECIMAL(5,1))
FROM W2Documents
UNION ALL
SELECT 'Form1099', COUNT_BIG(*), COUNT_BIG(DISTINCT ReturnId),
    CAST(COUNT_BIG(*) * 1.0 / NULLIF(COUNT_BIG(DISTINCT ReturnId), 0) AS DECIMAL(5,1))
FROM Form1099
UNION ALL
SELECT 'CapitalGainTransactions', COUNT_BIG(*), COUNT_BIG(DISTINCT ReturnId),
    CAST(COUNT_BIG(*) * 1.0 / NULLIF(COUNT_BIG(DISTINCT ReturnId), 0) AS DECIMAL(5,1))
FROM CapitalGainTransactions
UNION ALL
SELECT 'AuditLog', COUNT_BIG(*), COUNT_BIG(DISTINCT EntityId),
    CAST(COUNT_BIG(*) * 1.0 / NULLIF(COUNT_BIG(DISTINCT EntityId), 0) AS DECIMAL(5,1))
FROM AuditLog
UNION ALL
SELECT 'ScheduleE_Properties', COUNT_BIG(*), COUNT_BIG(DISTINCT ReturnId),
    CAST(COUNT_BIG(*) * 1.0 / NULLIF(COUNT_BIG(DISTINCT ReturnId), 0) AS DECIMAL(5,1))
FROM ScheduleE_Properties
UNION ALL
SELECT 'ScheduleE_Income', COUNT_BIG(*), COUNT_BIG(DISTINCT PropertyId),
    CAST(COUNT_BIG(*) * 1.0 / NULLIF(COUNT_BIG(DISTINCT PropertyId), 0) AS DECIMAL(5,1))
FROM ScheduleE_Income
UNION ALL
SELECT 'ScheduleB_InterestDividends', COUNT_BIG(*), COUNT_BIG(DISTINCT ReturnId),
    CAST(COUNT_BIG(*) * 1.0 / NULLIF(COUNT_BIG(DISTINCT ReturnId), 0) AS DECIMAL(5,1))
FROM ScheduleB_InterestDividends
UNION ALL
SELECT 'TaxFormDocuments', COUNT_BIG(*), COUNT_BIG(DISTINCT ReturnId),
    CAST(COUNT_BIG(*) * 1.0 / NULLIF(COUNT_BIG(DISTINCT ReturnId), 0) AS DECIMAL(5,1))
FROM TaxFormDocuments;

GO

-- Total database size
PRINT '';
PRINT 'Total Database Size:';
SELECT
    CAST(SUM(size) * 8.0 / 1024 / 1024 AS DECIMAL(12,2)) AS TotalSizeGB
FROM sys.database_files;

GO

PRINT '';
PRINT '=== VALIDATION COMPLETE ===';
PRINT '';
PRINT 'If all queries returned results without errors, the demo is ready!';
