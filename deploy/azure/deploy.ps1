<#
.SYNOPSIS
    Deploys the ZavaTax application to Azure.

.DESCRIPTION
    This script deploys all Azure infrastructure and application code for ZavaTax.
    Uses Azure CLI commands directly for each resource (no Bicep required).
    Uses Entra-only authentication for SQL Server (no SQL passwords required).

.PARAMETER Environment
    Target environment (dev, staging, prod). Default: dev

.PARAMETER Location
    Azure region for deployment. Default: eastus2

.PARAMETER BaseName
    Base name for resources. Default: zavatax

.PARAMETER ResourceGroupName
    Resource group name. If not specified, will be generated as "rg-{BaseName}-{Environment}"

.PARAMETER SkipInfrastructure
    Skip infrastructure deployment, only deploy application code.

.PARAMETER SkipDatabase
    Skip database schema deployment.

.PARAMETER SkipWebApp
    Skip web application deployment.

.EXAMPLE
    .\deploy.ps1 -Environment dev -Location eastus2

.EXAMPLE
    .\deploy.ps1 -Environment prod -SkipDatabase

.NOTES
    Prerequisites:
    - Azure CLI installed and logged in (az login)
    - PowerShell 7+ recommended
    - Node.js 18+ for webapp build
    
    Authentication:
    - Uses Entra-only authentication for SQL Server
    - Current logged-in user becomes SQL admin
    - Managed Identity used for app-to-database connections
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'dev',

    [Parameter()]
    [string]$Location = 'eastus2',

    [Parameter()]
    [string]$BaseName = 'zavatax',

    [Parameter()]
    [string]$ResourceGroupName,

    [Parameter()]
    [string]$SqlAadAdminObjectId,

    [Parameter()]
    [string]$SqlAadAdminName,

    [Parameter()]
    [string]$Owner,

    [Parameter()]
    [string]$CreatedBy,

    [Parameter()]
    [ValidateSet('B1', 'B2', 'B3', 'S1', 'S2', 'S3', 'P1v3', 'P2v3', 'P3v3')]
    [string]$AppServiceSku = 'B2',

    [Parameter()]
    [ValidateSet('HS_PRMS_2', 'HS_PRMS_4', 'HS_PRMS_6', 'HS_PRMS_8', 'HS_PRMS_10', 'HS_PRMS_12', 'HS_PRMS_14', 'HS_PRMS_16', 'HS_PRMS_18', 'HS_PRMS_20', 'HS_PRMS_24', 'HS_PRMS_32', 'HS_PRMS_40', 'HS_PRMS_64', 'HS_PRMS_80', 'HS_MOPRMS_4', 'HS_MOPRMS_6', 'HS_MOPRMS_8', 'HS_MOPRMS_10', 'HS_MOPRMS_12', 'HS_MOPRMS_14', 'HS_MOPRMS_16', 'HS_MOPRMS_18', 'HS_MOPRMS_20', 'HS_MOPRMS_24', 'HS_MOPRMS_32', 'HS_MOPRMS_40', 'HS_MOPRMS_64', 'HS_MOPRMS_80')]
    [string]$SqlDatabaseSku = 'HS_PRMS_4',

    [Parameter()]
    [switch]$DeployOpenAI,

    [Parameter()]
    [string]$OpenAILocation,

    [Parameter()]
    [ValidateSet('gpt-5.2-chat', 'gpt-4o', 'gpt-4o-mini', 'gpt-4', 'gpt-4-turbo', 'gpt-35-turbo', 'text-embedding-ada-002', 'text-embedding-3-small', 'text-embedding-3-large')]
    [string]$OpenAIModelName = 'gpt-5.2-chat',

    [Parameter()]
    [string]$OpenAIModelVersion = '2025-01-15',

    [Parameter()]
    [int]$OpenAICapacity = 30,

    [Parameter()]
    [switch]$SkipInfrastructure,

    [Parameter()]
    [switch]$SkipDatabase,

    [Parameter()]
    [switch]$SkipWebApp
)

$ErrorActionPreference = 'Stop'

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║ $($Message.PadRight(64)) ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([string]$Message)
    Write-Host "▶ $Message" -ForegroundColor Yellow
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor Gray
}

function Invoke-Az {
    <#
    .SYNOPSIS
        Runs an az CLI command and prints the full command on failure.
    .PARAMETER Command
        The full az command string to execute.
    .PARAMETER ErrorMessage
        Friendly error message for the throw. If omitted, defaults to "az command failed".
    .PARAMETER NoThrow
        If set, logs a warning instead of throwing on failure.
    #>
    param(
        [Parameter(Mandatory)][string]$Command,
        [string]$ErrorMessage,
        [switch]$NoThrow
    )
    
    # Execute
    Invoke-Expression $Command
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "  ╭─ FAILED COMMAND ──────────────────────────────────────────────" -ForegroundColor Red
        Write-Host "  │ $Command" -ForegroundColor Red
        Write-Host "  ╰──────────────────────────────────────────────────────────────" -ForegroundColor Red
        Write-Host ""
        
        if ($NoThrow) {
            Write-Warning ($ErrorMessage ?? "az command failed (non-fatal)")
        } else {
            throw ($ErrorMessage ?? "az command failed")
        }
    }
}

function Test-AzureCli {
    try {
        $null = az --version 2>&1
        return $true
    } catch {
        return $false
    }
}

function Get-AzureContext {
    $account = az account show 2>$null | ConvertFrom-Json
    if (-not $account) {
        throw "Not logged in to Azure. Please run 'az login' first."
    }
    return $account
}

