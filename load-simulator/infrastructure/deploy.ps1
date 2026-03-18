<#
.SYNOPSIS
    Deploy ZavaTax Load Simulator to Azure Container Apps (Azure CLI-based)

.DESCRIPTION
    Deploys load simulator infrastructure using Azure CLI commands (no Bicep required).
    Supports both OLTP and Analytics load tests.
    Uses managed identity for authentication to SQL Database.

.PARAMETER Mode
    Test mode: 'oltp' or 'analytics'. Default: oltp

.PARAMETER SqlServer
    SQL Server FQDN (e.g., myserver.database.windows.net)

.PARAMETER SqlDatabase
    SQL Database name. Default: zavatax

.PARAMETER ResourceGroup
    Resource group name. Default: rg-zavatax-loadsim

.PARAMETER Location
    Azure region. Default: eastus2

.PARAMETER AcrName
    Azure Container Registry name (without .azurecr.io). Required for container deployment.

.PARAMETER Replicas
    Number of container replicas. Default: 3

.PARAMETER WorkersPerReplica
    Workers per replica (OLTP mode). Default: 10

.PARAMETER Connections
    Concurrent connections (Analytics mode). Default: 25

.PARAMETER Duration
    Test duration in seconds. Default: 300

.PARAMETER TargetThroughputMbps
    Target throughput MB/s (OLTP mode). Default: 50

.PARAMETER SkipBuild
    Skip container image build (assumes image already exists)

.PARAMETER SkipInfrastructure
    Skip infrastructure creation (only update container app)

.PARAMETER LocalOnly
    Run locally instead of deploying to Azure

.EXAMPLE
    # Local OLTP test
    .\infrastructure\deploy.ps1 -SqlServer myserver.database.windows.net -LocalOnly

.EXAMPLE
    # Deploy OLTP to Azure
    .\infrastructure\deploy.ps1 -SqlServer myserver.database.windows.net -AcrName myacr -Replicas 3

.EXAMPLE
    # Deploy Analytics test
    .\infrastructure\deploy.ps1 -Mode analytics -SqlServer myserver-replica.database.windows.net -AcrName myacr

.EXAMPLE
    # Update existing deployment with more replicas
    .\infrastructure\deploy.ps1 -SqlServer myserver.database.windows.net -AcrName myacr -Replicas 5 -SkipBuild -SkipInfrastructure

.NOTES
    Prerequisites:
    - Azure CLI installed: https://aka.ms/installazurecli
    - az login completed
    - For local: Python 3.8+, pip install -r requirements.txt
    - For Azure: Docker (for local builds) or Azure Container Registry
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('oltp', 'analytics')]
    [string]$Mode = 'oltp',

    [Parameter(Mandatory=$true)]
    [string]$SqlServer,
    
    [Parameter()]
    [string]$SqlDatabase = "zavatax",
    
    [Parameter()]
    [string]$ResourceGroup = "rg-zavatax-loadsim",
    
    [Parameter()]
    [string]$Location = "eastus2",
    
    [Parameter()]
    [string]$AcrName,
    
    [Parameter()]
    [int]$Replicas = 3,
    
    [Parameter()]
    [int]$WorkersPerReplica = 10,
    
    [Parameter()]
    [int]$Connections = 25,
    
    [Parameter()]
    [int]$Duration = 300,
    
    [Parameter()]
    [int]$TargetThroughputMbps = 50,
    
    [Parameter()]
    [int]$BatchSize = 1000,
    
    [Parameter()]
    [switch]$SkipBuild,
    
    [Parameter()]
    [switch]$SkipInfrastructure,
    
    [Parameter()]
    [switch]$LocalOnly
)

$ErrorActionPreference = "Stop"

# ============================================================================
# Helper Functions
# ============================================================================

function Write-Header {
    param([string]$Text)
    Write-Host ""
    Write-Host "=" * 80 -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host "=" * 80 -ForegroundColor Cyan
    Write-Host ""
}

function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host "▶ $Text" -ForegroundColor Yellow
}

function Test-Command {
    param([string]$CommandName)
    return [bool](Get-Command $CommandName -ErrorAction SilentlyContinue)
}

# ============================================================================
# Validation
# ============================================================================

