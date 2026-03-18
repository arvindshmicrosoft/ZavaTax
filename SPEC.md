# ZavaTax — Project Specification

> **Purpose**: Complete specification for generating the ZavaTax Azure SQL Hyperscale demo project using spec-kit or equivalent code-generation tools. Everything in this document describes the desired end state of the system.

---

## 1. Business Context & Personas

### 1.1 Product Overview

ZavaTax is a full-stack tax preparation platform that showcases Azure SQL Database Hyperscale capabilities:

- **HTAP** (Hybrid Transactional/Analytical Processing) via clustered columnstore indexes
- **Read-Scale Out** with HA read-only replicas and named replicas
- **CQRS** routing reads vs. writes to appropriate replicas
- **Vector Search** using native `VECTOR(1536)` columns, DiskANN indexes, and `VECTOR_SEARCH()` / `VECTOR_DISTANCE()`
- **AI Integration** via Azure OpenAI (embeddings + chat) invoked from T-SQL using `sp_invoke_external_rest_endpoint`
- **Multi-Data-Source DAB** (Data API Builder) with 3 configuration files routing to primary, read-only replica, and named replica
- **High Transaction Log Throughput** via a multi-threaded load simulator (Hyperscale supports up to 100 MB/s per vCore; actual throughput varies with workload profile and SKU)

### 1.2 User Personas

| Persona | Role | Primary Activities |
|---------|------|-------------------|
| **Sarah Johnson** | Tax Filer | File returns, ask AI questions, view return history |
| **Michael Chen** | Tax Professional | Manage clients, find similar cases, search knowledge base |
| **Amanda Rodriguez** | Branch Manager | Team analytics, performance metrics, branch comparison |
| **Robert Williams** | Executive | Company-wide KPIs, branch rankings, filing trends |
| **Jennifer Park** | DevOps Engineer | System monitoring, security dashboard, DMV metrics, replica health |

### 1.3 Mock Users (Demo Mode)

```typescript
const mockUsers: MockUser[] = [
  { id: 'a1b2c3d4-...', name: 'Sarah Johnson', email: 'sarah.johnson@outlook.com', role: 'tax-filer', title: 'Individual Tax Filer', department: 'Customer', customerId: 1 },
  { id: 'b2c3d4e5-...', name: 'Michael Chen', email: 'mchen@zavatax.com', role: 'tax-professional', title: 'Senior Tax Preparer', department: 'Tax Services', professionalId: 1, branchId: 1 },
  { id: 'c3d4e5f6-...', name: 'Amanda Rodriguez', email: 'arodriguez@zavatax.com', role: 'branch-manager', title: 'Branch Manager', department: 'Operations', branchId: 1 },
  { id: 'd4e5f6a7-...', name: 'Robert Williams', email: 'rwilliams@zavatax.com', role: 'executive', title: 'Chief Operations Officer', department: 'Executive Leadership' },
  { id: 'e5f6a7b8-...', name: 'Jennifer Park', email: 'jpark@zavatax.com', role: 'devops', title: 'DevOps Engineer', department: 'Technology' },
];
```

`MockUser` interface includes: `id`, `name`, `email`, `role`, `title`, `department`, and optional `customerId`, `professionalId`, `branchId`.

Stored in `localStorage` under `zavatax_user`. Selected at login.

---

## 2. User Experience & Pages

### 2.1 LoginPage

- Two-column layout: left marketing panel (hidden on mobile) + right login card
- Phase 1: "Sign in with Microsoft Entra ID" button
- Phase 2: Persona picker showing all 5 mock users with role icons, names, titles
- Selected user highlighted with checkmark; Confirm/Back buttons
- No API calls; stores selected user in localStorage

### 2.2 Layout (Shell)

- Sidebar (256px, collapsible on mobile): Logo ("Z" in brand square + "Zava Tax"), role-based navigation sections, user info + logout button at bottom
- Header: hamburger menu (mobile), role badge with color dot (desktop)
- Main content area with padding

### 2.3 Tax Filer — Dashboard

- **Data**: `api.getTaxReturns()` filtered by `CustomerId eq {user.customerId}`
- **Stats row** (3 cards): Tax Years Filed (count), Latest Return (max year), Last Refund (latest refund amount)
- **Recent Returns** list: each row shows tax year, filing status, refund amount (green), View button (eye icon → `/filer/returns`)
- **Sidebar**: AI Tax Assistant gradient card (link to `/filer/ask`), Quick Links (New Return, View All Returns)
- Note: Status badge is intentionally hidden from filer UI (kept in DB/API)

### 2.4 Tax Filer — AskQuestion (AI Chat)

- **Data**: `api.askTaxAssistant()` (mutation)
- Full-height chat interface with scrollable message area
- Empty state: 4 suggested questions (clickable)
- User messages: right-aligned blue. Assistant messages: left-aligned gray with react-markdown rendering
- "AI-generated" badge on LLM-augmented responses
- Multi-turn: sends last 6 messages as context string
- Loading state: "Thinking..." with spinner

### 2.5 Tax Filer — MyReturns

- **Data**: `api.getTaxReturns()` filtered by customer
- Year filter dropdown (All + 2020–2024)
- Table: Tax Year, Filing Status, Form Type, Date Filed, Refund/Owed, Actions (eye icon)
- **Return Detail Modal**: Income section (Gross + AGI), Deductions, Tax Calculation (Liability + Withholding), metadata grid
- Note: Status column intentionally hidden

### 2.6 Tax Filer — NewReturn

- Thin wrapper rendering shared `NewReturnForm` with `customerId` prop
- On success navigates to `/filer/returns`

### 2.6a Tax Filer — EditReturn

- Route: `/filer/edit-return/:returnId`
- Loads existing return data and renders shared `NewReturnForm` in edit mode
- On success navigates to `/filer/returns`

### 2.7 NewReturnForm (Shared Component — ~1,263 lines)