function Remove-SensitiveFiles {
    <#
    .SYNOPSIS
        Removes sensitive local development files that should not be deployed.
    .DESCRIPTION
        Deletes files matching patterns for credentials and local configuration:
        - *.actual.sql (real API keys/credentials)
        - *.actual.json (real config values)
        - .env files (except .env.template)
        - *.local files
    #>
    param(
        [string]$RootPath = (Get-Location)
    )
    
    Write-Step "Cleaning up sensitive local files..."
    
    $patterns = @(
        "*.actual.sql",
        "*.actual.json",
        ".env",
        ".env.local",
        ".env.development",
        ".env.production",
        "*.local"
    )
    
    $excludePatterns = @(
        "*.template",
        "*.example",
        ".env.template",
        ".env.example"
    )
    
    $removedCount = 0
    
    foreach ($pattern in $patterns) {
        $files = Get-ChildItem -Path $RootPath -Filter $pattern -Recurse -File -ErrorAction SilentlyContinue | 
                 Where-Object { 
                     $excluded = $false
                     foreach ($excludePattern in $excludePatterns) {
                         if ($_.Name -like $excludePattern) {
                             $excluded = $true
                             break
                         }
                     }
                     -not $excluded
                 }
        
        foreach ($file in $files) {
            try {
                $relativePath = $file.FullName.Replace($RootPath, "").TrimStart("\", "/")
                Write-Info "  Removing: $relativePath"
                Remove-Item -Path $file.FullName -Force
                $removedCount++
            } catch {
                Write-Warning "  Failed to remove $($file.Name): $_"
            }
        }
    }
    
    if ($removedCount -eq 0) {
        Write-Info "  No sensitive files found"
    } else {
        Write-Success "Removed $removedCount sensitive file(s)"
    }
}

# ============================================================================
# VALIDATION
# ============================================================================

Write-Header "ZavaTax Azure Deployment"

Write-Step "Validating prerequisites..."

# Check Azure CLI
if (-not (Test-AzureCli)) {
    throw "Azure CLI is not installed. Please install it from https://docs.microsoft.com/cli/azure/install-azure-cli"
}
Write-Info "Azure CLI: OK"

# Check Azure login
$azContext = Get-AzureContext
Write-Info "Logged in as: $($azContext.user.name)"
Write-Info "Subscription: $($azContext.name) ($($azContext.id))"
Write-Info "Tenant: $($azContext.tenantId)"

# Normalize environment to lowercase
$Environment = $Environment.ToLower()

# Generate resource group name if not provided
if (-not $ResourceGroupName) {
    $ResourceGroupName = "rg-$BaseName-$Environment"
}
Write-Info "Resource Group: $ResourceGroupName"

# Get current user info for SQL AAD admin if not provided
if (-not $SqlAadAdminObjectId) {
    Write-Step "Getting current user information for SQL Entra admin..."
    $currentUser = az ad signed-in-user show 2>$null | ConvertFrom-Json
    if ($currentUser) {
        $SqlAadAdminObjectId = $currentUser.id
        $SqlAadAdminName = $currentUser.displayName
        Write-Info "Using current user as SQL Entra admin: $SqlAadAdminName"
    } else {
        throw "Could not get current user info. Please provide -SqlAadAdminObjectId and -SqlAadAdminName parameters."
    }
}

# Set default tags if not provided
if (-not $Owner) {
    $Owner = $azContext.user.name
}
if (-not $CreatedBy) {
    $CreatedBy = $azContext.user.name
}

Write-Success "Prerequisites validated"

# ============================================================================
# CLEANUP SENSITIVE FILES
# ============================================================================

# Remove local development files with real credentials before deployment
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Remove-SensitiveFiles -RootPath $repoRoot

# ============================================================================
# RESOURCE NAMING
# ============================================================================

# Use SHA256 of the RG name for a stable, deterministic suffix.
# Always hash the RG name (not the RG ID) so the suffix is identical whether
# the RG already exists or is about to be created on first run.
$bytes = [System.Text.Encoding]::UTF8.GetBytes($ResourceGroupName)
$hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
$uniqueSuffix = [BitConverter]::ToString($hash).Replace('-', '').Substring(0, 8).ToLower()

$resourcePrefix = "$BaseName-$Environment"

# Detect Drift: Check if a SQL Server already exists with this prefix but different suffix
# This handles cases where the hash algorithm changed or randomness occurred in previous deployments
try {
    # Find any SQL server in this RG matching "basename-env-sql-*"
    $existingServerName = az sql server list --resource-group $ResourceGroupName --query "[?starts_with(name, '${resourcePrefix}-sql-')].name | [0]" -o tsv 2>$null
    
    if (-not [string]::IsNullOrWhiteSpace($existingServerName)) {
        # Extract suffix (everything after the prefix and "-sql-")
        $prefixPattern = [Regex]::Escape("$resourcePrefix-sql-")
        $existingSuffix = $existingServerName -replace "^$prefixPattern", ""
        
        if (-not [string]::IsNullOrWhiteSpace($existingSuffix) -and $existingSuffix -ne $uniqueSuffix) {
            Write-Warning "Resource Drift Detected!"
            Write-Warning "  Computed suffix: '$uniqueSuffix' (based on RG ID hash)"
            Write-Warning "  Existing suffix: '$existingSuffix' (found on SQL Server '$existingServerName')"
            Write-Warning "  Aligning deployment to use existing suffix '$existingSuffix' to avoid creating duplicates."
            $uniqueSuffix = $existingSuffix
        }
    }
} catch {
    # Ignore errors during drift detection
}

# --- Build candidate (suffixed) names for all resources ---
$identityNameSuffixed = "$resourcePrefix-identity-$uniqueSuffix"
$identityNameLegacy = "$resourcePrefix-identity"
$sqlServerName = "$resourcePrefix-sql-$uniqueSuffix"
$sqlDatabaseName = "${BaseName}db"
$appServicePlanName = "$resourcePrefix-plan-$uniqueSuffix"
$appServicePlanNameLegacy = "$resourcePrefix-plan"
$webAppName = "$resourcePrefix-web-$uniqueSuffix"
$dabAppName = "$resourcePrefix-dab-$uniqueSuffix"
$acrNameSuffixed = ("${BaseName}${Environment}acr${uniqueSuffix}".ToLower() -replace '[^a-z0-9]', '')
$acrNameLegacy = ("${BaseName}${Environment}acr".ToLower() -replace '[^a-z0-9]', '')
$namedReplicaDbName = "${sqlDatabaseName}-analytics"
# Storage account names: max 24 chars, alphanumeric only → use first 6 chars of suffix
$storageSuffix = $uniqueSuffix.Substring(0, 6)
$storageAccountNameSuffixed = ("${BaseName}${Environment}data${storageSuffix}".ToLower() -replace '[^a-z0-9]', '').Substring(0, [Math]::Min(("${BaseName}${Environment}data${storageSuffix}".ToLower() -replace '[^a-z0-9]', '').Length, 24))
$storageAccountNameLegacy = ("${BaseName}${Environment}data".ToLower() -replace '[^a-z0-9]', '')
$openAIServiceNameSuffixed = "oai-$BaseName-$Environment-$uniqueSuffix"
$openAIServiceNameLegacy = "oai-$BaseName-$Environment"
$storageContainerName = "csvdata"

# --- Legacy resource detection ---
# For each newly-suffixed resource type, check if the old (non-suffixed) name already exists
# in the resource group. If so, reuse it to avoid breaking existing deployments.

Write-Step "Checking for existing (legacy) resource names in '$ResourceGroupName'..."

# Managed Identity
$identityName = $identityNameSuffixed
try {
    $legacyIdentity = az identity show --name $identityNameLegacy --resource-group $ResourceGroupName 2>$null | ConvertFrom-Json
    if ($legacyIdentity) {
        Write-Info "  Found legacy identity '$identityNameLegacy' — reusing"
        $identityName = $identityNameLegacy
    }
} catch { }

# Container Registry (global name, check existence by name)
$acrName = $acrNameSuffixed
try {
    $legacyAcr = az acr show --name $acrNameLegacy --resource-group $ResourceGroupName 2>$null | ConvertFrom-Json
    if ($legacyAcr) {
        Write-Info "  Found legacy ACR '$acrNameLegacy' — reusing"
        $acrName = $acrNameLegacy
    }
} catch { }

# Storage Account (global name, check existence by name)
$storageAccountName = $storageAccountNameSuffixed
try {
    $legacyStorage = az storage account show --name $storageAccountNameLegacy --resource-group $ResourceGroupName 2>$null | ConvertFrom-Json
    if ($legacyStorage) {
        Write-Info "  Found legacy storage account '$storageAccountNameLegacy' — reusing"
        $storageAccountName = $storageAccountNameLegacy
    }
} catch { }

# Azure OpenAI (check existence by name)
$openAIServiceName = $openAIServiceNameSuffixed
try {
    $legacyOAI = az cognitiveservices account show --name $openAIServiceNameLegacy --resource-group $ResourceGroupName 2>$null | ConvertFrom-Json
    if ($legacyOAI) {
        Write-Info "  Found legacy OpenAI service '$openAIServiceNameLegacy' — reusing"
        $openAIServiceName = $openAIServiceNameLegacy
    }
} catch { }

# App Service Plan
$appServicePlanName = "$resourcePrefix-plan-$uniqueSuffix"
try {
    $legacyPlan = az appservice plan show --name $appServicePlanNameLegacy --resource-group $ResourceGroupName 2>$null | ConvertFrom-Json
    if ($legacyPlan) {
        Write-Info "  Found legacy App Service Plan '$appServicePlanNameLegacy' — reusing"
        $appServicePlanName = $appServicePlanNameLegacy
    }
} catch { }

Write-Info "Resource naming:"
Write-Info "  Identity: $identityName"
Write-Info "  SQL Server: $sqlServerName"
Write-Info "  App Service Plan: $appServicePlanName"
Write-Info "  Web App: $webAppName"
Write-Info "  DAB App Service: $dabAppName"
Write-Info "  Container Registry: $acrName"
Write-Info "  Storage Account: $storageAccountName"
Write-Info "  Storage Container: $storageContainerName"
Write-Info "  OpenAI Service: $openAIServiceName"

# ============================================================================
# INFRASTRUCTURE DEPLOYMENT
# ============================================================================

$schemaDeployed = $false

if (-not $SkipInfrastructure) {
    Write-Header "Deploying Azure Infrastructure"

    # --- Resource Group ---
    Write-Step "Creating resource group '$ResourceGroupName'..."
    az group create `
        --name $ResourceGroupName `
        --location $Location `
        --tags "Environment=$Environment" "Owner=$Owner" "CreatedBy=$CreatedBy" "Application=ZavaTax" `
        --output none
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  FAILED CMD: az group create --name $ResourceGroupName --location $Location --output none" -ForegroundColor Red
        throw "Failed to create resource group"
    }
    Write-Success "Resource group created"

    # --- Detect Availability Zone Support ---
    $zones = az account list-locations --query "[?name=='$Location'].availabilityZoneMappings[]" -o json 2>$null | ConvertFrom-Json
    $hasZones = ($zones -and $zones.Count -gt 0)
    if ($hasZones) {
        Write-Info "Region '$Location' supports availability zones — using zone-redundant SKUs"
    } else {
        Write-Info "Region '$Location' does not support availability zones — using geo-redundant SKUs"
    }

    # --- User-Assigned Managed Identity ---
    Write-Step "Creating managed identity '$identityName'..."
    $identity = az identity create `
        --name $identityName `
        --resource-group $ResourceGroupName `
        --location $Location | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  FAILED CMD: az identity create --name $identityName --resource-group $ResourceGroupName --location $Location" -ForegroundColor Red
        throw "Failed to create managed identity"
    }
    $identityId = $identity.id
    $identityClientId = $identity.clientId
    $identityPrincipalId = $identity.principalId
    Write-Success "Managed identity created (Client ID: $identityClientId)"

    # --- Storage Account for CSV Data ---
    $storageSku = if ($hasZones) { "Standard_ZRS" } else { "Standard_GRS" }
    Write-Step "Creating Storage Account '$storageAccountName' ($storageSku)..."
    az storage account create `
        --name $storageAccountName `
        --resource-group $ResourceGroupName `
        --location $Location `
        --sku $storageSku `
        --kind StorageV2 `
        --allow-blob-public-access false `
        --allow-shared-key-access false `
        --min-tls-version TLS1_2 `
        --output none
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  FAILED CMD: az storage account create --name $storageAccountName --resource-group $ResourceGroupName --location $Location --sku $storageSku" -ForegroundColor Red
        throw "Failed to create Storage Account"
    }
    Write-Success "Storage Account created ($storageSku)"

    # Create blob container
    Write-Step "Creating blob container '$storageContainerName'..."
    az storage container create `
        --name $storageContainerName `
        --account-name $storageAccountName `
        --auth-mode login `
        --output none
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  FAILED CMD: az storage container create --name $storageContainerName --account-name $storageAccountName --auth-mode login" -ForegroundColor Red
        throw "Failed to create blob container"
    }
    Write-Success "Blob container created"

    # Assign Storage Blob Data Reader role to managed identity
    Write-Step "Assigning Storage Blob Data Reader role to managed identity..."
    $storageAccountId = az storage account show --name $storageAccountName --resource-group $ResourceGroupName --query id -o tsv
    az role assignment create `
        --assignee-object-id $identityPrincipalId `
        --assignee-principal-type ServicePrincipal `
        --role "Storage Blob Data Reader" `
        --scope $storageAccountId `
        --output none
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  FAILED CMD: az role assignment create --assignee-object-id $identityPrincipalId --role 'Storage Blob Data Reader' --scope $storageAccountId" -ForegroundColor Red
        Write-Warning "Failed to assign Storage Blob Data Reader role - may already exist"
    }
    Write-Success "Storage Blob Data Reader role assigned to managed identity"

    # Get storage account blob endpoint for later use
    $storageBlobEndpoint = az storage account show --name $storageAccountName --resource-group $ResourceGroupName --query "primaryEndpoints.blob" -o tsv
    Write-Info "Blob endpoint: $storageBlobEndpoint"

    # --- App Service Plan ---
    Write-Step "Creating App Service Plan '$appServicePlanName'..."
    az appservice plan create `
        --name $appServicePlanName `
        --resource-group $ResourceGroupName `
        --location $Location `
        --sku $AppServiceSku `
        --is-linux `
        --output none
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  FAILED CMD: az appservice plan create --name $appServicePlanName --resource-group $ResourceGroupName --location $Location --sku $AppServiceSku --is-linux" -ForegroundColor Red
        throw "Failed to create App Service Plan"
    }
    Write-Success "App Service Plan created"

    # --- SQL Server (Entra-only auth) ---
    Write-Step "Creating SQL Server '$sqlServerName' with Entra-only auth..."
    az sql server create `
        --name $sqlServerName `
        --resource-group $ResourceGroupName `
        --location $Location `
        --enable-ad-only-auth `
        --external-admin-principal-type User `
        --external-admin-name $SqlAadAdminName `
        --external-admin-sid $SqlAadAdminObjectId `
        --assign-identity `
        --identity-type UserAssigned `
        --user-assigned-identity-id $identityId `
        --primary-user-assigned-identity-id $identityId `
        --output none
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  FAILED CMD: az sql server create --name $sqlServerName --resource-group $ResourceGroupName --location $Location --enable-ad-only-auth --external-admin-name $SqlAadAdminName" -ForegroundColor Red
        throw "Failed to create SQL Server"
    }
    Write-Success "SQL Server created with Entra-only authentication and managed identity"

    # Get SQL Server FQDN
    $sqlServerFqdn = az sql server show --name $sqlServerName --resource-group $ResourceGroupName --query fullyQualifiedDomainName -o tsv

    # --- SQL Server Firewall: Allow Azure Services ---
    Write-Step "Configuring SQL Server firewall..."
    az sql server firewall-rule create `
        --server $sqlServerName `
        --resource-group $ResourceGroupName `
        --name "AllowAzureServices" `
        --start-ip-address 0.0.0.0 `
        --end-ip-address 0.0.0.0 `
        --output none
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  FAILED CMD: az sql server firewall-rule create --server $sqlServerName --resource-group $ResourceGroupName --name AllowAzureServices --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0" -ForegroundColor Red
        Write-Warning "Failed to add Azure services firewall rule"
    }

    # Add local IP for dev environment
    if ($Environment -eq 'dev') {
        try {
            $localIp = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 5)
            Write-Info "Adding firewall rule for local IP: $localIp"
            az sql server firewall-rule create `
                --server $sqlServerName `
                --resource-group $ResourceGroupName `
                --name "AllowLocalDev" `
                --start-ip-address $localIp `
                --end-ip-address $localIp `
                --output none 2>$null
        } catch {
            Write-Info "Could not detect local IP - add firewall rule manually if needed"
        }
    }
    Write-Success "SQL Server firewall configured"

    # --- SQL Database (Hyperscale with HA) ---
    $sqlZoneRedundant = if ($hasZones) { "true" } else { "false" }
    $sqlBackupRedundancy = if ($hasZones) { "GeoZone" } else { "Geo" }
    Write-Step "Creating SQL Database '$sqlDatabaseName' (Hyperscale, zone-redundant=$sqlZoneRedundant, backup=$sqlBackupRedundancy, 1 HA replica)..."
    az sql db create `
        --name $sqlDatabaseName `
        --server $sqlServerName `
        --resource-group $ResourceGroupName `
        --service-objective $SqlDatabaseSku `
        --zone-redundant $sqlZoneRedundant `
        --backup-storage-redundancy $sqlBackupRedundancy `
        --ha-replicas 1 `
        --read-scale Enabled `
        --output none
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  FAILED CMD: az sql db create --name $sqlDatabaseName --server $sqlServerName --resource-group $ResourceGroupName --service-objective $SqlDatabaseSku --zone-redundant $sqlZoneRedundant --backup-storage-redundancy $sqlBackupRedundancy" -ForegroundColor Red
        throw "Failed to create SQL Database"
    }
    Write-Success "SQL Database created (zone-redundant=$sqlZoneRedundant, backup=$sqlBackupRedundancy, 1 HA replica)"

    # --- Hyperscale Named Replica (for analytical / HTAP workloads) ---
    Write-Step "Creating Hyperscale Named Replica '$namedReplicaDbName' (serverless, max 24 vCores)..."
    Write-Info "Named replica offloads analytical queries (CCI scans, aggregations) from the primary"
    az sql db replica create `
        --name $sqlDatabaseName `
        --server $sqlServerName `
        --resource-group $ResourceGroupName `
        --partner-database $namedReplicaDbName `
        --partner-server $sqlServerName `
        --partner-resource-group $ResourceGroupName `
        --secondary-type Named `
        --family Gen5 `
        --capacity 24 `
        --compute-model Serverless `
        --ha-replicas 0 `
        --read-scale Disabled `
        --output none
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  FAILED CMD: az sql db replica create --name $sqlDatabaseName --server $sqlServerName --partner-database $namedReplicaDbName --secondary-type Named --family Gen5 --capacity 24 --compute-model Serverless" -ForegroundColor Red
        throw "Failed to create named replica"
    }
    Write-Success "Named replica created: $namedReplicaDbName (serverless, max 24 vCores)"

    # -----------------------------------------------------------------------
    # Deploy database schema BEFORE starting DAB, so the container finds tables
    # -----------------------------------------------------------------------
    $schemaDeployed = $false
    if (-not $SkipDatabase) {
        Write-Header "Database Setup (pre-DAB)"

        $schemaFile = Join-Path $PSScriptRoot "..\..\database\01_create_schema.sql"
        $sqlServer = $sqlServerFqdn   # direct variable already in scope

        # Step 1: Run schema script
        if (Test-Path $schemaFile) {
            Write-Step "Running schema script..."
            Write-Info "Schema file: $schemaFile"
            Write-Info "Server: $sqlServer"

            $exitCode = 0
            try {
                $p = Start-Process sqlcmd -ArgumentList "-S", "$sqlServer", "-d", "$sqlDatabaseName", "-G", "-i", "`"$schemaFile`"", "-b" -NoNewWindow -PassThru -Wait
                $exitCode = $p.ExitCode
            } catch {
                Write-Error "Failed to execute sqlcmd: $_"
                $exitCode = -1
            }

            if ($exitCode -ne 0) {
                Write-Warning "Schema script failed (Exit Code: $exitCode)."
                Write-Info "Manual command: sqlcmd -S $sqlServer -d $sqlDatabaseName -G -i `"$schemaFile`""
            } else {
                Write-Info "Schema created successfully"
            }
        } else {
            Write-Warning "Schema file not found: $schemaFile"
        }

        # Step 1b: Run OLTP stored procedures
        $oltpProcsFile = Join-Path $PSScriptRoot "..\..\database\06_oltp_procedures.sql"
        if (Test-Path $oltpProcsFile) {
            Write-Step "Running OLTP procedures script..."
            Write-Info "Procedures file: $oltpProcsFile"

            $exitCode = 0
            try {
                $p = Start-Process sqlcmd -ArgumentList "-S", "$sqlServer", "-d", "$sqlDatabaseName", "-G", "-i", "`"$oltpProcsFile`"", "-b" -NoNewWindow -PassThru -Wait
                $exitCode = $p.ExitCode
            } catch {
                Write-Error "Failed to execute sqlcmd for OLTP procedures: $_"
                $exitCode = -1
            }

            if ($exitCode -ne 0) {
                Write-Warning "OLTP procedures script failed (Exit Code: $exitCode)."
                Write-Info "Manual command: sqlcmd -S $sqlServer -d $sqlDatabaseName -G -i `"$oltpProcsFile`""
            } else {
                Write-Info "OLTP procedures deployed successfully"
            }
        }

        # Step 2: Grant managed identity access
        Write-Step "Granting managed identity access..."
        $grantSql = @"
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$identityName')
BEGIN
    CREATE USER [$identityName] FROM EXTERNAL PROVIDER;
END
ALTER ROLE db_owner ADD MEMBER [$identityName];
"@
        $grantSqlFile = Join-Path $env:TEMP "grant_identity.sql"
        $grantSql | Out-File -FilePath $grantSqlFile -Encoding utf8

        try {
            $p = Start-Process sqlcmd -ArgumentList "-S", "$sqlServer", "-d", "$sqlDatabaseName", "-G", "-i", "`"$grantSqlFile`"", "-b" -NoNewWindow -PassThru -Wait
            if ($p.ExitCode -ne 0) {
                Write-Warning "Could not grant managed identity access automatically (Exit Code: $($p.ExitCode))."
                Write-Info "Please run the following SQL manually:"
                Write-Host ""
                Write-Host $grantSql -ForegroundColor Yellow
                Write-Host ""
                Write-Info "Connect using: Azure Data Studio or SSMS with Entra authentication"
                Write-Info "Server: $sqlServer"
                Write-Host ""
                $continue = Read-Host "Press Enter after granting access, or 'skip' to continue"
            } else {
                Write-Info "Managed identity access granted"
            }
        } catch {
            Write-Warning "Failed to execute sqlcmd for granting identity access."
        }
        if (Test-Path $grantSqlFile) { Remove-Item $grantSqlFile -Force }

        # Step 3: Security features (Ledger, RLS, DDM, Classification)
        $securityFile = Join-Path $PSScriptRoot "..\..\database\10_security_features.sql"
        if (Test-Path $securityFile) {
            Write-Step "Running 10_security_features.sql (Ledger, RLS, DDM, Classification)..."
            try {
                $p = Start-Process sqlcmd -ArgumentList "-S", "$sqlServer", "-d", "$sqlDatabaseName", "-G", "-i", "`"$securityFile`"", "-b" -NoNewWindow -PassThru -Wait
                if ($p.ExitCode -eq 0) {
                    Write-Success "Security features deployed (Ledger, RLS, DDM, Column Security, Classification)"
                } else {
                    Write-Warning "Security features script returned exit code $($p.ExitCode). Some features may require Hyperscale tier."
                    Write-Info "Manual command: sqlcmd -S $sqlServer -d $sqlDatabaseName -G -i `"$securityFile`""
                }
            } catch {
                Write-Warning "Security features deployment failed: $($_.Exception.Message)"
                Write-Info "Manual command: sqlcmd -S $sqlServer -d $sqlDatabaseName -G -i `"$securityFile`""
            }
        }

        $schemaDeployed = $true
        Write-Success "Database schema ready — DAB will find its tables on startup"
    }

    # --- Web App (Frontend) ---
    Write-Step "Creating Web App '$webAppName' for frontend..."
    az webapp create `
        --name $webAppName `
        --resource-group $ResourceGroupName `
        --plan $appServicePlanName `
        --runtime "NODE:22-lts" `
        --assign-identity $identityId `
        --output none
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  FAILED CMD: az webapp create --name $webAppName --resource-group $ResourceGroupName --plan $appServicePlanName --runtime NODE:22-lts" -ForegroundColor Red
        throw "Failed to create Web App"
    }
    $webAppUrl = "https://$webAppName.azurewebsites.net"
    Write-Success "Web App created: $webAppUrl"

    # Configure startup command for static SPA
    Write-Step "Configuring web app startup command..."
    az webapp config set `
        --name $webAppName `
        --resource-group $ResourceGroupName `
        --startup-file "npx serve . -s -l 8080" `
        --output none
    Write-Success "Startup command configured"

    # --- Azure Container Registry for DAB ---
    Write-Step "Creating Azure Container Registry '$acrName'..."
    az acr create `
        --name $acrName `
        --resource-group $ResourceGroupName `
        --sku Basic `
        --admin-enabled true `
        --output none
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  FAILED CMD: az acr create --name $acrName --resource-group $ResourceGroupName --sku Basic --admin-enabled true" -ForegroundColor Red
        throw "Failed to create ACR"
    }
    Write-Success "ACR created: $acrName"
    
    # Build custom DAB image with config baked in
    Write-Step "Building custom DAB image..."
    $webappDir = Join-Path $PSScriptRoot "..\..\webapp"
    Push-Location $webappDir
    az acr build --registry $acrName --image dab:latest --file Dockerfile.dab . --output none
    if ($LASTEXITCODE -ne 0) { 
        Write-Host "  FAILED CMD: az acr build --registry $acrName --image dab:latest --file Dockerfile.dab ." -ForegroundColor Red
        Pop-Location
        throw "Failed to build DAB image" 
    }
    Pop-Location
    Write-Success "DAB image built and pushed to ACR"
    
    # Get ACR credentials
    $acrCreds = az acr credential show --name $acrName --query "{username:username,password:passwords[0].value}" -o json | ConvertFrom-Json
    $acrLoginServer = "$acrName.azurecr.io"

    # --- DAB App Service ---
    Write-Step "Creating App Service '$dabAppName' for Data API Builder..."
    
    # Primary connection string (for writes)
    $connectionString = "Server=$sqlServerFqdn;Database=$sqlDatabaseName;Authentication=Active Directory Managed Identity;User Id=$identityClientId;Encrypt=True;TrustServerCertificate=False;"
    
    # Read-only connection string (routes to HA replica via ApplicationIntent)
    $connectionStringReadOnly = "Server=$sqlServerFqdn;Database=$sqlDatabaseName;Authentication=Active Directory Managed Identity;User Id=$identityClientId;Encrypt=True;TrustServerCertificate=False;ApplicationIntent=ReadOnly;"

    # Analytics connection string (routes to named replica for HTAP / CCI analytical queries)
    $connectionStringAnalytics = "Server=$sqlServerFqdn;Database=$namedReplicaDbName;Authentication=Active Directory Managed Identity;User Id=$identityClientId;Encrypt=True;TrustServerCertificate=False;Command Timeout=60;"
    
    # Create DAB as a container-based App Service
    az webapp create `
        --name $dabAppName `
        --resource-group $ResourceGroupName `
        --plan $appServicePlanName `
        --container-image-name "$acrLoginServer/dab:latest" `
        --container-registry-user $acrCreds.username `
        --container-registry-password $acrCreds.password `
        --assign-identity $identityId `
        --output none
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  FAILED CMD: az webapp create --name $dabAppName --resource-group $ResourceGroupName --plan $appServicePlanName --container-image-name $acrLoginServer/dab:latest" -ForegroundColor Red
        throw "Failed to create DAB App Service"
    }
    
    # Configure DAB environment variables (primary, read-only, and analytics connections)
    # WEBSITES_PORT tells App Service which port the container listens on (DAB defaults to 5000)
    Write-Step "Configuring DAB settings with read scale-out and named replica analytics..."
    az webapp config appsettings set `
        --name $dabAppName `
        --resource-group $ResourceGroupName `
        --settings "DATABASE_CONNECTION_STRING=$connectionString" "DATABASE_CONNECTION_STRING_READONLY=$connectionStringReadOnly" "DATABASE_CONNECTION_STRING_ANALYTICS=$connectionStringAnalytics" "AZURE_CLIENT_ID=$identityClientId" "WEBSITES_PORT=5000" `
        --output none
    
    # Configure CORS on DAB App Service to allow requests from the web app
    Write-Step "Configuring DAB CORS..."
    $webAppUrl = "https://$webAppName.azurewebsites.net"
    az webapp cors add `
        --name $dabAppName `
        --resource-group $ResourceGroupName `
        --allowed-origins $webAppUrl 'http://localhost:5173' `
        --output none
    Write-Success "DAB CORS configured for $webAppUrl"
    
    # Get the DAB app URL
    $dabAppUrl = "https://$dabAppName.azurewebsites.net"
    Write-Success "DAB App Service ready: $dabAppUrl"

    # --- Configure Web App Settings ---
    Write-Step "Configuring web app settings..."
    az webapp config appsettings set `
        --name $webAppName `
        --resource-group $ResourceGroupName `
        --settings "VITE_API_BASE_URL=$dabAppUrl" "VITE_DEV_MODE=true" `
        --output none
    Write-Success "App settings configured"

    # --- Store outputs for later use ---
    $outputs = [PSCustomObject]@{
        webAppUrl = [PSCustomObject]@{ value = $webAppUrl }
        webAppName = [PSCustomObject]@{ value = $webAppName }
        dabAppUrl = [PSCustomObject]@{ value = $dabAppUrl }
        dabAppName = [PSCustomObject]@{ value = $dabAppName }
        sqlServerFqdn = [PSCustomObject]@{ value = $sqlServerFqdn }
        sqlServerName = [PSCustomObject]@{ value = $sqlServerName }
        sqlDatabaseName = [PSCustomObject]@{ value = $sqlDatabaseName }
        namedReplicaDbName = [PSCustomObject]@{ value = $namedReplicaDbName }
        userAssignedIdentityName = [PSCustomObject]@{ value = $identityName }
        userAssignedIdentityClientId = [PSCustomObject]@{ value = $identityClientId }
        userAssignedIdentityPrincipalId = [PSCustomObject]@{ value = $identityPrincipalId }
        storageAccountName = [PSCustomObject]@{ value = $storageAccountName }
        storageContainerName = [PSCustomObject]@{ value = $storageContainerName }
        storageBlobEndpoint = [PSCustomObject]@{ value = $storageBlobEndpoint }
    }

    Write-Host ""
    Write-Host "Deployment Outputs:" -ForegroundColor Cyan
    Write-Info "Web App URL: $webAppUrl"
    Write-Info "API URL: $dabAppUrl"
    Write-Info "SQL Server: $sqlServerFqdn"
    Write-Info "SQL Database: $sqlDatabaseName"
    Write-Info "Named Replica: $namedReplicaDbName (analytics, serverless max 24 vCores)"
    Write-Info "Managed Identity Client ID: $identityClientId"
    Write-Info "Storage Account: $storageAccountName"
    Write-Info "Storage Container: $storageContainerName"
    Write-Info "Blob Endpoint: $storageBlobEndpoint"

} else {
    Write-Step "Skipping infrastructure deployment - using existing resources"
    
    # Try to get existing resource info
    $webAppName = "$resourcePrefix-web-$uniqueSuffix"
    $dabAppName = "$resourcePrefix-dab-$uniqueSuffix"
    $sqlServerName = "$resourcePrefix-sql-$uniqueSuffix"
    
    $webAppUrl = "https://$webAppName.azurewebsites.net"
    $dabAppUrl = "https://$dabAppName.azurewebsites.net"
    $sqlServerFqdn = az sql server show --name $sqlServerName --resource-group $ResourceGroupName --query fullyQualifiedDomainName -o tsv 2>$null
    
    # If the exact calculated name wasn't found, try to discover one in the resource group
    if ([string]::IsNullOrWhiteSpace($sqlServerFqdn)) {
        Write-Info "Server '$sqlServerName' not found. searching for any SQL Server in '$ResourceGroupName'..."
        $foundServers = az sql server list --resource-group $ResourceGroupName --query "[].{name:name, fqdn:fullyQualifiedDomainName}" -o json 2>$null | ConvertFrom-Json
        
        if ($foundServers) {
            # Handle single object vs array return from ConvertFrom-Json
            if (-not ($foundServers -is [array])) { $foundServers = @($foundServers) }
            
            if ($foundServers.Count -gt 0) {
                $chosen = $foundServers[0]
                $sqlServerName = $chosen.name
                $sqlServerFqdn = $chosen.fqdn
                Write-Info "Auto-discovered SQL Server: $sqlServerName"
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($sqlServerFqdn)) {
            Write-Warning "Could not locate any SQL Server in resource group '$ResourceGroupName'."
        }
    }

    # Look up managed identity
    $identity = az identity show --name $identityName --resource-group $ResourceGroupName 2>$null | ConvertFrom-Json
    $identityClientId = if ($identity) { $identity.clientId } else { "" }
    $identityPrincipalId = if ($identity) { $identity.principalId } else { "" }
    
    $outputs = [PSCustomObject]@{
        webAppUrl = [PSCustomObject]@{ value = $webAppUrl }
        webAppName = [PSCustomObject]@{ value = $webAppName }
        dabAppUrl = [PSCustomObject]@{ value = $dabAppUrl }
        dabAppName = [PSCustomObject]@{ value = $dabAppName }
        sqlServerFqdn = [PSCustomObject]@{ value = $sqlServerFqdn }
        sqlServerName = [PSCustomObject]@{ value = $sqlServerName }
        sqlDatabaseName = [PSCustomObject]@{ value = $sqlDatabaseName }
        namedReplicaDbName = [PSCustomObject]@{ value = $namedReplicaDbName }
        userAssignedIdentityName = [PSCustomObject]@{ value = $identityName }
        userAssignedIdentityClientId = [PSCustomObject]@{ value = $identityClientId }
        userAssignedIdentityPrincipalId = [PSCustomObject]@{ value = $identityPrincipalId }
        storageAccountName = [PSCustomObject]@{ value = $storageAccountName }
        storageContainerName = [PSCustomObject]@{ value = $storageContainerName }
        storageBlobEndpoint = [PSCustomObject]@{ value = (az storage account show --name $storageAccountName --resource-group $ResourceGroupName --query "primaryEndpoints.blob" -o tsv 2>$null) }
    }
}

# ============================================================================
# AZURE OPENAI DEPLOYMENT
# ============================================================================

if ($DeployOpenAI) {
    Write-Header "Deploying Azure OpenAI"

    if (-not $OpenAILocation) {
        $OpenAILocation = $Location
    }

    # $openAIServiceName is already set (with legacy fallback) in the resource naming section
    $openAIDeploymentName = $OpenAIModelName  # Use same name as model for clarity
    $embeddingModelName = "text-embedding-3-small"
    $embeddingDeploymentName = "text-embedding-3-small"

    # Check if OpenAI service exists
    Write-Step "Creating Azure OpenAI service '$openAIServiceName'..."
    $existingOpenAI = az cognitiveservices account show --name $openAIServiceName --resource-group $ResourceGroupName 2>$null
    
    if (-not $existingOpenAI) {
        az cognitiveservices account create `
            --name $openAIServiceName `
            --resource-group $ResourceGroupName `
            --location $OpenAILocation `
            --kind OpenAI `
            --sku S0 `
            --custom-domain $openAIServiceName `
            --output none
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  FAILED CMD: az cognitiveservices account create --name $openAIServiceName --resource-group $ResourceGroupName --location $OpenAILocation --kind OpenAI --sku S0" -ForegroundColor Red
            throw "Failed to create Azure OpenAI service"
        }
        Write-Success "Azure OpenAI service created"
        
        Write-Info "Waiting 30 seconds for service to be ready..."
        Start-Sleep -Seconds 30
    } else {
        Write-Info "Azure OpenAI service already exists"
    }

    # Deploy chat model (if not an embedding model)
    if ($OpenAIModelName -notlike "text-embedding*") {
        Write-Step "Deploying chat model '$OpenAIModelName'..."
        $existingDeployment = az cognitiveservices account deployment show `
            --name $openAIServiceName `
            --resource-group $ResourceGroupName `
            --deployment-name $openAIDeploymentName 2>$null

        if (-not $existingDeployment) {
            az cognitiveservices account deployment create `
                --name $openAIServiceName `
                --resource-group $ResourceGroupName `
                --deployment-name $openAIDeploymentName `
                --model-name $OpenAIModelName `
                --model-version $OpenAIModelVersion `
                --model-format OpenAI `
                --sku-capacity $OpenAICapacity `
                --sku-name Standard `
                --output none
            if ($LASTEXITCODE -ne 0) {
                Write-Host "  FAILED CMD: az cognitiveservices account deployment create --name $openAIServiceName --deployment-name $openAIDeploymentName --model-name $OpenAIModelName --model-version $OpenAIModelVersion" -ForegroundColor Red
                Write-Warning "Chat model '$OpenAIModelName' (version $OpenAIModelVersion) is not available in this region."

                # Offer interactive fallback to gpt-4o
                $fallbackModel = "gpt-4o"
                $fallbackVersion = "2024-08-06"
                Write-Host ""
                $response = Read-Host "Would you like to fall back to '$fallbackModel' (version $fallbackVersion) instead? [Y/n]"
                if ($response -match '^(y|yes)?$') {
                    Write-Step "Deploying fallback chat model '$fallbackModel'..."
                    $OpenAIModelName = $fallbackModel
                    $OpenAIModelVersion = $fallbackVersion
                    $openAIDeploymentName = $fallbackModel
                    az cognitiveservices account deployment create `
                        --name $openAIServiceName `
                        --resource-group $ResourceGroupName `
                        --deployment-name $openAIDeploymentName `
                        --model-name $fallbackModel `
                        --model-version $fallbackVersion `
                        --model-format OpenAI `
                        --sku-capacity $OpenAICapacity `
                        --sku-name Standard `
                        --output none
                    if ($LASTEXITCODE -ne 0) {
                        Write-Warning "Fallback model '$fallbackModel' also failed. Continuing without a chat model."
                    } else {
                        Write-Success "Fallback chat model '$fallbackModel' deployed"
                    }
                } else {
                    Write-Warning "Continuing without a chat model. To fix later, either:"
                    Write-Warning "  1. Redeploy with a supported region: -OpenAILocation <region>"
                    Write-Warning "  2. Redeploy with a different model:  -OpenAIModelName gpt-4o -OpenAIModelVersion 2024-08-06"
                    Write-Warning "  3. Deploy the model manually in the Azure portal."
                }
            } else {
                Write-Success "Chat model '$OpenAIModelName' deployed"
            }
        } else {
            Write-Info "Chat model deployment already exists"
        }
    }

    # Always deploy embedding model for vector search
    Write-Step "Deploying embedding model '$embeddingModelName'..."
    $existingEmbeddingDeployment = az cognitiveservices account deployment show `
        --name $openAIServiceName `
        --resource-group $ResourceGroupName `
        --deployment-name $embeddingDeploymentName 2>$null

    if (-not $existingEmbeddingDeployment) {
        az cognitiveservices account deployment create `
            --name $openAIServiceName `
            --resource-group $ResourceGroupName `
            --deployment-name $embeddingDeploymentName `
            --model-name $embeddingModelName `
            --model-version "1" `
            --model-format OpenAI `
            --sku-capacity 150 `
            --sku-name GlobalStandard `
            --output none
        if ($LASTEXITCODE -ne 0) { 
            Write-Host "  FAILED CMD: az cognitiveservices account deployment create --name $openAIServiceName --deployment-name $embeddingDeploymentName --model-name $embeddingModelName --sku-name GlobalStandard" -ForegroundColor Red
            Write-Warning "Failed to deploy embedding model - vector search will use text fallback"
        } else {
            Write-Success "Embedding model deployed"
        }
    } else {
        Write-Info "Embedding model deployment already exists"
    }

    # Get endpoint
    $openAIEndpoint = az cognitiveservices account show --name $openAIServiceName --resource-group $ResourceGroupName --query 'properties.endpoint' -o tsv

    Write-Host ""
    Write-Host "Azure OpenAI Configuration:" -ForegroundColor Cyan
    Write-Info "Endpoint: $openAIEndpoint"
    Write-Info "Chat Deployment: $openAIDeploymentName"
    Write-Info "Embedding Deployment: $embeddingDeploymentName"
    
    # Grant managed identity access to Azure OpenAI
    Write-Step "Granting managed identity access to Azure OpenAI..."
    $openAIResourceId = az cognitiveservices account show --name $openAIServiceName --resource-group $ResourceGroupName --query id -o tsv
    $identityPrincipalId = if ($outputs) { $outputs.userAssignedIdentityPrincipalId.value } else {
        (az identity show --name $identityName --resource-group $ResourceGroupName --query principalId -o tsv)
    }
    
    az role assignment create `
        --assignee-object-id $identityPrincipalId `
        --assignee-principal-type ServicePrincipal `
        --role "Cognitive Services OpenAI User" `
        --scope $openAIResourceId `
        --output none 2>$null
    if ($LASTEXITCODE -ne 0) { 
        Write-Host "  FAILED CMD: az role assignment create --assignee-object-id $identityPrincipalId --role 'Cognitive Services OpenAI User' --scope $openAIResourceId" -ForegroundColor Red
        Write-Info "Role assignment may already exist or require elevated permissions"
    } else {
        Write-Success "Managed identity granted Cognitive Services OpenAI User role"
    }

    # Grant the current signed-in user access so data-prep scripts (embeddings, etc.) work locally
    Write-Step "Granting current user Cognitive Services OpenAI User role..."
    $currentUserObjectId = az ad signed-in-user show --query id -o tsv 2>$null
    if ($currentUserObjectId) {
        az role assignment create `
            --assignee-object-id $currentUserObjectId `
            --assignee-principal-type User `
            --role "Cognitive Services OpenAI User" `
            --scope $openAIResourceId `
            --output none 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  FAILED CMD: az role assignment create --assignee-object-id $currentUserObjectId --role 'Cognitive Services OpenAI User' --scope $openAIResourceId" -ForegroundColor Red
            Write-Info "Role assignment may already exist"
        } else {
            Write-Success "Current user granted Cognitive Services OpenAI User role"
        }
    } else {
        Write-Info "Could not determine signed-in user - skipping user role assignment"
    }
    
    # --- Run 05_setup_azure_openai_endpoint.sql (creates AI stored procedures DAB needs) ---
    $openAISetupScript = Join-Path $PSScriptRoot "..\..\database\05_setup_azure_openai_endpoint.sql"
    $sqlServer = if ($sqlServerFqdn) { $sqlServerFqdn } elseif ($outputs) { $outputs.sqlServerFqdn.value } else { $null }
    if ($sqlServer -and (Test-Path $openAISetupScript)) {
        Write-Step "Configuring SQL Server to use Azure OpenAI..."
        $embeddingDeploymentName = "text-embedding-3-small"

        # Replace placeholders in script with actual endpoint and deployment names
        $scriptContent = Get-Content $openAISetupScript -Raw
        $scriptContent = $scriptContent -replace 'https://your-openai-resource\.openai\.azure\.com', $openAIEndpoint.TrimEnd('/')
        $scriptContent = $scriptContent -replace 'your-embedding-deployment', $embeddingDeploymentName
        $scriptContent = $scriptContent -replace 'text-embedding-3-small', $embeddingDeploymentName

        # Replace chat deployment placeholder (used by AskTaxAssistant sproc)
        $scriptContent = $scriptContent -replace 'your-chat-deployment', $openAIDeploymentName

        # Generate a strong random password for the database master key
        $masterKeyChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
        $masterKeyPassword = -join ((1..28) | ForEach-Object { $masterKeyChars[(Get-Random -Maximum $masterKeyChars.Length)] })
        $masterKeyPassword = 'Zv' + $masterKeyPassword + '!4q'
        $scriptContent = $scriptContent -replace '\$\(MASTER_KEY_PASSWORD\)', $masterKeyPassword

        # Write modified script to temp file
        $tempScript = Join-Path $env:TEMP "05_setup_azure_openai_endpoint_configured.sql"
        $scriptContent | Out-File -FilePath $tempScript -Encoding utf8

        & sqlcmd -S $sqlServer -d $sqlDatabaseName -G -i "$tempScript" -b
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Azure OpenAI setup script failed. You may need to run it manually."
            Write-Info "Manual steps:"
            Write-Info "  1. Edit database/05_setup_azure_openai_endpoint.sql"
            Write-Info "  2. Replace endpoint URL with: $openAIEndpoint"
            Write-Info "  3. Run: sqlcmd -S $sqlServer -d $sqlDatabaseName -G -i database/05_setup_azure_openai_endpoint.sql"
        } else {
            Write-Success "Azure OpenAI endpoint and AI stored procedures configured"
        }

        Remove-Item $tempScript -Force -ErrorAction SilentlyContinue

        # Restart DAB so it discovers the newly created AI stored procedures
        $dabName = if ($dabAppName) { $dabAppName } elseif ($outputs) { $outputs.dabAppName.value } else { $null }
        if ($dabName) {
            Write-Step "Restarting DAB to pick up AI stored procedures..."
            az webapp restart --name $dabName --resource-group $ResourceGroupName --output none 2>$null
            Write-Success "DAB restarted"
        }
    } elseif (-not $sqlServer) {
        Write-Warning "SQL Server FQDN not available — skipping Azure OpenAI SQL setup"
    }
}

