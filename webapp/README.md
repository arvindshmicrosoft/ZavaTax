# Zava Tax Web Application

A modern React web application for professional tax preparation services.

## Quick Start (Local Development)

For the fastest local development experience, use SQL Express or LocalDB:

### 1. Set Up Local Database

```bash
# Using SQL Server Management Studio or sqlcmd, run:
sqlcmd -S "(localdb)\MSSQLLocalDB" -i ../database/scripts/local_dev_setup.sql

# Or for SQL Express:
sqlcmd -S "localhost\SQLEXPRESS" -i ../database/scripts/local_dev_setup.sql
```

### 2. Install Dependencies

```bash
npm install
```

### 3. Configure Environment

The `.env.development` file is pre-configured for local dev mode. Just create a `.env.local` file if you need to override any settings.

### 4. Start Data API Builder

```bash
# Set connection string (LocalDB)
$env:SQL_CONNECTION_STRING="Server=(localdb)\MSSQLLocalDB;Database=ZavaTax;Integrated Security=True;TrustServerCertificate=True;"

# Or for SQL Express
$env:SQL_CONNECTION_STRING="Server=localhost\SQLEXPRESS;Database=ZavaTax;Trusted_Connection=True;TrustServerCertificate=True;"

# Start DAB with local config (Simulator auth - no Azure AD needed)
# ⚠️ WARNING: This runs DAB with anonymous access — all data is readable/writable
#    without authentication. Do NOT expose this endpoint to untrusted networks.
dab start --config dab-config.json
```

### 5. Start the App

```bash
npm run dev
```

Visit `http://localhost:5173` and click "Sign in" to enter dev mode (no real auth required).

---

## Production Setup

For production deployment with Azure SQL DB Hyperscale and Azure AD authentication:

## Features

- **AI-Powered Tax Assistant** - RAG-based assistant using vector search + LLM for contextual tax guidance
- **Smart Case Search** - Find similar tax scenarios using vector embeddings
- **Real-Time Analytics** - Branch and company-wide dashboards
- **Role-Based Access** - Different views for different user types

## Key Dependencies

| Package | Purpose |
|---------|---------|
| `react-markdown` | Render markdown responses from AI assistant |
| `@tailwindcss/typography` | Styled prose for markdown content |
| `@tanstack/react-query` | Server state management and caching |
| `lucide-react` | Icons |
| `chart.js` / `react-chartjs-2` | Analytics charts |
| `@azure/msal-browser` | Azure AD authentication |

## Personas

The app supports five user personas:

| Persona | Features |
|---------|----------|
| **Tax Filer** | AI Q&A, return status tracking |
| **Tax Professional** | Client management, similar case search, knowledge base |
| **Branch Manager** | Team performance, real-time branch metrics |
| **Executive** | Company-wide dashboards and analytics |
| **DevOps** | System metrics and performance monitoring |

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────────────┐
│  React SPA      │────▶│  Data API        │────▶│  SQL Database           │
│  (Vite + TS)    │     │  Builder (DAB)   │     │  (Local or Azure)       │
│                 │     │                  │     │                         │
│  - MSAL Auth    │     │  - REST API      │     │  Local: SQL Express     │
│  - React Query  │     │  - GraphQL       │     │        or LocalDB       │
│  - TailwindCSS  │     │  - Role-based    │     │                         │
│                 │     │    access        │     │  Prod: Azure SQL DB     │
└─────────────────┘     └──────────────────┘     │        Hyperscale       │
                                                 └─────────────────────────┘
```

## Prerequisites

- Node.js 18+
- .NET 8.0 SDK or later
- SQL Server LocalDB, SQL Express 2025, or Azure SQL DB
- Data API Builder CLI (see installation below)
- (Production only) Azure AD application registration

### Install Data API Builder CLI

```bash
# Install DAB as a global .NET tool
dotnet tool install -g Microsoft.DataApiBuilder

# Verify installation
dab --version
```

If you've already installed it before, update to the latest:
```bash
dotnet tool update -g Microsoft.DataApiBuilder
```

## Production Setup

### 1. Install Dependencies

```bash
cd webapp
npm install
```

### 2. Configure Environment

Copy the environment template and update with your values:

```bash
cp .env.template .env
```

Edit `.env`:
```
VITE_DEV_MODE=false
VITE_AZURE_AD_CLIENT_ID=your-azure-ad-client-id
VITE_AZURE_AD_TENANT_ID=your-azure-ad-tenant-id
VITE_API_BASE_URL=http://localhost:5000
```

### 3. Configure Azure AD

Register an application in Azure AD with:

- **Redirect URI**: `http://localhost:5173` (development)
- **API Permissions**: Add a custom API scope for DAB
- **App Roles**: Create roles for each persona:
  - `TaxFiler`
  - `TaxProfessional`
  - `BranchManager`
  - `Executive`
  - `DevOps`

### 4. Start Data API Builder

Update the connection string in `dab-config.json`, then start DAB:

