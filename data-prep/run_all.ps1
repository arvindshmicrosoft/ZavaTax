# Zava Tax Data Preparation - Run All Steps
# Usage: .\run_all.ps1

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ZAVA TAX DATA PREPARATION PIPELINE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check for .env file
if (-not (Test-Path ".env")) {
    Write-Host "ERROR: .env file not found!" -ForegroundColor Red
    Write-Host "Copy .env.template to .env and configure your settings." -ForegroundColor Yellow
    exit 1
}

# Check Python
try {
    $pythonVersion = python --version 2>&1
    Write-Host "Using: $pythonVersion" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Python not found in PATH" -ForegroundColor Red
    exit 1
}

# --- Scale Factor Summary ---
# Read current settings from .env
$envVars = @{}
Get-Content ".env" | ForEach-Object {
    if ($_ -match '^\s*([A-Z_]+)\s*=\s*(.+)$' -and $_ -notmatch '^\s*#') {
        $envVars[$Matches[1]] = $Matches[2].Trim()
    }
}

$pubPriority     = if ($envVars['PUBLICATION_PRIORITY']) { $envVars['PUBLICATION_PRIORITY'] } else { '1' }
$scenarioCount   = if ($envVars['SCENARIO_COUNT'])   { $envVars['SCENARIO_COUNT'] }   else { '5000' }
$operationalRows = if ($envVars['OPERATIONAL_ROWS']) { $envVars['OPERATIONAL_ROWS'] } else { '1000000' }
$branches        = if ($envVars['BRANCHES'])          { $envVars['BRANCHES'] }          else { '500' }
$customers       = if ($envVars['CUSTOMERS'])         { $envVars['CUSTOMERS'] }         else { '10000' }
$professionals   = if ($envVars['PROFESSIONALS'])     { $envVars['PROFESSIONALS'] }     else { '2500' }

# Estimate DB sizes based on scale
$returnsK = [math]::Round([int]$operationalRows / 1000)
$estFilingRows = [math]::Round([int]$operationalRows * 65)  # ~65 detail rows per return
$estFilingGB   = [math]::Round($estFilingRows * 150 / 1e9, 1)  # ~150 bytes/row compressed

Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "  SCALE FACTORS (from .env)" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
$pubTierDesc = switch ($pubPriority) { '1' {'Core (12 pubs)'} '2' {'Core + Deductions (40 pubs)'} '3' {'Core + Business (75 pubs)'} '4' {'All (100 pubs)'} default {"Tier $pubPriority"} }
Write-Host "  Publication priority:          $pubPriority — $pubTierDesc" -ForegroundColor White
Write-Host "  Scenarios (knowledge search):  $scenarioCount" -ForegroundColor White
Write-Host "  Tax returns (operational):     ${operationalRows} (${returnsK}K)" -ForegroundColor White
Write-Host "  Branches:                      $branches" -ForegroundColor White
Write-Host "  Professionals:                 $professionals (auto-scaled to branches)" -ForegroundColor White
Write-Host "  Customers:                     $customers" -ForegroundColor White
Write-Host "" -ForegroundColor White
Write-Host "  After 08_generate_filing_details.sql:" -ForegroundColor DarkGray
Write-Host "    Estimated detail rows: ~$([string]::Format('{0:N0}', $estFilingRows))" -ForegroundColor DarkGray
Write-Host "    Estimated DB size:     ~${estFilingGB} GB compressed" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  To change: edit data-prep/.env (SCENARIO_COUNT, OPERATIONAL_ROWS, BRANCHES, etc.)" -ForegroundColor DarkGray
Write-Host "  Common presets:" -ForegroundColor DarkGray
Write-Host "    Quick demo:    OPERATIONAL_ROWS=100000   (~1 GB after filing details)" -ForegroundColor DarkGray
Write-Host "    Default:       OPERATIONAL_ROWS=1000000  (~10 GB after filing details)" -ForegroundColor DarkGray
Write-Host "    Large demo:    OPERATIONAL_ROWS=10000000 (~100 GB after filing details)" -ForegroundColor DarkGray
Write-Host "    Full scale:    OPERATIONAL_ROWS=50000000 (~300+ GB after filing details)" -ForegroundColor DarkGray
Write-Host ""