- **Data**: `api.checkExistingReturn()` (validation), `api.createTaxReturn()` (mutation), `api.askTaxAssistant()` (embedded AI)
- **6-step wizard** with visual progress bar:
  1. **Filing Status**: Tax year dropdown, filing status radio buttons (Single, MFJ, MFS, HOH, QSS), dependents count
  2. **Income**: 6 fields — wages, interest, dividends, business, capital gains, other income
  3. **Deductions**: Standard vs. itemized toggle; if itemized: mortgage interest, SALT, charitable, medical
  4. **Credits**: Child Tax Credit, Education Credits, EITC checkboxes
  5. **International**: 6 conditional sections — foreign accounts (8938/FBAR thresholds), PFIC (8621), foreign trusts (3520), foreign corporations (5471), foreign partnerships (8865), foreign gifts + foreign tax credit (1116). Dynamic "Required International Tax Forms" summary.
  6. **Review**: All data in color-coded summary panels
- **Sticky sidebar**: Running tax estimate (gross income, deductions, taxable income, estimated tax, withholding, refund/owed) + "Ask AI Assistant" button
- **AI Assistant panel**: Expandable/maximizable floating chat, step-specific suggested questions, markdown rendering
- **Validation**: Front-loads duplicate check on tax year change; shows error banner if return already exists
- **Tax calculation**: Simplified 2025 brackets (10%, 12%, 22%, 24%, 32%, 35%, 37%); withholding estimated as 22% of wages
- Query invalidation on success: `tax-returns`, `customer-returns`, `check-existing-return`

### 2.8 Professional — Dashboard

- **Data**: `api.getCustomers()`, `api.getTaxReturns()`
- 4 stat cards: Active Clients, Returns in Progress (no FilingDate), Completed 2025, Needs Review (RefundAmount < 0)
- Two-column: "Needs Attention" list (amber, unfiled clients or high-owed returns) + "Recently Completed"
- Sidebar: Quick Actions (Clients, Similar Cases, KB), 2025 Summary, Key Dates (hardcoded deadlines)

### 2.9 Professional — Clients (~695 lines)

- **Data**: `api.getCustomers()`, `api.getTaxReturns()`, `api.createCustomer()`, `api.askTaxAssistant()`
- Search bar with live client filtering
- Client card grid (3-col): avatar, email, phone, location
- **Client Detail Modal**: contact grid + return history + "New Return" button
- **Add Client Modal**: full form (name, email, phone, address, DOB)
- **Return Detail Modal**: income/deductions/tax breakdown + AI Analysis section (calls `askTaxAssistant` for return analysis)
- **New Return Modal**: renders shared `NewReturnForm` in a modal

### 2.10 Professional — SimilarCases (~588 lines)

- **Data**: `api.searchSimilarCases()`, `api.getCachedCaseSummary()`, `api.askTaxAssistant()`, `api.saveCachedCaseSummary()`
- Textarea search + filing status filter dropdown
- Result cards: scenario type, tax year, similarity %, summary, income/deduction tags
- **Case Detail Modal**: AI analysis (cached or fresh), similarity score, full scenario breakdown (taxpayer profile, income, deductions, credits, special situations — all parsed from JSON)
- Cache-first pattern: check cache → if miss, call LLM → save to cache
- "Regenerate analysis" button; cache hit indicator with green badge

### 2.11 Professional — KnowledgeBase (~245 lines)

- **Data**: `api.askTaxQuestion()` (vector search)
- Search bar with results showing title, content preview, category badge, relevance %
- **Article Detail Modal**: full content, reference metadata
- Empty state: 6 browsable category buttons (hardcoded counts), 5 popular article links (trigger searches)

### 2.12 Branch Manager — Dashboard (~232 lines)

- **Data**: `api.getBranchAnalytics(1)`, `api.getBranchLeaderboard(1)`, `api.getReplicaIdentity()`
- 4 stat cards: Team Members, Total Returns (with "this week" badge), Income Processed (MTD), Avg Processing Time
- Team Leaderboard table: Rank (medal styling for top 3), Name/Certification, Returns, Avg Time, Income Processed
- Sidebar: Return Status breakdown (progress bars), Financial Summary
- **Tech Banner**: Hyperscale Named Replica + NCCI info with live replica identity badges (DatabaseName, Updateability, ServerName)

### 2.13 Branch Manager — Team (~162 lines)

- **Data**: `api.getBranchLeaderboard(1)`, `api.getBranchAnalytics(1)`
- 4 summary cards (Team Members, Total Returns, Avg Processing Time, Income Processed), team member card grid, Top Performer banner
- Team member stats derived from leaderboard stored procedure

### 2.14 Branch Manager — Performance (~207 lines)

- **Data**: `api.getBranchAnalytics(1)`, `api.getTopBranches(5)`, `api.getBranchLeaderboard(1)` — all with year selector
- 4 metric cards: Returns, Income Processed, Avg Time, Team Size
- Team Performance table
- Branch Comparison table (current branch highlighted with "Your Branch" badge)
- Tech Banner explaining NCCI analytics

### 2.15 Executive — Dashboard (~296 lines)

- **Data**: `api.getExecutiveKPIs(selectedYear)`, `api.getTopBranches(5, selectedYear)`, `api.getFilingStatusDistribution(selectedYear)`, `api.getReplicaIdentity()`
- Year selector dropdown — all queries (KPIs, top branches, filing status) filter by selected tax year
- 4 KPI cards: Total Income Processed, Returns Processed, Active Customers, Active Branches — each with "last 30d" detail
- 3-col: Financial Summary, Returns by Status (progress bars), Filing Status Distribution (color dots)
- Top Branches table: Rank, Name, Location, Returns, Income Processed, Staff, Avg Time — filtered by selected year
- Tech Banner with live replica identity badges (DB_NAME, Updateability, ServerName)

### 2.16 Executive — Analytics (~236 lines)

- **Data**: `api.getTopBranches(10, selectedYear)`, `api.getFilingStatusDistribution(selectedYear)`, `api.getReturnsByYear()`
- Year selector dropdown for branch filtering
- CSS-based horizontal bar chart for branch income processed
- Filing status breakdown with avg income/refund
- Year-over-year comparison table with deductions and itemization stats
- Export button (placeholder, non-functional)

### 2.17 Executive — Filing Analytics (~602 lines)

