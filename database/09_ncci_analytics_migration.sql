-- ============================================================================
-- NCCI Migration: Align Columnstore Indexes with Filing Analytics Procs
-- ============================================================================
-- Adds missing columns to 4 existing NCCIs and creates 1 new NCCI so that
-- the GetEFileStatusSummary, GetW2Summary, GetCapitalGainsSummary,
-- GetScheduleCSummary, and GetFilingDetailOverview analytics procedures
-- can be fully served from columnstore segment scans on the named replica.
--
-- Safe to run on a database with existing data — each index is dropped
-- (if it exists) then recreated with DROP_EXISTING = OFF.
--
-- Run target: primary replica (indexes replicate to named replicas automatically)
-- ============================================================================

SET NOCOUNT ON;
GO

-- ============================================================================
-- 1. EFileSubmissions — add RejectionDate, StatusUpdatedAt
--    (GetEFileStatusSummary uses AVG(DATEDIFF(HOUR, SubmittedAt,
--     COALESCE(AcceptanceDate, RejectionDate, StatusUpdatedAt))))
-- ============================================================================
IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE name = 'NCCI_EFileSubmissions_Analytics'
             AND object_id = OBJECT_ID('EFileSubmissions'))
    DROP INDEX NCCI_EFileSubmissions_Analytics ON EFileSubmissions;
GO

CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_EFileSubmissions_Analytics
ON EFileSubmissions (
    ReturnId, TaxYear, SubmissionType, Status, SubmittedAt, AcceptanceDate,
    RejectionCode, RejectionDate, StatusUpdatedAt, AcknowledgmentReceived
) ON ps_TaxYear(TaxYear);
GO

PRINT '✓ Rebuilt NCCI_EFileSubmissions_Analytics (+RejectionDate, +StatusUpdatedAt)';
GO

-- ============================================================================
-- 2. EFileStatusHistory — new NCCI (previously had no columnstore)
--    (GetFilingDetailOverview uses COUNT_BIG(*) WHERE TaxYear = @TaxYear)
-- ============================================================================
IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE name = 'NCCI_EFileStatusHistory_Analytics'
             AND object_id = OBJECT_ID('EFileStatusHistory'))
    DROP INDEX NCCI_EFileStatusHistory_Analytics ON EFileStatusHistory;
GO

CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_EFileStatusHistory_Analytics
ON EFileStatusHistory (
    SubmissionId, TaxYear, NewStatus, ChangedAt
) ON ps_TaxYear(TaxYear);
GO

PRINT '✓ Created NCCI_EFileStatusHistory_Analytics (new)';
GO

-- ============================================================================
-- 3. W2Documents — add SocialSecurityTaxBox4, MedicareTaxBox6, RetirementPlan
--    (GetW2Summary aggregates SUM(SocialSecurityTaxBox4), SUM(MedicareTaxBox6),
--     COUNT_BIG(CASE WHEN RetirementPlan = 1 ...))
-- ============================================================================
IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE name = 'NCCI_W2Documents_Analytics'
             AND object_id = OBJECT_ID('W2Documents'))
    DROP INDEX NCCI_W2Documents_Analytics ON W2Documents;
GO

CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_W2Documents_Analytics
ON W2Documents (
    ReturnId, TaxYear, EmployerEIN, WagesBox1, FederalWithheldBox2,
    SocialSecurityWagesBox3, SocialSecurityTaxBox4, MedicareWagesBox5, MedicareTaxBox6,
    StateWagesBox16, StateWithheldBox17, RetirementPlan
) ON ps_TaxYear(TaxYear);
GO

PRINT '✓ Rebuilt NCCI_W2Documents_Analytics (+SocialSecurityTaxBox4, +MedicareTaxBox6, +RetirementPlan)';
GO

-- ============================================================================
-- 4. CapitalGainTransactions — add Quantity
--    (GetCapitalGainsSummary uses AVG(CAST(Quantity AS DECIMAL(18,2))))
-- ============================================================================
IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE name = 'NCCI_CapitalGains_Analytics'
             AND object_id = OBJECT_ID('CapitalGainTransactions'))
    DROP INDEX NCCI_CapitalGains_Analytics ON CapitalGainTransactions;
GO

CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_CapitalGains_Analytics
ON CapitalGainTransactions (
    ReturnId, TaxYear, SecurityType, Quantity, CostBasis, SaleProceeds,
    GainOrLoss, IsShortTerm, IsWashSale
) ON ps_TaxYear(TaxYear);
GO

