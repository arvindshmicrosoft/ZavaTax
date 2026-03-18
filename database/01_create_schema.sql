/*
 * Zava Tax - Database Schema
 * Azure SQL DB Hyperscale
 * 
 * This script creates all tables for the Zava Tax demo.
 * Run this BEFORE loading data.
 * 
 * IDEMPOTENT: Safe to run multiple times - uses IF NOT EXISTS guards.
 */

-- ============================================================================
-- REFERENCE TABLES
-- ============================================================================

-- Branches / Franchise Locations
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Branches')
BEGIN
    CREATE TABLE Branches (
        BranchId INT IDENTITY(1,1) PRIMARY KEY,
        BranchName NVARCHAR(200) NOT NULL,
        Address NVARCHAR(500),
        City NVARCHAR(100),
        State NVARCHAR(50),
        StateAbbr CHAR(2),
        ZipCode VARCHAR(10),
        Phone VARCHAR(30),
        ManagerName NVARCHAR(200),
        OpenedDate DATE,
        IsFranchise BIT DEFAULT 1,
        SquareFeet INT,
        NumWorkstations INT,
        CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME()
    );

    CREATE INDEX IX_Branches_State ON Branches(StateAbbr);
    CREATE INDEX IX_Branches_City ON Branches(City, StateAbbr);
END
GO

-- Tax Professionals
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'TaxProfessionals')
BEGIN
    CREATE TABLE TaxProfessionals (
        ProfessionalId INT IDENTITY(1,1) PRIMARY KEY,
        BranchId INT NOT NULL,
        FirstName NVARCHAR(100) NOT NULL,
        LastName NVARCHAR(100) NOT NULL,
        Email NVARCHAR(200),
        Phone VARCHAR(30),
        HireDate DATE,
        Certification NVARCHAR(50), -- CPA, EA, AFSP, None
        YearsExperience INT,
        IsActive BIT DEFAULT 1,
        HourlyRate DECIMAL(8,2),
        AvgReturnsPerDay DECIMAL(5,1),
        CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME(),
        
        CONSTRAINT FK_TaxProfessionals_Branch FOREIGN KEY (BranchId) 
            REFERENCES Branches(BranchId)
    );

    CREATE INDEX IX_TaxProfessionals_Branch ON TaxProfessionals(BranchId);
    CREATE INDEX IX_TaxProfessionals_Active ON TaxProfessionals(IsActive) INCLUDE (BranchId, FirstName, LastName);
END
GO

-- Customers
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Customers')
BEGIN
    CREATE TABLE Customers (
        CustomerId INT IDENTITY(1,1) PRIMARY KEY,
        FirstName NVARCHAR(100) NOT NULL,
        LastName NVARCHAR(100) NOT NULL,
        Email NVARCHAR(200),
        Phone VARCHAR(30),
        Address NVARCHAR(500),
        City NVARCHAR(100),
        State NVARCHAR(50),
        StateAbbr CHAR(2),
        ZipCode VARCHAR(10),
        DateOfBirth DATE,
        SSNLastFour CHAR(4),
        CreatedDate DATE,
        PreferredLanguage NVARCHAR(20) DEFAULT 'English',
        PreferredContact NVARCHAR(20) DEFAULT 'Email',
        IsActive BIT DEFAULT 1,
        CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME()
    );

    CREATE INDEX IX_Customers_State ON Customers(StateAbbr);
    CREATE INDEX IX_Customers_Email ON Customers(Email);
    CREATE INDEX IX_Customers_Name ON Customers(LastName, FirstName);
END
GO

-- International Form Requirements (Reference Table)
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'InternationalFormRequirements')
BEGIN
    CREATE TABLE InternationalFormRequirements (
        FormId INT IDENTITY(1,1) PRIMARY KEY,
        FormNumber NVARCHAR(20) NOT NULL,
        FormName NVARCHAR(200) NOT NULL,
        Description NVARCHAR(1000),
        ThresholdAmount INT NULL,
        ThresholdDescription NVARCHAR(500),
        Penalties NVARCHAR(500),
        FilingDeadline NVARCHAR(100),
        CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME()
    );

    CREATE INDEX IX_IntlFormReqs_FormNumber ON InternationalFormRequirements(FormNumber);

    -- Seed data for international form requirements
    INSERT INTO InternationalFormRequirements (FormNumber, FormName, Description, ThresholdAmount, ThresholdDescription, Penalties, FilingDeadline)
    VALUES 
        ('8938', 'FATCA Statement of Specified Foreign Financial Assets', 'Report foreign financial accounts, securities, and other assets', 50000, 'Over $50,000 on last day or $75,000 at any time (single)', 'Up to $10,000 initial penalty, $50,000 for continued non-compliance', 'With tax return'),
        ('FinCEN 114', 'FBAR - Foreign Bank Account Report', 'Report foreign financial accounts held during the year', 10000, 'Aggregate balance exceeds $10,000 at any time', 'Civil penalties up to $12,909 per violation; willful up to $129,210', 'April 15 (auto-extended to October 15)'),
        ('8621', 'PFIC Annual Information Statement', 'Report ownership of Passive Foreign Investment Companies', NULL, 'Any ownership in a PFIC', 'Complex tax calculations and potential excess distribution taxes', 'With tax return'),
        ('3520', 'Foreign Trust and Gift Report', 'Report transactions with foreign trusts and large foreign gifts', 100000, 'Gifts/bequests over $100,000 from foreign persons', '$10,000 or 35% of gross value for trusts; 5% per month for gifts', 'With tax return (or extension)'),
        ('3520-A', 'Annual Information Return of Foreign Trust with U.S. Owner', 'Filed by foreign trust with U.S. owner', NULL, 'U.S. owner of foreign trust', '$10,000 penalty for failure to file', 'March 15'),
        ('5471', 'Information Return of U.S. Persons with Foreign Corporations', 'Report ownership in controlled foreign corporations', NULL, '10% or more ownership in foreign corporation', '$10,000 per return; $10,000 additional for each 30-day period', 'With tax return'),
        ('8865', 'Return of U.S. Persons with Respect to Certain Foreign Partnerships', 'Report ownership in foreign partnerships', NULL, 'Control or 10%+ ownership in foreign partnership', '$10,000 per return; additional penalties for continued failure', 'With tax return'),
        ('1116', 'Foreign Tax Credit', 'Claim credit for foreign taxes paid', NULL, 'Any foreign taxes paid or accrued', 'N/A - elective form to reduce tax', 'With tax return');
END
GO

-- ============================================================================
-- KNOWLEDGE BASE (Vector Search)
-- ============================================================================

-- Tax Knowledge Base for RAG
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'TaxKnowledgeBase')
BEGIN
    CREATE TABLE TaxKnowledgeBase (
        Id INT IDENTITY(1,1) NOT NULL,
        ChunkId NVARCHAR(100) NOT NULL UNIQUE,
        PublicationId NVARCHAR(20) NOT NULL,
        PublicationTitle NVARCHAR(500),
        Section NVARCHAR(500),
        Subsection NVARCHAR(500),
        Content NVARCHAR(MAX) NOT NULL,
        TokenEstimate INT,
        SourceUrl NVARCHAR(1000),
        ChunkIndex INT,
        ContentEmbedding VECTOR(1536),  -- Azure SQL DB native vector type
        CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME(),
        
        CONSTRAINT PK_TaxKnowledgeBase PRIMARY KEY CLUSTERED (Id)
    );

    CREATE INDEX IX_TaxKnowledge_Publication ON TaxKnowledgeBase(PublicationId);
END
GO

-- DiskANN vector index for fast similarity search
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_TaxKnowledgeBase_Embedding' AND object_id = OBJECT_ID('TaxKnowledgeBase'))
BEGIN
    CREATE VECTOR INDEX IX_TaxKnowledgeBase_Embedding
    ON TaxKnowledgeBase(ContentEmbedding)
    WITH (METRIC = 'cosine', TYPE = 'DISKANN');
    PRINT 'Created vector index IX_TaxKnowledgeBase_Embedding';
END
ELSE
    PRINT 'Vector index IX_TaxKnowledgeBase_Embedding already exists - skipping';
GO

-- ============================================================================
-- TAX SCENARIOS (Similar Case Search)
-- ============================================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'TaxScenarios')
BEGIN
    CREATE TABLE TaxScenarios (
        Id INT IDENTITY(1,1) NOT NULL,
        ScenarioId NVARCHAR(50) NOT NULL UNIQUE,
        TaxYear INT NOT NULL,
        ScenarioType NVARCHAR(50) NOT NULL,
        
        -- Taxpayer Profile (JSON)
        TaxpayerProfile JSON, 
        FilingStatus AS CAST(JSON_VALUE(TaxpayerProfile, '$.filing_status') AS NVARCHAR(50)) PERSISTED,
        
        -- Income & Deductions (JSON)
        IncomeSources JSON,
        Deductions JSON,
        Credits JSON,
        SpecialSituations JSON,
        
        -- Outcome
        TaxOutcome JSON,
        TotalIncome AS CAST(JSON_VALUE(TaxOutcome, '$.total_income') AS INT) PERSISTED,
        RefundAmount AS CAST(JSON_VALUE(TaxOutcome, '$.refund_amount') AS INT) PERSISTED,
        AmountOwed AS CAST(JSON_VALUE(TaxOutcome, '$.amount_owed') AS INT) PERSISTED,
        
        -- Complexity & Classification
        ComplexityScore INT,
        KeyCharacteristics JSON, -- JSON array
        
        -- Narrative (for embedding)
        ScenarioSummary NVARCHAR(MAX),
        ResolutionNotes NVARCHAR(MAX),
        
        -- Vector Embedding
        ScenarioEmbedding VECTOR(1536),
        
        CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME(),
        
        CONSTRAINT PK_TaxScenarios PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT CK_TaxScenarios_TaxpayerProfile CHECK (ISJSON(TaxpayerProfile) = 1),
        CONSTRAINT CK_TaxScenarios_IncomeSources CHECK (ISJSON(IncomeSources) = 1),
        CONSTRAINT CK_TaxScenarios_TaxOutcome CHECK (ISJSON(TaxOutcome) = 1)
    );

    CREATE INDEX IX_TaxScenarios_Type ON TaxScenarios(ScenarioType, ComplexityScore);
    CREATE INDEX IX_TaxScenarios_FilingStatus ON TaxScenarios(FilingStatus);
    CREATE INDEX IX_TaxScenarios_TaxYear ON TaxScenarios(TaxYear);