Write-Header "ZAVATAX LOAD SIMULATOR DEPLOYMENT"

Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  Mode:               $Mode" -ForegroundColor White
Write-Host "  SQL Server:         $SqlServer" -ForegroundColor White
Write-Host "  SQL Database:       $SqlDatabase" -ForegroundColor White
Write-Host "  Local Only:         $LocalOnly" -ForegroundColor White
if (-not $LocalOnly) {
    Write-Host "  Resource Group:     $ResourceGroup" -ForegroundColor White
    Write-Host "  Location:           $Location" -ForegroundColor White
    Write-Host "  ACR:                $AcrName" -ForegroundColor White
    Write-Host "  Replicas:           $Replicas" -ForegroundColor White
    if ($Mode -eq 'oltp') {
        Write-Host "  Workers/Replica:    $WorkersPerReplica" -ForegroundColor White
        Write-Host "  Batch Size:         $BatchSize" -ForegroundColor White
        Write-Host "  Target Throughput:  $TargetThroughputMbps MB/s" -ForegroundColor White
    } else {
        Write-Host "  Connections:        $Connections" -ForegroundColor White
    }
    Write-Host "  Duration:           $Duration seconds" -ForegroundColor White
}

# Check prerequisites
Write-Section "Checking prerequisites"

if (-not (Test-Command "az")) {
    Write-Error "Azure CLI not found. Install from https://aka.ms/installazurecli"
}
Write-Host "✓ Azure CLI installed" -ForegroundColor Green

if (-not (Test-Command "python")) {
    Write-Error "Python not found. Install Python 3.8+ from https://www.python.org/"
}
$pythonVersion = python --version 2>&1
Write-Host "✓ Python installed: $pythonVersion" -ForegroundColor Green

if (-not $LocalOnly -and -not (Test-Command "docker")) {
    Write-Warning "Docker not found. Will use Azure Container Registry build."
}

# Check Azure login
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "⚠ Not logged in to Azure. Running 'az login'..." -ForegroundColor Yellow
    az login
    $account = az account show | ConvertFrom-Json
}
Write-Host "✓ Azure login verified: $($account.user.name)" -ForegroundColor Green
Write-Host "  Subscription: $($account.name)" -ForegroundColor Gray

# ============================================================================
# Local Execution
# ============================================================================

if ($LocalOnly) {
    Write-Header "LOCAL EXECUTION MODE"
    
    # Navigate to load-simulator directory
    $scriptPath = Split-Path -Parent $PSCommandPath
    $repoRoot = Split-Path -Parent $scriptPath
    Set-Location $repoRoot
    
    Write-Section "Setting up Python environment"
    
    # Create virtual environment if needed
    if (-not (Test-Path "venv")) {
        Write-Host "Creating Python virtual environment..." -ForegroundColor Yellow
        python -m venv venv
    }
    
    Write-Host "Activating virtual environment..." -ForegroundColor Yellow
    & ".\venv\Scripts\Activate.ps1"
    
    Write-Host "Installing dependencies..." -ForegroundColor Yellow
    pip install -r requirements.txt --quiet
    
    Write-Host "✓ Python environment ready" -ForegroundColor Green
    
    # Set environment variables
    Write-Section "Configuring environment"
    
    $env:SQL_SERVER = $SqlServer
    $env:SQL_DATABASE = $SqlDatabase
    
    Write-Host "✓ Environment configured" -ForegroundColor Green
    Write-Host "  SQL_SERVER=$SqlServer" -ForegroundColor Gray
    Write-Host "  SQL_DATABASE=$SqlDatabase" -ForegroundColor Gray
    
    # Run appropriate test
    Write-Section "Starting load test"
    Write-Host ""
    Write-Host "Press Ctrl+C to stop the test at any time" -ForegroundColor Yellow
    Write-Host ""
    
    Start-Sleep -Seconds 2
    
    if ($Mode -eq 'oltp') {
        Write-Host "Running OLTP load test..." -ForegroundColor Cyan
        python -m oltp.main --workers $WorkersPerReplica --batch-size $BatchSize --duration $Duration --target-mbps $TargetThroughputMbps
    } else {
        Write-Host "Running Analytics load test..." -ForegroundColor Cyan
        python -m analytics.main --connections $Connections --duration $Duration --server $SqlServer --database $SqlDatabase
    }
    
    Write-Host ""
    Write-Host "✓ Local test completed" -ForegroundColor Green
    exit 0
}

# ============================================================================
# Azure Container Apps Deployment
# ============================================================================

Write-Header "AZURE CONTAINER APPS DEPLOYMENT"

if (-not $AcrName) {
    Write-Error "ACR name required for Azure deployment. Use -AcrName parameter or -LocalOnly for local execution."
}

