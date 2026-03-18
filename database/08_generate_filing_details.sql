/*
 * Zava Tax - Generate Realistic Filing Detail Records (P0 + P1)
 *
 * Generates high-volume detail data IN-DATABASE from existing TaxReturns.
 * This is far more efficient than generating CSV files locally.
 *
 * Tables populated:
 *   P0: TaxForms, FormLineDefinitions, FormLineItems,
 *       StateTaxReturns, StateFormLineItems,
 *       EFileSubmissions, EFileStatusHistory
 *   P1: W2Documents, Form1099, AuditLog,
 *       CapitalGainTransactions, ScheduleC_Businesses, ScheduleC_Expenses,
 *       CharitableContributions
 *
 * Estimated output: ~2-3 billion rows, ~300+ GB compressed
 *
 * Run AFTER 01_create_schema.sql and AFTER loading TaxReturns.
 * IDEMPOTENT: Checks for existing data before inserting.
 *
 * Usage:  sqlcmd -S <server> -d <db> -i 08_generate_filing_details.sql
 */

SET NOCOUNT ON;
GO

PRINT '============================================================';
PRINT 'Zava Tax - Filing Detail Data Generation';
PRINT CONCAT('Started: ', CONVERT(NVARCHAR(30), SYSUTCDATETIME(), 120));
PRINT '============================================================';
PRINT '';

-- ============================================================================
-- PREREQUISITE CHECKS: Verify base data exists and show scale
-- ============================================================================

DECLARE @BranchCount    BIGINT = (SELECT COUNT_BIG(*) FROM Branches);
DECLARE @ProfCount      BIGINT = (SELECT COUNT_BIG(*) FROM TaxProfessionals);
DECLARE @CustomerCount  BIGINT = (SELECT COUNT_BIG(*) FROM Customers);
DECLARE @ReturnCount    BIGINT = (SELECT COUNT_BIG(*) FROM TaxReturns);

PRINT 'Prerequisite data check:';
PRINT CONCAT('   Branches:          ', FORMAT(@BranchCount,   'N0'));
PRINT CONCAT('   TaxProfessionals:  ', FORMAT(@ProfCount,     'N0'));
PRINT CONCAT('   Customers:         ', FORMAT(@CustomerCount, 'N0'));
PRINT CONCAT('   TaxReturns:        ', FORMAT(@ReturnCount,   'N0'));
PRINT '';

IF @ReturnCount = 0
BEGIN
    RAISERROR('ERROR: TaxReturns table is empty. Load data-prep output first (07_load_to_azure_sql.py).', 16, 1);
    RETURN;
END

IF @CustomerCount = 0
BEGIN
    RAISERROR('ERROR: Customers table is empty. Load data-prep output first.', 16, 1);
    RETURN;
END

-- Show estimated output scale (proportional to returns)
DECLARE @EstFormLines    BIGINT = @ReturnCount * 28;
DECLARE @EstStateReturns BIGINT = CAST(@ReturnCount * 0.89 AS BIGINT);
DECLARE @EstStateFLI     BIGINT = @EstStateReturns * 12;
DECLARE @EstEFile        BIGINT = CAST(@ReturnCount * 0.95 AS BIGINT);
DECLARE @EstEFileHist    BIGINT = @EstEFile * 3;
DECLARE @EstW2           BIGINT = CAST(@ReturnCount * 1.35 AS BIGINT);
DECLARE @EstF1099        BIGINT = CAST(@ReturnCount * 0.97 AS BIGINT);
DECLARE @EstCapGains     BIGINT = CAST(@ReturnCount * 0.40 * 6 AS BIGINT);
DECLARE @EstSchC         BIGINT = CAST(@ReturnCount * 0.15 AS BIGINT);
DECLARE @EstSchCExp      BIGINT = @EstSchC * 33;
DECLARE @EstCharity      BIGINT = CAST(@ReturnCount * 0.30 * 5 AS BIGINT);
DECLARE @EstAudit        BIGINT = @ReturnCount * 5;
DECLARE @EstSchE         BIGINT = CAST(@ReturnCount * 0.10 * 1.5 AS BIGINT);
DECLARE @EstSchEInc      BIGINT = @EstSchE * 4;
DECLARE @EstSchB         BIGINT = CAST(@ReturnCount * 2.5 AS BIGINT);
DECLARE @EstDocs         BIGINT = CAST(@ReturnCount * 5 AS BIGINT);
DECLARE @EstTotal        BIGINT = @EstFormLines + @EstStateFLI + @EstEFile + @EstEFileHist
    + @EstW2 + @EstF1099 + @EstCapGains + @EstSchC + @EstSchCExp + @EstCharity
    + @EstAudit + @EstSchE + @EstSchEInc + @EstSchB + @EstDocs + @EstStateReturns;
DECLARE @EstSizeGB       DECIMAL(10,1) = @EstTotal * 0.15 / 1000000000.0;  -- ~150 bytes/row avg compressed

PRINT 'Estimated output (proportional to TaxReturns):';
PRINT CONCAT('   Total rows:   ~', FORMAT(@EstTotal, 'N0'));
PRINT CONCAT('   Estimated DB: ~', FORMAT(@EstSizeGB, 'N1'), ' GB compressed');
PRINT CONCAT('   Avg returns per customer: ', FORMAT(CAST(@ReturnCount AS FLOAT) / NULLIF(@CustomerCount, 0), 'N1'));
PRINT CONCAT('   Avg returns per pro:      ', FORMAT(CAST(@ReturnCount AS FLOAT) / NULLIF(@ProfCount, 0), 'N1'));
PRINT '';

-- ============================================================================
-- HELPER: Numbers/Tally table for row multiplication
-- ============================================================================
IF OBJECT_ID('tempdb..#Numbers') IS NOT NULL DROP TABLE #Numbers;

;WITH E1(N) AS (SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1
    UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1
    UNION ALL SELECT 1 UNION ALL SELECT 1),
E2(N) AS (SELECT 1 FROM E1 a CROSS JOIN E1 b),  -- 100
E4(N) AS (SELECT 1 FROM E2 a CROSS JOIN E2 b)   -- 10,000
SELECT TOP 10000 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS N
INTO #Numbers
FROM E4;

CREATE CLUSTERED INDEX CIX_Numbers ON #Numbers(N);
GO

-- ============================================================================
-- STEP 1: Seed TaxForms & FormLineDefinitions (Reference Data)
-- ============================================================================

IF NOT EXISTS (SELECT 1 FROM TaxForms)
BEGIN
    PRINT '▶ Seeding TaxForms reference data...';

    -- Insert form definitions for each tax year
    INSERT INTO TaxForms (FormNumber, FormName, TaxYear, Version)
    SELECT f.FormNumber, f.FormName, y.TaxYear, f.Version
    FROM (VALUES
        ('1040',       'U.S. Individual Income Tax Return',        '2025-01'),
        ('Schedule A', 'Itemized Deductions',                      '2025-01'),
        ('Schedule B', 'Interest and Ordinary Dividends',          '2025-01'),
        ('Schedule C', 'Profit or Loss From Business',             '2025-01'),
        ('Schedule D', 'Capital Gains and Losses',                 '2025-01'),
        ('Schedule E', 'Supplemental Income and Loss',             '2025-01'),
        ('Schedule SE','Self-Employment Tax',                      '2025-01'),
        ('Schedule 1', 'Additional Income and Adjustments',        '2025-01'),
        ('Schedule 2', 'Additional Taxes',                         '2025-01'),
        ('Schedule 3', 'Additional Credits and Payments',          '2025-01'),
        ('Form 8812', 'Credits for Qualifying Children',           '2025-01'),
        ('Form 8863', 'Education Credits',                         '2025-01'),
        ('Form 8889', 'Health Savings Accounts',                   '2025-01'),
        ('Form 8959', 'Additional Medicare Tax',                   '2025-01'),
        ('Form 8960', 'Net Investment Income Tax',                 '2025-01')
    ) AS f(FormNumber, FormName, Version)
    CROSS JOIN (
        SELECT DISTINCT TaxYear FROM TaxReturns
    ) AS y;

    DECLARE @TaxFormsCount BIGINT = (SELECT COUNT_BIG(*) FROM TaxForms);
    PRINT CONCAT('   TaxForms seeded: ', @TaxFormsCount, ' rows');

    -- Insert line definitions for Form 1040
    DECLARE @F1040 INT;
    SELECT @F1040 = FormId FROM TaxForms WHERE FormNumber = '1040' AND TaxYear = 2025;

    INSERT INTO FormLineDefinitions (FormId, LineNumber, Description, DataType, IsRequired, SortOrder)
    VALUES
        (@F1040, '1',    'Wages, salaries, tips (W-2 box 1)',                'currency', 1, 1),
        (@F1040, '2a',   'Tax-exempt interest',                              'currency', 0, 2),
        (@F1040, '2b',   'Taxable interest',                                 'currency', 0, 3),
        (@F1040, '3a',   'Qualified dividends',                              'currency', 0, 4),
        (@F1040, '3b',   'Ordinary dividends',                               'currency', 0, 5),
        (@F1040, '4a',   'IRA distributions',                                'currency', 0, 6),
        (@F1040, '4b',   'IRA distributions taxable',                        'currency', 0, 7),
        (@F1040, '5a',   'Pensions and annuities',                           'currency', 0, 8),
        (@F1040, '5b',   'Pensions and annuities taxable',                   'currency', 0, 9),
        (@F1040, '6a',   'Social security benefits',                         'currency', 0, 10),
        (@F1040, '6b',   'Social security benefits taxable',                 'currency', 0, 11),
        (@F1040, '7',    'Capital gain or loss',                             'currency', 0, 12),
        (@F1040, '8',    'Other income from Schedule 1',                     'currency', 0, 13),
        (@F1040, '9',    'Total income',                                     'currency', 1, 14),
        (@F1040, '10',   'Adjustments to income from Schedule 1',            'currency', 0, 15),
        (@F1040, '11',   'Adjusted gross income',                            'currency', 1, 16),
        (@F1040, '12',   'Standard deduction or itemized deductions',        'currency', 1, 17),
        (@F1040, '13',   'Qualified business income deduction',              'currency', 0, 18),
        (@F1040, '14',   'Total deductions',                                 'currency', 1, 19),
        (@F1040, '15',   'Taxable income',                                   'currency', 1, 20),
        (@F1040, '16',   'Tax',                                              'currency', 1, 21),
        (@F1040, '24',   'Total tax',                                        'currency', 1, 22),
        (@F1040, '25a',  'Federal income tax withheld (W-2)',                'currency', 1, 23),
        (@F1040, '25d',  'Total federal tax withheld',                       'currency', 1, 24),
        (@F1040, '33',   'Total payments',                                   'currency', 1, 25),
        (@F1040, '34',   'Overpaid',                                         'currency', 0, 26),
        (@F1040, '35a',  'Refund',                                           'currency', 0, 27),
        (@F1040, '37',   'Amount you owe',                                   'currency', 0, 28);

    DECLARE @FLDCount BIGINT = (SELECT COUNT_BIG(*) FROM FormLineDefinitions);
    PRINT CONCAT('   FormLineDefinitions seeded: ', @FLDCount, ' rows');
END
ELSE
    PRINT '⏭ TaxForms already populated - skipping';
GO

-- ============================================================================
-- STEP 2: Generate FormLineItems (P0 - LARGEST TABLE)
-- ============================================================================
-- Generates ~28 lines × 47M returns = ~1.3 billion rows
-- Uses a batch approach to avoid log bloat.

