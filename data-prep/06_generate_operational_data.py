"""
Step 6: Generate Operational Data

Generates synthetic operational data for HTAP and throughput demos:
- Branches
- Tax professionals  
- Customers
- Tax returns (for columnstore analytics)

Usage:
    python 06_generate_operational_data.py [--rows 1000000]
"""

import argparse
import csv
import json
import random
import concurrent.futures
import multiprocessing
import math
from datetime import datetime, timedelta
from pathlib import Path
from tqdm import tqdm
from faker import Faker

from config import OUTPUT_DIR, OPERATIONAL_ROWS, BRANCHES, CUSTOMERS, PROFESSIONALS

fake = Faker()
Faker.seed(42)
random.seed(42)

# ============================================================================
# REFERENCE DATA
# ============================================================================

US_STATES = [
    ("AL", "Alabama"), ("AK", "Alaska"), ("AZ", "Arizona"), ("AR", "Arkansas"),
    ("CA", "California"), ("CO", "Colorado"), ("CT", "Connecticut"), ("DE", "Delaware"),
    ("FL", "Florida"), ("GA", "Georgia"), ("HI", "Hawaii"), ("ID", "Idaho"),
    ("IL", "Illinois"), ("IN", "Indiana"), ("IA", "Iowa"), ("KS", "Kansas"),
    ("KY", "Kentucky"), ("LA", "Louisiana"), ("ME", "Maine"), ("MD", "Maryland"),
    ("MA", "Massachusetts"), ("MI", "Michigan"), ("MN", "Minnesota"), ("MS", "Mississippi"),
    ("MO", "Missouri"), ("MT", "Montana"), ("NE", "Nebraska"), ("NV", "Nevada"),
    ("NH", "New Hampshire"), ("NJ", "New Jersey"), ("NM", "New Mexico"), ("NY", "New York"),
    ("NC", "North Carolina"), ("ND", "North Dakota"), ("OH", "Ohio"), ("OK", "Oklahoma"),
    ("OR", "Oregon"), ("PA", "Pennsylvania"), ("RI", "Rhode Island"), ("SC", "South Carolina"),
    ("SD", "South Dakota"), ("TN", "Tennessee"), ("TX", "Texas"), ("UT", "Utah"),
    ("VT", "Vermont"), ("VA", "Virginia"), ("WA", "Washington"), ("WV", "West Virginia"),
    ("WI", "Wisconsin"), ("WY", "Wyoming")
]

FILING_STATUSES = [
    "Single", "Married Filing Jointly", "Married Filing Separately",
    "Head of Household", "Qualifying Surviving Spouse"
]