$appName = "zavatax-simulator-$Mode"
$envName = "zavatax-loadsim-env"
$identityName = "zavatax-simulator-identity"
$imageName = "$AcrName.azurecr.io/load-simulator:latest"

# ============================================================================
# Infrastructure Creation
# ============================================================================

if (-not $SkipInfrastructure) {
    Write-Section "Creating infrastructure"
    
    # Resource Group
    Write-Host "Creating resource group '$ResourceGroup'..." -ForegroundColor Yellow
    az group create `
        --name $ResourceGroup `
        --location $Location `
        --output none
    Write-Host "✓ Resource group ready" -ForegroundColor Green
    
    # Container Registry
    Write-Host "Ensuring container registry '$AcrName' exists..." -ForegroundColor Yellow
    $acrExists = az acr show --name $AcrName --resource-group $ResourceGroup 2>$null
    if (-not $acrExists) {
        Write-Host "  Creating new ACR..." -ForegroundColor Gray
        az acr create `
            --name $AcrName `
            --resource-group $ResourceGroup `
            --sku Basic `
            --admin-enabled false `
            --output none
    }
    Write-Host "✓ Container registry ready" -ForegroundColor Green
    
    # Managed Identity
    Write-Host "Creating managed identity '$identityName'..." -ForegroundColor Yellow
    $identityJson = az identity create `
        --name $identityName `
        --resource-group $ResourceGroup `
        --location $Location `
        --output json
    
    if (-not $identityJson) {
        # Identity might already exist, retrieve it
        $identityJson = az identity show `
            --name $identityName `
            --resource-group $ResourceGroup `
            --output json
    }
    
    $identity = $identityJson | ConvertFrom-Json
    $identityId = $identity.id
    $identityClientId = $identity.clientId
    $identityPrincipalId = $identity.principalId
    
    Write-Host "✓ Managed identity ready" -ForegroundColor Green
    Write-Host "  Client ID: $identityClientId" -ForegroundColor Gray
    Write-Host "  Principal ID: $identityPrincipalId" -ForegroundColor Gray
    
    # Container Apps Environment
    Write-Host "Creating Container Apps environment '$envName'..." -ForegroundColor Yellow
    $envExists = az containerapp env show --name $envName --resource-group $ResourceGroup 2>$null
    if (-not $envExists) {
        az containerapp env create `
            --name $envName `
            --resource-group $ResourceGroup `
            --location $Location `
            --output none
    }
    Write-Host "✓ Container Apps environment ready" -ForegroundColor Green
    
    Write-Host ""
    Write-Host "Infrastructure deployment complete!" -ForegroundColor Green
}

# ============================================================================
# Container Image Build
# ============================================================================

if (-not $SkipBuild) {
    Write-Section "Building container image"
    
    # Navigate to load-simulator directory
    $scriptPath = Split-Path -Parent $PSCommandPath
    $repoRoot = Split-Path -Parent $scriptPath
    Set-Location $repoRoot
    
    Write-Host "Building and pushing image to ACR..." -ForegroundColor Yellow
    Write-Host "  Image: $imageName" -ForegroundColor Gray
    
    az acr build `
        --registry $AcrName `
        --image load-simulator:latest `
        --file Dockerfile `
        --platform linux/amd64 `
        .
    
    Write-Host "✓ Container image built and pushed" -ForegroundColor Green
}

# ============================================================================
# Container App Deployment
# ============================================================================

Write-Section "Deploying Container App"

