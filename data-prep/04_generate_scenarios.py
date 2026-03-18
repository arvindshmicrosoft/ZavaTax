"""
Step 4: Generate Synthetic Tax Scenarios

Generates realistic tax filing scenarios for the similar case search feature.
Uses a combination of rule-based generation and GPT-4 for complex scenarios.

Usage:
    python 04_generate_scenarios.py [--count 5000] [--use-gpt]

Examples:
    python 04_generate_scenarios.py --count 1000          # Quick: rule-based only
    python 04_generate_scenarios.py --count 5000 --use-gpt  # Full: with GPT enhancement
"""

import argparse
import json
import random
import uuid
from dataclasses import dataclass, asdict, field
from typing import Optional
from pathlib import Path
from tqdm import tqdm
from faker import Faker

from config import OUTPUT_DIR, SCENARIO_COUNT

fake = Faker()
Faker.seed(42)
random.seed(42)

# ============================================================================
# TAX DATA DISTRIBUTIONS (Based on IRS Statistics of Income)
# ============================================================================

FILING_STATUS_WEIGHTS = {
    "Single": 0.44,
    "Married Filing Jointly": 0.36,
    "Married Filing Separately": 0.03,
    "Head of Household": 0.14,
    "Qualifying Surviving Spouse": 0.03,
}

INCOME_RANGES = {
    "low": (15000, 40000),
    "middle": (40000, 85000),
    "upper_middle": (85000, 170000),
    "high": (170000, 400000),
    "very_high": (400000, 1000000),
}

INCOME_RANGE_WEIGHTS = {
    "low": 0.30,
    "middle": 0.35,
    "upper_middle": 0.20,
    "high": 0.12,
    "very_high": 0.03,
}

STATES = [
    ("CA", "California", True),
    ("TX", "Texas", False),
    ("FL", "Florida", False),
    ("NY", "New York", True),
    ("PA", "Pennsylvania", True),
    ("IL", "Illinois", True),
    ("OH", "Ohio", True),
    ("GA", "Georgia", True),
    ("NC", "North Carolina", True),
    ("MI", "Michigan", True),
    ("NJ", "New Jersey", True),
    ("VA", "Virginia", True),
    ("WA", "Washington", False),
    ("AZ", "Arizona", True),
    ("MA", "Massachusetts", True),
    ("TN", "Tennessee", False),
    ("CO", "Colorado", True),
    ("MN", "Minnesota", True),
    ("WI", "Wisconsin", True),
    ("NV", "Nevada", False),
]

OCCUPATIONS_W2 = [
    "Software Engineer", "Teacher", "Nurse", "Accountant", "Sales Manager",
    "Marketing Specialist", "Project Manager", "Administrative Assistant",
    "Financial Analyst", "Human Resources Manager", "Operations Manager",
    "Customer Service Representative", "Warehouse Worker", "Truck Driver",
    "Electrician", "Plumber", "Police Officer", "Firefighter", "Paralegal"
]

OCCUPATIONS_SELF_EMPLOYED = [
    "IT Consultant", "Freelance Writer", "Graphic Designer", "Real Estate Agent",
    "Photographer", "Personal Trainer", "Uber/Lyft Driver", "Etsy Seller",
    "YouTube Content Creator", "Social Media Manager", "Web Developer",
    "Bookkeeper", "Tax Preparer", "Dog Walker", "House Cleaner", "Tutor",
    "Life Coach", "Marketing Consultant", "Event Planner"
]

# ============================================================================
# SCENARIO GENERATION FUNCTIONS
# ============================================================================

def random_weighted(choices: dict) -> str:
    """Select random item based on weights."""
    items = list(choices.keys())
    weights = list(choices.values())
    return random.choices(items, weights=weights)[0]