IF NOT EXISTS (SELECT 1 FROM FormLineItems)
BEGIN
    PRINT '';
    PRINT '▶ Generating FormLineItems (Form 1040 lines for every return)...';
    PRINT '   This is the largest table — may take 30-60 minutes.';

    DECLARE @BatchSize INT = 500000;
    DECLARE @MinReturn INT, @MaxReturn INT, @BatchStart INT;
    DECLARE @RowsInserted BIGINT = 0;
    DECLARE @StartTime DATETIME2 = SYSUTCDATETIME();

    SELECT @MinReturn = MIN(ReturnId), @MaxReturn = MAX(ReturnId) FROM TaxReturns;
    SET @BatchStart = @MinReturn;

    WHILE @BatchStart <= @MaxReturn
    BEGIN
        INSERT INTO FormLineItems (ReturnId, TaxYear, FormNumber, LineNumber, LineDescription, Amount, IsCalculated)
        SELECT
            tr.ReturnId,
            tr.TaxYear,
            '1040',
            v.LineNumber,
            v.LineDescription,
            CASE v.LineNumber
                -- Income lines (derived from TaxReturns financial data)
                WHEN '1'   THEN CAST(tr.GrossIncome * 0.72 AS DECIMAL(18,2))
                WHEN '2a'  THEN CAST(tr.GrossIncome * 0.003 AS DECIMAL(18,2))
                WHEN '2b'  THEN CAST(tr.GrossIncome * 0.018 AS DECIMAL(18,2))
                WHEN '3a'  THEN CAST(tr.GrossIncome * 0.012 AS DECIMAL(18,2))
                WHEN '3b'  THEN CAST(tr.GrossIncome * 0.020 AS DECIMAL(18,2))
                WHEN '4a'  THEN CASE WHEN tr.ReturnId % 5 = 0 THEN CAST(tr.GrossIncome * 0.05 AS DECIMAL(18,2)) ELSE 0 END
                WHEN '4b'  THEN CASE WHEN tr.ReturnId % 5 = 0 THEN CAST(tr.GrossIncome * 0.04 AS DECIMAL(18,2)) ELSE 0 END
                WHEN '5a'  THEN CASE WHEN tr.ReturnId % 8 = 0 THEN CAST(tr.GrossIncome * 0.08 AS DECIMAL(18,2)) ELSE 0 END
                WHEN '5b'  THEN CASE WHEN tr.ReturnId % 8 = 0 THEN CAST(tr.GrossIncome * 0.06 AS DECIMAL(18,2)) ELSE 0 END
                WHEN '6a'  THEN CASE WHEN tr.ReturnId % 6 = 0 THEN CAST(tr.GrossIncome * 0.04 AS DECIMAL(18,2)) ELSE 0 END
                WHEN '6b'  THEN CASE WHEN tr.ReturnId % 6 = 0 THEN CAST(tr.GrossIncome * 0.03 AS DECIMAL(18,2)) ELSE 0 END
                WHEN '7'   THEN CASE WHEN tr.ReturnId % 3 = 0 THEN CAST(tr.GrossIncome * 0.02 AS DECIMAL(18,2)) ELSE 0 END
                WHEN '8'   THEN CAST(tr.GrossIncome * 0.01 AS DECIMAL(18,2))
                WHEN '9'   THEN CAST(tr.GrossIncome AS DECIMAL(18,2))
                WHEN '10'  THEN CAST((tr.GrossIncome - tr.AdjustedGrossIncome) AS DECIMAL(18,2))
                WHEN '11'  THEN CAST(tr.AdjustedGrossIncome AS DECIMAL(18,2))
                WHEN '12'  THEN CAST(tr.TotalDeductions AS DECIMAL(18,2))
                WHEN '13'  THEN CASE WHEN tr.ReturnId % 7 = 0 THEN CAST(tr.TaxableIncome * 0.02 AS DECIMAL(18,2)) ELSE 0 END
                WHEN '14'  THEN CAST(tr.TotalDeductions AS DECIMAL(18,2))
                WHEN '15'  THEN CAST(tr.TaxableIncome AS DECIMAL(18,2))
                WHEN '16'  THEN CAST(tr.TaxLiability AS DECIMAL(18,2))
                WHEN '24'  THEN CAST(tr.TaxLiability AS DECIMAL(18,2))
                WHEN '25a' THEN CAST(tr.TotalWithheld AS DECIMAL(18,2))
                WHEN '25d' THEN CAST(tr.TotalWithheld AS DECIMAL(18,2))
                WHEN '33'  THEN CAST(tr.TotalWithheld AS DECIMAL(18,2))
                WHEN '34'  THEN CAST(tr.RefundAmount AS DECIMAL(18,2))
                WHEN '35a' THEN CAST(tr.RefundAmount AS DECIMAL(18,2))
                WHEN '37'  THEN CAST(tr.AmountOwed AS DECIMAL(18,2))
                ELSE 0
            END,
            CASE WHEN v.LineNumber IN ('9','10','11','14','15','16','24','25d','33','34','35a','37') THEN 1 ELSE 0 END
        FROM TaxReturns tr
        CROSS JOIN (VALUES
            ('1',   'Wages, salaries, tips'),
            ('2a',  'Tax-exempt interest'),
            ('2b',  'Taxable interest'),
            ('3a',  'Qualified dividends'),
            ('3b',  'Ordinary dividends'),
            ('4a',  'IRA distributions'),
            ('4b',  'IRA distributions taxable'),
            ('5a',  'Pensions and annuities'),
            ('5b',  'Pensions taxable'),
            ('6a',  'Social security benefits'),
            ('6b',  'Social security taxable'),
            ('7',   'Capital gain or loss'),
            ('8',   'Other income'),
            ('9',   'Total income'),
            ('10',  'Adjustments to income'),
            ('11',  'Adjusted gross income'),
            ('12',  'Standard/itemized deductions'),
            ('13',  'QBI deduction'),
            ('14',  'Total deductions'),
            ('15',  'Taxable income'),
            ('16',  'Tax'),
            ('24',  'Total tax'),
            ('25a', 'Federal tax withheld (W-2)'),
            ('25d', 'Total federal tax withheld'),
            ('33',  'Total payments'),
            ('34',  'Overpaid'),
            ('35a', 'Refund'),
            ('37',  'Amount you owe')
        ) AS v(LineNumber, LineDescription)
        WHERE tr.ReturnId >= @BatchStart
          AND tr.ReturnId < @BatchStart + @BatchSize;

        SET @RowsInserted += @@ROWCOUNT;
        
        IF @RowsInserted % 10000000 < @BatchSize * 28
            PRINT CONCAT('   Progress: ', FORMAT(@RowsInserted, 'N0'), ' rows inserted (',
                FORMAT(DATEDIFF(SECOND, @StartTime, SYSUTCDATETIME()), 'N0'), 's elapsed)');

        SET @BatchStart += @BatchSize;
    END

    PRINT CONCAT('   ✅ FormLineItems complete: ', FORMAT(@RowsInserted, 'N0'), ' rows in ',
        FORMAT(DATEDIFF(SECOND, @StartTime, SYSUTCDATETIME()), 'N0'), ' seconds');
END
ELSE
    PRINT '⏭ FormLineItems already populated - skipping';
GO

-- ============================================================================
-- STEP 3: Generate StateTaxReturns (P0)
-- ============================================================================
-- ~89% of federal returns get a state return (excludes no-income-tax states)

IF NOT EXISTS (SELECT 1 FROM StateTaxReturns)
BEGIN
    PRINT '';
    PRINT '▶ Generating StateTaxReturns...';

    DECLARE @StateStartTime DATETIME2 = SYSUTCDATETIME();

    -- States with no income tax: AK, FL, NV, NH, SD, TN, TX, WA, WY
    -- For returns in those states, no state return is filed.
    -- For all others, generate a state return using the customer's state.

    DECLARE @BatchSizeST INT = 1000000;
    DECLARE @MinRetST INT, @MaxRetST INT, @BatchStartST INT;
    DECLARE @RowsST BIGINT = 0;

    SELECT @MinRetST = MIN(ReturnId), @MaxRetST = MAX(ReturnId) FROM TaxReturns;
    SET @BatchStartST = @MinRetST;

    -- State tax rates (simplified) and form numbers
    IF OBJECT_ID('tempdb..#StateTaxRates') IS NOT NULL DROP TABLE #StateTaxRates;
    CREATE TABLE #StateTaxRates (
        StateAbbr CHAR(2) PRIMARY KEY,
        TaxRate DECIMAL(5,3),
        FormNumber NVARCHAR(50)
    );
    INSERT INTO #StateTaxRates VALUES
        ('AL',0.050,'AL 40'),('AZ',0.045,'AZ 140'),('AR',0.055,'AR 1000F'),
        ('CA',0.093,'CA 540'),('CO',0.044,'CO 104'),('CT',0.070,'CT 1040'),
        ('DE',0.066,'DE 200-01'),('GA',0.055,'GA 500'),('HI',0.090,'HI N-11'),
        ('ID',0.058,'ID 40'),('IL',0.050,'IL 1040'),('IN',0.032,'IN IT-40'),
        ('IA',0.060,'IA 1040'),('KS',0.057,'KS K-40'),('KY',0.050,'KY 740'),
        ('LA',0.043,'LA IT-540'),('ME',0.075,'ME 1040'),('MD',0.058,'MD 502'),
        ('MA',0.050,'MA 1'),('MI',0.043,'MI 1040'),('MN',0.099,'MN M1'),
        ('MS',0.050,'MS 80-105'),('MO',0.054,'MO 1040'),('MT',0.069,'MT 2'),
        ('NE',0.068,'NE 1040N'),('NJ',0.108,'NJ 1040'),('NM',0.059,'NM PIT-1'),
        ('NY',0.109,'NY IT-201'),('NC',0.053,'NC D-400'),('ND',0.029,'ND ND-1'),
        ('OH',0.040,'OH IT 1040'),('OK',0.048,'OK 511'),('OR',0.099,'OR 40'),
        ('PA',0.031,'PA 40'),('RI',0.060,'RI 1040'),('SC',0.065,'SC 1040'),
        ('UT',0.049,'UT TC-40'),('VT',0.088,'VT IN-111'),('VA',0.058,'VA 760'),
        ('WV',0.065,'WV IT-140'),('WI',0.076,'WI 1'),('DC',0.095,'DC D-40');

    WHILE @BatchStartST <= @MaxRetST
    BEGIN
        INSERT INTO StateTaxReturns (
            FederalReturnId, TaxYear, StateCode, ResidentType, StateFormNumber,
            StateGrossIncome, StateTaxableIncome, StateTaxLiability,
            StateWithheld, StateRefund, StateAmountOwed, Status, FilingDate
        )
        SELECT
            tr.ReturnId,
            tr.TaxYear,
            c.StateAbbr,
            'Resident',
            st.FormNumber,
            tr.GrossIncome,
            tr.TaxableIncome,
            CAST(tr.TaxableIncome * st.TaxRate AS DECIMAL(14,2)),
            CAST(tr.TaxableIncome * st.TaxRate * 0.92 AS DECIMAL(14,2)),  -- 92% withholding
            CASE WHEN tr.TaxableIncome * st.TaxRate * 0.92 > tr.TaxableIncome * st.TaxRate
                 THEN CAST(tr.TaxableIncome * st.TaxRate * 0.92 - tr.TaxableIncome * st.TaxRate AS DECIMAL(14,2))
                 ELSE 0 END,
            CASE WHEN tr.TaxableIncome * st.TaxRate * 0.92 < tr.TaxableIncome * st.TaxRate
                 THEN CAST(tr.TaxableIncome * st.TaxRate - tr.TaxableIncome * st.TaxRate * 0.92 AS DECIMAL(14,2))
                 ELSE 0 END,
            tr.Status,
            ISNULL(tr.FilingDate, tr.CreatedAt)
        FROM TaxReturns tr
        INNER JOIN Customers c ON c.CustomerId = tr.CustomerId
        INNER JOIN #StateTaxRates st ON st.StateAbbr = c.StateAbbr
        WHERE tr.ReturnId >= @BatchStartST
          AND tr.ReturnId < @BatchStartST + @BatchSizeST;

        SET @RowsST += @@ROWCOUNT;

        IF @RowsST % 5000000 < @BatchSizeST
            PRINT CONCAT('   Progress: ', FORMAT(@RowsST, 'N0'), ' state returns');

        SET @BatchStartST += @BatchSizeST;
    END

    PRINT CONCAT('   ✅ StateTaxReturns complete: ', FORMAT(@RowsST, 'N0'), ' rows in ',
        FORMAT(DATEDIFF(SECOND, @StateStartTime, SYSUTCDATETIME()), 'N0'), 's');

    DROP TABLE #StateTaxRates;
END
ELSE
    PRINT '⏭ StateTaxReturns already populated - skipping';
GO