PRINT '✓ Rebuilt NCCI_CapitalGains_Analytics (+Quantity)';
GO

-- ============================================================================
-- 5. ScheduleC_Businesses — add AccountingMethod
--    (GetScheduleCSummary uses COUNT_BIG(CASE WHEN AccountingMethod = 'Cash' ...))
-- ============================================================================
IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE name = 'NCCI_ScheduleC_Analytics'
             AND object_id = OBJECT_ID('ScheduleC_Businesses'))
    DROP INDEX NCCI_ScheduleC_Analytics ON ScheduleC_Businesses;
GO

CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_ScheduleC_Analytics
ON ScheduleC_Businesses (
    ReturnId, TaxYear, BusinessCode, AccountingMethod, GrossReceipts,
    CostOfGoodsSold, GrossProfit, TotalExpenses, NetProfit
) ON ps_TaxYear(TaxYear);
GO

PRINT '✓ Rebuilt NCCI_ScheduleC_Analytics (+AccountingMethod)';
GO

-- ============================================================================
-- 6. ScheduleE_Properties — create NCCI from schema
-- ============================================================================
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'NCCI_ScheduleE_Prop_Analytics')
    DROP INDEX NCCI_ScheduleE_Prop_Analytics ON ScheduleE_Properties;

CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_ScheduleE_Prop_Analytics
ON ScheduleE_Properties (
    ReturnId, TaxYear, PropertyType, StateCode, GrossRents,
    MortgageInterest, Depreciation, Taxes, Insurance, Repairs
) ON ps_TaxYear(TaxYear);
GO

PRINT '✓ Created NCCI_ScheduleE_Prop_Analytics';
GO

-- ============================================================================
-- 7. ScheduleE_Income — create NCCI from schema
-- ============================================================================
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'NCCI_ScheduleE_Inc_Analytics')
    DROP INDEX NCCI_ScheduleE_Inc_Analytics ON ScheduleE_Income;

CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_ScheduleE_Inc_Analytics
ON ScheduleE_Income (
    PropertyId, TaxYear, IncomeType, Amount
) ON ps_TaxYear(TaxYear);
GO

PRINT '✓ Created NCCI_ScheduleE_Inc_Analytics';
GO

-- ============================================================================
-- 8. ScheduleB_InterestDividends — create NCCI from schema
-- ============================================================================
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'NCCI_ScheduleB_Analytics')
    DROP INDEX NCCI_ScheduleB_Analytics ON ScheduleB_InterestDividends;

CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_ScheduleB_Analytics
ON ScheduleB_InterestDividends (
    ReturnId, TaxYear, EntryType, PayerName, Amount,
    TaxExemptAmount, ForeignTaxPaid, IsForeignAccount
) ON ps_TaxYear(TaxYear);
GO

PRINT '✓ Created NCCI_ScheduleB_Analytics';
GO

-- ============================================================================
-- 9. TaxFormDocuments — create NCCI from schema
-- ============================================================================
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'NCCI_TaxFormDoc_Analytics')
    DROP INDEX NCCI_TaxFormDoc_Analytics ON TaxFormDocuments;

CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_TaxFormDoc_Analytics
ON TaxFormDocuments (
    ReturnId, TaxYear, DocumentType, PageCount, FileSizeBytes,
    MimeType, Status
) ON ps_TaxYear(TaxYear);
GO

PRINT '✓ Created NCCI_TaxFormDoc_Analytics';
GO

-- ============================================================================
-- Verification: precise column-level comparison of each NCCI
-- Shows ACTUAL columns vs EXPECTED columns and flags any mismatch.
-- ============================================================================

-- Build expected schema from this migration script
IF OBJECT_ID('tempdb..#ExpectedNCCI') IS NOT NULL DROP TABLE #ExpectedNCCI;
CREATE TABLE #ExpectedNCCI (
    TableName   SYSNAME,
    IndexName   SYSNAME,
    ColumnName  SYSNAME,
    ColOrdinal  INT
);