```bash
# Install DAB CLI if not already installed
dotnet tool install -g Microsoft.DataApiBuilder

# Start DAB
dab start --config dab-config.json
```

### 5. Start Development Server

```bash
npm run dev
```

The app will be available at `http://localhost:5173`

## Data API Builder Configuration

The `dab-config.json` file configures:

### Entities
- **Branch / BranchRead** - Branch locations (primary + read replica)
- **Professional / ProfessionalRead** - Tax professionals
- **Customer / CustomerRead** - Customer records
- **TaxReturn / TaxReturnRead** - Tax return data (primary + read replica)
- **TaxKnowledgeBase / TaxScenario** - Vector search tables
- **W2Document / Form1099 / CapitalGainTransaction** - Income documents
- **FormLineItem / StateTaxReturn / EFileSubmission** - Filing details

### Stored Procedures
- `SearchKnowledgeBase` - Vector similarity search on knowledge base
- `SearchSimilarCases` - Find similar tax scenarios using DiskANN
- `AskTaxQuestion` - Knowledge base Q&A using vector search
- `AskTaxAssistant` - RAG + LLM assistant (vector search + GPT-5.2 chat)
- `GetExecutiveKPIs` / `GetTopBranches` / `GetFilingStatusDistribution` - Executive analytics
- `GetBranchAnalytics` / `GetBranchLeaderboard` - Branch analytics
- `GetHyperscaleResourceStats` - DevOps monitoring DMVs
- `LogAIInteraction` - AI interaction audit ledger

### Views
- `BranchPerformance` - Real-time branch analytics
- `ExecutiveDashboard` - Company-wide metrics

### Role-Based Access
Each role has specific permissions:

| Role | Access |
|------|--------|
| tax-filer | Own returns only |
| tax-professional | Assigned clients |
| branch-manager | Branch data |
| executive | All data (read) |
| devops | System metrics |

## Development

### Project Structure

```
webapp/
├── src/
│   ├── components/       # Shared components
│   │   ├── Layout.tsx    # Main layout with navigation
│   │   └── NewReturnForm.tsx # 6-step tax return wizard
│   ├── lib/
│   │   ├── auth.ts       # MSAL configuration
│   │   ├── api.ts        # DAB API client (~45 methods)
│   │   ├── navigation.ts # Role-based navigation
│   │   └── workloadRouting.ts # CQRS replica routing headers
│   ├── pages/
│   │   ├── LoginPage.tsx
│   │   ├── tax-filer/    # Dashboard, MyReturns, NewReturn, EditReturn, AskQuestion
│   │   ├── professional/ # Dashboard, Clients, SimilarCases, KnowledgeBase
│   │   ├── branch-manager/ # Dashboard, Team, Performance
│   │   ├── executive/    # Dashboard, Analytics, FilingAnalytics
│   │   └── devops/       # Metrics, SecurityDashboard
│   ├── App.tsx           # Main app with routing (17 routes)
│   ├── main.tsx          # Entry point
│   └── index.css         # Tailwind styles
├── dab-config.json       # Data API Builder config (primary)
├── dab-config.replica.json  # Read replica entities
├── dab-config.analytics.json # Analytics stored procedures
├── package.json
└── vite.config.ts
```

### Building for Production

```bash
npm run build
```

Output will be in the `dist/` directory.

### Deploying to Azure Static Web Apps

```bash
# Install SWA CLI
npm install -g @azure/static-web-apps-cli

# Deploy
swa deploy ./dist --env production
```

## Key Features by Page

### Tax Filer Dashboard
- **Ask a Question**: Real-time AI Q&A using vector search + Azure OpenAI
- **My Returns**: View tax return history stored as JSON documents
- **New Return**: 6-step tax return wizard with AI assistant
  - Floating AI panel with maximize/minimize
  - Contextual suggested questions per step
  - Markdown-rendered responses from GPT-5.2

### Professional Workspace  
- **Similar Cases**: DiskANN-powered similarity search across historical returns
- **Knowledge Base**: Semantic search through tax regulations

### Branch Manager Dashboard
- **Team Performance**: Real-time leaderboard using columnstore indexes
- **Performance Analytics**: HTAP queries on live transaction data

### Executive Dashboard
- **Company Metrics**: Aggregations across all branches
- **Analytics**: Year-over-year comparisons with instant query performance

### DevOps Dashboard
- **Hyperscale Metrics**: Live DMV data and replica status
- **Security Dashboard**: SQL injection detection and blocked query monitoring

## Troubleshooting

### MSAL Authentication Issues
- Verify redirect URIs match in Azure AD
- Check browser console for token errors
- Ensure API scope is correctly configured

### DAB Connection Issues
- Verify connection string in `dab-config.json`
- Check managed identity permissions
- Ensure database firewall allows connections

### API Errors
- Check DAB logs for detailed error messages
- Verify role assignments match user's Azure AD roles
- Test endpoints directly with curl or Postman

## License

This is a demonstration application for Azure SQL DB Hyperscale capabilities.
