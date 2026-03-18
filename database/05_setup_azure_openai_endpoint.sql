/*
 * Zava Tax - Setup Azure OpenAI External Endpoint
 * 
 * Configures CREATE EXTERNAL MODEL to call Azure OpenAI embeddings
 * using Managed Identity authentication (no API keys needed).
 * 
 * This enables AI_GENERATE_EMBEDDINGS() function for vector search.
 * 
 * PREREQUISITES:
 * 1. Azure SQL DB managed identity must be enabled
 * 2. Grant the managed identity "Cognitive Services OpenAI User" role on the Azure OpenAI resource
 * 3. Deploy text-embedding-3-small model in Azure OpenAI
 */

SET NOCOUNT ON;

-- ============================================================================
-- STEP 1: Prerequisites - Grant Managed Identity Access to Azure OpenAI
-- ============================================================================

/*
Run these Azure CLI commands BEFORE executing this SQL script:

1. Get the managed identity principal ID:
   az identity show --name <your-identity-name> --resource-group <your-resource-group> --query principalId -o tsv

2. Grant "Cognitive Services OpenAI User" role to the managed identity:
   az role assignment create \
     --assignee-object-id <principal-id> \
     --assignee-principal-type ServicePrincipal \
     --role "Cognitive Services OpenAI User" \
     --scope /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/<openai-resource-name>

3. Verify the role assignment:
   az role assignment list --assignee <principal-id> --output table
*/

-- ============================================================================
-- STEP 2: Create Database Master Key (required for credentials)
-- ============================================================================

-- Create master key if not exists (required for database scoped credentials)
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$(MASTER_KEY_PASSWORD)';  -- Substituted at deploy time
    PRINT 'Database master key created.';
END
ELSE
BEGIN
    PRINT 'Database master key already exists.';
END
GO

-- ============================================================================
-- STEP 3: Drop existing external model first (before credential)
-- ============================================================================

-- Must drop external model before credential since model depends on credential
IF EXISTS (SELECT * FROM sys.external_models WHERE name = 'AzureOpenAI_Embeddings')
BEGIN
    DROP EXTERNAL MODEL AzureOpenAI_Embeddings;
    PRINT 'Dropped existing external model.';
END
GO

-- ============================================================================
-- STEP 4: Create Database Scoped Credential for Azure OpenAI (Managed Identity)
-- ============================================================================