-- ============================================================================
-- STEP 4: Generate StateFormLineItems (P0)
-- ============================================================================
-- ~12 lines per state return

IF NOT EXISTS (SELECT 1 FROM StateFormLineItems)
BEGIN
    PRINT '';
    PRINT '▶ Generating StateFormLineItems...';

    DECLARE @SFLStartTime DATETIME2 = SYSUTCDATETIME();
    DECLARE @BatchSizeSFL INT = 500000;
    DECLARE @MinSR BIGINT, @MaxSR BIGINT, @BatchStartSFL BIGINT;
    DECLARE @RowsSFL BIGINT = 0;

    SELECT @MinSR = MIN(StateReturnId), @MaxSR = MAX(StateReturnId) FROM StateTaxReturns;
    SET @BatchStartSFL = @MinSR;

    WHILE @BatchStartSFL <= @MaxSR
    BEGIN
        INSERT INTO StateFormLineItems (StateReturnId, TaxYear, FormNumber, LineNumber, LineDescription, Amount)
        SELECT
            sr.StateReturnId,
            sr.TaxYear,
            sr.StateFormNumber,
            v.LineNumber,
            v.Description,
            CASE v.LineNumber
                WHEN '1'  THEN sr.StateGrossIncome
                WHEN '2'  THEN CAST(sr.StateGrossIncome * 0.03 AS DECIMAL(18,2))    -- Adjustments
                WHEN '3'  THEN CAST(sr.StateGrossIncome * 0.97 AS DECIMAL(18,2))    -- State AGI
                WHEN '4'  THEN CAST(sr.StateGrossIncome * 0.08 AS DECIMAL(18,2))    -- State deductions
                WHEN '5'  THEN CAST(sr.StateGrossIncome * 0.02 AS DECIMAL(18,2))    -- Exemptions
                WHEN '6'  THEN sr.StateTaxableIncome
                WHEN '7'  THEN sr.StateTaxLiability
                WHEN '8'  THEN CAST(sr.StateTaxLiability * 0.02 AS DECIMAL(18,2))   -- Credits
                WHEN '9'  THEN CAST(sr.StateTaxLiability * 0.98 AS DECIMAL(18,2))   -- Net tax
                WHEN '10' THEN sr.StateWithheld
                WHEN '11' THEN sr.StateRefund
                WHEN '12' THEN sr.StateAmountOwed
            END
        FROM StateTaxReturns sr
        CROSS JOIN (VALUES
            ('1',  'Federal adjusted gross income'),
            ('2',  'State adjustments'),
            ('3',  'State adjusted gross income'),
            ('4',  'State deductions'),
            ('5',  'Exemptions'),
            ('6',  'State taxable income'),
            ('7',  'State tax'),
            ('8',  'State credits'),
            ('9',  'Net state tax'),
            ('10', 'State tax withheld'),
            ('11', 'State refund'),
            ('12', 'State amount owed')
        ) AS v(LineNumber, Description)
        WHERE sr.StateReturnId >= @BatchStartSFL
          AND sr.StateReturnId < @BatchStartSFL + @BatchSizeSFL;

        SET @RowsSFL += @@ROWCOUNT;

        IF @RowsSFL % 10000000 < @BatchSizeSFL * 12
            PRINT CONCAT('   Progress: ', FORMAT(@RowsSFL, 'N0'), ' state form line items');

        SET @BatchStartSFL += @BatchSizeSFL;
    END

    PRINT CONCAT('   ✅ StateFormLineItems complete: ', FORMAT(@RowsSFL, 'N0'), ' rows in ',
        FORMAT(DATEDIFF(SECOND, @SFLStartTime, SYSUTCDATETIME()), 'N0'), 's');
END
ELSE
    PRINT '⏭ StateFormLineItems already populated - skipping';
GO

-- ============================================================================
-- STEP 5: Generate EFileSubmissions (P0)
-- ============================================================================
-- Every return with Status in ('Filed','Accepted','Rejected') gets an e-file record.
-- ~5% get a second submission (resubmission after rejection).

IF NOT EXISTS (SELECT 1 FROM EFileSubmissions)
BEGIN
    PRINT '';
    PRINT '▶ Generating EFileSubmissions...';

    DECLARE @EFStartTime DATETIME2 = SYSUTCDATETIME();
    DECLARE @BatchSizeEF INT = 1000000;
    DECLARE @MinRetEF INT, @MaxRetEF INT, @BatchStartEF INT;
    DECLARE @RowsEF BIGINT = 0;

    SELECT @MinRetEF = MIN(ReturnId), @MaxRetEF = MAX(ReturnId) FROM TaxReturns;
    SET @BatchStartEF = @MinRetEF;

    WHILE @BatchStartEF <= @MaxRetEF
    BEGIN
        -- Original submissions
        INSERT INTO EFileSubmissions (
            ReturnId, TaxYear, SubmissionType, TransmitterControlCode, SubmissionIdIRS,
            SubmittedAt, SubmittedBy, TransmissionMethod, ERO_EFIN,
            Status, StatusUpdatedAt, AcknowledgmentReceived,
            AcceptanceDate, RejectionCode, RejectionDescription, RejectionDate
        )
        SELECT
            tr.ReturnId,
            tr.TaxYear,
            CASE WHEN tr.IsAmended = 1 THEN 'Amended' 
                 WHEN tr.IsExtension = 1 THEN 'Extension'
                 ELSE 'Original' END,
            CONCAT('TCC', RIGHT('00000' + CAST(tr.BranchId AS VARCHAR), 5)),
            CONCAT('IRS-', tr.TaxYear, '-', RIGHT('000000000' + CAST(tr.ReturnId AS VARCHAR), 9)),
            DATEADD(HOUR, -(tr.ReturnId % 720), ISNULL(tr.FilingDate, tr.CreatedAt)),
            tr.ProfessionalId,
            'MeF',
            RIGHT('000000' + CAST(tr.BranchId AS VARCHAR), 6),
            CASE tr.Status
                WHEN 'Accepted' THEN 'Accepted'
                WHEN 'Rejected' THEN 'Rejected'
                WHEN 'Filed'    THEN 'Accepted'
                WHEN 'In Progress' THEN 'Pending'
                ELSE 'Pending'
            END,
            DATEADD(HOUR, tr.ReturnId % 48, ISNULL(tr.FilingDate, tr.CreatedAt)),
            CASE WHEN tr.Status IN ('Accepted','Rejected','Filed') THEN 1 ELSE 0 END,
            CASE WHEN tr.Status IN ('Accepted','Filed') THEN DATEADD(DAY, 1 + tr.ReturnId % 3, ISNULL(tr.FilingDate, tr.CreatedAt)) END,
            CASE WHEN tr.Status = 'Rejected' 
                 THEN CONCAT('R', RIGHT('0000' + CAST(tr.ReturnId % 200 AS VARCHAR), 4)) END,
            CASE WHEN tr.Status = 'Rejected' THEN 'IRS rejection: data validation error' END,
            CASE WHEN tr.Status = 'Rejected' THEN DATEADD(DAY, 1, ISNULL(tr.FilingDate, tr.CreatedAt)) END
        FROM TaxReturns tr
        WHERE tr.Status IN ('Filed', 'Accepted', 'Rejected', 'In Progress', 'Draft')
          AND tr.ReturnId >= @BatchStartEF
          AND tr.ReturnId < @BatchStartEF + @BatchSizeEF;

        SET @RowsEF += @@ROWCOUNT;

        IF @RowsEF % 5000000 < @BatchSizeEF
            PRINT CONCAT('   Progress: ', FORMAT(@RowsEF, 'N0'), ' e-file submissions');

        SET @BatchStartEF += @BatchSizeEF;
    END

    PRINT CONCAT('   ✅ EFileSubmissions complete: ', FORMAT(@RowsEF, 'N0'), ' rows in ',
        FORMAT(DATEDIFF(SECOND, @EFStartTime, SYSUTCDATETIME()), 'N0'), 's');
END
ELSE
    PRINT '⏭ EFileSubmissions already populated - skipping';
GO

-- ============================================================================
-- STEP 6: Generate EFileStatusHistory (P0)
-- ============================================================================
-- Each submission gets 2-4 status transitions.

IF NOT EXISTS (SELECT 1 FROM EFileStatusHistory)
BEGIN
    PRINT '';
    PRINT '▶ Generating EFileStatusHistory...';

    DECLARE @EHStartTime DATETIME2 = SYSUTCDATETIME();
    DECLARE @BatchSizeEH INT = 500000;
    DECLARE @MinSubEH BIGINT, @MaxSubEH BIGINT, @BatchStartEH BIGINT;
    DECLARE @RowsEH BIGINT = 0;

    SELECT @MinSubEH = MIN(SubmissionId), @MaxSubEH = MAX(SubmissionId) FROM EFileSubmissions;
    SET @BatchStartEH = @MinSubEH;

    WHILE @BatchStartEH <= @MaxSubEH
    BEGIN
        -- Transition 1: NULL → Pending (submitted)
        INSERT INTO EFileStatusHistory (SubmissionId, TaxYear, PreviousStatus, NewStatus, StatusMessage, ChangedAt, ChangedBy)
        SELECT SubmissionId, TaxYear, NULL, 'Pending', 'Submission received by IRS MeF system',
               SubmittedAt, SubmittedBy
        FROM EFileSubmissions
        WHERE SubmissionId >= @BatchStartEH AND SubmissionId < @BatchStartEH + @BatchSizeEH;

        SET @RowsEH += @@ROWCOUNT;

        -- Transition 2: Pending → Processing
        INSERT INTO EFileStatusHistory (SubmissionId, TaxYear, PreviousStatus, NewStatus, StatusMessage, ChangedAt, ChangedBy)
        SELECT SubmissionId, TaxYear, 'Pending', 'Processing', 'Return under review',
               DATEADD(HOUR, 2, SubmittedAt), SubmittedBy
        FROM EFileSubmissions
        WHERE Status IN ('Accepted','Rejected')
          AND SubmissionId >= @BatchStartEH AND SubmissionId < @BatchStartEH + @BatchSizeEH;

        SET @RowsEH += @@ROWCOUNT;

        -- Transition 3: Processing → Accepted or Rejected
        INSERT INTO EFileStatusHistory (SubmissionId, TaxYear, PreviousStatus, NewStatus, StatusMessage, ChangedAt, ChangedBy)
        SELECT SubmissionId, TaxYear, 'Processing', Status,
               CASE Status WHEN 'Accepted' THEN 'Return accepted by IRS' ELSE CONCAT('Rejected: ', RejectionDescription) END,
               COALESCE(AcceptanceDate, RejectionDate, DATEADD(DAY, 1, SubmittedAt)), SubmittedBy
        FROM EFileSubmissions
        WHERE Status IN ('Accepted','Rejected')
          AND SubmissionId >= @BatchStartEH AND SubmissionId < @BatchStartEH + @BatchSizeEH;

        SET @RowsEH += @@ROWCOUNT;

        IF @RowsEH % 5000000 < @BatchSizeEH * 3
            PRINT CONCAT('   Progress: ', FORMAT(@RowsEH, 'N0'), ' status history records');

        SET @BatchStartEH += @BatchSizeEH;
    END

    PRINT CONCAT('   ✅ EFileStatusHistory complete: ', FORMAT(@RowsEH, 'N0'), ' rows in ',
        FORMAT(DATEDIFF(SECOND, @EHStartTime, SYSUTCDATETIME()), 'N0'), 's');
END
ELSE
    PRINT '⏭ EFileStatusHistory already populated - skipping';
GO

-- ============================================================================
-- STEP 7: Generate W2Documents (P1)
-- ============================================================================
-- Most returns have 1-2 W-2s; higher-income returns may have 2-3.

