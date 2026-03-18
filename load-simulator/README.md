# ZavaTax Load Simulator

Comprehensive load testing suite for Azure SQL DB Hyperscale demonstrating realistic OLTP workflows and analytics workloads.

## Overview

This load simulator consists of two specialized test harnesses:

1. **OLTP Load Test** (`oltp/`) - Simulates realistic tax preparation workflow patterns
   - Complete workflow: Customer creation → Draft return → Edit cycles (0-5) → Final submission
   - Read/Write mix: Configurable percentage of read operations from HA read replica (ApplicationIntent=ReadOnly)
   - Uses stored procedures matching production frontend patterns
   - Multi-threaded parallel workers
   - Realistic customer and tax return data generation using Faker library
   - Demonstrates high transaction throughput with production-like patterns
   - Exercises both primary (write) and HA read replica (read) connections

2. **Analytics Load Test** (`analytics/`) - Demonstrates named replica auto-scaling with serverless compute
   - Multi-process concurrent query execution for true parallelism
   - Realistic query mix simulating branch manager dashboards and executive KPIs
   - Ramp-up mode for observing auto-scaling behavior (0 → 100 connections)
   - Real-time QPS, latency reporting, and error tracking

Both tools use Microsoft Entra authentication (no passwords), support local and Azure Container Apps execution, and work seamlessly with Azure SQL Database.

## Project Structure

```
load-simulator/
├── oltp/                    # OLTP workflow simulation
│   ├── main.py             # Main entry point with Click CLI
│   ├── config.py           # Configuration from environment
│   ├── data_generator.py   # Realistic workflow generation
│   └── db_worker.py        # Workflow execution via stored procedures
│
├── analytics/              # Analytics query load test
│   └── main.py            # Main entry point (multiprocessing)
│
├── shared/                 # Shared utilities
│   ├── metrics.py         # Performance metrics collection
│   └── monitor.py         # Monitoring utilities
│
├── infrastructure/         # Azure deployment
│   └── deploy.ps1         # Azure CLI deployment script
│
├── README.md              # This file
├── DEPLOYMENT_GUIDE.md    # Comprehensive deployment documentation
├── requirements.txt       # Python dependencies
├── .env.template         # Environment template
└── Dockerfile            # Container image
```

## Quick Start

### Prerequisites

```powershell
# Install Python dependencies
cd load-simulator
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt

# Login to Azure (for Microsoft Entra authentication)
az login

# Configure connection
Copy-Item .env.template .env
notepad .env  # Set SQL_SERVER and SQL_DATABASE

# Deploy OLTP stored procedures (required for oltp.main)
cd ..  # Navigate to ZavaTax root
sqlcmd -S <your-server>.database.windows.net -d zavatax -G -i database\06_oltp_procedures.sql
```

### OLTP Load Test (Workflow Simulation)

**⚠️ Prerequisites:** Deploy stored procedures first (see above) - the load test will validate on startup.

**Quick Start:**
```powershell
# Basic test: 10 workers, 5 minute duration, 30% reads from HA read replica
python -m oltp.main --workers 10 --duration 300

# High throughput: 20 workers, target 50 MB/s, 40% read mix
python -m oltp.main --workers 20 --duration 600 --target-mbps 50 --read-pct 40

# Read-heavy workload: 50% reads from HA read replica
python -m oltp.main --workers 15 --duration 300 --read-pct 50

# Short test with specific server/database
python -m oltp.main -s myserver.database.windows.net -d zavatax -w 5 -d 60
```

**Workflow Pattern:**

Each worker executes realistic workflows combining writes (primary) and reads (HA read replica):

**Write Operations (Primary connection):**
1. **AddCustomer** - Creates customer via stored procedure, returns CustomerId
2. **SaveTaxReturnDraft** - Creates draft tax return for customer
3. **UpdateTaxReturn** - Simulates 0-5 random edit cycles (weighted: most have 1-2 edits)
4. **SubmitTaxReturn** - Final submission, status changes to 'Filed'

