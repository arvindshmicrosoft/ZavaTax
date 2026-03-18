# Zava Tax - Azure SQL DB Hyperscale Demonstration Application

## Executive Summary

Zava Tax is a comprehensive full-stack demonstration application showcasing Azure SQL DB Hyperscale capabilities in a realistic tax preparation and filing scenario. The application demonstrates how a national tax preparation company (similar to H&R Block) can leverage Azure SQL DB Hyperscale's advanced features to deliver exceptional performance, AI-powered assistance, and real-time analytics across hundreds of branch locations.

---

## Table of Contents

1. [Business Scenario](#business-scenario)
2. [Personas & User Journeys](#personas--user-journeys)
3. [System Architecture](#system-architecture)
4. [Azure SQL DB Hyperscale Features Demonstration](#azure-sql-db-hyperscale-features-demonstration)
5. [Database Schema Design](#database-schema-design)
6. [Application Components](#application-components)
7. [Demo Scenarios](#demo-scenarios)
8. [Technical Implementation Details](#technical-implementation-details)

---

## Business Scenario

### Company Overview

**Zava Tax** is a national tax preparation company with:
- **500+ branch locations** (franchisees) across the United States
- **Peak season processing**: January - April (tax filing season)
- **Millions of tax returns** processed annually
- **Walk-in customers** bringing physical documents for digitization and filing
- **AI-assisted** tax preparation for both customers and tax professionals

### Operational Model

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           ZAVA TAX ARCHITECTURE                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│   │  Branch 1    │  │  Branch 2    │  │  Branch N    │  │   Online     │   │
│   │  (Walk-in)   │  │  (Walk-in)   │  │  (Walk-in)   │  │   Portal     │   │
│   └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘   │
│          │                 │                 │                 │            │
│          └────────────────┬┴─────────────────┴─────────────────┘            │
│                           │                                                  │
│                           ▼                                                  │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                    Application Layer (API Gateway)                   │   │
│   │         Load Balanced across Azure App Service instances             │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                           │                                                  │
│          ┌────────────────┼────────────────────────┐                        │
│          ▼                ▼                        ▼                        │
│   ┌─────────────┐  ┌─────────────────┐  ┌──────────────────┐               │
│   │   Primary   │  │  Named Replica  │  │  Named Replica   │               │
│   │   (R/W)     │  │  (RAG Queries)  │  │  (Analytics)     │               │
│   │             │  │  Low Latency    │  │  HTAP Workload   │               │
│   └─────────────┘  └─────────────────┘  └──────────────────┘               │
│          │                                                                   │
│          │ Hyperscale Shared Storage                                        │
│          ▼                                                                   │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │              Azure SQL DB Hyperscale (Current Year)                  │   │
│   │                   High-Throughput Transaction Log                    │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                           │                                                  │
│                           │ Mirroring                                       │
│                           ▼                                                  │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                     Microsoft Fabric                                 │   │
│   │              (Consolidated Multi-Year Analytics)                     │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │           Hyperscale Elastic Pool (Historical Years)                 │   │
│   │    ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐              │   │
│   │    │ TY 2025 │  │ TY 2024 │  │ TY 2023 │  │ TY 2022 │              │   │
│   │    └─────────┘  └─────────┘  └─────────┘  └─────────┘              │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Personas & User Journeys

### 1. 👤 Tax Filer (End Customer)

**Profile**: Individual unfamiliar with tax codes, deductions, and filing requirements.

**User Journey**:
1. Walks into a Zava Tax branch with W-2s, 1099s, and receipts
2. Documents are scanned and digitized using OCR
3. **AI Assistant** answers questions like:
   - "What deductions am I eligible for?"
   - "Should I itemize or take standard deduction?"
   - "What documents do I still need?"
4. Reviews AI-generated tax return summary
5. Signs and files electronically

**Hyperscale Features Used**:
- **Vector Search** for semantic Q&A about tax situations
- **Named Replica (RAG)** for low-latency AI responses
- **JSON Support** for storing extracted document data

---

### 2. 👨‍💼 Tax Preparation Expert

**Profile**: Licensed tax professional helping customers file complex returns.

**User Journey**:
1. Views queue of customers assigned to them
2. Accesses customer's uploaded documents and extracted data
3. Uses AI copilot to:
   - Find similar past cases for complex situations
   - Get recommendations on deductions
   - Identify potential audit flags
4. Makes adjustments and finalizes return
5. Generates explanation documents for customer

**Hyperscale Features Used**:
- **Vector Search** for finding similar historical cases
- **Secure Model Invocation** via Azure AI Foundry for copilot features
- **JSON Support** for complex tax form structures

---

### 3. 📊 Branch Manager

**Profile**: Manages daily operations at a single branch location.

**User Journey**:
1. Views real-time dashboard of branch performance
2. Monitors:
   - Returns completed today vs. target
   - Average processing time
   - Customer satisfaction scores
   - Income processed metrics
3. Identifies bottlenecks and reassigns staff

**Hyperscale Features Used**:
- **Columnstore Indexes (HTAP)** for real-time aggregations
- **Named Replica (Analytics)** for dashboard queries

---

### 4. 📈 Company Executive

**Profile**: C-suite executive needing company-wide insights.

**User Journey**:
1. Accesses executive dashboard
2. Views:
   - National performance heat map
   - Income processing trends (real-time)
   - AI-generated insights on business performance
   - Anomaly detection alerts
3. Drills down into regional/branch performance
4. Uses natural language queries: "Why did income volume drop in Texas this week?"

**Hyperscale Features Used**:
- **Columnstore Indexes (HTAP)** for large-scale aggregations
- **Vector Search + AI** for natural language business queries
- **Named Replica** for analytics without impacting OLTP

---

### 5. 🔧 DevOps Engineer

**Profile**: Platform engineer ensuring system reliability and performance.

**User Journey**:
1. Monitors Hyperscale performance dashboard
2. Tracks:
   - Transaction log throughput (high sustained throughput during peak)
   - Query performance across replicas
   - Storage utilization
   - Replica lag metrics
3. Manages named replica scaling during peak periods
4. Reviews query store for optimization opportunities

**Hyperscale Features Used**:
- **High Transaction Log Throughput** monitoring
- **Named Replicas** management
- **Hyperscale-specific DMVs** for performance insights

---

## Azure SQL DB Hyperscale Features Demonstration

### Feature 1: Vector Indexes for Semantic Search

**Business Use Case**: Enable AI-powered assistance by semantically searching tax knowledge bases, IRS publications, and historical case data.

**Implementation**:
```sql
-- Tax Knowledge Base with Vector Embeddings
CREATE TABLE TaxKnowledgeBase (
    KnowledgeId INT IDENTITY PRIMARY KEY,
    Category NVARCHAR(100),
    Topic NVARCHAR(500),
    Content NVARCHAR(MAX),
    ContentEmbedding VECTOR(1536),  -- OpenAI ada-002 embeddings
    LastUpdated DATETIME2,
    SourceDocument NVARCHAR(500)
);

-- Create DiskANN vector index for fast similarity search
CREATE VECTOR INDEX IX_TaxKnowledge_Embedding
ON TaxKnowledgeBase(ContentEmbedding)
WITH (METRIC = 'cosine', TYPE = 'DISKANN');

-- Historical Tax Returns with Embeddings (for similar case finding)
CREATE TABLE TaxReturnEmbeddings (
    ReturnId INT PRIMARY KEY,
    TaxYear INT,
    SituationSummary NVARCHAR(MAX),
    SituationEmbedding VECTOR(1536),
    DeductionCategories NVARCHAR(MAX),  -- JSON array
    TotalRefund DECIMAL(12,2),
    AuditRisk DECIMAL(5,4)
);

CREATE VECTOR INDEX IX_TaxReturn_Situation
ON TaxReturnEmbeddings(SituationEmbedding)
WITH (METRIC = 'cosine', TYPE = 'DISKANN');
```

**Demo Scenarios**:
1. Customer asks: "Can I deduct my home office if I work remotely part-time?"
2. System converts question to embedding, searches knowledge base
3. Returns relevant IRS guidance with citations
4. Tax expert searches for similar complex cases to reference

---

### Feature 2: Hyperscale Read Scale with Named Replicas

**Business Use Case**: Separate workloads to ensure transactional operations (filing returns) aren't impacted by AI/RAG queries or analytics.

**Architecture**:
```
┌─────────────────────────────────────────────────────────────────┐
│                    Named Replica Strategy                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   PRIMARY (your-db-primary)                                     │
│   ├── All WRITE operations                                      │
│   ├── Transactional reads (customer lookup, return submission)  │
│   └── Connection String: ApplicationIntent=ReadWrite            │
│                                                                  │
│   REPLICA: RAG (your-db-rag)                                    │
│   ├── AI/Vector search queries                                  │
│   ├── Embedding similarity searches                             │
│   ├── Optimized for low-latency point queries                   │
│   └── SLO: < 100ms p95 response time                           │
│                                                                  │
│   REPLICA: Analytics (zavatax-analytics)                        │
│   ├── Dashboard queries                                         │
│   ├── HTAP workloads with columnstore                          │
│   ├── Executive reporting                                       │
│   └── SLO: Complex queries without impacting OLTP              │
│                                                                  │
│   REPLICA: DevOps (zavatax-devops)                              │
│   ├── Performance monitoring queries                            │
│   ├── Query Store analysis                                      │
│   └── Diagnostic workloads                                      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Implementation**:
```sql
-- Create named replicas (Azure CLI / Bicep)
-- az sql db replica create --name your-database 
--    --partner-server your-rag-server 
--    --partner-database your-rag-db 
--    --secondary-type Named

-- Application routing in connection strings
-- Primary: Server=your-server-primary.database.windows.net;Database=zavatax;
-- RAG: Server=your-server-rag.database.windows.net;Database=zavatax;
-- Analytics: Server=your-server-analytics.database.windows.net;Database=zavatax;
```

**Demo Scenarios**:
1. Show simultaneous high-throughput OLTP on primary
2. Execute RAG queries on named replica with consistent low latency
3. Run heavy analytics on analytics replica
4. Monitor that primary performance is unaffected

---

### Feature 3: Secure Model Invocation via Azure AI Foundry

**Business Use Case**: Invoke Azure OpenAI models directly from T-SQL for:
- Generating embeddings
- AI-powered responses
- Summarization
- Risk analysis

**Implementation** (using Managed Identity - no API keys):
```sql
-- Configure external REST endpoint for Azure OpenAI using Managed Identity
-- Prerequisites: Grant SQL Server's managed identity "Cognitive Services OpenAI User" role

CREATE DATABASE SCOPED CREDENTIAL AzureOpenAICredential
WITH IDENTITY = 'Managed Identity',
SECRET = '{"resourceid": "https://cognitiveservices.azure.com"}';

CREATE EXTERNAL DATA SOURCE AzureOpenAI
WITH (
    TYPE = REST,
    LOCATION = 'https://your-openai-resource.openai.azure.com',
    CREDENTIAL = AzureOpenAICredential
);

-- Generate embeddings for customer question
CREATE PROCEDURE GenerateEmbedding
    @InputText NVARCHAR(MAX),
    @Embedding VECTOR(1536) OUTPUT
AS
BEGIN
    DECLARE @response NVARCHAR(MAX);
    DECLARE @payload NVARCHAR(MAX) = '{"input": "' + @InputText + '"}';
    
    EXEC sp_invoke_external_rest_endpoint
        @url = '/openai/deployments/text-embedding-3-small/embeddings?api-version=2024-02-01',
        @method = 'POST',
        @payload = @payload,
        @headers = '{"Content-Type": "application/json"}',
        @credential = [AzureOpenAICredential],
        @response = @response OUTPUT;
    
    SET @Embedding = CAST(JSON_QUERY(@response, '$.result.data[0].embedding') AS VECTOR(1536));
END;

-- AI-powered tax advice generation
CREATE PROCEDURE GetTaxAdvice
    @CustomerQuestion NVARCHAR(MAX),
    @CustomerContext NVARCHAR(MAX),
    @Response NVARCHAR(MAX) OUTPUT
AS
BEGIN
    DECLARE @systemPrompt NVARCHAR(MAX) = 'You are a helpful tax assistant for Zava Tax. 
        Provide accurate, helpful tax guidance based on the customer context provided.
        Always cite relevant IRS publications when applicable.
        If unsure, recommend consulting with a tax professional.';
    
    DECLARE @payload NVARCHAR(MAX) = JSON_OBJECT(
        'messages': JSON_ARRAY(
            JSON_OBJECT('role': 'system', 'content': @systemPrompt),
            JSON_OBJECT('role': 'user', 'content': CONCAT('Customer Context: ', @CustomerContext, 
                CHAR(13), CHAR(10), 'Question: ', @CustomerQuestion))
        ),
        'max_tokens': 1000,
        'temperature': 0.3
    );
    
    EXEC sp_invoke_external_rest_endpoint
        @url = '/openai/deployments/gpt-5.2-chat/chat/completions?api-version=2024-02-01',
        @method = 'POST',
        @payload = @payload,
        @data_source = 'AzureOpenAI',
        @response = @Response OUTPUT;
END;
```

**Demo Scenarios**:
1. Customer asks tax question → embedding generated → vector search → context retrieved → GPT-5.2 generates response
2. Tax professional requests risk analysis on return
3. Executive asks natural language question about business metrics

---

### Feature 4: Columnstore Indexes for HTAP

**Business Use Case**: Real-time analytics on operational data without ETL delays.

**Implementation**:
```sql
-- TaxReturns table with NCCI for real-time analytics
CREATE TABLE TaxReturns (
    ReturnId BIGINT NOT NULL,
    CustomerId INT NOT NULL,
    BranchId INT NOT NULL,
    TaxProfessionalId INT NOT NULL,
    TaxYear INT NOT NULL,
    FilingDate DATETIME2 NOT NULL,
    
    -- Financial metrics
    GrossIncome DECIMAL(14,2),
    AdjustedGrossIncome DECIMAL(14,2),
    TotalDeductions DECIMAL(14,2),
    TaxableIncome DECIMAL(14,2),
    TaxLiability DECIMAL(14,2),
    TotalWithheld DECIMAL(14,2),
    RefundAmount DECIMAL(14,2),
    AmountOwed DECIMAL(14,2),
    
    -- Operational metrics
    ProcessingTimeMinutes INT,
    DocumentCount INT,
    AIAssistanceCount INT,
    
    -- Timestamps
    CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME(),
    
    INDEX NCCI_TaxReturns_Analytics NONCLUSTERED COLUMNSTORE
);

-- Add nonclustered rowstore index for point queries
CREATE NONCLUSTERED INDEX IX_TaxReturn_Customer 
ON TaxReturns(CustomerId, TaxYear);

CREATE NONCLUSTERED INDEX IX_TaxReturn_Branch_Date
ON TaxReturns(BranchId, FilingDate);

-- Real-time analytics view for branch dashboard
CREATE VIEW vw_BranchPerformanceRealtime AS
SELECT 
    b.BranchId,
    b.BranchName,
    b.City,
    b.State,
    COUNT(*) AS ReturnsToday,
    SUM(CASE WHEN f.RefundAmount > 0 THEN 1 ELSE 0 END) AS RefundsIssued,
    AVG(f.ProcessingTimeMinutes) AS AvgProcessingMinutes,
    SUM(f.RefundAmount) AS TotalRefundsToday,
    AVG(f.RefundAmount) AS AvgRefundAmount,
    COUNT(DISTINCT f.TaxProfessionalId) AS ActiveProfessionals
FROM TaxReturns f
JOIN Branches b ON f.BranchId = b.BranchId
WHERE f.FilingDate >= CAST(GETDATE() AS DATE)
GROUP BY b.BranchId, b.BranchName, b.City, b.State;

-- Company-wide executive dashboard
CREATE VIEW vw_ExecutiveDashboard AS
SELECT 
    TaxYear,
    DATEPART(week, FilingDate) AS FilingWeek,
    COUNT(*) AS TotalReturns,
    SUM(RefundAmount) AS TotalRefunds,
    SUM(AmountOwed) AS TotalOwed,
    AVG(ProcessingTimeMinutes) AS AvgProcessingTime,
    SUM(CASE WHEN AIAssistanceCount > 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS AIAssistedPct,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY RefundAmount) 
        OVER (PARTITION BY TaxYear, DATEPART(week, FilingDate)) AS MedianRefund
FROM TaxReturns
GROUP BY TaxYear, DATEPART(week, FilingDate);
```

**Demo Scenarios**:
1. Branch manager views real-time dashboard with sub-second response
2. Executive runs ad-hoc analytics across millions of returns
3. Show OLTP transactions continuing at full speed during analytics
4. Compare columnstore scan performance vs. rowstore

---

### Feature 5: High-Throughput Transaction Log

**Business Use Case**: Handle massive ingestion during tax season peak (April 15th deadline) when thousands of returns are filed simultaneously across all branches.

**Implementation & Monitoring**:
```sql
-- High-throughput batch ingestion procedure
CREATE PROCEDURE BulkIngestScannedDocuments
    @DocumentBatch NVARCHAR(MAX)  -- JSON array of documents
AS
BEGIN
    SET NOCOUNT ON;
    
    INSERT INTO ScannedDocuments (
        CustomerId, DocumentType, OCRText, 
        ExtractedData, DocumentEmbedding, ScannedAt, BranchId
    )
    SELECT 
        JSON_VALUE(doc.value, '$.customerId'),
        JSON_VALUE(doc.value, '$.documentType'),
        JSON_VALUE(doc.value, '$.ocrText'),
        JSON_QUERY(doc.value, '$.extractedData'),
        CAST(JSON_VALUE(doc.value, '$.embedding') AS VECTOR(1536)),
        SYSUTCDATETIME(),
        JSON_VALUE(doc.value, '$.branchId')
    FROM OPENJSON(@DocumentBatch) AS doc;
END;

-- Monitor transaction log throughput
CREATE VIEW vw_TransactionLogThroughput AS
SELECT 
-- Resource utilization monitoring
SELECT TOP 10
    end_time,
    avg_cpu_percent,
    avg_data_io_percent,
    avg_log_write_percent,
    avg_memory_usage_percent,
    max_worker_percent,
    max_session_percent
FROM sys.dm_db_resource_stats
ORDER BY end_time DESC;

-- DevOps monitoring dashboard query
CREATE PROCEDURE GetHyperscalePerformanceMetrics
AS
BEGIN
    -- Resource utilization
    SELECT 
        'CPU Utilization' AS Metric,
        avg_cpu_percent AS CurrentValue,
        80 AS TargetValue,
        CASE WHEN avg_cpu_percent <= 60 THEN 'HEALTHY' 
             WHEN avg_cpu_percent <= 80 THEN 'WARNING'
             ELSE 'CRITICAL' END AS Status
    FROM sys.dm_db_resource_stats
    WHERE end_time = (SELECT MAX(end_time) FROM sys.dm_db_resource_stats);
    
    -- Log write percentage
    SELECT 
        'Log Write %' AS Metric,
        avg_log_write_percent AS CurrentValue,
        80 AS TargetValue,
        CASE WHEN avg_log_write_percent <= 60 THEN 'HEALTHY'
             WHEN avg_log_write_percent <= 80 THEN 'WARNING'
             ELSE 'CRITICAL' END AS Status
    FROM sys.dm_db_resource_stats
    WHERE end_time = (SELECT MAX(end_time) FROM sys.dm_db_resource_stats);
    
    -- Replica lag
    SELECT 
        replica_name,
        'Replica Lag (seconds)' AS Metric,
        lag_seconds AS CurrentValue,
        5 AS TargetValue,
        CASE WHEN lag_seconds <= 5 THEN 'HEALTHY'
             WHEN lag_seconds <= 15 THEN 'WARNING'
             ELSE 'CRITICAL' END AS Status
    FROM sys.dm_hyperscale_replica_states;
END;
```

**Demo Scenarios**:
1. Simulate peak load with thousands of concurrent return submissions
2. Monitor transaction log throughput under sustained load
3. Show sustained high throughput without performance degradation
4. Demonstrate auto-scaling of page servers

---

### Feature 6: JSON Support

**Business Use Case**: Store and query complex, semi-structured tax data including extracted form fields, API responses, and flexible metadata.

**Implementation**:
```sql
-- Store tax forms with flexible JSON structure
CREATE TABLE TaxForms (
    FormId INT IDENTITY PRIMARY KEY,
    ReturnId INT NOT NULL,
    FormType NVARCHAR(20) NOT NULL,  -- W2, 1099-INT, 1099-DIV, Schedule A, etc.
    TaxYear INT NOT NULL,
    
    -- JSON storage for form-specific fields
    FormData NVARCHAR(MAX) NOT NULL,  -- Full form data as JSON
    ExtractedFields AS JSON_QUERY(FormData, '$.fields') PERSISTED,
    
    -- Commonly queried fields as computed columns
    EmployerEIN AS JSON_VALUE(FormData, '$.employer.ein'),
    WageAmount AS CAST(JSON_VALUE(FormData, '$.wages.total') AS DECIMAL(14,2)),
    
    -- Validation status
    ValidationResults NVARCHAR(MAX),  -- JSON with validation errors/warnings
    
    CONSTRAINT CK_FormData_IsJson CHECK (ISJSON(FormData) = 1),
    CONSTRAINT CK_ValidationResults_IsJson CHECK (ISJSON(ValidationResults) = 1 OR ValidationResults IS NULL)
);

-- Index for JSON property queries
CREATE INDEX IX_TaxForms_EmployerEIN ON TaxForms(EmployerEIN) WHERE FormType = 'W2';

-- Customer profile with flexible preferences and history
CREATE TABLE CustomerProfiles (
    CustomerId INT PRIMARY KEY,
    PersonalInfo NVARCHAR(MAX),  -- JSON: name, SSN (encrypted), DOB, address
    FilingPreferences NVARCHAR(MAX),  -- JSON: direct deposit, e-file consent, etc.
    TaxHistory NVARCHAR(MAX),  -- JSON array: summary of past returns
    AIInteractionLog NVARCHAR(MAX),  -- JSON array: questions asked, responses received
    
    -- Computed columns for common queries
    PreferredLanguage AS JSON_VALUE(FilingPreferences, '$.language'),
    DirectDepositEnabled AS CAST(JSON_VALUE(FilingPreferences, '$.directDeposit.enabled') AS BIT)
);

-- JSON aggregation for API responses
CREATE PROCEDURE GetCustomerTaxSummary
    @CustomerId INT
AS
BEGIN
    SELECT 
        c.CustomerId,
        JSON_VALUE(c.PersonalInfo, '$.firstName') AS FirstName,
        JSON_VALUE(c.PersonalInfo, '$.lastName') AS LastName,
        
        -- Aggregate forms into JSON array
        (SELECT 
            FormType,
            TaxYear,
            JSON_QUERY(FormData, '$.summary') AS Summary
         FROM TaxForms f
         WHERE f.ReturnId IN (SELECT ReturnId FROM TaxReturns WHERE CustomerId = @CustomerId)
         FOR JSON PATH) AS Forms,
         
        -- Aggregate returns into JSON array
        (SELECT 
            TaxYear,
            FilingStatus,
            RefundAmount,
            FilingDate
         FROM TaxReturns r
         WHERE r.CustomerId = @CustomerId
         FOR JSON PATH) AS Returns
    FROM CustomerProfiles c
    WHERE c.CustomerId = @CustomerId
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
END;

-- Query JSON data for analytics
SELECT 
    JSON_VALUE(FormData, '$.employer.name') AS Employer,
    COUNT(*) AS W2Count,
    SUM(CAST(JSON_VALUE(FormData, '$.wages.total') AS DECIMAL(14,2))) AS TotalWages
FROM TaxForms
WHERE FormType = 'W2' AND TaxYear = 2026
GROUP BY JSON_VALUE(FormData, '$.employer.name')
ORDER BY TotalWages DESC;
```

**Demo Scenarios**:
1. Ingest W-2 from OCR as JSON, extract fields dynamically
2. Query across heterogeneous form types using JSON functions
3. Build flexible API responses with FOR JSON
4. Show computed columns for frequently accessed JSON properties

---

## Database Schema Design

### Core Tables

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           ZAVA TAX SCHEMA                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  REFERENCE DATA                     OPERATIONAL DATA                         │
│  ┌─────────────────┐               ┌─────────────────────┐                  │
│  │ Branches        │               │ Customers           │                  │
│  │ TaxProfessionals│               │ CustomerProfiles    │                  │
│  │ TaxCodes        │               │ TaxReturns          │                  │
│  │ DeductionRules  │               │ TaxForms            │                  │
│  └─────────────────┘               │ ScannedDocuments    │                  │
│                                    │ Appointments        │                  │
│  AI/VECTOR DATA                    └─────────────────────┘                  │
│  ┌─────────────────┐                                                        │
│  │ TaxKnowledgeBase│               ANALYTICS (COLUMNSTORE)                  │
│  │ TaxReturnEmbedd.│               ┌─────────────────────┐                  │
│  │ ConversationLog │               │ TaxReturns          │                  │
│  └─────────────────┘               │ DailyBranchMetrics  │                  │
│                                    │ AIUsageMetrics      │                  │
│  AUDIT & COMPLIANCE                └─────────────────────┘                  │
│  ┌─────────────────┐                                                        │
│  │ AuditLog        │               DEVOPS MONITORING                        │
│  │ DataAccess      │               ┌─────────────────────┐                  │
│  │ SecurityEvents  │               │ QueryPerformanceLog │                  │
│  └─────────────────┘               │ SystemHealthSnapshots│                 │
│                                    └─────────────────────┘                  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Application Components

### Technology Stack

| Layer | Technology | Purpose |
|-------|------------|---------|
| **Frontend** | React + TypeScript | Single Page Application |
| **API Gateway** | Azure API Management | Request routing, rate limiting |
| **Backend API** | ASP.NET Core 8 | REST APIs, business logic |
| **Database** | Azure SQL DB Hyperscale | Primary data store |
| **AI Services** | Azure AI Foundry | GPT-5.2, Embeddings |
| **Search** | Native Vector Search | Semantic search in SQL |
| **Cache** | Azure Redis | Session, frequent queries |
| **File Storage** | Azure Blob Storage | Scanned documents |
| **Analytics** | Microsoft Fabric | Multi-year consolidated analytics |
| **Monitoring** | Azure Monitor + App Insights | Observability |

### Application Modules

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        APPLICATION MODULES                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    CUSTOMER PORTAL MODULE                            │   │
│  │  • Document upload & OCR processing                                  │   │
│  │  • AI Tax Assistant chat interface                                   │   │
│  │  • Return status tracking                                            │   │
│  │  • E-signature & filing                                              │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    TAX PROFESSIONAL MODULE                           │   │
│  │  • Customer queue management                                         │   │
│  │  • Return preparation workspace                                      │   │
│  │  • AI Copilot for complex cases                                     │   │
│  │  • Similar case search                                               │   │
│  │  • Audit risk assessment                                             │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    BRANCH MANAGER MODULE                             │   │
│  │  • Real-time branch dashboard                                        │   │
│  │  • Staff performance tracking                                        │   │
│  │  • Appointment scheduling                                            │   │
│  │  • Inventory & supplies management                                   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    EXECUTIVE DASHBOARD MODULE                        │   │
│  │  • Company-wide KPI dashboard                                        │   │
│  │  • Natural language query interface                                  │   │
│  │  • AI-generated insights                                             │   │
│  │  • Predictive analytics                                              │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    DEVOPS MONITORING MODULE                          │   │
│  │  • Hyperscale performance dashboard                                  │   │
│  │  • Named replica management                                          │   │
│  │  • Transaction log throughput monitoring                             │   │
│  │  • Query performance analysis                                        │   │
│  │  • Alerting & incident management                                    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Demo Scenarios

### Demo 1: AI-Powered Tax Assistance (Vector Search + RAG)

**Duration**: 5 minutes

**Steps**:
1. Customer opens chat: "I work from home 3 days a week. Can I deduct my home office?"
2. Show embedding generation via Azure AI Foundry
3. Execute vector search on TaxKnowledgeBase (show query plan with DISKANN index)
4. Retrieve top-5 relevant IRS guidelines
5. GPT-5.2 generates contextual response with citations
6. Show query executing on RAG named replica (not primary)

**Key Metrics**:
- Embedding generation: < 200ms
- Vector search: < 50ms
- Total response: < 2 seconds

---

### Demo 2: High-Throughput Filing (Log Throughput)

**Duration**: 5 minutes

**Steps**:
1. Start load generator simulating 500 branches filing simultaneously
2. Show transaction log throughput climbing under sustained load
3. Monitor primary replica performance (OLTP response times)
4. Demonstrate that RAG and Analytics replicas remain responsive
5. Show no degradation in customer-facing operations

**Key Metrics**:
- Transaction log throughput: sustained high throughput (varies by SKU; up to 100 MB/s per vCore)
- OLTP p99 latency: < 100ms
- Zero failed transactions

---

### Demo 3: Real-Time Executive Analytics (HTAP + Columnstore)

**Duration**: 5 minutes

**Steps**:
1. Executive opens dashboard while OLTP load is running
2. Execute aggregation query across 10M+ returns
3. Show columnstore index usage in query plan
4. Query runs on Analytics named replica
5. Compare performance vs. rowstore (10x+ improvement)
6. Drill-down queries with instant response

**Key Metrics**:
- Aggregation across 10M rows: < 2 seconds
- No impact on OLTP workload
- Sub-second drill-down queries

---

### Demo 4: Similar Case Search for Tax Professionals (Vector Search)

**Duration**: 3 minutes

**Steps**:
1. Tax professional has complex case (rental property + cryptocurrency)
2. Enter case description
3. System generates embedding and searches historical returns
4. Returns top-5 similar cases with outcomes
5. Professional reviews how similar cases were handled
6. Show similarity scores and relevant deduction categories

**Key Metrics**:
- Similar case search: < 500ms
- High relevance of returned cases

---

### Demo 5: DevOps Monitoring Dashboard (Hyperscale Metrics)

**Duration**: 5 minutes

**Steps**:
1. Open DevOps monitoring dashboard
2. Show real-time metrics:
   - Transaction log throughput gauge
   - Page server read latency
   - Named replica lag
   - Storage utilization
3. Simulate load spike, watch metrics respond
4. Show Query Store analysis for top resource-consuming queries
5. Demonstrate named replica health and failover capabilities

**Key Metrics**:
- All dashboards real-time (< 5 second refresh)
- Clear visualization of Hyperscale-specific metrics

---

## Technical Implementation Details

### Project Structure

```
ZavaTax/
├── docs/
│   └── ARCHITECTURE_AND_DEMO_DESIGN.md
├── src/
│   ├── ZavaTax.Web/                    # React frontend
│   │   ├── src/
│   │   │   ├── components/
│   │   │   │   ├── customer/           # Customer portal components
│   │   │   │   ├── professional/       # Tax pro components
│   │   │   │   ├── manager/            # Branch manager components
│   │   │   │   ├── executive/          # Executive dashboard
│   │   │   │   └── devops/             # DevOps monitoring
│   │   │   ├── services/               # API clients
│   │   │   └── hooks/                  # React hooks
│   │   └── package.json
│   │
│   ├── ZavaTax.Api/                    # ASP.NET Core Web API
│   │   ├── Controllers/
│   │   │   ├── CustomerController.cs
│   │   │   ├── TaxReturnController.cs
│   │   │   ├── AIAssistantController.cs
│   │   │   ├── AnalyticsController.cs
│   │   │   └── DevOpsController.cs
│   │   ├── Services/
│   │   │   ├── VectorSearchService.cs
│   │   │   ├── EmbeddingService.cs
│   │   │   ├── TaxCalculationService.cs
│   │   │   └── ReplicaRoutingService.cs
│   │   └── Program.cs
│   │
│   └── ZavaTax.Database/               # SQL Database project
│       ├── Tables/
│       ├── Views/
│       ├── StoredProcedures/
│       ├── VectorIndexes/
│       └── SeedData/
│
├── deploy/
│   └── azure/                          # Azure deployment (pure CLI)
│       ├── deploy.ps1                  # Main deployment script
│       ├── deploy-app.ps1              # App-only deployment
│       └── README.md                   # Deployment guide
│
├── load-simulator/                     # Load testing tools
│   ├── oltp/                           # OLTP workflow simulator
│   ├── analytics/                      # Analytics read workload
│   ├── infrastructure/                 # Container deployment
│   └── shared/                         # Metrics & monitoring
│
├── tests/
│   ├── load-tests/                     # k6 or JMeter scripts
│   └── integration-tests/
│
└── README.md
```

### Connection String Strategy

```csharp
// appsettings.json
{
  "ConnectionStrings": {
    "Primary": "Server=your-server-primary.database.windows.net;Database=zavatax;Authentication=Active Directory Default;",
    "RagReplica": "Server=your-server-rag.database.windows.net;Database=zavatax;Authentication=Active Directory Default;ApplicationIntent=ReadOnly;",
    "AnalyticsReplica": "Server=your-server-analytics.database.windows.net;Database=zavatax;Authentication=Active Directory Default;ApplicationIntent=ReadOnly;",
    "DevOpsReplica": "Server=your-server-devops.database.windows.net;Database=zavatax;Authentication=Active Directory Default;ApplicationIntent=ReadOnly;"
  }
}

// ReplicaRoutingService.cs
public class ReplicaRoutingService
{
    public SqlConnection GetConnection(WorkloadType workload)
    {
        return workload switch
        {
            WorkloadType.Transactional => new SqlConnection(_config["ConnectionStrings:Primary"]),
            WorkloadType.VectorSearch => new SqlConnection(_config["ConnectionStrings:RagReplica"]),
            WorkloadType.Analytics => new SqlConnection(_config["ConnectionStrings:AnalyticsReplica"]),
            WorkloadType.Monitoring => new SqlConnection(_config["ConnectionStrings:DevOpsReplica"]),
            _ => new SqlConnection(_config["ConnectionStrings:Primary"])
        };
    }
}
```

### Key Performance Targets

| Metric | Target | Demonstration |
|--------|--------|---------------|
| Vector Search Latency | < 50ms p95 | RAG queries on named replica |
| Transaction Log Throughput | High sustained (up to 100 MB/s per vCore) | Peak load simulation |
| OLTP Response Time | < 100ms p99 | During concurrent analytics |
| Analytics Query Time | < 2s for 10M rows | Columnstore aggregations |
| Named Replica Lag | < 5 seconds | Real-time monitoring |
| AI Response Generation | < 3 seconds | End-to-end RAG pipeline |

---

## Next Steps

1. **Phase 1**: Set up database schema and Hyperscale infrastructure
2. **Phase 2**: Implement core API with replica routing
3. **Phase 3**: Build vector search and AI integration
4. **Phase 4**: Create frontend dashboards for each persona
5. **Phase 5**: Implement load testing and monitoring
6. **Phase 6**: Create demo scripts and presentation materials

---

## Appendix: Azure Resources Required

| Resource | SKU/Tier | Purpose |
|----------|----------|---------|
| Azure SQL DB Hyperscale | Gen5, 8 vCores | Primary database |
| Named Replicas (3) | Gen5, 4 vCores each | RAG, Analytics, DevOps |
| Hyperscale Elastic Pool | 20 eDTUs | Historical year databases |
| Azure AI Foundry | S0 | GPT-5.2, Embeddings |
| Azure App Service | P2v3 | API hosting |
| Azure Static Web Apps | Standard | Frontend hosting |
| Azure Key Vault | Standard | Secrets management |
| Azure Monitor | - | Observability |
| Microsoft Fabric | F64 | Consolidated analytics |

---

*Document Version: 1.0*
*Last Updated: February 1, 2026*
*Author: Zava Tax Engineering Team*