def generate_income_sources(scenario_type: str, income_level: str) -> list[dict]:
    """Generate income sources based on scenario type."""
    income_range = INCOME_RANGES[income_level]
    sources = []
    
    if scenario_type in ["simple_w2", "dual_income"]:
        # W-2 only
        w2_amount = random.randint(income_range[0], income_range[1])
        sources.append({
            "type": "W-2",
            "description": random.choice(OCCUPATIONS_W2),
            "amount": w2_amount
        })
        
        if scenario_type == "dual_income":
            spouse_amount = random.randint(int(income_range[0] * 0.6), int(income_range[1] * 0.8))
            sources.append({
                "type": "W-2",
                "description": random.choice(OCCUPATIONS_W2) + " (Spouse)",
                "amount": spouse_amount
            })
    
    elif scenario_type == "self_employed":
        # 1099-NEC
        se_amount = random.randint(income_range[0], income_range[1])
        sources.append({
            "type": "1099-NEC",
            "description": random.choice(OCCUPATIONS_SELF_EMPLOYED),
            "amount": se_amount,
            "client_count": random.randint(2, 8)
        })
    
    elif scenario_type == "rental_property":
        # W-2 + Rental
        w2_amount = random.randint(income_range[0], income_range[1])
        sources.append({
            "type": "W-2",
            "description": random.choice(OCCUPATIONS_W2),
            "amount": w2_amount
        })
        
        rental_income = random.randint(12000, 48000)
        rental_expenses = int(rental_income * random.uniform(0.4, 0.8))
        sources.append({
            "type": "Rental Income",
            "description": f"Rental Property ({random.choice(['Single Family', 'Condo', 'Duplex'])})",
            "gross_rent": rental_income,
            "expenses": rental_expenses,
            "amount": rental_income - rental_expenses
        })
    
    elif scenario_type == "investments":
        # W-2 + Investment Income
        w2_amount = random.randint(income_range[0], income_range[1])
        sources.append({
            "type": "W-2",
            "description": random.choice(OCCUPATIONS_W2),
            "amount": w2_amount
        })
        
        if random.random() > 0.3:
            div_amount = random.randint(500, 15000)
            sources.append({
                "type": "1099-DIV",
                "description": "Dividends",
                "amount": div_amount,
                "qualified": int(div_amount * 0.8)
            })
        
        if random.random() > 0.4:
            int_amount = random.randint(100, 5000)
            sources.append({
                "type": "1099-INT",
                "description": "Bank Interest",
                "amount": int_amount
            })
        
        if random.random() > 0.5:
            # Capital gains
            gain = random.randint(-5000, 50000)
            sources.append({
                "type": "Capital Gains",
                "description": "Stock Sales",
                "amount": gain,
                "term": random.choice(["Short-term", "Long-term"])
            })
    
    elif scenario_type == "cryptocurrency":
        w2_amount = random.randint(income_range[0], income_range[1])
        sources.append({
            "type": "W-2",
            "description": random.choice(OCCUPATIONS_W2),
            "amount": w2_amount
        })
        
        crypto_gain = random.randint(-10000, 100000)
        sources.append({
            "type": "Cryptocurrency",
            "description": f"Crypto ({random.choice(['Bitcoin', 'Ethereum', 'Mixed Portfolio'])})",
            "amount": crypto_gain,
            "transactions": random.randint(5, 500),
            "exchanges": random.randint(1, 4)
        })
    
    elif scenario_type == "home_office":
        # Self-employed with home office
        se_amount = random.randint(income_range[0], income_range[1])
        sources.append({
            "type": "1099-NEC",
            "description": random.choice(OCCUPATIONS_SELF_EMPLOYED),
            "amount": se_amount,
            "client_count": random.randint(2, 6),
            "home_office": True
        })
    
    else:  # life_events, complex_edge
        # Mix of income types
        w2_amount = random.randint(income_range[0], income_range[1])
        sources.append({
            "type": "W-2",
            "description": random.choice(OCCUPATIONS_W2),
            "amount": w2_amount
        })
        
        if random.random() > 0.5:
            sources.append({
                "type": "1099-NEC",
                "description": "Side Gig",
                "amount": random.randint(2000, 20000)
            })
    
    return sources