- **Data**: `api.getFilingDetailOverview()`, `api.getEFileStatusSummary()`, `api.getW2Summary()`, `api.getForm1099Summary()`, `api.getCapitalGainsSummary()`, `api.getScheduleCSummary()`, `api.getStateTaxSummary()`, `api.getScheduleESummary()`, `api.getScheduleBSummary()`, `api.getDocumentSummary()`
- 10 simultaneous API queries to filing-detail analytics stored procedures
- Filing Overview cards, E-File status breakdown, income source summaries (W-2, 1099, Capital Gains, Schedule C/E/B), state tax distribution, document tracking
- All data is real — powered by the filing details tables populated by `08_generate_filing_details.sql`

### 2.18 DevOps — Dashboard / Metrics (~205 lines)

- **Data**: `api.getHyperscaleResourceStatsAll()` with 5s auto-refresh (toggleable)
- Fetches live DMV data from **3 endpoints in parallel**: primary, HA read replica, and named replica
- Metrics table showing per-replica: Snapshot Time, CPU%, Data IO%, Log Write%, Worker%, Memory%
- Manual refresh button + auto-refresh toggle
- All data is real — sourced from `sys.dm_db_resource_stats` via `GetHyperscaleMetrics` stored procedure

### 2.19 DevOps — Security Dashboard (~578 lines)

- **Data**: `api.getSecurityOverview()`, `api.getSecurityRLSDemo()`, `api.getSecurityDDMDemo()`, `api.getSecurityLedger()`, `api.getSecurityClassification()`
- Demonstrates 4 Azure SQL security features: Row-Level Security (RLS), Dynamic Data Masking (DDM), Ledger tables, Column Classification
- RLS demo: shows how different user contexts see different data subsets
- DDM demo: shows masked vs. unmasked PII fields
- Ledger demo: shows tamper-evident audit log entries
- Classification demo: shows column sensitivity labels
- All data is real — powered by 5 security stored procedures

---

## 3. Routing & Navigation

### 3.1 Routes

| Path | Component | Persona |
|------|-----------|---------|
| `/` | Redirect to role home | All |
| `/filer` | TaxFilerDashboard | Tax Filer |
| `/filer/ask` | AskQuestion | Tax Filer |
| `/filer/returns` | MyReturns | Tax Filer |
| `/filer/new-return` | NewReturn | Tax Filer |
| `/professional` | ProfessionalDashboard | Tax Professional |
| `/professional/clients` | Clients | Tax Professional |
| `/professional/cases` | SimilarCases | Tax Professional |
| `/professional/knowledge` | KnowledgeBase | Tax Professional |
| `/branch` | BranchManagerDashboard | Branch Manager |
| `/branch/team` | Team | Branch Manager |
| `/branch/performance` | Performance | Branch Manager |
| `/executive` | ExecutiveDashboard | Executive |
| `/executive/analytics` | Analytics | Executive |
| `/filer/edit-return/:returnId` | EditReturn | Tax Filer |
| `/executive/filing-analytics` | FilingAnalytics | Executive |
| `/devops` | Metrics | DevOps |
| `/devops/security` | SecurityDashboard | DevOps |

Each persona can only access their own routes. Unknown paths redirect to role home.

### 3.2 Workload Routing (CQRS)

The frontend tags every API request with workload intent headers:

| Header | Purpose |
|--------|---------|
| `X-Workload-Type` | Semantic workload classification (e.g., `analytics`, `tax-filer-readonly`) |
| `X-Replica-Target` | Physical target (`primary`, `readonly-replica`, `named-replica`) |

Routing rules:

| User Role | Operation | Workload Type | Replica Target |
|-----------|-----------|---------------|----------------|
| Tax Filer | Read returns | `tax-filer-readonly` | Read-Only Replica |
| Tax Filer | Create return | `transactional` | Primary |
| Tax Filer | AI assistant | `ai-assistant` | Read-Only Replica |
| Tax Professional | View clients | `tax-professional-readonly` | Read-Only Replica |
| Tax Professional | Vector search | `ai-assistant` | Read-Only Replica |
| Tax Professional | Write data | `transactional` | Primary |
| Branch Manager | Analytics | `analytics` | Named Replica |
| Executive | Dashboard | `executive-dashboard` | Named Replica |
| DevOps | Monitoring | `devops` | Named Replica |

An in-memory `WorkloadRoutingTracker` records routing decisions for the Read-Scale Demo page.

---

## 4. Frontend Layer

### 4.1 Tech Stack

| Technology | Version | Purpose |
|------------|---------|---------|
| React | 18 | UI framework |
| TypeScript | 5.3+ | Type safety |
| Vite | 7.x | Build tool and dev server |
| Tailwind CSS | 3.4 | Utility-first styling |
| TanStack React Query | 5 | Server state management |
| React Router | 6 | Client-side routing |
| Lucide React | 0.312 | Icon library |
| react-markdown | 10.1 | Markdown rendering for AI responses |
| MSAL Browser/React | 3.10 / 2.0 | Azure AD authentication |
| date-fns | 3.3 | Date formatting |

### 4.2 Custom Theme (Tailwind)

- **Brand color `zava`**: Sky-blue palette — `50: #f0f9ff` through `950: #082f49`, with primary `500: #0ea5e9` and `600: #0284c7`
- **Font**: Inter (Google Fonts)
- **Custom shadows**: `card` and `card-hover`
- **Plugin**: `@tailwindcss/typography` for prose rendering

### 4.3 Custom CSS Classes (index.css)

Reusable component classes built on Tailwind:
- `.card`, `.card-header`, `.card-body` — white bg, rounded, shadow
- `.btn-primary`, `.btn-secondary`, `.btn-success`, `.btn-warning`, `.btn-danger`, `.btn-outline` — using zava-* colors
- `.badge-*` — 6 variants (success, warning, danger, info, primary, secondary)
- `.data-table` — dark slate header, hover rows
- `.stat-card` — for dashboard metric cards
- `.sidebar-link`, `.sidebar-link-active`, `.sidebar-link-inactive`
- `.alert-*` — 4 variants (info, success, warning, danger)
- `.metric-value`, `.metric-label` — large number displays

