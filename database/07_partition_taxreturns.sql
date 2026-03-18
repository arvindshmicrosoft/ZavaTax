-- ============================================================================
-- PARTITION TaxReturns BY TaxYear
-- ============================================================================
-- Migrates the existing TaxReturns table to a partitioned table using TaxYear.
-- Each tax year gets its own partition for efficient partition elimination
-- in analytical queries and simplified data lifecycle management.
--
-- Azure SQL Hyperscale: All partitions map to [PRIMARY] filegroup.
--
-- IMPORTANT: Run this during a maintenance window. The clustered index rebuild
-- will be an offline operation proportional to the table size.
-- ============================================================================

SET NOCOUNT ON;
GO

-- ============================================================================
-- 1. CREATE PARTITION FUNCTION AND SCHEME
-- ============================================================================
-- RANGE RIGHT: boundary value is the FIRST value in the next partition.
--   Partition 1:  TaxYear < 2020   (2019 and earlier)
--   Partition 2:  TaxYear = 2020
--   Partition 3:  TaxYear = 2021
--   ...
--   Partition 8:  TaxYear = 2026
--   Partition 9:  TaxYear >= 2027  (future years)
-- ============================================================================

IF NOT EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = 'pf_TaxYear')
BEGIN
    CREATE PARTITION FUNCTION pf_TaxYear (INT)
    AS RANGE RIGHT FOR VALUES (2020, 2021, 2022, 2023, 2024, 2025, 2026, 2027);

    PRINT 'Created partition function pf_TaxYear';
END
ELSE
    PRINT 'Partition function pf_TaxYear already exists — skipped';
GO

IF NOT EXISTS (SELECT 1 FROM sys.partition_schemes WHERE name = 'ps_TaxYear')
BEGIN
    CREATE PARTITION SCHEME ps_TaxYear
    AS PARTITION pf_TaxYear
    ALL TO ([PRIMARY]);

    PRINT 'Created partition scheme ps_TaxYear';
END
ELSE
    PRINT 'Partition scheme ps_TaxYear already exists — skipped';
GO

-- ============================================================================
-- 2. CHECK IF TABLE IS ALREADY PARTITIONED
-- ============================================================================
IF EXISTS (
    SELECT 1
    FROM sys.indexes i
    JOIN sys.partition_schemes ps ON i.data_space_id = ps.data_space_id
    WHERE i.object_id = OBJECT_ID('TaxReturns')
      AND i.type_desc = 'CLUSTERED'
)
BEGIN
    PRINT 'TaxReturns is already partitioned — nothing to do.';
    -- Exit early
    RETURN;
END
GO

-- ============================================================================
-- 3. DROP NONCLUSTERED INDEXES (must be dropped before changing the PK)
-- ============================================================================
PRINT 'Dropping nonclustered indexes...';

-- Drop NCCI first (columnstore)
DROP INDEX IF EXISTS NCCI_TaxReturns_Analytics ON TaxReturns;
PRINT '  Dropped NCCI_TaxReturns_Analytics';

-- Drop rowstore nonclustered indexes
DROP INDEX IF EXISTS UQ_TaxReturns_Customer_TaxYear ON TaxReturns;
PRINT '  Dropped UQ_TaxReturns_Customer_TaxYear';

DROP INDEX IF EXISTS IX_TaxReturns_Customer ON TaxReturns;
PRINT '  Dropped IX_TaxReturns_Customer';

DROP INDEX IF EXISTS IX_TaxReturns_Branch_Date ON TaxReturns;
PRINT '  Dropped IX_TaxReturns_Branch_Date';

DROP INDEX IF EXISTS IX_TaxReturns_Professional ON TaxReturns;
PRINT '  Dropped IX_TaxReturns_Professional';

DROP INDEX IF EXISTS IX_TaxReturns_International ON TaxReturns;
PRINT '  Dropped IX_TaxReturns_International';
GO

-- ============================================================================
-- 4. DROP THE EXISTING PRIMARY KEY AND RECREATE AS COMPOSITE ON PARTITION SCHEME
-- ============================================================================
-- The partition key (TaxYear) MUST be part of every unique/clustered index.
-- We change (ReturnId) → (ReturnId, TaxYear) and place it on ps_TaxYear.
-- ============================================================================
PRINT 'Rebuilding clustered primary key on partition scheme...';

-- Find and drop the existing PK constraint by name
DECLARE @PKName NVARCHAR(256);
SELECT @PKName = kc.name
FROM sys.key_constraints kc
WHERE kc.parent_object_id = OBJECT_ID('TaxReturns')
  AND kc.type = 'PK';

IF @PKName IS NOT NULL
BEGIN
    DECLARE @DropSQL NVARCHAR(500) = N'ALTER TABLE TaxReturns DROP CONSTRAINT ' + QUOTENAME(@PKName);
    EXEC sp_executesql @DropSQL;
    PRINT '  Dropped PK constraint: ' + @PKName;
END

-- Recreate as composite PK on the partition scheme
ALTER TABLE TaxReturns
ADD CONSTRAINT PK_TaxReturns
    PRIMARY KEY CLUSTERED (ReturnId, TaxYear)
    ON ps_TaxYear(TaxYear);