def generate_deductions(income_sources: list, filing_status: str) -> dict:
    """Generate deduction information."""
    total_income = sum(s.get("amount", 0) for s in income_sources)
    
    # Standard deduction amounts (2025)
    standard_deductions = {
        "Single": 14600,
        "Married Filing Jointly": 29200,
        "Married Filing Separately": 14600,
        "Head of Household": 21900,
        "Qualifying Surviving Spouse": 29200,
    }
    
    standard = standard_deductions.get(filing_status, 14600)
    
    # Decide if itemizing makes sense
    itemized_total = 0
    itemized_breakdown = []
    
    # SALT (capped at 10K)
    if total_income > 50000:
        salt = min(random.randint(5000, 25000), 10000)
        itemized_breakdown.append({"type": "SALT", "amount": salt})
        itemized_total += salt
    
    # Mortgage interest
    if random.random() > 0.4 and total_income > 40000:
        mortgage_interest = random.randint(5000, 30000)
        itemized_breakdown.append({"type": "Mortgage Interest", "amount": mortgage_interest})
        itemized_total += mortgage_interest
    
    # Charitable
    if random.random() > 0.5:
        charity = random.randint(500, min(15000, int(total_income * 0.1)))
        itemized_breakdown.append({"type": "Charitable Contributions", "amount": charity})
        itemized_total += charity
    
    # Medical (only if > 7.5% AGI)
    if random.random() > 0.8:
        medical = random.randint(5000, 30000)
        if medical > total_income * 0.075:
            deductible_medical = int(medical - total_income * 0.075)
            itemized_breakdown.append({"type": "Medical Expenses", "amount": deductible_medical})
            itemized_total += deductible_medical
    
    use_itemized = itemized_total > standard
    
    return {
        "method": "Itemized" if use_itemized else "Standard",
        "standard_available": standard,
        "itemized_total": itemized_total if use_itemized else 0,
        "itemized_breakdown": itemized_breakdown if use_itemized else [],
        "deduction_amount": max(standard, itemized_total)
    }


def generate_credits(income_sources: list, filing_status: str, dependents: int) -> list[dict]:
    """Generate tax credits."""
    credits = []
    total_income = sum(s.get("amount", 0) for s in income_sources)
    
    # Child Tax Credit
    if dependents > 0 and total_income < 400000:
        ctc_amount = min(dependents * 2000, 4000)  # Simplified
        if total_income > 200000:
            ctc_amount = int(ctc_amount * 0.5)  # Phase-out
        credits.append({"type": "Child Tax Credit", "amount": ctc_amount})
    
    # EITC (simplified eligibility)
    if total_income < 60000 and total_income > 10000:
        has_w2 = any(s["type"] == "W-2" for s in income_sources)
        if has_w2 and random.random() > 0.5:
            eitc = random.randint(500, 3000)
            credits.append({"type": "Earned Income Credit", "amount": eitc})
    
    # Education credits
    if random.random() > 0.85:
        credits.append({
            "type": random.choice(["American Opportunity Credit", "Lifetime Learning Credit"]),
            "amount": random.randint(500, 2500)
        })
    
    # Energy credits
    if random.random() > 0.9:
        credits.append({
            "type": "Residential Energy Credit",
            "amount": random.randint(500, 3000)
        })
    
    return credits