### 4.4 Application Structure

```
src/
├── main.tsx              # Entry: BrowserRouter → MsalProvider → QueryClientProvider → App
├── App.tsx               # Auth gate + role-based route rendering
├── index.css             # Global Tailwind + custom component styles
├── vite-env.d.ts         # Vite type declarations
├── lib/
│   ├── api.ts            # REST API client (all DAB calls)
│   ├── auth.ts           # MSAL config, token acquisition, role parsing
│   ├── mockUsers.ts      # 5 demo personas with localStorage persistence
│   ├── navigation.ts     # Role-based sidebar navigation definitions
│   └── workloadRouting.ts # CQRS workload classification + tracking
├── components/
│   ├── Layout.tsx         # Shell: sidebar + header + main content area
│   └── NewReturnForm.tsx  # 6-step tax return wizard (shared by Filer + Professional)
└── pages/
    ├── LoginPage.tsx
    ├── tax-filer/
    │   ├── Dashboard.tsx
    │   ├── AskQuestion.tsx
    │   ├── MyReturns.tsx
    │   ├── NewReturn.tsx
    │   └── EditReturn.tsx
    ├── professional/
    │   ├── Dashboard.tsx
    │   ├── Clients.tsx
    │   ├── SimilarCases.tsx
    │   └── KnowledgeBase.tsx
    ├── branch-manager/
    │   ├── Dashboard.tsx
    │   ├── Team.tsx
    │   └── Performance.tsx
    ├── executive/
    │   ├── Dashboard.tsx
    │   ├── Analytics.tsx
    │   └── FilingAnalytics.tsx
    └── devops/
        ├── Dashboard.tsx  (unused — orphan file)
        ├── Metrics.tsx
        └── SecurityDashboard.tsx
```

### 4.5 API Client (`api.ts`)

The API client provides typed methods for all DAB endpoints. Key methods:

**CRUD Operations** (read from replica, write to primary):
- `getBranches()`, `getBranch(id)` → `/api/branches-read`
- `getTaxReturns()`, `createTaxReturn(data)` → `/api/returns-read` and `/api/returns`
- `getCustomers()`, `getCustomer(id)`, `createCustomer(data)`, `updateCustomer(id, data)` → `/api/customers-read` and `/api/customers`
- `getProfessionals(branchId?)` → `/api/professionals-read`
- `getScenarios()` → `/api/scenarios-read`
- `checkExistingReturn(customerId, taxYear)` → duplicate detection

**AI / Search** (read from replica):
- `askTaxQuestion(question, topK)` → POST `/api/ai-ask`
- `askTaxAssistant(question, context?, topK)` → POST `/api/ai-assistant` — returns `{ answer, sourceContent, isLLMAugmented }`
- `searchSimilarCases(query, filingStatus?, topK)` → POST `/api/search-cases`
- `searchKnowledgeText(searchText, topK)` → POST `/api/search-text`

**Cache**:
- `getCachedCaseSummary(scenarioId)` → GET `/api/case-summary-cache`
- `saveCachedCaseSummary(scenarioId, summary, model)` → POST `/api/case-summary-cache-save`

**Analytics** (named replica):
- `getBranchAnalytics(branchId)` → POST `/api/analytics-branch`
- `getBranchLeaderboard(branchId)` → POST `/api/analytics-leaderboard`
- `getExecutiveKPIs(taxYear?)` → POST `/api/analytics-executive-kpis`
- `getTopBranches(topN, taxYear?)` → POST `/api/analytics-top-branches`
- `getFilingStatusDistribution(taxYear?)` → POST `/api/analytics-filing-status`
- `getReturnsByYear()` → POST `/api/analytics-returns-by-year`
- `getReplicaIdentity()` → POST `/api/analytics-replica-info`

**Filing Detail Analytics** (named replica):
- `getFilingDetailOverview()` → POST `/api/analytics-filing-overview`
- `getEFileStatusSummary()` → POST `/api/analytics-efile-status`
- `getW2Summary()` → POST `/api/analytics-w2-summary`
- `getForm1099Summary()` → POST `/api/analytics-form1099-summary`
- `getCapitalGainsSummary()` → POST `/api/analytics-capital-gains`
- `getScheduleCSummary()` → POST `/api/analytics-schedule-c`
- `getStateTaxSummary()` → POST `/api/analytics-state-tax`
- `getScheduleESummary()` → POST `/api/analytics-schedule-e`
- `getScheduleBSummary()` → POST `/api/analytics-schedule-b`
- `getDocumentSummary()` → POST `/api/analytics-document-summary`

**Monitoring** (all three endpoints):
- `getHyperscaleResourceStatsAll()` → fetches `GetHyperscaleMetrics` from primary, read-only, and named replica in parallel

**Security** (named replica):
- `getSecurityOverview()` → POST `/api/analytics-security-overview`
- `getSecurityRLSDemo()` → POST `/api/analytics-security-rls`
- `getSecurityDDMDemo()` → POST `/api/analytics-security-ddm`
- `getSecurityLedger()` → POST `/api/analytics-security-ledger`
- `getSecurityClassification()` → POST `/api/analytics-security-classification`

**GraphQL**: `graphqlQuery<T>(query, variables)` → POST `/graphql`

### 4.6 Authentication

**Demo Mode** (mock users):
- Login page presents 5 mock personas (simulating Entra ID SSO)
- Selected user stored in `localStorage`
- Role determines which routes and navigation are available
- The web server acquires MI tokens for DAB regardless of demo/prod mode

**Production Mode** (Entra ID):
- MSAL.js with `@azure/msal-browser` and `@azure/msal-react`
- App roles: `TaxFiler`, `TaxProfessional`, `BranchManager`, `Executive`, `DevOps`
- Role priority: devops > executive > branch-manager > tax-professional > tax-filer
- Token scopes: `api://{client-id}/access_as_user`

---

## 5. Architecture

### 5.1 System Components