def generate_returns_batch(batch_args):
    """
    Generate a batch of tax returns.
    Arg is a tuple: (pairs_chunk, branch_to_profs, staffed_branch_ids, start_id)
    """
    pairs_chunk, branch_to_profs, staffed_branch_ids, start_id = batch_args
    
    # Re-seed random for each process to ensure variety if process logic is deterministic
    # (Though ProcessPool usually handles this, explicit seeding per process is safe)
    random.seed() 

    months = list(range(1, 13))
    month_weights = [15, 20, 25, 25, 3, 2, 2, 2, 1, 1, 2, 2]  # Heavy Jan-Apr
    
    income_ranges = [
        (10000, 30000, 0.20),
        (30000, 50000, 0.25),
        (50000, 75000, 0.20),
        (75000, 100000, 0.15),
        (100000, 150000, 0.10),
        (150000, 250000, 0.07),
        (250000, 500000, 0.03),
    ]

    results = []
    current_id = start_id
    
    for customer_id, tax_year in pairs_chunk:
        filing_year = tax_year + 1
        
        month = random.choices(months, month_weights)[0]
        day = random.randint(1, 28)
        
        try:
            filing_date = datetime(filing_year, month, day)
        except:
            filing_date = datetime(filing_year, month, 28)
        
        # Income based on distribution
        income_choice = random.random()
        cumulative = 0
        gross_income = 50000  # default
        for low, high, prob in income_ranges:
            cumulative += prob
            if income_choice <= cumulative:
                gross_income = random.randint(low, high)
                break
        
        # Derived values
        agi = int(gross_income * random.uniform(0.85, 1.0))
        
        filing_status = random.choices(
            FILING_STATUSES,
            weights=[0.44, 0.36, 0.03, 0.14, 0.03]
        )[0]
        
        # Standard vs itemized
        standard_deduction = 14600 if filing_status != "Married Filing Jointly" else 29200
        itemized = random.random() > 0.7 and agi > 75000

        # Ensure itemized deduction upper bound is at least standard_deduction
        itemized_max = max(standard_deduction + 1000, int(agi * 0.3))
        deduction = standard_deduction if not itemized else random.randint(standard_deduction, itemized_max)
        
        taxable_income = max(0, agi - deduction)
        
        # Simplified tax calculation
        if filing_status == "Married Filing Jointly":
            tax_rate = 0.18 if taxable_income < 200000 else 0.24
        else:
            tax_rate = 0.20 if taxable_income < 100000 else 0.26
        
        tax_liability = int(taxable_income * tax_rate)
        withholding = int(gross_income * random.uniform(0.15, 0.28))
        
        if withholding > tax_liability:
            refund = withholding - tax_liability
            owed = 0
        else:
            refund = 0
            owed = tax_liability - withholding
        
        # Assign to a random staffed branch, then pick a professional at that branch
        branch_id = random.choice(staffed_branch_ids)
        professional_id = random.choice(branch_to_profs[branch_id])

        # Return status logic (replicated)
        if tax_year == 2025:
            status = random.choices(
                ['Draft', 'In Progress', 'Filed', 'Accepted', 'Rejected'],
                weights=[0.25, 0.30, 0.25, 0.15, 0.05]
            )[0]
        elif tax_year == 2024:
            status = random.choices(
                ['Draft', 'In Progress', 'Filed', 'Accepted', 'Rejected'],
                weights=[0.05, 0.05, 0.15, 0.70, 0.05]
            )[0]
        else:
            status = random.choices(
                ['Draft', 'Filed', 'Accepted', 'Rejected'],
                weights=[0.02, 0.08, 0.87, 0.03]
            )[0]

        # International tax fields
        has_foreign_accounts = random.random() < 0.04
        has_pfic = random.random() < 0.01 if has_foreign_accounts else False
        has_foreign_trust = random.random() < 0.005
        has_foreign_corp = random.random() < 0.008
        has_foreign_partnership = random.random() < 0.005
        foreign_gifts = random.randint(0, 250000) if random.random() < 0.003 else 0
        foreign_taxes_paid = random.randint(100, 15000) if has_foreign_accounts else 0

        ret = {
            "return_id": current_id,
            "customer_id": customer_id,
            "branch_id": branch_id,
            "professional_id": professional_id,
            "tax_year": tax_year,
            "filing_date": filing_date.isoformat(),
            "filing_status": filing_status,
            "gross_income": gross_income,
            "adjusted_gross_income": agi,
            "total_deductions": deduction,
            "taxable_income": taxable_income,
            "tax_liability": tax_liability,
            "total_withholding": withholding,
            "refund_amount": refund,
            "amount_owed": owed,
            "status": status,
            "is_itemized": itemized,
            "num_dependents": random.choices([0, 1, 2, 3, 4], weights=[0.4, 0.25, 0.2, 0.1, 0.05])[0],
            "processing_time_minutes": random.randint(30, 180),
            "document_count": random.randint(3, 15),
            "ai_assistance_count": random.randint(0, 10),
            "is_amended": random.random() < 0.02,
            "is_extension": random.random() < 0.08,
            "has_foreign_accounts": has_foreign_accounts,
            "foreign_account_max_value": random.randint(10000, 500000) if has_foreign_accounts else 0,
            "has_pfic": has_pfic,
            "pfic_value": random.randint(5000, 200000) if has_pfic else 0,
            "pfic_income": random.randint(500, 20000) if has_pfic else 0,
            "has_foreign_trust": has_foreign_trust,
            "foreign_trust_value": random.randint(50000, 2000000) if has_foreign_trust else 0,
            "has_foreign_corporation": has_foreign_corp,
            "foreign_corp_ownership_pct": random.randint(10, 100) if has_foreign_corp else 0,
            "has_foreign_partnership": has_foreign_partnership,
            "foreign_gifts_received": foreign_gifts,
            "foreign_taxes_paid": foreign_taxes_paid,
            "created_at": filing_date.isoformat()
        }
        results.append(ret)
        current_id += 1
    
    return results