def generate_special_situations(scenario_type: str) -> list[str]:
    """Generate special situation tags."""
    situations = []
    
    type_situations = {
        "simple_w2": ["First-time filer", "Standard deduction only"],
        "dual_income": ["Both spouses working", "Combined W-2 income"],
        "self_employed": ["Quarterly estimated taxes", "Business expenses", "Self-employment tax"],
        "rental_property": ["Depreciation deduction", "Rental expenses", "Schedule E"],
        "investments": ["Capital gains reporting", "Form 8949", "Dividend income"],
        "cryptocurrency": ["Crypto cost basis tracking", "Multiple exchanges", "Form 8949 required"],
        "home_office": ["Home office deduction", "Vehicle expenses", "Business use of home"],
        "life_events": [],
        "complex_edge": ["Multiple states", "Complex situation"],
    }
    
    base = type_situations.get(scenario_type, [])
    situations.extend(random.sample(base, min(len(base), 2)))
    
    # Random additional situations
    optional = [
        "Student loan interest deduction",
        "HSA contributions",
        "401(k) contributions",
        "IRA contributions",
        "Alimony (pre-2019 agreement)",
        "Moving expenses (military)",
        "Educator expenses",
    ]
    
    if random.random() > 0.6:
        situations.append(random.choice(optional))
    
    return situations


def calculate_tax_outcome(income_sources: list, deductions: dict, credits: list, 
                          filing_status: str) -> dict:
    """Calculate simplified tax outcome."""
    total_income = sum(s.get("amount", 0) for s in income_sources)
    
    # Adjustments (simplified)
    adjustments = 0
    has_self_employment = any(s["type"] in ["1099-NEC"] for s in income_sources)
    if has_self_employment:
        se_income = sum(s["amount"] for s in income_sources if s["type"] == "1099-NEC")
        adjustments += int(se_income * 0.0765)  # SE tax deduction
    
    agi = total_income - adjustments
    taxable_income = max(0, agi - deductions["deduction_amount"])
    
    # Simplified tax calculation (2025 brackets - approximate)
    if filing_status == "Married Filing Jointly":
        tax = calculate_tax_mfj(taxable_income)
    else:
        tax = calculate_tax_single(taxable_income)
    
    # Add self-employment tax
    se_tax = 0
    if has_self_employment:
        se_income = sum(s["amount"] for s in income_sources if s["type"] == "1099-NEC")
        se_tax = int(se_income * 0.153 * 0.9235)
    
    total_tax = tax + se_tax
    
    # Apply credits
    total_credits = sum(c["amount"] for c in credits)
    tax_after_credits = max(0, total_tax - total_credits)
    
    # Withholding (estimate from W-2 income)
    w2_income = sum(s["amount"] for s in income_sources if s["type"] == "W-2")
    estimated_withholding = int(w2_income * random.uniform(0.15, 0.25))
    
    # Estimated payments if self-employed
    estimated_payments = 0
    if has_self_employment:
        estimated_payments = int(se_tax * random.uniform(0.7, 1.1))
    
    total_payments = estimated_withholding + estimated_payments
    
    if total_payments > tax_after_credits:
        refund = total_payments - tax_after_credits
        owed = 0
    else:
        refund = 0
        owed = tax_after_credits - total_payments
    
    return {
        "total_income": total_income,
        "adjusted_gross_income": agi,
        "taxable_income": taxable_income,
        "tax_liability": tax,
        "self_employment_tax": se_tax,
        "total_tax": total_tax,
        "credits_applied": total_credits,
        "tax_after_credits": tax_after_credits,
        "withholding": estimated_withholding,
        "estimated_payments": estimated_payments,
        "refund_amount": refund,
        "amount_owed": owed,
        "effective_tax_rate": round(tax_after_credits / max(total_income, 1) * 100, 1)
    }


def calculate_tax_single(taxable_income: int) -> int:
    """Calculate tax for Single filer (2025 brackets - approximate)."""
    brackets = [
        (11600, 0.10),
        (47150, 0.12),
        (100525, 0.22),
        (191950, 0.24),
        (243725, 0.32),
        (609350, 0.35),
        (float('inf'), 0.37)
    ]
    
    tax = 0
    prev_bracket = 0
    
    for bracket, rate in brackets:
        if taxable_income <= prev_bracket:
            break
        taxable_in_bracket = min(taxable_income, bracket) - prev_bracket
        tax += taxable_in_bracket * rate
        prev_bracket = bracket
    
    return int(tax)


