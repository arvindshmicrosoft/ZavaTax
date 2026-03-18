/*
 * Zava Tax - TRUNCATE Filing Detail Tables
 *
 * Resets all destination tables populated by 08_generate_filing_details.sql
 * so that script can re-run from scratch.
 *
 * ⚠️  DESTRUCTIVE — all rows in the listed tables will be permanently deleted.
 *     TaxReturns, Customers, TaxProfessionals, Branches are NOT touched.
 *
 * Run BEFORE 08_generate_filing_details.sql when tables already have data
 * (e.g. from SubmitTaxReturn stored-proc calls during testing).
 *
 * Truncation order respects FK constraints:
 *   ScheduleC_Expenses  → ScheduleC_Businesses
 *   StateFormLineItems  → StateTaxReturns
 *   EFileStatusHistory  → EFileSubmissions
 *   FormLineDefinitions → TaxForms  (TaxForms uses DELETE, not TRUNCATE, because
 *                                    SQL Server blocks TRUNCATE on any FK-referenced
 *                                    table even when the child is empty)
 */

SET NOCOUNT ON;
GO

PRINT '============================================================';
PRINT 'Zava Tax - Truncate Filing Detail Tables';
PRINT CONCAT('Started: ', CONVERT(NVARCHAR(30), SYSUTCDATETIME(), 120));
PRINT '============================================================';
PRINT '';
PRINT '⚠️  WARNING: This will DELETE ALL ROWS from all detail tables.';
PRINT '    TaxReturns, Customers, Branches, TaxProfessionals are safe.';
PRINT '';

-- Row counts before truncation
PRINT '--- Row counts BEFORE truncation ---';
SELECT t.name AS TableName, FORMAT(SUM(p.rows), 'N0') AS [RowCount]
FROM sys.tables t
INNER JOIN sys.indexes i ON t.object_id = i.object_id AND i.index_id <= 1
INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
WHERE t.name IN (
    'ScheduleC_Expenses','ScheduleC_Businesses',
    'StateFormLineItems','StateTaxReturns',
    'EFileStatusHistory','EFileSubmissions',
    'FormLineItems','W2Documents','Form1099',
    'CapitalGainTransactions','CharitableContributions',
    'ScheduleE_Income','ScheduleE_Properties',
    'ScheduleB_InterestDividends','TaxFormDocuments',
    'AuditLog','FormLineDefinitions','TaxForms'
)
GROUP BY t.name
ORDER BY t.name;
GO

-- ============================================================================
-- Truncate in FK-safe order (children before parents)
-- ============================================================================

PRINT '';
PRINT '▶ Truncating ScheduleC_Expenses (child of ScheduleC_Businesses)...';
TRUNCATE TABLE ScheduleC_Expenses;
PRINT '   ✅ Done';

PRINT '▶ Truncating ScheduleC_Businesses...';
TRUNCATE TABLE ScheduleC_Businesses;
PRINT '   ✅ Done';

PRINT '▶ Truncating StateFormLineItems (child of StateTaxReturns)...';
TRUNCATE TABLE StateFormLineItems;
PRINT '   ✅ Done';

PRINT '▶ Truncating StateTaxReturns...';
TRUNCATE TABLE StateTaxReturns;
PRINT '   ✅ Done';

PRINT '▶ Truncating EFileStatusHistory (child of EFileSubmissions)...';
TRUNCATE TABLE EFileStatusHistory;
PRINT '   ✅ Done';

PRINT '▶ Truncating EFileSubmissions...';
TRUNCATE TABLE EFileSubmissions;
PRINT '   ✅ Done';

PRINT '▶ Truncating FormLineItems...';
TRUNCATE TABLE FormLineItems;
PRINT '   ✅ Done';

PRINT '▶ Truncating W2Documents...';
TRUNCATE TABLE W2Documents;
PRINT '   ✅ Done';

PRINT '▶ Truncating Form1099...';
TRUNCATE TABLE Form1099;
PRINT '   ✅ Done';

PRINT '▶ Truncating CapitalGainTransactions...';
TRUNCATE TABLE CapitalGainTransactions;
PRINT '   ✅ Done';

PRINT '▶ Truncating CharitableContributions...';
TRUNCATE TABLE CharitableContributions;
PRINT '   ✅ Done';

PRINT '▶ Truncating ScheduleE_Income (child of ScheduleE_Properties)...';
TRUNCATE TABLE ScheduleE_Income;
PRINT '   ✅ Done';

PRINT '▶ Truncating ScheduleE_Properties...';
TRUNCATE TABLE ScheduleE_Properties;
PRINT '   ✅ Done';

PRINT '▶ Truncating ScheduleB_InterestDividends...';
TRUNCATE TABLE ScheduleB_InterestDividends;
PRINT '   ✅ Done';

PRINT '▶ Truncating TaxFormDocuments...';
TRUNCATE TABLE TaxFormDocuments;
PRINT '   ✅ Done';

PRINT '▶ Truncating AuditLog...';
TRUNCATE TABLE AuditLog;
PRINT '   ✅ Done';

PRINT '▶ Truncating FormLineDefinitions (child of TaxForms)...';
TRUNCATE TABLE FormLineDefinitions;
PRINT '   ✅ Done';

PRINT '▶ Deleting TaxForms (DELETE used: TRUNCATE blocked by FK from FormLineDefinitions)...';
DELETE FROM TaxForms;
PRINT '   ✅ Done';

-- ============================================================================
-- Confirm all empty
-- ============================================================================

PRINT '';
PRINT '--- Row counts AFTER truncation (all should be 0) ---';
SELECT t.name AS TableName, FORMAT(SUM(p.rows), 'N0') AS [RowCount]
FROM sys.tables t
INNER JOIN sys.indexes i ON t.object_id = i.object_id AND i.index_id <= 1
INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
WHERE t.name IN (
    'ScheduleC_Expenses','ScheduleC_Businesses',
    'StateFormLineItems','StateTaxReturns',
    'EFileStatusHistory','EFileSubmissions',
    'FormLineItems','W2Documents','Form1099',
    'CapitalGainTransactions','CharitableContributions',
    'ScheduleE_Income','ScheduleE_Properties',
    'ScheduleB_InterestDividends','TaxFormDocuments',
    'AuditLog','FormLineDefinitions','TaxForms'
)
GROUP BY t.name
ORDER BY t.name;
GO

PRINT '';
PRINT '============================================================';
PRINT 'All detail tables truncated.';
PRINT 'You can now run 08_generate_filing_details.sql safely.';
PRINT CONCAT('Completed: ', CONVERT(NVARCHAR(30), SYSUTCDATETIME(), 120));
PRINT '============================================================';
GO