def generate_customers_batch(batch_args):
    """
    Generate a batch of customer records.
    Arg is a tuple: (start_id, count)
    """
    start_id, count = batch_args
    
    # Re-seed to ensure uniqueness across processes
    random.seed()
    Faker.seed() 
    local_fake = Faker()
    
    customers = []
    
    for i in range(count):
        state = random.choice(US_STATES)
        birth_date = local_fake.date_of_birth(minimum_age=18, maximum_age=85)
        
        customer = {
            "customer_id": start_id + i,
            "first_name": local_fake.first_name(),
            "last_name": local_fake.last_name(),
            "email": local_fake.email(),
            "phone": local_fake.phone_number(),
            "address": local_fake.street_address(),
            "city": local_fake.city(),
            "state": state[1],
            "state_abbr": state[0],
            "zip_code": local_fake.zipcode(),
            "date_of_birth": birth_date.isoformat(),
            "ssn_last_four": local_fake.random_number(digits=4, fix_len=True),
            "created_date": local_fake.date_between(start_date="-5y", end_date="-1d").isoformat(),
            "preferred_language": random.choices(["English", "Spanish", "Chinese", "Vietnamese", "Korean"], 
                                                  weights=[0.85, 0.08, 0.03, 0.02, 0.02])[0],
            "preferred_contact": random.choice(["Email", "Phone", "Text"]),
            "is_active": random.random() > 0.1
        }
        customers.append(customer)
        
    return customers


def generate_branches(count: int = 500) -> list[dict]:
    """Generate branch/franchise locations."""
    print(f"   Generating {count} branches...")
    
    branches = []
    cities_used = set()
    
    for i in range(count):
        state = random.choice(US_STATES)
        
        # Generate unique city within state
        attempts = 0
        while attempts < 10:
            city = fake.city()
            city_key = f"{city}, {state[0]}"
            if city_key not in cities_used:
                cities_used.add(city_key)
                break
            attempts += 1
        
        branch = {
            "branch_id": i + 1,
            "branch_name": f"Zava Tax - {city}",
            "address": fake.street_address(),
            "city": city,
            "state": state[1],
            "state_abbr": state[0],
            "zip_code": fake.zipcode_in_state(state[0]) if hasattr(fake, 'zipcode_in_state') else fake.zipcode(),
            "phone": fake.phone_number(),
            "manager_name": fake.name(),
            "opened_date": fake.date_between(start_date="-15y", end_date="-1y").isoformat(),
            "is_franchise": random.random() > 0.3,
            "square_feet": random.randint(800, 3000),
            "num_workstations": random.randint(4, 15)
        }
        branches.append(branch)
    
    return branches