PRINT '  Created PK_TaxReturns (ReturnId, TaxYear) on ps_TaxYear';
GO

-- ============================================================================
-- 5. RECREATE NONCLUSTERED INDEXES (aligned to partition scheme)
-- ============================================================================
PRINT 'Recreating nonclustered indexes on partition scheme...';

-- Unique constraint: one return per customer per tax year (already includes TaxYear)
CREATE UNIQUE NONCLUSTERED INDEX UQ_TaxReturns_Customer_TaxYear
ON TaxReturns (CustomerId, TaxYear)
ON ps_TaxYear(TaxYear);
PRINT '  Created UQ_TaxReturns_Customer_TaxYear';

CREATE NONCLUSTERED INDEX IX_TaxReturns_Customer
ON TaxReturns (CustomerId, TaxYear)
ON ps_TaxYear(TaxYear);
PRINT '  Created IX_TaxReturns_Customer';

CREATE NONCLUSTERED INDEX IX_TaxReturns_Branch_Date
ON TaxReturns (BranchId, FilingDate)
INCLUDE (RefundAmount, AmountOwed, ProcessingTimeMinutes)
ON ps_TaxYear(TaxYear);
PRINT '  Created IX_TaxReturns_Branch_Date';

CREATE NONCLUSTERED INDEX IX_TaxReturns_Professional
ON TaxReturns (ProfessionalId, FilingDate)
ON ps_TaxYear(TaxYear);
PRINT '  Created IX_TaxReturns_Professional';

CREATE NONCLUSTERED INDEX IX_TaxReturns_International
ON TaxReturns (TaxYear, HasForeignAccounts, HasPFIC, HasForeignTrust, HasForeignCorporation, HasForeignPartnership)
INCLUDE (ForeignAccountMaxValue, PFICValue, ForeignTaxesPaid, ForeignGiftsReceived)
ON ps_TaxYear(TaxYear);
PRINT '  Created IX_TaxReturns_International';
GO

-- ============================================================================
-- 6. RECREATE NONCLUSTERED COLUMNSTORE INDEX (aligned)
-- ============================================================================
PRINT 'Recreating NCCI for analytics...';

CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_TaxReturns_Analytics
ON TaxReturns (
    ReturnId,
    CustomerId,
    BranchId,
    ProfessionalId,
    TaxYear,
    FilingDate,
    FilingStatus,
    GrossIncome,
    AdjustedGrossIncome,
    TotalDeductions,
    TaxableIncome,
    TaxLiability,
    TotalWithheld,
    RefundAmount,
    AmountOwed,
    Status,
    IsItemized,
    NumDependents,
    ProcessingTimeMinutes,
    DocumentCount,
    AIAssistanceCount,
    IsAmended,
    IsExtension,
    HasForeignAccounts,
    ForeignAccountMaxValue,
    HasPFIC,
    PFICValue,
    PFICIncome,
    HasForeignTrust,
    ForeignTrustValue,
    HasForeignCorporation,
    ForeignCorpOwnershipPct,
    HasForeignPartnership,
    ForeignGiftsReceived,
    ForeignTaxesPaid,
    CreatedAt,
    UpdatedAt
)
ON ps_TaxYear(TaxYear);

PRINT '  Created NCCI_TaxReturns_Analytics on ps_TaxYear';
GO

-- ============================================================================
-- 7. VERIFY PARTITIONING
-- ============================================================================
PRINT '';
PRINT '=== Partition Summary ===';

SELECT
    p.partition_number AS PartitionNumber,
    CASE
        WHEN prv_left.value IS NULL AND prv_right.value IS NOT NULL
            THEN 'TaxYear < ' + CAST(prv_right.value AS VARCHAR)
        WHEN prv_left.value IS NOT NULL AND prv_right.value IS NOT NULL
            THEN 'TaxYear = ' + CAST(prv_left.value AS VARCHAR)
        WHEN prv_left.value IS NOT NULL AND prv_right.value IS NULL
            THEN 'TaxYear >= ' + CAST(prv_left.value AS VARCHAR)
        ELSE 'All rows'
    END AS PartitionRange,
    p.[rows] AS [RowCount]
FROM sys.partitions p
JOIN sys.indexes i ON p.object_id = i.object_id AND p.index_id = i.index_id
CROSS APPLY (
    SELECT ps.function_id
    FROM sys.partition_schemes ps
    WHERE ps.data_space_id = i.data_space_id
) psf
LEFT JOIN sys.partition_range_values prv_right
    ON prv_right.function_id = psf.function_id
    AND prv_right.boundary_id = p.partition_number
LEFT JOIN sys.partition_range_values prv_left
    ON prv_left.function_id = psf.function_id
    AND prv_left.boundary_id = p.partition_number - 1
WHERE p.object_id = OBJECT_ID('TaxReturns')
  AND i.type_desc = 'CLUSTERED'
ORDER BY p.partition_number;

PRINT '';
PRINT 'TaxReturns partitioning complete!';
GO