# ============================================================================
# DATABASE SCHEMA DEPLOYMENT (only when infrastructure was skipped)
# ============================================================================

if (-not $schemaDeployed -and -not $SkipDatabase -and $outputs) {
    Write-Header "Database Setup"
    
    $schemaFile = Join-Path $PSScriptRoot "..\..\database\01_create_schema.sql"
    $sqlServer = $outputs.sqlServerFqdn.value
    
    # Step 1: Run schema script
    if (Test-Path $schemaFile) {
        Write-Step "Running schema script..."
        Write-Info "Schema file: $schemaFile"
        Write-Info "Server: $sqlServer"

        if ([string]::IsNullOrWhiteSpace($sqlServer)) {
            Write-Error "SQL Server FQDN is not defined. Cannot connect to database."
            Write-Info "If you skipped infrastructure, ensure the SQL Server exists and could be found."
        } else {
            # Run sqlcmd with Entra auth (-G flag)
            # Use Start-Process to ensure output is properly streamed and exit code captured
            $exitCode = 0
            try {
                $p = Start-Process sqlcmd -ArgumentList "-S", "$sqlServer", "-d", "$sqlDatabaseName", "-G", "-i", "`"$schemaFile`"", "-b" -NoNewWindow -PassThru -Wait
                $exitCode = $p.ExitCode
            } catch {
                Write-Error "Failed to execute sqlcmd: $_"
                $exitCode = -1
            }

            if ($exitCode -ne 0) {
                Write-Warning "Schema script failed (Exit Code: $exitCode)."
                Write-Info "Manual command: sqlcmd -S $sqlServer -d $sqlDatabaseName -G -i `"$schemaFile`""
            } else {
                Write-Info "Schema created successfully"
            }
        }
    } else {
        Write-Warning "Schema file not found: $schemaFile"
    }

    # Step 1b: Run OLTP stored procedures (SubmitTaxReturn, PopulateFilingDetails, etc.)
    $oltpProcsFile = Join-Path $PSScriptRoot "..\..\database\06_oltp_procedures.sql"
    if (Test-Path $oltpProcsFile) {
        Write-Step "Running OLTP procedures script..."
        Write-Info "Procedures file: $oltpProcsFile"

        if (-not [string]::IsNullOrWhiteSpace($sqlServer)) {
            $exitCode = 0
            try {
                $p = Start-Process sqlcmd -ArgumentList "-S", "$sqlServer", "-d", "$sqlDatabaseName", "-G", "-i", "`"$oltpProcsFile`"", "-b" -NoNewWindow -PassThru -Wait
                $exitCode = $p.ExitCode
            } catch {
                Write-Error "Failed to execute sqlcmd for OLTP procedures: $_"
                $exitCode = -1
            }

            if ($exitCode -ne 0) {
                Write-Warning "OLTP procedures script failed (Exit Code: $exitCode)."
                Write-Info "Manual command: sqlcmd -S $sqlServer -d $sqlDatabaseName -G -i `"$oltpProcsFile`""
            } else {
                Write-Info "OLTP procedures deployed successfully"
            }
        }
    } else {
        Write-Warning "OLTP procedures file not found: $oltpProcsFile"
    }
    
    # Step 2: Grant managed identity access
    Write-Step "Granting managed identity access..."
    
    $grantSql = @"
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$($outputs.userAssignedIdentityName.value)')
BEGIN
    CREATE USER [$($outputs.userAssignedIdentityName.value)] FROM EXTERNAL PROVIDER;
END
ALTER ROLE db_owner ADD MEMBER [$($outputs.userAssignedIdentityName.value)];
"@

    # Run the grant SQL
    $grantSqlFile = Join-Path $env:TEMP "grant_identity.sql"
    $grantSql | Out-File -FilePath $grantSqlFile -Encoding utf8
    
    if (-not [string]::IsNullOrWhiteSpace($sqlServer)) {
        try {
            $p = Start-Process sqlcmd -ArgumentList "-S", "$sqlServer", "-d", "$sqlDatabaseName", "-G", "-i", "`"$grantSqlFile`"", "-b" -NoNewWindow -PassThru -Wait
            if ($p.ExitCode -ne 0) {
                Write-Warning "Could not grant managed identity access automatically (Exit Code: $($p.ExitCode))."
                Write-Info "Please run the following SQL manually:"
                Write-Host ""
                Write-Host $grantSql -ForegroundColor Yellow
                Write-Host ""
                Write-Info "Connect using: Azure Data Studio or SSMS with Entra authentication"
                Write-Info "Server: $sqlServer"
                Write-Host ""
                $continue = Read-Host "Press Enter after granting access, or 'skip' to continue"
            } else {
                Write-Info "Managed identity access granted"
            }
        } catch {
            Write-Warning "Failed to execute sqlcmd for granting identity access."
        }
    }
    
    # Cleanup temp file
    if (Test-Path $grantSqlFile) {
        Remove-Item $grantSqlFile -Force
    }
}

# ============================================================================
# SECURITY FEATURES DEPLOYMENT (only when infrastructure was skipped)
# ============================================================================

if (-not $schemaDeployed) {
    Write-Header "Deploying Security Features"

    $securityFile = Join-Path $PSScriptRoot "..\..\database\10_security_features.sql"
    if (Test-Path $securityFile) {
        Write-Step "Running 10_security_features.sql (Ledger, RLS, DDM, Classification)..."
        try {
            $p = Start-Process sqlcmd -ArgumentList "-S", "$sqlServer", "-d", "$sqlDatabaseName", "-G", "-i", "`"$securityFile`"", "-b" -NoNewWindow -PassThru -Wait
            if ($p.ExitCode -eq 0) {
                Write-Success "Security features deployed (Ledger, RLS, DDM, Column Security, Classification)"
            } else {
                Write-Warning "Security features script returned exit code $($p.ExitCode). Some features may require Hyperscale tier."
                Write-Info "Manual command: sqlcmd -S $sqlServer -d $sqlDatabaseName -G -i `"$securityFile`""
            }
        } catch {
            Write-Warning "Security features deployment failed: $($_.Exception.Message)"
            Write-Info "Manual command: sqlcmd -S $sqlServer -d $sqlDatabaseName -G -i `"$securityFile`""
        }
    } else {
        Write-Warning "Security features script not found: $securityFile"
    }
}

# ============================================================================
# WEB APP DEPLOYMENT
# ============================================================================

if (-not $SkipWebApp -and $outputs) {
    Write-Header "Deploying Web Application"
    
    $webappDir = Join-Path $PSScriptRoot "..\..\webapp"
    
    if (Test-Path $webappDir) {
        Push-Location $webappDir
        try {
            Write-Step "Installing dependencies..."
            npm ci
            if ($LASTEXITCODE -ne 0) { throw "npm ci failed" }
            
            Write-Step "Building production bundle..."
            # Set Vite environment variables for the build (demo mode)
            $env:VITE_API_BASE_URL = "$($outputs.dabAppUrl.value)"
            $env:VITE_DEV_MODE = "true"
            npm run build
            if ($LASTEXITCODE -ne 0) { throw "npm build failed" }
            
            Write-Step "Deploying to Azure..."
            $zipPath = Join-Path $env:TEMP "webapp-deploy.zip"
            
            if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
            # Include dist, server, and package files for Node.js runtime
            Compress-Archive -Path @(
                "$webappDir\dist\*",
                "$webappDir\server\*",
                "$webappDir\package.json",
                "$webappDir\package-lock.json"
            ) -DestinationPath $zipPath -Force
            
            az webapp deployment source config-zip `
                --resource-group $ResourceGroupName `
                --name $($outputs.webAppName.value) `
                --src $zipPath
            
            if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
            
            Write-Step "Restarting web app..."
            az webapp restart `
                --resource-group $ResourceGroupName `
                --name $($outputs.webAppName.value) `
                --output none
            Write-Success "Web app restarted"

            Write-Step "Restarting DAB app service..."
            az webapp restart `
                --resource-group $ResourceGroupName `
                --name $($outputs.dabAppName.value) `
                --output none
            Write-Success "DAB app service restarted"

            Write-Success "Web application deployed: $($outputs.webAppUrl.value)"
        } finally {
            Pop-Location
        }
    } else {
        Write-Warning "Webapp directory not found: $webappDir"
    }
}

# ============================================================================
# SUMMARY
# ============================================================================

Write-Header "Deployment Complete"

if ($outputs) {
    Write-Host "Resources:" -ForegroundColor Cyan
    Write-Info "  Web App: $($outputs.webAppUrl.value)"
    Write-Info "  API: $($outputs.dabAppUrl.value)"
    Write-Info "  SQL: $($outputs.sqlServerFqdn.value) / $sqlDatabaseName"
    Write-Info "  Identity: $($outputs.userAssignedIdentityName.value)"
}

# Get the identity client ID for the loader
$identityClientId = az identity show --name $($outputs.userAssignedIdentityName.value) --resource-group $ResourceGroupName --query clientId -o tsv 2>$null

# --- Generate data-prep/.env with actual resource values ---
$dataPrepDir = Join-Path $PSScriptRoot "..\..\data-prep"
$envFile = Join-Path $dataPrepDir ".env"
if ($outputs) {
    $oaiEndpoint = if ($openAIEndpoint) { $openAIEndpoint.TrimEnd('/') + '/' } else { "# not deployed — run with -DeployOpenAI" }
    $chatDeploy = if ($openAIDeploymentName) { $openAIDeploymentName } else { "gpt-4o" }
    $envContent = @"
# Auto-generated by deploy.ps1 on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# DO NOT commit this file to source control

# Azure OpenAI Configuration
AZURE_OPENAI_ENDPOINT=$oaiEndpoint
AZURE_OPENAI_EMBEDDING_DEPLOYMENT=text-embedding-3-small
AZURE_OPENAI_CHAT_DEPLOYMENT=$chatDeploy
AZURE_OPENAI_API_VERSION=2024-02-01

# Azure SQL Database Configuration (Azure AD auth only)
SQL_SERVER=$($outputs.sqlServerFqdn.value)
SQL_DATABASE=$sqlDatabaseName

# Storage (for 07_load_to_azure_sql.py)
STORAGE_ACCOUNT=$($outputs.storageAccountName.value)
STORAGE_CONTAINER=$($outputs.storageContainerName.value)
IDENTITY_CLIENT_ID=$identityClientId

# Data generation settings
PUBLICATION_PRIORITY=4
SCENARIO_COUNT=5000
OPERATIONAL_ROWS=1000000
BRANCHES=500
CUSTOMERS=10000
PROFESSIONALS=2500
CHUNK_SIZE=500
"@
    $envContent | Out-File -FilePath $envFile -Encoding utf8 -Force
    Write-Success "Generated data-prep/.env with actual resource names"
}

Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Prepare sample data (skip if ./data-prep/data/output already has CSV files):" -ForegroundColor Gray
Write-Host "     cd data-prep && .\run_all.ps1" -ForegroundColor DarkGray
Write-Host "     (see data-prep/README.md for individual steps and customization options)" -ForegroundColor DarkGray
Write-Host "  2. Upload data files to blob storage:" -ForegroundColor Gray
Write-Host "     az storage blob upload-batch --account-name $($outputs.storageAccountName.value) --destination $($outputs.storageContainerName.value) --source ./data-prep/data/output --auth-mode login" -ForegroundColor DarkGray
Write-Host "  3. Load data to Azure SQL (reads from blob storage; args auto-populated from data-prep/.env):" -ForegroundColor Gray
Write-Host "     python data-prep/07_load_to_azure_sql.py" -ForegroundColor DarkGray
Write-Host "  4. Generate filing detail records (P0 + P1 tables, ~300GB):" -ForegroundColor Gray
Write-Host "     sqlcmd -S $($outputs.sqlServerFqdn.value) -d $sqlDatabaseName -G -i database/08_generate_filing_details.sql" -ForegroundColor DarkGray
if (-not $DeployOpenAI) {
    Write-Host "  5. Deploy OpenAI: .\deploy.ps1 -DeployOpenAI -SkipInfrastructure" -ForegroundColor Gray
}
Write-Host ""
Write-Host "  (Optional - only for production auth, not needed for demo with mock users):" -ForegroundColor DarkGray
Write-Host "  Assign app roles: Entra ID -> App registrations -> $resourcePrefix-app -> App roles" -ForegroundColor DarkGray
Write-Host ""