-- 1. EFileSubmissions
INSERT INTO #ExpectedNCCI VALUES
    ('EFileSubmissions','NCCI_EFileSubmissions_Analytics','ReturnId',1),
    ('EFileSubmissions','NCCI_EFileSubmissions_Analytics','TaxYear',2),
    ('EFileSubmissions','NCCI_EFileSubmissions_Analytics','SubmissionType',3),
    ('EFileSubmissions','NCCI_EFileSubmissions_Analytics','Status',4),
    ('EFileSubmissions','NCCI_EFileSubmissions_Analytics','SubmittedAt',5),
    ('EFileSubmissions','NCCI_EFileSubmissions_Analytics','AcceptanceDate',6),
    ('EFileSubmissions','NCCI_EFileSubmissions_Analytics','RejectionCode',7),
    ('EFileSubmissions','NCCI_EFileSubmissions_Analytics','RejectionDate',8),
    ('EFileSubmissions','NCCI_EFileSubmissions_Analytics','StatusUpdatedAt',9),
    ('EFileSubmissions','NCCI_EFileSubmissions_Analytics','AcknowledgmentReceived',10);

-- 2. EFileStatusHistory
INSERT INTO #ExpectedNCCI VALUES
    ('EFileStatusHistory','NCCI_EFileStatusHistory_Analytics','SubmissionId',1),
    ('EFileStatusHistory','NCCI_EFileStatusHistory_Analytics','TaxYear',2),
    ('EFileStatusHistory','NCCI_EFileStatusHistory_Analytics','NewStatus',3),
    ('EFileStatusHistory','NCCI_EFileStatusHistory_Analytics','ChangedAt',4);

-- 3. W2Documents
INSERT INTO #ExpectedNCCI VALUES
    ('W2Documents','NCCI_W2Documents_Analytics','ReturnId',1),
    ('W2Documents','NCCI_W2Documents_Analytics','TaxYear',2),
    ('W2Documents','NCCI_W2Documents_Analytics','EmployerEIN',3),
    ('W2Documents','NCCI_W2Documents_Analytics','WagesBox1',4),
    ('W2Documents','NCCI_W2Documents_Analytics','FederalWithheldBox2',5),
    ('W2Documents','NCCI_W2Documents_Analytics','SocialSecurityWagesBox3',6),
    ('W2Documents','NCCI_W2Documents_Analytics','SocialSecurityTaxBox4',7),
    ('W2Documents','NCCI_W2Documents_Analytics','MedicareWagesBox5',8),
    ('W2Documents','NCCI_W2Documents_Analytics','MedicareTaxBox6',9),
    ('W2Documents','NCCI_W2Documents_Analytics','StateWagesBox16',10),
    ('W2Documents','NCCI_W2Documents_Analytics','StateWithheldBox17',11),
    ('W2Documents','NCCI_W2Documents_Analytics','RetirementPlan',12);

-- 4. CapitalGainTransactions
INSERT INTO #ExpectedNCCI VALUES
    ('CapitalGainTransactions','NCCI_CapitalGains_Analytics','ReturnId',1),
    ('CapitalGainTransactions','NCCI_CapitalGains_Analytics','TaxYear',2),
    ('CapitalGainTransactions','NCCI_CapitalGains_Analytics','SecurityType',3),
    ('CapitalGainTransactions','NCCI_CapitalGains_Analytics','Quantity',4),
    ('CapitalGainTransactions','NCCI_CapitalGains_Analytics','CostBasis',5),
    ('CapitalGainTransactions','NCCI_CapitalGains_Analytics','SaleProceeds',6),
    ('CapitalGainTransactions','NCCI_CapitalGains_Analytics','GainOrLoss',7),
    ('CapitalGainTransactions','NCCI_CapitalGains_Analytics','IsShortTerm',8),
    ('CapitalGainTransactions','NCCI_CapitalGains_Analytics','IsWashSale',9);

-- 5. ScheduleC_Businesses
INSERT INTO #ExpectedNCCI VALUES
    ('ScheduleC_Businesses','NCCI_ScheduleC_Analytics','ReturnId',1),
    ('ScheduleC_Businesses','NCCI_ScheduleC_Analytics','TaxYear',2),
    ('ScheduleC_Businesses','NCCI_ScheduleC_Analytics','BusinessCode',3),
    ('ScheduleC_Businesses','NCCI_ScheduleC_Analytics','AccountingMethod',4),
    ('ScheduleC_Businesses','NCCI_ScheduleC_Analytics','GrossReceipts',5),
    ('ScheduleC_Businesses','NCCI_ScheduleC_Analytics','CostOfGoodsSold',6),
    ('ScheduleC_Businesses','NCCI_ScheduleC_Analytics','GrossProfit',7),
    ('ScheduleC_Businesses','NCCI_ScheduleC_Analytics','TotalExpenses',8),
    ('ScheduleC_Businesses','NCCI_ScheduleC_Analytics','NetProfit',9);