END
GO

-- DiskANN vector index for similar case search
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_TaxScenarios_Embedding' AND object_id = OBJECT_ID('TaxScenarios'))
BEGIN
    CREATE VECTOR INDEX IX_TaxScenarios_Embedding
    ON TaxScenarios(ScenarioEmbedding)
    WITH (METRIC = 'cosine', TYPE = 'DISKANN');
    PRINT 'Created vector index IX_TaxScenarios_Embedding';
END
ELSE
    PRINT 'Vector index IX_TaxScenarios_Embedding already exists - skipping';
GO

-- ============================================================================
-- PARTITION FUNCTION AND SCHEME (TaxYear partitioning)
-- ============================================================================
-- RANGE RIGHT: each boundary is the first value in the next partition.
--   Partition 1:  TaxYear < 2020   (2019 and earlier)
--   Partition 2:  TaxYear = 2020
--   ...
--   Partition 8:  TaxYear = 2026
--   Partition 9:  TaxYear >= 2027  (future years)
-- Azure SQL Hyperscale: all partitions map to [PRIMARY].
-- ============================================================================

IF NOT EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = 'pf_TaxYear')
BEGIN
    CREATE PARTITION FUNCTION pf_TaxYear (INT)
    AS RANGE RIGHT FOR VALUES (2020, 2021, 2022, 2023, 2024, 2025, 2026, 2027);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.partition_schemes WHERE name = 'ps_TaxYear')
BEGIN
    CREATE PARTITION SCHEME ps_TaxYear
    AS PARTITION pf_TaxYear
    ALL TO ([PRIMARY]);
END
GO

-- ============================================================================
-- TAX RETURNS TABLE (Partitioned by TaxYear · HTAP with Columnstore)
-- ============================================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'TaxReturns')
BEGIN
    CREATE TABLE TaxReturns (
        ReturnId INT IDENTITY(1,1) NOT NULL,
        CustomerId INT NOT NULL,
        BranchId INT NOT NULL,
        ProfessionalId INT NOT NULL,
        TaxYear INT NOT NULL,
        FilingDate DATETIME2,
        FilingStatus NVARCHAR(50) NOT NULL,
        
        -- Financial Metrics
        GrossIncome DECIMAL(14,2),
        AdjustedGrossIncome DECIMAL(14,2),
        TotalDeductions DECIMAL(14,2),
        TaxableIncome DECIMAL(14,2),
        TaxLiability DECIMAL(14,2),
        TotalWithheld DECIMAL(14,2),
        RefundAmount DECIMAL(14,2),
        AmountOwed DECIMAL(14,2),
        
        -- Status
        Status NVARCHAR(50) DEFAULT 'Draft',
        
        -- Flags
        IsItemized BIT,
        NumDependents TINYINT,
        
        -- Operational Metrics
        ProcessingTimeMinutes INT,
        DocumentCount INT,
        AIAssistanceCount INT,
        IsAmended BIT DEFAULT 0,
        IsExtension BIT DEFAULT 0,
        
        -- International Tax Form Fields
        HasForeignAccounts BIT DEFAULT 0,
        ForeignAccountMaxValue INT NULL,
        HasPFIC BIT DEFAULT 0,
        PFICValue INT NULL,
        PFICIncome INT NULL,
        HasForeignTrust BIT DEFAULT 0,
        ForeignTrustValue INT NULL,
        HasForeignCorporation BIT DEFAULT 0,
        ForeignCorpOwnershipPct TINYINT NULL,
        HasForeignPartnership BIT DEFAULT 0,
        ForeignGiftsReceived INT NULL,
        ForeignTaxesPaid INT NULL,
        
        -- Timestamps
        CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME(),
        UpdatedAt DATETIME2 DEFAULT SYSUTCDATETIME(),

        -- Composite PK includes TaxYear for partition alignment
        CONSTRAINT PK_TaxReturns PRIMARY KEY CLUSTERED (ReturnId, TaxYear)
    ) ON ps_TaxYear(TaxYear);

    -- Unique constraint: one return per customer per tax year (partition-aligned)
    CREATE UNIQUE NONCLUSTERED INDEX UQ_TaxReturns_Customer_TaxYear
    ON TaxReturns (CustomerId, TaxYear)
    ON ps_TaxYear(TaxYear);

    -- Nonclustered rowstore indexes for OLTP point queries (partition-aligned)
    CREATE NONCLUSTERED INDEX IX_TaxReturns_Customer 
    ON TaxReturns(CustomerId, TaxYear)
    ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED INDEX IX_TaxReturns_Branch_Date
    ON TaxReturns(BranchId, FilingDate)
    INCLUDE (RefundAmount, AmountOwed, ProcessingTimeMinutes)
    ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED INDEX IX_TaxReturns_Professional
    ON TaxReturns(ProfessionalId, FilingDate)
    ON ps_TaxYear(TaxYear);

    -- Index for international returns
    CREATE NONCLUSTERED INDEX IX_TaxReturns_International
    ON TaxReturns(TaxYear, HasForeignAccounts, HasPFIC, HasForeignTrust, HasForeignCorporation, HasForeignPartnership)
    INCLUDE (ForeignAccountMaxValue, PFICValue, ForeignTaxesPaid, ForeignGiftsReceived)
    ON ps_TaxYear(TaxYear);

    -- Nonclustered columnstore index for analytics (partition-aligned)
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
END
GO

-- ============================================================================
-- P0: IRS FORM METADATA (Reference Tables)
-- ============================================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'TaxForms')
BEGIN
    CREATE TABLE TaxForms (
        FormId INT IDENTITY(1,1) PRIMARY KEY,
        FormNumber NVARCHAR(20) NOT NULL,
        FormName NVARCHAR(200) NOT NULL,
        TaxYear INT NOT NULL,
        Version NVARCHAR(20),
        RevisionDate DATE,
        LineDefinitions JSON,
        CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME()
    );

    CREATE UNIQUE INDEX UQ_TaxForms_Number_Year ON TaxForms(FormNumber, TaxYear);
END
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'FormLineDefinitions')
BEGIN
    CREATE TABLE FormLineDefinitions (
        LineDefId INT IDENTITY(1,1) PRIMARY KEY,
        FormId INT NOT NULL,
        LineNumber NVARCHAR(20) NOT NULL,
        Description NVARCHAR(500) NOT NULL,
        DataType NVARCHAR(50) NOT NULL DEFAULT 'currency',
        IsRequired BIT DEFAULT 0,
        SortOrder INT DEFAULT 0,
        CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME(),

        CONSTRAINT FK_FormLineDef_Form FOREIGN KEY (FormId) REFERENCES TaxForms(FormId)
    );

    CREATE INDEX IX_FormLineDef_Form ON FormLineDefinitions(FormId, SortOrder);
END
GO

-- ============================================================================
-- P0: FEDERAL FORM LINE ITEMS (High-volume · Partitioned · Columnstore)
-- ============================================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'FormLineItems')
BEGIN
    CREATE TABLE FormLineItems (
        LineItemId BIGINT IDENTITY(1,1) NOT NULL,
        ReturnId INT NOT NULL,
        TaxYear INT NOT NULL,
        FormNumber NVARCHAR(20) NOT NULL,
        LineNumber NVARCHAR(20) NOT NULL,
        LineDescription NVARCHAR(500),
        Amount DECIMAL(18,2),
        TextValue NVARCHAR(200),
        IsCalculated BIT DEFAULT 0,
        CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_FormLineItems PRIMARY KEY CLUSTERED (LineItemId, TaxYear)
    ) ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED INDEX IX_FormLineItems_Return
    ON FormLineItems(ReturnId, TaxYear, FormNumber)
    ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED INDEX IX_FormLineItems_Form
    ON FormLineItems(FormNumber, LineNumber, TaxYear)
    INCLUDE (Amount)
    ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_FormLineItems_Analytics
    ON FormLineItems (
        ReturnId, TaxYear, FormNumber, LineNumber, Amount, IsCalculated
    ) ON ps_TaxYear(TaxYear);
END
GO

-- ============================================================================
-- P0: STATE TAX FILINGS (Partitioned)
-- ============================================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'StateTaxReturns')
BEGIN
    CREATE TABLE StateTaxReturns (
        StateReturnId BIGINT IDENTITY(1,1) NOT NULL,
        FederalReturnId INT NOT NULL,
        TaxYear INT NOT NULL,
        StateCode CHAR(2) NOT NULL,
        ResidentType NVARCHAR(20) DEFAULT 'Resident',
        StateFormNumber NVARCHAR(50),
        StateGrossIncome DECIMAL(14,2),
        StateTaxableIncome DECIMAL(14,2),
        StateTaxLiability DECIMAL(14,2),
        StateWithheld DECIMAL(14,2),
        StateRefund DECIMAL(14,2),
        StateAmountOwed DECIMAL(14,2),
        Status NVARCHAR(50) DEFAULT 'Filed',
        FilingDate DATETIME2,
        CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_StateTaxReturns PRIMARY KEY CLUSTERED (StateReturnId, TaxYear)
    ) ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED INDEX IX_StateReturns_Federal
    ON StateTaxReturns(FederalReturnId, TaxYear)
    ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED INDEX IX_StateReturns_State
    ON StateTaxReturns(StateCode, TaxYear)
    INCLUDE (StateTaxLiability, StateRefund)
    ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_StateTaxReturns_Analytics
    ON StateTaxReturns (
        FederalReturnId, TaxYear, StateCode, StateGrossIncome, StateTaxableIncome,
        StateTaxLiability, StateWithheld, StateRefund, StateAmountOwed, Status
    ) ON ps_TaxYear(TaxYear);
