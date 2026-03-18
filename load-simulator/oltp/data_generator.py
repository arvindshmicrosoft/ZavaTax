"""
Zava Tax Load Simulator - Data Generator

Generates realistic customer and tax return data with workflow simulation.
Simulates: Customer creation -> Draft return -> Edit cycles -> Submission
"""

import random
from datetime import datetime, timedelta, date
from typing import Iterator, Optional
from dataclasses import dataclass
from decimal import Decimal

from faker import Faker

fake = Faker()


FILING_STATUSES = [
    "Single",
    "Married Filing Jointly", 
    "Married Filing Separately",
    "Head of Household",
    "Qualifying Surviving Spouse"
]

FILING_STATUS_WEIGHTS = [0.44, 0.36, 0.03, 0.14, 0.03]

US_STATES = [
    'AL', 'AK', 'AZ', 'AR', 'CA', 'CO', 'CT', 'DE', 'FL', 'GA',
    'HI', 'ID', 'IL', 'IN', 'IA', 'KS', 'KY', 'LA', 'ME', 'MD',
    'MA', 'MI', 'MN', 'MS', 'MO', 'MT', 'NE', 'NV', 'NH', 'NJ',
    'NM', 'NY', 'NC', 'ND', 'OH', 'OK', 'OR', 'PA', 'RI', 'SC',
    'SD', 'TN', 'TX', 'UT', 'VT', 'VA', 'WA', 'WV', 'WI', 'WY'
]


@dataclass
class Customer:
    """Customer data for AddCustomer procedure."""
    first_name: str
    last_name: str
    email: str
    phone: str
    address: str
    city: str
    state: str
    state_abbr: str
    zip_code: str
    date_of_birth: date
    ssn_last_four: str
    preferred_language: str = 'English'
    preferred_contact: str = 'Email'


@dataclass
class TaxReturn:
    """Tax return data for SaveTaxReturnDraft procedure."""
    customer_id: Optional[int]  # Set after customer creation
    branch_id: int
    professional_id: int
    tax_year: int
    filing_status: str
    gross_income: Decimal
    adjusted_gross_income: Decimal
    total_deductions: Decimal
    taxable_income: Decimal
    tax_liability: Decimal
    total_withheld: Decimal
    refund_amount: Decimal
    amount_owed: Decimal
    is_itemized: bool
    num_dependents: int
    processing_time_minutes: int
    document_count: int
    ai_assistance_count: int
    is_amended: bool = False
    is_extension: bool = False
    has_foreign_accounts: bool = False
    foreign_account_max_value: Optional[int] = None
    has_pfic: bool = False
    pfic_value: Optional[int] = None
    pfic_income: Optional[int] = None
    has_foreign_trust: bool = False
    foreign_trust_value: Optional[int] = None
    has_foreign_corporation: bool = False
    foreign_corp_ownership_pct: Optional[int] = None
    has_foreign_partnership: bool = False
    foreign_gifts_received: Optional[int] = None
    foreign_taxes_paid: Optional[int] = None
    
    def mutate_for_edit(self):
        """Simulate editing the return - modify some values."""
        # Randomly adjust some financial values (simulates corrections/updates)
        if random.random() < 0.3:
            adjustment = Decimal(random.uniform(0.95, 1.05))
            self.gross_income = Decimal(int(self.gross_income * adjustment))
            self.adjusted_gross_income = Decimal(int(self.adjusted_gross_income * adjustment))
            self._recalculate_tax()
        
        if random.random() < 0.2:
            self.document_count += random.randint(1, 3)
            self.ai_assistance_count += random.randint(0, 2)
        
        if random.random() < 0.15:
            self.processing_time_minutes += random.randint(10, 45)
    
    def _recalculate_tax(self):
        """Recalculate tax values after income changes."""
        standard_deduction = 14600 if self.filing_status != "Married Filing Jointly" else 29200
        
        if self.is_itemized:
            self.total_deductions = Decimal(random.randint(
                standard_deduction, 
                max(standard_deduction, int(self.adjusted_gross_income * Decimal('0.25')))
            ))
        else:
            self.total_deductions = Decimal(standard_deduction)
        
        self.taxable_income = max(Decimal(0), self.adjusted_gross_income - self.total_deductions)
        
        # Tax calculation (simplified)
        if self.filing_status == "Married Filing Jointly":
            tax_rate = Decimal('0.15') if self.taxable_income < 100000 else Decimal('0.22')
        else:
            tax_rate = Decimal('0.18') if self.taxable_income < 50000 else Decimal('0.25')
        
        self.tax_liability = Decimal(int(self.taxable_income * tax_rate))
        
        if self.total_withheld > self.tax_liability:
            self.refund_amount = self.total_withheld - self.tax_liability
            self.amount_owed = Decimal(0)
        else:
            self.refund_amount = Decimal(0)
            self.amount_owed = self.tax_liability - self.total_withheld


@dataclass
class WorkflowSimulation:
    """Simulates a complete customer + tax return workflow."""
    customer: Customer
    tax_return: TaxReturn
    num_edits: int  # Number of edit cycles before submission (0-5)


