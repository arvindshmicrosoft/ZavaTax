"""
Configuration settings for Zava Tax data preparation.

IRS CONTENT NOTICE
------------------
The IRS publication URLs listed in IRS_PUBLICATIONS below point to
U.S. Government Works (17 U.S.C. § 105) that may be freely used per
https://www.irs.gov/about-irs/use-of-content-from-irsgov.
Neither this application nor Microsoft is affiliated with or endorsed by the IRS.
"""

import os
from pathlib import Path
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Paths
BASE_DIR = Path(__file__).parent
DATA_DIR = BASE_DIR / "data"
RAW_DIR = DATA_DIR / "raw"
PROCESSED_DIR = DATA_DIR / "processed"
OUTPUT_DIR = DATA_DIR / "output"

# Create directories if they don't exist
for dir_path in [DATA_DIR, RAW_DIR, PROCESSED_DIR, OUTPUT_DIR]:
    dir_path.mkdir(parents=True, exist_ok=True)

# Azure OpenAI Configuration (uses DefaultAzureCredential for authentication)
AZURE_OPENAI_ENDPOINT = os.getenv("AZURE_OPENAI_ENDPOINT")
AZURE_OPENAI_EMBEDDING_DEPLOYMENT = os.getenv("AZURE_OPENAI_EMBEDDING_DEPLOYMENT", "text-embedding-ada-002")
AZURE_OPENAI_CHAT_DEPLOYMENT = os.getenv("AZURE_OPENAI_CHAT_DEPLOYMENT", "gpt-4")
AZURE_OPENAI_API_VERSION = os.getenv("AZURE_OPENAI_API_VERSION", "2024-02-01")

# Managed Identity Configuration (optional - for user-assigned identity)
AZURE_CLIENT_ID = os.getenv("AZURE_CLIENT_ID")  # User-assigned managed identity client ID

# SQL Configuration (uses Azure AD authentication exclusively)
SQL_SERVER = os.getenv("SQL_SERVER")
SQL_DATABASE = os.getenv("SQL_DATABASE")

# Storage Configuration (for blob data loading)
STORAGE_ACCOUNT = os.getenv("STORAGE_ACCOUNT")
STORAGE_CONTAINER = os.getenv("STORAGE_CONTAINER")
IDENTITY_CLIENT_ID = os.getenv("IDENTITY_CLIENT_ID")

# Data generation settings
PUBLICATION_PRIORITY = int(os.getenv("PUBLICATION_PRIORITY", "1"))
SCENARIO_COUNT = int(os.getenv("SCENARIO_COUNT", "5000"))
OPERATIONAL_ROWS = int(os.getenv("OPERATIONAL_ROWS", "1000000"))
BRANCHES = int(os.getenv("BRANCHES", "500"))
CUSTOMERS = int(os.getenv("CUSTOMERS", "10000"))
PROFESSIONALS = int(os.getenv("PROFESSIONALS", "2500"))
CHUNK_SIZE = int(os.getenv("CHUNK_SIZE", "500"))
CHUNK_OVERLAP = 100