$continue = Read-Host "Continue with these settings? [Y/n]"
if ($continue -eq 'n' -or $continue -eq 'N') {
    Write-Host "Edit .env and re-run .\run_all.ps1 when ready." -ForegroundColor Yellow
    exit 0
}

# Install dependencies if needed
Write-Host ""
Write-Host "Step 0: Checking dependencies..." -ForegroundColor Yellow
pip install -r requirements.txt --quiet

# Step 1: Download IRS Publications
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Step 1: Download IRS Publications" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
python 01_download_irs_pubs.py --priority $pubPriority
if ($LASTEXITCODE -ne 0) {
    Write-Host "WARNING: Some downloads may have failed. Continuing..." -ForegroundColor Yellow
}

# Step 2: Parse and Chunk
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Step 2: Parse and Chunk Publications" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
python 02_parse_and_chunk.py
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Parsing failed" -ForegroundColor Red
    exit 1
}

# Step 3: Generate Embeddings for Knowledge Base
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Step 3: Generate Knowledge Base Embeddings" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
python 03_generate_embeddings.py
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Embedding generation failed" -ForegroundColor Red
    exit 1
}

# Step 4: Generate Tax Scenarios
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Step 4: Generate Tax Scenarios" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
python 04_generate_scenarios.py --count $scenarioCount
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Scenario generation failed" -ForegroundColor Red
    exit 1
}

# Step 5: Generate Embeddings for Scenarios
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Step 5: Generate Scenario Embeddings" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
python 05_embed_scenarios.py
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Scenario embedding failed" -ForegroundColor Red
    exit 1
}

# Step 6: Generate Operational Data
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Step 6: Generate Operational Data" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
python 06_generate_operational_data.py --rows $operationalRows --branches $branches --customers $customers --professionals $professionals
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Operational data generation failed" -ForegroundColor Red
    exit 1
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  DATA PREPARATION COMPLETE!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Output files in data/output/:" -ForegroundColor Cyan

Get-ChildItem -Path "data/output" | ForEach-Object {
    $size = "{0:N2} MB" -f ($_.Length / 1MB)
    Write-Host ("  - {0,-40} {1,10}" -f $_.Name, $size)
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow

# Load .env values for customized output
$envFile = Join-Path $PSScriptRoot ".env"
if (Test-Path $envFile) {
    $env = @{}
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*([A-Z_]+)\s*=\s*(.+)$' -and $_ -notmatch '^\s*#') {
            $env[$Matches[1]] = $Matches[2].Trim()
        }
    }
    $server   = $env['SQL_SERVER']
    $database = $env['SQL_DATABASE']
    $storage  = $env['STORAGE_ACCOUNT']
    $container = $env['STORAGE_CONTAINER']
    $identity = $env['IDENTITY_CLIENT_ID']

    Write-Host "  1. Upload data files to blob storage:" -ForegroundColor White
    Write-Host "     az storage blob upload-batch --account-name $storage --destination $container --source ./data/output --auth-mode login" -ForegroundColor DarkGray
    Write-Host "  2. Load data to Azure SQL (args auto-populated from .env):" -ForegroundColor White
    Write-Host "     python 07_load_to_azure_sql.py" -ForegroundColor DarkGray
    Write-Host "     (or explicitly: python 07_load_to_azure_sql.py --server $server --database $database --storage-account $storage --container $container --identity-client-id $identity)" -ForegroundColor DarkGray
    Write-Host "  3. Generate filing detail records (P0 + P1 tables, ~300GB):" -ForegroundColor White
    Write-Host "     sqlcmd -S $server -d $database -G -i ../database/08_generate_filing_details.sql" -ForegroundColor DarkGray
} else {
    Write-Host "  1. Upload data files to blob storage" -ForegroundColor White
    Write-Host "  2. Load data: python 07_load_to_azure_sql.py (Azure) or python 07_load_to_sqlexpress.py (local)" -ForegroundColor White
    Write-Host "  3. Generate filing detail records: sqlcmd ... -i ../database/08_generate_filing_details.sql" -ForegroundColor White
    Write-Host "  (Tip: run deploy.ps1 first to auto-generate .env with resource names)" -ForegroundColor DarkGray
}
Write-Host ""