END
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'StateFormLineItems')
BEGIN
    CREATE TABLE StateFormLineItems (
        StateLineItemId BIGINT IDENTITY(1,1) NOT NULL,
        StateReturnId BIGINT NOT NULL,
        TaxYear INT NOT NULL,
        FormNumber NVARCHAR(50) NOT NULL,
        LineNumber NVARCHAR(20) NOT NULL,
        LineDescription NVARCHAR(500),
        Amount DECIMAL(18,2),
        CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_StateFormLineItems PRIMARY KEY CLUSTERED (StateLineItemId, TaxYear)
    ) ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED INDEX IX_StateFormLine_Return
    ON StateFormLineItems(StateReturnId, TaxYear)
    ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_StateFormLineItems_Analytics
    ON StateFormLineItems (
        StateReturnId, TaxYear, FormNumber, LineNumber, Amount
    ) ON ps_TaxYear(TaxYear);
END
GO

-- ============================================================================
-- P0: E-FILE STATUS TRACKING (Partitioned)
-- ============================================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'EFileSubmissions')
BEGIN
    CREATE TABLE EFileSubmissions (
        SubmissionId BIGINT IDENTITY(1,1) NOT NULL,
        ReturnId INT NOT NULL,
        TaxYear INT NOT NULL,
        SubmissionType NVARCHAR(20) NOT NULL DEFAULT 'Original',
        TransmitterControlCode NVARCHAR(50),
        SubmissionIdIRS NVARCHAR(50),
        SubmittedAt DATETIME2 NOT NULL,
        SubmittedBy INT,
        TransmissionMethod NVARCHAR(20) DEFAULT 'MeF',
        ERO_EFIN CHAR(6),
        Status NVARCHAR(50) NOT NULL DEFAULT 'Pending',
        StatusUpdatedAt DATETIME2,
        AcknowledgmentReceived BIT DEFAULT 0,
        AcceptanceDate DATETIME2,
        RejectionCode NVARCHAR(20),
        RejectionDescription NVARCHAR(500),
        RejectionDate DATETIME2,
        RefundIssuedDate DATE,
        PaymentDueDate DATE,
        CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_EFileSubmissions PRIMARY KEY CLUSTERED (SubmissionId, TaxYear)
    ) ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED INDEX IX_EFile_Return
    ON EFileSubmissions(ReturnId, TaxYear)
    ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED INDEX IX_EFile_Status
    ON EFileSubmissions(Status, TaxYear)
    INCLUDE (ReturnId, SubmittedAt, AcceptanceDate)
    ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_EFileSubmissions_Analytics
    ON EFileSubmissions (
        ReturnId, TaxYear, SubmissionType, Status, SubmittedAt, AcceptanceDate,
        RejectionCode, RejectionDate, StatusUpdatedAt, AcknowledgmentReceived
    ) ON ps_TaxYear(TaxYear);
END
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'EFileStatusHistory')
BEGIN
    CREATE TABLE EFileStatusHistory (
        StatusHistoryId BIGINT IDENTITY(1,1) NOT NULL,
        SubmissionId BIGINT NOT NULL,
        TaxYear INT NOT NULL,
        PreviousStatus NVARCHAR(50),
        NewStatus NVARCHAR(50) NOT NULL,
        StatusMessage NVARCHAR(500),
        ChangedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        ChangedBy INT,

        CONSTRAINT PK_EFileStatusHistory PRIMARY KEY CLUSTERED (StatusHistoryId, TaxYear)
    ) ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED INDEX IX_EFileHistory_Submission
    ON EFileStatusHistory(SubmissionId, TaxYear, ChangedAt)
    ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_EFileStatusHistory_Analytics
    ON EFileStatusHistory (
        SubmissionId, TaxYear, NewStatus, ChangedAt
    ) ON ps_TaxYear(TaxYear);
END
GO

-- ============================================================================
-- P1: W-2 WAGE STATEMENTS (Partitioned)
-- ============================================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'W2Documents')
BEGIN
    CREATE TABLE W2Documents (
        W2Id BIGINT IDENTITY(1,1) NOT NULL,
        ReturnId INT NOT NULL,
        TaxYear INT NOT NULL,
        EmployerEIN CHAR(10),
        EmployerName NVARCHAR(200) NOT NULL,
        EmployerAddress NVARCHAR(500),
        EmployerCity NVARCHAR(100),
        EmployerState CHAR(2),
        EmployerZip VARCHAR(10),
        WagesBox1 DECIMAL(14,2),
        FederalWithheldBox2 DECIMAL(14,2),
        SocialSecurityWagesBox3 DECIMAL(14,2),
        SocialSecurityTaxBox4 DECIMAL(14,2),
        MedicareWagesBox5 DECIMAL(14,2),
        MedicareTaxBox6 DECIMAL(14,2),
        SocialSecurityTipsBox7 DECIMAL(14,2),
        AllocatedTipsBox8 DECIMAL(14,2),
        DependentCareBenefitsBox10 DECIMAL(14,2),
        NonqualifiedPlansBox11 DECIMAL(14,2),
        Box12Codes NVARCHAR(200),
        StatutoryEmployee BIT DEFAULT 0,
        RetirementPlan BIT DEFAULT 0,
        ThirdPartySickPay BIT DEFAULT 0,
        StateWagesBox16 DECIMAL(14,2),
        StateWithheldBox17 DECIMAL(14,2),
        LocalWagesBox18 DECIMAL(14,2),
        LocalTaxBox19 DECIMAL(14,2),
        VerificationStatus NVARCHAR(50) DEFAULT 'Verified',
        CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_W2Documents PRIMARY KEY CLUSTERED (W2Id, TaxYear)
    ) ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED INDEX IX_W2_Return
    ON W2Documents(ReturnId, TaxYear)
    ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED INDEX IX_W2_Employer
    ON W2Documents(EmployerEIN, TaxYear)
    ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_W2Documents_Analytics
    ON W2Documents (
        ReturnId, TaxYear, EmployerEIN, WagesBox1, FederalWithheldBox2,
        SocialSecurityWagesBox3, SocialSecurityTaxBox4, MedicareWagesBox5, MedicareTaxBox6,
        StateWagesBox16, StateWithheldBox17, RetirementPlan
    ) ON ps_TaxYear(TaxYear);
END
GO

-- ============================================================================
-- P1: 1099 FORMS (Partitioned)
-- ============================================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Form1099')
BEGIN
    CREATE TABLE Form1099 (
        Form1099Id BIGINT IDENTITY(1,1) NOT NULL,
        ReturnId INT NOT NULL,
        TaxYear INT NOT NULL,
        Form1099Type NVARCHAR(20) NOT NULL,
        PayerEIN CHAR(10),
        PayerName NVARCHAR(200) NOT NULL,
        PayerAddress NVARCHAR(500),
        PayerCity NVARCHAR(100),
        PayerState CHAR(2),
        PayerZip VARCHAR(10),
        GrossAmount DECIMAL(14,2),
        FederalWithheld DECIMAL(14,2) DEFAULT 0,
        StateWithheld DECIMAL(14,2) DEFAULT 0,
        DetailData JSON,
        IssueDate DATE,
        ImportedAt DATETIME2 DEFAULT SYSUTCDATETIME(),
        CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_Form1099 PRIMARY KEY CLUSTERED (Form1099Id, TaxYear)
    ) ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED INDEX IX_1099_Return
    ON Form1099(ReturnId, TaxYear)
    ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED INDEX IX_1099_Type
    ON Form1099(Form1099Type, TaxYear)
    INCLUDE (GrossAmount)
    ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_Form1099_Analytics
    ON Form1099 (
        ReturnId, TaxYear, Form1099Type, GrossAmount, FederalWithheld, StateWithheld
    ) ON ps_TaxYear(TaxYear);
END
GO

-- ============================================================================
-- P1: AUDIT LOG (Partitioned)
-- ============================================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'AuditLog')
BEGIN
    CREATE TABLE AuditLog (
        AuditId BIGINT IDENTITY(1,1) NOT NULL,
        TaxYear INT NOT NULL,
        EntityType NVARCHAR(50) NOT NULL,
        EntityId BIGINT NOT NULL,
        Action NVARCHAR(20) NOT NULL,
        UserId INT,
        UserRole NVARCHAR(50),
        IPAddress NVARCHAR(50),
        ChangedFields JSON,
        ChangedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        SessionId UNIQUEIDENTIFIER,

        CONSTRAINT PK_AuditLog PRIMARY KEY CLUSTERED (AuditId, TaxYear)
    ) ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED INDEX IX_Audit_Entity
    ON AuditLog(EntityType, EntityId, TaxYear)
    ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED INDEX IX_Audit_User
    ON AuditLog(UserId, ChangedAt, TaxYear)
    ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_AuditLog_Analytics
    ON AuditLog (
        TaxYear, EntityType, EntityId, Action, UserId, UserRole, ChangedAt
    ) ON ps_TaxYear(TaxYear);
END
GO

-- ============================================================================
-- P1: SCHEDULE DETAILS - Capital Gains (Schedule D) (Partitioned)
-- ============================================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'CapitalGainTransactions')
BEGIN
    CREATE TABLE CapitalGainTransactions (
        TransactionId BIGINT IDENTITY(1,1) NOT NULL,
        ReturnId INT NOT NULL,
        TaxYear INT NOT NULL,
        SecurityType NVARCHAR(50) NOT NULL,
        SecurityName NVARCHAR(200) NOT NULL,
        CUSIPNumber NVARCHAR(20),
        DateAcquired DATE,
        DateSold DATE,
        Quantity DECIMAL(18,8),
        CostBasis DECIMAL(18,2),
        SaleProceeds DECIMAL(18,2),
        GainOrLoss DECIMAL(18,2),
        IsShortTerm BIT DEFAULT 0,
        IsWashSale BIT DEFAULT 0,
        BrokerName NVARCHAR(200),
        CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_CapitalGainTxns PRIMARY KEY CLUSTERED (TransactionId, TaxYear)
    ) ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED INDEX IX_CapGain_Return
    ON CapitalGainTransactions(ReturnId, TaxYear)
    ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_CapitalGains_Analytics
    ON CapitalGainTransactions (
        ReturnId, TaxYear, SecurityType, Quantity, CostBasis, SaleProceeds,
        GainOrLoss, IsShortTerm, IsWashSale
    ) ON ps_TaxYear(TaxYear);
END
GO

