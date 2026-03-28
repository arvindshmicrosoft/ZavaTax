# Zava Tax - AI-Powered Tax Preparation Demo

A full-stack demo showcasing SQL Server 2025 / Azure SQL DB Hyperscale features including:
- **Vector Search** with native VECTOR type and DiskANN indexes
- **Columnstore Indexes** for real-time analytics
- **Data API Builder** for instant REST/GraphQL APIs
- **Azure OpenAI Integration** for embeddings and AI assistance

## ⚠️ Important Disclaimer (Not Production-Ready)

This repository is a **demo and educational sample only**. It is **not production-ready** and **must not** be used for real-world tax preparation or any regulated workload. It has not been hardened for security, privacy, compliance, reliability, or cost controls. Use it only in isolated, non-production environments.

### 📜 IRS Content Disclaimer

> Content in this repository is for **demonstration purposes only**. Neither this demonstration application nor Microsoft is **affiliated with or endorsed by the Internal Revenue Service (IRS)**, the U.S. Department of the Treasury, or any U.S. government agency. IRS publications are **U.S. Government Works** ([17 U.S.C. § 105](https://www.law.cornell.edu/uscode/text/17/105)) and may be freely used per [Use of Content from IRS.gov](https://www.irs.gov/about-irs/use-of-content-from-irsgov). All customer data is synthetic. **No part of this repository should be construed as tax advice.**

### 🔒 Security Notice

**This demo uses simplified mock authentication for ease of demonstration.** There is no password validation, no JWT token verification, and no authorization enforcement. This is intentional to allow quick setup and persona switching during demos.

> **⚠️ DAB Anonymous Access:** Data API Builder is configured with `"provider": "Simulator"` and all entities use `"role": "anonymous"` with full CRUD permissions. This means **anyone who can reach the DAB endpoint can read, create, update, or delete any data without authentication.** In production, replace the Simulator provider with Azure AD/Entra ID and enforce role-based permissions. See [SECURITY.md](SECURITY.md) and [dab-config.production.json](webapp/dab-config.production.json) for the secured configuration.

**📖 For production implementation guidance, see [SECURITY.md](SECURITY.md)** which provides:
- Detailed explanation of current demo security trade-offs
- Step-by-step Azure AD B2C setup guide
- Token storage best practices
- Claims-based authorization configuration
- Complete production deployment checklist

## Prerequisites

Before getting started, ensure you have:

| Tool | Version | Installation |
|------|---------|--------------|
| **Node.js** | 18+ | [nodejs.org](https://nodejs.org/) |
| **Python** | 3.10+ | [python.org](https://www.python.org/) |
| **.NET SDK** | 8.0+ | [dotnet.microsoft.com](https://dotnet.microsoft.com/download) |
| **SQL Server** | 2025 Express or LocalDB | [SQL Server Downloads](https://www.microsoft.com/sql-server/sql-server-downloads) |

### Install Data API Builder CLI

Data API Builder (DAB) is required to run the backend API:

```powershell
# Install as a global .NET tool
dotnet tool install -g Microsoft.DataApiBuilder

# Verify installation
dab --version

# If already installed, update to latest
dotnet tool update -g Microsoft.DataApiBuilder
```

## Quick Start (Local Development)

### 1. Prepare the Data

```powershell
cd data-prep

# Create virtual environment
python -m venv venv
.\venv\Scripts\Activate.ps1

# Install dependencies
pip install -r requirements.txt

# Configure Azure OpenAI (copy and edit .env)
# Note: If deploying to Azure via deploy.ps1, this is auto-generated — skip this step
Copy-Item .env.template .env
notepad .env

# Run the data pipeline
.\run_all.ps1
```

See [data-prep/README.md](data-prep/README.md) for details.

### 2. Set Up the Database

```powershell
# Create database and schema (SQL Server 2025 Express)
sqlcmd -S ".\SQLEXPRESS" -i "database/scripts/local_dev_setup.sql"

# Load the prepared data
cd data-prep
python 07_load_to_sqlexpress.py

# Deploy OLTP workflow stored procedures
# Required for New Return wizard, load simulator, and return submission
cd ..
sqlcmd -S ".\SQLEXPRESS" -d ZavaTax -i "database/06_oltp_procedures.sql"

# Deploy security features (Ledger table, RLS, DDM, classification)
# Required for Security Dashboard page and AI interaction audit logging
sqlcmd -S ".\SQLEXPRESS" -d ZavaTax -i "database/10_security_features.sql"
```

### 3. Enable Azure OpenAI Vector Search (Optional but Recommended)

For true semantic/vector search, configure Azure OpenAI:

```powershell
# Edit the setup script with your Azure OpenAI API key
notepad database/scripts/setup_openai_local.sql
# Update line 57: Replace YOUR_AZURE_OPENAI_API_KEY with your actual key

# Run the setup script (enables REST endpoint and creates procedures)
sqlcmd -S ".\SQLEXPRESS" -i "database/scripts/setup_openai_local.sql"

# Re-run local_dev_setup to update AskTaxQuestion procedure
sqlcmd -S ".\SQLEXPRESS" -d ZavaTax -i "database/scripts/local_dev_setup.sql"
```

**Note:** Without Azure OpenAI configured, knowledge base search falls back to keyword matching.

See [database/README.md](database/README.md) for Azure SQL DB setup.

### 4. Start the Application

```powershell
cd webapp

# Install dependencies
npm install

# Start Data API Builder (backend)
dab start --config dab-config.json

# In a new terminal, start the frontend
npm run dev
```

Open http://localhost:5173 and click "Sign in" to enter dev mode.

See [webapp/README.md](webapp/README.md) for full documentation.

## Incremental Deployment Updates (Azure)

For incremental publish steps after the initial deployment (web app updates and DAB config changes), see [deploy/azure/README.md](deploy/azure/README.md).

## Project Structure

```
ZavaTax/
├── data-prep/          # Data preparation scripts
│   ├── 01-06 scripts   # Download, parse, embed, generate
│   ├── 07_load_to_azure_sql.py # Load to Azure SQL (from blob)
│   └── 07_load_to_sqlexpress.py # Load to local SQL Express
│
├── database/           # SQL scripts
│   ├── 01_create_schema.sql     # Tables, views, indexes, stored procs
│   ├── 06_oltp_procedures.sql   # OLTP workflow stored procedures
│   ├── 08_generate_filing_details.sql  # Bulk generation of P0+P1 data
│   ├── 09_ncci_analytics_migration.sql # NCCI analytics migration
│   ├── 10_security_features.sql # Security audit & monitoring procs
│   └── scripts/                 # Local dev setup, OpenAI config
│
├── webapp/             # React frontend + DAB config
│   ├── src/            # React application
│   └── dab-config.*.json  # API configuration (primary, replica, analytics)
│
├── load-simulator/     # OLTP + analytics load testing tools
└── docs/               # Architecture and design documentation
```

## Features by Persona

| Persona | Features |
|---------|----------|
| **Tax Filer** | AI Q&A, return status tracking |
| **Tax Professional** | Client management, similar case search, knowledge base |
| **Branch Manager** | Team performance, real-time branch metrics |
| **Executive** | Company-wide dashboards and analytics |
| **DevOps** | System metrics and performance monitoring |

## Key Technologies

- **Frontend**: React 18, TypeScript, Vite, TailwindCSS, TanStack Query
- **Backend**: Data API Builder (REST + GraphQL)
- **Database**: SQL Server 2025 / Azure SQL DB Hyperscale (partitioned, ~300 GB with filing details)
- **AI**: Azure OpenAI (text-embedding-3-small for embeddings, GPT-5.2 for chat)
- **Auth**: MSAL.js / Entra ID (production), Simulator (local dev) - See [SECURITY.md](SECURITY.md)

## Key Dependencies (Selected)

**Frontend**
- React (`react`, `react-dom`)
- Routing (`react-router-dom`)
- Data fetching (`@tanstack/react-query`)
- Charts (`chart.js`, `react-chartjs-2`)
- UI icons (`lucide-react`)
- Markdown rendering (`react-markdown`)

**Backend / API**
- Data API Builder (DAB) CLI (.NET tool)
- Azure identity/auth (`@azure/identity`, `@azure/msal-browser`, `@azure/msal-react`)

**Data Prep / Load Simulator**
- HTTP + parsing (`requests`, `beautifulsoup4`, `lxml`)
- Data processing (`pandas`, `numpy`)
- Azure auth (`azure-identity`)
- SQL connectivity (`mssql-python`)
- JSON + perf (`orjson`)
- Async + retry (`aiohttp`, `tenacity`)

## Troubleshooting

### "dab: command not found"
Install Data API Builder:
```powershell
dotnet tool install -g Microsoft.DataApiBuilder
```

### Vector search not working
SQL Server 2025 requires preview features enabled:
```sql
ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;
```

### Connection refused on localhost:5000
Ensure DAB is running: `dab start --config dab-config.json`

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on how to get involved.

This project has adopted a Code of Conduct based on the [Contributor Covenant](https://www.contributor-covenant.org/). Please see [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for details. By participating, you are expected to uphold this code.

## License

This project's source code is released under the [MIT License](LICENSE).

**IRS content** (publications and form instructions) included or downloaded by this project is in the **public domain** as a U.S. Government Work under [17 U.S.C. § 105](https://www.law.cornell.edu/uscode/text/17/105) and is used in accordance with [Use of Content from IRS.gov](https://www.irs.gov/about-irs/use-of-content-from-irsgov). No copyright is claimed over that content.

All other trademarks, service marks, and trade names referenced herein are the property of their respective owners.