def calculate_tax_mfj(taxable_income: int) -> int:
    """Calculate tax for Married Filing Jointly (2025 brackets - approximate)."""
    brackets = [
        (23200, 0.10),
        (94300, 0.12),
        (201050, 0.22),
        (383900, 0.24),
        (487450, 0.32),
        (731200, 0.35),
        (float('inf'), 0.37)
    ]
    
    tax = 0
    prev_bracket = 0
    
    for bracket, rate in brackets:
        if taxable_income <= prev_bracket:
            break
        taxable_in_bracket = min(taxable_income, bracket) - prev_bracket
        tax += taxable_in_bracket * rate
        prev_bracket = bracket
    
    return int(tax)


def generate_scenario_summary(scenario_type: str, filing_status: str, 
                               income_sources: list, deductions: dict,
                               special_situations: list, outcome: dict) -> str:
    """Generate natural language summary for embedding."""
    
    # Filing status description
    status_desc = filing_status.lower()
    
    # Income description
    income_parts = []
    for source in income_sources:
        if source["type"] == "W-2":
            income_parts.append(f"W-2 employee ({source['description']})")
        elif source["type"] == "1099-NEC":
            income_parts.append(f"self-employed {source['description'].lower()}")
        elif source["type"] == "Rental Income":
            income_parts.append("rental property income")
        elif source["type"] == "1099-DIV":
            income_parts.append("dividend income")
        elif source["type"] == "Capital Gains":
            income_parts.append("stock/investment sales")
        elif source["type"] == "Cryptocurrency":
            income_parts.append("cryptocurrency transactions")
    
    income_desc = " with ".join(income_parts) if income_parts else "various income"
    
    # Deduction description
    deduction_desc = f"taking {deductions['method'].lower()} deduction"
    
    # Build summary
    summary = f"{filing_status} filer, {income_desc}, {deduction_desc}."
    
    # Add special situations
    if special_situations:
        summary += f" Key factors: {', '.join(special_situations[:3]).lower()}."
    
    # Add outcome hint
    if outcome["refund_amount"] > 0:
        summary += f" Resulted in ${outcome['refund_amount']:,} refund."
    else:
        summary += f" Resulted in ${outcome['amount_owed']:,} owed."
    
    return summary


def generate_key_characteristics(scenario_type: str, income_sources: list,
                                   deductions: dict, credits: list,
                                   special_situations: list) -> list[str]:
    """Generate key characteristics tags for filtering and display."""
    chars = []
    
    # Filing status added elsewhere
    
    # Income types
    for source in income_sources:
        if source["type"] == "W-2":
            chars.append("w2_income")
        elif source["type"] == "1099-NEC":
            chars.append("self_employed")
            chars.append("1099_income")
        elif source["type"] == "Rental Income":
            chars.append("rental_income")
        elif source["type"] == "Cryptocurrency":
            chars.append("cryptocurrency")
        elif source["type"] == "Capital Gains":
            chars.append("capital_gains")
        elif source["type"] == "1099-DIV":
            chars.append("dividends")
    
    # Deductions
    if deductions["method"] == "Itemized":
        chars.append("itemized_deductions")
        for item in deductions.get("itemized_breakdown", []):
            if "mortgage" in item["type"].lower():
                chars.append("mortgage_interest")
            if "charitable" in item["type"].lower():
                chars.append("charitable_giving")
    else:
        chars.append("standard_deduction")
    
    # Credits
    for credit in credits:
        if "child" in credit["type"].lower():
            chars.append("child_tax_credit")
        if "earned income" in credit["type"].lower():
            chars.append("eitc")
        if "education" in credit["type"].lower() or "learning" in credit["type"].lower():
            chars.append("education_credit")
    
    # Scenario type
    chars.append(scenario_type)
    
    return list(set(chars))


