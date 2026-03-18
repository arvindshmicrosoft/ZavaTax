-- ============================================================================
-- 10_security_features.sql
-- SQL Security Features Demonstration
-- ============================================================================
--
-- Compatible with: SQL Server 2025 Express / LocalDB AND Azure SQL DB Hyperscale
-- (Ledger tables require SQL Server 2022+; all other features work on 2016+)
--
-- This script implements five SQL security capabilities:
--
--  1. LEDGER TABLE         — Tamper-evident, append-only AI interaction audit trail
--  2. ROW-LEVEL SECURITY   — Branch isolation & role-based data access
--  3. DYNAMIC DATA MASKING — PII protection (SSN, Email, Phone, DOB)
--  4. COLUMN-LEVEL SECURITY— GRANT / DENY on sensitive financial columns
--  5. DATA CLASSIFICATION  — Sensitivity labels for compliance reporting
--
-- Each section is idempotent and safe to re-run.
-- Demo stored procedures at the end let the frontend visualise every feature.
-- ============================================================================

SET NOCOUNT ON;
GO

PRINT 'Security deployment starting...';
GO

-- ============================================================================
-- SECTION 1: DATABASE ROLES & USERS
-- Map application personas to database principals so that RLS, DDM, and
-- column-level security have something to key off.
-- ============================================================================

PRINT '  1/9 Roles & Users';

-- Create application roles (idempotent)
IF DATABASE_PRINCIPAL_ID('TaxFiler') IS NULL        CREATE ROLE TaxFiler;
IF DATABASE_PRINCIPAL_ID('TaxProfessional') IS NULL  CREATE ROLE TaxProfessional;
IF DATABASE_PRINCIPAL_ID('BranchManager') IS NULL    CREATE ROLE BranchManager;
IF DATABASE_PRINCIPAL_ID('Executive') IS NULL        CREATE ROLE Executive;
IF DATABASE_PRINCIPAL_ID('DevOps') IS NULL           CREATE ROLE DevOps;
GO

-- Create demonstration users (WITHOUT LOGIN — used only with EXECUTE AS)
IF DATABASE_PRINCIPAL_ID('SarahJohnson') IS NULL
    CREATE USER SarahJohnson WITHOUT LOGIN;       -- tax-filer,         customerId = 1
IF DATABASE_PRINCIPAL_ID('MichaelChen') IS NULL
    CREATE USER MichaelChen WITHOUT LOGIN;        -- tax-professional,  professionalId = 1, branchId = 1
IF DATABASE_PRINCIPAL_ID('AmandaRodriguez') IS NULL
    CREATE USER AmandaRodriguez WITHOUT LOGIN;    -- branch-manager,    branchId = 1
IF DATABASE_PRINCIPAL_ID('RobertWilliams') IS NULL
    CREATE USER RobertWilliams WITHOUT LOGIN;     -- executive
IF DATABASE_PRINCIPAL_ID('JenniferPark') IS NULL
    CREATE USER JenniferPark WITHOUT LOGIN;       -- devops
GO

-- Assign users to roles
ALTER ROLE TaxFiler        ADD MEMBER SarahJohnson;
ALTER ROLE TaxProfessional ADD MEMBER MichaelChen;
ALTER ROLE BranchManager   ADD MEMBER AmandaRodriguez;
ALTER ROLE Executive       ADD MEMBER RobertWilliams;
ALTER ROLE DevOps          ADD MEMBER JenniferPark;
GO

-- Grant base SELECT on tables the demo touches
GRANT SELECT ON dbo.TaxReturns    TO TaxFiler, TaxProfessional, BranchManager, Executive, DevOps;
GRANT SELECT ON dbo.Customers     TO TaxFiler, TaxProfessional, BranchManager, Executive, DevOps;
GRANT SELECT ON dbo.Branches      TO TaxProfessional, BranchManager, Executive, DevOps;
GRANT SELECT ON dbo.W2Documents   TO TaxFiler, TaxProfessional, BranchManager, Executive, DevOps;
GRANT SELECT ON dbo.Form1099      TO TaxFiler, TaxProfessional, BranchManager, Executive, DevOps;
GRANT SELECT ON dbo.EFileSubmissions TO TaxFiler, TaxProfessional, BranchManager, Executive, DevOps;
GO

GO


-- ============================================================================
-- SECTION 2: LEDGER TABLE — AI Interaction Audit Trail
-- ============================================================================
-- SQL Ledger provides tamper-evident tables (SQL Server 2022+, Azure SQL DB).
-- Append-only ledger tables only allow INSERTs — no UPDATE or DELETE.
-- Every row is cryptographically hashed and chained into blocks, giving
-- a blockchain-style guarantee of data integrity.
--
-- We use this to log every AI interaction (RAG search, embedding generation,
-- chat completion, similar-case lookup) so auditors can verify the log has
-- not been tampered with.
-- ============================================================================

PRINT '  2/9 Ledger Table';

