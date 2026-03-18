# Load Simulator Deployment Guide

## Overview

This guide covers deploying the ZavaTax load simulator to Azure Container Apps. For general usage and local execution, see [README.md](README.md).

## Prerequisites

**For All Deployments:**
- Azure subscription with access to create resources
- Azure CLI installed and logged in (`az login`)
- Azure SQL Database with ZavaTax schema deployed
- PowerShell 7+

**For Local Execution:**
- Python 3.10+, packages: `pip install -r requirements.txt`
- That's it! See [README.md](README.md) for usage examples

**For Container Deployment:**
- Azure Container Registry (ACR) with push permissions
- Docker installed for building container images

## Deployment Options

### Option 1: Local Execution (No Deployment Needed)

```powershell
# Setup environment (one-time)
.\infrastructure\deploy.ps1 -SqlServer myserver.database.windows.net -LocalOnly

# Then run tests directly (see README.md for all options)
python -m oltp.main -s myserver.database.windows.net -d zavatax -w 10 -b 1000 -d 300
python -m analytics.main -s myserver-replica.database.windows.net -d zavatax -c 10 -d 300
```

**For detailed usage examples, command-line options, and monitoring, see [README.md](README.md).**

---

### Option 2: Azure Container Apps Deployment

**Best for:** High throughput testing (100+ MB/s), scale-out scenarios, production load testing

```powershell
# Full deployment (creates all infrastructure)
.\infrastructure\deploy.ps1 `
    -SqlServer myserver.database.windows.net `
    -AcrName myacr `
    -ResourceGroup zavatax-load-rg `
    -Location eastus `
    -Replicas 3 `
    -Mode oltp
```

**Parameters:**
- **SqlServer** (Required): Azure SQL server name (e.g., `myserver.database.windows.net`)
- **AcrName** (Required for Azure): Azure Container Registry name
- **ResourceGroup** (Optional): Resource group name (default: `zavatax-load-simulator-rg`)
- **Location** (Optional): Azure region (default: `eastus`)
- **Replicas** (Optional): Number of container instances (default: `1`)
- **Mode** (Optional): Test mode - `oltp` or `analytics` (default: `oltp`)
- **NumWorkers** (OLTP only): Number of worker threads per instance (default: `10`)
- **BatchSize** (OLTP only): Batch size for inserts (default: `1000`)
- **Connections** (Analytics only): Number of concurrent connections (default: `10`)
- **Duration** (Optional): Test duration in seconds (default: `300`)

**What gets created:**
1. **Resource Group** - Container for all resources
2. **Azure Container Registry** - Stores container image
3. **Managed Identity** - For SQL authentication (no passwords!)
4. **Container Apps Environment** - Hosting environment for containers
5. **Container App** - Running load test instances

**Authentication:** Containers use managed identity to authenticate to Azure SQL. No passwords stored!

---

### Option 3: Update Existing Deployment

If you already deployed and want to update the container image or configuration:

```powershell
# Update existing deployment (rebuilds image, updates container)
.\infrastructure\deploy.ps1 `
    -SqlServer myserver.database.windows.net `
    -AcrName myacr `
    -ResourceGroup zavatax-load-rg `
    -Replicas 5
```

The script automatically detects existing resources and updates them.

---

## Post-Deployment Steps (Azure Container Apps)

After deploying to Azure, you need to grant the managed identity SQL permissions:

```sql
-- Connect to your Azure SQL Database (myserver.database.windows.net/zavatax)

-- Create database user for the managed identity
CREATE USER [zavatax-load-simulator-identity] FROM EXTERNAL PROVIDER;

-- Grant necessary permissions
ALTER ROLE db_datawriter ADD MEMBER [zavatax-load-simulator-identity];
ALTER ROLE db_datareader ADD MEMBER [zavatax-load-simulator-identity];
GRANT EXECUTE ON SCHEMA::dbo TO [zavatax-load-simulator-identity];

-- If using analytics queries with specific procedures
GRANT EXECUTE ON OBJECT::dbo.GetBranchPerformanceMetrics TO [zavatax-load-simulator-identity];
GRANT EXECUTE ON OBJECT::dbo.GetRegionalRevenueAnalysis TO [zavatax-load-simulator-identity];
```

**Note:** The deployment script outputs the exact SQL command you need to run!

---

## Monitoring Container Deployments

**View container logs:**
```powershell
az containerapp logs show `
    --name zavatax-load-simulator `
    --resource-group zavatax-load-rg `
    --follow
```

**View metrics in Azure Portal:**
- Navigate to Container App → Metrics
- Monitor: CPU percentage, Memory usage, Replica count

**Note:** For detailed metrics information (console output, Azure SQL metrics), see [README.md](README.md#monitoring).

---

## Troubleshooting Deployments

**Error: "Push to ACR failed"**
```powershell
# Login to ACR
az acr login --name myacr

# Verify ACR exists
az acr show --name myacr --resource-group myRG
```

**Error: "Container fails to start"**
```powershell
# Check container logs
az containerapp logs show `
    --name zavatax-load-simulator `
    --resource-group zavatax-load-rg `
    --follow

# Common issues:
# - Managed identity not granted SQL permissions (see Post-Deployment Steps)
# - SQL_SERVER or SQL_DATABASE incorrect
# - Container image build failed (check Docker build logs)
```

**Error: "Container runs but no load detected"**
- Check SQL_SERVER environment variable is correct
- Verify managed identity has SQL permissions (see Post-Deployment Steps)
- Check container logs for authentication errors

---

## Resource Cleanup

**Stop local test:** Press `Ctrl+C`

**Delete Azure resources:**
```powershell
az group delete --name zavatax-load-rg --yes --no-wait
```

---

## Deployment Examples

**High-throughput OLTP (10 replicas):**
```powershell
.\infrastructure\deploy.ps1 `
    -SqlServer myserver.database.windows.net `
    -AcrName myacr `
    -Replicas 10 `
    -NumWorkers 20 `
    -BatchSize 2000
```

**Analytics on named replica:**
```powershell
.\infrastructure\deploy.ps1 `
    -SqlServer myserver-replica.database.windows.net `
    -AcrName myacr `
    -Mode analytics `
    -Connections 50
```

---

## Architecture

**Container Apps Execution:**
```
[Azure Container Apps]
    ├─ Container App (1-N replicas)
    │   ├─ Python Process (OLTP or Analytics)
    │   ├─ Managed Identity (passwordless auth)
    │   └─ mssql-python driver
    │
    └─→ [Azure SQL Database]
           └─ ZavaTax schema
```

**What gets created:**
- Resource Group
- Azure Container Registry (stores image)
- Managed Identity (for SQL auth)
- Container Apps Environment
- Container App (running test instances)

---

## Next Steps

1. Review [README.md](README.md) for comprehensive usage guide
2. Start with local execution for testing
3. Deploy to Azure Container Apps when ready for high-scale testing (100+ MB/s)

---

**Last Updated:** February 2026