class WorkflowGenerator:
    """Generates complete workflow simulations: Customer + Tax Return + Edit cycles."""
    
    def __init__(
        self,
        num_branches: int = 500,
        num_professionals: int = 2000,
        worker_id: int = 0,
        seed: int = None
    ):
        self.num_branches = num_branches
        self.num_professionals = num_professionals
        self.worker_id = worker_id
        
        if seed:
            random.seed(seed)
            Faker.seed(seed)
    
    def generate_customer(self) -> Customer:
        """Generate a realistic customer profile."""
        first_name = fake.first_name()
        last_name = fake.last_name()
        state_abbr = random.choice(US_STATES)
        
        return Customer(
            first_name=first_name,
            last_name=last_name,
            email=f"{first_name.lower()}.{last_name.lower()}@{fake.free_email_domain()}",
            phone=fake.phone_number()[:20],
            address=fake.street_address()[:500],
            city=fake.city()[:100],
            state=state_abbr,
            state_abbr=state_abbr,
            zip_code=fake.zipcode()[:10],
            date_of_birth=fake.date_of_birth(minimum_age=18, maximum_age=85),
            ssn_last_four=f"{random.randint(0, 9999):04d}",
            preferred_language='English',
            preferred_contact=random.choice(['Email', 'Phone'])
        )
    
    def generate_tax_return(self, customer_id: Optional[int] = None) -> TaxReturn:
        """Generate a realistic tax return (initially in Draft status)."""
        # Random branch and professional IDs
        branch_id = random.randint(1, self.num_branches)
        professional_id = random.randint(1, self.num_professionals)
        
        # Filing info
        tax_year = random.choice([2024, 2025])
        filing_status = random.choices(FILING_STATUSES, FILING_STATUS_WEIGHTS)[0]
        
        # Income (realistic distribution)
        income_bracket = random.choices(
            [(15000, 40000), (40000, 75000), (75000, 120000), (120000, 200000), (200000, 500000)],
            weights=[0.25, 0.35, 0.20, 0.12, 0.08]
        )[0]
        gross_income = Decimal(random.randint(*income_bracket))
        
        # Deductions and calculations
        agi = Decimal(int(gross_income * Decimal(str(random.uniform(0.88, 0.98)))))
        
        standard_deduction = 14600 if filing_status != "Married Filing Jointly" else 29200
        is_itemized = random.random() > 0.7 and agi > 80000
        
        if is_itemized:
            deductions = Decimal(random.randint(
                standard_deduction, 
                max(standard_deduction, int(agi * Decimal('0.25')))
            ))
        else:
            deductions = Decimal(standard_deduction)
        
        taxable_income = max(Decimal(0), agi - deductions)
        
        # Tax calculation (simplified)
        if filing_status == "Married Filing Jointly":
            tax_rate = Decimal('0.15') if taxable_income < 100000 else Decimal('0.22')
        else:
            tax_rate = Decimal('0.18') if taxable_income < 50000 else Decimal('0.25')
        
        tax_liability = Decimal(int(taxable_income * tax_rate))
        withholding = Decimal(int(gross_income * Decimal(str(random.uniform(0.14, 0.26)))))
        
        if withholding > tax_liability:
            refund = withholding - tax_liability
            owed = Decimal(0)
        else:
            refund = Decimal(0)
            owed = tax_liability - withholding
        
        # Operational metrics
        processing_minutes = random.randint(25, 180)
        document_count = random.randint(3, 20)
        ai_assistance_count = random.randint(0, 8)
        
        # International tax (10% chance)
        has_foreign = random.random() < 0.10
        
        return TaxReturn(
            customer_id=customer_id,
            branch_id=branch_id,
            professional_id=professional_id,
            tax_year=tax_year,
            filing_status=filing_status,
            gross_income=gross_income,
            adjusted_gross_income=agi,
            total_deductions=deductions,
            taxable_income=taxable_income,
            tax_liability=tax_liability,
            total_withheld=withholding,
            refund_amount=refund,
            amount_owed=owed,
            is_itemized=is_itemized,
            num_dependents=random.randint(0, 4),
            processing_time_minutes=processing_minutes,
            document_count=document_count,
            ai_assistance_count=ai_assistance_count,
            has_foreign_accounts=has_foreign,
            foreign_account_max_value=random.randint(50000, 500000) if has_foreign else None,
            foreign_taxes_paid=random.randint(1000, 25000) if has_foreign else None
        )
    
    def generate_workflow(self) -> WorkflowSimulation:
        """
        Generate a complete workflow simulation.
        
        Returns a customer, tax return, and number of edit cycles to simulate.
        Edit cycles: 0-5 with weighted distribution (most have 1-2 edits).
        """
        customer = self.generate_customer()
        tax_return = self.generate_tax_return()
        
        # Weighted edit cycles: 0=10%, 1=30%, 2=35%, 3=15%, 4=7%, 5=3%
        num_edits = random.choices(
            [0, 1, 2, 3, 4, 5],
            weights=[0.10, 0.30, 0.35, 0.15, 0.07, 0.03]
        )[0]
        
        return WorkflowSimulation(
            customer=customer,
            tax_return=tax_return,
            num_edits=num_edits
        )
    
    def generate_batch(self, size: int) -> list[WorkflowSimulation]:
        """Generate a batch of workflow simulations."""
        return [self.generate_workflow() for _ in range(size)]


# Convenience function for creating generators
def create_generator(config) -> WorkflowGenerator:
    """Create a generator from config."""
    return WorkflowGenerator(
        num_branches=config.load.num_branches,
        num_professionals=config.load.num_professionals,
        worker_id=0
    )