**Read Operations (HA read replica with ApplicationIntent=ReadOnly):**
- **GetRecentTaxReturns** - View recent returns (TOP 20)
- **GetCustomersByProfessional** - View client list (TOP 50)
- **GetProfessionalsByBranch** - View team roster
- **GetReturnDetails** - View detailed return information

**Read/Write Mix:**
- Configurable via `--read-pct` parameter (default: 30%)
- Each workflow probabilistically executes 2-4 read operations
- Read operations interspersed throughout workflow (before writes, during edits, after submission)
- Simulates realistic user behavior: browsing/viewing before and after creating/editing
- Demonstrates Hyperscale's scale-out read capability with HA read replicas

**Command-Line Options:**
```
python -m oltp.main [OPTIONS]

Connection:
  -s, --server TEXT          SQL Server hostname (default: $env:SQL_SERVER or localhost)
  --database TEXT            Database name (default: $env:SQL_DATABASE or zavatax)

Load Configuration:
  -w, --workers INTEGER      Number of parallel workers (default: 10)
  -d, --duration INTEGER     Test duration in seconds (default: 300, 0 for unlimited)
  -r, --read-pct INTEGER     Percentage of operations that are reads from HA read replica (0-100, default: 30)
  -t, --target-mbps FLOAT    Target throughput in MB/s (default: 50)
```

**Required Database Objects:**

⚠️ **IMPORTANT**: The OLTP load test requires stored procedures from `database/06_oltp_procedures.sql`. Deploy these **before** running the load test:

**Stored Procedures:**
- `dbo.AddCustomer` - Customer creation (returns CustomerId)
- `dbo.SaveTaxReturnDraft` - Create/update draft return (returns ReturnId)
- `dbo.UpdateTaxReturn` - Edit return (partial updates)
- `dbo.SubmitTaxReturn` - Final submission (sets status to 'Filed')

**Deployment Options:**

**Option 1: Using sqlcmd (recommended)**
```powershell
# From the ZavaTax root directory
cd ..  # Navigate to ZavaTax root if you're in load-simulator
sqlcmd -S <your-server>.database.windows.net -d zavatax -G -i database\06_oltp_procedures.sql
```

**Option 2: Using Invoke-Sqlcmd with Az module**
```powershell
# Requires Az.Accounts module: Install-Module -Name Az.Accounts
Connect-AzAccount
Invoke-Sqlcmd -ServerInstance <your-server>.database.windows.net `
              -Database zavatax `
              -AccessToken (Get-AzAccessToken -ResourceUrl https://database.windows.net).Token `
              -InputFile ..\database\06_oltp_procedures.sql
```

**Option 3: Using Azure Data Studio or SSMS**
- Open `database/06_oltp_procedures.sql`
- Connect with Microsoft Entra authentication
- Execute the script

**Validation:**

The load simulator will automatically validate that procedures exist on startup. If missing, you'll see:
```
❌ ERROR: Missing Required Stored Procedures
Missing procedures: AddCustomer, SaveTaxReturnDraft, UpdateTaxReturn, SubmitTaxReturn

Please run:
  sqlcmd -S <server> -d <database> -G -i database/06_oltp_procedures.sql
