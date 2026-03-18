-- =====================================================
-- Zava Tax - Local Development Database Setup
-- For SQL Server 2025 / SQL Server Express
-- =====================================================
-- This script creates the database and runs the unified
-- schema, then adds sample data for local development.
--
-- USAGE:
--   sqlcmd -i local_dev_setup.sql
-- =====================================================

USE master;
GO

-- Create database if it doesn't exist
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'ZavaTax')
BEGIN
    CREATE DATABASE ZavaTax;
    PRINT 'Created ZavaTax database.';
END
GO

USE ZavaTax;
GO

-- Enable preview features for SQL Server 2025 vector support
ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;
GO

-- =====================================================
-- Run the main schema
-- =====================================================
-- In SQLCMD mode, this would be: :r ..\01_create_schema.sql
-- For non-SQLCMD execution, run 01_create_schema.sql separately first
-- =====================================================

PRINT 'NOTE: Make sure you have run 01_create_schema.sql first!';
PRINT 'The main schema must exist before adding sample data.';
PRINT '';
GO

-- =====================================================
-- Sample Data for Local Development
-- =====================================================

-- Sample Branches
IF NOT EXISTS (SELECT 1 FROM Branches WHERE BranchName = 'Manhattan Central')
BEGIN
    SET IDENTITY_INSERT Branches ON;
    INSERT INTO Branches (BranchId, BranchName, Address, City, State, StateAbbr, ZipCode, Phone, ManagerName, IsFranchise)
    VALUES 
        (1, 'Manhattan Central', '350 5th Avenue', 'New York', 'New York', 'NY', '10001', '212-555-0100', 'Sarah Johnson', 1),
        (2, 'Downtown Los Angeles', '633 W 5th Street', 'Los Angeles', 'California', 'CA', '90012', '213-555-0200', 'Michael Chen', 1),
        (3, 'Chicago Loop', '111 S Wacker Drive', 'Chicago', 'Illinois', 'IL', '60601', '312-555-0300', 'Jennifer Williams', 1),
        (4, 'Houston Galleria', '2800 Post Oak Blvd', 'Houston', 'Texas', 'TX', '77056', '713-555-0400', 'Robert Martinez', 1),
        (5, 'Phoenix Central', '100 W Washington St', 'Phoenix', 'Arizona', 'AZ', '85004', '602-555-0500', 'Emily Davis', 1);
    SET IDENTITY_INSERT Branches OFF;
    PRINT 'Inserted sample branches.';
END
GO

-- Sample Tax Professionals
IF NOT EXISTS (SELECT 1 FROM TaxProfessionals WHERE Email = 'john.smith@zavatax.com')
BEGIN
    SET IDENTITY_INSERT TaxProfessionals ON;
    INSERT INTO TaxProfessionals (ProfessionalId, BranchId, FirstName, LastName, Email, Phone, Certification, YearsExperience, HireDate, IsActive)
    VALUES 
        (1, 1, 'John', 'Smith', 'john.smith@zavatax.com', '212-555-0101', 'CPA', 12, '2014-03-15', 1),
        (2, 1, 'Lisa', 'Wong', 'lisa.wong@zavatax.com', '212-555-0102', 'EA', 8, '2018-06-01', 1),
        (3, 2, 'James', 'Garcia', 'james.garcia@zavatax.com', '213-555-0201', 'CPA', 15, '2011-02-20', 1),
        (4, 3, 'Amanda', 'Brown', 'amanda.brown@zavatax.com', '312-555-0301', 'CPA', 10, '2016-08-10', 1),
        (5, 4, 'David', 'Lee', 'david.lee@zavatax.com', '713-555-0401', 'EA', 6, '2020-01-15', 1),
        (6, 1, 'Maria', 'Santos', 'maria.santos@zavatax.com', '212-555-0103', 'CPA', 9, '2017-04-10', 1),
        (7, 1, 'Kevin', 'O''Brien', 'kevin.obrien@zavatax.com', '212-555-0104', 'EA', 5, '2021-01-20', 1),
        (8, 1, 'Priya', 'Patel', 'priya.patel@zavatax.com', '212-555-0105', 'CPA', 7, '2019-09-15', 1),
        (9, 5, 'Carlos', 'Rivera', 'carlos.rivera@zavatax.com', '602-555-0501', 'EA', 4, '2022-03-01', 1);
    SET IDENTITY_INSERT TaxProfessionals OFF;
    PRINT 'Inserted sample tax professionals.';