```
┌─────────────────┐     ┌──────────────────┐     ┌──────────────────────────┐
│   Web Server    │────▶│  Data API Builder │────▶│   Azure SQL Hyperscale   │
│  (Express.js /  │     │    (Container)    │     │  ┌──────────┐           │
│  ASP.NET Core)  │     │  3 DAB configs    │     │  │ Primary  │ R/W       │
│  Serves SPA +   │     │  Primary (R/W)    │     │  ├──────────┤           │
│  Proxies /api/* │     │  Replica (RO)     │     │  │ HA Replica│ ReadOnly │
│  with MI token  │     │  Analytics (NR)   │     │  ├──────────┤           │
└─────────────────┘     └──────────────────┘     │  │ Named    │ Analytics │
                                                  │  │ Replica  │           │
                                                  │  └──────────┘           │
                                                  └──────────────────────────┘
```

### 5.2 Web Server

The web server (Express.js, ASP.NET Core, or FastAPI) serves both the SPA static files and acts as an API proxy to DAB:

1. **Serves the SPA** — static files from the Vite `dist/` directory with SPA fallback (all non-API routes serve `index.html`)
2. **Proxies API calls** — forwards `/api/*` and `/graphql` requests to the DAB App Service
3. **Attaches Managed Identity tokens** — uses `@azure/identity` `ManagedIdentityCredential` (or `DefaultAzureCredential` for local dev) to acquire Bearer tokens for DAB
4. **Health check** — `/health` endpoint
5. **Same-origin** — no CORS configuration needed

**Recommended structure** (Express.js):

```
webapp/server/
├── server.js          # Express app setup, static serving, health check
├── middleware/
│   ├── auth.js        # MI token acquisition + caching
│   └── proxy.js       # API proxy to DAB with token injection
└── config.js          # Environment-based configuration
```

**Key behaviors**:
- Token caching with automatic refresh (tokens expire every ~1 hour)
- Request timeout handling (DAB stored procedures can take seconds for AI calls)
- Error forwarding (pass DAB error responses through to the client)
- Startup probe: verify DAB is reachable before accepting traffic

**Environment variables**:

| Variable | Description |
|----------|-------------|
| `DAB_BASE_URL` | DAB App Service URL (e.g., `https://zavatax-dev-dab-xxx.azurewebsites.net`) |
| `AZURE_CLIENT_ID` | User-Assigned Managed Identity Client ID |
| `PORT` | Server port (default 8080) |
| `NODE_ENV` | `production` or `development` |

**Local development**: The web server runs on port 8080 and proxies to DAB at `http://localhost:5000`. Uses `DefaultAzureCredential` which falls through to Azure CLI credentials. Vite dev server (port 5173) proxies `/api` and `/graphql` to port 5000 for hot-reload development.

---

## 6. Data API Builder (DAB) Layer

### 6.1 Multi-Data-Source Configuration

DAB uses 3 configuration files linked via `data-source-files`:

**dab-config.json** (Primary — Read/Write):
- Connection: `@env('DATABASE_CONNECTION_STRING')`
- Entities: Branch, Professional, Customer, TaxReturn, TaxScenario, Knowledge (all CRUD), plus stored procedure entities (GetCachedSummary, SaveCachedSummary, AskTaxAssistant, AskTaxQuestion, SearchSimilarCases)
- REST + GraphQL enabled

**dab-config.replica.json** (HA Read Replica):
- Connection: `@env('DATABASE_CONNECTION_STRING_READONLY')` (with `ApplicationIntent=ReadOnly`)
- Entities: BranchRead, ProfessionalRead, CustomerRead, TaxReturnRead, TaxScenarioRead, KnowledgeRead (read-only), BranchPerformance (view)
- REST paths suffixed with `-read` (e.g., `/branches-read`, `/returns-read`)

**dab-config.analytics.json** (Named Replica):
- Connection: `@env('DATABASE_CONNECTION_STRING_ANALYTICS')`
- 7 stored procedure entities (POST only): BranchAnalytics, BranchLeaderboard, ExecutiveKPIs, TopBranches, FilingStatusDistribution, ReturnsByYear, ReplicaInfo
- REST paths prefixed with `/analytics-` (e.g., `/analytics-branch`, `/analytics-executive-kpis`)

### 6.2 DAB Configuration Details

- **REST base path**: `/api`
- **GraphQL**: enabled at `/graphql` with introspection
- **Host mode**: `production`
- **Auth provider**: `EntraID`
- **CORS**: Not configured (same-origin with web server proxy)
- **Permissions**: `authenticated`

### 6.3 DAB Path Constraints

> **CRITICAL**: DAB REST paths **cannot contain forward slashes** (`/`). Use hyphens instead. For example: `/analytics-branch` not `/analytics/branch`. Paths with slashes cause DAB to crash with a startup error.

### 6.4 DAB Docker Image

```dockerfile
FROM mcr.microsoft.com/azure-databases/data-api-builder:latest
COPY dab-config.json /App/dab-config.json
COPY dab-config.replica.json /App/dab-config.replica.json
COPY dab-config.analytics.json /App/dab-config.analytics.json
```

Deployed to Azure Container Registry, run on Linux App Service.

---

## 7. Database Layer

### 7.1 Azure SQL DB Hyperscale Configuration

| Property | Value |
|----------|-------|
| SKU | Hyperscale (HS_PRMS_4 default, configurable) |
| Zone Redundant | Yes |
| Backup Redundancy | GeoZone (GZRS) |
| HA Replicas | 1 |
| Read Scale | Enabled |
| Auth | Entra-only (no SQL passwords) |

**Named Replica** (for analytics):

| Property | Value |
|----------|-------|
| Name | `{dbname}-analytics` |
| SKU | Gen5, Serverless |
| vCores | 2–24 (auto-scale) |
| HA Replicas | 0 |
| Read Scale | Disabled |

> **Important**: Hyperscale serverless does NOT support auto-pause. Do not set `--auto-pause-delay`.

### 7.2 Tables

#### Reference Tables

1. **Branches** — `BranchId` (IDENTITY PK), `BranchName`, `Address`, `City`, `State`, `StateAbbr` (CHAR 2), `ZipCode`, `Phone`, `ManagerName`, `OpenedDate`, `IsFranchise` (BIT), `SquareFeet`, `NumWorkstations`, `CreatedAt`
   - Indexes: `IX_Branches_State(StateAbbr)`, `IX_Branches_City(City, StateAbbr)`