# Get identity information if we skipped infrastructure
if ($SkipInfrastructure) {
    Write-Host "Retrieving existing identity..." -ForegroundColor Yellow
    $identityJson = az identity show `
        --name $identityName `
        --resource-group $ResourceGroup `
        --output json
    $identity = $identityJson | ConvertFrom-Json
    $identityId = $identity.id
    $identityClientId = $identity.clientId
    $identityPrincipalId = $identity.principalId
}

# Define environment variables based on mode
if ($Mode -eq 'oltp') {
    $envVars = @(
        "SQL_SERVER=$SqlServer"
        "SQL_DATABASE=$SqlDatabase"
        "AZURE_CLIENT_ID=$identityClientId"
        "NUM_WORKERS=$WorkersPerReplica"
        "BATCH_SIZE=$BatchSize"
        "TARGET_THROUGHPUT_MBPS=$TargetThroughputMbps"
        "DURATION_SECONDS=$Duration"
        "METRICS_ENABLED=true"
        "METRICS_PORT=8000"
        "LOG_LEVEL=INFO"
    )
} else {
    $envVars = @(
        "SQL_SERVER=$SqlServer"
        "SQL_DATABASE=$SqlDatabase"
        "AZURE_CLIENT_ID=$identityClientId"
        "ANALYTICS_CONNECTIONS=$Connections"
        "DURATION_SECONDS=$Duration"
        "LOG_LEVEL=INFO"
    )
}

# Check if container app exists
$appExists = az containerapp show --name $appName --resource-group $ResourceGroup 2>$null

if ($appExists) {
    Write-Host "Updating existing container app '$appName'..." -ForegroundColor Yellow
    
    az containerapp update `
        --name $appName `
        --resource-group $ResourceGroup `
        --image $imageName `
        --set-env-vars $envVars `
        --min-replicas $Replicas `
        --max-replicas $Replicas `
        --output none
        
} else {
    Write-Host "Creating new container app '$appName'..." -ForegroundColor Yellow
    
    # Build command based on mode
    $command = if ($Mode -eq 'oltp') { 
        @("python", "-m", "oltp.main")
    } else { 
        @("python", "-m", "analytics.main", "--connections", "$Connections", "--duration", "$Duration")
    }
    
    az containerapp create `
        --name $appName `
        --resource-group $ResourceGroup `
        --environment $envName `
        --image $imageName `
        --user-assigned $identityId `
        --cpu 2.0 `
        --memory 4Gi `
        --min-replicas $Replicas `
        --max-replicas $Replicas `
        --ingress external `
        --target-port 8000 `
        --env-vars $envVars `
        --command $command `
        --output none
}

Write-Host "✓ Container app deployed" -ForegroundColor Green

# Get app URL
$appJson = az containerapp show `
    --name $appName `
    --resource-group $ResourceGroup `
    --query "properties.configuration.ingress.fqdn" `
    --output json | ConvertFrom-Json

$appUrl = "https://$appJson"

# ============================================================================
# Post-Deployment Instructions
# ============================================================================

Write-Header "DEPLOYMENT COMPLETE"

Write-Host "Container App URL: " -ForegroundColor Cyan -NoNewline
Write-Host $appUrl -ForegroundColor White

if ($Mode -eq 'oltp') {
    Write-Host "Metrics URL: " -ForegroundColor Cyan -NoNewline
    Write-Host "$appUrl/metrics" -ForegroundColor White
}

Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Grant SQL access to the managed identity" -ForegroundColor White
Write-Host "   Run this SQL against '$SqlDatabase' database:" -ForegroundColor Gray
Write-Host ""
Write-Host "   CREATE USER [$identityName] FROM EXTERNAL PROVIDER;" -ForegroundColor Cyan
Write-Host "   ALTER ROLE db_datawriter ADD MEMBER [$identityName];" -ForegroundColor Cyan
Write-Host "   ALTER ROLE db_datareader ADD MEMBER [$identityName];" -ForegroundColor Cyan
Write-Host "   GRANT EXECUTE ON SCHEMA::dbo TO [$identityName];" -ForegroundColor Cyan
Write-Host ""

Write-Host "2. Monitor the load test:" -ForegroundColor White
Write-Host "   Container logs:" -ForegroundColor Gray
Write-Host "   az containerapp logs show --name $appName --resource-group $ResourceGroup --follow" -ForegroundColor Cyan
Write-Host ""
if ($Mode -eq 'oltp') {
    Write-Host "   Prometheus metrics:" -ForegroundColor Gray
    Write-Host "   curl $appUrl/metrics" -ForegroundColor Cyan
    Write-Host ""
}
Write-Host "   SQL Database metrics:" -ForegroundColor Gray
Write-Host "   Azure Portal → SQL Database → Monitoring → Metrics" -ForegroundColor Cyan
Write-Host ""

Write-Host "3. Scale replicas (optional):" -ForegroundColor White
Write-Host "   az containerapp update --name $appName --resource-group $ResourceGroup --min-replicas 5 --max-replicas 5" -ForegroundColor Cyan
Write-Host ""

Write-Host "Identity Details:" -ForegroundColor Gray
Write-Host "  Client ID:    $identityClientId" -ForegroundColor DarkGray
Write-Host "  Principal ID: $identityPrincipalId" -ForegroundColor DarkGray
Write-Host ""

Write-Host "Deployment successful!" -ForegroundColor Green