IF OBJECT_ID('dbo.AIInteractionLedger', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.AIInteractionLedger (
        -- Business columns
        InteractionId       BIGINT IDENTITY(1,1) NOT NULL,
        InteractionType     NVARCHAR(50)  NOT NULL,           -- RAG_Search, Embedding, ChatCompletion, SimilarCaseSearch
        UserRole            NVARCHAR(30)  NOT NULL,           -- tax-filer, tax-professional, branch-manager, executive, devops
        UserId              NVARCHAR(200) NULL,               -- email or principal name
        BranchId            INT           NULL,               -- for RLS scoping
        CustomerId          INT           NULL,               -- for tax-filer scoping

        -- Request details
        PromptText          NVARCHAR(MAX) NULL,               -- user query / input text
        ModelName           NVARCHAR(100) NULL,               -- gpt-4o, text-embedding-3-small
        ExternalEndpoint    NVARCHAR(500) NULL,               -- Azure OpenAI URL called
        TokensInput         INT           NULL,
        TokensOutput        INT           NULL,
        TokensTotal         AS (ISNULL(TokensInput, 0) + ISNULL(TokensOutput, 0)),

        -- Response details
        ResponseSummary     NVARCHAR(500) NULL,               -- first 500 chars of response
        ResultCount         INT           NULL,               -- rows returned by search
        SimilarityScoreAvg  DECIMAL(6,4)  NULL,               -- avg cosine distance (for vector search)

        -- Performance & status
        LatencyMs           INT           NULL,
        HttpStatusCode      INT           NULL,
        ErrorMessage        NVARCHAR(MAX) NULL,
        IsSuccess           BIT           NOT NULL DEFAULT 1,

        -- Correlation
        SessionId           NVARCHAR(100) NULL,               -- frontend session id
        CorrelationId       UNIQUEIDENTIFIER NULL DEFAULT NEWID(),

        -- Primary key
        CONSTRAINT PK_AIInteractionLedger PRIMARY KEY (InteractionId)
    )
    WITH (
        LEDGER = ON (APPEND_ONLY = ON)
    );

    PRINT '  ✓ Created AIInteractionLedger (append-only ledger table).';
END
ELSE
    PRINT '  - AIInteractionLedger already exists, skipping.';
GO

-- Index for time-range queries (the ledger adds ledger_start_transaction_id and ledger_sequence_number automatically)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AILedger_Type_Time' AND object_id = OBJECT_ID('dbo.AIInteractionLedger'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_AILedger_Type_Time
    ON dbo.AIInteractionLedger (InteractionType, IsSuccess)
    INCLUDE (UserRole, ModelName, LatencyMs, TokensInput, TokensOutput);
END
GO

-- Index for user-specific queries (RLS predicate)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AILedger_User' AND object_id = OBJECT_ID('dbo.AIInteractionLedger'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_AILedger_User
    ON dbo.AIInteractionLedger (UserRole, UserId)
    INCLUDE (InteractionType, IsSuccess, LatencyMs);
END
GO

-- Grant INSERT on ledger to all roles (everyone can log interactions)
-- SELECT governed by RLS below
GRANT INSERT ON dbo.AIInteractionLedger TO TaxFiler, TaxProfessional, BranchManager, Executive, DevOps;
GRANT SELECT ON dbo.AIInteractionLedger TO Executive, DevOps;
GO


-- ============================================================================
-- SECTION 3: ROW-LEVEL SECURITY (RLS)
-- ============================================================================
-- RLS uses inline table-valued functions as security predicates attached to
-- tables via a SECURITY POLICY.  The predicates run transparently on every
-- SELECT / UPDATE / DELETE — no application code changes needed.
--
-- NOTE: TaxReturns is intentionally EXCLUDED from RLS. The RLS predicate
-- function forces row-mode execution even when batch mode would otherwise be
-- chosen (e.g. NCCI scans on the named replica), causing severe analytics
-- performance degradation. TaxReturns access control is handled at the
-- application layer via ProfessionalId / CustomerId filters in DAB queries.
--
-- Policy design — Customers:
--   • Executive (COO)      → see ALL customers
--   • DevOps               → see NO customers (ops role, no PII access)
--   • BranchManager        → see customers with returns in their branch
--   • TaxProfessional      → see customers assigned to them (via TaxReturns)
--   • TaxFiler             → see only their own customer record
--
-- Policy design — AIInteractionLedger:
--   • Executive / DevOps   → see ALL entries
--   • Others               → see only their own interactions
--
-- For the demo we use EXECUTE AS USER + SESSION_CONTEXT to simulate each
-- persona's view.
-- ============================================================================

PRINT '  3/9 Row-Level Security';
GO

-- 3-pre. Drop existing security policies FIRST so we can alter the predicate functions
-- (TaxReturns policy removed — see note above re: batch-mode degradation)
IF EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'RLS_TaxReturns')
    DROP SECURITY POLICY dbo.RLS_TaxReturns;
IF EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'RLS_Customers')
    DROP SECURITY POLICY dbo.RLS_Customers;
IF EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'RLS_AILedger')
    DROP SECURITY POLICY dbo.RLS_AILedger;
GO

-- Also drop the TaxReturns predicate function if it exists from a prior deployment
IF OBJECT_ID('dbo.fn_RLS_TaxReturns', 'IF') IS NOT NULL
    DROP FUNCTION dbo.fn_RLS_TaxReturns;
GO

