/*
 * Zava Tax - Setup Azure OpenAI for Local SQL Server 2025 Express
 * 
 * This configures SQL Server 2025's native AI features:
 *   - CREATE EXTERNAL MODEL for Azure OpenAI embeddings
 *   - AI_GENERATE_EMBEDDINGS() function for vector generation
 *   - sp_invoke_external_rest_endpoint for LLM chat completions
 * 
 * PREREQUISITES:
 * 1. SQL Server 2025 Express
 * 2. Azure OpenAI resource for EMBEDDINGS
 * 3. Azure OpenAI resource for CHAT (can be same or separate resource)
 * 4. API keys for both Azure OpenAI resources
 *
 * IMPORTANT: Copy this file to setup_openai_local.actual.sql and update with your values.
 *            The .actual.sql file is gitignored and won't be committed.
 * 
 * Configuration (update these):
 *   EMBEDDINGS RESOURCE:
 *   - Resource: your-embeddings-resource
 *   - Deployment: text-embedding-3-small
 * 
 *   CHAT RESOURCE:
 *   - Resource: your-chat-resource
 *   - Deployment: gpt-4o (or your deployment name)
 */

USE ZavaTax;
GO

SET NOCOUNT ON;

PRINT '=== Setting up Azure OpenAI for Local SQL Server 2025 Express ===';
PRINT '';

-- ============================================================================
-- STEP 0: Enable External REST Endpoint (required for AI functions)
-- ============================================================================

EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
GO

EXEC sp_configure 'external rest endpoint enabled', 1;
RECONFIGURE WITH OVERRIDE;
GO

PRINT 'External REST endpoint enabled.';

-- ============================================================================
-- STEP 1: Create Master Key (required for credentials)
-- ============================================================================

IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<REPLACE_WITH_A_STRONG_PASSWORD>';
    PRINT 'Database master key created.';
END
ELSE
BEGIN
    PRINT 'Database master key already exists.';
END
GO

-- ============================================================================
-- STEP 2: Create Database Scoped Credentials
-- ============================================================================
-- IMPORTANT: The credential name MUST match the Azure OpenAI endpoint URL
-- (protocol + FQDN) per the credential naming rules for external models.
--
-- We need TWO credentials - one for embeddings and one for chat completions.
--
-- NOTE: External models must be dropped BEFORE their credentials can be dropped.

-- ============================================================================
-- STEP 2a: Drop existing External Model first (required before credential drop)
-- ============================================================================

IF EXISTS (SELECT * FROM sys.external_models WHERE name = 'AzureOpenAI_Embeddings')
BEGIN
    DROP EXTERNAL MODEL AzureOpenAI_Embeddings;
    PRINT 'Dropped existing external model (required before credential update).';
END
GO

-- ============================================================================
-- STEP 2b: Credential for EMBEDDINGS resource
-- ============================================================================