END
GO

-- Sample Customers
IF NOT EXISTS (SELECT 1 FROM Customers WHERE Email = 'alice.j@email.com')
BEGIN
    SET IDENTITY_INSERT Customers ON;
    INSERT INTO Customers (CustomerId, FirstName, LastName, Email, Phone, Address, City, State, StateAbbr, ZipCode, DateOfBirth, PreferredLanguage, PreferredContact)
    VALUES 
        (1, 'Alice', 'Johnson', 'alice.j@email.com', '212-555-1001', '123 Main St Apt 4B', 'New York', 'New York', 'NY', '10001', '1985-06-15', 'English', 'Email'),
        (2, 'Bob', 'Williams', 'bob.w@email.com', '213-555-2002', '456 Oak Avenue', 'Los Angeles', 'California', 'CA', '90012', '1978-11-22', 'English', 'Phone'),
        (3, 'Carol', 'Davis', 'carol.d@email.com', '312-555-3003', '789 Elm Street', 'Chicago', 'Illinois', 'IL', '60601', '1990-03-08', 'English', 'Email'),
        (4, 'Dan', 'Miller', 'dan.m@email.com', '713-555-4004', '321 Pine Road', 'Houston', 'Texas', 'TX', '77056', '1982-09-30', 'English', 'Email'),
        (5, 'Eve', 'Wilson', 'eve.w@email.com', '602-555-5005', '654 Cedar Lane', 'Phoenix', 'Arizona', 'AZ', '85004', '1995-12-01', 'Spanish', 'Phone'),
        (6, 'Frank', 'Taylor', 'frank.t@email.com', '212-555-1006', '88 Broadway Apt 2A', 'New York', 'New York', 'NY', '10006', '1988-04-12', 'English', 'Email'),
        (7, 'Grace', 'Kim', 'grace.k@email.com', '212-555-1007', '200 West 72nd St', 'New York', 'New York', 'NY', '10023', '1992-07-25', 'English', 'Email'),
        (8, 'Henry', 'Nguyen', 'henry.n@email.com', '212-555-1008', '45 Park Place', 'New York', 'New York', 'NY', '10007', '1975-01-18', 'English', 'Phone'),
        (9, 'Isabel', 'Martinez', 'isabel.m@email.com', '212-555-1009', '310 E 46th St', 'New York', 'New York', 'NY', '10017', '1983-10-05', 'Spanish', 'Email'),
        (10, 'Jack', 'Thompson', 'jack.t@email.com', '212-555-1010', '150 W 85th St', 'New York', 'New York', 'NY', '10024', '1980-12-30', 'English', 'Email'),
        (11, 'Karen', 'Lee', 'karen.l@email.com', '212-555-1011', '520 8th Avenue', 'New York', 'New York', 'NY', '10018', '1991-05-14', 'English', 'Phone'),
        (12, 'Luis', 'Hernandez', 'luis.h@email.com', '212-555-1012', '77 Water St', 'New York', 'New York', 'NY', '10005', '1987-08-22', 'Spanish', 'Email');
    SET IDENTITY_INSERT Customers OFF;
    PRINT 'Inserted sample customers.';
END
GO