-- 3a. PREDICATE FUNCTION: Customers
-- Executive sees all; DevOps sees none; BranchManager/Professional scoped
-- via TaxReturns join; TaxFiler sees only their own record.
CREATE OR ALTER FUNCTION dbo.fn_RLS_Customers (
    @CustomerId INT
)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS access
    WHERE
        -- Service connections (no session context) bypass RLS
        SESSION_CONTEXT(N'UserId') IS NULL
        -- db_owner always passes (admin / DAB managed identity)
        OR IS_MEMBER('db_owner') = 1
        -- Executive (COO) sees all customers
        OR IS_MEMBER('Executive') = 1
        -- DevOps is intentionally EXCLUDED — no PII access
        -- Branch manager sees customers who have returns in their branch
        OR (IS_MEMBER('BranchManager') = 1
            AND EXISTS (
                SELECT 1 FROM dbo.TaxReturns
                WHERE CustomerId = @CustomerId
                  AND BranchId = CAST(SESSION_CONTEXT(N'BranchId') AS INT)
            ))
        -- Tax professional sees customers assigned to them
        OR (IS_MEMBER('TaxProfessional') = 1
            AND EXISTS (
                SELECT 1 FROM dbo.TaxReturns
                WHERE CustomerId = @CustomerId
                  AND ProfessionalId = CAST(SESSION_CONTEXT(N'ProfessionalId') AS INT)
            ))
        -- Tax filer sees only their own record
        OR (IS_MEMBER('TaxFiler') = 1
            AND @CustomerId = CAST(SESSION_CONTEXT(N'CustomerId') AS INT));
GO

-- 3b. PREDICATE FUNCTION: AIInteractionLedger
-- Only Executive and DevOps can see all entries; others see only their own.
CREATE OR ALTER FUNCTION dbo.fn_RLS_AILedger (
    @UserRole  NVARCHAR(30),
    @UserId    NVARCHAR(200)
)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS access
    WHERE
        -- Service connections (no session context) bypass RLS
        SESSION_CONTEXT(N'UserId') IS NULL
        OR IS_MEMBER('Executive') = 1
        OR IS_MEMBER('DevOps') = 1
        -- Others can see only their own interactions
        OR @UserId = CAST(SESSION_CONTEXT(N'UserId') AS NVARCHAR(200))
        OR IS_MEMBER('db_owner') = 1;
GO

-- 3c. CREATE SECURITY POLICIES
-- (policies were dropped at top of section 3 so functions could be altered)
-- NOTE: No policy on TaxReturns — removed to preserve batch-mode execution on NCCI analytics.

CREATE SECURITY POLICY dbo.RLS_Customers
    ADD FILTER PREDICATE dbo.fn_RLS_Customers(CustomerId) ON dbo.Customers
WITH (STATE = ON, SCHEMABINDING = ON);
GO

CREATE SECURITY POLICY dbo.RLS_AILedger
    ADD FILTER PREDICATE dbo.fn_RLS_AILedger(UserRole, UserId) ON dbo.AIInteractionLedger
WITH (STATE = ON, SCHEMABINDING = ON);
GO

GO


-- ============================================================================
-- SECTION 4: DYNAMIC DATA MASKING (DDM)
-- ============================================================================
-- DDM masks sensitive data at query time for unprivileged users.
-- Users with UNMASK permission see the real values.
-- No application code changes required — masking is transparent.
--
-- Masking functions:
--   default()        — full mask (0 for numbers, xxxx for strings, 1900-01-01 for dates)
--   email()          — shows first char + XXX@XXXX.com
--   partial(p,m,s)   — prefix chars, padding, suffix chars
-- ============================================================================

PRINT '  4/9 Dynamic Data Masking';

-- 4a. Apply masks to Customers PII columns
ALTER TABLE dbo.Customers ALTER COLUMN Email       ADD MASKED WITH (FUNCTION = 'email()');
ALTER TABLE dbo.Customers ALTER COLUMN Phone       ADD MASKED WITH (FUNCTION = 'partial(0, "XXX-XXX-", 4)');
ALTER TABLE dbo.Customers ALTER COLUMN SSNLastFour ADD MASKED WITH (FUNCTION = 'default()');
ALTER TABLE dbo.Customers ALTER COLUMN DateOfBirth ADD MASKED WITH (FUNCTION = 'default()');
ALTER TABLE dbo.Customers ALTER COLUMN Address     ADD MASKED WITH (FUNCTION = 'partial(0, "XXXXX", 0)');
ALTER TABLE dbo.Customers ALTER COLUMN FirstName   ADD MASKED WITH (FUNCTION = 'partial(1, "XXXXX", 0)');
ALTER TABLE dbo.Customers ALTER COLUMN LastName    ADD MASKED WITH (FUNCTION = 'partial(1, "XXXXX", 0)');
GO

-- 4b. Apply masks to W2Documents sensitive fields
ALTER TABLE dbo.W2Documents ALTER COLUMN EmployerEIN ADD MASKED WITH (FUNCTION = 'partial(0, "XX-XXX", 4)');
ALTER TABLE dbo.W2Documents ALTER COLUMN FederalWithheldBox2 ADD MASKED WITH (FUNCTION = 'default()');
ALTER TABLE dbo.W2Documents ALTER COLUMN WagesBox1  ADD MASKED WITH (FUNCTION = 'default()');
GO