-- 6. ScheduleE_Properties
INSERT INTO #ExpectedNCCI VALUES
    ('ScheduleE_Properties','NCCI_ScheduleE_Prop_Analytics','ReturnId',1),
    ('ScheduleE_Properties','NCCI_ScheduleE_Prop_Analytics','TaxYear',2),
    ('ScheduleE_Properties','NCCI_ScheduleE_Prop_Analytics','PropertyType',3),
    ('ScheduleE_Properties','NCCI_ScheduleE_Prop_Analytics','StateCode',4),
    ('ScheduleE_Properties','NCCI_ScheduleE_Prop_Analytics','GrossRents',5),
    ('ScheduleE_Properties','NCCI_ScheduleE_Prop_Analytics','MortgageInterest',6),
    ('ScheduleE_Properties','NCCI_ScheduleE_Prop_Analytics','Depreciation',7),
    ('ScheduleE_Properties','NCCI_ScheduleE_Prop_Analytics','Taxes',8),
    ('ScheduleE_Properties','NCCI_ScheduleE_Prop_Analytics','Insurance',9),
    ('ScheduleE_Properties','NCCI_ScheduleE_Prop_Analytics','Repairs',10);

-- 7. ScheduleE_Income
INSERT INTO #ExpectedNCCI VALUES
    ('ScheduleE_Income','NCCI_ScheduleE_Inc_Analytics','PropertyId',1),
    ('ScheduleE_Income','NCCI_ScheduleE_Inc_Analytics','TaxYear',2),
    ('ScheduleE_Income','NCCI_ScheduleE_Inc_Analytics','IncomeType',3),
    ('ScheduleE_Income','NCCI_ScheduleE_Inc_Analytics','Amount',4);

-- 8. ScheduleB_InterestDividends
INSERT INTO #ExpectedNCCI VALUES
    ('ScheduleB_InterestDividends','NCCI_ScheduleB_Analytics','ReturnId',1),
    ('ScheduleB_InterestDividends','NCCI_ScheduleB_Analytics','TaxYear',2),
    ('ScheduleB_InterestDividends','NCCI_ScheduleB_Analytics','EntryType',3),
    ('ScheduleB_InterestDividends','NCCI_ScheduleB_Analytics','PayerName',4),
    ('ScheduleB_InterestDividends','NCCI_ScheduleB_Analytics','Amount',5),
    ('ScheduleB_InterestDividends','NCCI_ScheduleB_Analytics','TaxExemptAmount',6),
    ('ScheduleB_InterestDividends','NCCI_ScheduleB_Analytics','ForeignTaxPaid',7),
    ('ScheduleB_InterestDividends','NCCI_ScheduleB_Analytics','IsForeignAccount',8);

-- 9. TaxFormDocuments
INSERT INTO #ExpectedNCCI VALUES
    ('TaxFormDocuments','NCCI_TaxFormDoc_Analytics','ReturnId',1),
    ('TaxFormDocuments','NCCI_TaxFormDoc_Analytics','TaxYear',2),
    ('TaxFormDocuments','NCCI_TaxFormDoc_Analytics','DocumentType',3),
    ('TaxFormDocuments','NCCI_TaxFormDoc_Analytics','PageCount',4),
    ('TaxFormDocuments','NCCI_TaxFormDoc_Analytics','FileSizeBytes',5),
    ('TaxFormDocuments','NCCI_TaxFormDoc_Analytics','MimeType',6),
    ('TaxFormDocuments','NCCI_TaxFormDoc_Analytics','Status',7);
GO

-- Query actual NCCI columns from sys catalog
IF OBJECT_ID('tempdb..#ActualNCCI') IS NOT NULL DROP TABLE #ActualNCCI;
SELECT
    OBJECT_NAME(i.object_id)  AS TableName,
    i.name                    AS IndexName,
    c.name                    AS ColumnName,
    ic.index_column_id        AS ColOrdinal
INTO #ActualNCCI
FROM sys.indexes i
JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE i.type = 6  -- NCCI
  AND i.name LIKE 'NCCI_%Analytics%';
GO

-- ============================================================================
-- Result 1: Per-index summary — MATCH vs MISMATCH
-- ============================================================================
PRINT '';
PRINT '═══════════════════════════════════════════════════════════';
PRINT '  NCCI SCHEMA VERIFICATION — Per-Index Summary';
PRINT '═══════════════════════════════════════════════════════════';

