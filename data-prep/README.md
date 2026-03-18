# Zava Tax - Data Preparation Scripts

This directory contains scripts to prepare all data needed for the Zava Tax demo.

> **IRS Content Notice:** Content in this repository is for demonstration purposes
> only. Neither this demonstration application nor Microsoft is affiliated with or
> endorsed by the IRS. IRS publications are U.S. Government Works
> ([17 U.S.C. § 105](https://www.law.cornell.edu/uscode/text/17/105)) and may be freely
> used per [Use of Content from IRS.gov](https://www.irs.gov/about-irs/use-of-content-from-irsgov).
> All customer data is synthetic. No part of this repository should be construed as tax advice.

## Quick Start

### 1. Prerequisites

- Python 3.10 or higher
- Azure OpenAI resource with:
  - `text-embedding-ada-002` deployment (for embeddings)
  - `gpt-4` deployment (optional, for enhanced scenarios)
- Azure SQL Database Hyperscale instance

### 2. Setup

```powershell
# Navigate to data-prep directory
cd data-prep

# Create virtual environment (recommended)
python -m venv venv
.\venv\Scripts\Activate.ps1

# Install dependencies
pip install -r requirements.txt

# Configure environment
# Option A: If you ran deploy.ps1, .env was auto-generated with actual Azure resource names — skip this step
# Option B: For local dev, copy the template and fill in your values
Copy-Item .env.template .env
notepad .env
```

### 3. Run Pipeline

**Option A: Run all steps (recommended for first setup)**
```powershell
.\run_all.ps1
```

**Option B: Run individual steps**
```powershell
# Step 1: Download IRS publications
python 01_download_irs_pubs.py --priority 1   # or 2, 3, 4 — see Customization

# Step 2: Parse and chunk
python 02_parse_and_chunk.py

# Step 3: Generate knowledge base embeddings (reads endpoint/deployment from .env)
python 03_generate_embeddings.py

# Step 4: Generate tax scenarios
python 04_generate_scenarios.py --count 5000

# Step 5: Generate scenario embeddings (reads endpoint/deployment from .env)
python 05_embed_scenarios.py

# Step 6: Generate operational data
python 06_generate_operational_data.py --rows 1000000
```

> **Note:** Steps 3 and 5 require `AZURE_OPENAI_ENDPOINT` and `AZURE_OPENAI_EMBEDDING_DEPLOYMENT`
> to be set in `.env` (or passed via `--endpoint` and `--deployment` CLI args).

## Pipeline Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        DATA PREPARATION PIPELINE                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Step 1: Download IRS Publications                                          │
│  ─────────────────────────────────                                          │
│  • Downloads HTML from IRS.gov                                              │
│  • Downloads publications up to PUBLICATION_PRIORITY tier (default: 1)      │
│  • Priority 1: Core (12), 2: +Deductions (40), 3: +Business (75), 4: All  │
│  • Output: data/raw/*.html                                                  │
│  • Time: ~2 minutes                                                         │
│                                                                              │
│                           ↓                                                  │
│                                                                              │
│  Step 2: Parse and Chunk                                                    │
│  ───────────────────────                                                    │
│  • Extracts text from HTML                                                  │
│  • Chunks into ~500 token segments with overlap                            │
│  • Preserves section hierarchy                                              │
│  • Output: data/processed/knowledge_base_chunks.json                       │
│  • Time: ~1 minute                                                          │
│                                                                              │
│                           ↓                                                  │
│                                                                              │
│  Step 3: Generate Knowledge Base Embeddings                                 │
│  ──────────────────────────────────────────                                 │
│  • Calls Azure OpenAI embedding API                                         │
│  • Batch processing with rate limit handling                               │
│  • Output: data/output/knowledge_base_embedded.json                        │
│  • Time: ~5 minutes (500 chunks)                                           │
│  • Cost: ~$0.02                                                             │
│                                                                              │
│                           ↓                                                  │
│                                                                              │
│  Step 4: Generate Tax Scenarios                                             │
│  ─────────────────────────────                                              │
│  • Rule-based synthetic generation                                          │
│  • Realistic income/deduction distributions                                │
│  • Multiple scenario types (W-2, self-employed, crypto, etc.)             │
│  • Output: data/output/tax_scenarios.json                                  │
│  • Time: ~2 minutes (5,000 scenarios)                                      │
│                                                                              │
│                           ↓                                                  │
│                                                                              │
│  Step 5: Generate Scenario Embeddings                                       │
│  ────────────────────────────────────                                       │
│  • Embeds scenario summaries for similarity search                         │
│  • Output: data/output/tax_scenarios_embedded.json                         │
│  • Time: ~15 minutes (5,000 scenarios)                                     │
│  • Cost: ~$0.20                                                             │
│                                                                              │
│                           ↓                                                  │
│                                                                              │
│  Step 6: Generate Operational Data                                          │
│  ─────────────────────────────────                                          │
│  • Branches, professionals, customers                                       │
│  • Tax returns (for columnstore demo)                                      │
│  • Output: data/output/*.csv                                                │
│  • Time: ~5 minutes (1M rows)                                              │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Output Files

After running the pipeline, you'll have:

```
data/
├── raw/                              # Downloaded HTML files
│   ├── p17.html
│   ├── p587.html
│   └── ...
│
├── processed/                        # Intermediate files
│   └── knowledge_base_chunks.json    # Chunks without embeddings
│
└── output/                           # Final files for SQL load
    ├── knowledge_base_embedded.json  # Knowledge chunks + embeddings
    ├── tax_scenarios_embedded.json   # Scenarios + embeddings
    ├── branches.csv                  # 500 branches
    ├── tax_professionals.csv         # ~2,500 professionals (3-8 per branch)
    ├── customers.csv                 # 10,000 customers
    └── tax_returns_fact.csv          # 1,000,000 returns
```

## Customization

### Scale Factors (`.env`)

The `.env` file controls data volumes. `run_all.ps1` reads these and prompts before starting.

| Variable | Default | Description |
|----------|---------|-------------|
| `PUBLICATION_PRIORITY` | `1` | IRS publication download tier (see table below) |
| `SCENARIO_COUNT` | `5000` | Tax scenarios for knowledge search demo |
| `OPERATIONAL_ROWS` | `1000000` | Tax return rows (the main scale driver) |
| `BRANCHES` | `500` | Number of branch offices |
| `CUSTOMERS` | `10000` | Number of customer records |
| `PROFESSIONALS` | `2500` | Min tax professionals (auto-scales to 3-8 per branch) |
| `CHUNK_SIZE` | `500` | Tokens per knowledge base chunk |

**Presets** (`OPERATIONAL_ROWS` → approx DB size after `08_generate_filing_details.sql`):

| Preset | OPERATIONAL_ROWS | Filing detail rows | DB size |
|--------|-----------------|-------------------|---------|
| Quick demo | `100000` | ~6.5M | ~1 GB |
| Default | `1000000` | ~65M | ~10 GB |
| Large demo | `10000000` | ~650M | ~100 GB |
| Full scale | `50000000` | ~3.2B | ~300+ GB |

### Adjust Data Volumes (CLI overrides)

```powershell
# Or override .env via CLI args:
python 04_generate_scenarios.py --count 500
python 06_generate_operational_data.py --rows 100000 --branches 50 --customers 1000
```

### Publication Priority Tiers

`PUBLICATION_PRIORITY` in `.env` controls how many IRS publications are downloaded in step 1.
Higher tiers include all lower tiers and produce a larger knowledge base.

| Priority | Publications | Topics | KB chunks |
|----------|-------------|--------|-----------|
| `1` (default) | 12 | Core individual tax (Pub 17, 501, 525, 596...) | ~2,000 |
| `2` | 40 | + Deductions, credits, income types | ~6,000 |
| `3` | 75 | + Business, self-employment, special situations | ~12,000 |
| `4` | 100 | + International, estate, niche topics | ~16,000 |

To change: set `PUBLICATION_PRIORITY=2` (or 3, 4) in `.env` before running `run_all.ps1`.

### Expanding the Knowledge Base After Initial Setup

To download more publications and rebuild the knowledge base without regenerating operational data:

```powershell
# 1. Download additional publications (e.g., up to priority 3)
python 01_download_irs_pubs.py --priority 3

# 2. Re-chunk all downloaded publications (processes new + existing)
python 02_parse_and_chunk.py

# 3. Re-generate embeddings for the full knowledge base
python 03_generate_embeddings.py

# 4. Re-upload and reload the knowledge base to Azure SQL
#    (use --force on 07_load if TaxKnowledgeBase already has rows,
#     or TRUNCATE TaxKnowledgeBase first)
```

Steps 4-6 (scenarios, operational data) do NOT need to be re-run — only the knowledge base pipeline (steps 1-3) is affected.

### Add Custom Publications

To add publications not in the built-in list, edit `config.py` → `IRS_PUBLICATIONS`, then:
```powershell
python 01_download_irs_pubs.py --all
python 02_parse_and_chunk.py
python 03_generate_embeddings.py
```

## Troubleshooting

### Rate Limits
If you hit Azure OpenAI rate limits:
- The scripts automatically wait and retry
- Reduce batch size: `python 03_generate_embeddings.py --batch-size 50`
- Request quota increase in Azure portal

### Download Failures
If IRS website is slow:
- Increase delay: `python 01_download_irs_pubs.py --delay 3`
- Download PDFs manually and place in `data/raw/`

### Memory Issues
For large operational data:
- Reduce batch size in generation
- Process in chunks: `python 06_generate_operational_data.py --rows 100000` (run multiple times)

## Estimated Time and Cost

| Step | Time | Azure OpenAI Cost |
|------|------|-------------------|
| Download IRS Pubs | 2 min | $0 |
| Parse and Chunk | 1 min | $0 |
| Knowledge Embeddings | 5 min | ~$0.02 |
| Generate Scenarios | 2 min | $0 |
| Scenario Embeddings | 15 min | ~$0.20 |
| Operational Data | 5 min | $0 |
| **Total** | **~30 min** | **~$0.25** |

## Next Steps

After data preparation:
1. Load data to Azure SQL DB Hyperscale
2. Create vector indexes (DiskANN)
3. Create columnstore indexes
4. Validate with test queries
5. Run demo scenarios