-- Drop existing credential if updating (now safe since model is dropped)
IF EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'https://your-openai-resource.openai.azure.com/')
BEGIN
    DROP DATABASE SCOPED CREDENTIAL [https://your-openai-resource.openai.azure.com/];
END
GO

-- Create credential using Managed Identity for Azure OpenAI
-- The credential name must match the Azure OpenAI endpoint URL
CREATE DATABASE SCOPED CREDENTIAL [https://your-openai-resource.openai.azure.com/]
WITH IDENTITY = 'Managed Identity',
SECRET = '{"resourceid": "https://cognitiveservices.azure.com"}';
GO

PRINT 'Azure OpenAI credential created with Managed Identity.';

-- ============================================================================
-- STEP 5: Create External Model for Embeddings
-- ============================================================================

-- Create external model pointing to Azure OpenAI embedding deployment
-- IMPORTANT: Replace 'your-openai-resource' with your actual Azure OpenAI resource name
CREATE EXTERNAL MODEL AzureOpenAI_Embeddings
WITH (
    LOCATION = 'https://your-openai-resource.openai.azure.com/openai/deployments/text-embedding-3-small/embeddings?api-version=2024-02-01',
    API_FORMAT = 'Azure OpenAI',
    MODEL_TYPE = EMBEDDINGS,
    MODEL = 'text-embedding-3-small',
    CREDENTIAL = [https://your-openai-resource.openai.azure.com/]
);
GO

PRINT 'External model AzureOpenAI_Embeddings created.';

-- Grant execute permission to all users (for demo purposes)
GRANT EXECUTE ON EXTERNAL MODEL::AzureOpenAI_Embeddings TO PUBLIC;
GO

-- ============================================================================
-- STEP 5: Test the configuration
-- ============================================================================

PRINT '';
PRINT '=== Testing Azure OpenAI Configuration ===';
PRINT '';

BEGIN TRY
    DECLARE @testEmbedding VECTOR(1536);
    
    -- Use the native AI_GENERATE_EMBEDDINGS function
    SELECT @testEmbedding = AI_GENERATE_EMBEDDINGS(N'test embedding generation' USE MODEL AzureOpenAI_Embeddings);
    
    IF @testEmbedding IS NOT NULL
    BEGIN
        PRINT '✓ SUCCESS: AI_GENERATE_EMBEDDINGS is working!';
        PRINT '  Vector search is now enabled for knowledge base queries.';
    END
    ELSE
    BEGIN
        PRINT '✗ WARNING: Embedding returned NULL. Check your Azure OpenAI deployment.';
    END
END TRY
BEGIN CATCH
    PRINT '✗ ERROR: Failed to generate embedding.';
    PRINT '  Error: ' + ERROR_MESSAGE();
    PRINT '';
    PRINT '  Please verify:';
    PRINT '  1. Azure OpenAI resource name is correct in the LOCATION';
    PRINT '  2. Managed identity has "Cognitive Services OpenAI User" role';
    PRINT '  3. text-embedding-3-small deployment exists in Azure OpenAI';
    PRINT '  4. Azure SQL firewall allows outbound to Azure OpenAI';
END CATCH
GO

-- Note: sp_invoke_external_rest_endpoint does not require an external data source.
-- It can call Azure OpenAI directly using managed identity.
-- The external model created above is sufficient for AI_GENERATE_EMBEDDINGS.

PRINT 'Azure OpenAI configuration complete.';
PRINT '';
PRINT 'The external model AzureOpenAI_Embeddings is now available.';
PRINT 'Creating stored procedures that use the external model...';
GO

-- =============================================
-- STORED PROCEDURES USING AZURE OPENAI EMBEDDINGS
-- These must be created after the external model exists
-- =============================================

-- Knowledge base search using AI embeddings
-- Uses AI_GENERATE_EMBEDDINGS with CREATE EXTERNAL MODEL for Azure SQL + Azure OpenAI
CREATE OR ALTER PROCEDURE AskTaxQuestion
    @Question NVARCHAR(MAX),
    @TopK INT = 5
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @embedding VECTOR(1536);
    
    -- Generate embedding using Azure OpenAI external model
    SELECT @embedding = AI_GENERATE_EMBEDDINGS(@Question USE MODEL AzureOpenAI_Embeddings);
    
    -- Perform vector search using VECTOR_SEARCH
    SELECT TOP (@TopK)
        t.Section AS Title,
        t.Content AS Answer,
        t.PublicationTitle AS Source,
        t.PublicationId AS Category,
        s.distance AS SimilarityScore
    FROM
        VECTOR_SEARCH(
            table = TaxKnowledgeBase AS t,
            column = ContentEmbedding,
            similar_to = @embedding,
            metric = 'cosine',
            top_n = @TopK
        ) AS s
    ORDER BY s.distance;
END;
GO

PRINT 'Created AskTaxQuestion procedure.';
GO

-- Similar case search using AI embeddings
-- Uses VECTOR_SEARCH() TVF for DiskANN-accelerated approximate nearest neighbor search
CREATE OR ALTER PROCEDURE SearchSimilarCases
    @Query NVARCHAR(MAX),
    @FilingStatus NVARCHAR(50) = NULL,
    @TopK INT = 10
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @QueryVector VECTOR(1536);
    
    -- Generate embedding using Azure OpenAI external model
    SELECT @QueryVector = AI_GENERATE_EMBEDDINGS(@Query USE MODEL AzureOpenAI_Embeddings);
    
    -- Use VECTOR_SEARCH TVF for DiskANN-accelerated search
    SELECT 
        t.Id,
        t.ScenarioId,
        t.TaxYear,
        t.ScenarioType,
        t.TaxpayerProfile,
        t.IncomeSources,
        t.Deductions,
        t.Credits,
        t.SpecialSituations,
        t.ScenarioSummary,
        s.distance AS SimilarityScore
    FROM VECTOR_SEARCH(
        table = TaxScenarios AS t,
        column = ScenarioEmbedding,
        similar_to = @QueryVector,
        metric = 'cosine',
        top_n = @TopK
    ) AS s
    WHERE (@FilingStatus IS NULL OR JSON_VALUE(t.TaxpayerProfile, '$.filing_status') = @FilingStatus)
    ORDER BY s.distance;
END;
GO

PRINT 'Created SearchSimilarCases procedure.';
PRINT '';
PRINT 'All Azure OpenAI integration complete.';
GO


/*
 * AskTaxAssistant Stored Procedure
 * Uses REST endpoint for Chat Completions (RAG pattern) 
 */

IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'AskTaxAssistant')
    DROP PROCEDURE AskTaxAssistant;
GO

CREATE PROCEDURE AskTaxAssistant
    @Question NVARCHAR(MAX),
    @Context NVARCHAR(MAX) = NULL,  -- Optional: current form step context
    @TopK INT = 3
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @KBContent NVARCHAR(MAX) = '';
    DECLARE @SystemPrompt NVARCHAR(MAX);
    DECLARE @UserPrompt NVARCHAR(MAX);
    DECLARE @Response NVARCHAR(MAX);
    DECLARE @JsonPayload NVARCHAR(MAX);
    DECLARE @RetVal INT;
    DECLARE @ResponseJson NVARCHAR(MAX);
    
    -- Step 1: Retrieve relevant knowledge base content via vector search
    IF EXISTS (SELECT * FROM sys.external_models WHERE name = 'AzureOpenAI_Embeddings')
    BEGIN
        BEGIN TRY
            DECLARE @embedding VECTOR(1536);
            SELECT @embedding = AI_GENERATE_EMBEDDINGS(@Question USE MODEL AzureOpenAI_Embeddings);
            
            IF @embedding IS NOT NULL
            BEGIN
                SELECT @KBContent = @KBContent + 
                    '--- ' + t.Section + ' ---' + CHAR(10) + 
                    LEFT(t.Content, 500) + CHAR(10) + CHAR(10)
                FROM VECTOR_SEARCH(
                    table = TaxKnowledgeBase AS t,
                    column = ContentEmbedding,
                    similar_to = @embedding,
                    metric = 'cosine',
                    top_n = @TopK
                ) AS s
                ORDER BY s.distance;
            END
        END TRY
        BEGIN CATCH
            PRINT 'Vector search failed: ' + ERROR_MESSAGE();
        END CATCH
    END
    
    -- Fallback: keyword search if vector search didn't return results
    IF LEN(@KBContent) < 50
    BEGIN
        SELECT TOP (@TopK) @KBContent = @KBContent + 
            '--- ' + Section + ' ---' + CHAR(10) + 
            LEFT(Content, 1000) + CHAR(10) + CHAR(10)
        FROM TaxKnowledgeBase
        WHERE Content LIKE '%' + @Question + '%' -- simplified logic
           OR Section LIKE '%' + @Question + '%';
    END
    
    -- Step 2: Build prompts for LLM
    SET @SystemPrompt = N'You are a helpful tax assistant for Zava Tax, guiding users through their tax return. You provide accurate, concise tax advice based on the IRS knowledge base. Always be helpful and explain tax concepts in simple terms. If you are not sure about something, recommend consulting a tax professional. Keep responses concise (2-3 paragraphs max).';

    IF @Context IS NOT NULL
        SET @SystemPrompt = @SystemPrompt + ' Current context: ' + @Context;
    
    SET @UserPrompt = @Question;
    
    IF LEN(@KBContent) > 50
        SET @UserPrompt = @UserPrompt + CHAR(10) + CHAR(10) + 
            'Reference the following IRS knowledge base information in your answer:' + CHAR(10) + 
            @KBContent;
    
    -- Step 3: Call Azure OpenAI Chat API via REST endpoint
    SET @SystemPrompt = STRING_ESCAPE(@SystemPrompt, 'json');
    SET @UserPrompt = STRING_ESCAPE(@UserPrompt, 'json');
    
    SET @JsonPayload = N'{
        "messages": [
            {"role": "system", "content": "' + @SystemPrompt + '"},
            {"role": "user", "content": "' + @UserPrompt + '"}
        ],
        "max_completion_tokens": 2000
    }';
    
    BEGIN TRY
        -- Azure SQL Hyperscale uses Managed Identity credential for Azure OpenAI
        EXEC @RetVal = sp_invoke_external_rest_endpoint
            @url = N'https://your-openai-resource.openai.azure.com/openai/deployments/your-chat-deployment/chat/completions?api-version=2024-02-01',
            @method = 'POST',
            @credential = [https://your-openai-resource.openai.azure.com/],
            @payload = @JsonPayload,
            @response = @ResponseJson OUTPUT;
        
        IF @RetVal = 0 AND @ResponseJson IS NOT NULL
        BEGIN
            SELECT @Response = JSON_VALUE(@ResponseJson, '$.result.choices[0].message.content');
            
            IF @Response IS NOT NULL AND LEN(@Response) > 0
            BEGIN
                SELECT 
                    @Response AS Answer,
                    @KBContent AS SourceContent,
                    1 AS IsLLMAugmented;
                RETURN;
            END
            ELSE
            BEGIN
                DECLARE @ErrorMsg NVARCHAR(MAX) = JSON_VALUE(@ResponseJson, '$.result.error.message');
                IF @ErrorMsg IS NOT NULL
                BEGIN
                    SELECT 
                        'Error from AI service: ' + @ErrorMsg AS Answer,
                        @KBContent AS SourceContent,
                        0 AS IsLLMAugmented;
                    RETURN;
                END
            END
        END
    END TRY
    BEGIN CATCH
        DECLARE @ErrMsg NVARCHAR(MAX) = ERROR_MESSAGE();
        RAISERROR('LLM REST call failed: %s', 0, 1, @ErrMsg) WITH NOWAIT;
    END CATCH
    
    -- Fallback: Return KB content directly without LLM augmentation
    IF LEN(@KBContent) > 50
    BEGIN
        SELECT 
            @KBContent AS Answer,
            @KBContent AS SourceContent,
            0 AS IsLLMAugmented;
    END
    ELSE
    BEGIN
        SELECT 
            'I couldn''t find specific information about that. Please consult with a Zava Tax professional for personalized advice on: ' + @Question AS Answer,
            '' AS SourceContent,
            0 AS IsLLMAugmented;
    END
END
GO

PRINT 'AskTaxAssistant procedure created successfully.';
PRINT '';