2. **TaxProfessionals** — `ProfessionalId` (IDENTITY PK), `BranchId` (FK→Branches), `FirstName`, `LastName`, `Email`, `Phone`, `HireDate`, `Certification` (CPA/EA/AFSP/None), `YearsExperience`, `IsActive`, `HourlyRate`, `AvgReturnsPerDay`, `CreatedAt`
   - Indexes: `IX_TaxProfessionals_Branch(BranchId)`, `IX_TaxProfessionals_Active(IsActive) INCLUDE(BranchId, FirstName, LastName)`

3. **Customers** — `CustomerId` (IDENTITY PK), `FirstName`, `LastName`, `Email`, `Phone`, `Address`, `City`, `State`, `StateAbbr`, `ZipCode`, `DateOfBirth`, `SSNLastFour` (CHAR 4), `CreatedDate`, `PreferredLanguage`, `PreferredContact`, `IsActive`, `CreatedAt`
   - Indexes: `IX_Customers_State`, `IX_Customers_Email`, `IX_Customers_Name(LastName, FirstName)`

4. **InternationalFormRequirements** — `FormId` (IDENTITY PK), `FormNumber`, `FormName`, `Description`, `ThresholdAmount`, `ThresholdDescription`, `Penalties`, `FilingDeadline`
   - Seeded with 8 forms: 8938 (FATCA), FinCEN 114 (FBAR), 8621 (PFIC), 3520 (Foreign Trust), 3520-A, 5471, 8865, 1116

#### Vector Search Tables

5. **TaxKnowledgeBase** — `Id` (IDENTITY PK CLUSTERED), `ChunkId` (UNIQUE), `PublicationId`, `PublicationTitle`, `Section`, `Subsection`, `Content` (NVARCHAR MAX), `TokenEstimate`, `SourceUrl`, `ChunkIndex`, `ContentEmbedding VECTOR(1536)`, `CreatedAt`
   - Index: `IX_TaxKnowledge_Publication(PublicationId)`
   - Vector Index: `IX_TaxKnowledgeBase_Embedding` (DiskANN, cosine)

6. **TaxScenarios** — `Id` (IDENTITY PK CLUSTERED), `ScenarioId` (UNIQUE), `TaxYear`, `ScenarioType`, `TaxpayerProfile` (JSON), `FilingStatus` (computed from JSON, PERSISTED), `IncomeSources` (JSON), `Deductions` (JSON), `Credits` (JSON), `SpecialSituations` (JSON), `TaxOutcome` (JSON), `TotalIncome`/`RefundAmount`/`AmountOwed` (computed from JSON, PERSISTED), `ComplexityScore`, `KeyCharacteristics` (JSON), `ScenarioSummary`, `ResolutionNotes`, `ScenarioEmbedding VECTOR(1536)`, `CreatedAt`
   - Indexes: `IX_TaxScenarios_Type(ScenarioType, ComplexityScore)`, `IX_TaxScenarios_FilingStatus`, `IX_TaxScenarios_TaxYear`
   - Vector Index: `IX_TaxScenarios_Embedding` (DiskANN, cosine)
   - CHECK constraints: ISJSON on TaxpayerProfile, IncomeSources, TaxOutcome

#### HTAP / Transactional Tables

7. **TaxReturns** — `ReturnId` (IDENTITY PK CLUSTERED), `CustomerId`, `BranchId`, `ProfessionalId`, `TaxYear`, `FilingDate`, `FilingStatus`, `GrossIncome`, `AdjustedGrossIncome`, `TotalDeductions`, `TaxableIncome`, `TaxLiability`, `TotalWithheld`, `RefundAmount`, `AmountOwed` (all DECIMAL 14,2), `Status` (default 'Draft'), `IsItemized`, `NumDependents`, `ProcessingTimeMinutes`, `DocumentCount`, `AIAssistanceCount`, `IsAmended`, `IsExtension`, 11 international tax fields (`HasForeignAccounts`, `ForeignAccountMaxValue`, `HasPFIC`, `PFICValue`, `PFICIncome`, `HasForeignTrust`, `ForeignTrustValue`, `HasForeignCorporation`, `ForeignCorpOwnershipPct`, `HasForeignPartnership`, `ForeignGiftsReceived`, `ForeignTaxesPaid`), `CreatedAt`, `UpdatedAt`
   - **Nonclustered Columnstore Index**: `NCCI_TaxReturns_Analytics` (HTAP — analytical scans over rowstore)
   - Unique: `UQ_TaxReturns_Customer_TaxYear(CustomerId, TaxYear)`
   - NCI: `IX_TaxReturns_Customer`, `IX_TaxReturns_Branch_Date`, `IX_TaxReturns_Professional`, `IX_TaxReturns_International`

#### Cache Table

8. **CaseSummaryCache** — `CacheId` (IDENTITY PK), `ScenarioId` (UNIQUE), `Summary` (NVARCHAR MAX), `Model` (default 'gpt-5.2-chat'), `GeneratedAt`, `ExpiresAt`, `HitCount`

### 7.3 Views

1. **vw_BranchPerformanceRealtime** — Joins TaxReturns + Branches for today's data. Columns: BranchId, BranchName, City, State, ReturnsToday, RefundsIssued, AvgProcessingMinutes, TotalRefundsToday, AvgRefundAmount, ActiveProfessionals.

2. **vw_ExecutiveDashboard** — Aggregates TaxReturns by TaxYear, FilingWeek, FilingMonth, FilingStatus. Includes AIAssistedPct.

### 7.4 Stored Procedures

#### Core Procedures

| Procedure | Purpose | Parameters |
|-----------|---------|------------|
| `SearchKnowledgeBase` | Vector search for RAG | `@QueryEmbedding VECTOR(1536)`, `@TopK INT = 5` |
| `BulkInsertTaxReturns` | High-throughput batch insert | `@BatchData NVARCHAR(MAX)` (JSON), `@BatchId UNIQUEIDENTIFIER` |
| `GetHyperscaleMetrics` | Monitoring DMVs | None |