def generate_tax_professionals(count: int = 200, branches: list = None) -> list[dict]:
    """Generate tax professional employees.
    
    Ensures every branch gets a realistic staffing level (3–8 pros).
    The 'count' arg is treated as a minimum; actual count may be higher
    to guarantee coverage of all branches.
    """
    branch_ids = [b["branch_id"] for b in branches] if branches else list(range(1, 501))
    
    # Assign a realistic headcount to each branch (3–8, weighted toward 4–5)
    branch_headcounts: dict[int, int] = {}
    for bid in branch_ids:
        branch_headcounts[bid] = random.choices(
            [3, 4, 5, 6, 7, 8],
            weights=[0.10, 0.25, 0.30, 0.20, 0.10, 0.05]
        )[0]
    
    total_needed = sum(branch_headcounts.values())
    actual_count = max(count, total_needed)
    print(f"   Generating {actual_count} tax professionals across {len(branch_ids)} branches "
          f"(avg {actual_count / len(branch_ids):.1f}/branch)...")
    
    certifications = ["CPA", "EA", "AFSP", "None"]
    cert_weights = [0.15, 0.25, 0.40, 0.20]
    
    professionals = []
    prof_id = 1
    
    # Phase 1: fill each branch to its target headcount
    for bid in branch_ids:
        for _ in range(branch_headcounts[bid]):
            hire_date = fake.date_between(start_date="-10y", end_date="-30d")
            prof = {
                "professional_id": prof_id,
                "branch_id": bid,
                "first_name": fake.first_name(),
                "last_name": fake.last_name(),
                "email": fake.email(),
                "phone": fake.phone_number(),
                "hire_date": hire_date.isoformat(),
                "certification": random.choices(certifications, cert_weights)[0],
                "years_experience": min(20, max(1, (datetime.now().date() - hire_date).days // 365 + random.randint(0, 5))),
                "is_active": random.random() > 0.05,
                "hourly_rate": random.randint(25, 75),
                "avg_returns_per_day": round(random.uniform(3, 12), 1)
            }
            professionals.append(prof)
            prof_id += 1
    
    # Phase 2: if caller asked for more than we generated, add extras randomly
    while len(professionals) < count:
        hire_date = fake.date_between(start_date="-10y", end_date="-30d")
        prof = {
            "professional_id": prof_id,
            "branch_id": random.choice(branch_ids),
            "first_name": fake.first_name(),
            "last_name": fake.last_name(),
            "email": fake.email(),
            "phone": fake.phone_number(),
            "hire_date": hire_date.isoformat(),
            "certification": random.choices(certifications, cert_weights)[0],
            "years_experience": min(20, max(1, (datetime.now().date() - hire_date).days // 365 + random.randint(0, 5))),
            "is_active": random.random() > 0.05,
            "hourly_rate": random.randint(25, 75),
            "avg_returns_per_day": round(random.uniform(3, 12), 1)
        }
        professionals.append(prof)
        prof_id += 1
    
    random.shuffle(professionals)
    return professionals


class BufferedCSVWriter:
    """Writes data to CSV files, splitting into chunks of max_rows."""
    def __init__(self, base_name: str, output_dir: Path, max_rows: int = 1000000):
        self.base_name = base_name
        self.output_dir = output_dir
        self.max_rows = max_rows
        self.current_part = 1
        self.buffer = []
        self.total_written = 0
        self.fieldnames = None

    def add_rows(self, rows: list[dict]):
        if not rows:
            return
            
        if self.fieldnames is None:
            self.fieldnames = list(rows[0].keys())
            
        self.buffer.extend(rows)
        
        while len(self.buffer) >= self.max_rows:
            chunk = self.buffer[:self.max_rows]
            self.buffer = self.buffer[self.max_rows:]
            self._write_file(chunk)

    def close(self):
        if self.buffer:
            self._write_file(self.buffer)
            self.buffer = []

    def _write_file(self, data):
        filename = f"{self.base_name}_part_{self.current_part:03d}.csv"
        filepath = self.output_dir / filename
        
        with open(filepath, 'w', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=self.fieldnames)
            writer.writeheader()
            writer.writerows(data)
            
        tqdm.write(f"   💾 Saved {filename} ({len(data):,} rows)")
        self.current_part += 1
        self.total_written += len(data)


def generate_customers(count: int = 10000) -> None:
    """Generate customer records in parallel and write to chunked CSVs."""
    print(f"   Generating {count} customers...")
    
    writer = BufferedCSVWriter("customers", OUTPUT_DIR)
    
    num_processes = multiprocessing.cpu_count()
    # Fixed batch size for better progress reporting (e.g., 5000 per task)
    batch_size = 5000
    
    batches = []
    current_start_id = 1
    remaining = count
    
    while remaining > 0:
        current_batch_size = min(batch_size, remaining)
        batches.append((current_start_id, current_batch_size))
        current_start_id += current_batch_size
        remaining -= current_batch_size

    print(f"   Starting {num_processes} parallel workers for customers (Processing {len(batches)} batches)...")
    
    with concurrent.futures.ProcessPoolExecutor(max_workers=num_processes) as executor:
        futures = {executor.submit(generate_customers_batch, b): i for i, b in enumerate(batches)}
        
        with tqdm(total=count, desc="   Customers", leave=False) as pbar:
            for future in concurrent.futures.as_completed(futures):
                batch_result = future.result()
                writer.add_rows(batch_result)
                pbar.update(len(batch_result))
    
    writer.close()
    print(f"   ✅ Finished generating {writer.total_written:,} customers")


def generate_tax_returns(count: int, branches: list, professionals: list, customers) -> None:
    """
    Generate tax return records for columnstore/HTAP demo in parallel and write to chunked CSVs.
    """
    # Verify input - customers might be None/count now if we don't return them
    customer_ids = []
    if isinstance(customers, int):
        customer_ids = list(range(1, customers + 1))
    elif isinstance(customers, list):
        customer_ids = [c["customer_id"] for c in customers]
    else:
        # Fallback if None passed (shouldn't happen with updated main)
        print("   ⚠️ No customer data provided to generate_tax_returns")
        return

    # Build a lookup: branch_id → list of professional_ids
    branch_to_profs: dict[int, list[int]] = {}
    for p in professionals:
        bid = p["branch_id"]
        branch_to_profs.setdefault(bid, []).append(p["professional_id"])
    
    # Only branches that actually have professionals can receive returns
    staffed_branch_ids = list(branch_to_profs.keys())
    
    # Tax years and filing probability (more recent years = more filers)
    tax_years = [2020, 2021, 2022, 2023, 2024, 2025]
    year_filing_prob = {
        2020: 0.60,  # Older year, fewer records
        2021: 0.70,
        2022: 0.80,
        2023: 0.85,
        2024: 0.95,  # Most customers filed
        2025: 0.75,  # Current year, still in progress
    }
    
    # Build all unique (customer_id, tax_year) pairs with probabilistic selection
    pairs = []
    print("   Calculating customer/year pairs...")
    for cid in tqdm(customer_ids, desc="   Pairs"):
        for ty in tax_years:
            if random.random() < year_filing_prob[ty]:
                pairs.append((cid, ty))
    
    # Shuffle for realistic insertion order
    random.shuffle(pairs)
    
    # Cap at requested count if needed
    if len(pairs) > count:
        pairs = pairs[:count]
    
    print(f"   Generating {len(pairs):,} tax returns ({len(customer_ids):,} customers × {len(tax_years)} tax years)...")
    
    writer = BufferedCSVWriter("tax_returns", OUTPUT_DIR)
    
    # --- Parallel Processing ---
    num_processes = multiprocessing.cpu_count()
    # Batch size needs to be large enough to offset process overhead
    # Fixed batch size for better progress reporting (e.g., 5000 per task)
    batch_size = 5000
    
    # Prepare arguments for each batch
    # Each batch needs: (pairs_chunk, branch_to_profs, staffed_branch_ids, start_id)
    batches = []
    current_start_id = 1
    
    for i in range(0, len(pairs), batch_size):
        chunk = pairs[i : i + batch_size]
        batches.append((chunk, branch_to_profs, staffed_branch_ids, current_start_id))
        current_start_id += len(chunk)

    print(f"   Starting {num_processes} parallel workers (Processing {len(batches)} batches)...")
    
    with concurrent.futures.ProcessPoolExecutor(max_workers=num_processes) as executor:
        # We process batches map-style or submit-style
        futures = {executor.submit(generate_returns_batch, b): i for i, b in enumerate(batches)}
        
        # Track progress by actual records (len(pairs)) rather than batches
        with tqdm(total=len(pairs), desc="   Returns", leave=False) as pbar:
            for future in concurrent.futures.as_completed(futures):
                batch_results = future.result()
                writer.add_rows(batch_results)
                pbar.update(len(batch_results))
            
    writer.close()
    print(f"   ✅ Finished generating {writer.total_written:,} tax returns")


def save_csv(data: list[dict], filepath: Path, fieldnames: list = None):
    """Save data to CSV file."""
    if not data:
        return
    
    fieldnames = fieldnames or list(data[0].keys())
    
    with open(filepath, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(data)


def main():
    parser = argparse.ArgumentParser(description="Generate operational data")
    parser.add_argument("--rows", type=int, default=OPERATIONAL_ROWS,
                        help=f"Number of tax return rows (default: {OPERATIONAL_ROWS})")
    parser.add_argument("--branches", type=int, default=BRANCHES,
                        help=f"Number of branches (default: {BRANCHES})")
    parser.add_argument("--professionals", type=int, default=PROFESSIONALS,
                        help=f"Min tax professionals; auto-scales to 3-8 per branch (default: {PROFESSIONALS})")
    parser.add_argument("--customers", type=int, default=CUSTOMERS,
                        help=f"Number of customers (default: {CUSTOMERS})")
    
    args = parser.parse_args()
    
    print(f"\n{'='*60}")
    print(f"🏢 Generating Operational Data")
    print(f"{'='*60}")
    
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    
    # Generate reference data
    branches = generate_branches(args.branches)
    professionals = generate_tax_professionals(args.professionals, branches)
    
    # Generate and save customers (direct to chunked files)
    generate_customers(args.customers)
    
    # Generate and save tax returns data (direct to chunked files)
    generate_tax_returns(args.rows, branches, professionals, args.customers)
    
    # Save reference data
    print(f"\n💾 Saving reference data files...")
    
    save_csv(branches, OUTPUT_DIR / "branches.csv")
    print(f"   ✅ branches.csv ({len(branches)} rows)")
    
    save_csv(professionals, OUTPUT_DIR / "tax_professionals.csv")
    print(f"   ✅ tax_professionals.csv ({len(professionals)} rows)")
    
    print(f"\n   Output directory: {OUTPUT_DIR}")
    
    # Staffing distribution
    from collections import Counter
    branch_counts = Counter(p["branch_id"] for p in professionals)
    staff_values = list(branch_counts.values())
    
    print(f"\n   Staffing Distribution:")
    print(f"   - Pros/branch: min={min(staff_values)}, max={max(staff_values)}, "
          f"avg={sum(staff_values)/len(staff_values):.1f}")
    print(f"   - Branches with 0 pros: {len(branches) - len(branch_counts)}")


if __name__ == "__main__":
    main()