```

**Example Configurations:**
- **Light Load (Testing)**: `python -m oltp.main -w 2 -b 50 -d 60`  (2 workers, 50 workflows each)
- **Medium Load**: `python -m oltp.main -w 10 -b 100 -d 300 -t 50`  (10 workers, 100 workflows each)
- **Heavy Load**: `python -m oltp.main -w 20 -b 200 -d 600 -t 50`  (20 workers, 200 workflows each)

**How It Works:**
1. **Workflow Generation** - Each worker generates realistic customer profiles and tax returns using Faker library
2. **Stored Procedure Calls** - Each workflow executes 3+ database procedures with autocommit enabled:
   - `AddCustomer` → get CustomerId (auto-commits)
   - `SaveTaxReturnDraft` → get ReturnId (auto-commits)
   - `UpdateTaxReturn` → 0-5 random edit cycles (each auto-commits)
   - `SubmitTaxReturn` → final submission (auto-commits)
3. **Connection Management** - Each worker maintains a single database connection reused across all workflows (prevents auth token exhaustion)
4. **Staggered Startup** - Workers start with 50ms delay between each to prevent auth token stampede
5. **Parallel Workers** - Multiple threads execute workflows concurrently for realistic load patterns
6. **OLTP Pattern** - Uses autocommit mode (standard OLTP practice) - each procedure call commits immediately

### Analytics Load Test (Named Replica)

**Quick Start:**
```powershell
# Set your named replica endpoint
$env:SQL_SERVER = "yourserver-analytics.database.windows.net"
$env:SQL_DATABASE = "zavatax"

# Basic test: 10 connections, 5 minutes
python -m analytics.main --connections 10 --duration 300

# Ramp-up test: Demonstrates auto-scaling (0 → 100 connections)
python -m analytics.main --ramp-up --max-connections 100 --duration 600 --ramp-up-interval 30

# Executive-heavy workload
python -m analytics.main --executive-heavy --connections 50 --duration 600
```

**Command-Line Options:**
```
python -m analytics.main [OPTIONS]

Connection:
  -s, --server TEXT          SQL Server hostname (default: $env:SQL_SERVER or localhost)
  -d, --database TEXT        Database name (default: $env:SQL_DATABASE or zavatax)

Load Configuration:
  -c, --connections INT      Number of parallel connections (default: 10)
  --duration INT             Test duration in seconds (default: 300)
  -t, --think-time INT       Milliseconds between queries (default: 100)

Ramp-Up Options:
  --ramp-up                  Enable gradual connection ramp-up
  --max-connections INT      Maximum connections for ramp-up (default: 100)
  --ramp-up-step INT         Connections to add per interval (default: 10)
  --ramp-up-interval INT     Seconds between ramp-up steps (default: 30)

Query Mix Presets:
  --executive-heavy          70% executive, 30% branch queries
  --branch-heavy             70% branch, 30% executive queries

Other:
  -v, --verbose              Verbose output