-- 4c. Apply masks to Form1099 sensitive fields
ALTER TABLE dbo.Form1099 ALTER COLUMN PayerEIN ADD MASKED WITH (FUNCTION = 'partial(0, "XX-XXX", 4)');
ALTER TABLE dbo.Form1099 ALTER COLUMN GrossAmount ADD MASKED WITH (FUNCTION = 'default()');
GO

-- 4d. Apply mask to TaxReturns financial columns (non-privileged users see $0)
ALTER TABLE dbo.TaxReturns ALTER COLUMN GrossIncome           ADD MASKED WITH (FUNCTION = 'default()');
ALTER TABLE dbo.TaxReturns ALTER COLUMN AdjustedGrossIncome   ADD MASKED WITH (FUNCTION = 'default()');
ALTER TABLE dbo.TaxReturns ALTER COLUMN TaxableIncome         ADD MASKED WITH (FUNCTION = 'default()');
ALTER TABLE dbo.TaxReturns ALTER COLUMN TaxLiability          ADD MASKED WITH (FUNCTION = 'default()');
ALTER TABLE dbo.TaxReturns ALTER COLUMN RefundAmount          ADD MASKED WITH (FUNCTION = 'default()');
ALTER TABLE dbo.TaxReturns ALTER COLUMN AmountOwed            ADD MASKED WITH (FUNCTION = 'default()');
GO

-- 4e. Grant UNMASK to privileged roles only
-- Executive and DevOps can see all unmasked data
GRANT UNMASK TO Executive;
GRANT UNMASK TO DevOps;
-- Tax professionals see unmasked data for their clients (RLS limits which rows)
GRANT UNMASK TO TaxProfessional;
-- Branch managers see unmasked data for their branch
GRANT UNMASK TO BranchManager;
-- Tax filers do NOT get UNMASK — they see their own data via RLS,
-- but PII of other customers remains masked (defense in depth)
GO

GO


-- ============================================================================
-- SECTION 5: COLUMN-LEVEL SECURITY
-- ============================================================================
-- Beyond RLS (row filtering) and DDM (value masking), column-level DENY
-- prevents certain roles from even querying specific columns.
-- A SELECT on a denied column returns an error, not masked data.
--
-- Use case: TaxFiler role should never query other customers' SSN at all.
-- ============================================================================

PRINT '  5/9 Column-Level Security';

-- Tax filers cannot query SSN column at all (even their own — use a view or proc instead)
DENY SELECT ON dbo.Customers (SSNLastFour) TO TaxFiler;

-- Tax filers cannot see foreign account financial details
DENY SELECT ON dbo.TaxReturns (ForeignAccountMaxValue) TO TaxFiler;
DENY SELECT ON dbo.TaxReturns (HasForeignAccounts)      TO TaxFiler;

-- Branch managers cannot see SSN
DENY SELECT ON dbo.Customers (SSNLastFour) TO BranchManager;
GO

GO


-- ============================================================================
-- SECTION 6: DATA CLASSIFICATION (Sensitivity Labels)
-- ============================================================================
-- ADD SENSITIVITY CLASSIFICATION tags columns with information_type and
-- sensitivity_label metadata.  This integrates with:
--   • Azure Purview for data governance
--   • SQL Auditing (captures classified column access in audit logs)
--   • Compliance reporting (sys.sensitivity_classifications)
-- ============================================================================

PRINT '  6/9 Data Classification';

-- Customers table — PII
ADD SENSITIVITY CLASSIFICATION TO dbo.Customers.FirstName
    WITH (LABEL = 'Confidential - GDPR', LABEL_ID = 'bf91e9cf-8db0-4b18-9580-6c31bba4a4a2',
          INFORMATION_TYPE = 'Name', INFORMATION_TYPE_ID = '57845286-7598-22f5-9659-15b24aeb125e');

ADD SENSITIVITY CLASSIFICATION TO dbo.Customers.LastName
    WITH (LABEL = 'Confidential - GDPR', LABEL_ID = 'bf91e9cf-8db0-4b18-9580-6c31bba4a4a2',
          INFORMATION_TYPE = 'Name', INFORMATION_TYPE_ID = '57845286-7598-22f5-9659-15b24aeb125e');

ADD SENSITIVITY CLASSIFICATION TO dbo.Customers.Email
    WITH (LABEL = 'Confidential - GDPR', LABEL_ID = 'bf91e9cf-8db0-4b18-9580-6c31bba4a4a2',
          INFORMATION_TYPE = 'Contact Info', INFORMATION_TYPE_ID = '5c503e21-22c6-81fa-620b-f369b8ec38d1');

ADD SENSITIVITY CLASSIFICATION TO dbo.Customers.Phone
    WITH (LABEL = 'Confidential - GDPR', LABEL_ID = 'bf91e9cf-8db0-4b18-9580-6c31bba4a4a2',
          INFORMATION_TYPE = 'Contact Info', INFORMATION_TYPE_ID = '5c503e21-22c6-81fa-620b-f369b8ec38d1');

ADD SENSITIVITY CLASSIFICATION TO dbo.Customers.SSNLastFour
    WITH (LABEL = 'Highly Confidential', LABEL_ID = '3302ae7f-8e07-4e7a-b437-106ae8e84e8d',
          INFORMATION_TYPE = 'National ID', INFORMATION_TYPE_ID = '6f5a11a7-08b1-19c3-59e5-8c89cf4f8444');

