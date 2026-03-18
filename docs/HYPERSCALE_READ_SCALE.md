# Azure SQL Hyperscale Read-Scale Configuration

This document describes the connection string configuration for Azure SQL Database Hyperscale read-scale out architecture, implementing the **CQRS (Command Query Responsibility Segregation)** pattern using Data API Builder's multi-data-source feature.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           DAB CQRS Configuration                             │
│              (dab-config.json + data-source-files)                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌────────────────────┐  ┌────────────────────┐  ┌────────────────────┐   │
│  │  WRITE Config      │  │  READ Config       │  │  ANALYTICS Config  │   │
│  │  (dab-config.json) │  │(dab-config.replica) │  │(dab-config.analytics)│  │
│  ├────────────────────┤  ├────────────────────┤  ├────────────────────┤   │
│  │                    │  │                    │  │                    │   │
│  │ POST /customers    │  │ GET /customers     │  │ GET /analytics/*   │   │
│  │ PUT /returns       │  │ GET /returns       │  │ GET /htap-demo     │   │
│  │ DELETE /documents  │  │ GET /professionals │  │ Stored Procedures  │   │
│  │                    │  │ GET /branches      │  │                    │   │
│  └─────────┬──────────┘  └─────────┬──────────┘  └─────────┬──────────┘   │
│            │                       │                       │              │
│            ▼                       ▼                       ▼              │
│  ┌────────────────────┐  ┌────────────────────┐  ┌────────────────────┐   │
│  │ PRIMARY            │  │ READONLY           │  │ ANALYTICS          │   │
│  │ Connection String  │  │ Connection String  │  │ Connection String  │   │
│  │                    │  │ ApplicationIntent  │  │ Named Replica      │   │
│  │                    │  │ = ReadOnly         │  │ Server             │   │
│  └─────────┬──────────┘  └─────────┬──────────┘  └─────────┬──────────┘   │
│            │                       │                       │              │
└────────────┼───────────────────────┼───────────────────────┼──────────────┘
             │                       │                       │
             ▼                       ▼                       ▼
┌────────────────────┐  ┌────────────────────┐  ┌────────────────────┐
│  Azure SQL         │  │  Azure SQL         │  │  Azure SQL         │
│  Hyperscale        │  │  Hyperscale        │  │  Hyperscale        │
│  PRIMARY           │  │  HA READ REPLICA   │  │  NAMED REPLICA     │
│  (Read/Write)      │  │  (Read-Only)       │  │  (Analytics)       │
└────────────────────┘  └────────────────────┘  └────────────────────┘
```

## Connection String Strategy

ZavaTax uses three types of database connections to maximize performance and leverage Hyperscale capabilities:

### 1. Primary (Read/Write)
All transactional operations (INSERT, UPDATE, DELETE) and reads requiring consistency.

```
Server=tcp:<your-sql-server>.database.windows.net,1433;
Database=zavataxdb;
Authentication=Active Directory Managed Identity;
User Id=<managed-identity-client-id>;
Encrypt=True;
TrustServerCertificate=False;
```

### 2. Read-Only Replica (ApplicationIntent=ReadOnly)
For tax filer/professional read operations - uses Hyperscale's built-in HA replica.

```
Server=tcp:<your-sql-server>.database.windows.net,1433;
Database=zavataxdb;
Authentication=Active Directory Managed Identity;
User Id=<managed-identity-client-id>;
ApplicationIntent=ReadOnly;
Encrypt=True;
TrustServerCertificate=False;
```

### 3. Named Replica (Management Analytics)
Dedicated Hyperscale named replica for heavy management queries (executive dashboards, DevOps).

```
Server=tcp:<your-sql-server>-analytics.database.windows.net,1433;
Database=zavataxdb;
Authentication=Active Directory Managed Identity;
User Id=<managed-identity-client-id>;
ApplicationIntent=ReadOnly;
Encrypt=True;
TrustServerCertificate=False;
```

## Workload Routing Matrix

| User Role | Operation | Replica Target | Connection String |
|-----------|-----------|----------------|-------------------|
| Tax Filer | View returns | Read-Only | `ApplicationIntent=ReadOnly` |
| Tax Filer | AI assistant query | Read-Only | `ApplicationIntent=ReadOnly` |
| Tax Professional | View client data | Read-Only | `ApplicationIntent=ReadOnly` |
| Tax Professional | Create/update return | Primary | Standard |
| Tax Professional | Vector search | Read-Only | `ApplicationIntent=ReadOnly` |
| Branch Manager | View analytics | Named Replica | Analytics server |
| Executive | Dashboard queries | Named Replica | Analytics server |
| DevOps | Monitoring queries | Named Replica | Analytics server |

## DAB CQRS Configuration Files

The CQRS pattern is implemented using DAB's multi-data-source feature:

### Main Configuration: `dab-config.json`

```json
{
  "data-source-files": [
    "dab-config.replica.json",    // Queries → ReadOnly Replica
    "dab-config.analytics.json"   // Analytics → Named Replica
  ],
  "runtime": { ... }
}
```

### Write Configuration: `dab-config.json` (Main File)

- **Connection**: `DATABASE_CONNECTION_STRING` (Primary replica)
- **HTTP Methods**: GET, POST, PUT, PATCH, DELETE
- **Entities**: `Branch`, `Customer`, `Professional`, etc.
- **Use Case**: All transactional/mutating operations and default reads

### Read Configuration: `dab-config.replica.json`

- **Connection**: `DATABASE_CONNECTION_STRING_READONLY` (HA replica with `ApplicationIntent=ReadOnly`)
- **HTTP Methods**: GET only  
- **Entities**: `BranchRead`, `CustomerRead`, `ProfessionalRead`, etc.
- **Use Case**: Tax filer/professional read queries, vector searches

### Analytics Configuration: `dab-config.analytics.json`

- **Connection**: `DATABASE_CONNECTION_STRING_ANALYTICS` (Named replica endpoint)
- **HTTP Methods**: GET, POST (for stored procedures)
- **Entities**: Views (`vw_BranchPerformance`, `vw_ExecutiveDashboard`), Stored Procedures (`sp_HTAPDemoQuery`)
- **Use Case**: Executive dashboards, DevOps monitoring, HTAP demo

## Environment Variables

Set these environment variables for the DAB/API layer:

```bash
# Primary - Read/Write
DATABASE_CONNECTION_STRING="Server=tcp:<your-sql-server>.database.windows.net,1433;Database=zavataxdb;Authentication=Active Directory Managed Identity;User Id=${MANAGED_IDENTITY_CLIENT_ID};Encrypt=True;"

# Read-Only Replica - Tax Filer/Professional reads
DATABASE_CONNECTION_STRING_READONLY="Server=tcp:<your-sql-server>.database.windows.net,1433;Database=zavataxdb;Authentication=Active Directory Managed Identity;User Id=${MANAGED_IDENTITY_CLIENT_ID};ApplicationIntent=ReadOnly;Encrypt=True;"

# Named Replica - Management Analytics
DATABASE_CONNECTION_STRING_ANALYTICS="Server=tcp:<your-sql-server>-analytics.database.windows.net,1433;Database=zavataxdb;Authentication=Active Directory Managed Identity;User Id=${MANAGED_IDENTITY_CLIENT_ID};ApplicationIntent=ReadOnly;Encrypt=True;"
```

## Running DAB with CQRS Configuration

To start DAB with the CQRS multi-data-source configuration:

```bash
# Production with CQRS
dab start --config dab-config.json
```

## API Endpoint Mapping

| Operation | REST Endpoint | GraphQL | Source File |
|-----------|--------------|---------|-------------|
| Create Customer | `POST /api/customers` | `mutation { createCustomer }` | dab-config.json |
| Get Customer (Read Replica) | `GET /api/customers-read/:id` | `query { customerReadById }` | dab-config.replica.json |
| Get Branch Analytics | `GET /api/analytics-branch` | `query { branchAnalytics }` | dab-config.analytics.json |

## API Headers

The frontend sends these headers to indicate workload routing:

- `X-Workload-Type`: The type of workload (transactional, tax-filer-readonly, analytics, etc.)
- `X-Replica-Target`: The target replica (primary, readonly-replica, named-replica)

The backend/middleware uses these headers to select the appropriate connection string.

## Azure Deployment Configuration

The `deploy.ps1` PowerShell script (using Azure CLI) creates:
1. Primary Hyperscale database (configurable SKU, default `HS_PRMS_4`)
2. Named replicas for analytics and RAG workloads
3. Connection strings with appropriate `ApplicationIntent` settings
4. Managed Identity for passwordless authentication

## Local Development

For local development with SQL Express, read-scale is simulated but all queries go to the same instance:

```
Server=.\\SQLEXPRESS;Database=ZavaTax;Trusted_Connection=True;TrustServerCertificate=True;
```

The workload routing headers are still sent for observability/logging purposes.

## Benefits

1. **Offload read workloads** - Tax filer views don't impact write performance
2. **Isolate analytics** - Heavy management queries on named replica
3. **Near-zero lag** - Hyperscale replicas typically < 5 second replication lag
4. **Cost optimization** - Named replica can use different compute size
5. **HTAP support** - Columnstore indexes on replicas for real-time analytics

## Video Reference

This implementation follows the approach demonstrated in the official DAB documentation video:
[DAB and the CQRS pattern](https://youtu.be/pSuMIvXRM1Q)

Key concepts from the video:
- Use `data-source-files` array to define multiple data sources
- Each child config has its own `data-source` with unique connection string
- Entity names must be globally unique across all config files
- Only top-level file controls runtime settings (CORS, auth, etc.)