IF NOT EXISTS (SELECT 1 FROM W2Documents)
BEGIN
    PRINT '';
    PRINT '▶ Generating W2Documents...';

    DECLARE @W2StartTime DATETIME2 = SYSUTCDATETIME();
    DECLARE @BatchSizeW2 INT = 500000;
    DECLARE @MinRetW2 INT, @MaxRetW2 INT, @BatchStartW2 INT;
    DECLARE @RowsW2 BIGINT = 0;

    SELECT @MinRetW2 = MIN(ReturnId), @MaxRetW2 = MAX(ReturnId) FROM TaxReturns;
    SET @BatchStartW2 = @MinRetW2;

    -- Employer name pool
    IF OBJECT_ID('tempdb..#Employers') IS NOT NULL DROP TABLE #Employers;
    CREATE TABLE #Employers (EmpId INT PRIMARY KEY, EmpName NVARCHAR(200), EmpEIN CHAR(10));
    INSERT INTO #Employers VALUES
        (1,'Acme Corporation','12-3456789'),(2,'TechVentures Inc','23-4567890'),
        (3,'GlobalHealth Systems','34-5678901'),(4,'Pinnacle Financial','45-6789012'),
        (5,'Metro Services LLC','56-7890123'),(6,'Summit Manufacturing','67-8901234'),
        (7,'Horizon Energy Corp','78-9012345'),(8,'Pacific Trading Co','89-0123456'),
        (9,'National Education Group','90-1234567'),(10,'Liberty Consulting','01-2345678'),
        (11,'Atlas Engineering','11-1111111'),(12,'Beacon Healthcare','22-2222222'),
        (13,'Cascade Logistics','33-3333333'),(14,'Delta Aerospace','44-4444444'),
        (15,'Evergreen Media','55-5555555'),(16,'Falcon Industries','66-6666666'),
        (17,'Guardian Insurance','77-7777777'),(18,'Harbor Shipping','88-8888888'),
        (19,'Ironclad Defense','99-9999999'),(20,'Jupiter Tech','10-1010101');

    WHILE @BatchStartW2 <= @MaxRetW2
    BEGIN
        -- Primary W-2 for every return
        INSERT INTO W2Documents (
            ReturnId, TaxYear, EmployerEIN, EmployerName,
            WagesBox1, FederalWithheldBox2,
            SocialSecurityWagesBox3, SocialSecurityTaxBox4,
            MedicareWagesBox5, MedicareTaxBox6,
            RetirementPlan, StateWagesBox16, StateWithheldBox17,
            VerificationStatus
        )
        SELECT
            tr.ReturnId,
            tr.TaxYear,
            e.EmpEIN,
            e.EmpName,
            CAST(tr.GrossIncome * 0.72 AS DECIMAL(14,2)),                       -- Wages
            CAST(tr.TotalWithheld * 0.85 AS DECIMAL(14,2)),                     -- Federal withheld
            CAST(CASE WHEN tr.GrossIncome * 0.72 > 168600 THEN 168600           -- SS wage cap
                 ELSE tr.GrossIncome * 0.72 END AS DECIMAL(14,2)),
            CAST(CASE WHEN tr.GrossIncome * 0.72 > 168600 THEN 168600 * 0.062
                 ELSE tr.GrossIncome * 0.72 * 0.062 END AS DECIMAL(14,2)),      -- SS tax
            CAST(tr.GrossIncome * 0.72 AS DECIMAL(14,2)),                       -- Medicare wages
            CAST(tr.GrossIncome * 0.72 * 0.0145 AS DECIMAL(14,2)),             -- Medicare tax
            CASE WHEN tr.ReturnId % 3 < 2 THEN 1 ELSE 0 END,                   -- 67% have retirement
            CAST(tr.GrossIncome * 0.72 AS DECIMAL(14,2)),                       -- State wages = federal
            CAST(tr.TotalWithheld * 0.15 AS DECIMAL(14,2)),                     -- ~15% of withholding is state
            'Verified'
        FROM TaxReturns tr
        CROSS APPLY (SELECT EmpName, EmpEIN FROM #Employers WHERE EmpId = (tr.ReturnId % 20) + 1) e
        WHERE tr.ReturnId >= @BatchStartW2
          AND tr.ReturnId < @BatchStartW2 + @BatchSizeW2;

        SET @RowsW2 += @@ROWCOUNT;

        -- Second W-2 for ~35% of returns (dual-income households, job changers)
        INSERT INTO W2Documents (
            ReturnId, TaxYear, EmployerEIN, EmployerName,
            WagesBox1, FederalWithheldBox2,
            SocialSecurityWagesBox3, SocialSecurityTaxBox4,
            MedicareWagesBox5, MedicareTaxBox6,
            RetirementPlan, StateWagesBox16, StateWithheldBox17,
            VerificationStatus
        )
        SELECT
            tr.ReturnId,
            tr.TaxYear,
            e2.EmpEIN,
            e2.EmpName,
            CAST(tr.GrossIncome * 0.28 AS DECIMAL(14,2)),
            CAST(tr.TotalWithheld * 0.15 AS DECIMAL(14,2)),
            CAST(tr.GrossIncome * 0.28 AS DECIMAL(14,2)),
            CAST(tr.GrossIncome * 0.28 * 0.062 AS DECIMAL(14,2)),
            CAST(tr.GrossIncome * 0.28 AS DECIMAL(14,2)),
            CAST(tr.GrossIncome * 0.28 * 0.0145 AS DECIMAL(14,2)),
            CASE WHEN tr.ReturnId % 5 < 2 THEN 1 ELSE 0 END,
            CAST(tr.GrossIncome * 0.28 AS DECIMAL(14,2)),
            CAST(tr.TotalWithheld * 0.05 AS DECIMAL(14,2)),
            'Verified'
        FROM TaxReturns tr
        CROSS APPLY (SELECT EmpName, EmpEIN FROM #Employers WHERE EmpId = ((tr.ReturnId + 7) % 20) + 1) e2
        WHERE tr.ReturnId % 100 < 35  -- 35%
          AND tr.ReturnId >= @BatchStartW2
          AND tr.ReturnId < @BatchStartW2 + @BatchSizeW2;

        SET @RowsW2 += @@ROWCOUNT;

        IF @RowsW2 % 5000000 < @BatchSizeW2 * 2
            PRINT CONCAT('   Progress: ', FORMAT(@RowsW2, 'N0'), ' W-2 documents');

        SET @BatchStartW2 += @BatchSizeW2;
    END

    DROP TABLE #Employers;

    PRINT CONCAT('   ✅ W2Documents complete: ', FORMAT(@RowsW2, 'N0'), ' rows in ',
        FORMAT(DATEDIFF(SECOND, @W2StartTime, SYSUTCDATETIME()), 'N0'), 's');
END
ELSE
    PRINT '⏭ W2Documents already populated - skipping';
GO

-- ============================================================================
-- STEP 8: Generate Form1099 (P1)
-- ============================================================================
-- ~40% of returns have at least one 1099; types: INT, DIV, MISC, B, R, K

IF NOT EXISTS (SELECT 1 FROM Form1099)
BEGIN
    PRINT '';
    PRINT '▶ Generating Form1099 records...';

    DECLARE @F1099Start DATETIME2 = SYSUTCDATETIME();
    DECLARE @BatchSize1099 INT = 500000;
    DECLARE @MinRet1099 INT, @MaxRet1099 INT, @BatchStart1099 INT;
    DECLARE @Rows1099 BIGINT = 0;

    SELECT @MinRet1099 = MIN(ReturnId), @MaxRet1099 = MAX(ReturnId) FROM TaxReturns;
    SET @BatchStart1099 = @MinRet1099;

    -- Payer name pool
    IF OBJECT_ID('tempdb..#Payers') IS NOT NULL DROP TABLE #Payers;
    CREATE TABLE #Payers (PayerId INT PRIMARY KEY, PayerName NVARCHAR(200), PayerEIN CHAR(10));
    INSERT INTO #Payers VALUES
        (1,'Vanguard Group','23-1945930'),(2,'Fidelity Investments','04-3523567'),
        (3,'Charles Schwab','94-1737782'),(4,'JPMorgan Chase','13-2624428'),
        (5,'Bank of America','56-0906609'),(6,'Wells Fargo','41-0449260'),
        (7,'Morgan Stanley','36-3145972'),(8,'Goldman Sachs','13-5108880'),
        (9,'Citibank','13-5266470'),(10,'TD Ameritrade','47-0533629'),
        (11,'E*TRADE','94-2844166'),(12,'Merrill Lynch','13-5674085');

    WHILE @BatchStart1099 <= @MaxRet1099
    BEGIN
        -- 1099-INT (interest income) - ~30% of returns
        INSERT INTO Form1099 (ReturnId, TaxYear, Form1099Type, PayerEIN, PayerName, GrossAmount, DetailData)
        SELECT tr.ReturnId, tr.TaxYear, 'INT', p.PayerEIN, p.PayerName,
            CAST(tr.GrossIncome * 0.018 AS DECIMAL(14,2)),
            JSON_OBJECT('interest_income': CAST(tr.GrossIncome * 0.018 AS DECIMAL(14,2)),
                         'early_withdrawal_penalty': 0,
                         'us_savings_bond_interest': 0)
        FROM TaxReturns tr
        CROSS APPLY (SELECT PayerName, PayerEIN FROM #Payers WHERE PayerId = (tr.ReturnId % 12) + 1) p
        WHERE tr.ReturnId % 100 < 30
          AND tr.ReturnId >= @BatchStart1099 AND tr.ReturnId < @BatchStart1099 + @BatchSize1099;
        SET @Rows1099 += @@ROWCOUNT;

        -- 1099-DIV (dividends) - ~25% of returns
        INSERT INTO Form1099 (ReturnId, TaxYear, Form1099Type, PayerEIN, PayerName, GrossAmount, DetailData)
        SELECT tr.ReturnId, tr.TaxYear, 'DIV', p.PayerEIN, p.PayerName,
            CAST(tr.GrossIncome * 0.02 AS DECIMAL(14,2)),
            JSON_OBJECT('ordinary_dividends': CAST(tr.GrossIncome * 0.02 AS DECIMAL(14,2)),
                         'qualified_dividends': CAST(tr.GrossIncome * 0.012 AS DECIMAL(14,2)),
                         'capital_gain_distributions': CAST(tr.GrossIncome * 0.005 AS DECIMAL(14,2)))
        FROM TaxReturns tr
        CROSS APPLY (SELECT PayerName, PayerEIN FROM #Payers WHERE PayerId = ((tr.ReturnId + 3) % 12) + 1) p
        WHERE tr.ReturnId % 100 < 25
          AND tr.ReturnId >= @BatchStart1099 AND tr.ReturnId < @BatchStart1099 + @BatchSize1099;
        SET @Rows1099 += @@ROWCOUNT;

        -- 1099-MISC (misc income) - ~10% of returns
        INSERT INTO Form1099 (ReturnId, TaxYear, Form1099Type, PayerEIN, PayerName, GrossAmount, DetailData)
        SELECT tr.ReturnId, tr.TaxYear, 'MISC', p.PayerEIN, p.PayerName,
            CAST(tr.GrossIncome * 0.05 AS DECIMAL(14,2)),
            JSON_OBJECT('rents': 0, 'royalties': 0,
                         'other_income': CAST(tr.GrossIncome * 0.05 AS DECIMAL(14,2)),
                         'nonemployee_compensation': 0)
        FROM TaxReturns tr
        CROSS APPLY (SELECT PayerName, PayerEIN FROM #Payers WHERE PayerId = ((tr.ReturnId + 5) % 12) + 1) p
        WHERE tr.ReturnId % 100 < 10
          AND tr.ReturnId >= @BatchStart1099 AND tr.ReturnId < @BatchStart1099 + @BatchSize1099;
        SET @Rows1099 += @@ROWCOUNT;

        -- 1099-B (brokerage transactions) - ~20% of returns
        INSERT INTO Form1099 (ReturnId, TaxYear, Form1099Type, PayerEIN, PayerName, GrossAmount, DetailData)
        SELECT tr.ReturnId, tr.TaxYear, 'B', p.PayerEIN, p.PayerName,
            CAST(tr.GrossIncome * 0.15 AS DECIMAL(14,2)),
            JSON_OBJECT('proceeds': CAST(tr.GrossIncome * 0.15 AS DECIMAL(14,2)),
                         'cost_basis': CAST(tr.GrossIncome * 0.12 AS DECIMAL(14,2)),
                         'wash_sale_loss_disallowed': 0)
        FROM TaxReturns tr
        CROSS APPLY (SELECT PayerName, PayerEIN FROM #Payers WHERE PayerId = ((tr.ReturnId + 8) % 12) + 1) p
        WHERE tr.ReturnId % 100 < 20
          AND tr.ReturnId >= @BatchStart1099 AND tr.ReturnId < @BatchStart1099 + @BatchSize1099;
        SET @Rows1099 += @@ROWCOUNT;

        -- 1099-R (retirement distributions) - ~12% of returns
        INSERT INTO Form1099 (ReturnId, TaxYear, Form1099Type, PayerEIN, PayerName, GrossAmount, DetailData)
        SELECT tr.ReturnId, tr.TaxYear, 'R', p.PayerEIN, p.PayerName,
            CAST(tr.GrossIncome * 0.08 AS DECIMAL(14,2)),
            JSON_OBJECT('gross_distribution': CAST(tr.GrossIncome * 0.08 AS DECIMAL(14,2)),
                         'taxable_amount': CAST(tr.GrossIncome * 0.06 AS DECIMAL(14,2)),
                         'distribution_code': '7')
        FROM TaxReturns tr
        CROSS APPLY (SELECT PayerName, PayerEIN FROM #Payers WHERE PayerId = ((tr.ReturnId + 2) % 12) + 1) p
        WHERE tr.ReturnId % 100 < 12
          AND tr.ReturnId >= @BatchStart1099 AND tr.ReturnId < @BatchStart1099 + @BatchSize1099;
        SET @Rows1099 += @@ROWCOUNT;

        IF @Rows1099 % 5000000 < @BatchSize1099 * 5
            PRINT CONCAT('   Progress: ', FORMAT(@Rows1099, 'N0'), ' 1099 forms');

        SET @BatchStart1099 += @BatchSize1099;
    END

    DROP TABLE #Payers;

    PRINT CONCAT('   ✅ Form1099 complete: ', FORMAT(@Rows1099, 'N0'), ' rows in ',
        FORMAT(DATEDIFF(SECOND, @F1099Start, SYSUTCDATETIME()), 'N0'), 's');
END
ELSE
    PRINT '⏭ Form1099 already populated - skipping';
GO

-- ============================================================================
-- STEP 9: Generate CapitalGainTransactions (P1 - Schedule D)
-- ============================================================================
-- ~40% of returns have investments; avg 8 transactions each

IF NOT EXISTS (SELECT 1 FROM CapitalGainTransactions)
BEGIN
    PRINT '';
    PRINT '▶ Generating CapitalGainTransactions...';

    DECLARE @CGStartTime DATETIME2 = SYSUTCDATETIME();
    DECLARE @BatchSizeCG INT = 200000;
    DECLARE @MinRetCG INT, @MaxRetCG INT, @BatchStartCG INT;
    DECLARE @RowsCG BIGINT = 0;

    SELECT @MinRetCG = MIN(ReturnId), @MaxRetCG = MAX(ReturnId) FROM TaxReturns;
    SET @BatchStartCG = @MinRetCG;

    -- Security pool for realistic names
    IF OBJECT_ID('tempdb..#Securities') IS NOT NULL DROP TABLE #Securities;
    CREATE TABLE #Securities (SecId INT PRIMARY KEY, SecType NVARCHAR(50), SecName NVARCHAR(200), CUSIP NVARCHAR(20));
    INSERT INTO #Securities VALUES
        (1,'Stock','Apple Inc (AAPL)','037833100'),(2,'Stock','Microsoft Corp (MSFT)','594918104'),
        (3,'Stock','Amazon.com Inc (AMZN)','023135106'),(4,'Stock','Alphabet Inc (GOOGL)','02079K305'),
        (5,'Stock','Tesla Inc (TSLA)','88160R101'),(6,'Stock','NVIDIA Corp (NVDA)','67066G104'),
        (7,'Stock','Meta Platforms (META)','30303M102'),(8,'Stock','JPMorgan Chase (JPM)','46625H100'),
        (9,'ETF','SPDR S&P 500 ETF (SPY)','78462F103'),(10,'ETF','Vanguard Total Market (VTI)','922908769'),
        (11,'ETF','iShares Core S&P 500 (IVV)','464287200'),(12,'Bond','iShares Core US Agg (AGG)','464287440'),
        (13,'Stock','UnitedHealth (UNH)','91324P102'),(14,'Stock','Johnson & Johnson (JNJ)','478160104'),
        (15,'Crypto','Bitcoin (BTC)',NULL),(16,'Crypto','Ethereum (ETH)',NULL),
        (17,'Stock','Berkshire Hathaway (BRK.B)','084670702'),(18,'Stock','Visa Inc (V)','92826C839'),
        (19,'Mutual Fund','Vanguard 500 Index','922908363'),(20,'Mutual Fund','Fidelity Contrafund','316071109');

    WHILE @BatchStartCG <= @MaxRetCG
    BEGIN
        -- Generate 1-12 transactions per investing taxpayer (40% of returns)
        INSERT INTO CapitalGainTransactions (
            ReturnId, TaxYear, SecurityType, SecurityName, CUSIPNumber,
            DateAcquired, DateSold, Quantity, CostBasis, SaleProceeds,
            GainOrLoss, IsShortTerm, IsWashSale, BrokerName
        )
        SELECT
            tr.ReturnId,
            tr.TaxYear,
            s.SecType,
            s.SecName,
            s.CUSIP,
            DATEADD(DAY, -(365 + (tr.ReturnId * n.N) % 1800), ISNULL(tr.FilingDate, tr.CreatedAt)),  -- Acquired 1-5 years before
            DATEADD(DAY, -(30 + (tr.ReturnId * n.N) % 300), ISNULL(tr.FilingDate, tr.CreatedAt)),    -- Sold within tax year
            CAST(10 + (tr.ReturnId * n.N) % 500 AS DECIMAL(18,8)),             -- Quantity
            CAST(tr.GrossIncome * 0.01 * n.N * (0.5 + (tr.ReturnId % 10) * 0.05) AS DECIMAL(18,2)),
            CAST(tr.GrossIncome * 0.01 * n.N * (0.5 + (tr.ReturnId % 10) * 0.05) 
                 * (CASE WHEN (tr.ReturnId + n.N) % 3 = 0 THEN 0.85 ELSE 1.15 END) AS DECIMAL(18,2)),
            CAST(tr.GrossIncome * 0.01 * n.N * (0.5 + (tr.ReturnId % 10) * 0.05) 
                 * (CASE WHEN (tr.ReturnId + n.N) % 3 = 0 THEN -0.15 ELSE 0.15 END) AS DECIMAL(18,2)),
            CASE WHEN (tr.ReturnId * n.N) % 1800 < 365 THEN 1 ELSE 0 END,  -- Short-term if held < 1 year
            CASE WHEN (tr.ReturnId + n.N) % 50 = 0 THEN 1 ELSE 0 END,      -- 2% wash sales
            CASE (tr.ReturnId + n.N) % 4
                WHEN 0 THEN 'Vanguard Group'
                WHEN 1 THEN 'Charles Schwab'
                WHEN 2 THEN 'Fidelity Investments'
                ELSE 'TD Ameritrade'
            END
        FROM TaxReturns tr
        INNER JOIN #Numbers n ON n.N <= 
            CASE 
                WHEN tr.GrossIncome > 200000 THEN 12  -- High income: more trades
                WHEN tr.GrossIncome > 100000 THEN 8
                WHEN tr.GrossIncome > 50000  THEN 5
                ELSE 3
            END
        CROSS APPLY (
            SELECT SecType, SecName, CUSIP 
            FROM #Securities 
            WHERE SecId = ((tr.ReturnId + n.N) % 20) + 1
        ) s
        WHERE tr.ReturnId % 100 < 40  -- 40% of taxpayers invest
          AND tr.ReturnId >= @BatchStartCG
          AND tr.ReturnId < @BatchStartCG + @BatchSizeCG;

        SET @RowsCG += @@ROWCOUNT;

        IF @RowsCG % 5000000 < @BatchSizeCG * 12
            PRINT CONCAT('   Progress: ', FORMAT(@RowsCG, 'N0'), ' capital gain transactions');

        SET @BatchStartCG += @BatchSizeCG;
    END

    DROP TABLE #Securities;

    PRINT CONCAT('   ✅ CapitalGainTransactions complete: ', FORMAT(@RowsCG, 'N0'), ' rows in ',
        FORMAT(DATEDIFF(SECOND, @CGStartTime, SYSUTCDATETIME()), 'N0'), 's');
END
ELSE
    PRINT '⏭ CapitalGainTransactions already populated - skipping';
GO

-- ============================================================================
-- STEP 10: Generate ScheduleC_Businesses & Expenses (P1)
-- ============================================================================
-- ~15% of returns have self-employment income

IF NOT EXISTS (SELECT 1 FROM ScheduleC_Businesses)
BEGIN
    PRINT '';
    PRINT '▶ Generating ScheduleC_Businesses...';

    DECLARE @SCStartTime DATETIME2 = SYSUTCDATETIME();
    DECLARE @BatchSizeSC INT = 500000;
    DECLARE @MinRetSC INT, @MaxRetSC INT, @BatchStartSC INT;
    DECLARE @RowsSC BIGINT = 0;

    SELECT @MinRetSC = MIN(ReturnId), @MaxRetSC = MAX(ReturnId) FROM TaxReturns;
    SET @BatchStartSC = @MinRetSC;

    -- Business types
    IF OBJECT_ID('tempdb..#BizTypes') IS NOT NULL DROP TABLE #BizTypes;
    CREATE TABLE #BizTypes (BizId INT PRIMARY KEY, BizName NVARCHAR(200), BizCode CHAR(6));
    INSERT INTO #BizTypes VALUES
        (1,'Freelance Software Development','541511'),(2,'Consulting Services','541610'),
        (3,'Photography Studio','541922'),(4,'Real Estate Agent','531210'),
        (5,'Graphic Design Services','541430'),(6,'Personal Training','812190'),
        (7,'Accounting Services','541211'),(8,'Online Retail Store','454110'),
        (9,'Marketing Agency','541810'),(10,'Tutoring Services','611691'),
        (11,'Rideshare Driver','485310'),(12,'Handyman Services','236118'),
        (13,'Catering Business','722320'),(14,'Music Instruction','611610'),
        (15,'Cleaning Service','561720');

    WHILE @BatchStartSC <= @MaxRetSC
    BEGIN
        INSERT INTO ScheduleC_Businesses (
            ReturnId, TaxYear, BusinessName, EIN, BusinessCode, PrincipalProduct,
            AccountingMethod, MaterialParticipation,
            GrossReceipts, CostOfGoodsSold, GrossProfit, TotalExpenses, NetProfit
        )
        SELECT
            tr.ReturnId,
            tr.TaxYear,
            bt.BizName,
            CONCAT(RIGHT('00' + CAST(tr.ReturnId % 99 AS VARCHAR), 2), '-',
                   RIGHT('0000000' + CAST(tr.ReturnId AS VARCHAR), 7)),
            bt.BizCode,
            bt.BizName,
            CASE WHEN tr.ReturnId % 4 = 0 THEN 'Accrual' ELSE 'Cash' END,
            1,
            CAST(tr.GrossIncome * 0.35 AS DECIMAL(14,2)),                    -- Self-emp is ~35% of total income
            CAST(tr.GrossIncome * 0.35 * 0.15 AS DECIMAL(14,2)),            -- 15% COGS
            CAST(tr.GrossIncome * 0.35 * 0.85 AS DECIMAL(14,2)),            -- Gross profit
            CAST(tr.GrossIncome * 0.35 * 0.45 AS DECIMAL(14,2)),            -- 45% expenses
            CAST(tr.GrossIncome * 0.35 * 0.40 AS DECIMAL(14,2))             -- Net profit
        FROM TaxReturns tr
        CROSS APPLY (SELECT BizName, BizCode FROM #BizTypes WHERE BizId = (tr.ReturnId % 15) + 1) bt
        WHERE tr.ReturnId % 100 < 15  -- 15% self-employed
          AND tr.ReturnId >= @BatchStartSC
          AND tr.ReturnId < @BatchStartSC + @BatchSizeSC;

        SET @RowsSC += @@ROWCOUNT;

        IF @RowsSC % 2000000 < @BatchSizeSC
            PRINT CONCAT('   Progress: ', FORMAT(@RowsSC, 'N0'), ' Schedule C businesses');

        SET @BatchStartSC += @BatchSizeSC;
    END

    DROP TABLE #BizTypes;

    PRINT CONCAT('   ✅ ScheduleC_Businesses complete: ', FORMAT(@RowsSC, 'N0'), ' rows in ',
        FORMAT(DATEDIFF(SECOND, @SCStartTime, SYSUTCDATETIME()), 'N0'), 's');
END
ELSE
    PRINT '⏭ ScheduleC_Businesses already populated - skipping';
GO

-- Schedule C Expenses (20-50 expenses per business)
IF NOT EXISTS (SELECT 1 FROM ScheduleC_Expenses)
BEGIN
    PRINT '';
    PRINT '▶ Generating ScheduleC_Expenses...';

    DECLARE @SCEStartTime DATETIME2 = SYSUTCDATETIME();
    DECLARE @BatchSizeSCE INT = 100000;
    DECLARE @MinBiz BIGINT, @MaxBiz BIGINT, @BatchStartSCE BIGINT;
    DECLARE @RowsSCE BIGINT = 0;

    SELECT @MinBiz = MIN(BusinessId), @MaxBiz = MAX(BusinessId) FROM ScheduleC_Businesses;
    SET @BatchStartSCE = @MinBiz;

    WHILE @BatchStartSCE <= @MaxBiz
    BEGIN
        INSERT INTO ScheduleC_Expenses (BusinessId, TaxYear, ExpenseCategory, ExpenseDate, Vendor, Description, Amount, BusinessPercentage)
        SELECT
            b.BusinessId,
            b.TaxYear,
            v.Category,
            DATEADD(DAY, (b.BusinessId + n.N) % 365, DATEFROMPARTS(b.TaxYear, 1, 1)),
            CASE (b.BusinessId + n.N) % 8
                WHEN 0 THEN 'Office Depot' WHEN 1 THEN 'Amazon Business'
                WHEN 2 THEN 'Staples' WHEN 3 THEN 'Home Depot'
                WHEN 4 THEN 'AT&T' WHEN 5 THEN 'Comcast Business'
                WHEN 6 THEN 'State Farm' WHEN 7 THEN 'GEICO'
            END,
            CONCAT(v.Category, ' - monthly expense #', n.N),
            CAST(b.TotalExpenses / v.ExpCount * (0.7 + (b.BusinessId + n.N) % 60 * 0.01) AS DECIMAL(10,2)),
            CASE WHEN v.Category = 'Car and Truck' THEN 65.00
                 WHEN v.Category = 'Home Office' THEN 100.00
                 ELSE 100.00 END
        FROM ScheduleC_Businesses b
        CROSS JOIN (VALUES
            ('Advertising', 2), ('Car and Truck', 3), ('Office Expense', 4),
            ('Supplies', 3), ('Utilities', 2), ('Insurance', 1),
            ('Professional Services', 2), ('Rent or Lease', 1),
            ('Repairs and Maintenance', 2), ('Travel', 2),
            ('Meals (50%)', 3), ('Telephone', 2), ('Internet', 2),
            ('Software Subscriptions', 3), ('Home Office', 1)
        ) AS v(Category, ExpCount)
        INNER JOIN #Numbers n ON n.N <= v.ExpCount
        WHERE b.BusinessId >= @BatchStartSCE
          AND b.BusinessId < @BatchStartSCE + @BatchSizeSCE;

        SET @RowsSCE += @@ROWCOUNT;

        IF @RowsSCE % 5000000 < @BatchSizeSCE * 33
            PRINT CONCAT('   Progress: ', FORMAT(@RowsSCE, 'N0'), ' Schedule C expenses');

        SET @BatchStartSCE += @BatchSizeSCE;
    END

    PRINT CONCAT('   ✅ ScheduleC_Expenses complete: ', FORMAT(@RowsSCE, 'N0'), ' rows in ',
        FORMAT(DATEDIFF(SECOND, @SCEStartTime, SYSUTCDATETIME()), 'N0'), 's');
END
ELSE
    PRINT '⏭ ScheduleC_Expenses already populated - skipping';
GO

-- ============================================================================
-- STEP 11: Generate CharitableContributions (P1 - Schedule A)
-- ============================================================================
-- ~30% itemize, contributing to ~5 charities each

IF NOT EXISTS (SELECT 1 FROM CharitableContributions)
BEGIN
    PRINT '';
    PRINT '▶ Generating CharitableContributions...';

    DECLARE @CCStartTime DATETIME2 = SYSUTCDATETIME();
    DECLARE @BatchSizeCC INT = 500000;
    DECLARE @MinRetCC INT, @MaxRetCC INT, @BatchStartCC INT;
    DECLARE @RowsCC BIGINT = 0;

    SELECT @MinRetCC = MIN(ReturnId), @MaxRetCC = MAX(ReturnId) FROM TaxReturns;
    SET @BatchStartCC = @MinRetCC;

    IF OBJECT_ID('tempdb..#Charities') IS NOT NULL DROP TABLE #Charities;
    CREATE TABLE #Charities (CharId INT PRIMARY KEY, CharName NVARCHAR(200), CharEIN CHAR(10), CharType NVARCHAR(50));
    INSERT INTO #Charities VALUES
        (1,'American Red Cross','53-0196605','Cash'),
        (2,'Salvation Army','13-5562351','Cash'),
        (3,'United Way','13-1635294','Cash'),
        (4,'St. Jude Children''s Research Hospital','62-0646012','Cash'),
        (5,'Feeding America','36-3673599','Cash'),
        (6,'Habitat for Humanity','91-1914868','Cash'),
        (7,'YMCA','13-1624100','Cash'),
        (8,'Local Church/Synagogue/Mosque','00-0000001','Cash'),
        (9,'Goodwill Industries','53-0196517','Property'),
        (10,'Local Food Bank','00-0000002','Cash'),
        (11,'Public Radio/TV Station','00-0000003','Cash'),
        (12,'Alma Mater University','00-0000004','Cash');

    WHILE @BatchStartCC <= @MaxRetCC
    BEGIN
        INSERT INTO CharitableContributions (
            ReturnId, TaxYear, OrganizationName, OrganizationEIN,
            ContributionType, ContributionDate, Amount, FairMarketValue, DeductionLimitPct
        )
        SELECT
            tr.ReturnId,
            tr.TaxYear,
            ch.CharName,
            ch.CharEIN,
            ch.CharType,
            DATEADD(DAY, (tr.ReturnId + n.N * 37) % 365, DATEFROMPARTS(tr.TaxYear, 1, 1)),
            CAST(tr.TotalDeductions * 0.04 * (0.5 + (tr.ReturnId + n.N) % 100 * 0.01) AS DECIMAL(10,2)),
            CASE WHEN ch.CharType = 'Property' 
                 THEN CAST(tr.TotalDeductions * 0.06 AS DECIMAL(10,2)) 
                 ELSE NULL END,
            CASE WHEN ch.CharType = 'Property' THEN 30.00 ELSE 60.00 END
        FROM TaxReturns tr
        INNER JOIN #Numbers n ON n.N <= 
            CASE 
                WHEN tr.GrossIncome > 150000 THEN 8
                WHEN tr.GrossIncome > 75000  THEN 5
                ELSE 3
            END
        CROSS APPLY (
            SELECT CharName, CharEIN, CharType 
            FROM #Charities 
            WHERE CharId = ((tr.ReturnId + n.N) % 12) + 1
        ) ch
        WHERE tr.IsItemized = 1  -- Only itemizers
          AND tr.ReturnId >= @BatchStartCC
          AND tr.ReturnId < @BatchStartCC + @BatchSizeCC;

        SET @RowsCC += @@ROWCOUNT;

        IF @RowsCC % 5000000 < @BatchSizeCC * 8
            PRINT CONCAT('   Progress: ', FORMAT(@RowsCC, 'N0'), ' charitable contributions');

        SET @BatchStartCC += @BatchSizeCC;
    END

    DROP TABLE #Charities;

    PRINT CONCAT('   ✅ CharitableContributions complete: ', FORMAT(@RowsCC, 'N0'), ' rows in ',
        FORMAT(DATEDIFF(SECOND, @CCStartTime, SYSUTCDATETIME()), 'N0'), 's');
END
ELSE
    PRINT '⏭ CharitableContributions already populated - skipping';
GO

-- ============================================================================
-- STEP 12: Generate AuditLog (P1)
-- ============================================================================
-- 5 audit entries per return (create, review, update, submit, status change)

IF NOT EXISTS (SELECT 1 FROM AuditLog)
BEGIN
    PRINT '';
    PRINT '▶ Generating AuditLog...';

    DECLARE @ALStartTime DATETIME2 = SYSUTCDATETIME();
    DECLARE @BatchSizeAL INT = 500000;
    DECLARE @MinRetAL INT, @MaxRetAL INT, @BatchStartAL INT;
    DECLARE @RowsAL BIGINT = 0;

    SELECT @MinRetAL = MIN(ReturnId), @MaxRetAL = MAX(ReturnId) FROM TaxReturns;
    SET @BatchStartAL = @MinRetAL;

    WHILE @BatchStartAL <= @MaxRetAL
    BEGIN
        INSERT INTO AuditLog (TaxYear, EntityType, EntityId, Action, UserId, UserRole, IPAddress, ChangedAt, SessionId)
        SELECT
            tr.TaxYear,
            'TaxReturns',
            tr.ReturnId,
            v.Action,
            CASE v.Action
                WHEN 'INSERT' THEN tr.ProfessionalId
                WHEN 'UPDATE' THEN tr.ProfessionalId
                WHEN 'REVIEW' THEN tr.ProfessionalId + 1
                WHEN 'SUBMIT' THEN tr.ProfessionalId
                WHEN 'STATUS_CHANGE' THEN 0  -- System
            END,
            CASE v.Action
                WHEN 'STATUS_CHANGE' THEN 'System'
                ELSE 'TaxProfessional'
            END,
            CONCAT('10.', (tr.ReturnId % 255) + 1, '.', (tr.ReturnId / 255) % 255, '.', (tr.ReturnId / 65025) % 255),
            DATEADD(HOUR, v.HourOffset, ISNULL(tr.FilingDate, tr.CreatedAt)),
            NEWID()
        FROM TaxReturns tr
        CROSS JOIN (VALUES
            ('INSERT', -72),        -- Created 3 days before filing
            ('UPDATE', -48),        -- Updated 2 days before
            ('REVIEW', -24),        -- Reviewed 1 day before
            ('SUBMIT', 0),          -- Submitted on filing date
            ('STATUS_CHANGE', 24)   -- Status changed 1 day after
        ) AS v(Action, HourOffset)
        WHERE tr.ReturnId >= @BatchStartAL
          AND tr.ReturnId < @BatchStartAL + @BatchSizeAL;

        SET @RowsAL += @@ROWCOUNT;

        IF @RowsAL % 10000000 < @BatchSizeAL * 5
            PRINT CONCAT('   Progress: ', FORMAT(@RowsAL, 'N0'), ' audit log entries');

        SET @BatchStartAL += @BatchSizeAL;
    END

    PRINT CONCAT('   ✅ AuditLog complete: ', FORMAT(@RowsAL, 'N0'), ' rows in ',
        FORMAT(DATEDIFF(SECOND, @ALStartTime, SYSUTCDATETIME()), 'N0'), 's');
END
ELSE
    PRINT '⏭ AuditLog already populated - skipping';
GO

-- ============================================================================
-- STEP 13: Generate ScheduleE_Properties & Income (Rental/Royalty)
-- ============================================================================
-- ~10% of returns have rental/royalty income, avg 1.5 properties each

IF NOT EXISTS (SELECT 1 FROM ScheduleE_Properties)
BEGIN
    PRINT '';
    PRINT '▶ Generating ScheduleE_Properties...';

    DECLARE @SEStartTime DATETIME2 = SYSUTCDATETIME();
    DECLARE @BatchSizeSE INT = 500000;
    DECLARE @MinRetSE INT, @MaxRetSE INT, @BatchStartSE INT;
    DECLARE @RowsSE BIGINT = 0;

    SELECT @MinRetSE = MIN(ReturnId), @MaxRetSE = MAX(ReturnId) FROM TaxReturns;
    SET @BatchStartSE = @MinRetSE;

    -- Property types lookup
    IF OBJECT_ID('tempdb..#PropTypes') IS NOT NULL DROP TABLE #PropTypes;
    CREATE TABLE #PropTypes (PropId INT PRIMARY KEY, PropType NVARCHAR(30), AvgRent DECIMAL(12,2));
    INSERT INTO #PropTypes VALUES
        (1,'Single Family',18000),(2,'Single Family',22000),(3,'Multi-Family',36000),
        (4,'Commercial',48000),(5,'Single Family',15000),(6,'Royalty',8000),
        (7,'Multi-Family',42000),(8,'Single Family',20000),(9,'Commercial',60000),
        (10,'Single Family',24000);

    -- City lookup
    IF OBJECT_ID('tempdb..#RentalCities') IS NOT NULL DROP TABLE #RentalCities;
    CREATE TABLE #RentalCities (CityId INT PRIMARY KEY, CityName NVARCHAR(100), StateCode CHAR(2), Zip CHAR(5));
    INSERT INTO #RentalCities VALUES
        (1,'Austin','TX','78701'),(2,'Denver','CO','80202'),(3,'Nashville','TN','37201'),
        (4,'Phoenix','AZ','85001'),(5,'Raleigh','NC','27601'),(6,'Portland','OR','97201'),
        (7,'Tampa','FL','33601'),(8,'Charlotte','NC','28201'),(9,'San Antonio','TX','78201'),
        (10,'Las Vegas','NV','89101'),(11,'Orlando','FL','32801'),(12,'Atlanta','GA','30301');

    WHILE @BatchStartSE <= @MaxRetSE
    BEGIN
        INSERT INTO ScheduleE_Properties (
            ReturnId, TaxYear, PropertyType, PropertyAddress, City, StateCode, ZipCode,
            RentalDays, PersonalUseDays, GrossRents,
            Advertising, AutoAndTravel, Cleaning, Insurance,
            MortgageInterest, Repairs, Taxes, Utilities, Depreciation, ManagementFees
        )
        SELECT
            tr.ReturnId,
            tr.TaxYear,
            pt.PropType,
            CONCAT(100 + (tr.ReturnId + n.N) % 9900, ' ', 
                CASE (tr.ReturnId + n.N) % 6
                    WHEN 0 THEN 'Oak Street' WHEN 1 THEN 'Maple Avenue'
                    WHEN 2 THEN 'Pine Road' WHEN 3 THEN 'Cedar Lane'
                    WHEN 4 THEN 'Elm Drive' ELSE 'Main Street'
                END),
            rc.CityName,
            rc.StateCode,
            rc.Zip,
            CASE WHEN pt.PropType = 'Royalty' THEN 0 ELSE 330 + (tr.ReturnId + n.N) % 36 END,
            CASE WHEN pt.PropType = 'Royalty' THEN 0 ELSE (tr.ReturnId + n.N) % 15 END,
            CAST(pt.AvgRent * (0.7 + (tr.ReturnId + n.N) % 60 * 0.01) AS DECIMAL(12,2)),  -- GrossRents
            CAST(pt.AvgRent * 0.02 AS DECIMAL(10,2)),   -- Advertising
            CAST(pt.AvgRent * 0.01 AS DECIMAL(10,2)),   -- AutoAndTravel
            CAST(pt.AvgRent * 0.03 AS DECIMAL(10,2)),   -- Cleaning
            CAST(pt.AvgRent * 0.06 AS DECIMAL(10,2)),   -- Insurance
            CAST(pt.AvgRent * 0.25 AS DECIMAL(10,2)),   -- MortgageInterest
            CAST(pt.AvgRent * 0.05 AS DECIMAL(10,2)),   -- Repairs
            CAST(pt.AvgRent * 0.08 AS DECIMAL(10,2)),   -- Taxes
            CAST(pt.AvgRent * 0.04 AS DECIMAL(10,2)),   -- Utilities
            CAST(pt.AvgRent * 0.10 AS DECIMAL(10,2)),   -- Depreciation
            CAST(pt.AvgRent * 0.05 AS DECIMAL(10,2))    -- ManagementFees
        FROM TaxReturns tr
        INNER JOIN #Numbers n ON n.N <= CASE WHEN tr.GrossIncome > 150000 THEN 3 ELSE 1 END
        CROSS APPLY (SELECT PropType, AvgRent FROM #PropTypes WHERE PropId = ((tr.ReturnId + n.N) % 10) + 1) pt
        CROSS APPLY (SELECT CityName, StateCode, Zip FROM #RentalCities WHERE CityId = ((tr.ReturnId + n.N) % 12) + 1) rc
        WHERE tr.ReturnId % 100 < 10  -- 10% have rental income
          AND tr.ReturnId >= @BatchStartSE
          AND tr.ReturnId < @BatchStartSE + @BatchSizeSE;

        SET @RowsSE += @@ROWCOUNT;

        IF @RowsSE % 2000000 < @BatchSizeSE * 3
            PRINT CONCAT('   Progress: ', FORMAT(@RowsSE, 'N0'), ' Schedule E properties');

        SET @BatchStartSE += @BatchSizeSE;
    END

    DROP TABLE #PropTypes;
    DROP TABLE #RentalCities;

    PRINT CONCAT('   ✅ ScheduleE_Properties complete: ', FORMAT(@RowsSE, 'N0'), ' rows in ',
        FORMAT(DATEDIFF(SECOND, @SEStartTime, SYSUTCDATETIME()), 'N0'), 's');
END
ELSE
    PRINT '⏭ ScheduleE_Properties already populated - skipping';
GO

-- Schedule E Income entries (avg 4 income entries per property)
IF NOT EXISTS (SELECT 1 FROM ScheduleE_Income)
BEGIN
    PRINT '';
    PRINT '▶ Generating ScheduleE_Income...';

    DECLARE @SEIStartTime DATETIME2 = SYSUTCDATETIME();
    DECLARE @BatchSizeSEI INT = 200000;
    DECLARE @MinProp BIGINT, @MaxProp BIGINT, @BatchStartSEI BIGINT;
    DECLARE @RowsSEI BIGINT = 0;

    SELECT @MinProp = MIN(PropertyId), @MaxProp = MAX(PropertyId) FROM ScheduleE_Properties;
    SET @BatchStartSEI = @MinProp;

    WHILE @BatchStartSEI <= @MaxProp
    BEGIN
        INSERT INTO ScheduleE_Income (PropertyId, TaxYear, PayerName, IncomeType, PaymentDate, Amount)
        SELECT
            p.PropertyId,
            p.TaxYear,
            CONCAT(CASE (p.PropertyId + n.N) % 6
                WHEN 0 THEN 'John' WHEN 1 THEN 'Maria' WHEN 2 THEN 'David'
                WHEN 3 THEN 'Sarah' WHEN 4 THEN 'Michael' ELSE 'Jennifer'
            END, ' ', CASE (p.PropertyId + n.N) % 8
                WHEN 0 THEN 'Smith' WHEN 1 THEN 'Johnson' WHEN 2 THEN 'Williams'
                WHEN 3 THEN 'Brown' WHEN 4 THEN 'Jones' WHEN 5 THEN 'Garcia'
                WHEN 6 THEN 'Miller' ELSE 'Davis'
            END),
            CASE WHEN p.PropertyType = 'Royalty' THEN 'Royalty' ELSE 'Rent' END,
            DATEADD(DAY, (n.N * 30) + (p.PropertyId % 28), DATEFROMPARTS(p.TaxYear, 1, 1)),
            CAST(p.GrossRents / 4.0 * (0.8 + (p.PropertyId + n.N) % 40 * 0.01) AS DECIMAL(10,2))
        FROM ScheduleE_Properties p
        INNER JOIN #Numbers n ON n.N <= 4
        WHERE p.PropertyId >= @BatchStartSEI
          AND p.PropertyId < @BatchStartSEI + @BatchSizeSEI;

        SET @RowsSEI += @@ROWCOUNT;

        IF @RowsSEI % 5000000 < @BatchSizeSEI * 4
            PRINT CONCAT('   Progress: ', FORMAT(@RowsSEI, 'N0'), ' Schedule E income entries');

        SET @BatchStartSEI += @BatchSizeSEI;
    END

    PRINT CONCAT('   ✅ ScheduleE_Income complete: ', FORMAT(@RowsSEI, 'N0'), ' rows in ',
        FORMAT(DATEDIFF(SECOND, @SEIStartTime, SYSUTCDATETIME()), 'N0'), 's');
END
ELSE
    PRINT '⏭ ScheduleE_Income already populated - skipping';
GO

-- ============================================================================
-- STEP 14: Generate ScheduleB_InterestDividends
-- ============================================================================
-- Most returns have 1-5 interest/dividend entries (~170M rows total)

IF NOT EXISTS (SELECT 1 FROM ScheduleB_InterestDividends)
BEGIN
    PRINT '';
    PRINT '▶ Generating ScheduleB_InterestDividends...';

    DECLARE @SBStartTime DATETIME2 = SYSUTCDATETIME();
    DECLARE @BatchSizeSB INT = 500000;
    DECLARE @MinRetSB INT, @MaxRetSB INT, @BatchStartSB INT;
    DECLARE @RowsSB BIGINT = 0;

    SELECT @MinRetSB = MIN(ReturnId), @MaxRetSB = MAX(ReturnId) FROM TaxReturns;
    SET @BatchStartSB = @MinRetSB;

    -- Payer institutions lookup
    IF OBJECT_ID('tempdb..#Payers') IS NOT NULL DROP TABLE #Payers;
    CREATE TABLE #Payers (PayerId INT PRIMARY KEY, PayerName NVARCHAR(200), PayerEIN CHAR(10), EntryType NVARCHAR(20));
    INSERT INTO #Payers VALUES
        (1,'Chase Bank','13-4994650','Interest'),
        (2,'Bank of America','56-0906609','Interest'),
        (3,'Wells Fargo Bank','94-1347393','Interest'),
        (4,'Citibank','13-5266470','Interest'),
        (5,'Capital One Bank','54-1719368','Interest'),
        (6,'Ally Bank','75-1284171','Interest'),
        (7,'US Bank','31-0841368','Interest'),
        (8,'PNC Bank','25-1197336','Interest'),
        (9,'Fidelity Investments','04-2664166','Ordinary Dividend'),
        (10,'Vanguard Group','23-1945930','Qualified Dividend'),
        (11,'Charles Schwab','94-1393851','Ordinary Dividend'),
        (12,'TD Ameritrade','47-0642657','Qualified Dividend'),
        (13,'E*TRADE','52-1200829','Ordinary Dividend'),
        (14,'Morgan Stanley','13-2655998','Qualified Dividend'),
        (15,'Merrill Lynch','13-5674085','Ordinary Dividend');

    WHILE @BatchStartSB <= @MaxRetSB
    BEGIN
        INSERT INTO ScheduleB_InterestDividends (
            ReturnId, TaxYear, EntryType, PayerName, PayerEIN, Amount,
            TaxExemptAmount, ForeignTaxPaid, IsForeignAccount
        )
        SELECT
            tr.ReturnId,
            tr.TaxYear,
            py.EntryType,
            py.PayerName,
            py.PayerEIN,
            CASE 
                WHEN py.EntryType = 'Interest'
                    THEN CAST(tr.GrossIncome * 0.005 * (0.3 + (tr.ReturnId + n.N) % 140 * 0.01) AS DECIMAL(12,2))
                WHEN py.EntryType = 'Qualified Dividend'
                    THEN CAST(tr.GrossIncome * 0.008 * (0.2 + (tr.ReturnId + n.N) % 160 * 0.01) AS DECIMAL(12,2))
                ELSE CAST(tr.GrossIncome * 0.006 * (0.3 + (tr.ReturnId + n.N) % 140 * 0.01) AS DECIMAL(12,2))
            END,
            CASE WHEN (tr.ReturnId + n.N) % 20 = 0
                 THEN CAST(tr.GrossIncome * 0.001 AS DECIMAL(12,2)) ELSE 0 END,  -- 5% have tax-exempt
            CASE WHEN (tr.ReturnId + n.N) % 50 = 0
                 THEN CAST(tr.GrossIncome * 0.0005 AS DECIMAL(10,2)) ELSE 0 END, -- 2% have foreign tax
            CASE WHEN (tr.ReturnId + n.N) % 100 = 0 THEN 1 ELSE 0 END           -- 1% foreign accounts
        FROM TaxReturns tr
        INNER JOIN #Numbers n ON n.N <=
            CASE
                WHEN tr.GrossIncome > 200000 THEN 5   -- High income: more accounts
                WHEN tr.GrossIncome > 100000 THEN 3
                WHEN tr.GrossIncome > 50000  THEN 2
                ELSE 1
            END
        CROSS APPLY (
            SELECT PayerName, PayerEIN, EntryType
            FROM #Payers WHERE PayerId = ((tr.ReturnId + n.N) % 15) + 1
        ) py
        WHERE tr.ReturnId >= @BatchStartSB
          AND tr.ReturnId < @BatchStartSB + @BatchSizeSB;

        SET @RowsSB += @@ROWCOUNT;

        IF @RowsSB % 10000000 < @BatchSizeSB * 5
            PRINT CONCAT('   Progress: ', FORMAT(@RowsSB, 'N0'), ' Schedule B entries');

        SET @BatchStartSB += @BatchSizeSB;
    END

    DROP TABLE #Payers;

    PRINT CONCAT('   ✅ ScheduleB_InterestDividends complete: ', FORMAT(@RowsSB, 'N0'), ' rows in ',
        FORMAT(DATEDIFF(SECOND, @SBStartTime, SYSUTCDATETIME()), 'N0'), 's');
END
ELSE
    PRINT '⏭ ScheduleB_InterestDividends already populated - skipping';
GO

-- ============================================================================
-- STEP 15: Generate TaxFormDocuments
-- ============================================================================
-- 3-6 documents per return (~200M rows total)

IF NOT EXISTS (SELECT 1 FROM TaxFormDocuments)
BEGIN
    PRINT '';
    PRINT '▶ Generating TaxFormDocuments...';

    DECLARE @TDStartTime DATETIME2 = SYSUTCDATETIME();
    DECLARE @BatchSizeTD INT = 500000;
    DECLARE @MinRetTD INT, @MaxRetTD INT, @BatchStartTD INT;
    DECLARE @RowsTD BIGINT = 0;

    SELECT @MinRetTD = MIN(ReturnId), @MaxRetTD = MAX(ReturnId) FROM TaxReturns;
    SET @BatchStartTD = @MinRetTD;

    -- Document templates lookup
    IF OBJECT_ID('tempdb..#DocTemplates') IS NOT NULL DROP TABLE #DocTemplates;
    CREATE TABLE #DocTemplates (
        DocId INT PRIMARY KEY, DocType NVARCHAR(50), FormName NVARCHAR(100),
        MinPages INT, MaxPages INT, MinSizeKB INT, MaxSizeKB INT
    );
    INSERT INTO #DocTemplates VALUES
        (1, '1040',        'Form 1040 - U.S. Individual Income Tax Return', 2, 6, 150, 500),
        (2, 'W-2',         'W-2 Wage and Tax Statement', 1, 1, 45, 100),
        (3, 'State Return', 'State Income Tax Return', 2, 5, 120, 400),
        (4, 'Schedule A',   'Schedule A - Itemized Deductions', 1, 3, 80, 200),
        (5, 'Schedule B',   'Schedule B - Interest and Ordinary Dividends', 1, 2, 55, 150),
        (6, 'Schedule C',   'Schedule C - Profit or Loss from Business', 2, 4, 100, 300),
        (7, 'Schedule D',   'Schedule D - Capital Gains and Losses', 1, 3, 75, 250),
        (8, 'Schedule E',   'Schedule E - Supplemental Income and Loss', 1, 3, 80, 220),
        (9, '1099-INT',     'Form 1099-INT Interest Income', 1, 1, 35, 80),
        (10,'1099-DIV',     'Form 1099-DIV Dividends and Distributions', 1, 1, 35, 80);

    WHILE @BatchStartTD <= @MaxRetTD
    BEGIN
        -- Every return gets 1040 + W-2 + State Return (base docs)
        INSERT INTO TaxFormDocuments (
            ReturnId, TaxYear, DocumentType, FormName, PageCount, FileSizeBytes,
            MimeType, GeneratedAt, SignedAt, StoragePath, ChecksumSHA256, Status
        )
        SELECT
            tr.ReturnId,
            tr.TaxYear,
            dt.DocType,
            dt.FormName,
            dt.MinPages + (tr.ReturnId + dt.DocId) % (dt.MaxPages - dt.MinPages + 1),
            CAST((dt.MinSizeKB + (tr.ReturnId + dt.DocId) % (dt.MaxSizeKB - dt.MinSizeKB + 1)) * 1024 AS BIGINT),
            'application/pdf',
            DATEADD(MINUTE, -(30 + dt.DocId * 5), ISNULL(tr.FilingDate, tr.CreatedAt)),
            CASE WHEN dt.DocId = 1 THEN ISNULL(tr.FilingDate, tr.CreatedAt) ELSE NULL END,
            CONCAT('tax-documents/', tr.TaxYear, '/', tr.CustomerId, '/', tr.ReturnId, '/',
                   LOWER(REPLACE(dt.DocType, ' ', '-')), '.pdf'),
            CONVERT(CHAR(64), HASHBYTES('SHA2_256',
                CAST(CONCAT(tr.ReturnId, '-', dt.DocId, '-', tr.TaxYear) AS VARBINARY(100))), 2),
            CASE 
                WHEN tr.Status IN ('Filed','Accepted') AND dt.DocId <= 3 THEN 'Submitted'
                WHEN tr.Status = 'In Progress' THEN 'Generated'
                ELSE 'Signed'
            END
        FROM TaxReturns tr
        CROSS APPLY (
            SELECT DocId, DocType, FormName, MinPages, MaxPages, MinSizeKB, MaxSizeKB
            FROM #DocTemplates WHERE DocId <= 3  -- 1040 + W-2 + State Return (everyone gets these)
        ) dt
        WHERE tr.ReturnId >= @BatchStartTD
          AND tr.ReturnId < @BatchStartTD + @BatchSizeTD;

        -- Conditional schedule docs based on taxpayer profile
        INSERT INTO TaxFormDocuments (
            ReturnId, TaxYear, DocumentType, FormName, PageCount, FileSizeBytes,
            MimeType, GeneratedAt, StoragePath, ChecksumSHA256, Status
        )
        SELECT
            tr.ReturnId,
            tr.TaxYear,
            dt.DocType,
            dt.FormName,
            dt.MinPages + (tr.ReturnId + dt.DocId) % (dt.MaxPages - dt.MinPages + 1),
            CAST((dt.MinSizeKB + (tr.ReturnId + dt.DocId) % (dt.MaxSizeKB - dt.MinSizeKB + 1)) * 1024 AS BIGINT),
            'application/pdf',
            DATEADD(MINUTE, -(30 + dt.DocId * 5), ISNULL(tr.FilingDate, tr.CreatedAt)),
            CONCAT('tax-documents/', tr.TaxYear, '/', tr.CustomerId, '/', tr.ReturnId, '/',
                   LOWER(REPLACE(dt.DocType, ' ', '-')), '.pdf'),
            CONVERT(CHAR(64), HASHBYTES('SHA2_256',
                CAST(CONCAT(tr.ReturnId, '-', dt.DocId, '-', tr.TaxYear) AS VARBINARY(100))), 2),
            'Generated'
        FROM TaxReturns tr
        CROSS APPLY (
            SELECT DocId, DocType, FormName, MinPages, MaxPages, MinSizeKB, MaxSizeKB
            FROM #DocTemplates
            WHERE (DocId = 4 AND tr.TotalDeductions > tr.GrossIncome * 0.12)   -- Schedule A if itemizer
               OR (DocId = 5 AND tr.GrossIncome > 50000)                       -- Schedule B if moderate income
               OR (DocId = 6 AND tr.ReturnId % 100 < 15)                       -- Schedule C if self-employed
               OR (DocId = 7 AND tr.ReturnId % 100 < 40)                       -- Schedule D if investor
               OR (DocId = 8 AND tr.ReturnId % 100 < 10)                       -- Schedule E if rental
               OR (DocId = 9 AND tr.GrossIncome > 30000)                       -- 1099-INT if any interest
               OR (DocId = 10 AND tr.GrossIncome > 80000)                      -- 1099-DIV if higher income
        ) dt
        WHERE tr.ReturnId >= @BatchStartTD
          AND tr.ReturnId < @BatchStartTD + @BatchSizeTD;

        SET @RowsTD += @@ROWCOUNT;

        IF @RowsTD % 10000000 < @BatchSizeTD * 7
            PRINT CONCAT('   Progress: ', FORMAT(@RowsTD, 'N0'), ' tax form documents');

        SET @BatchStartTD += @BatchSizeTD;
    END

    DROP TABLE #DocTemplates;

    PRINT CONCAT('   ✅ TaxFormDocuments complete: ', FORMAT(@RowsTD, 'N0'), ' rows in ',
        FORMAT(DATEDIFF(SECOND, @TDStartTime, SYSUTCDATETIME()), 'N0'), 's');
END
ELSE
    PRINT '⏭ TaxFormDocuments already populated - skipping';
GO

-- ============================================================================
-- STEP 16: Update Statistics on all new tables
-- ============================================================================

PRINT '';
PRINT '▶ Updating statistics on all new tables...';

UPDATE STATISTICS FormLineItems;
UPDATE STATISTICS StateTaxReturns;
UPDATE STATISTICS StateFormLineItems;
UPDATE STATISTICS EFileSubmissions;
UPDATE STATISTICS EFileStatusHistory;
UPDATE STATISTICS W2Documents;
UPDATE STATISTICS Form1099;
UPDATE STATISTICS AuditLog;
UPDATE STATISTICS CapitalGainTransactions;
UPDATE STATISTICS ScheduleC_Businesses;
UPDATE STATISTICS ScheduleC_Expenses;
UPDATE STATISTICS CharitableContributions;
UPDATE STATISTICS ScheduleE_Properties;
UPDATE STATISTICS ScheduleE_Income;
UPDATE STATISTICS ScheduleB_InterestDividends;
UPDATE STATISTICS TaxFormDocuments;

PRINT '   ✅ Statistics updated';
GO

-- ============================================================================
-- STEP 17: Summary Report
-- ============================================================================

PRINT '';
PRINT '============================================================';
PRINT 'FILING DETAIL DATA GENERATION COMPLETE';
PRINT '============================================================';
PRINT '';

SELECT 
    t.name AS TableName,
    p.rows AS [RowCount],
    FORMAT(p.rows, 'N0') AS FormattedRows,
    CAST(SUM(a.total_pages) * 8.0 / 1024 AS DECIMAL(12,2)) AS SizeMB,
    CAST(SUM(a.total_pages) * 8.0 / 1024 / 1024 AS DECIMAL(12,2)) AS SizeGB
FROM sys.tables t
INNER JOIN sys.indexes i ON t.object_id = i.object_id
INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
WHERE t.name IN (
    'TaxReturns', 'FormLineItems', 'StateTaxReturns', 'StateFormLineItems',
    'EFileSubmissions', 'EFileStatusHistory', 'W2Documents', 'Form1099',
    'AuditLog', 'CapitalGainTransactions', 'ScheduleC_Businesses',
    'ScheduleC_Expenses', 'CharitableContributions',
    'ScheduleE_Properties', 'ScheduleE_Income',
    'ScheduleB_InterestDividends', 'TaxFormDocuments',
    'Branches', 'TaxProfessionals', 'Customers'
)
GROUP BY t.name, p.rows
ORDER BY p.rows DESC;

-- Total database size
SELECT 
    CAST(SUM(size) * 8.0 / 1024 / 1024 AS DECIMAL(12,2)) AS TotalDatabaseSizeGB
FROM sys.database_files;

PRINT '';
PRINT CONCAT('Completed: ', CONVERT(NVARCHAR(30), SYSUTCDATETIME(), 120));

-- Cleanup temp table
DROP TABLE IF EXISTS #Numbers;
GO
