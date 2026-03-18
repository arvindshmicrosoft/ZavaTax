/*
 * Zava Tax - Load JSON Data (Knowledge Base & Scenarios)
 * 
 * This script loads the embedded knowledge base and tax scenarios
 * from JSON format using OPENJSON.
 * 
 * Run this after loading CSV data.
 */

SET NOCOUNT ON;

-- ============================================================================
-- LOAD KNOWLEDGE BASE
-- ============================================================================

PRINT 'Loading Tax Knowledge Base from JSON...';

-- Create a procedure to load from JSON string
-- (In practice, you'd call this from an application that reads the JSON file)

CREATE OR ALTER PROCEDURE LoadKnowledgeBaseFromJson
    @JsonData NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    
    INSERT INTO TaxKnowledgeBase (
        ChunkId,
        PublicationId,
        PublicationTitle,
        Section,
        Subsection,
        Content,
        TokenEstimate,
        SourceUrl,
        ChunkIndex,
        ContentEmbedding
    )
    SELECT 
        JSON_VALUE(chunk.value, '$.chunk_id'),
        JSON_VALUE(chunk.value, '$.publication_id'),
        JSON_VALUE(chunk.value, '$.publication_title'),
        JSON_VALUE(chunk.value, '$.section'),
        JSON_VALUE(chunk.value, '$.subsection'),
        JSON_VALUE(chunk.value, '$.content'),
        CAST(JSON_VALUE(chunk.value, '$.token_estimate') AS INT),
        JSON_VALUE(chunk.value, '$.url'),
        CAST(JSON_VALUE(chunk.value, '$.chunk_index') AS INT),
        -- Convert JSON array to VECTOR
        CAST(JSON_QUERY(chunk.value, '$.embedding') AS VECTOR(1536))
    FROM OPENJSON(@JsonData) AS chunk
    WHERE JSON_VALUE(chunk.value, '$.embedding') IS NOT NULL;
    
    PRINT CONCAT('Knowledge base chunks loaded: ', @@ROWCOUNT);
END;
GO

-- ============================================================================
-- LOAD TAX SCENARIOS
-- ============================================================================

PRINT 'Loading Tax Scenarios from JSON...';

CREATE OR ALTER PROCEDURE LoadTaxScenariosFromJson
    @JsonData NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    
    INSERT INTO TaxScenarios (
        ScenarioId,
        TaxYear,
        ScenarioType,
        TaxpayerProfile,
        IncomeSources,
        Deductions,
        Credits,
        SpecialSituations,
        TaxOutcome,
        ComplexityScore,
        KeyCharacteristics,
        ScenarioSummary,
        ResolutionNotes,
        ScenarioEmbedding
    )
    SELECT 
        JSON_VALUE(s.value, '$.scenario_id'),
        CAST(JSON_VALUE(s.value, '$.tax_year') AS INT),
        JSON_VALUE(s.value, '$.scenario_type'),
        JSON_QUERY(s.value, '$.taxpayer_profile'),
        JSON_QUERY(s.value, '$.income_sources'),
        JSON_QUERY(s.value, '$.deductions'),
        JSON_QUERY(s.value, '$.credits'),
        JSON_QUERY(s.value, '$.special_situations'),
        JSON_QUERY(s.value, '$.tax_outcome'),
        CAST(JSON_VALUE(s.value, '$.complexity_score') AS INT),
        JSON_QUERY(s.value, '$.key_characteristics'),
        JSON_VALUE(s.value, '$.scenario_summary'),
        JSON_QUERY(s.value, '$.resolution_notes'),
        CAST(JSON_QUERY(s.value, '$.embedding') AS VECTOR(1536))
    FROM OPENJSON(@JsonData) AS s
    WHERE JSON_VALUE(s.value, '$.embedding') IS NOT NULL;
    
    PRINT CONCAT('Tax scenarios loaded: ', @@ROWCOUNT);
END;
GO

-- ============================================================================
-- SAMPLE: Insert a single knowledge base chunk (for testing)
-- ============================================================================

/*
DECLARE @SampleChunk NVARCHAR(MAX) = N'[{
    "chunk_id": "p587_chunk_0001",
    "publication_id": "p587",
    "publication_title": "Business Use of Your Home",
    "section": "Introduction",
    "subsection": "",
    "content": "If you use part of your home for business, you may be able to deduct expenses for the business use of your home. The home office deduction is available for homeowners and renters, and applies to all types of homes.",
    "token_estimate": 50,
    "url": "https://www.irs.gov/publications/p587",
    "chunk_index": 1,
    "embedding": [0.001, 0.002, ... ] -- 1536 floats
}]';

EXEC LoadKnowledgeBaseFromJson @JsonData = @SampleChunk;
*/

-- ============================================================================
-- Verify JSON Loads
-- ============================================================================

PRINT '';
PRINT '=== JSON Data Summary ===';

SELECT 
    'TaxKnowledgeBase' AS TableName,
    COUNT_BIG(*) AS TotalRows,
    COUNT_BIG(ContentEmbedding) AS WithEmbeddings,
    COUNT_BIG(DISTINCT PublicationId) AS Publications
FROM TaxKnowledgeBase;

SELECT 
    'TaxScenarios' AS TableName,
    COUNT_BIG(*) AS TotalRows,
    COUNT_BIG(ScenarioEmbedding) AS WithEmbeddings,
    COUNT_BIG(DISTINCT ScenarioType) AS ScenarioTypes,
    AVG(CAST(ComplexityScore AS BIGINT)) AS AvgComplexity
FROM TaxScenarios;

GO

PRINT 'JSON data load procedures ready.';
PRINT 'Call LoadKnowledgeBaseFromJson and LoadTaxScenariosFromJson from your application.';
