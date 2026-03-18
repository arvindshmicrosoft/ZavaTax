/*
 * Zava Tax - OLTP Stored Procedures
 * 
 * These procedures simulate the actual API calls that the frontend would make.
 * Used by the load simulator to generate realistic traffic patterns.
 * 
 * IDEMPOTENT: Safe to run multiple times - uses CREATE OR ALTER.
 */

-- ============================================================================
-- CUSTOMER MANAGEMENT
-- ============================================================================

CREATE OR ALTER PROCEDURE dbo.AddCustomer
    @FirstName NVARCHAR(100),
    @LastName NVARCHAR(100),
    @Email NVARCHAR(200),
    @Phone VARCHAR(30) = NULL,
    @Address NVARCHAR(500) = NULL,
    @City NVARCHAR(100) = NULL,
    @State NVARCHAR(50) = NULL,
    @StateAbbr CHAR(2) = NULL,
    @ZipCode VARCHAR(10) = NULL,
    @DateOfBirth DATE = NULL,
    @SSNLastFour CHAR(4) = NULL,
    @PreferredLanguage NVARCHAR(20) = 'English',
    @PreferredContact NVARCHAR(20) = 'Email'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @CustomerId INT;
    
    -- Insert customer
    INSERT INTO Customers (
        FirstName, LastName, Email, Phone, 
        Address, City, State, StateAbbr, ZipCode,
        DateOfBirth, SSNLastFour, 
        CreatedDate, PreferredLanguage, PreferredContact,
        IsActive, CreatedAt
    )
    VALUES (
        @FirstName, @LastName, @Email, @Phone,
        @Address, @City, @State, @StateAbbr, @ZipCode,
        @DateOfBirth, @SSNLastFour,
        CAST(GETDATE() AS DATE), @PreferredLanguage, @PreferredContact,
        1, SYSUTCDATETIME()
    );
    
    -- Return the new CustomerId
    SET @CustomerId = SCOPE_IDENTITY();
    
    SELECT @CustomerId AS CustomerId;
END
GO

-- ============================================================================
-- TAX RETURN WORKFLOW
-- ============================================================================

-- Create UpdateTaxReturn first (called by SaveTaxReturnDraft)
CREATE OR ALTER PROCEDURE dbo.UpdateTaxReturn
    @ReturnId INT,
    @FilingStatus NVARCHAR(50) = NULL,
    @GrossIncome DECIMAL(14,2) = NULL,
    @AdjustedGrossIncome DECIMAL(14,2) = NULL,
    @TotalDeductions DECIMAL(14,2) = NULL,
    @TaxableIncome DECIMAL(14,2) = NULL,
    @TaxLiability DECIMAL(14,2) = NULL,
    @TotalWithheld DECIMAL(14,2) = NULL,
    @RefundAmount DECIMAL(14,2) = NULL,
    @AmountOwed DECIMAL(14,2) = NULL,
    @IsItemized BIT = NULL,
    @NumDependents TINYINT = NULL,
    @ProcessingTimeMinutes INT = NULL,
    @DocumentCount INT = NULL,
    @AIAssistanceCount INT = NULL,
    @HasForeignAccounts BIT = NULL,
    @ForeignAccountMaxValue INT = NULL,
    @HasPFIC BIT = NULL,
    @PFICValue INT = NULL,
    @PFICIncome INT = NULL,
    @HasForeignTrust BIT = NULL,
    @ForeignTrustValue INT = NULL,
    @HasForeignCorporation BIT = NULL,
    @ForeignCorpOwnershipPct TINYINT = NULL,
    @HasForeignPartnership BIT = NULL,
    @ForeignGiftsReceived INT = NULL,
    @ForeignTaxesPaid INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Update only non-null parameters (allows partial updates)
    UPDATE TaxReturns
    SET 
        FilingStatus = COALESCE(@FilingStatus, FilingStatus),
        GrossIncome = COALESCE(@GrossIncome, GrossIncome),
        AdjustedGrossIncome = COALESCE(@AdjustedGrossIncome, AdjustedGrossIncome),
        TotalDeductions = COALESCE(@TotalDeductions, TotalDeductions),
        TaxableIncome = COALESCE(@TaxableIncome, TaxableIncome),
        TaxLiability = COALESCE(@TaxLiability, TaxLiability),
        TotalWithheld = COALESCE(@TotalWithheld, TotalWithheld),
        RefundAmount = COALESCE(@RefundAmount, RefundAmount),
        AmountOwed = COALESCE(@AmountOwed, AmountOwed),
        IsItemized = COALESCE(@IsItemized, IsItemized),
        NumDependents = COALESCE(@NumDependents, NumDependents),
        ProcessingTimeMinutes = COALESCE(@ProcessingTimeMinutes, ProcessingTimeMinutes),
        DocumentCount = COALESCE(@DocumentCount, DocumentCount),
        AIAssistanceCount = COALESCE(@AIAssistanceCount, AIAssistanceCount),
        HasForeignAccounts = COALESCE(@HasForeignAccounts, HasForeignAccounts),
        ForeignAccountMaxValue = COALESCE(@ForeignAccountMaxValue, ForeignAccountMaxValue),
        HasPFIC = COALESCE(@HasPFIC, HasPFIC),
        PFICValue = COALESCE(@PFICValue, PFICValue),
        PFICIncome = COALESCE(@PFICIncome, PFICIncome),
        HasForeignTrust = COALESCE(@HasForeignTrust, HasForeignTrust),
        ForeignTrustValue = COALESCE(@ForeignTrustValue, ForeignTrustValue),
        HasForeignCorporation = COALESCE(@HasForeignCorporation, HasForeignCorporation),
        ForeignCorpOwnershipPct = COALESCE(@ForeignCorpOwnershipPct, ForeignCorpOwnershipPct),
        HasForeignPartnership = COALESCE(@HasForeignPartnership, HasForeignPartnership),
        ForeignGiftsReceived = COALESCE(@ForeignGiftsReceived, ForeignGiftsReceived),
        ForeignTaxesPaid = COALESCE(@ForeignTaxesPaid, ForeignTaxesPaid),
        UpdatedAt = SYSUTCDATETIME()
    WHERE ReturnId = @ReturnId;
    
    SELECT @ReturnId AS ReturnId, @@ROWCOUNT AS RowsAffected;
END
GO