-- ============================================================================
-- P1: SCHEDULE DETAILS - Business Income/Expenses (Schedule C)
-- ============================================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'ScheduleC_Businesses')
BEGIN
    CREATE TABLE ScheduleC_Businesses (
        BusinessId BIGINT IDENTITY(1,1) NOT NULL,
        ReturnId INT NOT NULL,
        TaxYear INT NOT NULL,
        BusinessName NVARCHAR(200) NOT NULL,
        EIN CHAR(10),
        BusinessCode CHAR(6),
        PrincipalProduct NVARCHAR(200),
        AccountingMethod NVARCHAR(20) DEFAULT 'Cash',
        MaterialParticipation BIT DEFAULT 1,
        GrossReceipts DECIMAL(14,2),
        CostOfGoodsSold DECIMAL(14,2) DEFAULT 0,
        GrossProfit DECIMAL(14,2),
        TotalExpenses DECIMAL(14,2),
        NetProfit DECIMAL(14,2),
        CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_ScheduleC PRIMARY KEY CLUSTERED (BusinessId, TaxYear)
    ) ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED INDEX IX_SchedC_Return
    ON ScheduleC_Businesses(ReturnId, TaxYear)
    ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_ScheduleC_Analytics
    ON ScheduleC_Businesses (
        ReturnId, TaxYear, BusinessCode, AccountingMethod, GrossReceipts,
        CostOfGoodsSold, GrossProfit, TotalExpenses, NetProfit
    ) ON ps_TaxYear(TaxYear);
END
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'ScheduleC_Expenses')
BEGIN
    CREATE TABLE ScheduleC_Expenses (
        ExpenseId BIGINT IDENTITY(1,1) NOT NULL,
        BusinessId BIGINT NOT NULL,
        TaxYear INT NOT NULL,
        ExpenseCategory NVARCHAR(100) NOT NULL,
        ExpenseDate DATE,
        Vendor NVARCHAR(200),
        Description NVARCHAR(500),
        Amount DECIMAL(10,2) NOT NULL,
        BusinessPercentage DECIMAL(5,2) DEFAULT 100.00,
        CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_ScheduleC_Expenses PRIMARY KEY CLUSTERED (ExpenseId, TaxYear)
    ) ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED INDEX IX_SchedCExp_Business
    ON ScheduleC_Expenses(BusinessId, TaxYear)
    ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_ScheduleC_Expenses_Analytics
    ON ScheduleC_Expenses (
        BusinessId, TaxYear, ExpenseCategory, Amount, BusinessPercentage
    ) ON ps_TaxYear(TaxYear);
END
GO

-- ============================================================================
-- P1: SCHEDULE DETAILS - Charitable Contributions (Schedule A)
-- ============================================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'CharitableContributions')
BEGIN
    CREATE TABLE CharitableContributions (
        ContributionId BIGINT IDENTITY(1,1) NOT NULL,
        ReturnId INT NOT NULL,
        TaxYear INT NOT NULL,
        OrganizationName NVARCHAR(200) NOT NULL,
        OrganizationEIN CHAR(10),
        ContributionType NVARCHAR(50) NOT NULL DEFAULT 'Cash',
        ContributionDate DATE,
        Amount DECIMAL(10,2) NOT NULL,
        FairMarketValue DECIMAL(10,2),
        DeductionLimitPct DECIMAL(5,2) DEFAULT 60.00,
        CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_CharitableContrib PRIMARY KEY CLUSTERED (ContributionId, TaxYear)
    ) ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED INDEX IX_Charitable_Return
    ON CharitableContributions(ReturnId, TaxYear)
    ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_Charitable_Analytics
    ON CharitableContributions (
        ReturnId, TaxYear, ContributionType, Amount, FairMarketValue
    ) ON ps_TaxYear(TaxYear);
END
GO

-- ============================================================================
-- SCHEDULE E: RENTAL & ROYALTY PROPERTIES (parent table)
-- ============================================================================
-- ~7M rows: ~10% of returns have rental/royalty income, avg 1.5 properties each

IF OBJECT_ID('ScheduleE_Properties', 'U') IS NULL
BEGIN
    CREATE TABLE ScheduleE_Properties (
        PropertyId BIGINT IDENTITY(1,1) NOT NULL,
        ReturnId INT NOT NULL,
        TaxYear INT NOT NULL,
        PropertyType NVARCHAR(30) NOT NULL DEFAULT 'Single Family',  -- Single Family, Multi-Family, Commercial, Land, Royalty
        PropertyAddress NVARCHAR(300),
        City NVARCHAR(100),
        StateCode CHAR(2),
        ZipCode CHAR(5),
        RentalDays INT DEFAULT 365,
        PersonalUseDays INT DEFAULT 0,
        GrossRents DECIMAL(12,2) NOT NULL DEFAULT 0,
        Advertising DECIMAL(10,2) DEFAULT 0,
        AutoAndTravel DECIMAL(10,2) DEFAULT 0,
        Cleaning DECIMAL(10,2) DEFAULT 0,
        Commissions DECIMAL(10,2) DEFAULT 0,
        Insurance DECIMAL(10,2) DEFAULT 0,
        LegalAndProfessional DECIMAL(10,2) DEFAULT 0,
        ManagementFees DECIMAL(10,2) DEFAULT 0,
        MortgageInterest DECIMAL(10,2) DEFAULT 0,
        Repairs DECIMAL(10,2) DEFAULT 0,
        Taxes DECIMAL(10,2) DEFAULT 0,
        Utilities DECIMAL(10,2) DEFAULT 0,
        Depreciation DECIMAL(10,2) DEFAULT 0,
        OtherExpenses DECIMAL(10,2) DEFAULT 0,
        TotalExpenses AS (ISNULL(Advertising,0) + ISNULL(AutoAndTravel,0) + ISNULL(Cleaning,0) +
                          ISNULL(Commissions,0) + ISNULL(Insurance,0) + ISNULL(LegalAndProfessional,0) +
                          ISNULL(ManagementFees,0) + ISNULL(MortgageInterest,0) + ISNULL(Repairs,0) +
                          ISNULL(Taxes,0) + ISNULL(Utilities,0) + ISNULL(Depreciation,0) + ISNULL(OtherExpenses,0)),
        NetRentalIncome AS (GrossRents - (ISNULL(Advertising,0) + ISNULL(AutoAndTravel,0) + ISNULL(Cleaning,0) +
                            ISNULL(Commissions,0) + ISNULL(Insurance,0) + ISNULL(LegalAndProfessional,0) +
                            ISNULL(ManagementFees,0) + ISNULL(MortgageInterest,0) + ISNULL(Repairs,0) +
                            ISNULL(Taxes,0) + ISNULL(Utilities,0) + ISNULL(Depreciation,0) + ISNULL(OtherExpenses,0))),
        CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_ScheduleE_Properties PRIMARY KEY CLUSTERED (PropertyId, TaxYear)
    ) ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED INDEX IX_ScheduleE_Prop_Return
    ON ScheduleE_Properties(ReturnId, TaxYear)
    ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_ScheduleE_Prop_Analytics
    ON ScheduleE_Properties (
        ReturnId, TaxYear, PropertyType, StateCode, GrossRents,
        MortgageInterest, Depreciation, Taxes, Insurance, Repairs
    ) ON ps_TaxYear(TaxYear);
END
GO

-- ============================================================================
-- SCHEDULE E: RENTAL INCOME ENTRIES (child table)
-- ============================================================================
-- ~28M rows: avg 4 income entries per property (monthly/quarterly rents)

IF OBJECT_ID('ScheduleE_Income', 'U') IS NULL
BEGIN
    CREATE TABLE ScheduleE_Income (
        IncomeId BIGINT IDENTITY(1,1) NOT NULL,
        PropertyId BIGINT NOT NULL,
        TaxYear INT NOT NULL,
        PayerName NVARCHAR(200),
        IncomeType NVARCHAR(30) NOT NULL DEFAULT 'Rent',  -- Rent, Royalty, Partnership, S-Corp, Trust
        PaymentDate DATE,
        Amount DECIMAL(10,2) NOT NULL,
        CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_ScheduleE_Income PRIMARY KEY CLUSTERED (IncomeId, TaxYear)
    ) ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED INDEX IX_ScheduleE_Inc_Property
    ON ScheduleE_Income(PropertyId, TaxYear)
    ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_ScheduleE_Inc_Analytics
    ON ScheduleE_Income (
        PropertyId, TaxYear, IncomeType, Amount
    ) ON ps_TaxYear(TaxYear);
END
GO

-- ============================================================================
-- SCHEDULE B: INTEREST & DIVIDEND INCOME
-- ============================================================================
-- ~170M rows: ~1-5 rows per return (bank interest, brokerage dividends)

IF OBJECT_ID('ScheduleB_InterestDividends', 'U') IS NULL
BEGIN
    CREATE TABLE ScheduleB_InterestDividends (
        EntryId BIGINT IDENTITY(1,1) NOT NULL,
        ReturnId INT NOT NULL,
        TaxYear INT NOT NULL,
        EntryType NVARCHAR(20) NOT NULL DEFAULT 'Interest',  -- Interest, Ordinary Dividend, Qualified Dividend
        PayerName NVARCHAR(200) NOT NULL,
        PayerEIN CHAR(10),
        AccountNumber NVARCHAR(30),
        Amount DECIMAL(12,2) NOT NULL,
        TaxExemptAmount DECIMAL(12,2) DEFAULT 0,
        ForeignTaxPaid DECIMAL(10,2) DEFAULT 0,
        IsForeignAccount BIT DEFAULT 0,
        CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_ScheduleB PRIMARY KEY CLUSTERED (EntryId, TaxYear)
    ) ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED INDEX IX_ScheduleB_Return
    ON ScheduleB_InterestDividends(ReturnId, TaxYear)
    ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_ScheduleB_Analytics
    ON ScheduleB_InterestDividends (
        ReturnId, TaxYear, EntryType, PayerName, Amount,
        TaxExemptAmount, ForeignTaxPaid, IsForeignAccount
    ) ON ps_TaxYear(TaxYear);
END
GO

-- ============================================================================
-- TAX FORM DOCUMENTS (metadata for all filed forms/schedules)
-- ============================================================================
-- ~200M rows: 3-6 documents per return (1040, W-2 copy, state return, etc.)