def generate_resolution_notes(scenario_type: str, income_sources: list,
                               deductions: dict, special_situations: list) -> dict:
    """Generate resolution notes for how the case was handled."""
    
    notes = {
        "summary": "",
        "key_decisions": [],
        "forms_filed": ["Form 1040"],
        "lessons_learned": []
    }
    
    # Determine forms filed
    for source in income_sources:
        if source["type"] == "1099-NEC":
            notes["forms_filed"].extend(["Schedule C", "Schedule SE"])
        elif source["type"] == "Rental Income":
            notes["forms_filed"].append("Schedule E")
        elif source["type"] == "Capital Gains":
            notes["forms_filed"].extend(["Schedule D", "Form 8949"])
        elif source["type"] == "Cryptocurrency":
            notes["forms_filed"].extend(["Schedule D", "Form 8949"])
    
    if deductions["method"] == "Itemized":
        notes["forms_filed"].append("Schedule A")
    
    # Key decisions
    if deductions["method"] == "Itemized":
        notes["key_decisions"].append({
            "decision": "Deduction method",
            "choice": "Itemized",
            "rationale": f"Itemized ({deductions['itemized_total']:,}) exceeded standard ({deductions['standard_available']:,})"
        })
    
    # Home office decision
    has_home_office = any("home office" in s.lower() for s in special_situations)
    if has_home_office:
        method = random.choice(["Regular method", "Simplified method"])
        notes["key_decisions"].append({
            "decision": "Home office method",
            "choice": method,
            "rationale": "Based on expense comparison and documentation available"
        })
    
    # Generate summary
    form_list = ", ".join(notes["forms_filed"][:5])
    notes["summary"] = f"Filed {form_list}. {deductions['method']} deduction used."
    
    # Lessons learned
    lessons = [
        "Keep detailed records of all deductible expenses",
        "Track mileage contemporaneously if claiming vehicle deduction",
        "Maintain receipts for charitable contributions over $250",
        "Document home office square footage and exclusive use",
        "Calculate both deduction methods to maximize benefit"
    ]
    notes["lessons_learned"] = random.sample(lessons, 2)
    
    return notes


def generate_scenario(scenario_type: str, scenario_index: int) -> dict:
    """Generate a complete tax scenario."""
    
    # Basic info
    filing_status = random_weighted(FILING_STATUS_WEIGHTS)
    income_level = random_weighted(INCOME_RANGE_WEIGHTS)
    state = random.choice(STATES)
    
    # Dependents
    if filing_status in ["Married Filing Jointly", "Head of Household"]:
        dependents = random.choices([0, 1, 2, 3], weights=[0.3, 0.3, 0.25, 0.15])[0]
    else:
        dependents = random.choices([0, 1, 2], weights=[0.7, 0.2, 0.1])[0]
    
    # Generate components
    income_sources = generate_income_sources(scenario_type, income_level)
    deductions = generate_deductions(income_sources, filing_status)
    credits = generate_credits(income_sources, filing_status, dependents)
    special_situations = generate_special_situations(scenario_type)
    outcome = calculate_tax_outcome(income_sources, deductions, credits, filing_status)
    
    # Calculate complexity score
    complexity_base = {
        "simple_w2": 2, "dual_income": 3, "self_employed": 5,
        "rental_property": 6, "investments": 4, "cryptocurrency": 7,
        "home_office": 5, "life_events": 5, "complex_edge": 8
    }
    complexity = min(10, complexity_base.get(scenario_type, 5) + random.randint(-1, 2))
    
    # Generate narrative elements
    summary = generate_scenario_summary(
        scenario_type, filing_status, income_sources, 
        deductions, special_situations, outcome
    )
    
    key_chars = generate_key_characteristics(
        scenario_type, income_sources, deductions, 
        credits, special_situations
    )
    
    resolution = generate_resolution_notes(
        scenario_type, income_sources, deductions, special_situations
    )
    
    return {
        "scenario_id": f"SCN-2025-{scenario_index:05d}",
        "tax_year": 2025,
        "scenario_type": scenario_type,
        
        "taxpayer_profile": {
            "filing_status": filing_status,
            "dependents": dependents,
            "state": state[1],
            "state_abbr": state[0],
            "state_has_income_tax": state[2],
            "occupation": income_sources[0].get("description", "Employee") if income_sources else "Employee"
        },
        
        "income_sources": income_sources,
        "deductions": deductions,
        "credits": credits,
        "special_situations": special_situations,
        
        "tax_outcome": outcome,
        
        "complexity_score": complexity,
        "key_characteristics": key_chars,
        
        "scenario_summary": summary,
        "resolution_notes": resolution,
        
        # Placeholder for embedding (will be filled by embedding script)
        "embedding": None
    }