# IRS Publications to download (prioritized for demo)
# Priority 1: Core tax topics most customers ask about
# Priority 2: Common deductions, credits, and income types
# Priority 3: Business, self-employment, and special situations
# Priority 4: International, estate, niche, and specialized form instructions
IRS_PUBLICATIONS = [
    # ── Priority 1: Core individual tax topics (12) ─────────────────
    {
        "id": "i4562",
        "title": "Instructions for Form 4562 (Depreciation and Amortization)",
        "url": "https://www.irs.gov/instructions/i4562",
        "priority": 1,
        "description": "Section 179, MACRS, and listed property depreciation rules"
    },
    {
        "id": "p17",
        "title": "Your Federal Income Tax",
        "url": "https://www.irs.gov/publications/p17",
        "priority": 1,
        "description": "Comprehensive individual tax guide - covers most customer questions"
    },
    {
        "id": "p501",
        "title": "Dependents, Standard Deduction, and Filing Information",
        "url": "https://www.irs.gov/publications/p501",
        "priority": 1,
        "description": "Basic filing requirements"
    },
    {
        "id": "p509",
        "title": "Tax Calendars",
        "url": "https://www.irs.gov/publications/p509",
        "priority": 1,
        "description": "Filing deadlines, estimated tax due dates, and extension dates"
    },
    {
        "id": "p525",
        "title": "Taxable and Nontaxable Income",
        "url": "https://www.irs.gov/publications/p525",
        "priority": 1,
        "description": "W-2, 1099, and income type questions"
    },
    {
        "id": "p556",
        "title": "Examination of Returns, Appeal Rights, and Claims for Refund",
        "url": "https://www.irs.gov/publications/p556",
        "priority": 1,
        "description": "What happens during an audit, appeal procedures"
    },
    {
        "id": "p587",
        "title": "Business Use of Your Home",
        "url": "https://www.irs.gov/publications/p587",
        "priority": 1,
        "description": "Home office deduction - hot topic for demos"
    },
    {
        "id": "p596",
        "title": "Earned Income Credit",
        "url": "https://www.irs.gov/publications/p596",
        "priority": 1,
        "description": "EITC - important for refund-focused customers"
    },
    {
        "id": "i6251",
        "title": "Instructions for Form 6251 (Alternative Minimum Tax)",
        "url": "https://www.irs.gov/instructions/i6251",
        "priority": 1,
        "description": "AMT calculation, exemptions, and phase-outs"
    },
    {
        "id": "i8995",
        "title": "Instructions for Form 8995 (Qualified Business Income Deduction)",
        "url": "https://www.irs.gov/instructions/i8995",
        "priority": 1,
        "description": "Section 199A QBI deduction for pass-through entities"
    },
    {
        "id": "p974",
        "title": "Premium Tax Credit",
        "url": "https://www.irs.gov/publications/p974",
        "priority": 1,
        "description": "ACA marketplace premium tax credit and Form 8962"
    },
    {
        "id": "i1041",
        "title": "Instructions for Form 1041 (Estates and Trusts)",
        "url": "https://www.irs.gov/instructions/i1041",
        "priority": 1,
        "description": "Fiduciary income tax return for estates and trusts"
    },
    # ── Priority 2: Common deductions, credits, and income types (28) ──
    {
        "id": "p502",
        "title": "Medical and Dental Expenses",
        "url": "https://www.irs.gov/publications/p502",
        "priority": 2,
        "description": "Medical deductions and 7.5% AGI threshold"
    },
    {
        "id": "p503",
        "title": "Child and Dependent Care Expenses",
        "url": "https://www.irs.gov/publications/p503",
        "priority": 2,
        "description": "Dependent care credit and FSA rules"
    },
    {
        "id": "p504",
        "title": "Divorced or Separated Individuals",
        "url": "https://www.irs.gov/publications/p504",
        "priority": 2,
        "description": "Filing status, alimony, and property settlements"
    },
    {
        "id": "p505",
        "title": "Tax Withholding and Estimated Tax",
        "url": "https://www.irs.gov/publications/p505",
        "priority": 2,
        "description": "Withholding, estimated tax payments, and penalties"
    },
    {
        "id": "p523",
        "title": "Selling Your Home",
        "url": "https://www.irs.gov/publications/p523",
        "priority": 2,
        "description": "Capital gains exclusion on home sales"
    },
    {
        "id": "p524",
        "title": "Credit for the Elderly or the Disabled",
        "url": "https://www.irs.gov/publications/p524",
        "priority": 2,
        "description": "Eligibility and calculation for elderly/disabled credit"
    },
    {
        "id": "p526",
        "title": "Charitable Contributions",
        "url": "https://www.irs.gov/publications/p526",
        "priority": 2,
        "description": "Rules for deducting charitable donations"
    },
    {
        "id": "p527",
        "title": "Residential Rental Property",
        "url": "https://www.irs.gov/publications/p527",
        "priority": 2,
        "description": "Rental income, expenses, and depreciation"
    },
    {
        "id": "p529",
        "title": "Miscellaneous Deductions",
        "url": "https://www.irs.gov/publications/p529",
        "priority": 2,
        "description": "Miscellaneous itemized deductions"
    },
    {
        "id": "p530",
        "title": "Tax Information for Homeowners",
        "url": "https://www.irs.gov/publications/p530",
        "priority": 2,
        "description": "Mortgage interest, property taxes, energy credits"
    },
    {
        "id": "p531",
        "title": "Reporting Tip Income",
        "url": "https://www.irs.gov/publications/p531",
        "priority": 2,
        "description": "Tip reporting rules for employees"
    },
    {
        "id": "p550",
        "title": "Investment Income and Expenses",
        "url": "https://www.irs.gov/publications/p550",
        "priority": 2,
        "description": "Stocks, dividends, capital gains"
    },
    {
        "id": "p551",
        "title": "Basis of Assets",
        "url": "https://www.irs.gov/publications/p551",
        "priority": 2,
        "description": "Cost basis for property, stocks, and other assets"
    },
    {
        "id": "p554",
        "title": "Tax Guide for Seniors",
        "url": "https://www.irs.gov/publications/p554",
        "priority": 2,
        "description": "Social Security, pension, and senior-specific rules"
    },
    {
        "id": "p575",
        "title": "Pension and Annuity Income",
        "url": "https://www.irs.gov/publications/p575",
        "priority": 2,
        "description": "Taxation of pension, 401(k), and annuity distributions"
    },
    {
        "id": "p590a",
        "title": "Contributions to IRAs",
        "url": "https://www.irs.gov/publications/p590a",
        "priority": 2,
        "description": "Traditional and Roth IRA contribution rules"
    },
    {
        "id": "p590b",
        "title": "Distributions from IRAs",
        "url": "https://www.irs.gov/publications/p590b",
        "priority": 2,
        "description": "IRA withdrawal rules, RMDs, and penalties"
    },
    {
        "id": "p907",
        "title": "Tax Highlights for Persons with Disabilities",
        "url": "https://www.irs.gov/publications/p907",
        "priority": 2,
        "description": "ABLE accounts, impairment-related work expenses"
    },
    {
        "id": "p915",
        "title": "Social Security and Equivalent Railroad Retirement Benefits",
        "url": "https://www.irs.gov/publications/p915",
        "priority": 2,
        "description": "Taxability of Social Security benefits"
    },
    {
        "id": "p936",
        "title": "Home Mortgage Interest Deduction",
        "url": "https://www.irs.gov/publications/p936",
        "priority": 2,
        "description": "Deducting home mortgage interest"
    },
    {
        "id": "p969",
        "title": "Health Savings Accounts and Other Tax-Favored Health Plans",
        "url": "https://www.irs.gov/publications/p969",
        "priority": 2,
        "description": "HSA, HRA, FSA rules and limits"
    },
    {
        "id": "p970",
        "title": "Tax Benefits for Education",
        "url": "https://www.irs.gov/publications/p970",
        "priority": 2,
        "description": "Education credits, student loan interest, 529 plans"
    },
    {
        "id": "p971",
        "title": "Innocent Spouse Relief",
        "url": "https://www.irs.gov/publications/p971",
        "priority": 2,
        "description": "Relief from joint liability for understatement of tax"
    },
    {
        "id": "i1065",
        "title": "Instructions for Form 1065 (Partnership Return)",
        "url": "https://www.irs.gov/instructions/i1065",
        "priority": 2,
        "description": "Partnership income, deductions, and K-1 preparation"
    },
    {
        "id": "i1040sb",
        "title": "Instructions for Schedule B (Interest and Ordinary Dividends)",
        "url": "https://www.irs.gov/instructions/i1040sb",
        "priority": 2,
        "description": "Reporting interest and dividend income over $1,500"
    },
    {
        "id": "i1040sr",
        "title": "Instructions for Form 1040-SR (Tax Return for Seniors)",
        "url": "https://www.irs.gov/instructions/i1040sr",
        "priority": 2,
        "description": "Simplified return for taxpayers 65 and older"
    },
    {
        "id": "i8812",
        "title": "Instructions for Schedule 8812 (Credits for Qualifying Children)",
        "url": "https://www.irs.gov/instructions/i1040s8",
        "priority": 2,
        "description": "Child Tax Credit and Additional Child Tax Credit worksheet"
    },
    {
        "id": "i2441",
        "title": "Instructions for Form 2441 (Child and Dependent Care Expenses)",
        "url": "https://www.irs.gov/instructions/i2441",
        "priority": 2,
        "description": "Calculating the child and dependent care credit"
    },
    # ── Priority 3: Business, self-employment, and special situations (35) ──
    {
        "id": "p3",
        "title": "Armed Forces' Tax Guide",
        "url": "https://www.irs.gov/publications/p3",
        "priority": 3,
        "description": "Military pay, combat zone exclusions, moving expenses"
    },
    {
        "id": "i1120s",
        "title": "Instructions for Form 1120-S (S Corporation Return)",
        "url": "https://www.irs.gov/instructions/i1120s",
        "priority": 3,
        "description": "S corporation income, deductions, and shareholder K-1s"
    },
    {
        "id": "p15",
        "title": "Employer's Tax Guide (Circular E)",
        "url": "https://www.irs.gov/publications/p15",
        "priority": 3,
        "description": "Withholding tables, employer payroll tax obligations"
    },
    {
        "id": "p15b",
        "title": "Employer's Tax Guide to Fringe Benefits",
        "url": "https://www.irs.gov/publications/p15b",
        "priority": 3,
        "description": "Taxability of fringe benefits: vehicles, meals, education"
    },
    {
        "id": "p225",
        "title": "Farmer's Tax Guide",
        "url": "https://www.irs.gov/publications/p225",
        "priority": 3,
        "description": "Farm income, expenses, and Schedule F"
    },
    {
        "id": "p334",
        "title": "Tax Guide for Small Business",
        "url": "https://www.irs.gov/publications/p334",
        "priority": 3,
        "description": "Small business, self-employment, and Schedule C"
    },
    {
        "id": "p463",
        "title": "Travel, Gift, and Car Expenses",
        "url": "https://www.irs.gov/publications/p463",
        "priority": 3,
        "description": "Business travel, entertainment, and vehicle deductions"
    },
    {
        "id": "p535",
        "title": "Business Expenses",
        "url": "https://www.irs.gov/publications/p535",
        "priority": 3,
        "description": "Deductible business expenses and Section 179"
    },
    {
        "id": "i709",
        "title": "Instructions for Form 709 (Gift and Generation-Skipping Transfer Tax)",
        "url": "https://www.irs.gov/instructions/i709",
        "priority": 3,
        "description": "Gift tax return filing, annual exclusion, and lifetime exemption"
    },
    {
        "id": "p537",
        "title": "Installment Sales",
        "url": "https://www.irs.gov/publications/p537",
        "priority": 3,
        "description": "Reporting gain from installment sales"
    },
    {
        "id": "p538",
        "title": "Accounting Periods and Methods",
        "url": "https://www.irs.gov/publications/p538",
        "priority": 3,
        "description": "Cash vs. accrual method, fiscal year elections"
    },
    {
        "id": "p541",
        "title": "Partnerships",
        "url": "https://www.irs.gov/publications/p541",
        "priority": 3,
        "description": "Partnership taxation and K-1 reporting"
    },
    {
        "id": "p542",
        "title": "Corporations",
        "url": "https://www.irs.gov/publications/p542",
        "priority": 3,
        "description": "C corporation taxation"
    },
    {
        "id": "p544",
        "title": "Sales and Other Dispositions of Assets",
        "url": "https://www.irs.gov/publications/p544",
        "priority": 3,
        "description": "Capital gains, 1031 exchanges, installment sales"
    },
    {
        "id": "p547",
        "title": "Casualties, Disasters, and Thefts",
        "url": "https://www.irs.gov/publications/p547",
        "priority": 3,
        "description": "Reporting casualty and theft losses"
    },
    {
        "id": "p555",
        "title": "Community Property",
        "url": "https://www.irs.gov/publications/p555",
        "priority": 3,
        "description": "Community property rules for married filing separately"
    },
    {
        "id": "p559",
        "title": "Survivors, Executors, and Administrators",
        "url": "https://www.irs.gov/publications/p559",
        "priority": 3,
        "description": "Filing for deceased taxpayers and estates"
    },
    {
        "id": "p560",
        "title": "Retirement Plans for Small Business",
        "url": "https://www.irs.gov/publications/p560",
        "priority": 3,
        "description": "SEP, SIMPLE, and qualified retirement plans"
    },
    {
        "id": "p561",
        "title": "Determining the Value of Donated Property",
        "url": "https://www.irs.gov/publications/p561",
        "priority": 3,
        "description": "Fair market value for charitable donation deductions"
    },
    {
        "id": "p571",
        "title": "Tax-Sheltered Annuity Plans (403(b) Plans)",
        "url": "https://www.irs.gov/publications/p571",
        "priority": 3,
        "description": "403(b) contribution limits, distributions, and rollovers"
    },
    {
        "id": "p583",
        "title": "Starting a Business and Keeping Records",
        "url": "https://www.irs.gov/publications/p583",
        "priority": 3,
        "description": "EIN, business structure, and recordkeeping basics"
    },
    {
        "id": "p584",
        "title": "Casualty, Disaster, and Theft Loss Workbook",
        "url": "https://www.irs.gov/publications/p584",
        "priority": 3,
        "description": "Worksheets for computing personal casualty losses"
    },
    {
        "id": "p908",
        "title": "Bankruptcy Tax Guide",
        "url": "https://www.irs.gov/publications/p908",
        "priority": 3,
        "description": "Tax consequences of bankruptcy filing"
    },
    {
        "id": "p925",
        "title": "Passive Activity and At-Risk Rules",
        "url": "https://www.irs.gov/publications/p925",
        "priority": 3,
        "description": "Passive activity loss limitations"
    },
    {
        "id": "p926",
        "title": "Household Employer's Tax Guide",
        "url": "https://www.irs.gov/publications/p926",
        "priority": 3,
        "description": "Nanny tax, household employee withholding"
    },
    {
        "id": "p939",
        "title": "General Rule for Pensions and Annuities",
        "url": "https://www.irs.gov/publications/p939",
        "priority": 3,
        "description": "Exclusion ratio for partially taxable annuity payments"
    },
    {
        "id": "p946",
        "title": "How to Depreciate Property",
        "url": "https://www.irs.gov/publications/p946",
        "priority": 3,
        "description": "MACRS, Section 179, and bonus depreciation"
    },
    {
        "id": "p947",
        "title": "Practice Before the IRS and Power of Attorney",
        "url": "https://www.irs.gov/publications/p947",
        "priority": 3,
        "description": "Who can represent taxpayers before the IRS"
    },
    {
        "id": "i5329",
        "title": "Instructions for Form 5329 (Additional Taxes on Qualified Plans)",
        "url": "https://www.irs.gov/instructions/i5329",
        "priority": 3,
        "description": "Early distribution penalties, excess contributions, and RMD failures"
    },
    {
        "id": "i1040sc",
        "title": "Instructions for Schedule C (Profit or Loss from Business)",
        "url": "https://www.irs.gov/instructions/i1040sc",
        "priority": 3,
        "description": "Sole proprietorship business income and expenses"
    },
    {
        "id": "i1040sd",
        "title": "Instructions for Schedule D (Capital Gains and Losses)",
        "url": "https://www.irs.gov/instructions/i1040sd",
        "priority": 3,
        "description": "Reporting capital gains, losses, and carryovers"
    },
    {
        "id": "i1040se",
        "title": "Instructions for Schedule SE (Self-Employment Tax)",
        "url": "https://www.irs.gov/instructions/i1040sse",
        "priority": 3,
        "description": "Self-employment tax calculation"
    },
    {
        "id": "i1040sf",
        "title": "Instructions for Schedule F (Profit or Loss from Farming)",
        "url": "https://www.irs.gov/instructions/i1040sf",
        "priority": 3,
        "description": "Farm income reporting and deductions"
    },
    {
        "id": "i8829",
        "title": "Instructions for Form 8829 (Expenses for Business Use of Your Home)",
        "url": "https://www.irs.gov/instructions/i8829",
        "priority": 3,
        "description": "Calculating the home office deduction"
    },
    {
        "id": "i8889",
        "title": "Instructions for Form 8889 (Health Savings Accounts)",
        "url": "https://www.irs.gov/instructions/i8889",
        "priority": 3,
        "description": "HSA contributions, distributions, and excess contribution penalties"
    },
    # ── Priority 4: International, specialized, and niche (25) ─────
    {
        "id": "p15a",
        "title": "Employer's Supplemental Tax Guide",
        "url": "https://www.irs.gov/publications/p15a",
        "priority": 4,
        "description": "Supplemental wages, withholding methods, sick pay"
    },
    {
        "id": "p15t",
        "title": "Federal Income Tax Withholding Methods",
        "url": "https://www.irs.gov/publications/p15t",
        "priority": 4,
        "description": "Percentage method and wage bracket tables"
    },
    {
        "id": "i8283",
        "title": "Instructions for Form 8283 (Noncash Charitable Contributions)",
        "url": "https://www.irs.gov/instructions/i8283",
        "priority": 4,
        "description": "Reporting noncash donations over $500 with appraisal requirements"
    },
    {
        "id": "p54",
        "title": "Tax Guide for U.S. Citizens and Resident Aliens Abroad",
        "url": "https://www.irs.gov/publications/p54",
        "priority": 4,
        "description": "Foreign earned income exclusion and expat taxes"
    },
    {
        "id": "i1120",
        "title": "Instructions for Form 1120 (Corporation Income Tax Return)",
        "url": "https://www.irs.gov/instructions/i1120",
        "priority": 4,
        "description": "C corporation income tax return filing and line-by-line guidance"
    },
    {
        "id": "p510",
        "title": "Excise Taxes",
        "url": "https://www.irs.gov/publications/p510",
        "priority": 4,
        "description": "Environmental, fuel, and manufacturers excise taxes"
    },
    {
        "id": "p514",
        "title": "Foreign Tax Credit for Individuals",
        "url": "https://www.irs.gov/publications/p514",
        "priority": 4,
        "description": "Claiming credits for taxes paid to foreign countries"
    },
    {
        "id": "p515",
        "title": "Withholding of Tax on Nonresident Aliens and Foreign Entities",
        "url": "https://www.irs.gov/publications/p515",
        "priority": 4,
        "description": "Withholding requirements for payments to foreign persons"
    },
    {
        "id": "p516",
        "title": "U.S. Government Civilian Employees Stationed Abroad",
        "url": "https://www.irs.gov/publications/p516",
        "priority": 4,
        "description": "Tax rules for federal employees living overseas"
    },
    {
        "id": "p517",
        "title": "Social Security and Other Information for Members of the Clergy",
        "url": "https://www.irs.gov/publications/p517",
        "priority": 4,
        "description": "Clergy housing allowance, SE tax exemption"
    },
    {
        "id": "p519",
        "title": "U.S. Tax Guide for Aliens",
        "url": "https://www.irs.gov/publications/p519",
        "priority": 4,
        "description": "Tax rules for resident and nonresident aliens"
    },
    {
        "id": "i8959",
        "title": "Instructions for Form 8959 (Additional Medicare Tax)",
        "url": "https://www.irs.gov/instructions/i8959",
        "priority": 4,
        "description": "0.9% Additional Medicare Tax on high earners"
    },
    {
        "id": "p557",
        "title": "Tax-Exempt Status for Your Organization",
        "url": "https://www.irs.gov/publications/p557",
        "priority": 4,
        "description": "501(c)(3) and other exempt organization rules"
    },
    {
        "id": "p570",
        "title": "Tax Guide for Individuals with Income from U.S. Possessions",
        "url": "https://www.irs.gov/publications/p570",
        "priority": 4,
        "description": "Tax rules for income from Guam, USVI, Puerto Rico, etc."
    },
    {
        "id": "p598",
        "title": "Tax on Unrelated Business Income of Exempt Organizations",
        "url": "https://www.irs.gov/publications/p598",
        "priority": 4,
        "description": "UBTI rules for nonprofits and tax-exempt entities"
    },
    {
        "id": "p721",
        "title": "Tax Guide to U.S. Civil Service Retirement Benefits",
        "url": "https://www.irs.gov/publications/p721",
        "priority": 4,
        "description": "FERS and CSRS pension taxation"
    },
    {
        "id": "p901",
        "title": "U.S. Tax Treaties",
        "url": "https://www.irs.gov/publications/p901",
        "priority": 4,
        "description": "Overview of U.S. income tax treaty provisions"
    },
    {
        "id": "i8960",
        "title": "Instructions for Form 8960 (Net Investment Income Tax)",
        "url": "https://www.irs.gov/instructions/i8960",
        "priority": 4,
        "description": "3.8% NIIT on investment income for high earners"
    },
    {
        "id": "i1040nr",
        "title": "Instructions for Form 1040-NR (Nonresident Alien Income Tax Return)",
        "url": "https://www.irs.gov/instructions/i1040nr",
        "priority": 4,
        "description": "Filing requirements and line-by-line help for nonresident aliens"
    },
    {
        "id": "i1040x",
        "title": "Instructions for Form 1040-X (Amended Return)",
        "url": "https://www.irs.gov/instructions/i1040x",
        "priority": 4,
        "description": "How to amend a previously filed individual return"
    },
    {
        "id": "i8606",
        "title": "Instructions for Form 8606 (Nondeductible IRAs)",
        "url": "https://www.irs.gov/instructions/i8606",
        "priority": 4,
        "description": "Nondeductible IRA contributions and Roth conversions"
    },
    {
        "id": "i8863",
        "title": "Instructions for Form 8863 (Education Credits)",
        "url": "https://www.irs.gov/instructions/i8863",
        "priority": 4,
        "description": "American Opportunity and Lifetime Learning credits"
    },
    {
        "id": "i8949",
        "title": "Instructions for Form 8949 (Sales and Dispositions of Capital Assets)",
        "url": "https://www.irs.gov/instructions/i8949",
        "priority": 4,
        "description": "Reporting individual stock, bond, and property transactions"
    },
    {
        "id": "i8962",
        "title": "Instructions for Form 8962 (Premium Tax Credit)",
        "url": "https://www.irs.gov/instructions/i8962",
        "priority": 4,
        "description": "Reconciling advance PTC payments with actual credit"
    },
    {
        "id": "i5695",
        "title": "Instructions for Form 5695 (Residential Energy Credits)",
        "url": "https://www.irs.gov/instructions/i5695",
        "priority": 4,
        "description": "Solar, EV charger, and energy-efficient home improvement credits"
    },
]

# Embedding model settings
EMBEDDING_MODEL = "text-embedding-ada-002"
EMBEDDING_DIMENSIONS = 1536
EMBEDDING_BATCH_SIZE = 100  # Max items per API call

# Scenario generation settings
SCENARIO_CATEGORIES = {
    "simple_w2": {"count": 1000, "complexity_range": (1, 3)},
    "dual_income": {"count": 500, "complexity_range": (2, 4)},
    "self_employed": {"count": 800, "complexity_range": (4, 7)},
    "rental_property": {"count": 500, "complexity_range": (5, 8)},
    "investments": {"count": 700, "complexity_range": (3, 6)},
    "cryptocurrency": {"count": 300, "complexity_range": (6, 9)},
    "home_office": {"count": 400, "complexity_range": (4, 7)},
    "life_events": {"count": 500, "complexity_range": (4, 8)},
    "complex_edge": {"count": 300, "complexity_range": (7, 10)},
}