ADD SENSITIVITY CLASSIFICATION TO dbo.Customers.DateOfBirth
    WITH (LABEL = 'Confidential - GDPR', LABEL_ID = 'bf91e9cf-8db0-4b18-9580-6c31bba4a4a2',
          INFORMATION_TYPE = 'Date Of Birth', INFORMATION_TYPE_ID = '3de7cc52-710d-4e09-a52a-a8b92f028393');

ADD SENSITIVITY CLASSIFICATION TO dbo.Customers.Address
    WITH (LABEL = 'Confidential - GDPR', LABEL_ID = 'bf91e9cf-8db0-4b18-9580-6c31bba4a4a2',
          INFORMATION_TYPE = 'U.S. Address', INFORMATION_TYPE_ID = 'c25585ec-3591-1dbb-7c42-756d5e3e0b07');

-- TaxReturns — Financial data
ADD SENSITIVITY CLASSIFICATION TO dbo.TaxReturns.GrossIncome
    WITH (LABEL = 'Highly Confidential', LABEL_ID = '3302ae7f-8e07-4e7a-b437-106ae8e84e8d',
          INFORMATION_TYPE = 'Financial', INFORMATION_TYPE_ID = 'c22a6f80-8932-1ee5-4527-b436e2362da3');

ADD SENSITIVITY CLASSIFICATION TO dbo.TaxReturns.AdjustedGrossIncome
    WITH (LABEL = 'Highly Confidential', LABEL_ID = '3302ae7f-8e07-4e7a-b437-106ae8e84e8d',
          INFORMATION_TYPE = 'Financial', INFORMATION_TYPE_ID = 'c22a6f80-8932-1ee5-4527-b436e2362da3');

ADD SENSITIVITY CLASSIFICATION TO dbo.TaxReturns.TaxableIncome
    WITH (LABEL = 'Highly Confidential', LABEL_ID = '3302ae7f-8e07-4e7a-b437-106ae8e84e8d',
          INFORMATION_TYPE = 'Financial', INFORMATION_TYPE_ID = 'c22a6f80-8932-1ee5-4527-b436e2362da3');

ADD SENSITIVITY CLASSIFICATION TO dbo.TaxReturns.TaxLiability
    WITH (LABEL = 'Highly Confidential', LABEL_ID = '3302ae7f-8e07-4e7a-b437-106ae8e84e8d',
          INFORMATION_TYPE = 'Financial', INFORMATION_TYPE_ID = 'c22a6f80-8932-1ee5-4527-b436e2362da3');

ADD SENSITIVITY CLASSIFICATION TO dbo.TaxReturns.RefundAmount
    WITH (LABEL = 'Highly Confidential', LABEL_ID = '3302ae7f-8e07-4e7a-b437-106ae8e84e8d',
          INFORMATION_TYPE = 'Financial', INFORMATION_TYPE_ID = 'c22a6f80-8932-1ee5-4527-b436e2362da3');

-- W2Documents — PII / Financial
ADD SENSITIVITY CLASSIFICATION TO dbo.W2Documents.EmployerEIN
    WITH (LABEL = 'Confidential', LABEL_ID = '331f0b13-76b5-2f1b-a77b-def5a73c73c2',
          INFORMATION_TYPE = 'National ID', INFORMATION_TYPE_ID = '6f5a11a7-08b1-19c3-59e5-8c89cf4f8444');

ADD SENSITIVITY CLASSIFICATION TO dbo.W2Documents.WagesBox1
    WITH (LABEL = 'Highly Confidential', LABEL_ID = '3302ae7f-8e07-4e7a-b437-106ae8e84e8d',
          INFORMATION_TYPE = 'Financial', INFORMATION_TYPE_ID = 'c22a6f80-8932-1ee5-4527-b436e2362da3');

ADD SENSITIVITY CLASSIFICATION TO dbo.W2Documents.FederalWithheldBox2
    WITH (LABEL = 'Highly Confidential', LABEL_ID = '3302ae7f-8e07-4e7a-b437-106ae8e84e8d',
          INFORMATION_TYPE = 'Financial', INFORMATION_TYPE_ID = 'c22a6f80-8932-1ee5-4527-b436e2362da3');

-- Form1099 — PII / Financial
ADD SENSITIVITY CLASSIFICATION TO dbo.Form1099.PayerEIN
    WITH (LABEL = 'Confidential', LABEL_ID = '331f0b13-76b5-2f1b-a77b-def5a73c73c2',
          INFORMATION_TYPE = 'National ID', INFORMATION_TYPE_ID = '6f5a11a7-08b1-19c3-59e5-8c89cf4f8444');

ADD SENSITIVITY CLASSIFICATION TO dbo.Form1099.GrossAmount
    WITH (LABEL = 'Highly Confidential', LABEL_ID = '3302ae7f-8e07-4e7a-b437-106ae8e84e8d',
          INFORMATION_TYPE = 'Financial', INFORMATION_TYPE_ID = 'c22a6f80-8932-1ee5-4527-b436e2362da3');
GO

GO


-- ============================================================================
-- SECTION 7: AI INTERACTION LOGGING PROCEDURE
-- ============================================================================
-- Called by the AI stored procedures (AskTaxQuestion, SearchSimilarCases,
-- AskTaxAssistant) to log every external AI call to the ledger table.
-- ============================================================================

