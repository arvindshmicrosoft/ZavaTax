# ZavaTax Azure Deployment Guide

This guide walks you through deploying the ZavaTax application to Azure using the automated PowerShell deployment script.

## 📋 Prerequisites

### Required Tools
- **Azure CLI** (v2.50+): [Install Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli)
- **PowerShell 7+**: [Install PowerShell](https://docs.microsoft.com/powershell/scripting/install/installing-powershell)
- **Node.js 22+**: [Install Node.js](https://nodejs.org/)
- **sqlcmd**: [Install sqlcmd](https://aka.ms/sqlcmd)

### Azure Requirements
- An active Azure subscription
- Permissions to create resources (Contributor role or higher)
- Microsoft Entra ID permissions to create SQL DB users

### Setup Prerequisites

```powershell
# Login to Azure
az login

# Verify your subscription
az account show
```

## 🏗️ Architecture Overview

The deployment creates the following Azure resources:

```
┌─────────────────────────────────────────────────────────────────┐
│                        Azure Resource Group                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────┐     ┌──────────────────┐                  │
│  │   App Service    │     │   App Service    │                  │
│  │   (React SPA)    │────▶│   (DAB API)      │                  │
│  └──────────────────┘     └────────┬─────────┘                  │
│                                    │                             │
│                                    │ Managed Identity            │
│                                    ▼                             │
│  ┌──────────────────┐     ┌──────────────────────────────────┐  │
│  │  User-Assigned   │     │   Azure SQL Hyperscale           │  │
│  │ Managed Identity │────▶│   • Zone Redundant               │  │
│  └──────────────────┘     │   • GZRS Backup Storage          │  │
│                           │   • 1 HA Replica                  │  │
│                           │   • Read Scale-Out Enabled        │  │
│                           └──────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────┐     ┌──────────────────┐                  │
│  │  Azure Container │     │  Storage Account │                  │
│  │  Registry (ACR)  │     │  (Documents)     │                  │
│  └──────────────────┘     └──────────────────┘                  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Security Features

- **Entra-only Authentication**: SQL Server uses Microsoft Entra ID exclusively (no SQL passwords)
- **User-Assigned Managed Identity**: Keyless authentication between services
- **DAB Simulator Mode**: Demo mode with X-MS-API-ROLE header authentication
- **HTTPS Only**: All web traffic encrypted

## 🚀 Quick Start Deployment

```powershell
# Navigate to the deploy folder
cd deploy/azure

# Run the deployment script (demo mode with Simulator auth)
.\deploy.ps1 -Environment dev -Location eastus2

# Or with custom settings
.\deploy.ps1 -Environment dev -Location eastus2 -SqlDatabaseSku HS_PRMS_8
```

## 📝 Deployment Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Environment` | `dev` | Target environment (dev, staging, prod) |
| `-Location` | `eastus2` | Azure region |
| `-BaseName` | `zavatax` | Base name for resources |
| `-ResourceGroupName` | Auto-generated | Resource group name |
| `-AppServiceSku` | `B2` | App Service Plan tier |
| `-SqlDatabaseSku` | `HS_PRMS_4` | Hyperscale SKU (HS_PRMS_2 through HS_PRMS_64) |
| `-SkipInfrastructure` | `false` | Skip Azure resource creation |
| `-SkipDatabase` | `false` | Skip DB schema setup |
| `-SkipWebApp` | `false` | Skip app deployment |

### SQL Database SKU Options

All SKUs are Hyperscale Premium-series with:
- Zone redundancy (where the region supports availability zones; auto-detected)
- GZRS or Geo backup storage (based on zone support)
- 1 HA replica for automatic failover
- Read scale-out enabled

| SKU | vCores | Use Case |
|-----|--------|----------|
| `HS_PRMS_2` | 2 | Development/Testing |
| `HS_PRMS_4` | 4 | Demo/Light Production |
| `HS_PRMS_8` | 8 | Production |
| `HS_PRMS_16` | 16 | High-Performance |

## 🔧 Step-by-Step Deployment

### Step 1: Clone and Prepare

```powershell
git clone <your-repo-url>
cd ZavaTax
```

### Step 2: Run Deployment

```powershell
.\deploy\azure\deploy.ps1 -Environment dev

# The script will automatically:
# - Create all Azure resources
# - Configure Entra-only SQL authentication
# - Deploy the schema
# - Build and deploy the web app
# - Configure DAB with ACR
```

### Step 3: Verify Deployment

After deployment, the script outputs the URLs:

```
═══════════════════════════════════════════════════════════════════
  DEPLOYMENT COMPLETE
═══════════════════════════════════════════════════════════════════
  Web App:  https://zavatax-dev-web-xxxxx.azurewebsites.net
  DAB API:  https://zavatax-dev-dab-xxxxx.azurewebsites.net
  SQL:      zavatax-dev-sql-xxxxx.database.windows.net
═══════════════════════════════════════════════════════════════════
```

## 📊 Post-Deployment Tasks

### Auto-Generated `.env`

The deployment script auto-generates `data-prep/.env` with actual Azure resource names
(OpenAI endpoint, SQL server, storage account, managed identity, etc.).
All data-prep scripts read from this file automatically — no manual configuration needed.

### Prepare and Load Sample Data

```powershell
# Step 1: Prepare sample data (skip if data-prep/data/output already has CSV files)
cd data-prep
.\run_all.ps1
# (see data-prep/README.md for individual steps and customization)

# Step 2: Upload to blob storage
az storage blob upload-batch --account-name <from-.env> --destination csvdata --source ./data/output --auth-mode login

# Step 3: Load to Azure SQL (reads all args from .env)
python 07_load_to_azure_sql.py

# Step 4 (optional): Generate filing detail records (~300GB)
cd ..
sqlcmd -S <sql-server-from-.env> -d zavataxdb -G -i database/08_generate_filing_details.sql
```

### Deploy Azure OpenAI (Optional)

For AI-powered vector search and RAG features:

```powershell
# Deploy OpenAI models and configure SQL AI stored procedures
.\deploy.ps1 -DeployOpenAI -SkipInfrastructure
```

This automatically:
1. Creates an Azure OpenAI resource with `text-embedding-3-small` and a chat model
2. Runs `05_setup_azure_openai_endpoint.sql` to create the external model and AI stored procedures
3. Restarts DAB to pick up the new stored procedures

> **Note:** When using `-DeployOpenAI` during a full deployment, the script handles all of this automatically.

## 🔄 Updating the Deployment

### Do you need deploy-app.ps1?

**Yes, if you want a fast, app-only publish.** The main [deploy.ps1](deploy.ps1) script can deploy everything or just the web app, but it also re-validates all prerequisites and expects the full deployment context. The [deploy-app.ps1](deploy-app.ps1) script is a lightweight, **web-app-only** deploy that is ideal for rapid iterations when infrastructure already exists.

### Redeploy Web App Only

```powershell
.\deploy.ps1 -Environment dev -SkipInfrastructure -SkipDatabase
```

### Web App Incremental Publish (recommended for UI-only changes)

```powershell
cd deploy/azure
./deploy-app.ps1 -ResourceGroupName <your-resource-group> -WebAppName <your-web-app-name> -ApiBaseUrl https://<your-dab-app>.azurewebsites.net
```

Use this when you change:
- React UI code in webapp/src
- Frontend configuration (Vite envs)
- Static assets

### Redeploy DAB Container

```powershell
# Rebuild DAB image with latest config
cd webapp
az acr build --registry <your-acr-name> --image dab:latest --file Dockerfile.dab .
az webapp restart --name zavatax-dev-dab-xxxxx --resource-group <your-resource-group>
```

### DAB Config Incremental Publish (dab-config*.json changes)

The DAB configuration is baked into the container image in [webapp/Dockerfile.dab](../webapp/Dockerfile.dab). When you change any DAB config file (for example dab-config.json, dab-config.replica.json, dab-config.analytics.json):

1. Rebuild and push the DAB container image:
  ```powershell
  cd webapp
  az acr build --registry <your-acr-name> --image dab:latest --file Dockerfile.dab .
  ```
2. Restart the DAB App Service:
  ```powershell
  az webapp restart --name <your-dab-app-name> --resource-group <your-resource-group>
  ```

If you only changed DAB config, **no web app rebuild is required**.

### Update Database Schema

Run scripts in order:

```powershell
# 1. Schema first (tables, views, basic stored procs)
sqlcmd -S zavatax-dev-sql-xxxxx.database.windows.net -d zavataxdb -G `
    -i database/01_create_schema.sql

# 2. OLTP stored procedures
sqlcmd -S zavatax-dev-sql-xxxxx.database.windows.net -d zavataxdb -G `
    -i database/06_oltp_procedures.sql

# 3. Azure OpenAI endpoint + AI stored procs (requires OpenAI resource)
sqlcmd -S zavatax-dev-sql-xxxxx.database.windows.net -d zavataxdb -G `
    -i database/05_setup_azure_openai_endpoint.sql
```

## 🧹 Cleanup

To delete all resources:

```powershell
# Delete the entire resource group
az group delete --name <your-resource-group> --yes --no-wait
```

## 📁 Files

| File | Description |
|------|-------------|
| [deploy.ps1](deploy.ps1) | Main deployment script using Azure CLI |
| [deploy-app.ps1](deploy-app.ps1) | App-only deployment (fast publish for UI changes) |

## 🔍 Troubleshooting

### "Subscription does not allow shared key access"

This error occurs when trying to use Azure Files. The script uses ACR to bake the DAB config into the container image instead.

### DAB container won't start

Check the container logs:
```powershell
az webapp log tail --name zavatax-dev-dab-xxxxx --resource-group <your-resource-group>
```

Common issues:
- Port mismatch: Ensure `WEBSITES_PORT=5000` is set
- Config syntax error: Validate `dab-config.json`

### CORS errors in browser

The DAB config must allow the web app origin. Check `dab-config.json`:
```json
"cors": {
  "origins": ["*"],
  "allow-credentials": false
}
```

### SQL connection failures

Verify the managed identity has access:
```sql
SELECT name, type_desc FROM sys.database_principals WHERE name LIKE '<your-prefix>%';
```