-- Create SaveTaxReturnDraft after UpdateTaxReturn (it calls UpdateTaxReturn)
CREATE OR ALTER PROCEDURE dbo.SaveTaxReturnDraft
    @CustomerId INT,
    @BranchId INT,
    @ProfessionalId INT,
    @TaxYear INT,
    @FilingStatus NVARCHAR(50),
    @GrossIncome DECIMAL(14,2) = NULL,
    @AdjustedGrossIncome DECIMAL(14,2) = NULL,
    @TotalDeductions DECIMAL(14,2) = NULL,
    @TaxableIncome DECIMAL(14,2) = NULL,
    @TaxLiability DECIMAL(14,2) = NULL,
    @TotalWithheld DECIMAL(14,2) = NULL,
    @RefundAmount DECIMAL(14,2) = NULL,
    @AmountOwed DECIMAL(14,2) = NULL,
    @IsItemized BIT = 0,
    @NumDependents TINYINT = 0,
    @ProcessingTimeMinutes INT = NULL,
    @DocumentCount INT = 0,
    @AIAssistanceCount INT = 0,
    @IsAmended BIT = 0,
    @IsExtension BIT = 0,
    @HasForeignAccounts BIT = 0,
    @ForeignAccountMaxValue INT = NULL,
    @HasPFIC BIT = 0,
    @PFICValue INT = NULL,
    @PFICIncome INT = NULL,
    @HasForeignTrust BIT = 0,
    @ForeignTrustValue INT = NULL,
    @HasForeignCorporation BIT = 0,
    @ForeignCorpOwnershipPct TINYINT = NULL,
    @HasForeignPartnership BIT = 0,
    @ForeignGiftsReceived INT = NULL,
    @ForeignTaxesPaid INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @ReturnId INT;
    DECLARE @ExistingReturnId INT;
    
    -- Check if a return already exists for this customer/year
    SELECT @ExistingReturnId = ReturnId
    FROM TaxReturns WITH (UPDLOCK, HOLDLOCK)
    WHERE CustomerId = @CustomerId AND TaxYear = @TaxYear;
    
    IF @ExistingReturnId IS NOT NULL
    BEGIN
        -- Return already exists - update it instead
        EXEC dbo.UpdateTaxReturn 
            @ReturnId = @ExistingReturnId,
            @FilingStatus = @FilingStatus,
            @GrossIncome = @GrossIncome,
            @AdjustedGrossIncome = @AdjustedGrossIncome,
            @TotalDeductions = @TotalDeductions,
            @TaxableIncome = @TaxableIncome,
            @TaxLiability = @TaxLiability,
            @TotalWithheld = @TotalWithheld,
            @RefundAmount = @RefundAmount,
            @AmountOwed = @AmountOwed,
            @IsItemized = @IsItemized,
            @NumDependents = @NumDependents,
            @ProcessingTimeMinutes = @ProcessingTimeMinutes,
            @DocumentCount = @DocumentCount,
            @AIAssistanceCount = @AIAssistanceCount,
            @HasForeignAccounts = @HasForeignAccounts,
            @ForeignAccountMaxValue = @ForeignAccountMaxValue,
            @HasPFIC = @HasPFIC,
            @PFICValue = @PFICValue,
            @PFICIncome = @PFICIncome,
            @HasForeignTrust = @HasForeignTrust,
            @ForeignTrustValue = @ForeignTrustValue,
            @HasForeignCorporation = @HasForeignCorporation,
            @ForeignCorpOwnershipPct = @ForeignCorpOwnershipPct,
            @HasForeignPartnership = @HasForeignPartnership,
            @ForeignGiftsReceived = @ForeignGiftsReceived,
            @ForeignTaxesPaid = @ForeignTaxesPaid;
        
        SELECT @ExistingReturnId AS ReturnId, 'Updated' AS Action;
        RETURN;
    END
    
    -- Create new draft tax return
    INSERT INTO TaxReturns (
        CustomerId, BranchId, ProfessionalId, TaxYear,
        FilingStatus, Status,
        GrossIncome, AdjustedGrossIncome, TotalDeductions, TaxableIncome,
        TaxLiability, TotalWithheld, RefundAmount, AmountOwed,
        IsItemized, NumDependents,
        ProcessingTimeMinutes, DocumentCount, AIAssistanceCount,
        IsAmended, IsExtension,
        HasForeignAccounts, ForeignAccountMaxValue,
        HasPFIC, PFICValue, PFICIncome,
        HasForeignTrust, ForeignTrustValue,
        HasForeignCorporation, ForeignCorpOwnershipPct,
        HasForeignPartnership,
        ForeignGiftsReceived, ForeignTaxesPaid,
        CreatedAt, UpdatedAt
    )
    VALUES (
        @CustomerId, @BranchId, @ProfessionalId, @TaxYear,
        @FilingStatus, 'Draft',
        @GrossIncome, @AdjustedGrossIncome, @TotalDeductions, @TaxableIncome,
        @TaxLiability, @TotalWithheld, @RefundAmount, @AmountOwed,
        @IsItemized, @NumDependents,
        @ProcessingTimeMinutes, @DocumentCount, @AIAssistanceCount,
        @IsAmended, @IsExtension,
        @HasForeignAccounts, @ForeignAccountMaxValue,
        @HasPFIC, @PFICValue, @PFICIncome,
        @HasForeignTrust, @ForeignTrustValue,
        @HasForeignCorporation, @ForeignCorpOwnershipPct,
        @HasForeignPartnership,
        @ForeignGiftsReceived, @ForeignTaxesPaid,
        SYSUTCDATETIME(), SYSUTCDATETIME()
    );
    
    SET @ReturnId = SCOPE_IDENTITY();
    
    SELECT @ReturnId AS ReturnId, 'Created' AS Action;
END
GO

CREATE OR ALTER PROCEDURE dbo.SubmitTaxReturn
    @ReturnId INT,
    @FilingDate DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    IF @FilingDate IS NULL
        SET @FilingDate = SYSUTCDATETIME();
    
    -- Update status to Filed and set filing date
    UPDATE TaxReturns
    SET 
        Status = 'Filed',
        FilingDate = @FilingDate,
        UpdatedAt = SYSUTCDATETIME()
    WHERE ReturnId = @ReturnId;
    
    -- Populate all filing detail tables for this return
    -- (form line items, state return, e-file submission, W-2s, 1099s, audit log, etc.)
    EXEC dbo.PopulateFilingDetails @ReturnId = @ReturnId;
    
    SELECT @ReturnId AS ReturnId, @@ROWCOUNT AS RowsAffected;
END
GO