def generate_all_scenarios(total_count: int) -> list[dict]:
    """Generate all scenarios according to distribution."""
    
    # Calculate counts per category
    categories = {
        "simple_w2": 0.20,
        "dual_income": 0.10,
        "self_employed": 0.16,
        "rental_property": 0.10,
        "investments": 0.14,
        "cryptocurrency": 0.06,
        "home_office": 0.08,
        "life_events": 0.10,
        "complex_edge": 0.06,
    }
    
    scenarios = []
    scenario_index = 1
    
    for category, proportion in categories.items():
        count = int(total_count * proportion)
        print(f"   Generating {count} {category} scenarios...")
        
        for _ in range(count):
            scenario = generate_scenario(category, scenario_index)
            scenarios.append(scenario)
            scenario_index += 1
    
    # Fill remaining with random categories
    while len(scenarios) < total_count:
        category = random.choice(list(categories.keys()))
        scenario = generate_scenario(category, scenario_index)
        scenarios.append(scenario)
        scenario_index += 1
    
    # Shuffle to mix categories
    random.shuffle(scenarios)
    
    # Re-index after shuffle
    for i, scenario in enumerate(scenarios):
        scenario["scenario_id"] = f"SCN-2025-{i+1:05d}"
    
    return scenarios


def main():
    parser = argparse.ArgumentParser(description="Generate synthetic tax scenarios")
    parser.add_argument("--count", type=int, default=SCENARIO_COUNT,
                        help=f"Number of scenarios to generate (default: {SCENARIO_COUNT})")
    parser.add_argument("--output", type=str, default="tax_scenarios.json",
                        help="Output filename")
    
    args = parser.parse_args()
    
    print(f"\n{'='*60}")
    print(f"🎲 Generating {args.count} Tax Scenarios")
    print(f"{'='*60}")
    
    scenarios = generate_all_scenarios(args.count)
    
    # Save to file
    output_file = OUTPUT_DIR / args.output
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(scenarios, f, indent=2, ensure_ascii=False)
    
    # Statistics
    print(f"\n{'='*60}")
    print(f"📊 Generation Summary")
    print(f"{'='*60}")
    print(f"   Total scenarios: {len(scenarios)}")
    print(f"   Output file: {output_file}")
    print(f"   File size: {output_file.stat().st_size:,} bytes")
    
    # Category breakdown
    from collections import Counter
    type_counts = Counter(s["scenario_type"] for s in scenarios)
    print(f"\n   By type:")
    for stype, count in sorted(type_counts.items()):
        print(f"   - {stype}: {count}")
    
    # Complexity distribution
    complexity_counts = Counter(s["complexity_score"] for s in scenarios)
    print(f"\n   By complexity:")
    for score in sorted(complexity_counts.keys()):
        print(f"   - Level {score}: {complexity_counts[score]}")
    
    # Outcome statistics
    refunds = [s["tax_outcome"]["refund_amount"] for s in scenarios if s["tax_outcome"]["refund_amount"] > 0]
    owed = [s["tax_outcome"]["amount_owed"] for s in scenarios if s["tax_outcome"]["amount_owed"] > 0]
    
    print(f"\n   Outcomes:")
    print(f"   - Refunds: {len(refunds)} (avg ${sum(refunds)//max(len(refunds),1):,})")
    print(f"   - Owed: {len(owed)} (avg ${sum(owed)//max(len(owed),1):,})")


if __name__ == "__main__":
    main()