#### AI Procedures (created by 05_setup_azure_openai_endpoint.sql)

| Procedure | Purpose | Parameters |
|-----------|---------|------------|
| `AskTaxQuestion` | RAG vector search only | `@Question`, `@TopK = 5` |
| `SearchSimilarCases` | Scenario vector search | `@Query`, `@FilingStatus`, `@TopK = 10` |
| `AskTaxAssistant` | Full RAG + LLM pipeline | `@Question`, `@Context`, `@TopK = 3` |

`AskTaxAssistant` workflow:
1. Generate embedding via `AI_GENERATE_EMBEDDINGS(@Question, 'AzureOpenAI_Embeddings')`
2. `VECTOR_SEARCH` on TaxKnowledgeBase (cosine, DiskANN)
3. If no results → keyword fallback with `CONTAINS` / `LIKE`
4. Build prompt with retrieved context
5. Call GPT model via `sp_invoke_external_rest_endpoint` with Managed Identity credential
6. Return `Answer`, `SourceContent`, `IsLLMAugmented`

#### Cache Procedures

| Procedure | Purpose | Parameters |
|-----------|---------|------------|
| `GetCachedCaseSummary` | Retrieve cached LLM summary (increments HitCount) | `@ScenarioId` |
| `SaveCachedCaseSummary` | Upsert summary with 30-day TTL | `@ScenarioId`, `@Summary`, `@Model`, `@ExpirationDays = 30` |
| `ClearExpiredCaseSummaries` | Maintenance cleanup | None |

#### Analytics Procedures (Named Replica / NCCI)

| Procedure | Purpose | Parameters |
|-----------|---------|------------|
| `GetBranchAnalytics` | Branch KPIs (returns, income processed, processing times, status breakdown) | `@BranchId INT = 1` |
| `GetBranchLeaderboard` | Top 10 professionals by returns filed | `@BranchId INT = 1` |
| `GetExecutiveKPIs` | Company-wide aggregations for a given tax year | `@TaxYear INT = 0` |
| `GetTopBranches` | Top N branches by return count | `@TopN INT = 10`, `@TaxYear INT = 0` |
| `GetFilingStatusDistribution` | Filing status breakdown with percentages for a given tax year | `@TaxYear INT = 0` |
| `GetReturnsByYear` | Year-over-year trend data | None |
| `GetReplicaInfo` | Returns `DB_NAME()`, `Updateability`, `@@SERVERNAME`, `GETUTCDATE()` — proves which replica served the query | None |

### 7.5 Azure OpenAI Integration (SQL-Side)

- **External Model**: `AzureOpenAI_Embeddings` — type `EMBEDDINGS`, `text-embedding-3-small` deployment, `API_FORMAT = 'Azure OpenAI'`
- **Credential**: Database-scoped credential with `Managed Identity` and `resourceid=https://cognitiveservices.azure.com`
- **Functions used**: `AI_GENERATE_EMBEDDINGS()`, `VECTOR_SEARCH()`, `VECTOR_DISTANCE()`
- **LLM invocation**: `sp_invoke_external_rest_endpoint` with `@credential` for chat completions

---

## 8. Data Preparation Pipeline

### 8.1 Overview

A 7-step Python pipeline generates all data for the application:

```
01_download_irs_pubs.py  →  Download IRS HTML publications
02_parse_and_chunk.py    →  Parse HTML → structured text chunks (~500 tokens)
03_generate_embeddings.py →  Azure OpenAI embeddings (VECTOR 1536)
04_generate_scenarios.py →  5,000 synthetic tax scenarios (rule-based)
05_embed_scenarios.py    →  Embed scenario summaries
06_generate_operational_data.py → CSV data (branches, professionals, customers, returns)
07_load_to_azure_sql.py  →  Load to Azure SQL (from blob storage)
07_load_to_sqlexpress.py →  Load to local SQL Express (from local files)
```

### 8.2 Configuration (config.py)

- **IRS Publications**: 10 publications (p17, p587, p501, p525, p596 at priority 1; i1040, p502, p527, p550, p590a at priority 2)
- **Azure OpenAI**: `text-embedding-3-small` (1536-dim), configurable chat model
- **Data volumes**: 500 branches, ~2,500 professionals (3–8 per branch), 10,000 customers, up to 1,000,000 returns
- **Scenario types**: 9 categories (simple_w2=1000, dual_income=500, self_employed=800, rental_property=500, investments=700, cryptocurrency=300, home_office=400, life_events=500, complex_edge=300)
- **Embedding**: batch size 100, 1536 dimensions

### 8.3 Python Dependencies

`requests`, `beautifulsoup4`, `lxml`, `pymupdf`, `openai`, `azure-identity`, `faker`, `pandas`, `numpy`, `tqdm`, `python-dotenv`, `mssql-python`, `orjson`

### 8.4 Data Loaders (3 variants)

1. **`07_load_to_azure_sql.py`** — Production: reads from Azure Blob Storage via `OPENROWSET`, uses Entra ID auth, handles vector index lifecycle
2. **`07_load_to_sqlexpress.py`** — Local dev: reads local CSV/JSON files, uses Windows auth, limits TaxReturns to 10K

### 8.5 SQL Loading Scripts

- **`02_load_csv_data.sql`** — BULK INSERT from Azure Blob Storage with External Data Source + Managed Identity credential
- **`03_load_json_data.sql`** — Stored procedures (`LoadKnowledgeBaseFromJson`, `LoadTaxScenariosFromJson`) accepting JSON strings, parsing with OPENJSON, casting embeddings to `VECTOR(1536)`

---

## 9. Load Simulator

### 9.1 Purpose

Demonstrates Azure SQL Hyperscale’s high transaction log throughput capability via multi-threaded batch inserts. Hyperscale supports up to 100 MB/s per vCore; actual throughput varies with batch size, data complexity, and SKU.

### 9.2 Architecture