```

**Query Mix (Default Balanced):**
- **Branch Manager Queries (40%)**
  - GetBranchAnalytics (25%) - Branch performance with columnstore scan
  - GetBranchLeaderboard (15%) - Professional rankings
- **Executive Queries (40%)**
  - GetExecutiveKPIs (20%) - Company-wide KPIs (full columnstore scan)
  - GetTopBranches (15%) - Top performing branches
  - GetFilingStatusDistribution (5%) - Filing status breakdown
- **Trend Analysis (10%)** - GetReturnsByYear - Multi-year trends
- **System Monitoring (10%)** - GetHyperscaleResourceStats - Resource utilization

**How It Works:**
1. **Connection** - Each worker process creates its own connection using Azure AD authentication
2. **Query Selection** - Queries randomly selected based on configured weights
3. **Execution** - Worker executes query, fetches all results, records timing
4. **Think Time** - Brief pause simulates user reading results (configurable)
5. **Statistics** - Main process collects stats and reports progress every 10 seconds

**Console Output Example:**
```
======================================================================
Elapsed: 120.5s | Queries: 2,847 | QPS: 23.62 | Errors: 0 (0.00%)
======================================================================
Query                              Count     Avg (ms)     Errors
----------------------------------------------------------------------
GetBranchAnalytics                   712       285.42          0
GetExecutiveKPIs                     568      1842.67          0
...
```

## Authentication & Execution

### Microsoft Entra Authentication (No Passwords!)

Both tests use Azure Default Credential chain:
- **Local**: Uses `az login` credentials (Azure CLI)
- **Containers**: Uses managed identity
- **Environment**: Can use service principal via environment variables

No passwords or connection strings with credentials in code or configuration.

### Execution Modes

| Aspect | Local Execution | Azure Container Apps |
|--------|----------------|---------------------|
| **Setup** | Simple - Python + pip install | Container build & Azure deployment |
| **Authentication** | `az login` (Azure CLI) | Managed Identity |
| **Cost** | $0 (existing SQL only) | Container Apps charges (~$0.08/10 min) |
| **Scalability** | Single machine | Horizontal scale (multiple replicas) |
| **Best For** | Development, testing, demos, < 50 MB/s | High throughput (100+ MB/s), stress testing |

**Local Execution (Recommended for most scenarios):**
- ✅ Works seamlessly with Azure SQL Database (not just localhost)
- ✅ Uses your Azure CLI credentials (`az login`) - no passwords needed
- ✅ Zero cost (free compute, SQL charges only)
- ✅ Easier to control, monitor, and debug
- ✅ Perfect for development, testing, demos, and analytics tests
- ✅ Handles OLTP up to ~50 MB/s throughput

**Azure Container Apps (For high-scale OLTP testing):**
- ✅ Deploy when you need 100+ MB/s throughput
- ✅ Scale-out with multiple replicas (3-5 replicas for higher throughput)
- ✅ Uses managed identity (passwordless authentication)
- ✅ Automated and long-running tests
- ⚠️ Analytics tests: Local execution strongly recommended (multiprocessing handles concurrency excellently)

**Throughput Recommendations (OLTP):**
- **< 50 MB/s**: Use local execution (10-20 workers, 100-200 workflows per worker)
- **50-100 MB/s**: Local on powerful machine or 1-2 container replicas (20-30 workers)
- **100+ MB/s**: 3-5 container replicas (30-50 workers/replica)

**Note:** Workflow-based load is slower than bulk inserts but more realistic. Each workflow includes multiple procedure calls (customer creation, draft, 0-5 edits, submission).

**Both modes support the exact same features and command-line options.**

## Environment Variables

Configure via `.env` file or environment:

```properties
# Database Connection (uses Microsoft Entra Default auth)
SQL_SERVER=yourserver.database.windows.net
SQL_DATABASE=zavatax
AZURE_CLIENT_ID=<optional-managed-identity-client-id>

# OLTP Load Configuration
NUM_WORKERS=10
BATCHES_PER_WORKER=100        # Workflows per worker (not rows)
READ_PERCENTAGE=30             # % of operations that are reads from HA read replica
DURATION_SECONDS=300
TARGET_THROUGHPUT_MBPS=50

# Data Generation (OLTP)
NUM_BRANCHES=500
NUM_PROFESSIONALS=2000
NUM_CUSTOMERS=100000
```

## Usage Scenarios

### Scenario 1: HTAP Demo (OLTP + Analytics)

**Setup**: Run OLTP load against primary, analytics queries against named replica

```powershell
# Terminal 1: OLTP load (writes to primary + reads from HA read replica)
$env:SQL_SERVER = "myserver.database.windows.net"
python -m oltp.main -w 15 -d 600 --read-pct 30

# Terminal 2: Analytics on named replica
$env:SQL_SERVER = "myserver-analytics.database.windows.net"
python -m analytics.main -c 25 -d 600
```

**Demonstrates**: Workload isolation - analytics queries don't impact write performance

### Scenario 2: Serverless Auto-Scaling

**Setup**: Named replica with serverless compute (0.5 min → 8 max vCores)

```powershell
# Ramp-up test
python -m analytics.main --ramp-up --max-connections 100 --duration 600 --ramp-up-interval 30
```

**Observe**: In Azure Portal, watch vCore usage scale from 0.5 → 8 as connections ramp up

### Scenario 3: Log Throughput Stress Test

**Setup**: Multiple Container Apps replicas for maximum throughput

```powershell
# Deploy with high replica count for heavy load
az containerapp update `
  --name zavatax-load-simulator `
  --min-replicas 5 `
  --max-replicas 5 `
  --set-env-vars NUM_WORKERS=30 TARGET_THROUGHPUT_MBPS=100 DURATION_SECONDS=600