IF OBJECT_ID('TaxFormDocuments', 'U') IS NULL
BEGIN
    CREATE TABLE TaxFormDocuments (
        DocumentId BIGINT IDENTITY(1,1) NOT NULL,
        ReturnId INT NOT NULL,
        TaxYear INT NOT NULL,
        DocumentType NVARCHAR(50) NOT NULL,         -- 1040, W-2, 1099-INT, Schedule A, Schedule B, Schedule C, Schedule E, State Return
        FormName NVARCHAR(100) NOT NULL,
        PageCount INT NOT NULL DEFAULT 1,
        FileSizeBytes BIGINT NOT NULL DEFAULT 0,
        MimeType NVARCHAR(50) NOT NULL DEFAULT 'application/pdf',
        GeneratedAt DATETIME2 NOT NULL,
        SignedAt DATETIME2,
        StoragePath NVARCHAR(500),                  -- Azure Blob reference path
        ChecksumSHA256 CHAR(64),
        Status NVARCHAR(20) NOT NULL DEFAULT 'Generated',  -- Generated, Signed, Submitted, Archived
        CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_TaxFormDocuments PRIMARY KEY CLUSTERED (DocumentId, TaxYear)
    ) ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED INDEX IX_TaxFormDoc_Return
    ON TaxFormDocuments(ReturnId, TaxYear)
    ON ps_TaxYear(TaxYear);

    CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_TaxFormDoc_Analytics
    ON TaxFormDocuments (
        ReturnId, TaxYear, DocumentType, PageCount, FileSizeBytes,
        MimeType, Status
    ) ON ps_TaxYear(TaxYear);
END
GO

-- ============================================================================
-- VIEWS FOR ANALYTICS
-- ============================================================================

-- Real-time branch performance view
CREATE OR ALTER VIEW vw_BranchPerformanceRealtime AS
SELECT 
    b.BranchId,
    b.BranchName,
    b.City,
    b.StateAbbr AS State,
    COUNT_BIG(*) AS ReturnsToday,
    COUNT_BIG(CASE WHEN f.RefundAmount > 0 THEN 1 END) AS RefundsIssued,
    AVG(CAST(f.ProcessingTimeMinutes AS BIGINT)) AS AvgProcessingMinutes,
    SUM(f.RefundAmount) AS TotalRefundsToday,
    AVG(f.RefundAmount) AS AvgRefundAmount,
    COUNT_BIG(DISTINCT f.ProfessionalId) AS ActiveProfessionals
FROM TaxReturns f
JOIN Branches b ON f.BranchId = b.BranchId
WHERE f.FilingDate >= CAST(GETDATE() AS DATE)
GROUP BY b.BranchId, b.BranchName, b.City, b.StateAbbr;
GO

-- Executive dashboard view
CREATE OR ALTER VIEW vw_ExecutiveDashboard AS
SELECT 
    TaxYear,
    DATEPART(week, FilingDate) AS FilingWeek,
    DATEPART(month, FilingDate) AS FilingMonth,
    FilingStatus,
    COUNT_BIG(*) AS TotalReturns,
    SUM(RefundAmount) AS TotalRefunds,
    SUM(AmountOwed) AS TotalOwed,
    AVG(GrossIncome) AS AvgGrossIncome,
    AVG(CAST(ProcessingTimeMinutes AS BIGINT)) AS AvgProcessingTime,
    CAST(
        COUNT_BIG(CASE WHEN AIAssistanceCount > 0 THEN 1 END) * 100.0
        / NULLIF(COUNT_BIG(*), 0)
        AS DECIMAL(5,2)
    ) AS AIAssistedPct
FROM TaxReturns
GROUP BY TaxYear, DATEPART(week, FilingDate), DATEPART(month, FilingDate), FilingStatus;
GO

-- ============================================================================
-- STORED PROCEDURES
-- ============================================================================

-- Vector search for RAG
CREATE OR ALTER PROCEDURE SearchKnowledgeBase
    @QueryEmbedding VECTOR(1536),
    @TopK INT = 5
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT TOP (@TopK)
        ChunkId,
        PublicationId,
        PublicationTitle,
        Section,
        Subsection,
        Content,
        SourceUrl,
        VECTOR_DISTANCE('cosine', ContentEmbedding, @QueryEmbedding) AS Distance
    FROM TaxKnowledgeBase
    ORDER BY VECTOR_DISTANCE('cosine', ContentEmbedding, @QueryEmbedding);
END;
GO

-- NOTE: AskTaxQuestion and SearchSimilarCases procedures are created in 
-- 05_setup_azure_openai_endpoint.sql after the external model is set up.
-- They require the AzureOpenAI_Embeddings external model to exist.

-- High-throughput batch insert for load testing
CREATE OR ALTER PROCEDURE BulkInsertTaxReturns
    @BatchData NVARCHAR(MAX),  -- JSON array
    @BatchId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    
    INSERT INTO TaxReturns (
        CustomerId, BranchId, ProfessionalId, TaxYear,
        FilingDate, FilingStatus, GrossIncome, AdjustedGrossIncome,
        TotalDeductions, TaxableIncome, TaxLiability, TotalWithheld,
        RefundAmount, AmountOwed, ProcessingTimeMinutes, DocumentCount, AIAssistanceCount
    )
    SELECT 
        JSON_VALUE(r.value, '$.customer_id'),
        JSON_VALUE(r.value, '$.branch_id'),
        JSON_VALUE(r.value, '$.professional_id'),
        JSON_VALUE(r.value, '$.tax_year'),
        JSON_VALUE(r.value, '$.filing_date'),
        JSON_VALUE(r.value, '$.filing_status'),
        JSON_VALUE(r.value, '$.gross_income'),
        JSON_VALUE(r.value, '$.agi'),
        JSON_VALUE(r.value, '$.deductions'),
        JSON_VALUE(r.value, '$.taxable_income'),
        JSON_VALUE(r.value, '$.tax_liability'),
        JSON_VALUE(r.value, '$.withholding'),
        JSON_VALUE(r.value, '$.refund'),
        JSON_VALUE(r.value, '$.owed'),
        JSON_VALUE(r.value, '$.processing_minutes'),
        JSON_VALUE(r.value, '$.document_count'),
        0
    FROM OPENJSON(@BatchData) AS r;
    
    SELECT @@ROWCOUNT AS RowsInserted;
END;
GO

-- Hyperscale performance monitoring using sys.dm_db_resource_stats
CREATE OR ALTER PROCEDURE GetHyperscaleMetrics
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Resource utilization from sys.dm_db_resource_stats
    SELECT 
        'Resource Stats' AS MetricCategory,
        end_time AS SnapshotTime,
        avg_cpu_percent AS AvgCpuPercent,
        avg_data_io_percent AS AvgDataIoPercent,
        avg_log_write_percent AS AvgLogWritePercent,
        max_worker_percent AS MaxWorkerPercent,
        max_session_percent AS MaxSessionPercent
    FROM sys.dm_db_resource_stats
    WHERE end_time >= DATEADD(MINUTE, -5, SYSUTCDATETIME())
    ORDER BY end_time DESC;
    
    -- Recent insert activity
    SELECT 
        'Insert Activity' AS MetricCategory,
        COUNT_BIG(*) AS RecentInserts,
        MIN(CreatedAt) AS OldestRecord,
        MAX(CreatedAt) AS NewestRecord,
        DATEDIFF(SECOND, MIN(CreatedAt), MAX(CreatedAt)) AS TimeSpanSeconds
    FROM TaxReturns
    WHERE CreatedAt >= DATEADD(MINUTE, -5, SYSUTCDATETIME());
END;
GO

-- Hyperscale resource stats from sys.dm_db_resource_stats
CREATE OR ALTER PROCEDURE GetHyperscaleResourceStats
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        ;WITH latest AS (
            SELECT TOP (1)
                end_time,
                avg_cpu_percent,
                avg_data_io_percent,
                avg_log_write_percent,
                avg_memory_usage_percent,
                max_worker_percent,
                max_session_percent
            FROM sys.dm_db_resource_stats
            ORDER BY end_time DESC
        )
        SELECT
            DB_NAME() AS DatabaseName,
            latest.end_time AS SnapshotTime,
            latest.avg_cpu_percent AS AvgCpuPercent,
            latest.avg_data_io_percent AS AvgDataIoPercent,
            latest.avg_log_write_percent AS AvgLogWritePercent,
            latest.avg_memory_usage_percent AS AvgMemoryUsagePercent,
            latest.max_worker_percent AS MaxWorkerPercent,
            latest.max_session_percent AS MaxSessionPercent
        FROM latest;
    END TRY
    BEGIN CATCH
        SELECT
            DB_NAME() AS DatabaseName,
            SYSUTCDATETIME() AS SnapshotTime,
            CAST(NULL AS DECIMAL(5,2)) AS AvgCpuPercent,
            CAST(NULL AS DECIMAL(5,2)) AS AvgDataIoPercent,
            CAST(NULL AS DECIMAL(5,2)) AS AvgLogWritePercent,
            CAST(NULL AS DECIMAL(5,2)) AS AvgMemoryUsagePercent,
            CAST(NULL AS DECIMAL(5,2)) AS MaxWorkerPercent,
            CAST(NULL AS DECIMAL(5,2)) AS MaxSessionPercent;
    END CATCH
END;
GO

-- ============================================================================
-- AI SUMMARY CACHE
-- ============================================================================
-- Caches LLM-generated case summaries to avoid repeated API calls

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'CaseSummaryCache')
BEGIN
    CREATE TABLE CaseSummaryCache (
        CacheId INT IDENTITY(1,1) PRIMARY KEY,
        ScenarioId NVARCHAR(50) NOT NULL,
        Summary NVARCHAR(MAX) NOT NULL,
        Model NVARCHAR(100) DEFAULT 'gpt-5.2-chat',
        GeneratedAt DATETIME2 DEFAULT SYSUTCDATETIME(),
        ExpiresAt DATETIME2,
        HitCount INT DEFAULT 0,
        
        CONSTRAINT UQ_CaseSummaryCache_ScenarioId UNIQUE (ScenarioId)
    );

    CREATE INDEX IX_CaseSummaryCache_ScenarioId ON CaseSummaryCache(ScenarioId);
    CREATE INDEX IX_CaseSummaryCache_ExpiresAt ON CaseSummaryCache(ExpiresAt);