- `main.py` — CLI entry point, orchestrates workers
- `data_generator.py` — Generates realistic tax return JSON batches
- `db_worker.py` — Thread workers using `mssql-python` driver, calls `BulkInsertTaxReturns` stored procedure
- `metrics.py` — Prometheus-compatible metrics
- `monitor.py` — Real-time progress with color-coded throughput

### 9.3 Configuration

CLI options: `--server`, `--database`, `--workers` (1–64), `--batch-size` (100–100K), `--duration` (seconds), `--target-throughput` (MB/s)

### 9.4 Dependencies

`mssql-python`, `azure-identity`, `pandas`, `numpy`, `aiohttp`, `faker`, `psutil`, `tabulate`, `orjson`, `rich`, `tenacity`

---

## 10. Deployment

### 10.1 Azure Resources

| Resource | Type | Purpose |
|----------|------|---------|
| Resource Group | `rg-{basename}-{env}` | Container for all resources |
| User-Assigned Managed Identity | `{basename}-{env}-identity` | App-to-DB and App-to-OpenAI auth |
| Azure SQL Server | `{basename}-{env}-sql-{suffix}` | Entra-only auth, with MI assigned |
| SQL Database (Hyperscale) | `{basename}db` | Primary R/W database |
| SQL Named Replica | `{basename}db-analytics` | Analytics workload offload |
| App Service Plan | `{basename}-{env}-plan` | Linux, B2 default |
| Web App (Frontend + Server) | `{basename}-{env}-web-{suffix}` | Node.js 22 (or .NET 8 / Python 3.12) |
| Azure Container Registry | `{basename}{env}acr` | DAB Docker image |
| DAB App Service (Container) | `{basename}-{env}-dab-{suffix}` | Data API Builder |
| Storage Account | `{basename}{env}data` | CSV data for BULK INSERT |
| Azure OpenAI (optional) | `oai-{basename}-{env}` | Chat + Embedding models |

### 10.2 Connection Strings

Three connection strings are set as App Settings on the DAB App Service:

1. **`DATABASE_CONNECTION_STRING`** — Primary (R/W): `Server={fqdn};Database={db};Authentication=Active Directory Managed Identity;User Id={mi-client-id};Encrypt=True;`
2. **`DATABASE_CONNECTION_STRING_READONLY`** — HA Replica: same as above + `ApplicationIntent=ReadOnly;`
3. **`DATABASE_CONNECTION_STRING_ANALYTICS`** — Named Replica: `Server={fqdn};Database={db}-analytics;...`

### 10.3 Deployment Script (`deploy.ps1`)

Single PowerShell script (~900 lines) with modular phases:
1. **Validation** — Azure CLI, login, prerequisites
2. **Resource naming** — Deterministic names with unique suffix from resource group hash
3. **Infrastructure** — Resource group, managed identity, storage account, App Service Plan, SQL Server (Entra-only), Hyperscale DB (zone-redundant, GZRS, 1 HA replica), Named Replica (serverless Gen5 2-24 vCores), Web App, ACR, DAB App Service
4. **Azure OpenAI** (optional) — Chat model + embedding model deployment, MI role assignment
5. **Database schema** — Runs `01_create_schema.sql` via sqlcmd with Entra auth, grants MI access, runs `05_setup_azure_openai_endpoint.sql`
6. **Web app deployment** — `npm ci`, `npm run build`, zip deploy

**Parameters**: `-Environment` (dev/staging/prod), `-Location`, `-BaseName`, `-AppServiceSku`, `-SqlDatabaseSku`, `-DeployOpenAI`, `-SkipInfrastructure`, `-SkipDatabase`, `-SkipWebApp`

### 10.4 Security Headers

- Content-Security-Policy: default-src 'self', connect-src includes `*.azurewebsites.net`
- X-Frame-Options: DENY
- X-Content-Type-Options: nosniff
- X-XSS-Protection: 1; mode=block
- Referrer-Policy: strict-origin-when-cross-origin

---

## 11. Documentation

### 11.1 Docs

| File | Purpose | Length |
|------|---------|-------|
| `docs/ARCHITECTURE_AND_DEMO_DESIGN.md` | Full architecture, persona journeys, demo scenarios, performance targets | ~985 lines |
| `docs/DATA_STRATEGY_AND_RAG_DESIGN.md` | Data sources, RAG strategy, chunking approach, synthetic data design | ~1452 lines |
| `docs/HYPERSCALE_READ_SCALE.md` | CQRS connection string strategy, workload routing matrix, DAB config | ~216 lines |
| `README.md` | Quick start, project structure, tech stack | Root-level |
| `data-prep/README.md` | Data pipeline instructions | |
| `database/README.md` | Schema deployment guide | |
| `load-simulator/README.md` | Load testing guide | |
| `webapp/README.md` | Frontend development guide | |

### 11.2 Performance Targets

| Metric | Target |
|--------|--------|
| Vector search latency | < 50ms |
| Transaction log throughput | High (varies by SKU; Hyperscale supports up to 100 MB/s per vCore) |
| OLTP point query (p99) | < 100ms |
| Analytics query (10M rows) | < 2 seconds |
| Named replica lag | < 5 seconds |
| AI assistant response | < 3 seconds |

---

## 12. Known Constraints & Design Decisions

1. **DAB path constraint**: REST paths cannot contain `/` — use hyphens (e.g., `/analytics-branch` not `/analytics/branch`)
2. **Hyperscale serverless**: Does NOT support auto-pause — do not set `--auto-pause-delay`
3. **Status field**: Exists in DB/DAB/API but intentionally hidden from tax filer UI (all returns default to 'Draft')
4. **Status values**: Seed data uses statuses `Draft`, `In Progress`, `Filed`, `Accepted`, `Rejected`. The `GetExecutiveKPIs` proc counts all five. The "Returns by Status" section on the Executive Dashboard shows all five statuses with progress bars.
5. **DevOps Dashboard orphan**: `devops/Dashboard.tsx` exists on disk but is not routed in `App.tsx` — the `/devops` route renders `Metrics.tsx` directly. The Dashboard file has hardcoded system status values (latency, uptime).
6. **Mock users**: Demo mode uses localStorage-based mock users; production uses MSAL.js with Entra ID