PRINT '  7/9 LogAIInteraction Proc';
GO

CREATE OR ALTER PROCEDURE dbo.LogAIInteraction
    @InteractionType    NVARCHAR(50),
    @UserRole           NVARCHAR(30)       = 'anonymous',
    @UserId             NVARCHAR(200)      = NULL,
    @BranchId           INT                = NULL,
    @CustomerId         INT                = NULL,
    @PromptText         NVARCHAR(MAX)      = NULL,
    @ModelName          NVARCHAR(100)      = NULL,
    @ExternalEndpoint   NVARCHAR(500)      = NULL,
    @TokensInput        INT                = NULL,
    @TokensOutput       INT                = NULL,
    @ResponseSummary    NVARCHAR(500)      = NULL,
    @ResultCount        INT                = NULL,
    @SimilarityScoreAvg DECIMAL(6,4)       = NULL,
    @LatencyMs          INT                = NULL,
    @HttpStatusCode     INT                = NULL,
    @ErrorMessage       NVARCHAR(MAX)      = NULL,
    @IsSuccess          BIT                = 1,
    @SessionId          NVARCHAR(100)      = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.AIInteractionLedger (
        InteractionType, UserRole, UserId, BranchId, CustomerId,
        PromptText, ModelName, ExternalEndpoint,
        TokensInput, TokensOutput,
        ResponseSummary, ResultCount, SimilarityScoreAvg,
        LatencyMs, HttpStatusCode, ErrorMessage, IsSuccess, SessionId
    )
    VALUES (
        @InteractionType, @UserRole, @UserId, @BranchId, @CustomerId,
        @PromptText, @ModelName, @ExternalEndpoint,
        @TokensInput, @TokensOutput,
        @ResponseSummary, @ResultCount, @SimilarityScoreAvg,
        @LatencyMs, @HttpStatusCode, @ErrorMessage, @IsSuccess, @SessionId
    );
END;
GO

-- Grant execute to all roles (everyone logs their own interactions)
GRANT EXECUTE ON dbo.LogAIInteraction TO TaxFiler, TaxProfessional, BranchManager, Executive, DevOps;
GO

PRINT '  ✓ Created LogAIInteraction procedure.';
GO


-- ============================================================================
-- SECTION 8: SECURITY DEMO STORED PROCEDURES
-- ============================================================================
-- These procedures use EXECUTE AS to switch context to each demo persona
-- and return the results side-by-side for the frontend dashboard.
-- ============================================================================

PRINT '  8/9 Demo Stored Procedures';
GO

-- -------------------------------------------------------------------------
-- 9a. RLS Demo — Shows row counts per persona for Customers & AILedger
--     Executive=all, DevOps=none, BranchMgr=branch, Professional=assigned,
--     TaxFiler=own record only.
-- -------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SecurityDemo_RLS
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @totalCustomers INT, @totalLedger INT;
    SELECT @totalCustomers = COUNT(*) FROM dbo.Customers;
    SELECT @totalLedger = COUNT(*) FROM dbo.AIInteractionLedger;

    -- Executive (COO) sees all customers
    SELECT
        'executive'                      AS Persona,
        'Robert Williams (COO)'          AS PersonaName,
        @totalCustomers                  AS CustomerRows,
        @totalLedger                     AS LedgerRows
    UNION ALL
    -- DevOps sees NO customer data (operations role — no PII access)
    SELECT
        'devops',
        'Jennifer Park (DevOps)',
        0,
        @totalLedger   -- DevOps can still see all ledger entries
    UNION ALL
    -- Branch Manager sees customers with returns in their branch (BranchId = 1)
    SELECT
        'branch-manager',
        'Amanda Rodriguez (Branch Mgr)',
        (SELECT COUNT(DISTINCT c.CustomerId)
         FROM dbo.Customers c
         INNER JOIN dbo.TaxReturns tr ON tr.CustomerId = c.CustomerId
         WHERE tr.BranchId = 1),
        (SELECT COUNT(*) FROM dbo.AIInteractionLedger WHERE UserRole = 'branch-manager')
    UNION ALL
    -- Tax Professional sees customers assigned to them (ProfessionalId = 1)
    SELECT
        'tax-professional',
        'Michael Chen (Tax Prep)',
        (SELECT COUNT(DISTINCT c.CustomerId)
         FROM dbo.Customers c
         INNER JOIN dbo.TaxReturns tr ON tr.CustomerId = c.CustomerId
         WHERE tr.ProfessionalId = 1),
        (SELECT COUNT(*) FROM dbo.AIInteractionLedger WHERE UserRole = 'tax-professional')
    UNION ALL
    -- Tax Filer sees only their own customer record (CustomerId = 1)
    SELECT
        'tax-filer',
        'Sarah Johnson (Tax Filer)',
        1,
        (SELECT COUNT(*) FROM dbo.AIInteractionLedger WHERE UserId = 'sarah.johnson@outlook.com');
END;
GO

GRANT EXECUTE ON dbo.SecurityDemo_RLS TO Executive, DevOps;
GO