-- ============================================================================
-- FILING DETAIL AUTO-POPULATION
-- When a tax return is submitted, this procedure generates all associated
-- detail records: form line items, state tax return, e-file submission,
-- W-2/1099 income documents, schedule details, and audit trail entries.
-- This simulates what a real tax platform does at filing time.
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.PopulateFilingDetails
    @ReturnId INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Gather the return's data once
    DECLARE @TaxYear INT, @CustomerId INT, @BranchId INT, @ProfessionalId INT,
            @FilingStatus NVARCHAR(50), @GrossIncome DECIMAL(14,2),
            @AdjustedGrossIncome DECIMAL(14,2), @TotalDeductions DECIMAL(14,2),
            @TaxableIncome DECIMAL(14,2), @TaxLiability DECIMAL(14,2),
            @TotalWithheld DECIMAL(14,2), @RefundAmount DECIMAL(14,2),
            @AmountOwed DECIMAL(14,2), @IsItemized BIT, @NumDependents TINYINT,
            @FilingDate DATETIME2, @Status NVARCHAR(50);

    SELECT
        @TaxYear = TaxYear, @CustomerId = CustomerId, @BranchId = BranchId,
        @ProfessionalId = ProfessionalId, @FilingStatus = FilingStatus,
        @GrossIncome = GrossIncome, @AdjustedGrossIncome = AdjustedGrossIncome,
        @TotalDeductions = TotalDeductions, @TaxableIncome = TaxableIncome,
        @TaxLiability = TaxLiability, @TotalWithheld = TotalWithheld,
        @RefundAmount = RefundAmount, @AmountOwed = AmountOwed,
        @IsItemized = IsItemized, @NumDependents = NumDependents,
        @FilingDate = FilingDate, @Status = Status
    FROM TaxReturns
    WHERE ReturnId = @ReturnId;

    IF @TaxYear IS NULL RETURN;  -- Return not found

    -- Get customer state for state filing
    DECLARE @CustomerState CHAR(2);
    SELECT @CustomerState = StateAbbr FROM Customers WHERE CustomerId = @CustomerId;

    -- ================================================================
    -- 1. FORM 1040 LINE ITEMS (28 lines per return)
    -- ================================================================
    IF NOT EXISTS (SELECT 1 FROM FormLineItems WHERE ReturnId = @ReturnId AND TaxYear = @TaxYear)
    BEGIN
        DECLARE @WagesPct DECIMAL(5,2) = 0.70 + (CHECKSUM(NEWID()) % 20) * 0.01;  -- 70-89%
        DECLARE @InterestPct DECIMAL(5,2) = 0.01 + (CHECKSUM(NEWID()) % 5) * 0.005;  -- 1-3.5%
        DECLARE @DividendPct DECIMAL(5,2) = 0.01 + (CHECKSUM(NEWID()) % 4) * 0.005;  -- 1-2.5%
        DECLARE @WagesAmt DECIMAL(18,2) = @GrossIncome * @WagesPct;
        DECLARE @InterestAmt DECIMAL(18,2) = @GrossIncome * @InterestPct;
        DECLARE @DividendAmt DECIMAL(18,2) = @GrossIncome * @DividendPct;
        DECLARE @OtherIncome DECIMAL(18,2) = @GrossIncome - @WagesAmt - @InterestAmt - @DividendAmt;

        INSERT INTO FormLineItems (ReturnId, TaxYear, FormNumber, LineNumber, LineDescription, Amount, IsCalculated)
        VALUES
            (@ReturnId, @TaxYear, '1040', '1a', 'Wages, salaries, tips (W-2)', @WagesAmt, 0),
            (@ReturnId, @TaxYear, '1040', '1b', 'Household employee income', 0, 0),
            (@ReturnId, @TaxYear, '1040', '1c', 'Tip income not on W-2', 0, 0),
            (@ReturnId, @TaxYear, '1040', '1z', 'Total from adding lines 1a through 1c', @WagesAmt, 1),
            (@ReturnId, @TaxYear, '1040', '2a', 'Tax-exempt interest', 0, 0),
            (@ReturnId, @TaxYear, '1040', '2b', 'Taxable interest', @InterestAmt, 0),
            (@ReturnId, @TaxYear, '1040', '3a', 'Qualified dividends', @DividendAmt * 0.6, 0),
            (@ReturnId, @TaxYear, '1040', '3b', 'Ordinary dividends', @DividendAmt, 0),
            (@ReturnId, @TaxYear, '1040', '4a', 'IRA distributions', 0, 0),
            (@ReturnId, @TaxYear, '1040', '4b', 'Taxable IRA amount', 0, 0),
            (@ReturnId, @TaxYear, '1040', '5a', 'Pensions and annuities', 0, 0),
            (@ReturnId, @TaxYear, '1040', '5b', 'Taxable pension amount', 0, 0),
            (@ReturnId, @TaxYear, '1040', '6a', 'Social Security benefits', 0, 0),
            (@ReturnId, @TaxYear, '1040', '6b', 'Taxable SS amount', 0, 0),
            (@ReturnId, @TaxYear, '1040', '7', 'Capital gain or loss', 0, 0),
            (@ReturnId, @TaxYear, '1040', '8', 'Other income (Schedule 1)', @OtherIncome, 0),
            (@ReturnId, @TaxYear, '1040', '9', 'Total income', @GrossIncome, 1),
            (@ReturnId, @TaxYear, '1040', '10', 'Adjustments to income', @GrossIncome - @AdjustedGrossIncome, 1),
            (@ReturnId, @TaxYear, '1040', '11', 'Adjusted gross income', @AdjustedGrossIncome, 1),
            (@ReturnId, @TaxYear, '1040', '12', CASE WHEN @IsItemized = 1 THEN 'Itemized deductions' ELSE 'Standard deduction' END, @TotalDeductions, 0),
            (@ReturnId, @TaxYear, '1040', '13', 'Qualified business income deduction', 0, 0),
            (@ReturnId, @TaxYear, '1040', '14', 'Total deductions', @TotalDeductions, 1),
            (@ReturnId, @TaxYear, '1040', '15', 'Taxable income', @TaxableIncome, 1),
            (@ReturnId, @TaxYear, '1040', '16', 'Tax', @TaxLiability, 1),
            (@ReturnId, @TaxYear, '1040', '24', 'Total tax', @TaxLiability, 1),
            (@ReturnId, @TaxYear, '1040', '25d', 'Federal income tax withheld', @TotalWithheld, 0),
            (@ReturnId, @TaxYear, '1040', '34', 'Amount overpaid (refund)', @RefundAmount, 1),
            (@ReturnId, @TaxYear, '1040', '37', 'Amount you owe', @AmountOwed, 1);
    END

    -- ================================================================
    -- 2. STATE TAX RETURN (if applicable)
    -- ================================================================
    IF @CustomerState IS NOT NULL
       AND @CustomerState NOT IN ('AK','FL','NV','NH','SD','TN','TX','WA','WY')
       AND NOT EXISTS (SELECT 1 FROM StateTaxReturns WHERE FederalReturnId = @ReturnId AND TaxYear = @TaxYear)
    BEGIN
        -- Simplified state tax rate lookup
        DECLARE @StateTaxRate DECIMAL(5,3) = CASE @CustomerState
            WHEN 'CA' THEN 0.093 WHEN 'NY' THEN 0.109 WHEN 'NJ' THEN 0.108
            WHEN 'OR' THEN 0.099 WHEN 'MN' THEN 0.099 WHEN 'HI' THEN 0.090
            WHEN 'DC' THEN 0.095 WHEN 'VT' THEN 0.088 WHEN 'WI' THEN 0.076
            WHEN 'ME' THEN 0.075 WHEN 'CT' THEN 0.070 WHEN 'MT' THEN 0.069
            WHEN 'NE' THEN 0.068 WHEN 'DE' THEN 0.066 WHEN 'WV' THEN 0.065
            WHEN 'SC' THEN 0.065 WHEN 'IA' THEN 0.060 WHEN 'RI' THEN 0.060
            WHEN 'NM' THEN 0.059 WHEN 'VA' THEN 0.058 WHEN 'MD' THEN 0.058
            WHEN 'ID' THEN 0.058 WHEN 'KS' THEN 0.057 WHEN 'GA' THEN 0.055
            WHEN 'AR' THEN 0.055 WHEN 'MO' THEN 0.054 WHEN 'NC' THEN 0.053
            WHEN 'AL' THEN 0.050 WHEN 'IL' THEN 0.050 WHEN 'KY' THEN 0.050
            WHEN 'MA' THEN 0.050 WHEN 'MS' THEN 0.050 WHEN 'UT' THEN 0.049
            WHEN 'OK' THEN 0.048 WHEN 'AZ' THEN 0.045 WHEN 'CO' THEN 0.044
            WHEN 'LA' THEN 0.043 WHEN 'MI' THEN 0.043 WHEN 'OH' THEN 0.040
            WHEN 'IN' THEN 0.032 WHEN 'PA' THEN 0.031 WHEN 'ND' THEN 0.029
            ELSE 0.050  -- Default
        END;

        DECLARE @StateFormNumber NVARCHAR(50) = CASE @CustomerState
            WHEN 'CA' THEN 'CA 540' WHEN 'NY' THEN 'NY IT-201' WHEN 'NJ' THEN 'NJ 1040'
            WHEN 'IL' THEN 'IL 1040' WHEN 'PA' THEN 'PA 40' WHEN 'OH' THEN 'OH IT 1040'
            WHEN 'GA' THEN 'GA 500' WHEN 'NC' THEN 'NC D-400' WHEN 'VA' THEN 'VA 760'
            WHEN 'MA' THEN 'MA 1' WHEN 'MD' THEN 'MD 502' WHEN 'MN' THEN 'MN M1'
            WHEN 'CO' THEN 'CO 104' WHEN 'OR' THEN 'OR 40' WHEN 'CT' THEN 'CT 1040'
            ELSE @CustomerState + ' 1040'
        END;

        DECLARE @StateTax DECIMAL(14,2) = CAST(@TaxableIncome * @StateTaxRate AS DECIMAL(14,2));
        DECLARE @StateWithheld DECIMAL(14,2) = CAST(@StateTax * 0.92 AS DECIMAL(14,2));
        DECLARE @StateRefund DECIMAL(14,2) = CASE WHEN @StateWithheld > @StateTax THEN @StateWithheld - @StateTax ELSE 0 END;
        DECLARE @StateOwed DECIMAL(14,2) = CASE WHEN @StateWithheld < @StateTax THEN @StateTax - @StateWithheld ELSE 0 END;

        DECLARE @StateReturnId BIGINT;

        INSERT INTO StateTaxReturns (
            FederalReturnId, TaxYear, StateCode, ResidentType, StateFormNumber,
            StateGrossIncome, StateTaxableIncome, StateTaxLiability,
            StateWithheld, StateRefund, StateAmountOwed, Status, FilingDate
        )
        VALUES (
            @ReturnId, @TaxYear, @CustomerState, 'Resident', @StateFormNumber,
            @GrossIncome, @TaxableIncome, @StateTax,
            @StateWithheld, @StateRefund, @StateOwed, @Status, @FilingDate
        );

        SET @StateReturnId = SCOPE_IDENTITY();

        -- State form line items (12 lines)
        INSERT INTO StateFormLineItems (StateReturnId, TaxYear, FormNumber, LineNumber, LineDescription, Amount)
        VALUES
            (@StateReturnId, @TaxYear, @StateFormNumber, '1', 'Federal AGI', @AdjustedGrossIncome),
            (@StateReturnId, @TaxYear, @StateFormNumber, '2', 'State additions', 0),
            (@StateReturnId, @TaxYear, @StateFormNumber, '3', 'State subtractions', 0),
            (@StateReturnId, @TaxYear, @StateFormNumber, '4', 'State adjusted income', @GrossIncome),
            (@StateReturnId, @TaxYear, @StateFormNumber, '5', 'State standard/itemized deduction', @TotalDeductions * 0.8),
            (@StateReturnId, @TaxYear, @StateFormNumber, '6', 'State exemptions', @NumDependents * 1000),
            (@StateReturnId, @TaxYear, @StateFormNumber, '7', 'State taxable income', @TaxableIncome),
            (@StateReturnId, @TaxYear, @StateFormNumber, '8', 'State tax', @StateTax),
            (@StateReturnId, @TaxYear, @StateFormNumber, '9', 'State credits', 0),
            (@StateReturnId, @TaxYear, @StateFormNumber, '10', 'Net state tax', @StateTax),
            (@StateReturnId, @TaxYear, @StateFormNumber, '11', 'State withholding', @StateWithheld),
            (@StateReturnId, @TaxYear, @StateFormNumber, '12', 'Refund / Amount owed', @StateRefund - @StateOwed);
    END

    -- ================================================================
    -- 3. E-FILE SUBMISSION
    -- ================================================================
    IF NOT EXISTS (SELECT 1 FROM EFileSubmissions WHERE ReturnId = @ReturnId AND TaxYear = @TaxYear)
    BEGIN
        DECLARE @SubmissionId BIGINT;
        DECLARE @IRSSubmissionId NVARCHAR(50) = 'IRS-' + CAST(@TaxYear AS VARCHAR) + '-' + RIGHT('0000000000' + CAST(@ReturnId AS VARCHAR), 10);
        DECLARE @AcceptDelay INT = 1 + ABS(CHECKSUM(NEWID())) % 72;  -- 1-72 hours

        INSERT INTO EFileSubmissions (
            ReturnId, TaxYear, SubmissionType, TransmitterControlCode,
            SubmissionIdIRS, SubmittedAt, SubmittedBy, TransmissionMethod,
            ERO_EFIN, Status, StatusUpdatedAt, AcknowledgmentReceived,
            AcceptanceDate
        )
        VALUES (
            @ReturnId, @TaxYear, 'Original', 'TCC-ZAVA-2026',
            @IRSSubmissionId, ISNULL(@FilingDate, SYSUTCDATETIME()), @ProfessionalId, 'MeF',
            'ZAVA01', 'Accepted', DATEADD(HOUR, @AcceptDelay, ISNULL(@FilingDate, SYSUTCDATETIME())),
            1, DATEADD(HOUR, @AcceptDelay, ISNULL(@FilingDate, SYSUTCDATETIME()))
        );

        SET @SubmissionId = SCOPE_IDENTITY();

        -- E-file status history (3 entries: Pending → Processing → Accepted)
        INSERT INTO EFileStatusHistory (SubmissionId, TaxYear, PreviousStatus, NewStatus, StatusMessage, ChangedAt, ChangedBy)
        VALUES
            (@SubmissionId, @TaxYear, NULL, 'Pending', 'Return submitted via MeF', ISNULL(@FilingDate, SYSUTCDATETIME()), @ProfessionalId),
            (@SubmissionId, @TaxYear, 'Pending', 'Processing', 'Acknowledged by IRS', DATEADD(MINUTE, 15 + ABS(CHECKSUM(NEWID())) % 60, ISNULL(@FilingDate, SYSUTCDATETIME())), NULL),
            (@SubmissionId, @TaxYear, 'Processing', 'Accepted', 'Return accepted', DATEADD(HOUR, @AcceptDelay, ISNULL(@FilingDate, SYSUTCDATETIME())), NULL);
    END

    -- ================================================================
    -- 4. W-2 DOCUMENTS (1-3 per return, based on income)
    -- ================================================================
    IF NOT EXISTS (SELECT 1 FROM W2Documents WHERE ReturnId = @ReturnId AND TaxYear = @TaxYear)
    BEGIN
        DECLARE @NumW2s INT = CASE
            WHEN @GrossIncome > 200000 THEN 2 + ABS(CHECKSUM(NEWID())) % 2  -- 2-3
            WHEN @GrossIncome > 75000  THEN 1 + ABS(CHECKSUM(NEWID())) % 2  -- 1-2
            ELSE 1
        END;
        DECLARE @W2Idx INT = 1;
        DECLARE @RemainingWages DECIMAL(14,2) = @WagesAmt;

        WHILE @W2Idx <= @NumW2s
        BEGIN
            DECLARE @ThisWage DECIMAL(14,2) = CASE
                WHEN @W2Idx = @NumW2s THEN @RemainingWages
                ELSE CAST(@RemainingWages * (0.4 + (ABS(CHECKSUM(NEWID())) % 30) * 0.01) AS DECIMAL(14,2))
            END;
            DECLARE @SSWage DECIMAL(14,2) = CASE WHEN @ThisWage > 168600 THEN 168600 ELSE @ThisWage END;
            DECLARE @MedWage DECIMAL(14,2) = @ThisWage;
            DECLARE @FedWith DECIMAL(14,2) = CAST(@ThisWage * (0.15 + (ABS(CHECKSUM(NEWID())) % 15) * 0.01) AS DECIMAL(14,2));
            DECLARE @SSTax DECIMAL(14,2) = CAST(@SSWage * 0.062 AS DECIMAL(14,2));
            DECLARE @MedTax DECIMAL(14,2) = CAST(@MedWage * 0.0145 AS DECIMAL(14,2));
            DECLARE @EmpIdx INT = ABS(CHECKSUM(NEWID())) % 500 + 1;

            INSERT INTO W2Documents (
                ReturnId, TaxYear, EmployerEIN, EmployerName, EmployerState,
                WagesBox1, FederalWithheldBox2, SocialSecurityWagesBox3,
                SocialSecurityTaxBox4, MedicareWagesBox5, MedicareTaxBox6,
                StateWagesBox16, StateWithheldBox17,
                RetirementPlan, VerificationStatus
            )
            VALUES (
                @ReturnId, @TaxYear,
                RIGHT('00' + CAST(@EmpIdx AS VARCHAR), 2) + '-' + RIGHT('0000000' + CAST(@EmpIdx * 137 AS VARCHAR), 7),
                CHOOSE((@EmpIdx % 10) + 1,
                    'Acme Corp','TechVision Inc','Global Services LLC','Metro Industries',
                    'Pacific Solutions','Summit Healthcare','Valley Financial','Coastal Manufacturing',
                    'Pioneer Technology','Horizon Energy'),
                @CustomerState,
                @ThisWage, @FedWith, @SSWage, @SSTax, @MedWage, @MedTax,
                @ThisWage, CAST(@ThisWage * 0.04 AS DECIMAL(14,2)),
                CASE WHEN ABS(CHECKSUM(NEWID())) % 3 > 0 THEN 1 ELSE 0 END,
                'Verified'
            );

            SET @RemainingWages -= @ThisWage;
            SET @W2Idx += 1;
        END
    END

    -- ================================================================
    -- 5. 1099 FORMS (0-3 per return, based on income level)
    -- ================================================================
    IF NOT EXISTS (SELECT 1 FROM Form1099 WHERE ReturnId = @ReturnId AND TaxYear = @TaxYear)
       AND @GrossIncome > 50000  -- Only higher earners get 1099s
    BEGIN
        -- 1099-INT (interest income)
        IF @InterestAmt > 100
        BEGIN
            INSERT INTO Form1099 (ReturnId, TaxYear, Form1099Type, PayerEIN, PayerName, GrossAmount, FederalWithheld, IssueDate)
            VALUES (@ReturnId, @TaxYear, 'INT',
                '12-' + RIGHT('0000000' + CAST(ABS(CHECKSUM(NEWID())) % 9999999 AS VARCHAR), 7),
                ISNULL(CHOOSE(ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 5 + 1, 'Chase Bank','Bank of America','Wells Fargo','Citibank','Capital One'), 'Chase Bank'),
                @InterestAmt, 0, DATEFROMPARTS(@TaxYear + 1, 1, 31));
        END

        -- 1099-DIV (dividend income)
        IF @DividendAmt > 200
        BEGIN
            INSERT INTO Form1099 (ReturnId, TaxYear, Form1099Type, PayerEIN, PayerName, GrossAmount, FederalWithheld, IssueDate)
            VALUES (@ReturnId, @TaxYear, 'DIV',
                '34-' + RIGHT('0000000' + CAST(ABS(CHECKSUM(NEWID())) % 9999999 AS VARCHAR), 7),
                ISNULL(CHOOSE(ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 5 + 1, 'Vanguard','Fidelity','Charles Schwab','TD Ameritrade','E*Trade'), 'Vanguard'),
                @DividendAmt, 0, DATEFROMPARTS(@TaxYear + 1, 1, 31));
        END

        -- 1099-MISC/NEC (10% chance for self-employment income)
        IF ABS(CHECKSUM(NEWID())) % 10 = 0
        BEGIN
            DECLARE @MiscAmt DECIMAL(14,2) = CAST(@OtherIncome * 0.5 AS DECIMAL(14,2));
            IF @MiscAmt > 600
            INSERT INTO Form1099 (ReturnId, TaxYear, Form1099Type, PayerEIN, PayerName, GrossAmount, FederalWithheld, IssueDate)
            VALUES (@ReturnId, @TaxYear, 'NEC',
                '56-' + RIGHT('0000000' + CAST(ABS(CHECKSUM(NEWID())) % 9999999 AS VARCHAR), 7),
                ISNULL(CHOOSE(ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 5 + 1, 'Freelance Hub','Upwork Payments','Consulting Co','Contract Services Inc','GigWork LLC'), 'Freelance Hub'),
                @MiscAmt, 0, DATEFROMPARTS(@TaxYear + 1, 1, 31));
        END
    END

    -- ================================================================
    -- 6. CAPITAL GAINS (Schedule D) - for ~40% of returns
    -- ================================================================
    IF NOT EXISTS (SELECT 1 FROM CapitalGainTransactions WHERE ReturnId = @ReturnId AND TaxYear = @TaxYear)
       AND ABS(CHECKSUM(NEWID())) % 100 < 40  -- ~40% of filers have cap gains
       AND @GrossIncome > 60000
    BEGIN
        DECLARE @NumTrades INT = 2 + ABS(CHECKSUM(NEWID())) % 13;  -- 2-14 trades
        DECLARE @TradeIdx INT = 1;

        WHILE @TradeIdx <= @NumTrades
        BEGIN
            DECLARE @SecType NVARCHAR(50) = ISNULL(CHOOSE(ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 5 + 1, 'Stock','Stock','ETF','Bond','Crypto'), 'Stock');
            DECLARE @SecName NVARCHAR(200) = ISNULL(CHOOSE(ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 15 + 1,
                'AAPL','MSFT','GOOGL','AMZN','TSLA','SPY','QQQ','VTI','BND','NVDA',
                'META','BTC-USD','ETH-USD','JPM','V'), 'SPY');
            DECLARE @Qty DECIMAL(18,8) = CASE WHEN @SecType = 'Crypto' THEN 0.1 + ABS(CHECKSUM(NEWID())) % 50 * 0.1 ELSE 5 + ABS(CHECKSUM(NEWID())) % 500 END;
            DECLARE @Basis DECIMAL(18,2) = CAST(@Qty * (10 + ABS(CHECKSUM(NEWID())) % 500) AS DECIMAL(18,2));
            DECLARE @Proceeds DECIMAL(18,2) = CAST(@Basis * (0.7 + ABS(CHECKSUM(NEWID())) % 80 * 0.01) AS DECIMAL(18,2));  -- -30% to +50%
            DECLARE @IsShort BIT = CASE WHEN ABS(CHECKSUM(NEWID())) % 3 = 0 THEN 1 ELSE 0 END;

            INSERT INTO CapitalGainTransactions (
                ReturnId, TaxYear, SecurityType, SecurityName, Quantity,
                DateAcquired, DateSold, CostBasis, SaleProceeds, GainOrLoss,
                IsShortTerm, IsWashSale, BrokerName
            )
            VALUES (
                @ReturnId, @TaxYear, @SecType, @SecName, @Qty,
                DATEADD(DAY, -(365 + ABS(CHECKSUM(NEWID())) % 730), DATEFROMPARTS(@TaxYear, 6, 15)),
                DATEADD(DAY, -(ABS(CHECKSUM(NEWID())) % 365), DATEFROMPARTS(@TaxYear, 12, 31)),
                @Basis, @Proceeds, @Proceeds - @Basis,
                @IsShort, CASE WHEN ABS(CHECKSUM(NEWID())) % 20 = 0 THEN 1 ELSE 0 END,
                ISNULL(CHOOSE(ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 5 + 1, 'Fidelity','Charles Schwab','Vanguard','TD Ameritrade','Robinhood'), 'Fidelity')
            );

            SET @TradeIdx += 1;
        END
    END

    -- ================================================================
    -- 7. SCHEDULE C (Self-Employment) - for ~15% of returns
    -- ================================================================
    IF NOT EXISTS (SELECT 1 FROM ScheduleC_Businesses WHERE ReturnId = @ReturnId AND TaxYear = @TaxYear)
       AND ABS(CHECKSUM(NEWID())) % 100 < 15
       AND @GrossIncome > 30000
    BEGIN
        DECLARE @BizGross DECIMAL(14,2) = CAST(@OtherIncome * (0.8 + (ABS(CHECKSUM(NEWID())) % 40) * 0.01) AS DECIMAL(14,2));
        IF @BizGross < 5000 SET @BizGross = 5000 + ABS(CHECKSUM(NEWID())) % 50000;
        DECLARE @BizExpenses DECIMAL(14,2) = CAST(@BizGross * (0.3 + (ABS(CHECKSUM(NEWID())) % 40) * 0.01) AS DECIMAL(14,2));
        DECLARE @BizProfit DECIMAL(14,2) = @BizGross - @BizExpenses;
        DECLARE @BusinessId BIGINT;

        INSERT INTO ScheduleC_Businesses (
            ReturnId, TaxYear, BusinessName, BusinessCode, PrincipalProduct,
            AccountingMethod, MaterialParticipation, GrossReceipts,
            TotalExpenses, GrossProfit, NetProfit
        )
        VALUES (
            @ReturnId, @TaxYear,
            ISNULL(CHOOSE(ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 8 + 1, 'Consulting Services','Freelance Design','IT Solutions','Photography',
                'Handyman Services','Tutoring','Event Planning','Tax Preparation'), 'Consulting Services'),
            ISNULL(CHOOSE(ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 5 + 1, '541990','541511','541430','541219','238990'), '541990'),
            'Professional Services',
            CASE WHEN ABS(CHECKSUM(NEWID())) % 4 = 0 THEN 'Accrual' ELSE 'Cash' END,
            1, @BizGross, @BizExpenses, @BizGross, @BizProfit
        );

        SET @BusinessId = SCOPE_IDENTITY();

        -- Generate 5-12 expense line items
        DECLARE @NumExpenses INT = 5 + ABS(CHECKSUM(NEWID())) % 8;
        DECLARE @ExpIdx INT = 1;
        DECLARE @ExpRemaining DECIMAL(14,2) = @BizExpenses;

        WHILE @ExpIdx <= @NumExpenses
        BEGIN
            DECLARE @ExpCat NVARCHAR(100) = CHOOSE((@ExpIdx - 1) % 10 + 1,
                'Advertising','Car and truck expenses','Office expense','Rent or lease',
                'Supplies','Utilities','Insurance','Professional services',
                'Travel','Meals (50% deductible)');
            DECLARE @ExpAmt DECIMAL(10,2) = CASE
                WHEN @ExpIdx = @NumExpenses THEN @ExpRemaining
                ELSE CAST(@ExpRemaining * (0.05 + ABS(CHECKSUM(NEWID())) % 20 * 0.01) AS DECIMAL(10,2))
            END;

            INSERT INTO ScheduleC_Expenses (BusinessId, TaxYear, ExpenseCategory, ExpenseDate, Amount, BusinessPercentage)
            VALUES (@BusinessId, @TaxYear, @ExpCat,
                DATEADD(DAY, ABS(CHECKSUM(NEWID())) % 365, DATEFROMPARTS(@TaxYear, 1, 1)),
                @ExpAmt, 100.00);

            SET @ExpRemaining -= @ExpAmt;
            SET @ExpIdx += 1;
        END
    END

    -- ================================================================
    -- 8. CHARITABLE CONTRIBUTIONS (for itemizers only)
    -- ================================================================
    IF NOT EXISTS (SELECT 1 FROM CharitableContributions WHERE ReturnId = @ReturnId AND TaxYear = @TaxYear)
       AND @IsItemized = 1
    BEGIN
        DECLARE @NumDonations INT = 1 + ABS(CHECKSUM(NEWID())) % 5;
        DECLARE @DonIdx INT = 1;

        WHILE @DonIdx <= @NumDonations
        BEGIN
            INSERT INTO CharitableContributions (
                ReturnId, TaxYear, OrganizationName, ContributionType,
                ContributionDate, Amount, FairMarketValue, DeductionLimitPct
            )
            VALUES (
                @ReturnId, @TaxYear,
                ISNULL(CHOOSE(ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 10 + 1,
                    'Red Cross','Salvation Army','United Way','Habitat for Humanity',
                    'Local Food Bank','St. Jude Research Hospital',
                    'Doctors Without Borders','ASPCA','Goodwill','Local Church'), 'Red Cross'),
                CASE WHEN ABS(CHECKSUM(NEWID())) % 5 = 0 THEN 'Property' ELSE 'Cash' END,
                DATEADD(DAY, ABS(CHECKSUM(NEWID())) % 365, DATEFROMPARTS(@TaxYear, 1, 1)),
                CAST(200 + ABS(CHECKSUM(NEWID())) % 5000 AS DECIMAL(10,2)),
                NULL, 60.00
            );
            SET @DonIdx += 1;
        END
    END

    -- ================================================================
    -- 9. SCHEDULE E: RENTAL PROPERTIES (10% of returns)
    -- ================================================================
    IF NOT EXISTS (SELECT 1 FROM ScheduleE_Properties WHERE ReturnId = @ReturnId AND TaxYear = @TaxYear)
       AND ABS(CHECKSUM(NEWID())) % 10 = 0
    BEGIN
        DECLARE @NumProperties INT = 1 + ABS(CHECKSUM(NEWID())) % 3;
        DECLARE @PropIdx INT = 1;
        DECLARE @PropType NVARCHAR(30);
        DECLARE @PropGrossRents DECIMAL(12,2);

        WHILE @PropIdx <= @NumProperties
        BEGIN
            SET @PropType = ISNULL(CHOOSE(ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 5 + 1,
                'Single Family', 'Multi-Family', 'Commercial', 'Single Family', 'Royalty'), 'Single Family');
            SET @PropGrossRents = CAST(8000 + ABS(CHECKSUM(NEWID())) % 42000 AS DECIMAL(12,2));

            DECLARE @NewPropId BIGINT;
            INSERT INTO ScheduleE_Properties (
                ReturnId, TaxYear, PropertyType, PropertyAddress, City, StateCode, ZipCode,
                RentalDays, PersonalUseDays, GrossRents,
                Advertising, Insurance, MortgageInterest, Repairs, Taxes,
                Utilities, Depreciation, ManagementFees
            )
            VALUES (
                @ReturnId, @TaxYear, @PropType,
                CONCAT(100 + ABS(CHECKSUM(NEWID())) % 9900, ' Main Street'),
                ISNULL(CHOOSE(ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 6 + 1,
                    'Austin','Denver','Nashville','Phoenix','Raleigh','Portland'), 'Austin'),
                @CustomerState,
                RIGHT('00000' + CAST(10000 + ABS(CHECKSUM(NEWID())) % 89999 AS VARCHAR), 5),
                CASE WHEN @PropType = 'Royalty' THEN 0 ELSE 330 + ABS(CHECKSUM(NEWID())) % 36 END,
                CASE WHEN @PropType = 'Royalty' THEN 0 ELSE ABS(CHECKSUM(NEWID())) % 15 END,
                @PropGrossRents,
                CAST(@PropGrossRents * 0.02 AS DECIMAL(10,2)),
                CAST(@PropGrossRents * 0.06 AS DECIMAL(10,2)),
                CAST(@PropGrossRents * 0.25 AS DECIMAL(10,2)),
                CAST(@PropGrossRents * 0.05 AS DECIMAL(10,2)),
                CAST(@PropGrossRents * 0.08 AS DECIMAL(10,2)),
                CAST(@PropGrossRents * 0.04 AS DECIMAL(10,2)),
                CAST(@PropGrossRents * 0.10 AS DECIMAL(10,2)),
                CAST(@PropGrossRents * 0.05 AS DECIMAL(10,2))
            );
            SET @NewPropId = SCOPE_IDENTITY();

            -- Add 2-6 income entries per property
            DECLARE @NumIncEntries INT = 2 + ABS(CHECKSUM(NEWID())) % 5;
            DECLARE @IncIdx INT = 1;
            WHILE @IncIdx <= @NumIncEntries
            BEGIN
                INSERT INTO ScheduleE_Income (PropertyId, TaxYear, PayerName, IncomeType, PaymentDate, Amount)
                VALUES (
                    @NewPropId, @TaxYear,
                    CONCAT('Tenant ', @IncIdx),
                    CASE WHEN @PropType = 'Royalty' THEN 'Royalty' ELSE 'Rent' END,
                    DATEADD(MONTH, @IncIdx, DATEFROMPARTS(@TaxYear, 1, 1)),
                    CAST(@PropGrossRents / @NumIncEntries * (0.8 + ABS(CHECKSUM(NEWID())) % 40 * 0.01) AS DECIMAL(10,2))
                );
                SET @IncIdx += 1;
            END

            SET @PropIdx += 1;
        END
    END

    -- ================================================================
    -- 10. SCHEDULE B: INTEREST & DIVIDEND INCOME
    -- ================================================================
    IF NOT EXISTS (SELECT 1 FROM ScheduleB_InterestDividends WHERE ReturnId = @ReturnId AND TaxYear = @TaxYear)
    BEGIN
        -- Most returns have 1-3 interest/dividend entries
        DECLARE @NumBEntries INT = 1 + ABS(CHECKSUM(NEWID())) % 4;
        DECLARE @BIdx INT = 1;

        WHILE @BIdx <= @NumBEntries
        BEGIN
            INSERT INTO ScheduleB_InterestDividends (
                ReturnId, TaxYear, EntryType, PayerName, PayerEIN, Amount,
                TaxExemptAmount, ForeignTaxPaid, IsForeignAccount
            )
            VALUES (
                @ReturnId, @TaxYear,
                ISNULL(CHOOSE(ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 3 + 1,
                    'Interest', 'Ordinary Dividend', 'Qualified Dividend'), 'Interest'),
                ISNULL(CHOOSE(ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 8 + 1,
                    'Chase Bank','Bank of America','Fidelity Investments','Charles Schwab',
                    'Vanguard','Wells Fargo','TD Ameritrade','E*TRADE'), 'Chase Bank'),
                RIGHT('00-0000000' + CAST(ABS(CHECKSUM(NEWID())) % 9999999 AS VARCHAR), 10),
                CAST(@InterestAmt / @NumBEntries * (0.5 + ABS(CHECKSUM(NEWID())) % 100 * 0.01) AS DECIMAL(12,2)),
                CASE WHEN ABS(CHECKSUM(NEWID())) % 10 = 0
                     THEN CAST(ABS(CHECKSUM(NEWID())) % 500 AS DECIMAL(12,2)) ELSE 0 END,
                CASE WHEN ABS(CHECKSUM(NEWID())) % 20 = 0
                     THEN CAST(ABS(CHECKSUM(NEWID())) % 200 AS DECIMAL(10,2)) ELSE 0 END,
                CASE WHEN ABS(CHECKSUM(NEWID())) % 50 = 0 THEN 1 ELSE 0 END
            );
            SET @BIdx += 1;
        END
    END

    -- ================================================================
    -- 11. TAX FORM DOCUMENTS (metadata for every return)
    -- ================================================================
    IF NOT EXISTS (SELECT 1 FROM TaxFormDocuments WHERE ReturnId = @ReturnId AND TaxYear = @TaxYear)
    BEGIN
        DECLARE @DocDate DATETIME2 = ISNULL(@FilingDate, SYSUTCDATETIME());
        DECLARE @ReturnPath NVARCHAR(500) = CONCAT('tax-documents/', @TaxYear, '/', @CustomerId, '/', @ReturnId);

        -- Always generate 1040 + at least one W-2 copy
        INSERT INTO TaxFormDocuments (ReturnId, TaxYear, DocumentType, FormName, PageCount, FileSizeBytes, MimeType, GeneratedAt, SignedAt, StoragePath, ChecksumSHA256, Status)
        VALUES
            (@ReturnId, @TaxYear, '1040', 'Form 1040 - U.S. Individual Income Tax Return', 2 + ABS(CHECKSUM(NEWID())) % 4,
             CAST(150000 + ABS(CHECKSUM(NEWID())) % 350000 AS BIGINT), 'application/pdf',
             DATEADD(MINUTE, -20, @DocDate), @DocDate,
             CONCAT(@ReturnPath, '/1040.pdf'), CONVERT(CHAR(64), HASHBYTES('SHA2_256', CAST(NEWID() AS NVARCHAR(36))), 2),
             CASE WHEN @Status IN ('Filed','Accepted') THEN 'Submitted' ELSE 'Signed' END),
            (@ReturnId, @TaxYear, 'W-2', 'W-2 Wage and Tax Statement', 1,
             CAST(45000 + ABS(CHECKSUM(NEWID())) % 55000 AS BIGINT), 'application/pdf',
             DATEADD(MINUTE, -25, @DocDate), NULL,
             CONCAT(@ReturnPath, '/w2.pdf'), CONVERT(CHAR(64), HASHBYTES('SHA2_256', CAST(NEWID() AS NVARCHAR(36))), 2),
             'Generated');

        -- Conditionally add schedules
        IF @IsItemized = 1
            INSERT INTO TaxFormDocuments (ReturnId, TaxYear, DocumentType, FormName, PageCount, FileSizeBytes, MimeType, GeneratedAt, StoragePath, ChecksumSHA256, Status)
            VALUES (@ReturnId, @TaxYear, 'Schedule A', 'Schedule A - Itemized Deductions', 2,
                    CAST(80000 + ABS(CHECKSUM(NEWID())) % 70000 AS BIGINT), 'application/pdf',
                    DATEADD(MINUTE, -18, @DocDate), CONCAT(@ReturnPath, '/schedule-a.pdf'),
                    CONVERT(CHAR(64), HASHBYTES('SHA2_256', CAST(NEWID() AS NVARCHAR(36))), 2), 'Generated');

        IF @InterestAmt > 500
            INSERT INTO TaxFormDocuments (ReturnId, TaxYear, DocumentType, FormName, PageCount, FileSizeBytes, MimeType, GeneratedAt, StoragePath, ChecksumSHA256, Status)
            VALUES (@ReturnId, @TaxYear, 'Schedule B', 'Schedule B - Interest and Ordinary Dividends', 1,
                    CAST(55000 + ABS(CHECKSUM(NEWID())) % 45000 AS BIGINT), 'application/pdf',
                    DATEADD(MINUTE, -17, @DocDate), CONCAT(@ReturnPath, '/schedule-b.pdf'),
                    CONVERT(CHAR(64), HASHBYTES('SHA2_256', CAST(NEWID() AS NVARCHAR(36))), 2), 'Generated');
    END

    -- ================================================================
    -- 12. AUDIT LOG ENTRIES (filing lifecycle events)
    -- ================================================================
    IF NOT EXISTS (SELECT 1 FROM AuditLog WHERE EntityType = 'TaxReturn' AND EntityId = @ReturnId AND TaxYear = @TaxYear)
    BEGIN
        DECLARE @SessionId UNIQUEIDENTIFIER = NEWID();

        INSERT INTO AuditLog (TaxYear, EntityType, EntityId, Action, UserId, UserRole, ChangedAt, SessionId)
        VALUES
            (@TaxYear, 'TaxReturn', @ReturnId, 'CREATE', @ProfessionalId, 'TaxProfessional',
             DATEADD(MINUTE, -30, ISNULL(@FilingDate, SYSUTCDATETIME())), @SessionId),
            (@TaxYear, 'TaxReturn', @ReturnId, 'UPDATE', @ProfessionalId, 'TaxProfessional',
             DATEADD(MINUTE, -15, ISNULL(@FilingDate, SYSUTCDATETIME())), @SessionId),
            (@TaxYear, 'TaxReturn', @ReturnId, 'SUBMIT', @ProfessionalId, 'TaxProfessional',
             ISNULL(@FilingDate, SYSUTCDATETIME()), @SessionId);
    END
END
GO

-- ============================================================================
-- HELPER PROCEDURES
-- ============================================================================

CREATE OR ALTER PROCEDURE dbo.GetTaxReturn
    @ReturnId INT
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT *
    FROM TaxReturns
    WHERE ReturnId = @ReturnId;
END
GO

PRINT 'OLTP procedures created successfully!';
