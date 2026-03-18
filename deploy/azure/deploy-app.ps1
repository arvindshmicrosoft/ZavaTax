<#
.SYNOPSIS
    Deploys the ZavaTax web application to Azure App Service.

.DESCRIPTION
    This script builds and deploys the ZavaTax React web application to an existing
    Azure App Service. Use this script for subsequent application deployments after
    the infrastructure has been created with deploy.ps1.

.PARAMETER ResourceGroupName
    The name of the resource group containing the App Service.

.PARAMETER WebAppName
    The name of the Azure App Service to deploy to.

.PARAMETER ApiBaseUrl
    The base URL of the Data API Builder endpoint.

.EXAMPLE
    .\deploy-app.ps1 -ResourceGroupName "rg-<your-env>" -WebAppName "app-<your-env>-web" -ApiBaseUrl "https://app-<your-env>-dab.azurewebsites.net"

.NOTES
    Requires Azure CLI and Node.js to be installed.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$WebAppName,

    [Parameter(Mandatory = $true)]
    [string]$ApiBaseUrl,

    [Parameter()]
    [switch]$SkipBuild,

    [Parameter()]
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

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

# ============================================================================
# VALIDATION
# ============================================================================

Write-Host ""
Write-Host "ZavaTax Application Deployment" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan
Write-Host ""

Write-Step "Validating prerequisites..."

# Check Azure CLI
try {
    $null = az --version 2>&1
} catch {
    throw "Azure CLI is not installed. Please install it from https://docs.microsoft.com/cli/azure/install-azure-cli"
}

# Check Azure login
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    throw "Not logged in to Azure. Please run 'az login' first."
}
Write-Info "Logged in as: $($account.user.name)"

# Verify App Service exists
Write-Step "Verifying App Service exists..."
$appService = az webapp show --resource-group $ResourceGroupName --name $WebAppName 2>$null | ConvertFrom-Json
if (-not $appService) {
    throw "App Service '$WebAppName' not found in resource group '$ResourceGroupName'"
}
Write-Info "App Service: $WebAppName"
Write-Info "URL: https://$($appService.defaultHostName)"

# Find webapp directory
$scriptRoot = $PSScriptRoot
$repoRoot = Split-Path (Split-Path $scriptRoot -Parent) -Parent
$webappDir = Join-Path $repoRoot "webapp"

if (-not (Test-Path $webappDir)) {
    throw "Webapp directory not found at: $webappDir"
}

Write-Success "Prerequisites validated"

# ============================================================================
# BUILD APPLICATION
# ============================================================================

if (-not $SkipBuild) {
    Write-Host ""
    Write-Host "Building Application" -ForegroundColor Cyan
    Write-Host "====================" -ForegroundColor Cyan
    Write-Host ""

    Push-Location $webappDir
    try {
        Write-Step "Installing dependencies..."
        npm ci
        if ($LASTEXITCODE -ne 0) {
            throw "npm ci failed"
        }
        Write-Success "Dependencies installed"

        Write-Step "Building production bundle..."
        $env:VITE_API_BASE_URL = "$ApiBaseUrl/api"
        npm run build
        if ($LASTEXITCODE -ne 0) {
            throw "npm build failed"
        }
        Write-Success "Build complete"
    }
    finally {
        Pop-Location
    }
}

# ============================================================================
# DEPLOY APPLICATION
# ============================================================================

Write-Host ""
Write-Host "Deploying to Azure" -ForegroundColor Cyan
Write-Host "==================" -ForegroundColor Cyan
Write-Host ""

$distPath = Join-Path $webappDir "dist"
if (-not (Test-Path $distPath)) {
    throw "Build output not found at: $distPath. Run without -SkipBuild first."
}

Write-Step "Creating deployment package..."
$zipPath = Join-Path $env:TEMP "zavatax-webapp-$(Get-Date -Format 'yyyyMMddHHmmss').zip"
Compress-Archive -Path "$distPath\*" -DestinationPath $zipPath -Force
Write-Info "Package: $zipPath"
Write-Info "Size: $([math]::Round((Get-Item $zipPath).Length / 1MB, 2)) MB"

if (-not $WhatIf) {
    try {
        Write-Step "Deploying to App Service..."
        az webapp deploy `
            --resource-group $ResourceGroupName `
            --name $WebAppName `
            --src-path $zipPath `
            --type zip `
            --async true
        
        if ($LASTEXITCODE -ne 0) {
            throw "Deployment failed"
        }
        
        Write-Success "Deployment complete"
        Write-Host ""
        Write-Host "Application URL: https://$($appService.defaultHostName)" -ForegroundColor Green
    }
    finally {
        if (Test-Path $zipPath) {
            Remove-Item $zipPath -Force
        }
    }
} else {
    Write-Info "What-If mode: Skipping actual deployment"
    Write-Info "Would deploy $zipPath to $WebAppName"
    Remove-Item $zipPath -Force
}

Write-Host ""
Write-Success "Done!"
Write-Host ""