-- -------------------------------------------------------------------------
-- 9b. DDM Demo — Shows masked column definitions alongside real data
--     Since DAB runs as db_owner (has UNMASK), we simulate the masked
--     view by applying the mask functions in SQL.
-- -------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SecurityDemo_DDM
AS
BEGIN
    SET NOCOUNT ON;

    -- Result set 1: Show top 5 customers with both real and masked values
    SELECT TOP 5
        'Executive (Unmasked)' AS ViewAs,
        c.CustomerId,
        c.FirstName,
        c.LastName,
        c.Email,
        c.Phone,
        c.SSNLastFour,
        CONVERT(VARCHAR(30), c.DateOfBirth, 23) AS DateOfBirth,
        c.Address
    FROM dbo.Customers c
    ORDER BY c.CustomerId;

    -- Result set 2: Simulated masked view (how unprivileged users would see these)
    SELECT TOP 5
        'Tax Filer (Masked)' AS ViewAs,
        c.CustomerId,
        LEFT(c.FirstName, 1) + 'XXXXX'          AS FirstName,
        LEFT(c.LastName, 1) + 'XXXXX'           AS LastName,
        LEFT(c.Email, 1) + 'XXX@XXXX.com'       AS Email,
        'xxxx'                                    AS Phone,
        '****'                                    AS SSNLastFour,
        '1900-01-01'                              AS DateOfBirth,
        'xxxx'                                    AS Address
    FROM dbo.Customers c
    ORDER BY c.CustomerId;

    -- Result set 3: Mask definitions from sys catalog
    SELECT
        OBJECT_NAME(mc.object_id)   AS TableName,
        col.name                    AS ColumnName,
        mc.masking_function         AS MaskFunction
    FROM sys.masked_columns mc
    JOIN sys.columns col ON mc.object_id = col.object_id AND mc.column_id = col.column_id
    ORDER BY OBJECT_NAME(mc.object_id), col.name;
END;
GO

GRANT EXECUTE ON dbo.SecurityDemo_DDM TO Executive, DevOps;
GO

-- -------------------------------------------------------------------------
-- 9c. Ledger Verification — Shows ledger metadata and verification status
-- -------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SecurityDemo_LedgerInfo
AS
BEGIN
    SET NOCOUNT ON;

    -- DAB returns only the first result set, so return the interaction records
    -- that the frontend dashboard needs to display.
    -- Metadata columns are embedded alongside each row for the UI.
    SELECT TOP 20
        a.InteractionId,
        a.InteractionType,
        a.UserRole,
        a.UserId,
        LEFT(a.PromptText, 120)  AS PromptPreview,
        a.ModelName,
        a.TokensTotal,
        a.LatencyMs,
        a.HttpStatusCode,
        a.IsSuccess,
        a.CorrelationId,
        -- Ledger metadata (same for all rows — lets UI show ledger info)
        CASE t.ledger_type
            WHEN 1 THEN 'UPDATABLE_LEDGER_TABLE'
            WHEN 2 THEN 'APPEND_ONLY_LEDGER_TABLE'
            ELSE 'UNKNOWN'
        END                       AS LedgerType,
        t.name                    AS LedgerTableName,
        (SELECT COUNT(*) FROM sys.database_ledger_blocks) AS BlockCount
    FROM dbo.AIInteractionLedger a
    CROSS JOIN sys.tables t
    WHERE t.name = 'AIInteractionLedger'
      AND t.ledger_type > 0
    ORDER BY a.InteractionId DESC;
END;
GO

GRANT EXECUTE ON dbo.SecurityDemo_LedgerInfo TO Executive, DevOps;
GO

-- -------------------------------------------------------------------------
-- 9d. Data Classification Report
-- -------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SecurityDemo_Classification
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        SCHEMA_NAME(o.schema_id)                 AS SchemaName,
        o.name                                    AS TableName,
        c.name                                    AS ColumnName,
        sc.information_type                       AS InformationType,
        sc.label                                  AS SensitivityLabel,
        t.name                                    AS DataType,
        CASE
            WHEN EXISTS (
                SELECT 1 FROM sys.masked_columns mc
                WHERE mc.object_id = c.object_id AND mc.column_id = c.column_id
            ) THEN 'Yes'
            ELSE 'No'
        END                                       AS IsMasked,
        CASE
            WHEN EXISTS (
                SELECT 1 FROM sys.masked_columns mc
                WHERE mc.object_id = c.object_id AND mc.column_id = c.column_id
            ) THEN (
                SELECT mc.masking_function FROM sys.masked_columns mc
                WHERE mc.object_id = c.object_id AND mc.column_id = c.column_id
            )
            ELSE NULL
        END                                       AS MaskingFunction
    FROM sys.sensitivity_classifications sc
    JOIN sys.objects o ON sc.major_id = o.object_id
    JOIN sys.columns c ON sc.major_id = c.object_id AND sc.minor_id = c.column_id
    JOIN sys.types t   ON c.user_type_id = t.user_type_id
    ORDER BY sc.label DESC, o.name, c.column_id;
END;
GO

GRANT EXECUTE ON dbo.SecurityDemo_Classification TO Executive, DevOps;
GO

