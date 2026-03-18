# Zava Tax - Data Strategy and RAG Design

> **📜 IRS Content Disclaimer:** Content in this repository is for **demonstration purposes only**. Neither this demonstration application nor Microsoft is **affiliated with or endorsed by the Internal Revenue Service (IRS)**, the U.S. Department of the Treasury, or any U.S. government agency. IRS publications are **U.S. Government Works** ([17 U.S.C. § 105](https://www.law.cornell.edu/uscode/text/17/105)) and may be freely used per [Use of Content from IRS.gov](https://www.irs.gov/about-irs/use-of-content-from-irsgov). All customer data is synthetic. **No part of this repository should be construed as tax advice.**

## Overview

This document details the data sources, preparation steps, and RAG demonstration strategy for the Zava Tax application. It answers key questions about what data will power the AI-assisted tax guidance and how we'll demonstrate the capabilities.

---

## Table of Contents

1. [Data Sources for Vector Search](#data-sources-for-vector-search)
2. [RAG Demonstration Strategy](#rag-demonstration-strategy)
3. [Data Preparation Steps](#data-preparation-steps)
4. [Public Data Sources and GitHub Projects](#public-data-sources-and-github-projects)
5. [Synthetic Data Generation](#synthetic-data-generation)
6. [Data Ingestion Pipeline](#data-ingestion-pipeline)

---

## Data Sources for Vector Search

### Primary Data Categories

We need three categories of data to power meaningful AI-assisted tax guidance:

| Category | Purpose | Source Type | Volume Estimate |
|----------|---------|-------------|-----------------|
| **Tax Knowledge Base** | Answer "how do I..." questions | Public IRS content | ~5,000 chunks |
| **Historical Tax Scenarios** | Find similar cases | Synthetic generation | ~50,000 scenarios |
| **Tax Form Reference** | Form field explanations | Public IRS instructions | ~2,000 chunks |

---

### Category 1: Tax Knowledge Base (IRS Publications & Guidance)

**What it is**: Authoritative tax guidance from IRS publications, chunked and embedded for semantic search.

**Source Documents** (All publicly available from IRS.gov):

| Publication | Title | Content Type | Estimated Chunks |
|-------------|-------|--------------|------------------|
| Pub 17 | Your Federal Income Tax | Comprehensive individual tax guide | ~800 chunks |
| Pub 501 | Dependents, Standard Deduction, Filing Info | Filing requirements | ~150 chunks |
| Pub 502 | Medical and Dental Expenses | Itemized deductions | ~200 chunks |
| Pub 503 | Child and Dependent Care Expenses | Credits | ~100 chunks |
| Pub 504 | Divorced or Separated Individuals | Special situations | ~150 chunks |
| Pub 505 | Tax Withholding and Estimated Tax | Withholding | ~200 chunks |
| Pub 523 | Selling Your Home | Capital gains | ~150 chunks |
| Pub 525 | Taxable and Nontaxable Income | Income types | ~300 chunks |
| Pub 526 | Charitable Contributions | Deductions | ~200 chunks |
| Pub 527 | Residential Rental Property | Rental income | ~250 chunks |
| Pub 529 | Miscellaneous Deductions | Various deductions | ~150 chunks |
| Pub 530 | Tax Information for Homeowners | Home-related tax | ~150 chunks |
| Pub 535 | Business Expenses | Self-employment | ~400 chunks |
| Pub 550 | Investment Income and Expenses | Investments | ~350 chunks |
| Pub 551 | Basis of Assets | Cost basis | ~150 chunks |
| Pub 554 | Tax Guide for Seniors | Senior-specific | ~150 chunks |
| Pub 587 | Business Use of Your Home | Home office | ~200 chunks |
| Pub 590-A/B | IRAs | Retirement | ~300 chunks |
| Pub 596 | Earned Income Credit | EITC | ~150 chunks |
| Pub 936 | Home Mortgage Interest Deduction | Mortgage interest | ~150 chunks |

**Chunking Strategy**:
- Chunk size: 500-800 tokens with 100 token overlap
- Preserve section headers in metadata
- Include publication number and section reference
- Maintain paragraph integrity (don't split mid-paragraph)

**Sample Chunk Structure**:
```json
{
  "chunk_id": "pub587_sec3_001",
  "publication": "Publication 587",
  "publication_title": "Business Use of Your Home",
  "section": "Figuring the Deduction",
  "subsection": "Regular Method",
  "content": "To figure your deduction using the regular method, you must first figure the percentage of your home used for business. Then you apply that percentage to certain expenses...",
  "tax_year": 2025,
  "last_updated": "2025-01-15",
  "url": "https://www.irs.gov/publications/p587#en_US_2025_publink1000226288",
  "embedding": [0.0123, -0.0456, ...] // 1536 dimensions
}
```

---

### Category 2: Historical Tax Scenarios (Synthetic)

**What it is**: Realistic but synthetic tax filing scenarios that allow tax professionals to find "similar cases" for guidance on complex situations.

**Why Synthetic**: We cannot use real tax data due to privacy. We'll generate realistic scenarios that cover common and edge cases.

**Scenario Structure**:
```json
{
  "scenario_id": "SCN-2025-00001",
  "scenario_summary": "Single filer, W-2 employee with side gig income, home office deduction, cryptocurrency transactions",
  "filing_status": "Single",
  "income_sources": ["W-2 Employment", "1099-NEC Freelance", "Cryptocurrency"],
  "deduction_types": ["Home Office (Simplified)", "Business Expenses", "Student Loan Interest"],
  "credits_claimed": ["Lifetime Learning Credit"],
  "special_situations": ["First-time crypto seller", "Partial year home office"],
  "complexity_score": 7,
  "audit_risk_factors": ["High crypto volume", "Home office with W-2"],
  "resolution_notes": "Used Form 8949 for crypto. Simplified home office method ($5/sq ft). Kept freelance and W-2 expenses separate.",
  "outcome": {
    "federal_refund": 2847.00,
    "state_refund": 412.00,
    "effective_tax_rate": 18.3
  },
  "embedding": [0.0234, -0.0567, ...] // 1536 dimensions
}
```

**Scenario Categories to Generate**:

| Category | Count | Complexity | Examples |
|----------|-------|------------|----------|
| Simple W-2 Only | 10,000 | Low | Single income, standard deduction |
| Multiple W-2s | 5,000 | Low-Med | Married, both working |
| Self-Employment | 8,000 | Medium | 1099 income, business expenses |
| Rental Property | 5,000 | Medium-High | Passive income, depreciation |
| Investment Income | 7,000 | Medium | Dividends, capital gains |
| Cryptocurrency | 3,000 | High | Trading, mining, staking |
| Home Office | 4,000 | Medium | Remote work, self-employed |
| Life Events | 5,000 | Variable | Marriage, divorce, baby, death |
| Retirement | 3,000 | Medium-High | IRA distributions, RMDs |
| Edge Cases | 2,000 | High | Multi-state, foreign income, AMT |

---

### Category 3: Tax Form Reference Data

**What it is**: Line-by-line explanations of tax forms and their instructions.

**Forms to Include**:

| Form | Description | Chunks |
|------|-------------|--------|
| 1040 | Individual Income Tax Return | ~100 |
| Schedule A | Itemized Deductions | ~80 |
| Schedule B | Interest and Dividends | ~40 |
| Schedule C | Profit or Loss from Business | ~150 |
| Schedule D | Capital Gains and Losses | ~80 |
| Schedule E | Supplemental Income | ~100 |
| Schedule SE | Self-Employment Tax | ~50 |
| Form 8949 | Sales of Capital Assets | ~60 |
| Form 2441 | Child and Dependent Care | ~50 |
| Form 8863 | Education Credits | ~60 |
| W-2 | Wage and Tax Statement | ~30 |
| 1099 Series | Various information returns | ~200 |

**Chunk Structure**:
```json
{
  "form_id": "1040",
  "form_name": "U.S. Individual Income Tax Return",
  "line_number": "12",
  "line_description": "Standard deduction or itemized deductions",
  "instructions": "Enter the larger of your standard deduction or your itemized deductions from Schedule A. If you checked any box under Standard Deduction, see instructions...",
  "common_questions": [
    "Should I itemize or take standard deduction?",
    "What is the standard deduction amount?",
    "Can I switch between standard and itemized?"
  ],
  "related_forms": ["Schedule A"],
  "tax_year": 2025,
  "embedding": [0.0345, -0.0678, ...]
}
```

---

## RAG Demonstration Strategy

### Demo Flow 1: Customer Tax Question (End User)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     RAG FLOW: CUSTOMER QUESTION                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. CUSTOMER INPUT                                                          │
│     "I started working from home in June. Can I deduct my home office       │
│      even though I'm a W-2 employee?"                                       │
│                                                                              │
│  2. EMBEDDING GENERATION (Azure OpenAI)                                     │
│     Question → text-embedding-3-small → Vector[1536]                        │
│     Latency Target: < 200ms                                                 │
│                                                                              │
│  3. VECTOR SEARCH (Azure SQL DB - RAG Named Replica)                        │
│     ┌─────────────────────────────────────────────────────────────────┐    │
│     │ SELECT TOP 5                                                     │    │
│     │   chunk_id, publication, section, content,                       │    │
│     │   VECTOR_DISTANCE('cosine', ContentEmbedding, @queryVector) AS dist│   │
│     │ FROM TaxKnowledgeBase                                            │    │
│     │ ORDER BY dist                                                    │    │
│     │ -- Uses DiskANN vector index                                     │    │
│     └─────────────────────────────────────────────────────────────────┘    │
│     Latency Target: < 50ms                                                  │
│                                                                              │
│  4. CONTEXT ASSEMBLY                                                        │
│     Retrieved chunks assembled into context:                                │
│     - Pub 587: "Employees cannot deduct home office expenses..."           │
│     - Pub 529: "Unreimbursed employee expenses..."                         │
│     - Pub 535: "If you are self-employed, you may deduct..."              │
│                                                                              │
│  5. LLM GENERATION (Azure OpenAI GPT-5.2)                                   │
│     ┌─────────────────────────────────────────────────────────────────┐    │
│     │ System: You are a tax assistant. Answer based on provided        │    │
│     │         context. Cite publications. Be accurate.                 │    │
│     │                                                                  │    │
│     │ Context: [Retrieved chunks]                                      │    │
│     │                                                                  │    │
│     │ User: [Original question]                                        │    │
│     └─────────────────────────────────────────────────────────────────┘    │
│     Latency Target: < 2000ms                                                │
│                                                                              │
│  6. RESPONSE TO CUSTOMER                                                    │
│     "Unfortunately, as a W-2 employee, you generally cannot deduct         │
│      home office expenses on your federal tax return. The Tax Cuts and     │
│      Jobs Act of 2017 suspended the deduction for unreimbursed employee    │
│      business expenses through 2025 (Publication 587, Section 1).          │
│      However, you may want to ask your employer about a home office        │
│      reimbursement program, which would be tax-free to you..."             │
│                                                                              │
│  TOTAL LATENCY TARGET: < 3 seconds                                          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Demo Flow 2: Similar Case Search (Tax Professional)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     RAG FLOW: SIMILAR CASE SEARCH                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. TAX PROFESSIONAL INPUT                                                  │
│     Current case: "Client has rental property in Texas but lives in        │
│     California. They sold cryptocurrency and have a home office for        │
│     their consulting business."                                             │
│                                                                              │
│  2. EMBEDDING GENERATION                                                    │
│     Case description → Vector[1536]                                         │
│                                                                              │
│  3. VECTOR SEARCH ON HISTORICAL SCENARIOS                                   │
│     ┌─────────────────────────────────────────────────────────────────┐    │
│     │ SELECT TOP 10                                                    │    │
│     │   scenario_id, scenario_summary, filing_status,                  │    │
│     │   income_sources, deduction_types, resolution_notes,             │    │
│     │   VECTOR_DISTANCE('cosine', ScenarioEmbedding, @queryVector) AS sim│   │
│     │ FROM TaxScenarios                                                │    │
│     │ WHERE complexity_score >= 6  -- Filter for complex cases         │    │
│     │ ORDER BY sim                                                     │    │
│     └─────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  4. RESULTS DISPLAYED                                                       │
│     ┌─────────────────────────────────────────────────────────────────┐    │
│     │ Similar Case #1 (92% match)                                      │    │
│     │ Multi-state rental + crypto + self-employment                    │    │
│     │ Resolution: Filed CA resident return, TX has no state tax.       │    │
│     │ Used Form 8949 for crypto with specific ID method...             │    │
│     ├─────────────────────────────────────────────────────────────────┤    │
│     │ Similar Case #2 (87% match)                                      │    │
│     │ Rental property + home office (no crypto)                        │    │
│     │ Resolution: Kept Schedule E and Schedule C separate...           │    │
│     └─────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  5. OPTIONAL: AI SYNTHESIS                                                  │
│     "Based on similar cases, key considerations for this return:           │
│      1. California will tax all income; Texas rental has no state impact   │
│      2. Crypto transactions require Form 8949 - verify cost basis          │
│      3. Home office: use regular method for larger deduction given high    │
│         mortgage interest in California..."                                 │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Similar Case Search Feature - Deep Dive

### Business Value

Tax professionals often encounter complex situations they haven't seen before. The "Similar Case Search" feature allows them to:

1. **Find precedent** - "How did we handle this type of situation before?"
2. **Learn from experience** - Junior preparers benefit from institutional knowledge
3. **Reduce errors** - See common pitfalls and audit flags from similar cases
4. **Speed up preparation** - Don't reinvent the wheel on complex returns
5. **Improve consistency** - Similar situations get similar treatment across branches

### What Gets Embedded (Semantic Search Text)

The embedding is generated from a **narrative summary** of the case, not just structured fields. This allows semantic matching on concepts like:

- "first-time home buyer" matches "purchased primary residence"
- "gig economy worker" matches "Uber driver with 1099-K"
- "crypto trader" matches "sold Bitcoin and Ethereum"

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     EMBEDDING STRATEGY                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  WHAT GETS EMBEDDED (concatenated into single text):                        │
│  ──────────────────────────────────────────────────────────────────────     │
│  • scenario_summary (2-3 sentences describing the taxpayer situation)       │
│  • key_characteristics (comma-separated list of notable features)           │
│  • complexity_factors (what made this case tricky)                          │
│  • resolution_approach (high-level how it was handled)                      │
│                                                                              │
│  WHAT DOES NOT GET EMBEDDED (used for filtering/display only):              │
│  ──────────────────────────────────────────────────────────────────────     │
│  • Specific dollar amounts (would skew similarity)                          │
│  • Names, SSNs, addresses (PII - synthetic anyway)                         │
│  • Exact dates (year matters, specific dates don't)                        │
│  • Internal IDs                                                             │
│                                                                              │
│  EXAMPLE EMBEDDING INPUT TEXT:                                              │
│  ──────────────────────────────────────────────────────────────────────     │
│  "Married couple, both self-employed consultants working from home.         │
│   Multiple 1099-NEC clients, significant business expenses including        │
│   home office, vehicle, and equipment. Sold investment property held        │
│   for 3 years. First year contributing to SEP-IRA. Key characteristics:    │
│   self-employment, home office regular method, rental property sale,        │
│   capital gains, retirement contributions, estimated tax payments.          │
│   Complexity factors: dual self-employment allocation, mixed-use home       │
│   office, 1031 exchange considered but not executed. Resolution: Filed      │
│   joint return with two Schedule Cs, used regular home office method        │
│   with square footage allocation, reported property sale on Schedule D      │
│   with depreciation recapture on Form 4797."                                │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Complete Case Record Schema

```json
{
  // ═══════════════════════════════════════════════════════════════════════════
  // IDENTIFICATION
  // ═══════════════════════════════════════════════════════════════════════════
  "scenario_id": "SCN-2025-04721",
  "tax_year": 2025,
  "created_date": "2025-03-15",
  "branch_id": 127,
  "preparer_id": 1842,
  
  // ═══════════════════════════════════════════════════════════════════════════
  // TAXPAYER PROFILE (Synthetic - No Real PII)
  // ═══════════════════════════════════════════════════════════════════════════
  "taxpayer_profile": {
    "filing_status": "Married Filing Jointly",
    "age_primary": 42,
    "age_spouse": 39,
    "dependents": 2,
    "dependent_details": [
      {"relationship": "child", "age": 14},
      {"relationship": "child", "age": 11}
    ],
    "state_of_residence": "California",
    "occupation_primary": "IT Consultant (Self-Employed)",
    "occupation_spouse": "Marketing Consultant (Self-Employed)",
    "home_ownership": "Own",
    "years_filing_with_us": 3
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // INCOME SUMMARY
  // ═══════════════════════════════════════════════════════════════════════════
  "income": {
    "total_gross_income": 285000,
    "sources": [
      {
        "type": "1099-NEC",
        "description": "IT Consulting - Primary",
        "amount": 165000,
        "payer_count": 4
      },
      {
        "type": "1099-NEC", 
        "description": "Marketing Consulting - Spouse",
        "amount": 78000,
        "payer_count": 3
      },
      {
        "type": "1099-INT",
        "description": "Bank Interest",
        "amount": 1200
      },
      {
        "type": "1099-DIV",
        "description": "Investment Dividends",
        "amount": 3800,
        "qualified_dividends": 3200
      },
      {
        "type": "1099-S",
        "description": "Sale of Rental Property (Texas)",
        "sale_price": 385000,
        "cost_basis": 290000,
        "gain": 95000,
        "holding_period": "Long-term (3 years)",
        "depreciation_recapture": 28500
      }
    ],
    "adjustments_to_income": [
      {"type": "SEP-IRA Contribution", "amount": 45000},
      {"type": "Self-Employment Tax Deduction", "amount": 17200},
      {"type": "Health Insurance (Self-Employed)", "amount": 18000}
    ],
    "adjusted_gross_income": 204800
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // DEDUCTIONS
  // ═══════════════════════════════════════════════════════════════════════════
  "deductions": {
    "method": "Itemized",
    "itemized_total": 52400,
    "standard_deduction_available": 30000,
    "itemized_breakdown": [
      {"type": "State and Local Taxes (SALT)", "amount": 10000, "note": "Capped"},
      {"type": "Mortgage Interest", "amount": 28400, "note": "Primary residence"},
      {"type": "Charitable Contributions", "amount": 8500, "note": "Cash + appreciated stock"},
      {"type": "Property Taxes (within SALT cap)", "amount": 0, "note": "Included in SALT"},
      {"type": "Medical Expenses", "amount": 5500, "note": "Above 7.5% AGI threshold"}
    ]
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // BUSINESS EXPENSES (Schedule C - Both Taxpayers)
  // ═══════════════════════════════════════════════════════════════════════════
  "business_expenses": {
    "primary_taxpayer": {
      "gross_receipts": 165000,
      "total_expenses": 38500,
      "net_profit": 126500,
      "expense_breakdown": [
        {"category": "Home Office (Regular Method)", "amount": 8200, 
         "details": "320 sq ft dedicated office, 15% of home"},
        {"category": "Vehicle (Actual Expenses)", "amount": 6800,
         "details": "65% business use, kept mileage log"},
        {"category": "Equipment & Software", "amount": 12000,
         "details": "Computer, monitors, software subscriptions"},
        {"category": "Professional Development", "amount": 3500,
         "details": "Certifications, conferences"},
        {"category": "Professional Services", "amount": 4800,
         "details": "Accounting, legal"},
        {"category": "Insurance (E&O)", "amount": 2400},
        {"category": "Internet & Phone", "amount": 800, "details": "Business portion"}
      ]
    },
    "spouse": {
      "gross_receipts": 78000,
      "total_expenses": 15200,
      "net_profit": 62800,
      "expense_breakdown": [
        {"category": "Home Office (Regular Method)", "amount": 4100,
         "details": "160 sq ft dedicated office, 7.5% of home"},
        {"category": "Vehicle (Standard Mileage)", "amount": 4200,
         "details": "6,000 business miles @ $0.70"},
        {"category": "Marketing & Advertising", "amount": 3800},
        {"category": "Software Subscriptions", "amount": 1800},
        {"category": "Professional Development", "amount": 1300}
      ]
    }
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // TAX CREDITS
  // ═══════════════════════════════════════════════════════════════════════════
  "credits": [
    {
      "type": "Child Tax Credit",
      "amount": 4000,
      "details": "2 qualifying children, phased out partially due to income"
    },
    {
      "type": "Residential Energy Credit",
      "amount": 1200,
      "details": "Solar panel installation"
    }
  ],

  // ═══════════════════════════════════════════════════════════════════════════
  // TAX CALCULATION SUMMARY
  // ═══════════════════════════════════════════════════════════════════════════
  "tax_summary": {
    "taxable_income": 152400,
    "federal_tax_liability": 26850,
    "self_employment_tax": 26780,
    "net_investment_income_tax": 0,
    "total_tax": 53630,
    "total_payments_and_credits": {
      "estimated_tax_payments": 48000,
      "child_tax_credit": 4000,
      "energy_credit": 1200,
      "total": 53200
    },
    "amount_owed": 430,
    "effective_tax_rate": 18.8
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE TAX SUMMARY
  // ═══════════════════════════════════════════════════════════════════════════
  "state_returns": [
    {
      "state": "California",
      "status": "Resident",
      "taxable_income": 162400,
      "state_tax": 14200,
      "payments": 12000,
      "amount_owed": 2200
    },
    {
      "state": "Texas",
      "status": "Non-Resident (Rental Property)",
      "note": "No state income tax - no return required"
    }
  ],

  // ═══════════════════════════════════════════════════════════════════════════
  // FORMS FILED
  // ═══════════════════════════════════════════════════════════════════════════
  "forms_filed": [
    "Form 1040",
    "Schedule 1 (Adjustments)",
    "Schedule 2 (Additional Taxes)",
    "Schedule 3 (Additional Credits)",
    "Schedule A (Itemized Deductions)",
    "Schedule B (Interest and Dividends)",
    "Schedule C (x2 - Both Spouses)",
    "Schedule D (Capital Gains)",
    "Schedule SE (x2 - Both Spouses)",
    "Form 4797 (Sale of Business Property - Depreciation Recapture)",
    "Form 8829 (x2 - Home Office)",
    "Form 8949 (Capital Asset Sales)",
    "CA Form 540 (Resident Return)"
  ],

  // ═══════════════════════════════════════════════════════════════════════════
  // COMPLEXITY & RISK ASSESSMENT
  // ═══════════════════════════════════════════════════════════════════════════
  "complexity": {
    "score": 8,
    "level": "High",
    "factors": [
      "Dual self-employment (both spouses)",
      "Dual home office in same residence",
      "Rental property sale with depreciation recapture",
      "Multi-state considerations",
      "High income with credit phase-outs",
      "SEP-IRA contribution calculations",
      "Capital gains on property sale"
    ]
  },
  
  "audit_risk": {
    "score": 6.2,
    "level": "Moderate",
    "flags": [
      {"flag": "Home office deduction (dual)", "risk": "Medium", 
       "mitigation": "Documented dedicated spaces, floor plan on file"},
      {"flag": "High Schedule C income", "risk": "Medium",
       "mitigation": "All 1099s matched, expenses documented"},
      {"flag": "Vehicle deduction", "risk": "Low-Medium",
       "mitigation": "Contemporaneous mileage log maintained"},
      {"flag": "Property sale", "risk": "Low",
       "mitigation": "Clear documentation, held > 1 year"}
    ]
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // SPECIAL SITUATIONS & NOTES (Key for Semantic Search)
  // ═══════════════════════════════════════════════════════════════════════════
  "special_situations": [
    "Both spouses self-employed from home",
    "Shared home office expenses allocated by square footage",
    "Rental property in no-income-tax state (Texas)",
    "Depreciation recapture on rental sale",
    "Considered 1031 exchange but chose taxable sale for liquidity",
    "First year with SEP-IRA (transitioned from SIMPLE IRA)",
    "Estimated tax safe harbor used (110% prior year)"
  ],

  // ═══════════════════════════════════════════════════════════════════════════
  // RESOLUTION NOTES (How the Case Was Handled)
  // ═══════════════════════════════════════════════════════════════════════════
  "resolution_notes": {
    "summary": "Filed MFJ with dual Schedule Cs. Used regular home office method for both taxpayers with square footage allocation (total 22.5% of home). Rental property sale reported on Schedule D and Form 4797 for depreciation recapture. SEP-IRA contribution maximized at 25% of net self-employment income. California taxed all income as residents; Texas had no filing requirement.",
    
    "key_decisions": [
      {
        "decision": "Home Office Method",
        "choice": "Regular Method (actual expenses)",
        "rationale": "Higher deduction than simplified method ($12,300 vs $2,400) due to high mortgage interest in California",
        "documentation": "Floor plan showing dedicated office spaces, utility bills, mortgage statements"
      },
      {
        "decision": "Vehicle Expense Method",
        "choice": "Primary: Actual Expenses, Spouse: Standard Mileage",
        "rationale": "Primary has newer expensive vehicle (actual better), Spouse has older paid-off car (standard better)",
        "documentation": "Mileage logs, fuel receipts, maintenance records"
      },
      {
        "decision": "Rental Property Sale",
        "choice": "Taxable sale (not 1031 exchange)",
        "rationale": "Client wanted liquidity for other investments, accepted tax hit",
        "documentation": "HUD-1, original purchase documents, depreciation schedule"
      },
      {
        "decision": "Retirement Contribution",
        "choice": "SEP-IRA at maximum",
        "rationale": "Highest contribution limit, simpler than Solo 401(k) for their situation",
        "documentation": "SEP-IRA account statements, contribution confirmations"
      }
    ],
    
    "lessons_learned": [
      "For dual self-employed couples, carefully allocate shared home office expenses",
      "When both use home office, ensure spaces are truly separate and dedicated",
      "Texas rental income still taxable federally even though TX has no state tax",
      "Depreciation recapture taxed at 25% max rate - factor into sale decision"
    ],
    
    "client_communication": "Explained trade-off between 1031 exchange (tax deferral) vs. taxable sale (liquidity). Client chose liquidity. Discussed estimated tax implications for next year given property sale capital gain."
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // SCENARIO NARRATIVE (This Gets Embedded)
  // ═══════════════════════════════════════════════════════════════════════════
  "scenario_summary": "Married couple filing jointly, both self-employed consultants (IT and Marketing) working from home in California. Combined 1099-NEC income around $240K from multiple clients. Both claim home office deductions using regular method with allocated expenses. Sold rental property in Texas held for 3 years, resulting in long-term capital gain plus depreciation recapture. First year making SEP-IRA contributions. Two dependent children qualifying for partial child tax credit (income phase-out applies). Key complexity factors include dual self-employment, shared home office allocation, multi-state rental property considerations, and retirement contribution optimization.",

  "key_characteristics": [
    "married filing jointly",
    "dual self-employment",
    "1099-NEC multiple clients",
    "home office both spouses",
    "rental property sale",
    "Texas rental California resident",
    "depreciation recapture",
    "SEP-IRA first year",
    "capital gains",
    "high income",
    "itemized deductions",
    "estimated tax payments",
    "child tax credit phase-out"
  ],

  // ═══════════════════════════════════════════════════════════════════════════
  // VECTOR EMBEDDING (1536 dimensions - truncated for display)
  // ═══════════════════════════════════════════════════════════════════════════
  "embedding": [0.0234, -0.0156, 0.0412, -0.0089, 0.0567, ...]  // 1536 floats
}
```

### How Search Matching Works

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     SEARCH FLOW EXAMPLE                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  TAX PROFESSIONAL'S CURRENT CASE:                                           │
│  ──────────────────────────────────────────────────────────────────────     │
│  "I have a married couple where the husband is a freelance web developer    │
│   and the wife does freelance graphic design. They both work from their     │
│   apartment. They also sold a condo they were renting out in Arizona        │
│   last year. They want to know about retirement account options."           │
│                                                                              │
│                                    │                                         │
│                                    ▼                                         │
│                                                                              │
│  STEP 1: GENERATE QUERY EMBEDDING                                           │
│  ──────────────────────────────────────────────────────────────────────     │
│  Query text → Azure OpenAI text-embedding-3-small → Vector[1536]            │
│                                                                              │
│                                    │                                         │
│                                    ▼                                         │
│                                                                              │
│  STEP 2: VECTOR SEARCH WITH OPTIONAL FILTERS                                │
│  ──────────────────────────────────────────────────────────────────────     │
│  SELECT TOP 5                                                               │
│      scenario_id,                                                           │
│      scenario_summary,                                                      │
│      filing_status,                                                         │
│      JSON_QUERY(resolution_notes, '$.summary') AS resolution,               │
│      JSON_QUERY(resolution_notes, '$.key_decisions') AS decisions,          │
│      complexity.score AS complexity,                                        │
│      VECTOR_DISTANCE('cosine', embedding, @queryVector) AS distance         │
│  FROM TaxScenarios                                                          │
│  WHERE tax_year >= 2023                                -- Recent cases       │
│    AND JSON_VALUE(taxpayer_profile, '$.filing_status')                      │
│          = 'Married Filing Jointly'                    -- Same filing status │
│  ORDER BY distance ASC                                 -- Most similar first │
│                                                                              │
│                                    │                                         │
│                                    ▼                                         │
│                                                                              │
│  STEP 3: RESULTS (Scenario SCN-2025-04721 matches at 94% similarity)        │
│  ──────────────────────────────────────────────────────────────────────     │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ ★ SIMILAR CASE #1 - 94% Match                     Complexity: 8/10  │   │
│  │ ─────────────────────────────────────────────────────────────────── │   │
│  │ Married couple, both self-employed consultants working from home.   │   │
│  │ Sold rental property in Texas. First year SEP-IRA.                  │   │
│  │                                                                      │   │
│  │ KEY DECISIONS:                                                       │   │
│  │ • Home Office: Regular method, allocated by square footage          │   │
│  │ • Rental Sale: Taxable (not 1031), depreciation recapture           │   │
│  │ • Retirement: SEP-IRA maximized at 25%                              │   │
│  │                                                                      │   │
│  │ WATCH OUT FOR:                                                       │   │
│  │ • Dual home office requires separate dedicated spaces               │   │
│  │ • Depreciation recapture taxed at 25% rate                          │   │
│  │                                                                      │   │
│  │ [View Full Case Details]  [Apply to Current Return]                 │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  WHY IT MATCHED:                                                            │
│  ──────────────────────────────────────────────────────────────────────     │
│  ✓ Both spouses self-employed (1099-NEC)                                   │
│  ✓ Work from home (home office deduction)                                  │
│  ✓ Sold rental property (capital gains + depreciation)                     │
│  ✓ Asking about retirement options (SEP-IRA discussed)                     │
│  ✓ Married filing jointly                                                  │
│                                                                              │
│  Minor differences (don't affect match quality):                            │
│  • Arizona vs Texas (both no-income-tax states)                            │
│  • Apartment vs house (home office rules same)                             │
│  • Web dev/design vs IT/Marketing (self-employment similar)                │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### UI Presentation for Tax Professional

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  🔍 SIMILAR CASE SEARCH                                    [Clear] [Search] │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Describe your current case:                                                │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Married couple, both freelancers working from home. Sold rental     │   │
│  │ property in Arizona. Interested in retirement account options.      │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  Optional Filters:  Filing Status [MFJ ▼]  Min Complexity [5 ▼]  Year [Any]│
│                                                                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  📋 5 SIMILAR CASES FOUND                                                   │
│                                                                              │
│  ┌────┬────────────────────────────────────────────────────────┬──────────┐│
│  │ 94%│ Dual self-employed, home office, rental sale, SEP-IRA │ ★★★★★★★★ ││
│  ├────┼────────────────────────────────────────────────────────┼──────────┤│
│  │ 87%│ Self-employed couple, home office, 401k rollover      │ ★★★★★★☆☆ ││
│  ├────┼────────────────────────────────────────────────────────┼──────────┤│
│  │ 82%│ Freelancer + W-2 spouse, rental income (not sold)     │ ★★★★★☆☆☆ ││
│  ├────┼────────────────────────────────────────────────────────┼──────────┤│
│  │ 78%│ Single self-employed, rental property sale, no office │ ★★★★★★★☆ ││
│  ├────┼────────────────────────────────────────────────────────┼──────────┤│
│  │ 71%│ MFJ dual W-2, sold vacation home (not rental)         │ ★★★★☆☆☆☆ ││
│  └────┴────────────────────────────────────────────────────────┴──────────┘│
│                                                                              │
│  ═══════════════════════════════════════════════════════════════════════════│
│                                                                              │
│  📄 CASE DETAILS: SCN-2025-04721                              [Expand All] │
│  ───────────────────────────────────────────────────────────────────────── │
│                                                                              │
│  PROFILE                           │  INCOME SUMMARY                        │
│  • Filing: Married Filing Jointly  │  • 1099-NEC: $243,000 (7 clients)     │
│  • Ages: 42 & 39, 2 dependents     │  • Investment: $5,000                  │
│  • State: California               │  • Rental Sale Gain: $95,000          │
│  • Occupations: IT & Marketing     │  • AGI: $204,800                       │
│                                                                              │
│  ───────────────────────────────────────────────────────────────────────── │
│                                                                              │
│  📌 KEY DECISIONS MADE                                                      │
│                                                                              │
│  ┌─────────────────┬────────────────────────────────────────────────────┐  │
│  │ Home Office     │ Regular method - $12,300 deduction                 │  │
│  │                 │ Why: High CA mortgage interest made this better    │  │
│  │                 │ than simplified ($2,400)                           │  │
│  ├─────────────────┼────────────────────────────────────────────────────┤  │
│  │ Rental Sale     │ Taxable sale, not 1031 exchange                    │  │
│  │                 │ Why: Client prioritized liquidity                  │  │
│  │                 │ Note: $28,500 depreciation recapture at 25%        │  │
│  ├─────────────────┼────────────────────────────────────────────────────┤  │
│  │ Retirement      │ SEP-IRA, maxed at $45,000                          │  │
│  │                 │ Why: Simpler than Solo 401(k), high contribution   │  │
│  └─────────────────┴────────────────────────────────────────────────────┘  │
│                                                                              │
│  ⚠️ AUDIT FLAGS & MITIGATIONS                                               │
│  • Home office (dual): Documented separate dedicated spaces                │
│  • Vehicle deduction: Contemporaneous mileage log kept                     │
│  • High Schedule C: All 1099s matched, receipts organized                  │
│                                                                              │
│  💡 LESSONS FROM THIS CASE                                                  │
│  • Allocate shared home expenses carefully between two Schedule Cs         │
│  • TX rental income taxable federally even though TX has no state tax      │
│  • Depreciation recapture at 25% - factor into sale vs 1031 decision       │
│                                                                              │
│  [📋 Copy Notes to Current Return]  [💬 Ask AI About This Case]            │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Demo Flow 3: Natural Language Analytics (Executive)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     RAG FLOW: EXECUTIVE NL QUERY                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. EXECUTIVE INPUT                                                         │
│     "Why did our average refund amount drop in the Southwest region        │
│      this month compared to last year?"                                     │
│                                                                              │
│  2. QUERY UNDERSTANDING (LLM)                                               │
│     Translate NL to structured query requirements:                          │
│     - Metric: Average refund amount                                         │
│     - Filter: Southwest region (AZ, NM, TX, OK)                            │
│     - Time: Current month vs same month last year                          │
│     - Analysis: Root cause / comparison                                     │
│                                                                              │
│  3. SQL GENERATION (runs on Analytics replica with columnstore)            │
│     ┌─────────────────────────────────────────────────────────────────┐    │
│     │ WITH CurrentPeriod AS (...), PriorPeriod AS (...)               │    │
│     │ SELECT                                                          │    │
│     │   FilingStatus, IncomeRange, DeductionType,                     │    │
│     │   AVG(CurrentRefund) - AVG(PriorRefund) AS RefundDelta          │    │
│     │ FROM ... GROUP BY ...                                           │    │
│     │ ORDER BY ABS(RefundDelta) DESC                                  │    │
│     └─────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  4. CONTEXT: VECTOR SEARCH ON BUSINESS KNOWLEDGE                           │
│     Search internal business context for relevant factors:                  │
│     - Tax law changes affecting Southwest                                   │
│     - Regional economic factors                                             │
│     - Operational changes                                                   │
│                                                                              │
│  5. AI SYNTHESIS                                                            │
│     "Average refund in the Southwest dropped 12% ($847 → $745).            │
│      Primary factors identified:                                            │
│      1. Texas branch expansion brought in 40% more customers in            │
│         lower income brackets (avg AGI $38K vs $52K regional avg)          │
│      2. Reduced child tax credit compared to 2024                          │
│      3. Higher proportion of gig workers with underwithholding..."         │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Data Preparation Steps

### Step 1: IRS Publication Harvesting

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     STEP 1: IRS CONTENT HARVESTING                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  SOURCE: IRS.gov Publications (Public Domain - U.S. Government Works)       │
│                                                                              │
│  APPROACH A: Direct PDF Download + Extraction                               │
│  ──────────────────────────────────────────────────────────────────────    │
│  1. Download PDFs from https://www.irs.gov/publications                     │
│  2. Extract text using PyMuPDF or pdfplumber                               │
│  3. Clean and structure content                                             │
│  4. Chunk with overlap                                                      │
│                                                                              │
│  APPROACH B: HTML Scraping (Preferred - Better Structure)                   │
│  ──────────────────────────────────────────────────────────────────────    │
│  1. Use IRS HTML versions: irs.gov/publications/p17 (etc.)                 │
│  2. Scrape with BeautifulSoup/Scrapy                                       │
│  3. Preserve heading hierarchy                                              │
│  4. Extract tables separately                                               │
│                                                                              │
│  LEGAL STATUS: ✅ Public Domain                                             │
│  "Works of the United States Government are not eligible for               │
│   U.S. copyright protection" - 17 U.S.C. § 105                             │
│                                                                              │
│  DELIVERABLE: ~5,000 JSON chunks with metadata                             │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Step 2: Form Instructions Processing

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     STEP 2: FORM INSTRUCTIONS                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  SOURCE: IRS Form Instructions (Public Domain)                              │
│                                                                              │
│  PROCESS:                                                                   │
│  1. Download instructions for each form (PDF)                              │
│     - i1040.pdf, i1040sca.pdf, i1040scc.pdf, etc.                         │
│  2. Parse line-by-line structure                                           │
│  3. Create mapping: Form → Line → Instructions → Common Questions          │
│  4. Generate embeddings for each line item                                 │
│                                                                              │
│  ENHANCEMENT:                                                               │
│  - Use LLM to generate "Common Questions" for each line item               │
│  - These become additional search vectors                                   │
│                                                                              │
│  Example:                                                                   │
│  Form 1040, Line 12 (Standard Deduction)                                   │
│  → Generated questions:                                                     │
│    - "What is my standard deduction?"                                      │
│    - "Am I better off itemizing?"                                          │
│    - "Standard deduction for married filing jointly"                       │
│                                                                              │
│  DELIVERABLE: ~2,000 JSON chunks with form/line metadata                   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Step 3: Synthetic Scenario Generation

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     STEP 3: SYNTHETIC TAX SCENARIOS                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  WHY SYNTHETIC: Real tax data is PII. We generate realistic scenarios.     │
│                                                                              │
│  GENERATION APPROACH:                                                       │
│                                                                              │
│  Option A: Rule-Based Generation (Recommended for consistency)             │
│  ──────────────────────────────────────────────────────────────────────    │
│  1. Define parameter distributions based on IRS Statistics of Income       │
│     - Income ranges, filing statuses, deduction frequencies                │
│  2. Create scenario templates with slots                                    │
│  3. Fill slots with realistic random values                                │
│  4. Apply tax calculation logic for realistic outcomes                     │
│                                                                              │
│  Option B: LLM-Assisted Generation                                         │
│  ──────────────────────────────────────────────────────────────────────    │
│  1. Provide GPT-5.2 with tax scenario requirements                         │
│  2. Generate diverse, realistic scenarios                                   │
│  3. Validate against tax rules                                             │
│  4. Human review sample for quality                                        │
│                                                                              │
│  RECOMMENDED: Hybrid - Rule-based for volume, LLM for complex edge cases   │
│                                                                              │
│  PARAMETERS TO VARY:                                                        │
│  ├── Filing Status: Single, MFJ, MFS, HoH, QSS                            │
│  ├── Income Sources: W-2, 1099-NEC, 1099-INT, 1099-DIV, K-1, Rental       │
│  ├── Income Level: $0-25K, $25-50K, $50-100K, $100-200K, $200K+           │
│  ├── Deductions: Standard, Itemized (mortgage, SALT, charity, medical)    │
│  ├── Credits: EITC, CTC, AOTC, LLC, Saver's Credit                        │
│  ├── Life Events: Marriage, Divorce, Baby, Home Purchase, Job Change      │
│  ├── Complexity: Simple (1-3), Medium (4-6), Complex (7-10)               │
│  └── Special Situations: Crypto, Multi-state, Self-employed, Rental       │
│                                                                              │
│  DELIVERABLE: 50,000 scenario JSON documents with embeddings               │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Step 4: Embedding Generation

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     STEP 4: EMBEDDING GENERATION                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  MODEL: Azure OpenAI text-embedding-3-small                                │
│  DIMENSIONS: 1536                                                           │
│                                                                              │
│  BATCH PROCESSING:                                                          │
│  1. Batch chunks in groups of 100-500 (API limits)                         │
│  2. Rate limit handling with exponential backoff                           │
│  3. Store embeddings alongside source content                              │
│                                                                              │
│  ESTIMATED VOLUME:                                                          │
│  ├── Tax Knowledge Base: 5,000 chunks                                      │
│  ├── Form Instructions: 2,000 chunks                                       │
│  ├── Tax Scenarios: 50,000 scenarios                                       │
│  └── Total: ~57,000 embeddings                                             │
│                                                                              │
│  COST ESTIMATE (ada-002 at $0.0001/1K tokens):                             │
│  - Average chunk: 400 tokens                                                │
│  - Total tokens: 57,000 × 400 = 22.8M tokens                               │
│  - Cost: ~$2.28 for initial embedding                                      │
│                                                                              │
│  OUTPUT FORMAT:                                                             │
│  {                                                                          │
│    "id": "chunk_001",                                                       │
│    "content": "...",                                                        │
│    "metadata": {...},                                                       │
│    "embedding": [0.0123, -0.0456, ...] // 1536 floats                      │
│  }                                                                          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Step 5: Data Loading to Azure SQL DB

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     STEP 5: DATA LOADING                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  LOAD SEQUENCE:                                                             │
│                                                                              │
│  1. Create tables with VECTOR columns                                       │
│  2. Bulk insert knowledge base chunks                                       │
│  3. Bulk insert form reference data                                        │
│  4. Bulk insert synthetic scenarios                                        │
│  5. Create DiskANN vector indexes                                          │
│  6. Update statistics                                                       │
│  7. Validate with sample queries                                           │
│                                                                              │
│  BULK INSERT APPROACH:                                                      │
│  - Use SqlBulkCopy or BULK INSERT                                          │
│  - Stream from JSON/CSV files in Azure Blob Storage                        │
│  - Batch size: 10,000 rows                                                 │
│                                                                              │
│  VECTOR INDEX CREATION (after data load):                                  │
│  CREATE VECTOR INDEX IX_Knowledge_Embedding                                 │
│  ON TaxKnowledgeBase(ContentEmbedding)                                     │
│  WITH (METRIC = 'cosine', TYPE = 'DISKANN');                               │
│                                                                              │
│  Note: Index creation may take several minutes for 50K+ vectors            │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Public Data Sources and GitHub Projects

### IRS Data (Public Domain - No License Needed)

| Source | URL | Content | Format |
|--------|-----|---------|--------|
| IRS Publications | irs.gov/publications | Tax guidance | PDF/HTML |
| IRS Forms & Instructions | irs.gov/forms-instructions | Form instructions | PDF |
| IRS Statistics of Income | irs.gov/statistics | Aggregate tax stats | Excel/CSV |
| IRS Tax Tables | irs.gov/pub/irs-pdf | Rate schedules | PDF |

### Open Source Projects (Permissive Licenses)

#### 1. **OpenTaxSolver** - GPL v2
- **URL**: https://github.com/GaryQ-physics/OpenTaxSolver
- **License**: GPL v2 (⚠️ Copyleft - careful with derivative works)
- **Useful For**: Tax calculation logic, form field mappings
- **Content**: C code for federal tax calculations

#### 2. **TaxBrain** - MIT License ✅
- **URL**: https://github.com/PSLmodels/Tax-Brain
- **License**: MIT (Permissive)
- **Useful For**: Tax policy simulation parameters
- **Content**: Python-based tax calculation models

#### 3. **Tax-Calculator** - MIT License ✅
- **URL**: https://github.com/PSLmodels/Tax-Calculator
- **License**: MIT (Permissive)
- **Useful For**: Microsimulation tax calculations
- **Content**: Detailed tax logic, test scenarios
- **Highlight**: Contains many test cases with realistic scenarios

#### 4. **usaspending-api** - Creative Commons Zero ✅
- **URL**: https://github.com/fedspendingtransparency/usaspending-api
- **License**: CC0 (Public Domain)
- **Useful For**: Government data API patterns
- **Content**: API design for government financial data

#### 5. **irs-efile-viewer** - MIT License ✅
- **URL**: https://github.com/jsfenfen/irs-efile-viewer
- **License**: MIT (Permissive)
- **Useful For**: Understanding IRS e-file XML schemas
- **Content**: Parsing logic for 990 forms

#### 6. **python-irs-efile** - MIT License ✅
- **URL**: https://github.com/jsfenfen/990-xml-reader
- **License**: MIT (Permissive)
- **Useful For**: IRS form structure understanding
- **Content**: XML schema parsers

### Synthetic Data Generation Tools

#### 1. **Faker** - MIT License ✅
- **URL**: https://github.com/joke2k/faker
- **License**: MIT
- **Useful For**: Generating realistic names, addresses, SSN patterns
- **Usage**: `faker.ssn()`, `faker.address()`, `faker.name()`

#### 2. **SDV (Synthetic Data Vault)** - MIT License ✅
- **URL**: https://github.com/sdv-dev/SDV
- **License**: MIT
- **Useful For**: Learning distributions from sample data, generating similar synthetic data
- **Usage**: Train on IRS Statistics of Income distributions

#### 3. **Gretel Synthetics** - Apache 2.0 ✅
- **URL**: https://github.com/gretelai/gretel-synthetics
- **License**: Apache 2.0
- **Useful For**: Deep learning-based synthetic data generation
- **Usage**: Generate realistic correlated financial data

### Recommended Data Harvesting Strategy

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     RECOMMENDED DATA SOURCES                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  PRIMARY KNOWLEDGE BASE:                                                    │
│  ├── Direct from IRS.gov (Public Domain) ✅                                │
│  │   - Publications in HTML format                                         │
│  │   - Form instructions in PDF                                            │
│  │   - No licensing concerns                                               │
│  │                                                                          │
│  SCENARIO GENERATION:                                                       │
│  ├── Tax-Calculator (MIT) for realistic calculation logic ✅              │
│  ├── Faker (MIT) for PII generation ✅                                     │
│  ├── IRS Statistics of Income for distributions ✅                         │
│  │                                                                          │
│  FORM STRUCTURE:                                                            │
│  ├── IRS.gov official form definitions (Public Domain) ✅                  │
│  ├── irs-efile-viewer (MIT) for schema understanding ✅                    │
│  │                                                                          │
│  ⚠️ AVOID:                                                                  │
│  ├── OpenTaxSolver (GPL) - copyleft complications                          │
│  ├── Any real tax return data - PII concerns                               │
│  ├── Commercial tax software logic - proprietary                           │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Synthetic Data Generation

### Scenario Generation Script (Conceptual)

```python
# Conceptual approach - not implementation

import random
from faker import Faker
from dataclasses import dataclass
from typing import List

fake = Faker()

# Based on IRS Statistics of Income distributions
INCOME_DISTRIBUTIONS = {
    'W2': {'mean': 55000, 'std': 35000, 'min': 15000, 'max': 500000},
    '1099-NEC': {'mean': 25000, 'std': 20000, 'min': 1000, 'max': 200000},
    'Rental': {'mean': 18000, 'std': 15000, 'min': -10000, 'max': 100000},
    'Dividends': {'mean': 3000, 'std': 8000, 'min': 0, 'max': 100000},
}

FILING_STATUS_WEIGHTS = {
    'Single': 0.44,
    'Married Filing Jointly': 0.36,
    'Married Filing Separately': 0.03,
    'Head of Household': 0.14,
    'Qualifying Surviving Spouse': 0.03,
}

def generate_scenario() -> dict:
    filing_status = random.choices(
        list(FILING_STATUS_WEIGHTS.keys()),
        list(FILING_STATUS_WEIGHTS.values())
    )[0]
    
    income_sources = select_income_sources(filing_status)
    deductions = select_deductions(income_sources)
    credits = select_credits(filing_status, income_sources)
    
    return {
        'scenario_id': f"SCN-{fake.uuid4()[:8]}",
        'filing_status': filing_status,
        'income_sources': income_sources,
        'deductions': deductions,
        'credits': credits,
        'scenario_summary': generate_summary(...),
        'complexity_score': calculate_complexity(...),
        # ... calculate tax outcome
    }
```

### Scenario Categories and Counts

| Category | Description | Target Count | Generation Method |
|----------|-------------|--------------|-------------------|
| Baseline Simple | W-2 only, standard deduction | 10,000 | Rule-based |
| Dual Income | Two W-2s, joint filing | 5,000 | Rule-based |
| Side Gig | W-2 + 1099-NEC | 8,000 | Rule-based |
| Investor | W-2 + investments | 7,000 | Rule-based |
| Landlord | Rental property income | 5,000 | Rule-based + review |
| Crypto | Cryptocurrency transactions | 3,000 | LLM-assisted |
| Self-Employed | Schedule C business | 5,000 | Rule-based |
| Home Office | Remote work deductions | 4,000 | Rule-based |
| Life Changes | Marriage/divorce/baby | 5,000 | LLM-assisted |
| Complex Edge | Multi-state, AMT, foreign | 2,000 | LLM-assisted |

---

## Data Ingestion Pipeline

### End-to-End Pipeline

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     DATA INGESTION PIPELINE                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐  │
│  │   Source    │    │   Extract   │    │  Transform  │    │   Embed     │  │
│  │   Data      │───▶│   & Parse   │───▶│  & Chunk    │───▶│   (Azure    │  │
│  │             │    │             │    │             │    │   OpenAI)   │  │
│  └─────────────┘    └─────────────┘    └─────────────┘    └──────┬──────┘  │
│       │                   │                   │                   │         │
│       │                   │                   │                   ▼         │
│       │                   │                   │           ┌─────────────┐  │
│  IRS PDFs/HTML      BeautifulSoup       Chunk with       │    Load     │  │
│  GitHub repos       PyMuPDF             overlap          │   to SQL    │  │
│  Statistics         JSON parsing        Add metadata     │ Hyperscale  │  │
│                                                          └──────┬──────┘  │
│                                                                  │         │
│                                                                  ▼         │
│                                                          ┌─────────────┐  │
│                                                          │   Create    │  │
│                                                          │   Vector    │  │
│                                                          │   Indexes   │  │
│                                                          └─────────────┘  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Pipeline Scripts Needed

| Script | Purpose | Input | Output |
|--------|---------|-------|--------|
| `harvest_irs_pubs.py` | Download/scrape IRS publications | URLs | Raw HTML/PDF |
| `parse_publications.py` | Extract text, preserve structure | Raw files | Structured JSON |
| `chunk_content.py` | Split into semantic chunks | Structured JSON | Chunked JSON |
| `generate_scenarios.py` | Create synthetic tax scenarios | Config | Scenario JSON |
| `generate_embeddings.py` | Call Azure OpenAI for embeddings | Chunked JSON | Embedded JSON |
| `load_to_sql.py` | Bulk insert to Azure SQL DB | Embedded JSON | SQL tables |
| `create_indexes.py` | Create vector and other indexes | - | Indexed DB |
| `validate_rag.py` | Test queries, measure quality | Test questions | Quality report |

---

## Summary: Pre-Implementation Checklist

### ⚡ ACCELERATED TIMELINE: 3-Day Data Prep

Given limited time, we prioritize a **minimal viable dataset** that demonstrates all Hyperscale features effectively.

---

### Prioritized Data Strategy (P0 = Must Have, P1 = Nice to Have, P2 = Skip for Demo)

| Data Category | Full Target | **Demo Minimum** | Priority |
|---------------|-------------|------------------|----------|
| Tax Knowledge Base | 5,000 chunks | **500 chunks** | P0 |
| Form Instructions | 2,000 chunks | **200 chunks** | P1 |
| Synthetic Scenarios | 50,000 | **5,000** | P0 |
| Operational Data (returns, customers) | 10M rows | **1M rows** | P0 |

---

### Day 1: Knowledge Base & Embeddings (8 hours)

| Hour | Task | Output |
|------|------|--------|
| 1-2 | Download 5 key IRS pubs (Pub 17, 587, 501, 525, 596) HTML | Raw HTML files |
| 3-4 | Quick parse with simple chunking (500 tokens, no overlap) | 500 JSON chunks |
| 5-6 | Generate embeddings via Azure OpenAI batch API | 500 embedded chunks |
| 7-8 | Load to SQL, create vector index, test 5 queries | Working RAG |

**Key Publications for Demo (Covers Most Common Questions):**
- **Pub 17** - General tax guide (150 chunks) - covers most customer questions
- **Pub 587** - Home office (50 chunks) - hot topic, great demo
- **Pub 501** - Filing requirements (50 chunks) - basic questions
- **Pub 525** - Income types (100 chunks) - W-2, 1099 questions
- **Pub 596** - EITC (50 chunks) - refund-focused questions
- **Form 1040 Instructions** (100 chunks) - line-by-line help

---

### Day 2: Synthetic Scenarios & Operational Data (8 hours)

| Hour | Task | Output |
|------|------|--------|
| 1-3 | Generate 5,000 scenarios using GPT-5.2 batch (template-driven) | Scenario JSON |
| 4-5 | Generate scenario embeddings | Embedded scenarios |
| 6-8 | Generate 1M operational rows (customers, returns, forms) | CSV files |

**Scenario Generation Shortcut:**
Instead of complex rule-based generation, use GPT-5.2 with structured prompts:

```
Generate 100 realistic tax filing scenarios. For each include:
- filing_status, income_sources[], total_income, deduction_type, 
- credits[], special_situations[], complexity (1-10),
- 2-sentence summary, resolution_notes

Vary across: simple W-2, self-employed, rental income, crypto, 
multi-state, life events. Make financially realistic.
Output as JSON array.
```

Run 50 batches = 5,000 scenarios in ~2 hours.

**Operational Data Generation (for HTAP/Throughput demos):**
Use SQL scripts or Python Faker to generate:
- 10,000 customers
- 500 branches
- 200 tax professionals
- 1,000,000 tax return rows (for columnstore demo)

---

### Day 3: Load, Index, Validate (8 hours)

| Hour | Task | Output |
|------|------|--------|
| 1-2 | Bulk load all data to Hyperscale | Populated tables |
| 3-4 | Create indexes (vector, columnstore, rowstore) | Indexed DB |
| 5-6 | Run validation queries, tune as needed | Performance baseline |
| 7-8 | Prepare demo scripts with known-good queries | Demo ready |

---

### Minimal Data Files Needed

```
data/
├── knowledge_base/
│   ├── pub17_chunks.json          # ~150 chunks
│   ├── pub587_chunks.json         # ~50 chunks  
│   ├── pub501_chunks.json         # ~50 chunks
│   ├── pub525_chunks.json         # ~100 chunks
│   ├── pub596_chunks.json         # ~50 chunks
│   └── form1040_instructions.json # ~100 chunks
│
├── scenarios/
│   └── tax_scenarios_5k.json      # 5,000 scenarios with embeddings
│
├── operational/
│   ├── branches.csv               # 500 rows
│   ├── customers.csv              # 10,000 rows
│   ├── tax_professionals.csv      # ~2,500 rows (3-8 per branch)
│   ├── tax_returns_fact.csv       # 1,000,000 rows (for columnstore)
│   └── tax_forms.json             # 50,000 JSON documents
│
└── demo_queries/
    ├── rag_test_questions.json    # 20 curated Q&A pairs
    └── similar_case_tests.json    # 10 scenario match tests
```

---

### Demo-Ready Validation Checklist

**RAG Quality (must pass before demo):**
- [ ] "Can I deduct home office as W-2 employee?" → Returns Pub 587 content, correct answer (No)
- [ ] "What is the standard deduction for married filing jointly?" → Correct 2025 amount
- [ ] "Do I need to report crypto?" → Returns guidance on Form 8949
- [ ] "Am I eligible for EITC?" → Returns Pub 596 eligibility criteria
- [ ] "What documents do I need to file?" → Returns Pub 17/501 checklist

**Similar Case Search (must return relevant results):**
- [ ] "Self-employed with home office" → Returns 3+ relevant scenarios
- [ ] "Crypto + W-2 income" → Returns crypto-related scenarios
- [ ] "Rental property multi-state" → Returns rental scenarios

**Performance Targets (must meet for demo):**
- [ ] Vector search: < 100ms on 500 chunks
- [ ] Similar case search: < 200ms on 5K scenarios
- [ ] Columnstore aggregation: < 2s on 1M rows
- [ ] Bulk insert rate: > 50 MB/s demonstrated

---

### Quick-Start Scripts Needed

| Script | Purpose | Runtime |
|--------|---------|---------|
| `01_download_irs_pubs.py` | Fetch 5 publications from IRS.gov | 5 min |
| `02_chunk_publications.py` | Parse HTML, chunk to JSON | 10 min |
| `03_generate_embeddings.py` | Azure OpenAI batch embedding | 15 min |
| `04_generate_scenarios.py` | GPT-5.2 batch scenario generation | 2 hours |
| `05_generate_operational.py` | Faker-based operational data | 30 min |
| `06_load_to_sql.ps1` | Bulk load all data | 20 min |
| `07_create_indexes.sql` | Vector + columnstore indexes | 10 min |
| `08_validate_demo.py` | Run all validation checks | 5 min |

---

### Risk Mitigation

| Risk | Mitigation |
|------|------------|
| IRS site slow/blocked | Pre-download PDFs as backup, use cached HTML |
| Azure OpenAI rate limits | Use batch API, request quota increase |
| Embedding costs | 500 chunks = ~$0.02, 5K scenarios = ~$0.20 (negligible) |
| Data quality issues | Pre-test 10 queries before full generation |
| Time overrun | Start with 100 chunks + 500 scenarios, scale up if time permits |

---

### Absolute Minimum Viable Demo (If Only 1 Day)

If critically short on time, this dataset still demonstrates all features:

| Data | Count | Demonstrates |
|------|-------|--------------|
| Knowledge chunks | 100 (Pub 587 only) | Vector search, RAG |
| Scenarios | 500 | Similar case search |
| Operational rows | 100,000 | Columnstore, throughput |

**Total embedding cost: < $0.05**
**Total prep time: 4-6 hours**

---

## Open Questions for Discussion

1. **Embedding Model**: Using `text-embedding-3-small` (1536 dim) - the newer model with better performance.

2. **Chunk Size**: 500-800 tokens recommended, but should we experiment with different sizes for different content types?

3. **Scenario Volume**: Is 50K scenarios sufficient for meaningful "similar case" search, or should we target higher?

4. **Multi-Year Data**: Should scenarios span multiple tax years (2022-2025) to demonstrate searching across years?

5. **Quality Validation**: What questions should we use to validate RAG quality before demo?

---

*Document Version: 1.0*  
*Last Updated: February 1, 2026*  
*Status: Draft - Awaiting Review*