END
GO

-- Get cached summary (if not expired)
CREATE OR ALTER PROCEDURE GetCachedCaseSummary
    @ScenarioId NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    
    IF EXISTS (
        SELECT 1 FROM CaseSummaryCache 
        WHERE ScenarioId = @ScenarioId 
          AND (ExpiresAt IS NULL OR ExpiresAt > SYSUTCDATETIME())
    )
    BEGIN
        UPDATE CaseSummaryCache 
        SET HitCount = HitCount + 1
        WHERE ScenarioId = @ScenarioId;
        
        SELECT 
            ScenarioId,
            Summary,
            Model,
            GeneratedAt,
            HitCount,
            1 AS IsCached
        FROM CaseSummaryCache 
        WHERE ScenarioId = @ScenarioId;
    END
    ELSE
    BEGIN
        SELECT 
            @ScenarioId AS ScenarioId,
            NULL AS Summary,
            NULL AS Model,
            NULL AS GeneratedAt,
            0 AS HitCount,
            0 AS IsCached;
    END
END;
GO

-- Save summary to cache (upsert)
CREATE OR ALTER PROCEDURE SaveCachedCaseSummary
    @ScenarioId NVARCHAR(50),
    @Summary NVARCHAR(MAX),
    @Model NVARCHAR(100) = 'gpt-5.2-chat',
    @ExpirationDays INT = 30
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @ExpiresAt DATETIME2 = DATEADD(DAY, @ExpirationDays, SYSUTCDATETIME());
    
    MERGE CaseSummaryCache AS target
    USING (SELECT @ScenarioId AS ScenarioId) AS source
    ON target.ScenarioId = source.ScenarioId
    WHEN MATCHED THEN
        UPDATE SET 
            Summary = @Summary,
            Model = @Model,
            GeneratedAt = SYSUTCDATETIME(),
            ExpiresAt = @ExpiresAt,
            HitCount = 0
    WHEN NOT MATCHED THEN
        INSERT (ScenarioId, Summary, Model, ExpiresAt)
        VALUES (@ScenarioId, @Summary, @Model, @ExpiresAt);
    
    SELECT 
        ScenarioId,
        Summary,
        Model,
        GeneratedAt,
        ExpiresAt,
        HitCount,
        1 AS Saved
    FROM CaseSummaryCache 
    WHERE ScenarioId = @ScenarioId;
END;
GO

-- Clear expired cache entries (maintenance)
CREATE OR ALTER PROCEDURE ClearExpiredCaseSummaries
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @DeletedCount INT;
    
    DELETE FROM CaseSummaryCache 
    WHERE ExpiresAt IS NOT NULL AND ExpiresAt < SYSUTCDATETIME();
    
    SET @DeletedCount = @@ROWCOUNT;
    
    SELECT @DeletedCount AS DeletedCount;
END;
GO

-- ============================================================================
-- ANALYTICS STORED PROCEDURES (Hyperscale Named Replica / CCI)
-- ============================================================================
-- These procedures power the Branch Manager and COO dashboards.
-- They run on the named replica and leverage the Nonclustered Columnstore Index
-- (NCCI) on TaxReturns for efficient analytical scans and aggregations,
-- demonstrating HTAP on Azure SQL Hyperscale.
-- ============================================================================

-- 1. Branch Performance Analytics (Branch Manager Dashboard)
CREATE OR ALTER PROCEDURE dbo.GetBranchAnalytics
    @BranchId INT = 1,
    @TaxYear INT = 0
AS
BEGIN
    SET NOCOUNT ON;

    -- Default to current year if not specified (0 or NULL)
    IF @TaxYear IS NULL OR @TaxYear = 0
        SET @TaxYear = YEAR(GETDATE());

    SELECT
        b.BranchName,
        b.City + ', ' + b.StateAbbr AS BranchLocation,
        @TaxYear AS TaxYear,
        (SELECT COUNT_BIG(*) FROM TaxProfessionals WHERE BranchId = @BranchId AND IsActive = 1) AS TeamMembers,
        COUNT_BIG(tr.ReturnId) AS TotalReturns,
        SUM(tr.GrossIncome) AS TotalIncomeProcessed,
        AVG(CAST(tr.ProcessingTimeMinutes AS BIGINT)) AS AvgProcessingMinutes,
        COUNT_BIG(CASE WHEN tr.FilingDate >= DATEADD(DAY, -30, SYSUTCDATETIME()) THEN 1 END) AS ReturnsLast30Days,
        COUNT_BIG(CASE WHEN tr.FilingDate >= DATEADD(DAY, -7, SYSUTCDATETIME()) THEN 1 END) AS ReturnsLast7Days,
        SUM(CASE WHEN tr.FilingDate >= DATEADD(DAY, -30, SYSUTCDATETIME()) THEN tr.GrossIncome ELSE 0 END) AS IncomeLast30Days,
        AVG(CASE WHEN tr.FilingDate >= DATEADD(DAY, -30, SYSUTCDATETIME()) THEN CAST(tr.ProcessingTimeMinutes AS BIGINT) END) AS AvgProcessingLast30Days,
        COUNT_BIG(CASE WHEN tr.Status = 'Accepted' THEN 1 END) AS AcceptedReturns,
        COUNT_BIG(CASE WHEN tr.Status = 'Pending' THEN 1 END) AS PendingReturns,
        COUNT_BIG(CASE WHEN tr.Status = 'Rejected' THEN 1 END) AS RejectedReturns,
        SUM(tr.RefundAmount) AS TotalRefunds,
        SUM(tr.AmountOwed) AS TotalAmountOwed,
        AVG(tr.TotalDeductions) AS AvgDeductions
    FROM TaxReturns tr
    INNER JOIN Branches b ON b.BranchId = tr.BranchId
    WHERE tr.BranchId = @BranchId
      AND tr.TaxYear = @TaxYear
    GROUP BY b.BranchName, b.City, b.StateAbbr;
END
GO

-- 2. Branch Leaderboard (professionals ranked by returns filed)
CREATE OR ALTER PROCEDURE dbo.GetBranchLeaderboard
    @BranchId INT = 1,
    @TaxYear INT = 0
AS
BEGIN
    SET NOCOUNT ON;

    -- Default to current year if not specified (0 or NULL)
    IF @TaxYear IS NULL OR @TaxYear = 0
        SET @TaxYear = YEAR(GETDATE());

    SELECT TOP 10
        tp.ProfessionalId,
        tp.FirstName + ' ' + tp.LastName AS ProfessionalName,
        LEFT(tp.FirstName, 1) + LEFT(tp.LastName, 1) AS Initials,
        tp.Certification,
        COUNT_BIG(tr.ReturnId) AS TotalReturns,
        SUM(tr.GrossIncome) AS TotalIncomeProcessed,
        AVG(CAST(tr.ProcessingTimeMinutes AS BIGINT)) AS AvgProcessingMinutes,
        AVG(tr.TotalDeductions) AS AvgDeductions,
        SUM(tr.RefundAmount) AS TotalRefunds
    FROM TaxProfessionals tp
    INNER JOIN TaxReturns tr ON tr.ProfessionalId = tp.ProfessionalId
    WHERE tp.BranchId = @BranchId
      AND tr.TaxYear = @TaxYear
    GROUP BY tp.ProfessionalId, tp.FirstName, tp.LastName, tp.Certification
    ORDER BY COUNT_BIG(tr.ReturnId) DESC;
END
GO

-- 3. Executive KPIs (COO Dashboard — company-wide CCI scan)
CREATE OR ALTER PROCEDURE dbo.GetExecutiveKPIs
    @TaxYear INT = 0
AS
BEGIN
    SET NOCOUNT ON;

    -- Default to current year if not specified (0 or NULL)
    IF @TaxYear IS NULL OR @TaxYear = 0
        SET @TaxYear = YEAR(GETDATE());

    SELECT
        COUNT_BIG(tr.ReturnId) AS TotalReturns,
        COUNT_BIG(DISTINCT tr.CustomerId) AS ActiveCustomers,
        COUNT_BIG(DISTINCT tr.BranchId) AS ActiveBranches,
        SUM(CAST(tr.GrossIncome AS DECIMAL(19,2))) AS TotalIncomeProcessed,
        AVG(CAST(tr.GrossIncome AS DECIMAL(19,2))) AS AvgIncomePerReturn,
        AVG(CAST(tr.ProcessingTimeMinutes AS DECIMAL(19,2))) AS AvgProcessingMinutes,
        SUM(CAST(tr.RefundAmount AS DECIMAL(19,2))) AS TotalRefunds,
        SUM(CAST(tr.AmountOwed AS DECIMAL(19,2))) AS TotalAmountOwed,
        COUNT_BIG(CASE WHEN tr.Status = 'Accepted' THEN 1 END) AS AcceptedReturns,
        COUNT_BIG(CASE WHEN tr.Status = 'Filed' THEN 1 END) AS FiledReturns,
        COUNT_BIG(CASE WHEN tr.Status = 'In Progress' THEN 1 END) AS InProgressReturns,
        COUNT_BIG(CASE WHEN tr.Status = 'Rejected' THEN 1 END) AS RejectedReturns,
        COUNT_BIG(CASE WHEN tr.Status = 'Draft' THEN 1 END) AS DraftReturns,
        COUNT_BIG(CASE WHEN tr.FilingDate >= DATEADD(DAY, -30, SYSUTCDATETIME()) THEN 1 END) AS ReturnsLast30Days,
        SUM(CASE 
            WHEN tr.FilingDate >= DATEADD(DAY, -30, SYSUTCDATETIME()) THEN CAST(tr.GrossIncome AS DECIMAL(19,2))
            ELSE CAST(0 AS DECIMAL(19,2))
        END) AS IncomeLast30Days
    FROM TaxReturns tr
    WHERE tr.TaxYear = @TaxYear;
END
GO

-- 4. Top Branches (ranked by returns — executive dashboard)
CREATE OR ALTER PROCEDURE dbo.GetTopBranches
    @TopN INT = 10,
    @TaxYear INT = 0