SELECT
    e.IndexName,
    e.TableName,
    CASE WHEN a.IndexName IS NULL THEN '❌ INDEX MISSING'
         WHEN EXISTS (
             SELECT ColumnName FROM #ExpectedNCCI WHERE IndexName = e.IndexName
             EXCEPT
             SELECT ColumnName FROM #ActualNCCI WHERE IndexName = e.IndexName
         ) THEN '❌ COLUMNS MISSING'
         WHEN EXISTS (
             SELECT ColumnName FROM #ActualNCCI WHERE IndexName = e.IndexName
             EXCEPT
             SELECT ColumnName FROM #ExpectedNCCI WHERE IndexName = e.IndexName
         ) THEN '⚠️ EXTRA COLUMNS'
         ELSE '✅ MATCH'
    END AS [Status],
    (SELECT COUNT(*) FROM #ExpectedNCCI WHERE IndexName = e.IndexName) AS ExpectedCols,
    ISNULL((SELECT COUNT(*) FROM #ActualNCCI WHERE IndexName = a.IndexName), 0) AS ActualCols
FROM (SELECT DISTINCT IndexName, TableName FROM #ExpectedNCCI) e
LEFT JOIN (SELECT DISTINCT IndexName, TableName FROM #ActualNCCI) a
    ON a.IndexName = e.IndexName
ORDER BY e.TableName;
GO

-- ============================================================================
-- Result 2: Column-level diff — shows exactly which columns are missing/extra
-- ============================================================================
PRINT '';
PRINT '═══════════════════════════════════════════════════════════';
PRINT '  NCCI COLUMN DIFF — Missing & Extra Columns';
PRINT '═══════════════════════════════════════════════════════════';

-- Missing columns (expected but not in actual)
SELECT
    'MISSING' AS Issue,
    e.TableName,
    e.IndexName,
    e.ColumnName,
    e.ColOrdinal AS ExpectedOrdinal
FROM #ExpectedNCCI e
LEFT JOIN #ActualNCCI a ON a.IndexName = e.IndexName AND a.ColumnName = e.ColumnName
WHERE a.ColumnName IS NULL

UNION ALL

-- Extra columns (in actual but not expected)
SELECT
    'EXTRA' AS Issue,
    a.TableName,
    a.IndexName,
    a.ColumnName,
    a.ColOrdinal AS ActualOrdinal
FROM #ActualNCCI a
INNER JOIN #ExpectedNCCI e2 ON e2.IndexName = a.IndexName  -- only for indexes we care about
LEFT JOIN #ExpectedNCCI e ON e.IndexName = a.IndexName AND e.ColumnName = a.ColumnName
WHERE e.ColumnName IS NULL

ORDER BY TableName, IndexName, Issue;
GO

-- ============================================================================
-- Result 3: Full side-by-side column listing for every NCCI
-- ============================================================================
PRINT '';
PRINT '═══════════════════════════════════════════════════════════';
PRINT '  NCCI FULL COLUMN LISTING (Expected ↔ Actual)';
PRINT '═══════════════════════════════════════════════════════════';

SELECT
    COALESCE(e.IndexName, a.IndexName) AS IndexName,
    COALESCE(e.ColOrdinal, a.ColOrdinal) AS Pos,
    e.ColumnName AS ExpectedColumn,
    a.ColumnName AS ActualColumn,
    CASE
        WHEN e.ColumnName IS NULL THEN N'← extra'
        WHEN a.ColumnName IS NULL THEN N'← MISSING'
        WHEN e.ColOrdinal <> a.ColOrdinal THEN N'← wrong ordinal'
        ELSE N'✓'
    END AS [Check]
FROM #ExpectedNCCI e
FULL OUTER JOIN #ActualNCCI a
    ON a.IndexName = e.IndexName AND a.ColumnName = e.ColumnName
WHERE e.IndexName IS NOT NULL OR a.IndexName IN (SELECT IndexName FROM #ExpectedNCCI)
ORDER BY COALESCE(e.IndexName, a.IndexName), COALESCE(e.ColOrdinal, a.ColOrdinal);
GO

-- Cleanup
DROP TABLE IF EXISTS #ExpectedNCCI;
DROP TABLE IF EXISTS #ActualNCCI;
GO

PRINT '';
PRINT '============================================================';
PRINT 'NCCI migration complete — 4 rebuilt, 5 new.';
PRINT 'Indexes replicate to named replicas automatically.';
PRINT '============================================================';
GO