-- Drop existing credential if updating
IF EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'https://your-embeddings-resource.openai.azure.com/')
BEGIN
    DROP DATABASE SCOPED CREDENTIAL [https://your-embeddings-resource.openai.azure.com/];
    PRINT 'Dropped existing embeddings credential.';
END
GO

-- Create credential for embeddings - name must match the endpoint URL pattern
CREATE DATABASE SCOPED CREDENTIAL [https://your-embeddings-resource.openai.azure.com/]
WITH IDENTITY = 'HTTPEndpointHeaders', 
SECRET = '{"api-key":"YOUR_EMBEDDINGS_API_KEY"}';
GO

PRINT 'Azure OpenAI EMBEDDINGS credential created.';

-- ============================================================================
-- STEP 2c: Credential for CHAT resource
-- ============================================================================
-- IMPORTANT: Update the resource name and API key for your chat resource!

-- Drop existing credential if updating
IF EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'https://your-chat-resource.openai.azure.com/')
BEGIN
    DROP DATABASE SCOPED CREDENTIAL [https://your-chat-resource.openai.azure.com/];
    PRINT 'Dropped existing chat credential.';
END
GO

-- Create credential for chat completions
-- TODO: Replace YOUR_CHAT_API_KEY with your actual API key
CREATE DATABASE SCOPED CREDENTIAL [https://your-chat-resource.openai.azure.com/]
WITH IDENTITY = 'HTTPEndpointHeaders', 
SECRET = '{"api-key":"YOUR_CHAT_API_KEY"}';
GO

PRINT 'Azure OpenAI CHAT credential created.';

-- ============================================================================
-- STEP 3: Create External Model for Embeddings
-- ============================================================================
-- Note: Model was already dropped in Step 2a to allow credential updates

-- Create external model pointing to Azure OpenAI embedding deployment
CREATE EXTERNAL MODEL AzureOpenAI_Embeddings
WITH (
    LOCATION = 'https://your-embeddings-resource.openai.azure.com/openai/deployments/text-embedding-3-small/embeddings?api-version=2024-02-01',
    API_FORMAT = 'Azure OpenAI',
    MODEL_TYPE = EMBEDDINGS,
    MODEL = 'text-embedding-3-small',
    CREDENTIAL = [https://your-embeddings-resource.openai.azure.com/]
);
GO

PRINT 'External model AzureOpenAI_Embeddings created.';

-- Grant execute permission to all users (for demo purposes)
GRANT EXECUTE ON EXTERNAL MODEL::AzureOpenAI_Embeddings TO PUBLIC;
GO

-- ============================================================================
-- STEP 4: Test the configuration
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
    PRINT '  1. Azure OpenAI resource name is correct';
    PRINT '  2. API key is valid (update the credential SECRET)';
    PRINT '  3. text-embedding-3-small deployment exists';
    PRINT '  4. SQL Server has outbound internet access';
END CATCH

PRINT '';
PRINT '=== Setup Complete ===';
PRINT '';
PRINT 'Usage: SELECT AI_GENERATE_EMBEDDINGS(N''your text'' USE MODEL AzureOpenAI_Embeddings)';
GO

-- ============================================================================
-- STEP 5: RAG-Augmented Assistant Stored Procedure
-- ============================================================================
-- This procedure:
-- 1. Uses vector search to find relevant KB content
-- 2. Calls Azure OpenAI chat API via sp_invoke_external_rest_endpoint for LLM response
--
-- NOTE: SQL Server 2025 only supports EMBEDDINGS model type for CREATE EXTERNAL MODEL.
-- For chat completions, we use sp_invoke_external_rest_endpoint directly.

IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'AskTaxAssistant')
    DROP PROCEDURE AskTaxAssistant;
GO

CREATE PROCEDURE AskTaxAssistant
    @Question NVARCHAR(MAX),
    @Context NVARCHAR(MAX) = NULL,  -- Optional: current form step context
    @TopK INT = 3,
    @ChatDeploymentName NVARCHAR(100) = 'gpt-5.2-chat',  -- Parameterized model deployment name
    @ChatResourceName NVARCHAR(100) = 'your-chat-resource'  -- Azure OpenAI resource name
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
    DECLARE @ChatUrl NVARCHAR(500);
    
    -- Build the chat completion URL with parameterized deployment and resource names
    SET @ChatUrl = N'https://' + @ChatResourceName + '.openai.azure.com/openai/deployments/' + @ChatDeploymentName + '/chat/completions?api-version=2024-02-01';
    
    -- Step 1: Retrieve relevant knowledge base content via vector search
    IF EXISTS (SELECT * FROM sys.external_models WHERE name = 'AzureOpenAI_Embeddings')
    BEGIN
        BEGIN TRY
            DECLARE @embedding VECTOR(1536);
            SELECT @embedding = AI_GENERATE_EMBEDDINGS(@Question USE MODEL AzureOpenAI_Embeddings);
            
            IF @embedding IS NOT NULL
            BEGIN
                -- Get relevant KB snippets (limited to 500 chars each for faster LLM response)
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
            -- Continue without vector search
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
        WHERE Content LIKE '%' + @Question + '%'
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
    -- Escape JSON special characters using STRING_ESCAPE for proper JSON encoding
    SET @SystemPrompt = STRING_ESCAPE(@SystemPrompt, 'json');
    SET @UserPrompt = STRING_ESCAPE(@UserPrompt, 'json');
    
    -- GPT-5.2 is a reasoning model - it uses tokens for internal "thinking" before output
    -- Need enough tokens for both reasoning (~500-1000) AND the actual response (~300-500)
    SET @JsonPayload = N'{
        "messages": [
            {"role": "system", "content": "' + @SystemPrompt + '"},
            {"role": "user", "content": "' + @UserPrompt + '"}
        ],
        "max_completion_tokens": 2000
    }';
    
    DECLARE @DebugLen INT;
    
    BEGIN TRY
        -- Use parameterized URL for the chat resource and deployment
        EXEC @RetVal = sp_invoke_external_rest_endpoint
            @url = @ChatUrl,
            @method = 'POST',
            @credential = [https://your-chat-resource.openai.azure.com/],
            @payload = @JsonPayload,
            @response = @ResponseJson OUTPUT;
        
        -- Debug: Show return value and response
        SET @DebugLen = LEN(ISNULL(@ResponseJson, ''));
        RAISERROR('REST call RetVal=%d, ResponseLen=%d', 0, 1, @RetVal, @DebugLen) WITH NOWAIT;
        
        IF @RetVal = 0 AND @ResponseJson IS NOT NULL
        BEGIN
            -- Extract the response content from JSON
            SELECT @Response = JSON_VALUE(@ResponseJson, '$.result.choices[0].message.content');
            
            -- Debug: Show extracted response
            SET @DebugLen = LEN(ISNULL(@Response, ''));
            RAISERROR('Extracted response length=%d', 0, 1, @DebugLen) WITH NOWAIT;
            
            -- Check for both NULL and empty string
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
                -- Try alternative path or check for error
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
        -- Log error for debugging (will show in SSMS Messages)
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

PRINT 'RAG-augmented assistant procedure created.';
PRINT '';
PRINT 'Usage: EXEC AskTaxAssistant @Question = ''What deductions can I claim for working from home?''';
PRINT '       EXEC AskTaxAssistant @Question = ''Should I itemize?'', @Context = ''User has $15000 in deductions''';
GO