AS
BEGIN
    SET NOCOUNT ON;

    -- Default to current year if not specified (0 or NULL)
    IF @TaxYear IS NULL OR @TaxYear = 0
        SET @TaxYear = YEAR(GETDATE());

    SELECT TOP (@TopN)
        b.BranchId,
        b.BranchName,
        b.City + ', ' + b.StateAbbr AS BranchLocation,
        COUNT_BIG(tr.ReturnId) AS TotalReturns,
        SUM(tr.GrossIncome) AS TotalIncomeProcessed,
        AVG(CAST(tr.ProcessingTimeMinutes AS BIGINT)) AS AvgProcessingMinutes,
        COUNT_BIG(DISTINCT tr.ProfessionalId) AS StaffCount,
        AVG(tr.TotalDeductions) AS AvgDeductions,
        SUM(tr.RefundAmount) AS TotalRefunds
    FROM TaxReturns tr
    INNER JOIN Branches b ON b.BranchId = tr.BranchId
    WHERE tr.TaxYear = @TaxYear
    GROUP BY b.BranchId, b.BranchName, b.City, b.StateAbbr
    ORDER BY COUNT_BIG(tr.ReturnId) DESC;
END
GO

-- 5. Filing Status Distribution (executive analytics)
CREATE OR ALTER PROCEDURE dbo.GetFilingStatusDistribution
    @TaxYear INT = 0
AS
BEGIN
    SET NOCOUNT ON;

    -- Default to current year if not specified (0 or NULL)
    IF @TaxYear IS NULL OR @TaxYear = 0
        SET @TaxYear = YEAR(GETDATE());

    SELECT
        FilingStatus,
        COUNT_BIG(*) AS ReturnCount,
        CAST(COUNT_BIG(*) * 100.0 / SUM(COUNT_BIG(*)) OVER() AS DECIMAL(5,1)) AS Percentage,
        AVG(GrossIncome) AS AvgIncome,
        AVG(TotalDeductions) AS AvgDeductions,
        AVG(RefundAmount) AS AvgRefund
    FROM TaxReturns
    WHERE TaxYear = @TaxYear
    GROUP BY FilingStatus
    ORDER BY COUNT_BIG(*) DESC;
END
GO

-- 6. Returns by Tax Year (trend analysis)
CREATE OR ALTER PROCEDURE dbo.GetReturnsByYear
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        TaxYear,
        COUNT_BIG(*) AS ReturnCount,
        SUM(GrossIncome) AS TotalIncomeProcessed,
        AVG(GrossIncome) AS AvgIncome,
        AVG(CAST(ProcessingTimeMinutes AS BIGINT)) AS AvgProcessingMinutes,
        SUM(RefundAmount) AS TotalRefunds,
        SUM(AmountOwed) AS TotalOwed,
        COUNT_BIG(CASE WHEN IsItemized = 1 THEN 1 END) AS ItemizedCount,
        COUNT_BIG(CASE WHEN IsItemized = 0 OR IsItemized IS NULL THEN 1 END) AS StandardCount
    FROM TaxReturns
    GROUP BY TaxYear
    ORDER BY TaxYear DESC;
END
GO

-- ============================================================================
-- 7. E-File Status Summary (acceptance/rejection rates)
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.GetEFileStatusSummary
    @TaxYear INT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF @TaxYear IS NULL OR @TaxYear = 0
        SET @TaxYear = YEAR(GETDATE());

    -- Returns one row per status for the frontend status-breakdown bar chart.
    -- DATEDIFF returns INT; casting to BIGINT before AVG prevents arithmetic
    -- overflow when millions of rows are aggregated.
    SELECT
        @TaxYear AS TaxYear,
        Status,
        COUNT_BIG(*) AS StatusCount,
        AVG(CAST(DATEDIFF(HOUR, SubmittedAt,
                 COALESCE(AcceptanceDate, RejectionDate, StatusUpdatedAt)) AS BIGINT)) AS AvgProcessingHours
    FROM EFileSubmissions
    WHERE TaxYear = @TaxYear
    GROUP BY Status
    ORDER BY COUNT_BIG(*) DESC;
END
GO

-- ============================================================================
-- 8. W-2 Wage Summary (employer/wage analytics by branch or company)
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.GetW2Summary
    @TaxYear INT = 0,
    @BranchId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @TaxYear IS NULL OR @TaxYear = 0
        SET @TaxYear = YEAR(GETDATE());

    -- DAB sends 0 for BranchId when caller omits it; treat 0 as "no filter".
    IF @BranchId = 0
        SET @BranchId = NULL;

    -- Fast path: no branch filter → scan W2Documents NCCI only (no JOIN).
    IF @BranchId IS NULL
    BEGIN
        SELECT
            @TaxYear AS TaxYear,
            COUNT_BIG(*) AS TotalW2s,
            COUNT_BIG(DISTINCT w.ReturnId) AS ReturnsWithW2,
            SUM(w.WagesBox1) AS TotalWages,
            AVG(w.WagesBox1) AS AvgWages,
            SUM(w.FederalWithheldBox2) AS TotalFederalWithheld,
            AVG(w.FederalWithheldBox2) AS AvgFederalWithheld,
            SUM(w.SocialSecurityTaxBox4) AS TotalSSTax,
            SUM(w.MedicareTaxBox6) AS TotalMedicareTax,
            SUM(w.StateWithheldBox17) AS TotalStateWithheld,
            COUNT_BIG(CASE WHEN w.RetirementPlan = 1 THEN 1 END) AS RetirementPlanCount,
            CAST(COUNT_BIG(CASE WHEN w.RetirementPlan = 1 THEN 1 END) * 100.0
                 / NULLIF(COUNT_BIG(*), 0) AS DECIMAL(5,2)) AS RetirementPlanPct
        FROM W2Documents w
        WHERE w.TaxYear = @TaxYear;
    END
    ELSE
    BEGIN
        -- Branch filter: must JOIN to TaxReturns to resolve BranchId.
        SELECT
            @TaxYear AS TaxYear,
            COUNT_BIG(*) AS TotalW2s,
            COUNT_BIG(DISTINCT w.ReturnId) AS ReturnsWithW2,
            SUM(w.WagesBox1) AS TotalWages,
            AVG(w.WagesBox1) AS AvgWages,
            SUM(w.FederalWithheldBox2) AS TotalFederalWithheld,
            AVG(w.FederalWithheldBox2) AS AvgFederalWithheld,
            SUM(w.SocialSecurityTaxBox4) AS TotalSSTax,
            SUM(w.MedicareTaxBox6) AS TotalMedicareTax,
            SUM(w.StateWithheldBox17) AS TotalStateWithheld,
            COUNT_BIG(CASE WHEN w.RetirementPlan = 1 THEN 1 END) AS RetirementPlanCount,
            CAST(COUNT_BIG(CASE WHEN w.RetirementPlan = 1 THEN 1 END) * 100.0
                 / NULLIF(COUNT_BIG(*), 0) AS DECIMAL(5,2)) AS RetirementPlanPct
        FROM W2Documents w
        INNER JOIN TaxReturns tr ON tr.ReturnId = w.ReturnId AND tr.TaxYear = w.TaxYear
        WHERE w.TaxYear = @TaxYear
          AND tr.BranchId = @BranchId;
    END
END
GO

-- ============================================================================
-- 9. 1099 Type Distribution (income source analytics)
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.GetForm1099Summary
    @TaxYear INT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF @TaxYear IS NULL OR @TaxYear = 0
        SET @TaxYear = YEAR(GETDATE());

    SELECT
        @TaxYear AS TaxYear,
        Form1099Type,
        COUNT_BIG(*) AS FormCount,
        CAST(COUNT_BIG(*) * 100.0 / SUM(COUNT_BIG(*)) OVER() AS DECIMAL(5,2)) AS PctOfTotal,
        SUM(GrossAmount) AS TotalGrossAmount,
        AVG(GrossAmount) AS AvgGrossAmount,
        SUM(FederalWithheld) AS TotalFederalWithheld,
        SUM(StateWithheld) AS TotalStateWithheld
    FROM Form1099
    WHERE TaxYear = @TaxYear
    GROUP BY Form1099Type
    ORDER BY COUNT_BIG(*) DESC;
END
GO

-- ============================================================================
-- 10. Capital Gains Summary (investment analytics)
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.GetCapitalGainsSummary
    @TaxYear INT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF @TaxYear IS NULL OR @TaxYear = 0
        SET @TaxYear = YEAR(GETDATE());

    SELECT
        @TaxYear AS TaxYear,
        COUNT_BIG(DISTINCT ReturnId) AS InvestorCount,
        COUNT_BIG(*) AS TotalTransactions,
        SUM(CASE WHEN GainOrLoss > 0 THEN GainOrLoss ELSE 0 END) AS TotalGains,
        SUM(CASE WHEN GainOrLoss < 0 THEN GainOrLoss ELSE 0 END) AS TotalLosses,
        SUM(GainOrLoss) AS NetGainLoss,
        SUM(CostBasis) AS TotalCostBasis,
        SUM(SaleProceeds) AS TotalProceeds,
        COUNT_BIG(CASE WHEN IsShortTerm = 1 THEN 1 END) AS ShortTermCount,
        COUNT_BIG(CASE WHEN IsShortTerm = 0 THEN 1 END) AS LongTermCount,
        COUNT_BIG(CASE WHEN IsWashSale = 1 THEN 1 END) AS WashSaleCount,
        AVG(CAST(Quantity AS DECIMAL(18,2))) AS AvgSharesPerTrade
    FROM CapitalGainTransactions
    WHERE TaxYear = @TaxYear;
END
GO