```

**Monitor**: Azure Portal → SQL Database → Metrics → "Log write throughput"

## Container Deployment (Azure)

### Quick Deploy with Azure CLI

```powershell
# Deploy OLTP load test to Azure Container Apps
.\infrastructure\deploy.ps1 `
  -SqlServer yourserver.database.windows.net `
  -AcrName youracr `
  -Replicas 3 `
  -NumWorkers 10

# Deploy Analytics load test
.\infrastructure\deploy.ps1 `
  -Mode analytics `
  -SqlServer yourserver-replica.database.windows.net `
  -AcrName youracr `
  -Connections 50

# Local execution setup (creates .env file)
.\infrastructure\deploy.ps1 `
  -SqlServer yourserver.database.windows.net `
  -LocalOnly
```

See [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for comprehensive deployment documentation including:
- Prerequisites and setup
- Deployment parameters
- Post-deployment SQL permissions
- Container monitoring
- Troubleshooting
- Cost considerations

### Grant SQL Permissions (For Containers)

When deploying to Azure Container Apps, grant the managed identity SQL permissions:

```sql
-- Connect to your Azure SQL Database
CREATE USER [zavatax-load-simulator-identity] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datawriter ADD MEMBER [zavatax-load-simulator-identity];
ALTER ROLE db_datareader ADD MEMBER [zavatax-load-simulator-identity];
GRANT EXECUTE ON SCHEMA::dbo TO [zavatax-load-simulator-identity];
```

**Note:** The deployment script outputs the exact SQL command needed!

## Monitoring

### OLTP Metrics

**Console output:** Structured logs via structlog showing throughput, operations/sec, and workflow statistics

### Analytics Metrics

**Real-time console statistics (every 10 seconds):**
```
======================================================================
Elapsed: 120.5s | Queries: 2,847 | QPS: 23.62 | Errors: 0 (0.00%)
======================================================================
Query                              Count     Avg (ms)     Errors
----------------------------------------------------------------------
GetBranchAnalytics                   712       285.42          0
GetExecutiveKPIs                     568      1842.67          0
...
```

### Azure SQL Metrics (Azure Portal)

Navigate to: **SQL Database → Monitoring → Metrics**

**For OLTP:**
- Log write throughput (MB/s) - Shows transaction log throughput
- Workers percentage - Database DTU/vCore utilization
- CPU percentage

**For Analytics (Named Replica):**
- CPU percentage
- vCore usage - Watch serverless scaling in real-time
- Active connections

## Performance Expectations

### OLTP Load Test

| Workers | Workflows/Worker | Target MB/s | Actual MB/s | SQL vCores | Notes |
|---------|------------------|-------------|-------------|------------|-------|
| 5       | 100              | 25          | 20-30       | 4          | Light load, testing |
| 10      | 100-200          | 50          | 40-55       | 8          | Recommended starting point |
| 20      | 150-200          | 75          | 65-85       | 16         | Medium-heavy load |
| 30+     | 200              | 100+        | 90-120      | 24-32      | Heavy load, realistic workflows |

**Note:** Workflow-based load generates 3+ procedure calls per workflow (AddCustomer, SaveTaxReturnDraft, 0-5 edits, SubmitTaxReturn). Throughput is lower than bulk inserts but patterns are more realistic.

### Analytics Load Test

| Connections | Query Mix | Expected QPS | Expected CPU | Scaling Time |
|-------------|-----------|--------------|--------------|--------------|
| 10          | Balanced  | 8-15         | 10-20%       | Immediate    |
| 25          | Balanced  | 20-40        | 30-50%       | 1-2 min      |
| 50          | Executive | 30-60        | 60-80%       | 2-3 min      |
| 100         | Executive | 50-100       | 90-100%      | 3-5 min      |

## Database Requirements

Both tests require the ZavaTax database schema created by [database/01_create_schema.sql](../database/01_create_schema.sql):

**Tables:**
- `TaxReturns`, `Branches`, `TaxProfessionals`, `Customers`
- Columnstore index on `TaxReturns` (for analytics performance)

**Stored Procedures:**
- **OLTP**: `AddCustomer`, `SaveTaxReturnDraft`, `UpdateTaxReturn`, `SubmitTaxReturn` (workflow procedures in [database/06_oltp_procedures.sql](../database/06_oltp_procedures.sql))
- **Analytics**: `GetBranchAnalytics`, `GetExecutiveKPIs`, `GetTopBranches`, `GetReturnsByYear`, etc.

**Permissions:**
- `db_datawriter` role (OLTP)
- `db_datareader` role (Analytics)
- `EXECUTE` on schema `dbo`

## Troubleshooting

### Connection Issues

**Error: "Login timeout expired" or "Cannot connect"**
- Check Azure SQL firewall rules: `az sql server firewall-rule create ...`
- Verify network connectivity to Azure SQL
- Ensure you're in the same region (or have good network path)

**Error: "AADSTS50020: User account not found" or authentication failed**
- Run `az login` to refresh credentials
- Verify: `az account show` to confirm correct subscription
- Check that the database user exists (for containers)

### Performance Issues

**OLTP not reaching target throughput:**
1. Check if stored procedures are deployed: The simulator validates on startup
2. Check SQL metrics - is log throughput at Azure SQL limit?
3. Increase workers (`--workers 30`) - workflow approach benefits more from concurrency
4. Verify network co-location (deploy Container Apps in same region as SQL)
5. Check for blocking operations: `SELECT * FROM sys.dm_exec_requests WHERE blocking_session_id > 0`

**OLTP showing zero progress (no operations):**
1. Ensure stored procedures are deployed: `sqlcmd -S <server> -d <database> -G -i database\06_oltp_procedures.sql`
2. Check logs for "Missing Required Stored Procedures" error
3. Verify database permissions: User needs `db_datawriter` and `EXECUTE` on schema `dbo`

**Analytics queries slow:**
1. Verify columnstore indexes exist: `SELECT * FROM sys.column_store_row_groups`
2. Update statistics: `UPDATE STATISTICS TaxReturns WITH FULLSCAN`
3. Check if named replica is paused (serverless) - first query may be slower
4. Ensure sufficient data exists for meaningful query results

**Python errors or import failures:**
- Ensure virtual environment is activated
- Install dependencies: `pip install -r requirements.txt`
- Check Python version: requires Python 3.10+

## Dependencies

See [requirements.txt](requirements.txt) for full list:

- **mssql-python** - Native SQL Server driver with Azure AD authentication
- **structlog** - Structured logging (OLTP)
- **Faker** - Realistic test data generation (OLTP)
- **click** - CLI interface (OLTP)

## Best Practices

1. **Start Small** - Begin with low worker/connection counts to validate connectivity
2. **Monitor First** - Open Azure Portal metrics dashboard before starting tests
3. **Use Named Replicas** - Route analytics queries to named replicas for workload isolation
4. **Co-locate** - Deploy in same Azure region as SQL database for best performance
5. **Clean Up** - Truncate `TaxReturns` table between major test runs to reset data
6. **Test Locally First** - Use local execution with `az login` before deploying containers

## Additional Documentation

- **[DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)** - Comprehensive deployment guide (local and Azure)
- **[Dockerfile](Dockerfile)** - Container image definition
- **[requirements.txt](requirements.txt)** - Python dependencies

## License

Part of the ZavaTax demonstration application for Azure SQL DB Hyperscale.