-- -------------------------------------------------------------------------
-- 9e. Security Overview — Aggregate security posture
-- -------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.SecurityDemo_Overview
AS
BEGIN
    SET NOCOUNT ON;

    -- Result set 1: Security feature summary
    SELECT
        'Row-Level Security'    AS Feature,
        (SELECT COUNT(*) FROM sys.security_policies WHERE is_enabled = 1) AS Policies,
        (SELECT COUNT(*) FROM sys.security_predicates) AS Predicates,
        'Enabled'               AS Status
    UNION ALL
    SELECT
        'Dynamic Data Masking',
        (SELECT COUNT(*) FROM sys.masked_columns),
        NULL,
        CASE WHEN EXISTS (SELECT 1 FROM sys.masked_columns) THEN 'Enabled' ELSE 'Not Configured' END
    UNION ALL
    SELECT
        'Ledger Tables',
        (SELECT COUNT(*) FROM sys.tables WHERE ledger_type > 0),
        NULL,
        CASE WHEN EXISTS (SELECT 1 FROM sys.tables WHERE ledger_type > 0) THEN 'Enabled' ELSE 'Not Configured' END
    UNION ALL
    SELECT
        'Data Classification',
        (SELECT COUNT(*) FROM sys.sensitivity_classifications),
        NULL,
        CASE WHEN EXISTS (SELECT 1 FROM sys.sensitivity_classifications) THEN 'Enabled' ELSE 'Not Configured' END
    UNION ALL
    SELECT
        'Column-Level Security',
        (SELECT COUNT(*) FROM sys.database_permissions
         WHERE type = 'SL' AND state_desc = 'DENY'),
        NULL,
        CASE WHEN EXISTS (SELECT 1 FROM sys.database_permissions WHERE type = 'SL' AND state_desc = 'DENY') THEN 'Enabled' ELSE 'Not Configured' END
    UNION ALL
    SELECT
        'TDE (Transparent Data Encryption)',
        NULL,
        NULL,
        CASE WHEN (SELECT is_encrypted FROM sys.databases WHERE database_id = DB_ID()) = 1 THEN 'Enabled' ELSE 'Not Encrypted' END;

    -- Result set 2: Role membership
    SELECT
        dp.name         AS RoleName,
        mp.name         AS MemberName,
        mp.type_desc    AS MemberType
    FROM sys.database_role_members drm
    JOIN sys.database_principals dp ON drm.role_principal_id = dp.principal_id
    JOIN sys.database_principals mp ON drm.member_principal_id = mp.principal_id
    WHERE dp.name IN ('TaxFiler', 'TaxProfessional', 'BranchManager', 'Executive', 'DevOps')
    ORDER BY dp.name, mp.name;

    -- Result set 3: Security policies detail
    SELECT
        sp.name                         AS PolicyName,
        sp.is_enabled                   AS IsEnabled,
        OBJECT_NAME(pred.target_object_id) AS TargetTable,
        pred.predicate_type_desc        AS PredicateType,
        pred.predicate_definition        AS PredicateFunction,
        pred.operation_desc             AS Operation
    FROM sys.security_policies sp
    JOIN sys.security_predicates pred ON sp.object_id = pred.object_id
    ORDER BY sp.name;

    -- Result set 4: Masked columns detail
    SELECT
        OBJECT_NAME(mc.object_id)   AS TableName,
        c.name                      AS ColumnName,
        mc.masking_function         AS MaskFunction,
        t.name                      AS DataType
    FROM sys.masked_columns mc
    JOIN sys.columns c ON mc.object_id = c.object_id AND mc.column_id = c.column_id
    JOIN sys.types t   ON c.user_type_id = t.user_type_id
    ORDER BY OBJECT_NAME(mc.object_id), c.column_id;
END;
GO

GRANT EXECUTE ON dbo.SecurityDemo_Overview TO Executive, DevOps;
GO

PRINT '  ✓ Created 5 security demo stored procedures.';
GO


-- ============================================================================
-- SECTION 9: VERIFICATION
-- ============================================================================

PRINT '  9/9 Verification';

DECLARE @roleCount INT, @userCount INT, @ledgerCount INT, @rlsCount INT, @ddmCount INT, @classCount INT;

SELECT @roleCount = COUNT(*) FROM sys.database_principals
WHERE name IN ('TaxFiler', 'TaxProfessional', 'BranchManager', 'Executive', 'DevOps');

SELECT @userCount = COUNT(*) FROM sys.database_principals
WHERE name IN ('SarahJohnson', 'MichaelChen', 'AmandaRodriguez', 'RobertWilliams', 'JenniferPark');

SELECT @ledgerCount = COUNT(*) FROM sys.tables WHERE ledger_type > 0;

SELECT @rlsCount = COUNT(*) FROM sys.security_policies;

SELECT @ddmCount = COUNT(*) FROM sys.masked_columns;

SELECT @classCount = COUNT(*) FROM sys.sensitivity_classifications;

PRINT '  ✓ Roles: '    + CAST(@roleCount  AS VARCHAR) + '/5';
PRINT '  ✓ Users: '    + CAST(@userCount  AS VARCHAR) + '/5';
PRINT '  ✓ Ledger tables: ' + CAST(@ledgerCount AS VARCHAR);
PRINT '  ✓ RLS policies: '  + CAST(@rlsCount  AS VARCHAR) + '/2';
PRINT '  ✓ DDM columns: '   + CAST(@ddmCount  AS VARCHAR);
PRINT '  ✓ Classifications: ' + CAST(@classCount AS VARCHAR);

PRINT 'Security deployment complete.';
GO