-- ============================================================================
-- 11. Schedule C Self-Employment Summary
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.GetScheduleCSummary
    @TaxYear INT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF @TaxYear IS NULL OR @TaxYear = 0
        SET @TaxYear = YEAR(GETDATE());

    SELECT
        @TaxYear AS TaxYear,
        COUNT_BIG(*) AS TotalBusinesses,
        SUM(GrossReceipts) AS TotalGrossReceipts,
        SUM(NetProfit) AS TotalNetProfit,
        AVG(GrossReceipts) AS AvgGrossReceipts,
        AVG(NetProfit) AS AvgNetProfit,
        SUM(TotalExpenses) AS TotalExpenses,
        CAST(SUM(TotalExpenses) * 100.0 / NULLIF(SUM(GrossReceipts), 0) AS DECIMAL(5,2)) AS ExpenseRatioPct,
        COUNT_BIG(CASE WHEN AccountingMethod = 'Cash' THEN 1 END) AS CashMethodCount,
        COUNT_BIG(CASE WHEN AccountingMethod = 'Accrual' THEN 1 END) AS AccrualMethodCount
    FROM ScheduleC_Businesses
    WHERE TaxYear = @TaxYear;
END
GO

-- ============================================================================
-- 12. Schedule E Rental & Royalty Summary
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.GetScheduleESummary
    @TaxYear INT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF @TaxYear IS NULL OR @TaxYear = 0
        SET @TaxYear = YEAR(GETDATE());

    SELECT
        @TaxYear AS TaxYear,
        COUNT_BIG(*) AS TotalProperties,
        COUNT_BIG(DISTINCT ReturnId) AS ReturnCount,
        SUM(GrossRents) AS TotalRents,
        AVG(GrossRents) AS AvgRentPerProperty,
        SUM(MortgageInterest) AS TotalMortgageInterest,
        SUM(Depreciation) AS TotalDepreciation,
        SUM(Taxes) AS TotalPropertyTaxes,
        SUM(GrossRents - (ISNULL(Advertising,0) + ISNULL(AutoAndTravel,0) + ISNULL(Cleaning,0) +
            ISNULL(Commissions,0) + ISNULL(Insurance,0) + ISNULL(LegalAndProfessional,0) +
            ISNULL(ManagementFees,0) + ISNULL(MortgageInterest,0) + ISNULL(Repairs,0) +
            ISNULL(Taxes,0) + ISNULL(Utilities,0) + ISNULL(Depreciation,0) + ISNULL(OtherExpenses,0)))
            AS TotalNetRentalIncome,
        COUNT_BIG(CASE WHEN PropertyType = 'Single Family' THEN 1 END) AS SingleFamilyCount,
        COUNT_BIG(CASE WHEN PropertyType = 'Multi-Family' THEN 1 END) AS MultiFamilyCount,
        COUNT_BIG(CASE WHEN PropertyType = 'Commercial' THEN 1 END) AS CommercialCount,
        COUNT_BIG(CASE WHEN PropertyType = 'Royalty' THEN 1 END) AS RoyaltyCount
    FROM ScheduleE_Properties
    WHERE TaxYear = @TaxYear;
END
GO

-- ============================================================================
-- 13. Schedule B Interest & Dividend Summary
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.GetScheduleBSummary
    @TaxYear INT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF @TaxYear IS NULL OR @TaxYear = 0
        SET @TaxYear = YEAR(GETDATE());

    SELECT
        @TaxYear AS TaxYear,
        COUNT_BIG(*) AS TotalEntries,
        COUNT_BIG(DISTINCT ReturnId) AS ReturnCount,
        SUM(CASE WHEN EntryType = 'Interest' THEN Amount ELSE 0 END) AS TotalInterestIncome,
        SUM(CASE WHEN EntryType LIKE '%Dividend%' THEN Amount ELSE 0 END) AS TotalDividendIncome,
        SUM(Amount) AS TotalInvestmentIncome,
        AVG(Amount) AS AvgAmountPerEntry,
        SUM(TaxExemptAmount) AS TotalTaxExempt,
        SUM(ForeignTaxPaid) AS TotalForeignTaxPaid,
        COUNT_BIG(CASE WHEN IsForeignAccount = 1 THEN 1 END) AS ForeignAccountCount,
        COUNT_BIG(CASE WHEN EntryType = 'Interest' THEN 1 END) AS InterestEntryCount,
        COUNT_BIG(CASE WHEN EntryType = 'Ordinary Dividend' THEN 1 END) AS OrdinaryDivCount,
        COUNT_BIG(CASE WHEN EntryType = 'Qualified Dividend' THEN 1 END) AS QualifiedDivCount
    FROM ScheduleB_InterestDividends
    WHERE TaxYear = @TaxYear;
END
GO

-- ============================================================================
-- 14. Tax Form Document Summary
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.GetDocumentSummary
    @TaxYear INT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF @TaxYear IS NULL OR @TaxYear = 0
        SET @TaxYear = YEAR(GETDATE());

    SELECT
        @TaxYear AS TaxYear,
        COUNT_BIG(*) AS TotalDocuments,
        COUNT_BIG(DISTINCT ReturnId) AS ReturnCount,
        SUM(PageCount) AS TotalPages,
        SUM(FileSizeBytes) AS TotalStorageBytes,
        CAST(SUM(FileSizeBytes) / 1073741824.0 AS DECIMAL(12,2)) AS TotalStorageGB,
        AVG(PageCount) AS AvgPagesPerDoc,
        AVG(FileSizeBytes) AS AvgFileSizeBytes,
        COUNT_BIG(CASE WHEN Status = 'Signed' THEN 1 END) AS SignedCount,
        COUNT_BIG(CASE WHEN Status = 'Submitted' THEN 1 END) AS SubmittedCount,
        COUNT_BIG(CASE WHEN Status = 'Archived' THEN 1 END) AS ArchivedCount,
        COUNT_BIG(CASE WHEN Status = 'Generated' THEN 1 END) AS GeneratedCount,
        COUNT_BIG(CASE WHEN DocumentType = '1040' THEN 1 END) AS Form1040Count,
        COUNT_BIG(CASE WHEN DocumentType = 'W-2' THEN 1 END) AS W2CopyCount,
        COUNT_BIG(CASE WHEN DocumentType LIKE 'Schedule%' THEN 1 END) AS ScheduleCount
    FROM TaxFormDocuments
    WHERE TaxYear = @TaxYear;
END
GO

-- ============================================================================
-- 15. Filing Detail Overview (cross-table summary for executive dashboard)
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.GetFilingDetailOverview
    @TaxYear INT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF @TaxYear IS NULL OR @TaxYear = 0
        SET @TaxYear = YEAR(GETDATE());

    -- Table row counts for the filing detail layer
    SELECT
        @TaxYear AS TaxYear,
        (SELECT COUNT_BIG(*) FROM FormLineItems WHERE TaxYear = @TaxYear) AS FormLineItemRows,
        (SELECT COUNT_BIG(*) FROM StateTaxReturns WHERE TaxYear = @TaxYear) AS StateReturnRows,
        (SELECT COUNT_BIG(*) FROM StateFormLineItems WHERE TaxYear = @TaxYear) AS StateLineItemRows,
        (SELECT COUNT_BIG(*) FROM EFileSubmissions WHERE TaxYear = @TaxYear) AS EFileRows,
        (SELECT COUNT_BIG(*) FROM EFileStatusHistory WHERE TaxYear = @TaxYear) AS EFileHistoryRows,
        (SELECT COUNT_BIG(*) FROM W2Documents WHERE TaxYear = @TaxYear) AS W2Rows,
        (SELECT COUNT_BIG(*) FROM Form1099 WHERE TaxYear = @TaxYear) AS Form1099Rows,
        (SELECT COUNT_BIG(*) FROM CapitalGainTransactions WHERE TaxYear = @TaxYear) AS CapGainRows,
        (SELECT COUNT_BIG(*) FROM ScheduleC_Businesses WHERE TaxYear = @TaxYear) AS ScheduleCRows,
        (SELECT COUNT_BIG(*) FROM ScheduleC_Expenses WHERE TaxYear = @TaxYear) AS ScheduleCExpenseRows,
        (SELECT COUNT_BIG(*) FROM CharitableContributions WHERE TaxYear = @TaxYear) AS CharitableRows,
        (SELECT COUNT_BIG(*) FROM ScheduleE_Properties WHERE TaxYear = @TaxYear) AS ScheduleEPropertyRows,
        (SELECT COUNT_BIG(*) FROM ScheduleE_Income WHERE TaxYear = @TaxYear) AS ScheduleEIncomeRows,
        (SELECT COUNT_BIG(*) FROM ScheduleB_InterestDividends WHERE TaxYear = @TaxYear) AS ScheduleBRows,
        (SELECT COUNT_BIG(*) FROM TaxFormDocuments WHERE TaxYear = @TaxYear) AS TaxFormDocumentRows,
        (SELECT COUNT_BIG(*) FROM AuditLog WHERE TaxYear = @TaxYear) AS AuditLogRows;
END
GO

-- ============================================================================
-- 16. State Tax Summary (state-level analytics)
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.GetStateTaxSummary
    @TaxYear INT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF @TaxYear IS NULL OR @TaxYear = 0
        SET @TaxYear = YEAR(GETDATE());

    SELECT TOP 20
        @TaxYear AS TaxYear,
        StateCode,
        COUNT_BIG(*) AS ReturnCount,
        SUM(StateGrossIncome) AS TotalGrossIncome,
        SUM(StateTaxLiability) AS TotalTaxLiability,
        AVG(StateTaxLiability) AS AvgTaxLiability,
        SUM(StateRefund) AS TotalRefunds,
        SUM(StateAmountOwed) AS TotalOwed,
        CAST(SUM(StateTaxLiability) * 100.0 / NULLIF(SUM(StateGrossIncome), 0) AS DECIMAL(5,3)) AS EffectiveRatePct,
        COUNT_BIG(CASE WHEN Status = 'Accepted' THEN 1 END) AS AcceptedCount
    FROM StateTaxReturns
    WHERE TaxYear = @TaxYear
    GROUP BY StateCode
    ORDER BY COUNT_BIG(*) DESC;
END
GO

-- ============================================================================
-- GetReplicaInfo: Returns DB identity to prove which replica served the query
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.GetReplicaInfo
AS
BEGIN
    SET NOCOUNT ON;
    SELECT 
        DB_NAME() AS DatabaseName,
        CAST(DATABASEPROPERTYEX(DB_NAME(), 'Updateability') AS NVARCHAR(20)) AS Updateability,
        @@SERVERNAME AS ServerName,
        GETUTCDATE() AS QueryTimeUTC;
END
GO

PRINT 'Schema creation complete!';