-- Sample Tax Returns
IF NOT EXISTS (SELECT 1 FROM TaxReturns WHERE CustomerId = 1 AND TaxYear = 2025)
BEGIN
    SET IDENTITY_INSERT TaxReturns ON;
    INSERT INTO TaxReturns (ReturnId, CustomerId, ProfessionalId, BranchId, TaxYear, FilingStatus, GrossIncome, AdjustedGrossIncome, TotalDeductions, TaxableIncome, TaxLiability, TotalWithheld, RefundAmount, AmountOwed, Status, FilingDate)
    VALUES 
        -- Professional 1 (John Smith, BranchId 1)
        (1,  1, 1, 1, 2025, 'Single', 75000.00, 72500.00, 14600.00, 57900.00, 8650.00, 9900.00, 1250.00, 0.00, 'Accepted', '2026-01-15'),
        (2,  1, 1, 1, 2024, 'Single', 72000.00, 69500.00, 13850.00, 55650.00, 8250.00, 9350.00, 1100.00, 0.00, 'Accepted', '2025-02-10'),
        -- Professional 2 (Lisa Wong, BranchId 1)
        (6,  6, 2, 1, 2025, 'Married Filing Jointly', 145000.00, 138000.00, 32400.00, 105600.00, 16200.00, 18500.00, 2300.00, 0.00, 'Accepted', '2026-01-18'),
        (7,  7, 2, 1, 2025, 'Single', 62000.00, 59800.00, 14600.00, 45200.00, 5890.00, 6800.00, 910.00, 0.00, 'Accepted', '2026-01-22'),
        -- Professional 3 (James Garcia, BranchId 2)
        (3,  2, 3, 2, 2025, 'Married Filing Jointly', 125000.00, 120000.00, 29200.00, 90800.00, 12460.00, 14800.00, 2340.00, 0.00, 'Pending', NULL),
        -- Professional 4 (Amanda Brown, BranchId 3)
        (4,  3, 4, 3, 2025, 'Head of Household', 85000.00, 82000.00, 21900.00, 60100.00, 8400.00, 10200.00, 1800.00, 0.00, 'Accepted', '2026-01-20'),
        -- Professional 5 (David Lee, BranchId 4)
        (5,  4, 5, 4, 2025, 'Single', 65000.00, 62500.00, 14600.00, 47900.00, 6510.00, 7400.00, 890.00, 0.00, 'Draft', NULL),
        -- Professional 6 (Maria Santos, BranchId 1)
        (8,  8, 6, 1, 2025, 'Married Filing Separately', 92000.00, 88500.00, 14600.00, 73900.00, 11850.00, 12400.00, 550.00, 0.00, 'Accepted', '2026-01-10'),
        (9,  9, 6, 1, 2025, 'Single', 54000.00, 51800.00, 14600.00, 37200.00, 4250.00, 5100.00, 850.00, 0.00, 'Pending', NULL),
        -- Professional 7 (Kevin O'Brien, BranchId 1)
        (10, 10, 7, 1, 2025, 'Head of Household', 78000.00, 75200.00, 21900.00, 53300.00, 7100.00, 8500.00, 1400.00, 0.00, 'Accepted', '2026-01-25'),
        (11, 11, 7, 1, 2025, 'Single', 48000.00, 46200.00, 14600.00, 31600.00, 3580.00, 4200.00, 620.00, 0.00, 'Accepted', '2026-01-28'),
        -- Professional 8 (Priya Patel, BranchId 1)
        (12, 12, 8, 1, 2025, 'Married Filing Jointly', 168000.00, 160000.00, 34500.00, 125500.00, 21400.00, 24000.00, 2600.00, 0.00, 'Accepted', '2026-01-12'),
        (13, 6,  8, 1, 2024, 'Married Filing Jointly', 140000.00, 133000.00, 30200.00, 102800.00, 15800.00, 17600.00, 1800.00, 0.00, 'Accepted', '2025-03-05');
    SET IDENTITY_INSERT TaxReturns OFF;
    PRINT 'Inserted sample tax returns.';
END
GO

-- Sample International Form Requirements (reference data)
IF NOT EXISTS (SELECT 1 FROM InternationalFormRequirements WHERE FormNumber = '8938')
BEGIN
    INSERT INTO InternationalFormRequirements (FormNumber, FormName, Description, ThresholdAmount, ThresholdDescription, Penalties, FilingDeadline)
    VALUES 
        ('8938', 'FATCA Statement of Specified Foreign Financial Assets', 'Report foreign financial accounts, securities, and other assets', 50000, 'Over $50,000 on last day or $75,000 at any time (single)', 'Up to $10,000 initial penalty, $50,000 for continued non-compliance', 'With tax return'),
        ('FinCEN 114', 'FBAR - Foreign Bank Account Report', 'Report foreign financial accounts held during the year', 10000, 'Aggregate balance exceeds $10,000 at any time', 'Civil penalties up to $12,909 per violation; willful up to $129,210', 'April 15 (auto-extended to October 15)'),
        ('8621', 'PFIC Annual Information Statement', 'Report ownership of Passive Foreign Investment Companies', NULL, 'Any ownership in a PFIC', 'Complex tax calculations and potential excess distribution taxes', 'With tax return'),
        ('3520', 'Foreign Trust and Gift Report', 'Report transactions with foreign trusts and large foreign gifts', 100000, 'Gifts/bequests over $100,000 from foreign persons', '$10,000 or 35% of gross value for trusts; 5% per month for gifts', 'With tax return (or extension)'),
        ('3520-A', 'Annual Information Return of Foreign Trust with U.S. Owner', 'Filed by foreign trust with U.S. owner', NULL, 'U.S. owner of foreign trust', '$10,000 penalty for failure to file', 'March 15'),
        ('5471', 'Information Return of U.S. Persons with Foreign Corporations', 'Report ownership in controlled foreign corporations', NULL, '10% or more ownership in foreign corporation', '$10,000 per return; $10,000 additional for each 30-day period', 'With tax return'),
        ('8865', 'Return of U.S. Persons with Respect to Certain Foreign Partnerships', 'Report ownership in foreign partnerships', NULL, 'Control or 10%+ ownership in foreign partnership', '$10,000 per return; additional penalties for continued failure', 'With tax return'),
        ('1116', 'Foreign Tax Credit', 'Claim credit for foreign taxes paid', NULL, 'Any foreign taxes paid or accrued', 'N/A - elective form to reduce tax', 'With tax return');
    PRINT 'Inserted international form requirements reference data.';
END
GO

-- =====================================================
-- Setup Complete
-- =====================================================
PRINT '';
PRINT '=====================================================';
PRINT 'Zava Tax local database setup complete!';
PRINT '=====================================================';
PRINT '';
PRINT 'Database: ZavaTax';
PRINT 'Sample data: 5 branches, 9 professionals (5 in Manhattan), 12 customers, 13 returns';
PRINT '';
PRINT 'NEXT STEPS:';
PRINT '  1. Load bulk data:     cd data-prep && python 07_load_to_sqlexpress.py';
PRINT '  2. OLTP procedures:    sqlcmd -S ".\SQLEXPRESS" -d ZavaTax -i "..\06_oltp_procedures.sql"';
PRINT '     (New Return wizard, return submission, load simulator workflows)';
PRINT '  3. Security features:  sqlcmd -S ".\SQLEXPRESS" -d ZavaTax -i "..\10_security_features.sql"';
PRINT '     (Ledger table, RLS, DDM, data classification, security demo procs)';
PRINT '  4. (Optional) Azure OpenAI: sqlcmd -S ".\SQLEXPRESS" -d ZavaTax -i "setup_openai_local.sql"';
PRINT '';
PRINT 'To connect with DAB, use one of these connection strings:';
PRINT '';
PRINT 'SQL Server 2025 / SQL Express:';
PRINT '  Server=localhost\SQLEXPRESS;Database=ZavaTax;Trusted_Connection=True;TrustServerCertificate=True;';
PRINT '';
PRINT 'SQL Server (default instance):';
PRINT '  Server=localhost;Database=ZavaTax;Trusted_Connection=True;TrustServerCertificate=True;';
PRINT '';
PRINT 'LocalDB:';
PRINT '  Server=(localdb)\MSSQLLocalDB;Database=ZavaTax;Integrated Security=True;TrustServerCertificate=True;';
GO
