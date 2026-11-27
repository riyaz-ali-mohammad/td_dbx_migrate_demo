#!/usr/bin/env python3
"""
Synthetic data generator for the AML Transaction Monitoring demo batch
(td_banking_scripts). Produces:

  landing/   the 4 files the MultiLoad scripts import
             kycref.refsys.dat   fixed width, A(2) B(30) C(221)       -> kycref.15.LOAD_REFSYS.mld
             kycref.kycsys.dat   fixed width, A(2) B(26) C(472)       -> kycref.15.LOAD_KYCSYS.mld
             kycref.sancsys.txt  pipe delimited, heading line, UTF-8  -> kycref.15.LOAD_SANCSYS.mld
             dailytxn.dat        fixed width 1243, H / D / T records  -> dailytxn.02.LOAD_DATA.mld
  seed/      CSVs for tables maintained outside the batch, plus the transaction
             history the monitoring look-back windows need (one file per table,
             named <DATABASE>.<TABLE>.csv, columns in DDL order, header row)
  expected/  scenario manifest and expected results (alerts, screening hits,
             DQ findings, duplicates, control totals) to reconcile the
             Teradata and the migrated Databricks runs against

All people, companies, banks, BICs, sort codes and sanctions designations are
fictitious. Country risk statuses are illustrative only.

Usage:  python3 generate_aml_data.py --out ..  [--run-date 2026-11-25] [--seed 42]
                                     [--parties 1000] [--history-days 150]
"""
import argparse
import csv
import datetime as dt
import math
import os
import random
import uuid
from collections import defaultdict, Counter

D = dt.date
ONE = dt.timedelta(days=1)


# ======================================================================================
# helpers
# ======================================================================================
def ymd(d):
    return d.strftime("%Y%m%d") if d else "00000000"


def dmy(d):
    return d.strftime("%d/%m/%Y") if d else ""


def fw(v, n):
    s = "" if v is None else str(v)
    return s[:n].ljust(n)


def money(v):
    return f"{v:.2f}"


_TR = str.maketrans(".,'-&/()", "        ")


def norm(x):
    """Shared name normalisation (kycref.60 / dailytxn.05 / dailytxn.08)."""
    if x is None:
        return ""
    s = x.strip().upper().translate(_TR)
    s = s.replace("  ", " ").replace("  ", " ")
    return s.strip()


class Payload:
    """Fixed-width payload with 1-based positions (as documented in the SQL banners)."""

    def __init__(self, n):
        self.c = [" "] * n

    def put(self, pos, ln, val):
        s = fw(val, ln)
        self.c[pos - 1:pos - 1 + ln] = list(s)
        return self

    def s(self):
        return "".join(self.c)


def easter(y):
    a = y % 19; b = y // 100; c = y % 100; d = b // 4; e = b % 4
    f = (b + 8) // 25; g = (b - f + 1) // 3; h = (19 * a + b - d - g + 15) % 30
    i = c // 4; k = c % 4; l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) // 451
    mon = (h + l - 7 * m + 114) // 31; day = ((h + l - 7 * m + 114) % 31) + 1
    return D(y, mon, day)


def uk_bank_holidays(y):
    """England & Wales bank holidays."""
    hol = {}
    nyd = D(y, 1, 1)
    nyd = nyd + ONE * {5: 2, 6: 1}.get(nyd.weekday(), 0)
    hol[nyd] = "New Year's Day"
    e = easter(y)
    hol[e - 2 * ONE] = "Good Friday"
    hol[e + ONE] = "Easter Monday"
    may1 = D(y, 5, 1)
    early = may1 + ONE * ((7 - may1.weekday()) % 7)
    spring = D(y, 5, 31) - ONE * D(y, 5, 31).weekday()
    summer = D(y, 8, 31) - ONE * D(y, 8, 31).weekday()
    if y == 2020:
        early = D(2020, 5, 8)
    if y == 2022:
        spring = D(2022, 6, 2)
        hol[D(2022, 6, 3)] = "Platinum Jubilee"
        hol[D(2022, 9, 19)] = "State Funeral"
    if y == 2023:
        hol[D(2023, 5, 8)] = "Coronation"
    hol[early] = "Early May bank holiday"
    hol[spring] = "Spring bank holiday"
    hol[summer] = "Summer bank holiday"
    xmas = D(y, 12, 25)
    if xmas.weekday() == 5:
        days = (27, 28)
    elif xmas.weekday() == 6:
        days = (27, 26)
    elif D(y, 12, 26).weekday() == 5:
        days = (25, 28)
    else:
        days = (25, 26)
    hol[D(y, 12, days[0])] = "Christmas Day" + (" (substitute)" if days[0] != 25 else "")
    hol[D(y, 12, days[1])] = "Boxing Day" + (" (substitute)" if days[1] != 26 else "")
    return hol


# ======================================================================================
# reference data (REFSYS)
# ======================================================================================
# iso2, iso3, name, fatf, hmt_hr, eu_hr, basel, cpi, offshore, region
COUNTRIES = [
    ("GB", "GBR", "United Kingdom", "NA", "N", "N", 3.90, 71, "N", "EUR"),
    ("IE", "IRL", "Ireland", "NA", "N", "N", 3.70, 77, "N", "EUR"),
    ("FR", "FRA", "France", "NA", "N", "N", 4.10, 71, "N", "EUR"),
    ("DE", "DEU", "Germany", "NA", "N", "N", 4.00, 78, "N", "EUR"),
    ("NL", "NLD", "Netherlands", "NA", "N", "N", 4.20, 79, "N", "EUR"),
    ("BE", "BEL", "Belgium", "NA", "N", "N", 4.10, 73, "N", "EUR"),
    ("ES", "ESP", "Spain", "NA", "N", "N", 4.30, 60, "N", "EUR"),
    ("PT", "PRT", "Portugal", "NA", "N", "N", 4.20, 61, "N", "EUR"),
    ("IT", "ITA", "Italy", "NA", "N", "N", 4.60, 56, "N", "EUR"),
    ("CH", "CHE", "Switzerland", "NA", "N", "N", 4.80, 82, "N", "EUR"),
    ("AT", "AUT", "Austria", "NA", "N", "N", 4.10, 71, "N", "EUR"),
    ("PL", "POL", "Poland", "NA", "N", "N", 4.50, 54, "N", "EUR"),
    ("RO", "ROU", "Romania", "NA", "N", "N", 4.90, 46, "N", "EUR"),
    ("BG", "BGR", "Bulgaria", "NA", "N", "N", 5.10, 43, "N", "EUR"),
    ("GR", "GRC", "Greece", "NA", "N", "N", 4.70, 49, "N", "EUR"),
    ("CY", "CYP", "Cyprus", "NA", "N", "N", 5.10, 53, "N", "EUR"),
    ("MT", "MLT", "Malta", "NA", "N", "N", 4.90, 51, "N", "EUR"),
    ("LU", "LUX", "Luxembourg", "NA", "N", "N", 4.60, 78, "N", "EUR"),
    ("SE", "SWE", "Sweden", "NA", "N", "N", 3.60, 82, "N", "EUR"),
    ("NO", "NOR", "Norway", "NA", "N", "N", 3.50, 84, "N", "EUR"),
    ("DK", "DNK", "Denmark", "NA", "N", "N", 3.40, 90, "N", "EUR"),
    ("FI", "FIN", "Finland", "NA", "N", "N", 3.30, 87, "N", "EUR"),
    ("LT", "LTU", "Lithuania", "NA", "N", "N", 4.40, 61, "N", "EUR"),
    ("JE", "JEY", "Jersey", "NA", "N", "N", 4.20, 0, "Y", "EUR"),
    ("GG", "GGY", "Guernsey", "NA", "N", "N", 4.20, 0, "Y", "EUR"),
    ("IM", "IMN", "Isle of Man", "NA", "N", "N", 4.30, 0, "Y", "EUR"),
    ("GI", "GIB", "Gibraltar", "NA", "N", "N", 4.80, 0, "Y", "EUR"),
    ("US", "USA", "United States", "NA", "N", "N", 4.80, 69, "N", "AME"),
    ("CA", "CAN", "Canada", "NA", "N", "N", 4.30, 76, "N", "AME"),
    ("MX", "MEX", "Mexico", "NA", "N", "N", 5.90, 31, "N", "AME"),
    ("BR", "BRA", "Brazil", "NA", "N", "N", 5.50, 36, "N", "AME"),
    ("VE", "VEN", "Venezuela", "GL", "Y", "Y", 7.20, 13, "N", "AME"),
    ("HT", "HTI", "Haiti", "GL", "Y", "Y", 7.60, 17, "N", "AME"),
    ("KY", "CYM", "Cayman Islands", "NA", "N", "N", 5.20, 0, "Y", "AME"),
    ("VG", "VGB", "British Virgin Islands", "NA", "N", "N", 5.40, 0, "Y", "AME"),
    ("BM", "BMU", "Bermuda", "NA", "N", "N", 4.90, 0, "Y", "AME"),
    ("PA", "PAN", "Panama", "NA", "N", "N", 6.10, 35, "Y", "AME"),
    ("BS", "BHS", "Bahamas", "NA", "N", "N", 5.60, 64, "Y", "AME"),
    ("AE", "ARE", "United Arab Emirates", "NA", "N", "N", 5.60, 68, "N", "MEA"),
    ("SA", "SAU", "Saudi Arabia", "NA", "N", "N", 5.40, 52, "N", "MEA"),
    ("QA", "QAT", "Qatar", "NA", "N", "N", 5.10, 58, "N", "MEA"),
    ("TR", "TUR", "Turkey", "NA", "N", "N", 5.90, 34, "N", "MEA"),
    ("IL", "ISR", "Israel", "NA", "N", "N", 4.50, 62, "N", "MEA"),
    ("EG", "EGY", "Egypt", "NA", "N", "N", 5.80, 35, "N", "MEA"),
    ("IR", "IRN", "Iran", "BL", "Y", "Y", 8.10, 24, "N", "MEA"),
    ("SY", "SYR", "Syria", "GL", "Y", "Y", 8.00, 13, "N", "MEA"),
    ("YE", "YEM", "Yemen", "GL", "Y", "Y", 7.40, 16, "N", "MEA"),
    ("NG", "NGA", "Nigeria", "GL", "Y", "Y", 7.00, 25, "N", "AFR"),
    ("ZA", "ZAF", "South Africa", "NA", "N", "N", 5.60, 41, "N", "AFR"),
    ("KE", "KEN", "Kenya", "NA", "N", "N", 6.30, 31, "N", "AFR"),
    ("GH", "GHA", "Ghana", "NA", "N", "N", 5.70, 43, "N", "AFR"),
    ("SS", "SSD", "South Sudan", "GL", "Y", "Y", 7.90, 8, "N", "AFR"),
    ("IN", "IND", "India", "NA", "N", "N", 5.30, 39, "N", "APA"),
    ("PK", "PAK", "Pakistan", "NA", "N", "N", 6.40, 29, "N", "APA"),
    ("BD", "BGD", "Bangladesh", "NA", "N", "N", 6.60, 24, "N", "APA"),
    ("CN", "CHN", "China", "NA", "N", "N", 6.00, 43, "N", "APA"),
    ("HK", "HKG", "Hong Kong", "NA", "N", "N", 5.00, 75, "N", "APA"),
    ("SG", "SGP", "Singapore", "NA", "N", "N", 4.30, 83, "N", "APA"),
    ("JP", "JPN", "Japan", "NA", "N", "N", 4.20, 73, "N", "APA"),
    ("AU", "AUS", "Australia", "NA", "N", "N", 4.10, 75, "N", "APA"),
    ("NZ", "NZL", "New Zealand", "NA", "N", "N", 3.60, 85, "N", "APA"),
    ("TH", "THA", "Thailand", "NA", "N", "N", 5.70, 35, "N", "APA"),
    ("VN", "VNM", "Vietnam", "GL", "Y", "N", 6.70, 41, "N", "APA"),
    ("PH", "PHL", "Philippines", "NA", "N", "N", 6.20, 34, "N", "APA"),
    ("MY", "MYS", "Malaysia", "NA", "N", "N", 5.20, 50, "N", "APA"),
    ("MM", "MMR", "Myanmar", "BL", "Y", "Y", 8.20, 20, "N", "APA"),
    ("KP", "PRK", "North Korea", "BL", "Y", "Y", 8.50, 17, "N", "APA"),
    ("AF", "AFG", "Afghanistan", "NA", "Y", "Y", 7.80, 20, "N", "APA"),
    ("RU", "RUS", "Russia", "NA", "N", "Y", 6.60, 26, "N", "EUR"),
    ("BY", "BLR", "Belarus", "NA", "N", "N", 6.10, 37, "N", "EUR"),
    ("UA", "UKR", "Ukraine", "NA", "N", "N", 5.90, 36, "N", "EUR"),
]
CTRY = {c[0]: c for c in COUNTRIES}


def ctry_risk(c):
    _, _, _, fatf, hmt, eu, basel, _, off, _ = CTRY[c]
    if fatf in ("BL", "GL") or hmt == "Y" or eu == "Y" or basel >= 6.50:
        return "H"
    if off == "Y" or basel >= 5.00:
        return "M"
    return "L"


HIGH_RISK_CTRY = {c for c in CTRY if ctry_risk(c) == "H" or CTRY[c][8] == "Y"}

# ccy, name, minor units, numeric, base units-per-GBP (None = no FX rate delivered)
CURRENCIES = [
    ("GBP", "Pound Sterling", 2, "826", 1.0), ("EUR", "Euro", 2, "978", 1.17),
    ("USD", "US Dollar", 2, "840", 1.27), ("CHF", "Swiss Franc", 2, "756", 1.12),
    ("JPY", "Yen", 0, "392", 190.0), ("AED", "UAE Dirham", 2, "784", 4.66),
    ("CNY", "Yuan Renminbi", 2, "156", 9.20), ("INR", "Indian Rupee", 2, "356", 106.0),
    ("NGN", "Naira", 2, "566", 1950.0), ("PLN", "Zloty", 2, "985", 5.05),
    ("RON", "Romanian Leu", 2, "946", 5.82), ("TRY", "Turkish Lira", 2, "949", 43.0),
    ("HKD", "Hong Kong Dollar", 2, "344", 9.90), ("SGD", "Singapore Dollar", 2, "702", 1.70),
    ("CAD", "Canadian Dollar", 2, "124", 1.76), ("AUD", "Australian Dollar", 2, "036", 1.93),
    ("ZAR", "Rand", 2, "710", 23.0), ("SEK", "Swedish Krona", 2, "752", 13.6),
    ("NOK", "Norwegian Krone", 2, "578", 13.9), ("DKK", "Danish Krone", 2, "208", 8.72),
    ("PKR", "Pakistan Rupee", 2, "586", 355.0), ("KES", "Kenyan Shilling", 2, "404", None),
]

# mcc, desc, risk, cash_like, gambling, crypto
MCCS = [
    ("5411", "Grocery stores and supermarkets", "L", "N", "N", "N"),
    ("5812", "Eating places and restaurants", "L", "N", "N", "N"),
    ("5814", "Fast food restaurants", "L", "N", "N", "N"),
    ("5541", "Service stations", "L", "N", "N", "N"),
    ("5912", "Drug stores and pharmacies", "L", "N", "N", "N"),
    ("5311", "Department stores", "L", "N", "N", "N"),
    ("5651", "Family clothing stores", "L", "N", "N", "N"),
    ("5732", "Electronics stores", "M", "N", "N", "N"),
    ("5942", "Book stores", "L", "N", "N", "N"),
    ("5999", "Miscellaneous retail", "L", "N", "N", "N"),
    ("4111", "Commuter transport", "L", "N", "N", "N"),
    ("4121", "Taxicabs and limousines", "L", "N", "N", "N"),
    ("4511", "Airlines", "L", "N", "N", "N"),
    ("7011", "Hotels and lodging", "L", "N", "N", "N"),
    ("4814", "Telecommunication services", "L", "N", "N", "N"),
    ("4900", "Utilities", "L", "N", "N", "N"),
    ("5815", "Digital goods - media", "L", "N", "N", "N"),
    ("7832", "Cinemas", "L", "N", "N", "N"),
    ("8011", "Doctors", "L", "N", "N", "N"),
    ("8220", "Colleges and universities", "L", "N", "N", "N"),
    ("8999", "Professional services", "M", "N", "N", "N"),
    ("9399", "Government services", "L", "N", "N", "N"),
    ("5944", "Jewellery and watch stores", "H", "N", "N", "N"),
    ("5933", "Pawn shops", "H", "Y", "N", "N"),
    ("4829", "Money transfer", "H", "Y", "N", "N"),
    ("6010", "Manual cash disbursement", "M", "Y", "N", "N"),
    ("6011", "Automated cash disbursement", "M", "Y", "N", "N"),
    ("6012", "Financial institutions - merchandise", "M", "N", "N", "N"),
    ("6051", "Quasi cash - crypto assets", "H", "Y", "N", "Y"),
    ("6211", "Security brokers and dealers", "M", "N", "N", "N"),
    ("7995", "Betting and casino gambling", "H", "Y", "Y", "N"),
    ("7800", "Government owned lotteries", "M", "N", "Y", "N"),
    ("7801", "Internet gambling", "H", "Y", "Y", "N"),
    ("7273", "Dating services", "M", "N", "N", "N"),
    ("5094", "Precious stones and metals", "H", "N", "N", "N"),
]
MCC = {m[0]: m for m in MCCS}

OWN_BANK = "ORIGIN BANK PLC"
OWN_BIC = "ORGNGB2LXXX"
OWN_SORTS = [f"9910{i:02d}" for i in range(1, 13)]
OWN_BRANCHES = ["LEEDS CITY", "MANCHESTER KING ST", "BIRMINGHAM NEW ST", "LONDON MOORGATE",
                "BRISTOL BROADMEAD", "GLASGOW BUCHANAN", "CARDIFF QUEEN ST", "NEWCASTLE GREY ST",
                "LIVERPOOL LORD ST", "NOTTINGHAM OLD MKT", "SHEFFIELD FARGATE", "LONDON CANARY WHARF"]
PEER_BANKS = [("NORTHGATE BANK PLC", "NGTBGB2L"), ("THAMES MUTUAL BANK", "THMBGB2L"),
              ("PENNINE BUILDING SOCIETY", "PENBGB21"), ("UNION COUNTIES BANK", "UNCBGB2L"),
              ("SEVERN DIGITAL BANK", "SVDBGB2L"), ("CALEDONIAN BANK PLC", "CLDBGB2E"),
              ("HARBOUR CHALLENGER BANK", "HRBCGB2L"), ("MERIDIAN PAYMENTS LTD", "MRDPGB2L")]
CLOSED_SORT = "992999"
POSTCODES = ["LS1 4AP", "LS6 2QE", "M1 3BN", "M20 4TR", "B1 2JP", "B15 3AA", "EC2R 6DA", "E14 5LQ",
             "SW1A 2AA", "N1 9GU", "BS1 3XE", "G1 2FF", "CF10 1EP", "NE1 6JQ", "L1 8JQ", "NG1 2BY",
             "S1 2HE", "OX1 3PN", "CB2 1TN", "YO1 7HH", "EH1 1YZ", "BN1 1AE", "RG1 1AF", "MK9 3EP"]

# txn type, desc, scheme, direction, cash, xborder, supplier, default channel
TXN_TYPES = [
    ("FPSI", "Faster Payment received", "FPS", "C", "N", "N", "PAY1", "BAT"),
    ("FPSO", "Faster Payment sent", "FPS", "D", "N", "N", "PAY1", "MOB"),
    ("BACC", "BACS credit received", "BACS", "C", "N", "N", "PAY1", "BAT"),
    ("BACD", "BACS payment sent (bulk)", "BACS", "D", "N", "N", "PAY1", "OLB"),
    ("DDBT", "Direct Debit", "DD", "D", "N", "N", "CBS1", "BAT"),
    ("SORD", "Standing order", "SO", "D", "N", "N", "CBS1", "BAT"),
    ("CHPI", "CHAPS payment received", "CHAP", "C", "N", "N", "PAY1", "BAT"),
    ("CHPO", "CHAPS payment sent", "CHAP", "D", "N", "N", "PAY1", "OLB"),
    ("SWFI", "International payment received", "SWFT", "C", "N", "Y", "PAY1", "BAT"),
    ("SWFO", "International payment sent", "SWFT", "D", "N", "Y", "PAY1", "OLB"),
    ("CRDP", "Debit card purchase", "CARD", "D", "N", "N", "CRD1", "POS"),
    ("CRDR", "Debit card refund", "CARD", "C", "N", "N", "CRD1", "POS"),
    ("ATMW", "ATM cash withdrawal", "CASH", "D", "Y", "N", "CRD1", "ATM"),
    ("CSHD", "Cash deposit at branch", "CASH", "C", "Y", "N", "CBS1", "BRN"),
    ("CSHW", "Cash withdrawal at branch", "CASH", "D", "Y", "N", "CBS1", "BRN"),
    ("CHQD", "Cheque deposit", "CHQ", "C", "N", "N", "CBS1", "BRN"),
    ("ITRI", "Internal transfer in", "BOOK", "C", "N", "N", "CBS1", "MOB"),
    ("ITRO", "Internal transfer out", "BOOK", "D", "N", "N", "CBS1", "MOB"),
    ("FEEC", "Account fee", "BOOK", "D", "N", "N", "CBS1", "BAT"),
    ("INTC", "Credit interest", "BOOK", "C", "N", "N", "CBS1", "BAT"),
]
TT = {t[0]: t for t in TXN_TYPES}

CHANNELS = [("BRN", "Branch counter", "N"), ("OLB", "Online banking", "Y"), ("MOB", "Mobile app", "Y"),
            ("TEL", "Telephone banking", "N"), ("ATM", "ATM network", "N"), ("POS", "Card point of sale", "N"),
            ("API", "Open banking API", "Y"), ("BAT", "Batch / scheme file", "N"),
            ("RMG", "Relationship manager", "N")]
CHNL_DIGITAL = {c[0]: c[2] for c in CHANNELS}

# product, desc, family, segment, risk
PRODUCTS = [("RETCUR", "Everyday current account", "CURR", "RET", "L"),
            ("RETBAS", "Basic bank account", "CURR", "RET", "M"),
            ("RETSAV", "Easy access saver", "SAVE", "RET", "L"),
            ("RETISA", "Cash ISA", "ISA", "RET", "L"),
            ("BUSCUR", "Business current account", "BUSI", "BUS", "M"),
            ("BUSSAV", "Business reserve account", "SAVE", "BUS", "L"),
            ("CIBCUR", "Corporate operating account", "BUSI", "CIB", "M"),
            ("CIBTRD", "Trade finance settlement account", "BUSI", "CIB", "H"),
            ("WLTCUR", "Premier current account", "CURR", "WLT", "M"),
            ("WLTINV", "Wealth investment cash account", "INVS", "WLT", "H")]
PRDT = {p[0]: p for p in PRODUCTS}

# sic, desc, risk, cash intensive
SICS = [("99999", "Individual - employed", "L", "N"), ("99998", "Individual - student", "L", "N"),
        ("99997", "Individual - retired", "L", "N"), ("99996", "Individual - self employed", "M", "N"),
        ("62020", "Information technology consultancy", "L", "N"),
        ("86210", "General medical practice", "L", "N"), ("85200", "Primary education", "L", "N"),
        ("70229", "Management consultancy", "M", "N"), ("41100", "Development of building projects", "M", "N"),
        ("49410", "Freight transport by road", "M", "N"), ("43210", "Electrical installation", "L", "N"),
        ("56101", "Licensed restaurants", "M", "Y"), ("56302", "Public houses and bars", "M", "Y"),
        ("47110", "Retail sale in non-specialised stores", "M", "Y"), ("96020", "Hairdressing and beauty", "M", "Y"),
        ("45112", "Sale of used cars and light vehicles", "H", "Y"), ("47770", "Retail sale of watches and jewellery", "H", "Y"),
        ("92000", "Gambling and betting activities", "H", "Y"), ("64999", "Financial intermediation n.e.c.", "H", "N"),
        ("68100", "Buying and selling of own real estate", "H", "N"), ("46720", "Wholesale of metals and metal ores", "H", "N"),
        ("66190", "Money service business", "H", "Y"), ("10710", "Manufacture of bread", "L", "N"),
        ("46900", "Non-specialised wholesale trade", "M", "N"), ("52290", "Other transportation support", "M", "N")]
SIC = {s[0]: s for s in SICS}

# rule, segment, amt, cnt, lookback, pct, weight, desc
RULES = [
    ("TM_STR01", "ALL", 10000, 3, 7, 80, 60, "Structuring - cash credits just below threshold"),
    ("TM_RPM01", "ALL", 25000, 1, 7, 90, 70, "Rapid movement of funds - pass through"),
    ("TM_RPM01", "RET", 10000, 1, 7, 90, 70, "Rapid movement of funds - pass through (retail)"),
    ("TM_RPM01", "BUS", 40000, 1, 7, 95, 70, "Rapid movement of funds - pass through (business)"),
    ("TM_RPM01", "CIB", 2000000, 1, 7, 98, 50, "Rapid movement of funds - pass through (corporate)"),
    ("TM_HRC01", "ALL", 15000, 1, 30, 100, 60, "High risk jurisdiction payments"),
    ("TM_HRC01", "RET", 5000, 1, 30, 100, 60, "High risk jurisdiction payments (retail)"),
    ("TM_RND01", "ALL", 20000, 5, 30, 100, 40, "Repeated round amount transfers"),
    ("TM_DRM01", "ALL", 5000, 365, 1, 100, 50, "Dormant account reactivation"),
    ("TM_VEL01", "ALL", 10000, 1, 30, 500, 50, "Velocity spike against own history"),
    ("TM_VEL01", "CIB", 250000, 1, 30, 500, 40, "Velocity spike against own history (corporate)"),
    ("TM_PEP01", "ALL", 25000, 1, 1, 100, 70, "Large transaction of a PEP"),
    ("TM_PEP01", "WLT", 50000, 1, 1, 100, 70, "Large transaction of a PEP (wealth)"),
    ("TM_TOV01", "ALL", 10000, 1, 30, 300, 50, "Turnover inconsistent with KYC profile"),
    ("TM_CSH01", "ALL", 10000, 1, 30, 100, 50, "Cash activity for non cash-intensive customer"),
    ("TM_CSH01", "BUS", 25000, 1, 30, 100, 50, "Cash activity for non cash-intensive business"),
    ("TM_MUL01", "ALL", 2000, 5, 90, 100, 80, "Money mule fan-in on new accounts"),
    ("TM_MUL01", "RET", 2000, 5, 90, 100, 80, "Money mule fan-in on new retail accounts"),
    ("TM_GMB01", "ALL", 3000, 1, 30, 100, 40, "Gambling and crypto-asset spend"),
    ("TM_SAN01", "ALL", 0, 1, 1, 100, 100, "Sanctions screening hit"),
]
SEGMENTS = ["RET", "BUS", "CIB", "WLT"]


def rule_param(rule, seg):
    if seg not in SEGMENTS:
        return None
    sp = [r for r in RULES if r[0] == rule and r[1] == seg]
    ap = [r for r in RULES if r[0] == rule and r[1] == "ALL"]
    r = (sp or ap or [None])[0]
    if r is None:
        return None
    return dict(amt=r[2], cnt=r[3], lb=r[4], pct=r[5], w=r[6])


# ======================================================================================
# name pools (fictitious)
# ======================================================================================
FIRST = ["Oliver", "Amelia", "George", "Isla", "Harry", "Ava", "Jack", "Mia", "Noah", "Grace", "Leo", "Sophie",
         "Arthur", "Freya", "Oscar", "Lily", "Charlie", "Emily", "Thomas", "Ella", "James", "Poppy", "William",
         "Evie", "Henry", "Ruby", "Alfie", "Chloe", "Joshua", "Daisy", "Samuel", "Alice", "Daniel", "Hannah",
         "Mohammed", "Aisha", "Priya", "Arjun", "Zara", "Imran", "Kwame", "Chidi", "Ewa", "Piotr", "Ioana",
         "Andrei", "Siobhan", "Callum", "Rhys", "Megan", "Fiona", "Ewan", "Niamh", "Connor", "Bethany", "Dylan"]
LAST = ["Smith", "Jones", "Taylor", "Brown", "Williams", "Wilson", "Johnson", "Davies", "Robinson", "Wright",
        "Thompson", "Evans", "Walker", "White", "Roberts", "Green", "Hall", "Wood", "Jackson", "Clarke", "Patel",
        "Khan", "Lewis", "James", "Phillips", "Mason", "Mitchell", "Rose", "Davis", "Rodriguez", "Cox", "Alexander",
        "Begum", "Hussain", "Shah", "Okafor", "Mensah", "Kowalski", "Nowak", "Popescu", "Murphy", "Kelly",
        "MacDonald", "Campbell", "Stewart", "Hughes", "Price", "Morgan", "Fletcher", "Hargreaves", "Ashworth",
        "Pemberton", "Whitfield", "Oakley", "Thornton", "Brennan", "Lockwood", "Fairbairn", "Holloway"]
ORG_WORDS = ["Riverside", "Northern", "Summit", "Oakwood", "Pinnacle", "Harbour", "Crescent", "Meadow", "Granite",
             "Beacon", "Kestrel", "Highfield", "Silverline", "Bluebell", "Ironbridge", "Fernhill", "Westgate",
             "Elmstead", "Copperfield", "Brookside", "Lakeview", "Castlegate", "Redwood", "Foxglove"]
ORG_TRADES = {"62020": "IT Solutions", "86210": "Medical Practice", "85200": "Primary Academy",
              "70229": "Consulting", "41100": "Developments", "49410": "Haulage", "43210": "Electrical",
              "56101": "Kitchen", "56302": "Tavern", "47110": "Convenience Stores", "96020": "Hair & Beauty",
              "45112": "Motors", "47770": "Jewellers", "92000": "Bookmakers", "64999": "Capital",
              "68100": "Property", "46720": "Metals Trading", "66190": "Money Transfer", "10710": "Bakery",
              "46900": "Wholesale", "52290": "Freight Services"}
EMPLOYERS = ["Yorkshire Health Trust", "Leeds City Council", "Pennine Logistics Ltd", "Northern Rail Services",
             "Kingfisher Retail Group plc", "Brightwave Energy Ltd", "Castlegate Engineering Ltd",
             "Meridian Insurance Services", "Oakwood Care Homes Ltd", "Summit Software Ltd",
             "Highfield University", "Granite Construction plc", "Harbour Foods Ltd", "Westgate Pharma Ltd",
             "HM Revenue and Customs", "Department for Work and Pensions"]
DD_ORIGINATORS = [("AQUALINE WATER", 20, 60), ("BRIGHTWAVE ENERGY", 60, 220), ("STREAMNET BROADBAND", 25, 70),
                  ("COUNCIL TAX LEEDS CC", 110, 260), ("MERIDIAN INSURANCE", 15, 90), ("FITLIFE GYMS", 20, 55),
                  ("VOXCELL MOBILE", 10, 60), ("HOMESAFE MORTGAGES", 450, 1600), ("TVSTREAM PLUS", 8, 18),
                  ("SHIELD PET INSURANCE", 12, 45)]
MERCHANTS = {
    "5411": ["GREENLEAF GROCERS", "VALUEMART SUPERSTORE", "CORNER FRESH", "HARVEST FOODHALL"],
    "5812": ["THE COPPER KETTLE", "LA PIAZZA RISTORANTE", "SPICE ROUTE KITCHEN"],
    "5814": ["BURGER BARN", "QUICKBITE", "NOODLE STOP"], "5541": ["QUICKFUEL STATION", "MOTORWAY FUEL"],
    "5912": ["WELLCARE PHARMACY"], "5311": ["HAMPTONS DEPARTMENT STORE"], "5651": ["THREADLINE CLOTHING"],
    "5732": ["PIXELHUB ELECTRONICS"], "5942": ["PAGETURNER BOOKS"], "5999": ["ODDS AND ENDS STORE"],
    "4111": ["METROLINE TRAVEL"], "4121": ["CITYCAB RIDES"], "4511": ["SKYBRIDGE AIRWAYS"],
    "7011": ["HARBOURVIEW HOTEL"], "4814": ["VOXCELL MOBILE"], "5815": ["TUNEWAVE MUSIC"],
    "7832": ["GRAND PICTUREHOUSE"], "8999": ["LEDGERWISE ACCOUNTANTS"], "9399": ["DVLA ONLINE SERVICES"],
    "5944": ["GOLDCREST JEWELLERS"], "4829": ["SWIFTSEND MONEY TRANSFER"], "6051": ["COINVAULT EXCHANGE"],
    "7995": ["LUCKYSPIN BETTING"], "7801": ["ACEHIGH ONLINE CASINO"], "7800": ["NATIONAL LOTTERY ONLINE"],
}
EVERYDAY_MCC = ["5411"] * 8 + ["5812"] * 3 + ["5814"] * 3 + ["5541"] * 2 + ["5912", "5311", "5651", "5732",
                "5942", "5999", "4111", "4111", "4121", "4814", "5815", "7832", "4511", "7011", "9399", "7800"]
EU_MERCHANTS = [("ES", "EUR", "HOTEL PLAYA SOL"), ("FR", "EUR", "BRASSERIE DU PORT"), ("IT", "EUR", "TRATTORIA ROMA"),
                ("PT", "EUR", "FARMACIA CENTRAL"), ("US", "USD", "SUNSET DINER NYC"), ("NL", "EUR", "FIETSVERHUUR CENTRUM")]
INTL_SUPPLIERS = [("DE", "EUR", "Rheinwerk Maschinenbau GmbH", "RHWMDEFFXXX"),
                  ("NL", "EUR", "Van Dijk Agro Export BV", "VDAENL2AXXX"),
                  ("FR", "EUR", "Atelier Lumiere SARL", "ATLMFRPPXXX"),
                  ("IT", "EUR", "Ceramiche Toscane SpA", "CRTSITMMXXX"),
                  ("ES", "EUR", "Aceites del Sur SL", "ACSUESMMXXX"),
                  ("US", "USD", "Prairie Components Inc", "PRCMUS33XXX"),
                  ("CN", "USD", "Shenzhen Brightstar Electronics Co Ltd", "SZBSCNSHXXX"),
                  ("IN", "USD", "Coimbatore Textiles Pvt Ltd", "CBTXINBBXXX"),
                  ("PL", "EUR", "Baltic Timber Sp z o o", "BLTMPLPWXXX"),
                  ("IE", "EUR", "Shannon Dairy Co-operative", "SHDCIE2DXXX"),
                  ("TR", "USD", "Anatolia Textile AS", "ANTXTRISXXX"),
                  ("AE", "USD", "Gulf Horizon General Trading FZE", "GHGTAEADXXX"),
                  ("HK", "USD", "Pearl River Sourcing Ltd", "PRSLHKHHXXX"),
                  ("SG", "USD", "Straits Marine Supplies Pte Ltd", "STMSSGSGXXX"),
                  ("CH", "EUR", "Alpenhof Precision AG", "ALPHCHZZXXX")]

# sanctions pools (fictitious)
RU_FIRST = ["Arkady", "Gennady", "Vsevolod", "Yaroslav", "Rostislav", "Feliks", "Kirill", "Lev", "Matvei",
            "Stanislav", "Timofei", "Vadim", "Zakhar", "Gleb", "Lavrenty", "Yefim", "Rodion", "Svyatoslav"]
RU_PATRO = ["Viktorovich", "Gennadyevich", "Borisovich", "Lvovich", "Arkadyevich", "Feliksovich",
            "Rostislavovich", "Yefimovich", "Matveyevich", "Glebovich"]
RU_LAST = ["Zeltsky", "Vorbanov", "Krestovets", "Shalyapkin", "Dorogunov", "Ryabtsevsky", "Tulchinov",
           "Mezhakov", "Pryadkin", "Zvonarev", "Bulavintsev", "Kolchanov", "Ostapchuk", "Lysenkov",
           "Sharapovsky", "Gromtsev", "Voznyakov", "Chernavin", "Talyzin", "Burmistrov"]
IR_FIRST = ["Mahmoud Reza", "Hossein Ali", "Kamran", "Behrouz", "Farhad", "Mehrdad", "Shahram", "Davoud"]
IR_LAST = ["Khalilzadeh", "Tavakkolian", "Rostamnejad", "Ghasemipour", "Najafabadi", "Sarrafian",
           "Mirhashemi", "Bagherzadeh"]
KP_FIRST = ["Ri Chol", "Kim Song", "Pak Myong", "Jon Il", "Han Yong", "Choe Sok"]
KP_LAST = ["Hyok", "Gwang", "Su", "Nam", "Chun", "Jin"]
SY_FIRST = ["Bashir", "Nizar", "Tariq", "Wael", "Fadi", "Ghassan"]
SY_LAST = ["al-Hamdani", "Qassab", "Shalhoub", "Darwishi", "Haddadin", "Mardini"]
ENT_STEM = ["Korvex", "Tavrida", "Zaryant", "Velmora", "Arktivo", "Solvanta", "Pribrezh", "Kamtrel",
            "Ostrava Nord", "Yuzhtek", "Belovar", "Dravinsk", "Morskoy Klyuch", "Severnyi Put", "Zolotar",
            "Persiran", "Kavirgas", "Darya Noor", "Taybeh Star", "Ryongak", "Chilbo Sea", "Halabi Bros"]
ENT_KIND = ["Maritime Holdings", "Commerce Bank", "Energy Trading", "Shipping", "Metallurg", "Industrial Group",
            "Petrochemical", "Logistics", "Investment Company", "Defence Systems", "Precious Metals"]
ENT_FORM = ["LLC", "JSC", "OOO", "PJSC", "Ltd", "FZE", "Co"]
TRANSLIT = {"a": "а", "b": "б", "v": "в", "g": "г", "d": "д", "e": "е", "z": "з", "i": "и", "y": "й",
            "k": "к", "l": "л", "m": "м", "n": "н", "o": "о", "p": "п", "r": "р", "s": "с", "t": "т",
            "u": "у", "f": "ф", "h": "х", "c": "ц"}


def cyr(name):
    out, i, low = [], 0, name.lower()
    pairs = {"sh": "ш", "ch": "ч", "zh": "ж", "kh": "х", "ts": "ц", "ya": "я", "yu": "ю", "yo": "ё"}
    while i < len(low):
        two = low[i:i + 2]
        if two in pairs:
            out.append(pairs[two]); i += 2; continue
        ch = low[i]
        out.append(TRANSLIT.get(ch, ch)); i += 1
    s = "".join(out)
    return " ".join(w[:1].upper() + w[1:] for w in s.split(" "))


NOISE_WORDS = [("LTD", "LF"), ("LIMITED", "LF"), ("PLC", "LF"), ("LLP", "LF"), ("LLC", "LF"), ("INC", "LF"),
               ("CORP", "LF"), ("CORPORATION", "LF"), ("COMPANY", "LF"), ("CO", "LF"), ("GMBH", "LF"),
               ("AG", "LF"), ("SA", "LF"), ("BV", "LF"), ("SARL", "LF"), ("SPA", "LF"), ("SL", "LF"),
               ("OOO", "LF"), ("ZAO", "LF"), ("OAO", "LF"), ("JSC", "LF"), ("PJSC", "LF"), ("FZE", "LF"),
               ("FZCO", "LF"), ("PTE", "LF"), ("PVT", "LF"), ("THE", "AR"), ("AND", "AR"), ("OF", "AR"),
               ("FOR", "AR"), ("MR", "TI"), ("MRS", "TI"), ("MS", "TI"), ("MISS", "TI"), ("DR", "TI"),
               ("SIR", "TI"), ("LORD", "TI"), ("LADY", "TI"), ("PROF", "TI"), ("AL", "AR")]
NOISE = {w for w, _ in NOISE_WORDS}


def tokens(nm):
    out = []
    for t in norm(nm).split(" "):
        if len(t) >= 2 and t not in NOISE and t not in out:
            out.append(t)
    return out


# ======================================================================================
# generator
# ======================================================================================
class Gen:
    def __init__(self, a):
        self.a = a
        self.r = random.Random(a.seed)
        self.run = D.fromisoformat(a.run_date)
        self.hist_start = self.run - a.history_days * ONE
        self.out = os.path.abspath(a.out)
        self.parties, self.accts, self.rels, self.aliases = {}, {}, [], []
        self.hist, self.daily = [], []          # typed txn dicts
        self.cpty = {}                          # (key, norm) -> row
        self.next_cpty = 500000
        self.seq = Counter()
        self.scen = []                          # scenario manifest rows
        self.planted_accts = set()
        self.kyc_dq, self.ref_dq, self.dq = [], [], []
        self.fx = {}                            # (ccy, date) -> rate
        self.holidays = {}
        for y in range(1920, 2031):
            self.holidays.update(uk_bank_holidays(y))

    # ------------------------------------------------------------------ utils
    def bus_day(self, d):
        return d.weekday() < 5 and d not in self.holidays

    def prev_bus(self, d):
        while not self.bus_day(d):
            d -= ONE
        return d

    def pid(self):
        return f"PTY{len(self.parties) + 1000001:09d}"

    def new_acct_nr(self):
        return f"{self.r.randint(10000000, 99999999)}"

    def person(self):
        return f"{self.r.choice(FIRST)} {self.r.choice(LAST)}"

    # ------------------------------------------------------------------ FX
    def build_fx(self):
        for ccy, _, _, _, base in CURRENCIES:
            if base is None:
                continue
            rate = base
            d = self.hist_start - 10 * ONE
            while d <= self.run:
                if self.bus_day(d):
                    rate = rate * (1 + self.r.gauss(0, 0.0025)) if ccy != "GBP" else 1.0
                    self.fx[(ccy, d)] = round(rate, 8 if base < 10 else 6)
                d += ONE

    def rate(self, ccy, d):
        """FX_RATE_SNAPSHOT when the date matches, else latest earlier FX_RATE (dailytxn.06)."""
        if ccy == "GBP":
            return 1.0, "N"
        if (ccy, d) in self.fx:
            return self.fx[(ccy, d)], "N"
        for k in range(1, 15):
            if (ccy, d - k * ONE) in self.fx:
                return self.fx[(ccy, d - k * ONE)], "Y"
        return None, "X"

    # ------------------------------------------------------------------ KYC
    def add_party(self, seg, ptype, **kw):
        r = self.r
        pid = kw.pop("party_id", None) or self.pid()
        indiv = ptype == "I"
        sic = kw.pop("sic", None)
        if sic is None:
            if indiv:
                sic = r.choices(["99999", "99998", "99997", "99996"], [70, 8, 15, 7])[0]
            else:
                sic = r.choice([s for s in ORG_TRADES])
        if indiv:
            name = kw.pop("name", None) or self.person()
        else:
            name = kw.pop("name", None) or f"{r.choice(ORG_WORDS)} {ORG_TRADES[sic]} {r.choice(['Ltd', 'Ltd', 'Limited', 'LLP', 'plc'])}"
        onboard = kw.pop("onboard", None) or (self.run - r.randint(90, 6500) * ONE)
        pep = kw.pop("pep", None)
        if pep is None:
            pep = indiv and r.random() < (0.05 if seg == "WLT" else 0.006)
        rating = kw.pop("rating", None) or r.choices(["L", "M", "H"], [75, 20, 5])[0]
        if pep:
            rating = "H"
        exp_turn = kw.pop("exp_turnover", None)
        if exp_turn is None:
            exp_turn = {"RET": r.randint(12, 60) * 100, "WLT": r.randint(10, 60) * 1000,
                        "BUS": r.randint(20, 200) * 1000, "CIB": r.randint(5, 50) * 100000}[seg]
        nat = kw.pop("nationality", None) or (r.choices(
            ["GB", "IE", "PL", "RO", "IN", "PK", "NG", "FR", "DE", "US", "CN", "AE", "ES", "IT"],
            [85, 2, 2, 1.5, 2, 1.5, 1, 1, 1, 0.5, 0.5, 0.5, 0.5, 0.5])[0] if indiv else None)
        res = kw.pop("residence", None) or ("GB" if r.random() < 0.97 or not indiv else r.choice(["IE", "ES", "AE", "FR"]))
        review_m = {"L": 36, "M": 24, "H": 12}[rating]
        due = onboard
        while due <= self.run - 60 * ONE:
            due = D(due.year + review_m // 12, due.month, min(due.day, 28)) if review_m % 12 == 0 else due + 365 * ONE
        overdue = kw.pop("overdue", None)
        if overdue is None:
            overdue = r.random() < 0.03
        if overdue:
            due = self.run - r.randint(10, 200) * ONE
        p = dict(PARTY_ID=pid, PARTY_TYP_CD=ptype, FULL_NM=name,
                 BIRTH_DT=kw.pop("birth", None) or (D(r.randint(1945, 2004), r.randint(1, 12), r.randint(1, 28)) if indiv else None),
                 NATIONALITY_CD=nat, RESIDENCE_CTRY_CD=res, SIC_CD=sic, PEP_IND="Y" if pep else "N",
                 PEP_TYP_CD=(kw.pop("pep_typ", None) or r.choice(["DO", "FO", "IO", "RC"])) if pep else "",
                 ADV_MEDIA_IND=kw.pop("adv_media", None) or ("Y" if r.random() < 0.005 else "N"),
                 SEGMENT_CD=seg, ONBOARD_DT=onboard, KYC_REVIEW_DUE_DT=due,
                 KYC_STATUS_CD=kw.pop("kyc_status", None) or r.choices(["VE", "PE", "EX"], [95, 3, 2])[0],
                 CDD_LEVEL_CD=kw.pop("cdd", None) or ("EDD" if rating == "H" or pep else r.choice(["CDD", "CDD", "SDD"])),
                 RISK_RATING_CD=rating, RM_ID=f"RM{r.randint(1, 400):06d}" if seg in ("WLT", "CIB", "BUS") else "",
                 POSTCODE=r.choice(POSTCODES),
                 CO_HOUSE_NR=kw.pop("co_house", None) if "co_house" in kw else ("" if indiv else f"{r.randint(1000000, 15999999):08d}"),
                 INCORP_CTRY_CD="" if indiv else "GB", EXP_MTH_TURNOVER_AMT=exp_turn,
                 SRC_OF_FUNDS_CD=kw.pop("sof", None) or (r.choice(["SA", "SA", "SA", "IN", "PE", "IV"]) if indiv else "BU"),
                 CLOSED_IND="N")
        p["RISK_RATING_CD_EFF"] = "H" if pep else rating          # kycref.55 forces PEP -> H / EDD
        assert not kw, kw
        self.parties[pid] = p
        return p

    def add_acct(self, party, prdt, **kw):
        r = self.r
        sort = kw.pop("sort", None) or r.choice(OWN_SORTS)
        nr = kw.pop("acct_nr", None) or self.new_acct_nr()
        aid = sort + nr
        while aid in self.accts:
            nr = self.new_acct_nr(); aid = sort + nr
        opened = kw.pop("open_dt", None) or max(party["ONBOARD_DT"], self.run - r.randint(40, 6000) * ONE)
        a = dict(ACCT_ID=aid, SORT_CD=sort, ACCT_NR=nr, PRDT_CD=prdt, CCY_CD=kw.pop("ccy", "GBP"),
                 OPEN_DT=opened, CLOSE_DT=None, ACCT_STATUS_CD=kw.pop("status", "A"),
                 PRIMARY_PARTY_ID=party["PARTY_ID"],
                 OD_LIMIT_AMT=kw.pop("od", None) or (r.choice([0, 250, 500, 1000, 1500]) if PRDT[prdt][2] == "CURR" else 0),
                 LAST_CUST_ACTV_DT=kw.pop("last_actv", None) or (self.run - ONE),
                 OPEN_CHNL_CD=kw.pop("open_chnl", None) or r.choices(["BRN", "OLB", "MOB", "RMG"], [40, 25, 30, 5])[0],
                 SEGMENT_CD=PRDT[prdt][3], profile=kw.pop("profile", "std"), favs=[])
        assert not kw, kw
        self.accts[aid] = a
        self.rels.append(dict(PARTY_ID=party["PARTY_ID"], ACCT_ID=aid, ROLE_CD="PH", START_DT=opened,
                              END_DT=None, OWNERSHIP_PCT=100.0))
        return a

    def build_kyc(self):
        r = self.r
        n = self.a.parties
        mix = (["RET"] * 70) + (["BUS"] * 18) + (["CIB"] * 4) + (["WLT"] * 8)
        for _ in range(n):
            seg = r.choice(mix)
            p = self.add_party(seg, "I" if seg in ("RET", "WLT") else "O")
            if seg == "RET":
                main = self.add_acct(p, "RETBAS" if r.random() < 0.06 else "RETCUR")
                if r.random() < 0.30:
                    self.add_acct(p, r.choice(["RETSAV", "RETISA"]), open_dt=main["OPEN_DT"] + r.randint(0, 400) * ONE)
            elif seg == "WLT":
                self.add_acct(p, "WLTCUR")
                if r.random() < 0.4:
                    self.add_acct(p, "WLTINV")
            elif seg == "BUS":
                self.add_acct(p, "BUSCUR")
                if r.random() < 0.2:
                    self.add_acct(p, "BUSSAV")
            else:
                self.add_acct(p, "CIBCUR")
                if r.random() < 0.3:
                    self.add_acct(p, "CIBTRD", ccy=r.choice(["USD", "EUR"]))
        for a in self.accts.values():
            if a["OPEN_DT"] > self.run - ONE:
                a["OPEN_DT"] = self.run - 30 * ONE
        # joint holders / signatories
        rets = [p for p in self.parties.values() if p["SEGMENT_CD"] == "RET"]
        for a in list(self.accts.values()):
            if a["PRDT_CD"] == "RETCUR" and r.random() < 0.10:
                jh = r.choice(rets)
                if jh["PARTY_ID"] != a["PRIMARY_PARTY_ID"]:
                    self.rels.append(dict(PARTY_ID=jh["PARTY_ID"], ACCT_ID=a["ACCT_ID"], ROLE_CD="JH",
                                          START_DT=a["OPEN_DT"], END_DT=None, OWNERSHIP_PCT=50.0))
                    for rel in self.rels:
                        if rel["ACCT_ID"] == a["ACCT_ID"] and rel["ROLE_CD"] == "PH":
                            rel["OWNERSHIP_PCT"] = 50.0
            if a["SEGMENT_CD"] in ("BUS", "CIB") and r.random() < 0.35:
                sg = r.choice(rets)
                self.rels.append(dict(PARTY_ID=sg["PARTY_ID"], ACCT_ID=a["ACCT_ID"],
                                      ROLE_CD=r.choice(["SG", "BO"]), START_DT=a["OPEN_DT"], END_DT=None,
                                      OWNERSHIP_PCT=r.choice([25.0, 33.33, 50.0, 100.0])))
        # dormant accounts (no activity, old last activity)
        for a in r.sample([a for a in self.accts.values() if a["PRDT_CD"] in ("RETCUR", "RETSAV")], 15):
            a["ACCT_STATUS_CD"] = "D"
            a["LAST_CUST_ACTV_DT"] = self.run - r.randint(400, 1500) * ONE
            a["profile"] = "dormant"
        # aliases
        for p in r.sample([p for p in self.parties.values() if p["PARTY_TYP_CD"] == "O"], 25):
            self.aliases.append(dict(PARTY_ID=p["PARTY_ID"], ALIAS_SEQ_NR=1,
                                     ALIAS_NM=p["FULL_NM"].rsplit(" ", 1)[0].upper() + " TRADING", ALIAS_TYP_CD="TN"))
        for p in r.sample([p for p in self.parties.values() if p["PARTY_TYP_CD"] == "I"], 25):
            self.aliases.append(dict(PARTY_ID=p["PARTY_ID"], ALIAS_SEQ_NR=1,
                                     ALIAS_NM=p["FULL_NM"].split(" ")[0] + " " + r.choice(LAST), ALIAS_TYP_CD="PN"))

    # ------------------------------------------------------------------ counterparty pools
    def build_pools(self):
        r = self.r
        self.pool_people = []
        for _ in range(700):
            pb = r.choice(PEER_BANKS)
            sort = f"99{r.randint(20, 89)}{r.randint(10, 99)}"
            self.pool_people.append(dict(nm=self.person(), sort=sort, acct=self.new_acct_nr(), bic=pb[1] + "XXX",
                                         ctry="GB", bank="GB"))
        self.pool_biz = []
        for _ in range(200):
            sic = r.choice(list(ORG_TRADES))
            self.pool_biz.append(dict(nm=f"{r.choice(ORG_WORDS)} {ORG_TRADES[sic]} Ltd",
                                      sort=f"99{r.randint(20, 89)}{r.randint(10, 99)}", acct=self.new_acct_nr(),
                                      bic="", ctry="GB", bank="GB"))
        self.pool_employers = [dict(nm=e, sort=f"99{r.randint(20, 89)}{r.randint(10, 99)}", acct=self.new_acct_nr(),
                                    bic="", ctry="GB", bank="GB") for e in EMPLOYERS]
        self.pool_intl = []
        for c, ccy, nm, bic in INTL_SUPPLIERS:
            self.pool_intl.append(dict(nm=nm, iban=self.iban(c), bic=bic, ctry=c, bank=c, ccy=ccy))

    def iban(self, c):
        ln = {"DE": 22, "NL": 18, "FR": 27, "IT": 27, "ES": 24, "PL": 28, "IE": 22, "CH": 21, "TR": 26,
              "AE": 23, "CY": 28, "RU": 33, "NG": 20, "KP": 20}.get(c, 0)
        if ln == 0:
            return ""
        body = "".join(str(self.r.randint(0, 9)) for _ in range(ln - 4))
        return f"{c}{self.r.randint(10, 99)}{body}"

    # ------------------------------------------------------------------ transactions
    def txn(self, acct, d, typ, amt, **kw):
        """Create a typed transaction (raw field names of DLYTXN_LOAD)."""
        r = self.r
        t = TT[typ]
        sup = kw.pop("supplier", t[6])
        self.seq[(sup, d)] += 1
        hh = kw.pop("hour", None)
        if hh is None:
            hh = r.randint(0, 23) if typ in ("CRDP", "CRDR", "ATMW", "FPSI", "FPSO") else r.randint(7, 18)
        tms = dt.datetime(d.year, d.month, d.day, hh, r.randint(0, 59), r.randint(0, 59))
        chnl = kw.pop("chnl", None) or (t[7] if typ != "FPSO" else r.choice(["MOB", "MOB", "OLB", "API"]))
        ccy = kw.pop("ccy", acct["CCY_CD"] if acct else "GBP")
        x = dict(SUPPLIER_CD=sup, FILE_SEQ_NR=0, TXN_REF=kw.pop("ref", None) or f"{sup}{d:%y%m%d}{self.seq[(sup, d)]:09d}",
                 TXN_SEQ_NR=1, ACCT_ID=acct["ACCT_ID"] if acct else kw.get("acct_id"),
                 SORT_CD=acct["SORT_CD"] if acct else kw.get("acct_id", "")[:6],
                 ACCT_NR=acct["ACCT_NR"] if acct else kw.get("acct_id", "")[6:], TXN_TYP_CD=typ, CHNL_CD=chnl,
                 DR_CR_IND=kw.pop("drcr", t[3]), TXN_AMT=round(amt, 2), TXN_CCY=ccy,
                 ORIG_AMT=round(kw.pop("orig_amt", amt), 2), ORIG_CCY=kw.pop("orig_ccy", ccy), BOOKING_DT=d,
                 VALUE_DT=kw.pop("value_dt", d), TXN_TMS=tms, NARRATIVE=kw.pop("narr", t[1].upper()),
                 CPTY_NM="", CPTY_SORT_CD="", CPTY_ACCT_NR="", CPTY_IBAN="", CPTY_BIC="", CPTY_BANK_CTRY="",
                 CPTY_CTRY="", ORDERING_CUST_NM="", BENEF_CUST_NM="", PAYMENT_REF="", E2E_ID="", UETR="",
                 SWIFT_MSG_TYP="", CHARGE_BEARER="", INTERMED_BIC="", MCC="", MERCHANT_NM="", MERCHANT_CTRY="",
                 MERCHANT_ID="", TERMINAL_ID="", ATM_ID="", CARD_TOKEN="", POS_ENTRY_MODE="", CARD_PRESENT_IND="",
                 BRANCH_SORT_CD="", TELLER_ID="", CASH_IND=t[4], CHEQUE_NR="", DEVICE_ID="", IP_ADDR="",
                 IP_CTRY="", SESSION_ID="", AUTH_METHOD="", COP_RESULT="", APP_FRAUD_IND="N",
                 RETURN_REASON_CD="", REVERSAL_IND="N", ORIG_TXN_REF="", BAL_AFTER=round(r.uniform(-200, 25000), 2),
                 TXN_STATUS=kw.pop("status", "BK"), FEE_AMT=0.0, PURPOSE_CD="", BATCH_ID="", EXTRACT_DT=d)
        cp = kw.pop("cpty", None)
        if cp:
            x["CPTY_NM"] = cp.get("nm", "")
            x["CPTY_SORT_CD"] = cp.get("sort", "")
            x["CPTY_ACCT_NR"] = cp.get("acct", "")
            x["CPTY_IBAN"] = cp.get("iban", "")
            x["CPTY_BIC"] = cp.get("bic", "")
            x["CPTY_BANK_CTRY"] = cp.get("bank", "")
            x["CPTY_CTRY"] = cp.get("ctry", "")
        if t[2] in ("FPS", "BACS", "CHAP", "SWFT"):
            x["PAYMENT_REF"] = kw.pop("pref", None) or r.choice(["INVOICE ", "REF ", "PAYMENT ", ""]) + str(r.randint(1000, 99999))
            x["E2E_ID"] = f"E2E{d:%y%m%d}{r.randint(10 ** 15, 10 ** 16 - 1)}"
            x["PURPOSE_CD"] = kw.pop("purpose", None) or r.choice(["OTHR", "SUPP", "GDDS", "SALA", "TRAD"]) if t[2] != "BACS" else "SALA"
        if t[2] in ("CHAP", "SWFT"):
            x["UETR"] = str(uuid.UUID(int=r.getrandbits(128)))
            x["SWIFT_MSG_TYP"] = "103"
            x["CHARGE_BEARER"] = r.choice(["SHA", "SHA", "OUR", "BEN"])
            x["ORDERING_CUST_NM"] = kw.pop("ordering", None) or (self.parties[acct["PRIMARY_PARTY_ID"]]["FULL_NM"].upper() if t[3] == "D" else x["CPTY_NM"].upper())
            x["BENEF_CUST_NM"] = kw.pop("benef", None) or (x["CPTY_NM"].upper() if t[3] == "D" else self.parties[acct["PRIMARY_PARTY_ID"]]["FULL_NM"].upper())
            x["INTERMED_BIC"] = kw.pop("intermed", "")
        if typ in ("FPSO",):
            x["COP_RESULT"] = kw.pop("cop", None) or r.choices(["MA", "CM", "NM", "NA"], [88, 6, 3, 3])[0]
        if CHNL_DIGITAL.get(chnl) == "Y":
            x["DEVICE_ID"] = f"dev-{r.getrandbits(64):016x}"
            x["IP_ADDR"] = kw.pop("ip", None) or f"81.{r.randint(0, 255)}.{r.randint(0, 255)}.{r.randint(1, 254)}"
            x["IP_CTRY"] = kw.pop("ip_ctry", "GB")
            x["SESSION_ID"] = str(uuid.UUID(int=r.getrandbits(128)))
            x["AUTH_METHOD"] = r.choice(["BI", "BI", "PW", "OT"])
        if t[2] == "CARD" or typ == "ATMW":
            x["CARD_TOKEN"] = f"4{r.randint(10000, 99999)}******{r.randint(1000, 9999)}"
        if t[2] == "CARD":
            mcc = kw.pop("mcc", None) or r.choice(EVERYDAY_MCC)
            x["MCC"] = mcc
            mctry = kw.pop("mctry", "GB")
            x["MERCHANT_NM"] = kw.pop("merchant", None) or r.choice(MERCHANTS.get(mcc, ["GENERAL MERCHANT"]))
            x["MERCHANT_CTRY"] = mctry
            x["MERCHANT_ID"] = f"M{r.randint(10 ** 13, 10 ** 14 - 1)}"
            x["TERMINAL_ID"] = f"T{r.randint(1000000, 9999999)}"
            ecom = mcc in ("5815", "7801", "6051", "4511") or r.random() < 0.25
            x["POS_ENTRY_MODE"] = "81" if ecom else r.choice(["05", "07"])
            x["CARD_PRESENT_IND"] = "N" if ecom else "Y"
            x["AUTH_METHOD"] = "3D" if ecom else r.choice(["CP", "CL", "CL"])
            x["NARRATIVE"] = x["MERCHANT_NM"]
        if typ == "ATMW":
            x["ATM_ID"] = f"ATM{r.randint(10000, 99999)}"
            x["MCC"] = "6011"
            x["AUTH_METHOD"] = "CP"
        if typ in ("CSHD", "CSHW", "CHQD"):
            x["BRANCH_SORT_CD"] = kw.pop("branch", None) or acct["SORT_CD"]
            x["TELLER_ID"] = f"TLR{r.randint(10000, 99999)}"
            if typ == "CHQD":
                x["CHEQUE_NR"] = f"{r.randint(100000, 999999)}"
        if typ == "FEEC":
            x["FEE_AMT"] = round(amt, 2)
        x["BATCH_ID"] = f"{sup}{d:%Y%m%d}B{r.randint(1, 9):02d}"
        x.update({k.upper(): v for k, v in kw.items() if k != "acct_id"})
        return x

    def activity(self, a, d, sink):
        """Background behaviour of an account for one day."""
        r = self.r
        if a["profile"] in ("dormant", "quiet") or d < a["OPEN_DT"]:
            return
        p = self.parties[a["PRIMARY_PARTY_ID"]]
        prd, seg = a["PRDT_CD"], a["SEGMENT_CD"]
        bd = self.bus_day(d)
        if not a["favs"]:
            a["favs"] = r.sample(self.pool_people, 6) + r.sample(self.pool_biz, 3)
            a["employer"] = r.choice(self.pool_employers)
            a["salary_day"] = r.choice([1, 15, 20, 25, 28])
            a["dds"] = r.sample(DD_ORIGINATORS, r.randint(3, 6))
            a["dd_days"] = [r.randint(1, 28) for _ in a["dds"]]
            a["savings"] = next((x for x in self.accts.values() if x["PRIMARY_PARTY_ID"] == p["PARTY_ID"]
                                 and x["ACCT_ID"] != a["ACCT_ID"]), None)
        turn = float(p["EXP_MTH_TURNOVER_AMT"])

        def pay_day(day_of_month):
            target = D(d.year, d.month, min(day_of_month, 28))
            return self.prev_bus(target) == d

        def ln(mean, sd=0.8):
            return max(1.0, round(math.exp(math.log(mean) + r.gauss(0, sd)), 2))

        if prd in ("RETCUR", "RETBAS", "WLTCUR"):
            if bd and pay_day(a["salary_day"]) and p["SIC_CD"] != "99998":
                payer = a["employer"] if p["SIC_CD"] != "99997" else dict(nm="Department for Work and Pensions", sort="992011", acct="10000001", ctry="GB", bank="GB")
                sink.append(self.txn(a, d, "BACC", round(turn * r.uniform(0.75, 0.95), 2), cpty=payer,
                                     narr="SALARY" if p["SIC_CD"] != "99997" else "PENSION"))
            if bd:
                for (nm, lo, hi), dd in zip(a["dds"], a["dd_days"]):
                    if pay_day(dd):
                        sink.append(self.txn(a, d, "DDBT", round(r.uniform(lo, hi), 2), cpty=dict(nm=nm), narr=nm))
            for _ in range(self.poisson(0.55 if seg == "RET" else 0.8)):
                if r.random() < 0.04:
                    c, ccy, m = r.choice(EU_MERCHANTS)
                    g = ln(45)
                    rt = self.fx.get((ccy, self.prev_bus(d)), 1.17)
                    sink.append(self.txn(a, d, "CRDP", g, mcc="5812", mctry=c, merchant=m, orig_amt=g * rt, orig_ccy=ccy))
                else:
                    sink.append(self.txn(a, d, "CRDP", ln(22 if seg == "RET" else 60)))
            if r.random() < 0.01:
                sink.append(self.txn(a, d, "CRDR", ln(30)))
            if r.random() < 0.07:
                sink.append(self.txn(a, d, "ATMW", float(r.choice([20, 30, 40, 50, 100, 150, 200, 250]))))
            if r.random() < 0.08:
                cp = r.choice(a["favs"])
                sink.append(self.txn(a, d, "FPSO", ln(120 if seg == "RET" else 900), cpty=cp))
            if r.random() < 0.04:
                cp = r.choice(a["favs"])
                sink.append(self.txn(a, d, "FPSI", ln(90 if seg == "RET" else 700), cpty=cp))
            if bd and a["savings"] and d.day == 2:
                amt = ln(150 if seg == "RET" else 2000, 0.5)
                sv = a["savings"]
                sink.append(self.txn(a, d, "ITRO", amt, cpty=dict(nm=p["FULL_NM"], sort=sv["SORT_CD"], acct=sv["ACCT_NR"], ctry="GB", bank="GB"), narr="TRANSFER TO SAVINGS"))
                sink.append(self.txn(sv, d, "ITRI", amt, cpty=dict(nm=p["FULL_NM"], sort=a["SORT_CD"], acct=a["ACCT_NR"], ctry="GB", bank="GB"), narr="TRANSFER FROM CURRENT"))
            if seg == "WLT" and r.random() < 0.01:
                sink.append(self.txn(a, d, "CHPO", ln(18000, 0.6), cpty=r.choice(self.pool_biz), chnl="RMG"))
            if p["SIC_CD"] == "99996" and r.random() < 0.05:
                sink.append(self.txn(a, d, "CSHD", ln(250, 0.6), chnl="BRN"))
            if bd and d.day == 1 and prd != "RETBAS":
                sink.append(self.txn(a, d, "FEEC", 3.00 if seg == "RET" else 25.00))
        elif prd in ("RETSAV", "RETISA", "BUSSAV", "WLTINV"):
            if bd and d.day == 1:
                sink.append(self.txn(a, d, "INTC", round(r.uniform(0.5, 60 if prd != "WLTINV" else 400), 2)))
            if prd == "WLTINV" and r.random() < 0.01:
                sink.append(self.txn(a, d, "CHPI", ln(25000, 0.6), cpty=r.choice(self.pool_biz)))
        elif prd == "BUSCUR":
            scale = turn / 30.0
            n_in = self.poisson(1.1 if bd else 0.2)
            for _ in range(n_in):
                sink.append(self.txn(a, d, "FPSI", ln(max(scale / 1.2, 50), 0.9), cpty=r.choice(self.pool_biz + a["favs"])))
            for _ in range(self.poisson(0.8 if bd else 0.1)):
                sink.append(self.txn(a, d, "FPSO", ln(max(scale / 1.6, 40), 0.9), cpty=r.choice(self.pool_biz)))
            if bd and pay_day(28):
                sink.append(self.txn(a, d, "BACD", round(turn * r.uniform(0.25, 0.4), 2), cpty=dict(nm="PAYROLL BULK"), narr="PAYROLL"))
            if SIC[p["SIC_CD"]][3] == "Y" and bd and r.random() < 0.45:
                sink.append(self.txn(a, d, "CSHD", ln(max(scale / 3, 150), 0.6), chnl="BRN"))
            if r.random() < 0.25:
                sink.append(self.txn(a, d, "CRDP", ln(80)))
            if bd and r.random() < 0.02:
                s = r.choice(self.pool_intl)
                sink.append(self.txn(a, d, "SWFO", ln(6000, 0.7), cpty=s, orig_ccy=s["ccy"]))
            if bd and r.random() < 0.015:
                sink.append(self.txn(a, d, "CHPO", ln(30000, 0.5), cpty=r.choice(self.pool_biz)))
            if bd and d.day == 1:
                sink.append(self.txn(a, d, "FEEC", 12.50))
        elif prd in ("CIBCUR", "CIBTRD"):
            scale = turn / 30.0
            ccy = a["CCY_CD"]
            for _ in range(self.poisson(0.7 if bd else 0)):
                s = r.choice(self.pool_intl)
                sink.append(self.txn(a, d, r.choice(["SWFI", "SWFO"]), ln(scale / 4, 0.8), cpty=s, ccy=ccy))
            for _ in range(self.poisson(0.6 if bd else 0)):
                sink.append(self.txn(a, d, r.choice(["CHPI", "CHPO"]), ln(scale / 3, 0.7), cpty=r.choice(self.pool_biz), ccy="GBP" if ccy == "GBP" else ccy))
            for _ in range(self.poisson(2.0 if bd and prd == "CIBCUR" else 0)):
                sink.append(self.txn(a, d, r.choice(["FPSI", "FPSO"]), ln(scale / 20, 0.8), cpty=r.choice(self.pool_biz)))
            if bd and prd == "CIBCUR" and pay_day(25):
                sink.append(self.txn(a, d, "BACD", round(turn * 0.3, 2), cpty=dict(nm="PAYROLL BULK"), narr="PAYROLL"))

    def poisson(self, lam):
        if lam <= 0:
            return 0
        L, k, p = math.exp(-lam), 0, 1.0
        while True:
            p *= self.r.random()
            if p <= L:
                return k
            k += 1

    # ------------------------------------------------------------------ planted scenarios
    def plant(self):
        r, R = self.r, self.run
        S = self.scen
        H, Dy = self.hist, self.daily

        def sink(d):
            return Dy if d == R else H

        def scen(sid, rules, party, acct, desc):
            S.append(dict(SCENARIO_ID=sid, EXPECTED_RULES=rules, PARTY_ID=party["PARTY_ID"],
                          PARTY_NM=party["FULL_NM"], SEGMENT_CD=party["SEGMENT_CD"],
                          ACCT_ID=acct["ACCT_ID"] if acct else "", DESCRIPTION=desc))
            if acct:
                self.planted_accts.add(acct["ACCT_ID"])

        # S01 structuring (+ cash for non cash-intensive)
        p = self.add_party("RET", "I", name="Marcus Fenwick", sic="62020", rating="L", overdue=False, pep=False)
        a = self.add_acct(p, "RETCUR", open_dt=R - 2100 * ONE, profile="quiet")
        for k, amt in ((5, 9400.00), (3, 9650.00), (1, 9200.00), (0, 9800.00)):
            d = R - k * ONE
            sink(d).append(self.txn(a, d, "CSHD", amt, chnl="BRN", branch=r.choice(OWN_SORTS), narr="CASH DEPOSIT"))
        scen("S01_STRUCTURING", "TM_STR01;TM_CSH01;TM_TOV01", p, a,
             "Four branch cash deposits of GBP 9,200-9,800 in 6 days at different branches (just below GBP 10k); also far above declared turnover")

        # S02 rapid movement / pass-through (business)
        p = self.add_party("BUS", "O", name="Northbridge Trade Links Ltd", sic="46900", exp_turnover=60000,
                           overdue=False, rating="M")
        a = self.add_acct(p, "BUSCUR", open_dt=R - 700 * ONE, profile="quiet")
        for d, ins, outs in ((R - ONE, [14000, 12500, 13500], [("FPSO", 38000.0, None)]),
                             (R, [16000, 14000], [("SWFO", 29000.0, "AE")])):
            for amt in ins:
                sink(d).append(self.txn(a, d, "FPSI", float(amt) + r.randint(1, 99) / 100, cpty=r.choice(self.pool_biz)))
            for typ, amt, c in outs:
                cp = r.choice(self.pool_biz) if c is None else dict(nm="Gulf Horizon General Trading FZE", iban=self.iban("AE"), bic="GHGTAEADXXX", ctry="AE", bank="AE", ccy="USD")
                sink(d).append(self.txn(a, d, typ, amt + 0.37, cpty=cp, orig_ccy="USD" if c else "GBP"))
        scen("S02_RAPID_MOVEMENT", "TM_RPM01", p, a,
             "GBP 70k received from 5 payers over 2 days, ~96% sent straight on (incl. SWIFT to UAE)")

        # S03 high risk jurisdiction (retail SWIFT to Nigeria)
        p = self.add_party("RET", "I", name="Grace Adebayo-Holt", nationality="GB", rating="M", overdue=False, pep=False)
        a = self.add_acct(p, "RETCUR", open_dt=R - 1500 * ONE)
        for k, amt in ((10, 2500.00), (0, 3800.00)):
            d = R - k * ONE
            sink(d).append(self.txn(a, d, "SWFO", amt + 0.55, cpty=dict(nm="Chukwuma Eze", iban=self.iban("NG"), bic="LGSBNGLAXXX", ctry="NG", bank="NG"), orig_ccy="NGN", orig_amt=amt * 1950, chnl="OLB"))
        scen("S03_HIGH_RISK_JURISDICTION", "TM_HRC01", p, a, "Two SWIFT payments to Nigeria (FATF grey list), GBP 6.3k in 30 days")

        # S04 round amounts (business)
        p = self.add_party("BUS", "O", name="Kestrel Property Developments Ltd", sic="41100", exp_turnover=150000, overdue=False, rating="M")
        a = self.add_acct(p, "BUSCUR", open_dt=R - 1200 * ONE)
        for k, amt in ((25, 5000.0), (18, 5000.0), (11, 5000.0), (4, 5000.0), (0, 10000.0)):
            d = self.prev_bus(R - k * ONE)
            sink(d).append(self.txn(a, d, "FPSO", amt, cpty=dict(nm="Lockwood Investments", sort="992455", acct="40112233", ctry="GB", bank="GB"), narr="LOAN REPAYMENT"))
        scen("S04_ROUND_AMOUNTS", "TM_RND01", p, a, "Five exact GBP 5k/10k transfers to the same payee within 30 days")

        # S05 dormant reactivation
        p = self.add_party("RET", "I", name="Harold Pemberton", sic="99997", rating="L", overdue=False, pep=False)
        a = self.add_acct(p, "RETSAV", open_dt=R - 4000 * ONE, status="D", last_actv=R - 480 * ONE, profile="dormant")
        Dy.append(self.txn(a, R, "FPSI", 18000.00, cpty=dict(nm="Unity Crest Holdings", sort="992870", acct="77665544", ctry="GB", bank="GB"), chnl="BAT"))
        Dy.append(self.txn(a, R, "FPSO", 17500.00, cpty=dict(nm="Ewa Nowak", sort="992311", acct="12121212", ctry="GB", bank="GB"), chnl="TEL"))
        scen("S05_DORMANT_REACTIVATION", "TM_DRM01;TM_RPM01;TM_TOV01", p, a,
             "Savings account dormant for 480 days receives GBP 18k and pays GBP 17.5k out the same day")

        # S06 velocity spike
        p = self.add_party("RET", "I", name="Sophie Ashworth", sic="99999", exp_turnover=8000, rating="L", overdue=False, pep=False)
        a = self.add_acct(p, "RETCUR", open_dt=R - 2500 * ONE, profile="quiet")
        d = self.hist_start
        while d <= R:
            if self.bus_day(d) and self.prev_bus(D(d.year, d.month, 25)) == d:
                sink(d).append(self.txn(a, d, "BACC", 2600.00, cpty=self.pool_employers[0], narr="SALARY"))
            d += ONE
        for k in (26, 21, 15, 9, 4, 0):
            dd = R - k * ONE
            sink(dd).append(self.txn(a, dd, "FPSI", 3000.00 + r.randint(0, 900) + 0.25, cpty=r.choice(self.pool_people)))
        scen("S06_VELOCITY_SPIKE", "TM_VEL01", p, a, "30-day credits ~8x the average month of the prior 90 days")

        # S07 PEP large transaction (wealth, foreign PEP) + KYC DQ 102 (PEP without EDD)
        p = self.add_party("WLT", "I", name="Viktor Alder-Moss", nationality="GB", pep=True, pep_typ="FO", cdd="CDD", overdue=False, exp_turnover=40000)
        a = self.add_acct(p, "WLTCUR", open_dt=R - 900 * ONE)
        Dy.append(self.txn(a, R, "CHPO", 150000.00, cpty=dict(nm="Harrington Conveyancing LLP", sort="992600", acct="55443322", ctry="GB", bank="GB"), chnl="RMG", narr="PROPERTY PURCHASE"))
        scen("S07_PEP_LARGE_TXN", "TM_PEP01", p, a, "Foreign PEP sends GBP 150k CHAPS (also KYC DQ 102: PEP delivered with CDD, forced to EDD)")
        self.kyc_dq.append(dict(ERR_NR=102, KEY=p["PARTY_ID"], DESCRIPTION="PEP delivered with CDD_LEVEL_CD CDD"))

        # S08 turnover inconsistent with KYC (+ velocity)
        p = self.add_party("BUS", "O", name="Fernhill Hair & Beauty Ltd", sic="96020", exp_turnover=5000, overdue=False, rating="L")
        a = self.add_acct(p, "BUSCUR", open_dt=R - 800 * ONE, profile="quiet")
        d = self.hist_start
        while d <= R - 31 * ONE:
            if self.bus_day(d) and r.random() < 0.25:
                sink(d).append(self.txn(a, d, "FPSI", round(r.uniform(150, 420), 2), cpty=r.choice(self.pool_people)))
            d += ONE
        for k in (27, 23, 19, 15, 11, 7, 3, 0):
            dd = R - k * ONE
            sink(dd).append(self.txn(a, dd, "FPSI", 5000.00 + r.randint(0, 300) + 0.10, cpty=r.choice(self.pool_biz), narr="CONSULTANCY FEES"))
        scen("S08_TURNOVER_MISMATCH", "TM_TOV01;TM_VEL01", p, a,
             "Declared GBP 5k monthly turnover, ~GBP 41k credited in 30 days")

        # S09 cash for non cash-intensive customer
        p = self.add_party("RET", "I", name="Dr Aisha Rahman", sic="86210", exp_turnover=9000, rating="L", overdue=False, pep=False)
        a = self.add_acct(p, "RETCUR", open_dt=R - 3000 * ONE, profile="quiet")
        for k, amt in ((20, 4000.0), (12, 4200.0), (0, 4100.0)):
            d = self.prev_bus(R - k * ONE)
            sink(d).append(self.txn(a, d, "CSHD", amt + 0.50, chnl="BRN"))
        scen("S09_CASH_NON_INTENSIVE", "TM_CSH01", p, a, "GP (not cash intensive) pays in GBP 12.3k cash in 30 days")

        # S10 money mule fan-in
        p = self.add_party("RET", "I", name="Tyler Brennan", sic="99998", birth=D(2005, 3, 14), exp_turnover=1200,
                           onboard=R - 20 * ONE, rating="L", overdue=False, pep=False)
        a = self.add_acct(p, "RETCUR", open_dt=R - 20 * ONE, open_chnl="MOB", profile="quiet")
        payers = r.sample(self.pool_people, 8)
        for i, cp in enumerate(payers):
            d = R - (2 - i % 3) * ONE
            sink(d).append(self.txn(a, d, "FPSI", round(r.uniform(450, 950), 2), cpty=cp, narr=r.choice(["RENT", "FOR TICKETS", "THANKS", "CAR PART"])))
        Dy.append(self.txn(a, R, "FPSO", 5200.00, cpty=dict(nm="Jordan Kellet", sort="992777", acct="66778899", ctry="GB", bank="GB"), cop="NM"))
        scen("S10_MONEY_MULE", "TM_MUL01", p, a, "Account opened 20 days ago via app receives from 8 different payers in 3 days, then forwards GBP 5.2k (CoP no-match)")

        # S11 gambling / crypto
        p = self.add_party("RET", "I", name="Liam Holloway", sic="99999", rating="L", overdue=False, pep=False)
        a = self.add_acct(p, "RETCUR", open_dt=R - 1800 * ONE)
        for k in (28, 24, 19, 15, 10, 6, 2, 0):
            d = R - k * ONE
            mcc = "7995" if k % 2 == 0 else "6051"
            sink(d).append(self.txn(a, d, "CRDP", round(r.uniform(420, 620), 2), mcc=mcc))
        scen("S11_GAMBLING_CRYPTO", "TM_GMB01", p, a, "Eight card payments to betting and crypto exchange merchants, ~GBP 4.2k in 30 days")

        # S17 alert suppression: same pattern as S04, but an open alert for the same rule exists from 12 days ago
        p = self.add_party("BUS", "O", name="Silverline Car Sales Ltd", sic="45112", exp_turnover=200000, overdue=False, rating="M")
        a = self.add_acct(p, "BUSCUR", open_dt=R - 900 * ONE)
        for k, amt in ((27, 4000.0), (20, 6000.0), (13, 4000.0), (6, 5000.0), (0, 8000.0)):
            d = self.prev_bus(R - k * ONE)
            sink(d).append(self.txn(a, d, "FPSO", amt, cpty=dict(nm="Ashworth Auto Finance", sort="992455", acct="40998877", ctry="GB", bank="GB"), narr="STOCK FUNDING"))
        scen("S17_ALERT_SUPPRESSION", "TM_RND01", p, a,
             "Round-amount pattern again; an open TM_RND01 alert from 12 days ago (seeded) means today's alert is raised as SUPPR / DUPL")
        self.suppress_seed = (p, a, self.prev_bus(R - 12 * ONE))

        # sanctions designations used by S12-S16 are created in build_sanctions()
        # S12 exact name (beneficiary) - pending outbound => DAML
        p = self.add_party("CIB", "O", name="Atlas Freight Forwarding plc", sic="52290", overdue=False, rating="M")
        a = self.add_acct(p, "CIBCUR", open_dt=R - 2000 * ONE, ccy="USD")
        Dy.append(self.txn(a, R, "SWFO", 250000.00, ccy="USD", cpty=dict(nm="KORVEX MARITIME HOLDINGS LLC", iban=self.iban("AE"), bic="GHGTAEADXXX", ctry="AE", bank="AE"), status="PD", narr="CHARTER HIRE"))
        scen("S12_SANCTIONS_EXACT", "TM_SAN01", p, a, "Pending USD 250k SWIFT to a listed entity (exact name), routed via UAE - DAML/SAR candidate")
        # S13 token match (reordered individual name)
        p = self.add_party("WLT", "I", name="Oliver Strathmore", overdue=False, pep=False, rating="M")
        a = self.add_acct(p, "WLTCUR", open_dt=R - 1600 * ONE)
        Dy.append(self.txn(a, R, "SWFO", 45000.00, cpty=dict(nm="ZELTSKY ARKADY VIKTOROVICH", iban=self.iban("CY"), bic="CYPBCY2NXXX", ctry="CY", bank="CY"), orig_ccy="EUR", orig_amt=45000 * 1.17, narr="YACHT SHARE"))
        scen("S13_SANCTIONS_TOKEN", "TM_SAN01", p, a, "SWIFT to Cyprus; beneficiary is a listed individual with name order changed (token match)")
        # S14 BIC match
        p = self.add_party("BUS", "O", name="Castlegate Metals Trading Ltd", sic="46720", overdue=False, rating="H")
        a = self.add_acct(p, "BUSCUR", open_dt=R - 1300 * ONE)
        Dy.append(self.txn(a, R, "SWFO", 12000.00, cpty=dict(nm="Trading House Alferov", iban=self.iban("RU"), bic="TVDCRUMMXXX", ctry="RU", bank="RU"), orig_ccy="USD", narr="NICKEL CATHODES"))
        scen("S14_SANCTIONS_BIC", "TM_SAN01", p, a, "SWIFT via a listed Russian bank (BIC match); payee name itself is not listed")
        # S15 country match (DPRK)
        p = self.add_party("CIB", "O", name="Redwood Marine Supplies plc", sic="46900", overdue=False, rating="M")
        a = self.add_acct(p, "CIBCUR", open_dt=R - 2600 * ONE)
        Dy.append(self.txn(a, R, "SWFO", 8000.00, cpty=dict(nm="Taedong Marine Parts Co", iban="", bic="", ctry="KP", bank="KP"), orig_ccy="USD", narr="SPARE PARTS"))
        scen("S15_SANCTIONS_COUNTRY", "TM_SAN01", p, a, "SWIFT to a bank in North Korea (comprehensive regime)")
        # S16 ordering customer (inbound)
        p = self.add_party("RET", "I", name="Kamal Haddad", nationality="GB", exp_turnover=6000, overdue=False, pep=False, rating="L")
        a = self.add_acct(p, "RETCUR", open_dt=R - 1100 * ONE)
        Dy.append(self.txn(a, R, "SWFI", 9500.00, cpty=dict(nm="Mahmoud Reza Khalilzadeh", iban=self.iban("AE"), bic="GHGTAEADXXX", ctry="AE", bank="AE"), ordering="MAHMOUD REZA KHALILZADEH", orig_ccy="AED", orig_amt=9500 * 4.66, narr="FAMILY SUPPORT"))
        scen("S16_SANCTIONS_ORDERING", "TM_SAN01", p, a, "Inbound SWIFT from UAE where the ordering customer is a listed Iranian individual")

        # KYC DQ plants
        p = self.add_party("BUS", "O", name="Brookside Bakery Ltd", sic="10710", co_house="", overdue=False)
        self.add_acct(p, "BUSCUR")
        self.kyc_dq.append(dict(ERR_NR=109, KEY=p["PARTY_ID"], DESCRIPTION="UK organisation without company number"))
        p = self.add_party("RET", "I", name="Nadia Petrescu", nationality="QQ", overdue=False)
        self.add_acct(p, "RETCUR")
        self.kyc_dq.append(dict(ERR_NR=104, KEY=p["PARTY_ID"], DESCRIPTION="Unknown nationality QQ"))
        p = self.add_party("RET", "I", name="Owen Fairbairn", overdue=False)
        a = self.add_acct(p, "RETCUR")
        a["PRDT_CD_RAW"] = "XXXPRD"
        a["profile"] = "quiet"
        self.kyc_dq.append(dict(ERR_NR=106, KEY=a["ACCT_ID"], DESCRIPTION="Unknown product XXXPRD"))
        self.orphan_acct = dict(ACCT_ID=OWN_SORTS[0] + "90909090", SORT_CD=OWN_SORTS[0], ACCT_NR="90909090",
                                PRDT_CD="RETCUR", CCY_CD="GBP", OPEN_DT=R - 400 * ONE, CLOSE_DT=None,
                                ACCT_STATUS_CD="A", PRIMARY_PARTY_ID="PTY999999999", OD_LIMIT_AMT=0,
                                LAST_CUST_ACTV_DT=R - ONE, OPEN_CHNL_CD="BRN")
        self.kyc_dq.append(dict(ERR_NR=101, KEY=self.orphan_acct["ACCT_ID"], DESCRIPTION="Primary party PTY999999999 not delivered"))

    # ------------------------------------------------------------------ daily file specials
    def daily_specials(self):
        r, R = self.r, self.run
        Dy = self.daily
        live = [a for a in self.accts.values() if a["profile"] == "std" and a["PRDT_CD"] in ("RETCUR", "BUSCUR")
                and a["ACCT_ID"] not in self.planted_accts]
        # placeholder account (not delivered by KYCSYS)
        ghost = dict(ACCT_ID=OWN_SORTS[3] + "31415926", SORT_CD=OWN_SORTS[3], ACCT_NR="31415926", CCY_CD="GBP",
                     PRIMARY_PARTY_ID=None)
        for amt in (420.00, 75.20):
            x = self.txn(None, R, "FPSI", amt, acct_id=ghost["ACCT_ID"], cpty=r.choice(self.pool_people))
            Dy.append(x)
        self.dq.append(dict(CHECK="UNKNOWN_ACCOUNT", KEY=ghost["ACCT_ID"], EXPECTED="2 txns; placeholder row in ACCT_SNAPSHOT (SEGMENT_CD UNK)"))
        a = r.choice(live)
        x = self.txn(a, R, "SWFI", 1250.00, ccy="XYZ", cpty=r.choice(self.pool_intl)); Dy.append(x)
        self.dq.append(dict(CHECK="UNKNOWN_CURRENCY", KEY=x["TXN_REF"], EXPECTED="TXN_CCY XYZ; no GBP amount"))
        a = r.choice(live)
        x = self.txn(a, R, "SWFI", 30000.00, ccy="KES", orig_ccy="KES", cpty=dict(nm="Nairobi Fresh Produce Ltd", iban="", bic="NFPLKENAXXX", ctry="KE", bank="KE")); Dy.append(x)
        self.dq.append(dict(CHECK="MISSING_FX_RATE", KEY=x["TXN_REF"], EXPECTED="KES has no FX rate; RATE_FALLBACK_IND X"))
        a = r.choice(live)
        x = self.txn(a, R, "SWFO", 640.00, cpty=dict(nm="Unknown Republic Supplies", iban="", bic="", ctry="QQ", bank="QQ")); Dy.append(x)
        self.dq.append(dict(CHECK="UNKNOWN_COUNTRY", KEY=x["TXN_REF"], EXPECTED="CPTY_CTRY and CPTY_BANK_CTRY QQ"))
        a = r.choice(live)
        x = self.txn(a, R, "FPSO", 55.00, cpty=r.choice(self.pool_people)); x["TXN_TYP_CD"] = "ZZZZ"; Dy.append(x)
        self.dq.append(dict(CHECK="UNKNOWN_TXN_TYPE", KEY=x["TXN_REF"], EXPECTED="ZZZZ added to TXN_TYP_CAT (auto) and logged"))
        a = r.choice(live)
        x = self.txn(a, R, "FPSO", 310.00, cpty=dict(nm="Closed Branch Payee", sort=CLOSED_SORT, acct="12345678", ctry="GB", bank="GB")); Dy.append(x)
        self.dq.append(dict(CHECK="CLOSED_SORT_CODE", KEY=x["TXN_REF"], EXPECTED=f"Counterparty sort code {CLOSED_SORT} is closed"))
        a = r.choice(live)
        x = self.txn(a, R, "CRDP", 19.99, mcc="0000", merchant="MYSTERY MERCHANT"); Dy.append(x)
        self.dq.append(dict(CHECK="UNKNOWN_MCC", KEY=x["TXN_REF"], EXPECTED="MCC 0000 not in MCC_SNAPSHOT"))
        # in-file duplicates (same key, higher FILE_SEQ_NR wins; positions set when writing)
        self.file_dups = []
        for x in r.sample([t for t in Dy if t["TXN_TYP_CD"] == "CRDP" and t["ACCT_ID"] not in self.planted_accts], 2):
            y = dict(x)
            y["BAL_AFTER"] = round(x["BAL_AFTER"] - 1, 2)
            self.file_dups.append(y)
            self.dq.append(dict(CHECK="IN_FILE_DUPLICATE", KEY=x["TXN_REF"], EXPECTED="Earlier record to HIST_DLYTXN_LOAD_DUP reason FD"))
        # re-sent history (restart) -> PD
        cand = [t for t in self.hist if t["BOOKING_DT"] >= R - 5 * ONE and t["ACCT_ID"] not in self.planted_accts
                and t["TXN_TYP_CD"] in ("CRDP", "FPSO", "DDBT")]
        self.resends = [dict(t) for t in r.sample(cand, 3)]
        for t in self.resends:
            self.dq.append(dict(CHECK="PREVIOUSLY_LOADED", KEY=t["TXN_REF"], EXPECTED="Re-sent unchanged; to HIST_DLYTXN_LOAD_DUP reason PD"))
        # status change of a history payment (returned) -> before-image U in AML_TXN_DAILY_HIST
        t = dict(r.choice([t for t in cand if t["TXN_TYP_CD"] == "FPSO" and t not in self.resends]))
        t["TXN_STATUS"] = "RJ"; t["RETURN_REASON_CD"] = "AC04"
        self.status_change = t
        self.dq.append(dict(CHECK="STATUS_CHANGE", KEY=t["TXN_REF"], EXPECTED="Status BK->RJ (AC04 account closed); before-image U in AML_TXN_DAILY_HIST"))
        # reversal of a history card payment
        o = r.choice([t for t in self.hist if t["TXN_TYP_CD"] == "CRDP" and t["BOOKING_DT"] >= R - 10 * ONE
                      and t["ACCT_ID"] not in self.planted_accts and t["TXN_REF"] not in {z["TXN_REF"] for z in self.resends}])
        acct = self.accts[o["ACCT_ID"]]
        rv = self.txn(acct, R, "CRDP", -o["TXN_AMT"], mcc=o["MCC"], merchant=o["MERCHANT_NM"], drcr="D")
        rv.update(REVERSAL_IND="Y", ORIG_TXN_REF=o["TXN_REF"], NARRATIVE="REVERSAL " + o["MERCHANT_NM"])
        Dy.append(rv)
        self.reversal = (rv, o)
        self.dq.append(dict(CHECK="REVERSAL", KEY=rv["TXN_REF"], EXPECTED=f"Reverses {o['TXN_REF']}; original gets 'R' before-image and status RV"))
        # late (back-dated) postings
        for a in r.sample(live, 2):
            d = self.prev_bus(R - 3 * ONE)
            x = self.txn(a, d, "CHQD", round(r.uniform(80, 900), 2), chnl="BRN")
            x["EXTRACT_DT"] = R
            Dy.append(x)
            self.dq.append(dict(CHECK="BACK_DATED", KEY=x["TXN_REF"], EXPECTED=f"Booking date {d}; ACCT_DAILY_SUMM for that date re-summarised"))

    # ------------------------------------------------------------------ sanctions list
    def build_sanctions(self):
        r = self.r
        rows, gid = [], 14000
        self.sanc_entities = []

        def add(gtype, regime, names, nat="", addr_ctry="", dob=None, other="", position="", listed=None, pp=""):
            nonlocal gid
            gid += 1
            listed = listed or (self.run - r.randint(60, 1500) * ONE)
            upd = min(self.run - 3 * ONE, listed + r.randint(0, 400) * ONE)
            ref = {"Russia": "RUS", "Iran": "IRN", "Democratic People's Republic of Korea": "DPR", "Syria": "SYR",
                   "Belarus": "BLR", "Global Human Rights": "GHR", "Counter-Terrorism (International)": "CTI",
                   "Libya": "LIB"}[regime] + f"{gid % 10000:04d}"
            for (n1, n2, n6, atype, qual, nonlat) in names:
                rows.append(dict(GROUP_ID=str(gid), NAME_6=n6, NAME_1=n1, NAME_2=n2, NAME_3="", NAME_4="", NAME_5="",
                                 TITLE="", NAME_NON_LATIN=nonlat, DOB=dob or "", TOWN_OF_BIRTH="", CTRY_OF_BIRTH=nat,
                                 NATIONALITY=nat, PASSPORT_NR=pp, NATIONAL_ID_NR="", POSITION=position,
                                 ADDR_1="", ADDR_CTRY=addr_ctry, OTHER_INFO=other,
                                 GROUP_TYPE={"I": "Individual", "E": "Entity", "S": "Ship"}[gtype],
                                 ALIAS_TYPE=atype, ALIAS_QUALITY=qual, REGIME=regime, LISTED_ON=dmy(listed),
                                 UK_SANC_LIST_DT=dmy(listed), LAST_UPDATED=dmy(upd), UK_SANC_LIST_REF=ref))
            self.sanc_entities.append(dict(GROUP_ID=gid, TYPE=gtype, REGIME=regime, NAMES=[n for n in names], OTHER=other, NAT=nat))
            return gid

        # planted designations
        self.g_korvex = add("E", "Russia", [("", "", "KORVEX MARITIME HOLDINGS LLC", "Primary name", "Good", "Корвекс Маритайм Холдингс"),
                                            ("", "", "KORVEKS MARITIME", "AKA", "Low", "")],
                            addr_ctry="Russia", other="Ship management company. Registered address St Petersburg.")
        self.g_zeltsky = add("I", "Russia", [("Arkady", "Viktorovich", "ZELTSKY", "Primary name", "Good", cyr("Arkady Viktorovich Zeltsky")),
                                             ("Arkadi", "", "ZELTSKI", "Primary name variation", "Good", "")],
                             nat="Russia", dob="14/02/1968", position="Board member, Korvex Maritime Holdings", pp="7212345678")
        self.g_tavrida = add("E", "Russia", [("", "", "TAVRIDA COMMERCE BANK JSC", "Primary name", "Good", "")],
                             addr_ctry="Russia", other="SWIFT/BIC: TVDCRUMM. Website: none.")
        self.g_khalil = add("I", "Iran", [("Mahmoud Reza", "", "KHALILZADEH", "Primary name", "Good", ""),
                                          ("Mahmood", "", "KHALIL ZADEH", "AKA", "Low", "")],
                            nat="Iran", dob="00/00/1961", position="Procurement agent")
        self.g_ryongak = add("E", "Democratic People's Republic of Korea", [("", "", "RYONGAK TRADING CORPORATION", "Primary name", "Good", "")],
                             addr_ctry="North Korea", other="Front company")
        # background designations
        regimes = [("Russia", RU_FIRST, RU_LAST, "Russia"), ("Iran", IR_FIRST, IR_LAST, "Iran"),
                   ("Democratic People's Republic of Korea", KP_FIRST, KP_LAST, "North Korea"),
                   ("Syria", SY_FIRST, SY_LAST, "Syria"), ("Belarus", RU_FIRST, RU_LAST, "Belarus")]
        used = set()
        for _ in range(85):
            reg, F, L, nat = r.choice(regimes)
            f, l = r.choice(F), r.choice(L)
            pat = r.choice(RU_PATRO) if reg in ("Russia", "Belarus") else ""
            if (f, l) in used or l.upper() in ("ZELTSKY", "KHALILZADEH"):
                continue
            used.add((f, l))
            names = [(f, pat, l.upper(), "Primary name", "Good", cyr(f"{f} {pat} {l}") if reg in ("Russia", "Belarus") else "")]
            if r.random() < 0.4:
                names.append((f[0] + ".", "", l.upper(), "AKA", "Low", ""))
            if r.random() < 0.3:
                names.append((f, "", l.upper() + ("A" if l[-1] in "vn" else "I"), "Primary name variation", "Good", ""))
            dob = f"{r.randint(1, 28):02d}/{r.randint(1, 12):02d}/{r.randint(1945, 1990)}" if r.random() < 0.8 else f"00/00/{r.randint(1945, 1990)}"
            add("I", reg, names, nat=nat, dob=dob, position=r.choice(["Businessman", "Former official", "Military officer", "Member of parliament", ""]))
        for _ in range(45):
            reg, _, _, nat = r.choice(regimes)
            stem = r.choice(ENT_STEM)
            nm = f"{stem} {r.choice(ENT_KIND)} {r.choice(ENT_FORM)}".upper()
            if nm in used or stem in ("Korvex", "Tavrida", "Ryongak"):
                continue
            used.add(nm)
            other = ""
            if "BANK" in nm:
                other = f"SWIFT/BIC: {''.join(r.choice('BCDFGHJKLMNPQRSTVWXZ') for _ in range(4))}{ {'Russia': 'RU', 'Iran': 'IR', 'Belarus': 'BY'}.get(reg, 'RU')}{r.choice(['MM', '2X', 'TH'])}"
            names = [("", "", nm, "Primary name", "Good", "")]
            if r.random() < 0.3:
                names.append(("", "", nm.rsplit(" ", 1)[0], "AKA", "Good", ""))
            add("E", reg, names, addr_ctry=nat, other=other)
        for _ in range(5):
            nm = f"{r.choice(['MV', 'MT'])} {r.choice(['SEA', 'NORTH', 'STAR', 'GOLDEN', 'PEARL'])} {r.choice(['FALCON', 'DAWN', 'WIND', 'HAWK', 'TIDE'])}"
            if nm in used:
                continue
            used.add(nm)
            add("S", r.choice(["Russia", "Iran", "Democratic People's Republic of Korea"]),
                [("", "", nm, "Primary name", "Good", "")], other=f"IMO number {r.randint(9000000, 9999999)}")
        self.sanc_rows = rows
        # name index for screening simulation (active, from file)
        self.sanc_names = []
        for row in rows:
            full = " ".join(x for x in [row["NAME_1"], row["NAME_2"], row["NAME_3"], row["NAME_4"], row["NAME_5"], row["NAME_6"]] if x)
            full = full.replace("  ", " ").replace("  ", " ")
            self.sanc_names.append(dict(GROUP_ID=int(row["GROUP_ID"]), FULL_NM=full, NORM_NM=norm(full),
                                        TOKENS=tokens(full), QUAL="L" if row["ALIAS_QUALITY"] == "Low" else "G",
                                        REGIME=row["REGIME"]))
        self.sanc_bics = {}
        import re
        for e in self.sanc_entities:
            m = re.search(r"(SWIFT/BIC|SWIFT|BIC)[ :/]{1,3}([A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?)", e["OTHER"].upper())
            if m:
                self.sanc_bics[m.group(2)[:8]] = e["GROUP_ID"]

    # ------------------------------------------------------------------ enrichment (mirror of dailytxn.05-.10)
    def cpty_for(self, x, d):
        key = (x["CPTY_IBAN"].strip() or (x["CPTY_SORT_CD"] + x["CPTY_ACCT_NR"]).strip()) or None
        if not key:
            return None
        nm = norm(x["CPTY_NM"]) or "UNKNOWN"
        k = (key, nm)
        c = self.cpty.get(k)
        if c is None:
            self.next_cpty += 1
            c = dict(CPTY_ID=self.next_cpty, CPTY_ACCT_KEY=key, CPTY_NORM_NM=nm, CPTY_BIC_CD=x["CPTY_BIC"],
                     CPTY_CTRY_CD=x["CPTY_CTRY"], FIRST_SEEN_DT=d, LAST_SEEN_DT=d, TXN_CNT=0)
            self.cpty[k] = c
        c["LAST_SEEN_DT"] = max(c["LAST_SEEN_DT"], d)
        c["TXN_CNT"] += 1
        return c

    def enrich(self, x, assign_cpty=True):
        a = self.accts.get(x["ACCT_ID"])
        p = self.parties.get(a["PRIMARY_PARTY_ID"]) if a else None
        typ = TT.get(x["TXN_TYP_CD"])
        rate, fb = self.rate(x["TXN_CCY"], x["BOOKING_DT"]) if x["TXN_CCY"] in {c[0] for c in CURRENCIES} else (None, "X")
        gbp = round(x["TXN_AMT"] / rate, 2) if rate else None
        bank = x["CPTY_BANK_CTRY"] or (x["CPTY_BIC"][4:6] if len(x["CPTY_BIC"].strip()) == 11 else "") or \
            (x["CPTY_IBAN"][:2] if x["CPTY_IBAN"] else "") or ("GB" if x["CPTY_SORT_CD"].strip() else "")
        c = self.cpty_for(x, x["BOOKING_DT"]) if assign_cpty else None
        internal = None
        if c and x["CPTY_SORT_CD"] and (x["CPTY_SORT_CD"] + x["CPTY_ACCT_NR"]) in self.accts:
            internal = self.accts[x["CPTY_SORT_CD"] + x["CPTY_ACCT_NR"]]
        mctry = x["MERCHANT_CTRY"]
        hrc = any(cc in HIGH_RISK_CTRY for cc in (x["CPTY_CTRY"], bank, mctry) if cc)
        f = dict(
            TXN_REF=x["TXN_REF"], SUPPLIER_CD=x["SUPPLIER_CD"], BOOKING_DT=x["BOOKING_DT"], VALUE_DT=x["VALUE_DT"],
            TXN_TMS=x["TXN_TMS"], ACCT_ID=x["ACCT_ID"], SORT_CD=x["SORT_CD"], ACCT_NR=x["ACCT_NR"],
            PARTY_ID=a["PRIMARY_PARTY_ID"] if a else None, PRDT_CD=a["PRDT_CD"] if a else None,
            SEGMENT_CD=a["SEGMENT_CD"] if a else "UNK", TXN_TYP_CD=x["TXN_TYP_CD"],
            PAY_SCHEME_CD=typ[2] if typ else None, CHNL_CD=x["CHNL_CD"], DR_CR_IND=x["DR_CR_IND"],
            TXN_AMT=x["TXN_AMT"], TXN_CCY_CD=x["TXN_CCY"], ORIG_AMT=x["ORIG_AMT"], ORIG_CCY_CD=x["ORIG_CCY"],
            GBP_AMT=gbp, GBP_RATE=rate,
            CASH_IND="Y" if (typ and typ[4] == "Y") or x["CASH_IND"] == "Y" else "N",
            XBORDER_IND="Y" if (typ and typ[5] == "Y") or (bank or "GB") not in ("GB",) or (mctry or "GB") != "GB" else "N",
            ROUND_AMT_IND="Y" if gbp is not None and abs(gbp) >= 1000 and abs(gbp) % 1000 == 0 else "N",
            NARRATIVE_TXT=x["NARRATIVE"], CPTY_ID=c["CPTY_ID"] if c else None, CPTY_NM=x["CPTY_NM"],
            CPTY_SORT_CD=x["CPTY_SORT_CD"], CPTY_ACCT_NR=x["CPTY_ACCT_NR"], CPTY_IBAN=x["CPTY_IBAN"],
            CPTY_BIC_CD=x["CPTY_BIC"], CPTY_BANK_CTRY_CD=bank or None, CPTY_CTRY_CD=x["CPTY_CTRY"] or None,
            CPTY_CTRY_RISK_CD=ctry_risk(x["CPTY_CTRY"]) if x["CPTY_CTRY"] in CTRY else None,
            CPTY_INTERNAL_IND="Y" if internal else "N",
            CPTY_PARTY_ID=internal["PRIMARY_PARTY_ID"] if internal else None,
            ORDERING_CUST_NM=x["ORDERING_CUST_NM"], BENEF_CUST_NM=x["BENEF_CUST_NM"], PAYMENT_REF=x["PAYMENT_REF"],
            E2E_ID=x["E2E_ID"], UETR=x["UETR"], SWIFT_MSG_TYP_CD=x["SWIFT_MSG_TYP"], INTERMED_BIC_CD=x["INTERMED_BIC"],
            MCC_CD=x["MCC"], MCC_RISK_CD=MCC[x["MCC"]][2] if x["MCC"] in MCC else None, MERCHANT_NM=x["MERCHANT_NM"],
            MERCHANT_CTRY_CD=x["MERCHANT_CTRY"], CARD_TOKEN=x["CARD_TOKEN"], CARD_PRESENT_IND=x["CARD_PRESENT_IND"],
            ATM_ID=x["ATM_ID"], BRANCH_SORT_CD=x["BRANCH_SORT_CD"], CHEQUE_NR=x["CHEQUE_NR"], DEVICE_ID=x["DEVICE_ID"],
            IP_CTRY_CD=x["IP_CTRY"], AUTH_METHOD_CD=x["AUTH_METHOD"], COP_RESULT_CD=x["COP_RESULT"],
            APP_FRAUD_IND=x["APP_FRAUD_IND"], RETURN_REASON_CD=x["RETURN_REASON_CD"], REVERSAL_IND=x["REVERSAL_IND"],
            ORIG_TXN_REF=x["ORIG_TXN_REF"], BAL_AFTER_AMT=x["BAL_AFTER"], TXN_STATUS_CD=x["TXN_STATUS"],
            FEE_AMT=x["FEE_AMT"], PURPOSE_CD=x["PURPOSE_CD"],
            PARTY_RISK_RATING_CD=p["RISK_RATING_CD_EFF"] if p else "U", PARTY_PEP_IND=p["PEP_IND"] if p else "N",
            HRC_IND="Y" if hrc else "N", SANC_HIT_IND="N", DQ_ERR_IND="N", BATCH_ID=x["BATCH_ID"],
            FILE_SEQ_NR=x["FILE_SEQ_NR"],
            LOAD_TMS=dt.datetime.combine(x["BOOKING_DT"] + ONE, dt.time(5, 30)),
            CO_UPD_TMS=dt.datetime.combine(x["BOOKING_DT"] + ONE, dt.time(5, 30)))
        return f

    # ------------------------------------------------------------------ orchestration
    def build_transactions(self):
        d = self.hist_start
        accts = list(self.accts.values())
        while d <= self.run:
            sink = self.daily if d == self.run else self.hist
            for a in accts:
                self.activity(a, d, sink)
            d += ONE

    def run_all(self):
        self.build_fx()
        self.build_kyc()
        self.build_pools()
        self.build_sanctions()
        self.plant()
        self.build_transactions()
        self.hist.sort(key=lambda t: (t["BOOKING_DT"], t["TXN_TMS"]))
        self.fact = [self.enrich(t) for t in self.hist]
        self.daily_specials()
        self.write_all()

    # ------------------------------------------------------------------ writers
    def path(self, *p):
        fp = os.path.join(self.out, *p)
        os.makedirs(os.path.dirname(fp), exist_ok=True)
        return fp

    def write_all(self):
        self.write_refsys()
        self.write_kycsys()
        self.write_sancsys()
        self.write_dailytxn()
        self.write_seeds()
        self.write_expected()

    def write_refsys(self):
        R = self.run
        lines = [("HD", fw("REFSYS FULL EXTRACT", 30), fw(ymd(R) + "  RECORDS FOLLOW", 221))]

        def rec(a, b, payload):
            lines.append((a, fw(b, 30), payload.s()))
        for c in COUNTRIES:
            p = Payload(221).put(1, 1, "I").put(2, 3, c[1]).put(5, 50, c[2]).put(55, 2, c[3]).put(57, 1, c[4]) \
                .put(58, 1, c[5]).put(59, 5, f"{c[6]:.2f}").put(64, 3, str(c[7])).put(67, 1, c[8]) \
                .put(68, 3, c[9]).put(71, 8, "20200101").put(79, 8, "99991231")
            rec("CT", c[0], p)
        for ccy, nm, mu, num, base in CURRENCIES:
            rec("CY", ccy, Payload(221).put(1, 1, "I").put(2, 30, nm).put(32, 1, str(mu)).put(33, 3, num).put(36, 1, "Y"))
        fx_days = sorted({d for (_, d) in self.fx if d >= R - 14 * ONE})
        for (ccy, d), v in sorted(self.fx.items()):
            if d in fx_days:
                rec("FX", ccy + ymd(d), Payload(221).put(1, 1, "I").put(2, 2, "SP").put(4, 16, f"{v:.8f}"))
        for m in MCCS:
            rec("MC", m[0], Payload(221).put(1, 1, "I").put(2, 50, m[1]).put(52, 1, m[2]).put(53, 1, m[3]).put(54, 1, m[4]).put(55, 1, m[5]))
        for i, s in enumerate(OWN_SORTS):
            rec("SC", s, Payload(221).put(1, 1, "I").put(2, 40, OWN_BANK).put(42, 40, OWN_BRANCHES[i]).put(82, 11, OWN_BIC)
                .put(93, 1, "Y").put(94, 1, "Y").put(95, 1, "Y").put(96, 1, "N").put(97, 8, POSTCODES[i]))
        peer_sorts = sorted({x["sort"] for x in self.pool_people + self.pool_biz + self.pool_employers} |
                            {"992455", "992870", "992311", "992600", "992777", "992011"})
        for s in peer_sorts:
            pb = PEER_BANKS[int(s[2:4]) % len(PEER_BANKS)]
            rec("SC", s, Payload(221).put(1, 1, "I").put(2, 40, pb[0]).put(42, 40, f"BRANCH {s[2:]}").put(82, 11, pb[1] + "XXX")
                .put(93, 1, "Y").put(94, 1, "Y" if int(s) % 3 else "N").put(95, 1, "Y").put(96, 1, "N").put(97, 8, self.r.choice(POSTCODES)))
        rec("SC", CLOSED_SORT, Payload(221).put(1, 1, "I").put(2, 40, "THAMES MUTUAL BANK").put(42, 40, "FORMER HIGH ST BRANCH")
            .put(82, 11, "THMBGB2LXXX").put(93, 1, "N").put(94, 1, "N").put(95, 1, "N").put(96, 1, "Y").put(97, 8, "SE1 9SG"))
        for t in TXN_TYPES:
            rec("TT", t[0], Payload(221).put(1, 1, "I").put(2, 50, t[1]).put(52, 4, t[2]).put(56, 1, t[3]).put(57, 1, t[4]).put(58, 1, t[5]))
        for c in CHANNELS:
            rec("CH", c[0], Payload(221).put(1, 1, "I").put(2, 40, c[1]).put(42, 1, c[2]))
        for p in PRODUCTS:
            rec("PR", p[0], Payload(221).put(1, 1, "I").put(2, 50, p[1]).put(52, 4, p[2]).put(56, 3, p[3]).put(59, 1, p[4]))
        for s in SICS:
            rec("OC", s[0], Payload(221).put(1, 1, "I").put(2, 60, s[1]).put(62, 1, s[2]).put(63, 1, s[3]))
        for ru in RULES:
            rec("RT", fw(ru[0], 8) + ru[1], Payload(221).put(1, 1, "I").put(2, 14, f"{ru[2]:.2f}").put(16, 5, str(ru[3]))
                .put(21, 3, str(ru[4])).put(24, 7, f"{ru[5]:.2f}").put(31, 3, str(ru[6])).put(34, 1, "Y").put(35, 60, ru[7]))
        # planted rejects
        rec("ZZ", "UNKNOWN RECTYPE", Payload(221).put(1, 1, "I").put(2, 30, "LEGACY RECORD TYPE NO LONGER USED"))
        self.ref_dq.append(dict(CHECK="UNKNOWN RECORD TYPE ZZ", KEY="ZZ", EXPECTED="AML_REFSYS_REJ"))
        p = Payload(221).put(1, 1, "I").put(2, 3, "XKX").put(5, 50, "Kosovo").put(55, 2, "NA").put(57, 1, "N").put(58, 1, "N") \
            .put(59, 5, "5.10").put(64, 3, "41").put(67, 1, "N").put(68, 3, "EUR").put(71, 8, "20251350").put(79, 8, "99991231")
        rec("CT", "XK", p)
        self.ref_dq.append(dict(CHECK="INVALID VALID_FROM_DT", KEY="CT XK", EXPECTED="AML_REFSYS_REJ (date 20251350)"))
        n = len(lines) - 1
        lines.append(("TR", fw(f"{n:010d}", 30), fw("", 221)))
        with open(self.path("landing", "kycref.refsys.dat"), "w", newline="\n") as f:
            for a, b, c in lines:
                f.write(a + b + c + "\n")
        self.refsys_cnt = n

    def write_kycsys(self):
        R = self.run
        lines = [("HD", fw("KYCSYS FULL", 26), fw(ymd(R), 472))]
        for p in self.parties.values():
            c = Payload(472).put(1, 1, "I").put(2, 1, p["PARTY_TYP_CD"]).put(3, 100, p["FULL_NM"]).put(103, 8, ymd(p["BIRTH_DT"])) \
                .put(111, 2, p["NATIONALITY_CD"] or "").put(113, 2, p["RESIDENCE_CTRY_CD"]).put(115, 5, p["SIC_CD"]) \
                .put(120, 1, p["PEP_IND"]).put(121, 2, p["PEP_TYP_CD"]).put(123, 1, p["ADV_MEDIA_IND"]) \
                .put(124, 3, p["SEGMENT_CD"]).put(127, 8, ymd(p["ONBOARD_DT"])).put(135, 8, ymd(p["KYC_REVIEW_DUE_DT"])) \
                .put(143, 2, p["KYC_STATUS_CD"]).put(145, 3, p["CDD_LEVEL_CD"]).put(148, 1, p["RISK_RATING_CD"]) \
                .put(149, 8, p["RM_ID"]).put(157, 8, p["POSTCODE"]).put(165, 8, p["CO_HOUSE_NR"]) \
                .put(173, 2, p["INCORP_CTRY_CD"]).put(175, 14, f"{p['EXP_MTH_TURNOVER_AMT']:.2f}") \
                .put(189, 2, p["SRC_OF_FUNDS_CD"]).put(191, 1, p["CLOSED_IND"])
            lines.append(("PY", fw(p["PARTY_ID"], 26), c.s()))
        for a in list(self.accts.values()) + [self.orphan_acct]:
            c = Payload(472).put(1, 1, "I").put(2, 6, a.get("PRDT_CD_RAW", a["PRDT_CD"])).put(8, 3, a["CCY_CD"]) \
                .put(11, 8, ymd(a["OPEN_DT"])).put(19, 8, ymd(a["CLOSE_DT"])).put(27, 1, a["ACCT_STATUS_CD"]) \
                .put(28, 12, a["PRIMARY_PARTY_ID"]).put(40, 14, f"{a['OD_LIMIT_AMT']:.2f}") \
                .put(54, 8, ymd(a["LAST_CUST_ACTV_DT"])).put(62, 3, a["OPEN_CHNL_CD"])
            lines.append(("AC", fw(a["ACCT_ID"], 26), c.s()))
        for rl in self.rels:
            c = Payload(472).put(1, 1, "I").put(2, 2, rl["ROLE_CD"]).put(4, 8, ymd(rl["START_DT"])) \
                .put(12, 8, ymd(rl["END_DT"])).put(20, 6, f"{rl['OWNERSHIP_PCT']:.2f}")
            lines.append(("PA", fw(rl["PARTY_ID"], 12) + fw(rl["ACCT_ID"], 14), c.s()))
        for al in self.aliases:
            c = Payload(472).put(1, 1, "I").put(2, 100, al["ALIAS_NM"]).put(102, 2, al["ALIAS_TYP_CD"])
            lines.append(("AL", fw(fw(al["PARTY_ID"], 12) + f"{al['ALIAS_SEQ_NR']:03d}", 26), c.s()))
        n = len(lines) - 1
        lines.append(("TR", fw(f"{n:010d}", 26), fw("", 472)))
        with open(self.path("landing", "kycref.kycsys.dat"), "w", newline="\n") as f:
            for a, b, c in lines:
                f.write(a + b + c + "\n")
        self.kycsys_cnt = n

    SANC_COLS = ["GROUP_ID", "NAME_6", "NAME_1", "NAME_2", "NAME_3", "NAME_4", "NAME_5", "TITLE", "NAME_NON_LATIN",
                 "DOB", "TOWN_OF_BIRTH", "CTRY_OF_BIRTH", "NATIONALITY", "PASSPORT_NR", "NATIONAL_ID_NR", "POSITION",
                 "ADDR_1", "ADDR_CTRY", "OTHER_INFO", "GROUP_TYPE", "ALIAS_TYPE", "ALIAS_QUALITY", "REGIME",
                 "LISTED_ON", "UK_SANC_LIST_DT", "LAST_UPDATED", "UK_SANC_LIST_REF"]

    def write_sancsys(self):
        heading = ["Group ID", "Name 6", "Name 1", "Name 2", "Name 3", "Name 4", "Name 5", "Title",
                   "Name Non-Latin Script", "DOB", "Town of Birth", "Country of Birth", "Nationality",
                   "Passport Number", "National Identification Number", "Position", "Address 1", "Country",
                   "Other Information", "Group Type", "Alias Type", "Alias Quality", "Regime", "Listed On",
                   "UK Sanctions List Date Designated", "Last Updated", "UK Sanctions List Ref"]
        with open(self.path("landing", "kycref.sancsys.txt"), "w", encoding="utf-8", newline="\n") as f:
            f.write("|".join(heading) + "\n")
            for row in self.sanc_rows:
                f.write("|".join(str(row[c]).replace("|", "/") for c in self.SANC_COLS) + "\n")

    def raw_line(self, x):
        vals = dict(RECTYPE="D", SUPPLIER_CD=x["SUPPLIER_CD"], FILE_SEQ_NR=str(x["FILE_SEQ_NR"]), TXN_REF=x["TXN_REF"],
                    TXN_SEQ_NR=str(x["TXN_SEQ_NR"]), SORT_CD=x["SORT_CD"], ACCT_NR=x["ACCT_NR"], TXN_TYP_CD=x["TXN_TYP_CD"],
                    CHNL_CD=x["CHNL_CD"], DR_CR_IND=x["DR_CR_IND"], TXN_AMT=money(x["TXN_AMT"]), TXN_CCY=x["TXN_CCY"],
                    ORIG_AMT=money(x["ORIG_AMT"]), ORIG_CCY=x["ORIG_CCY"], BOOKING_DT=ymd(x["BOOKING_DT"]),
                    VALUE_DT=ymd(x["VALUE_DT"]), TXN_TMS=x["TXN_TMS"].strftime("%Y%m%d%H%M%S"), NARRATIVE=x["NARRATIVE"],
                    CPTY_NM=x["CPTY_NM"], CPTY_SORT_CD=x["CPTY_SORT_CD"], CPTY_ACCT_NR=x["CPTY_ACCT_NR"],
                    CPTY_IBAN=x["CPTY_IBAN"], CPTY_BIC=x["CPTY_BIC"], CPTY_BANK_CTRY=x["CPTY_BANK_CTRY"],
                    CPTY_CTRY=x["CPTY_CTRY"], ORDERING_CUST_NM=x["ORDERING_CUST_NM"], BENEF_CUST_NM=x["BENEF_CUST_NM"],
                    PAYMENT_REF=x["PAYMENT_REF"], E2E_ID=x["E2E_ID"], UETR=x["UETR"], SWIFT_MSG_TYP=x["SWIFT_MSG_TYP"],
                    CHARGE_BEARER=x["CHARGE_BEARER"], INTERMED_BIC=x["INTERMED_BIC"], MCC=x["MCC"],
                    MERCHANT_NM=x["MERCHANT_NM"], MERCHANT_CTRY=x["MERCHANT_CTRY"], MERCHANT_ID=x["MERCHANT_ID"],
                    TERMINAL_ID=x["TERMINAL_ID"], ATM_ID=x["ATM_ID"], CARD_TOKEN=x["CARD_TOKEN"],
                    POS_ENTRY_MODE=x["POS_ENTRY_MODE"], CARD_PRESENT_IND=x["CARD_PRESENT_IND"],
                    BRANCH_SORT_CD=x["BRANCH_SORT_CD"], TELLER_ID=x["TELLER_ID"], CASH_IND=x["CASH_IND"],
                    CHEQUE_NR=x["CHEQUE_NR"], DEVICE_ID=x["DEVICE_ID"], IP_ADDR=x["IP_ADDR"], IP_CTRY=x["IP_CTRY"],
                    SESSION_ID=x["SESSION_ID"], AUTH_METHOD=x["AUTH_METHOD"], COP_RESULT=x["COP_RESULT"],
                    APP_FRAUD_IND=x["APP_FRAUD_IND"], RETURN_REASON_CD=x["RETURN_REASON_CD"], REVERSAL_IND=x["REVERSAL_IND"],
                    ORIG_TXN_REF=x["ORIG_TXN_REF"], BAL_AFTER=money(x["BAL_AFTER"]), TXN_STATUS=x["TXN_STATUS"],
                    FEE_AMT=money(x["FEE_AMT"]) if x["FEE_AMT"] else "", PURPOSE_CD=x["PURPOSE_CD"], BATCH_ID=x["BATCH_ID"],
                    EXTRACT_DT=ymd(x["EXTRACT_DT"]))
        return "".join(fw(vals[c], w) for c, w in TXN_RAW)

    def write_dailytxn(self):
        R = self.run
        recs = list(self.daily) + self.resends + [self.status_change] + self.file_dups
        by_sup = defaultdict(list)
        for x in recs:
            by_sup[x["SUPPLIER_CD"]].append(x)
        width = sum(w for _, w in TXN_RAW)
        out, totals = [], []
        seq = 0
        for sup in ("CBS1", "PAY1", "CRD1"):
            rows = sorted(by_sup.get(sup, []), key=lambda t: t["TXN_TMS"])
            # duplicates must come after their original so they get the higher FILE_SEQ_NR
            rows = [t for t in rows if t not in self.file_dups] + [t for t in self.file_dups if t["SUPPLIER_CD"] == sup]
            file_id = f"{sup}{ymd(R)}01"
            created = (dt.datetime.combine(R + ONE, dt.time(1, 15))).strftime("%Y%m%d%H%M%S")
            out.append(("H" + fw(sup, 4) + fw(file_id, 20) + ymd(R) + fw("", 10) + fw("", 18) + fw("", 18) + created).ljust(width))
            dr = cr = 0.0
            for x in rows:
                seq += 1
                x["EXTRACT_DT"] = R
                x["FILE_SEQ_NR"] = seq
                out.append(self.raw_line(x))
                if x["DR_CR_IND"] == "D":
                    dr += abs(round(x["TXN_AMT"], 2))
                else:
                    cr += abs(round(x["TXN_AMT"], 2))
            out.append(("T" + fw(sup, 4) + fw(file_id, 20) + ymd(R) + fw(f"{len(rows):010d}", 10)
                        + fw(f"{dr:.2f}", 18) + fw(f"{cr:.2f}", 18) + created).ljust(width))
            totals.append(dict(FILE_ID=file_id, SUPPLIER_CD=sup, EXTRACT_DT=R, REC_CNT=len(rows),
                               DR_TOTAL=f"{dr:.2f}", CR_TOTAL=f"{cr:.2f}"))
        with open(self.path("landing", "dailytxn.dat"), "w", newline="\n") as f:
            for line in out:
                assert len(line) == width, (len(line), width)
                f.write(line + "\n")
        self.ctrl_totals = totals
        self.daily_width = width

    # ------------------------------------------------------------------ seeds
    def write_csv(self, name, cols, rows):
        with open(self.path("seed", name + ".csv"), "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(cols)
            for row in rows:
                out = []
                for c in cols:
                    v = row.get(c)
                    if v is None:
                        out.append("")
                    elif isinstance(v, dt.datetime):
                        out.append(v.strftime("%Y-%m-%d %H:%M:%S"))
                    elif isinstance(v, dt.date):
                        out.append(v.isoformat())
                    elif isinstance(v, float):
                        out.append(f"{v:.8f}".rstrip("0").rstrip(".") if c.endswith("RATE") else f"{v:.2f}")
                    else:
                        out.append(str(v))
                w.writerow(out)

    def write_seeds(self):
        R = self.run
        tms = dt.datetime.combine(R - ONE, dt.time(6, 0))
        # --- DB_REFERENCE static seeds
        self.write_csv("DB_REFERENCE.NAME_NOISE_WORD", ["NOISE_WORD", "WORD_TYP_CD"],
                       [dict(NOISE_WORD=w, WORD_TYP_CD=t) for w, t in NOISE_WORDS])
        xref = {}
        for c in COUNTRIES:
            xref[c[2].upper()] = c[0]
        xref.update({"NORTH KOREA": "KP", "DEMOCRATIC PEOPLE'S REPUBLIC OF KOREA": "KP", "DPRK": "KP",
                     "RUSSIAN FEDERATION": "RU", "IRAN (ISLAMIC REPUBLIC OF)": "IR", "SYRIAN ARAB REPUBLIC": "SY",
                     "UAE": "AE", "UNITED STATES OF AMERICA": "US", "UK": "GB", "TURKIYE": "TR", "BURMA": "MM"})
        self.write_csv("DB_REFERENCE.CTRY_NAME_XREF", ["CTRY_NM_TXT", "CTRY_2_CD"],
                       [dict(CTRY_NM_TXT=k, CTRY_2_CD=v) for k, v in sorted(xref.items())])
        self.write_csv("DB_REFERENCE.SANC_REGIME_CTRY", ["REGIME_NM", "CTRY_2_CD", "COMPREHENSIVE_IND"], [
            dict(REGIME_NM="Democratic People's Republic of Korea", CTRY_2_CD="KP", COMPREHENSIVE_IND="Y"),
            dict(REGIME_NM="Iran", CTRY_2_CD="IR", COMPREHENSIVE_IND="Y"),
            dict(REGIME_NM="Syria", CTRY_2_CD="SY", COMPREHENSIVE_IND="Y"),
            dict(REGIME_NM="Russia", CTRY_2_CD="RU", COMPREHENSIVE_IND="N"),
            dict(REGIME_NM="Belarus", CTRY_2_CD="BY", COMPREHENSIVE_IND="N"),
            dict(REGIME_NM="Libya", CTRY_2_CD="LY", COMPREHENSIVE_IND="N"),
            dict(REGIME_NM="Myanmar", CTRY_2_CD="MM", COMPREHENSIVE_IND="N")])
        rfw = [("RESCTRY", "L", 0), ("RESCTRY", "M", 10), ("RESCTRY", "H", 30), ("RESCTRY", "X", 60), ("RESCTRY", "UNKNOWN", 15),
               ("NATCTRY", "L", 0), ("NATCTRY", "M", 5), ("NATCTRY", "H", 20), ("NATCTRY", "X", 40), ("NATCTRY", "UNKNOWN", 10),
               ("PEP", "DO", 30), ("PEP", "FO", 40), ("PEP", "IO", 30), ("PEP", "RC", 20), ("PEP", "NONE", 0),
               ("OCCP", "L", 0), ("OCCP", "M", 10), ("OCCP", "H", 25), ("OCCP", "UNKNOWN", 10),
               ("PRDT", "L", 0), ("PRDT", "M", 5), ("PRDT", "H", 15), ("PRDT", "UNKNOWN", 5),
               ("CHNL", "F2F", 0), ("CHNL", "NFTF", 5),
               ("ALERTS", "0", 0), ("ALERTS", "1-2", 10), ("ALERTS", "3-5", 20), ("ALERTS", "6+", 35),
               ("SANC", "OPEN", 60), ("SANC", "NONE", 0),
               ("KYC", "OVERDUE", 15), ("KYC", "VE", 0), ("KYC", "PE", 10), ("KYC", "EX", 15), ("KYC", "RF", 40),
               ("ADVMEDIA", "Y", 25), ("ADVMEDIA", "N", 0)]
        desc = {"RESCTRY": "Country of residence risk", "NATCTRY": "Nationality risk", "PEP": "Politically exposed person",
                "OCCP": "Occupation / industry risk", "PRDT": "Highest product risk held", "CHNL": "Onboarding channel",
                "ALERTS": "TM alerts in last 90 days", "SANC": "Open sanctions screening hit", "KYC": "KYC status",
                "ADVMEDIA": "Adverse media"}
        self.write_csv("DB_REFERENCE.RISK_FACTOR_WEIGHT", ["FACTOR_CD", "FACTOR_VALUE_CD", "SCORE_PTS", "FACTOR_DESC"],
                       [dict(FACTOR_CD=a, FACTOR_VALUE_CD=b, SCORE_PTS=c, FACTOR_DESC=desc[a]) for a, b, c in rfw])
        self.write_csv("DB_REFERENCE.RISK_BAND", ["RISK_BAND_CD", "MIN_SCORE", "MAX_SCORE", "RISK_BAND_DESC", "REVIEW_FREQ_MTHS", "CDD_LEVEL_CD"], [
            dict(RISK_BAND_CD="L", MIN_SCORE=0, MAX_SCORE=24, RISK_BAND_DESC="Low", REVIEW_FREQ_MTHS=36, CDD_LEVEL_CD="SDD"),
            dict(RISK_BAND_CD="M", MIN_SCORE=25, MAX_SCORE=49, RISK_BAND_DESC="Medium", REVIEW_FREQ_MTHS=24, CDD_LEVEL_CD="CDD"),
            dict(RISK_BAND_CD="H", MIN_SCORE=50, MAX_SCORE=79, RISK_BAND_DESC="High", REVIEW_FREQ_MTHS=12, CDD_LEVEL_CD="EDD"),
            dict(RISK_BAND_CD="VH", MIN_SCORE=80, MAX_SCORE=999, RISK_BAND_DESC="Very high", REVIEW_FREQ_MTHS=6, CDD_LEVEL_CD="EDD")])
        q = []
        for seg, nm in (("RET", "Retail"), ("BUS", "Business"), ("CIB", "Corporate"), ("WLT", "Wealth")):
            q.append(dict(QUEUE_CD=f"{seg}P1", QUEUE_NM=f"{nm} - priority investigations", SEGMENT_CD=seg, MIN_PRIORITY_NR=1, MAX_PRIORITY_NR=2, SLA_BUS_DAYS=5))
            q.append(dict(QUEUE_CD=f"{seg}STD", QUEUE_NM=f"{nm} - standard investigations", SEGMENT_CD=seg, MIN_PRIORITY_NR=3, MAX_PRIORITY_NR=5, SLA_BUS_DAYS=20))
        q.append(dict(QUEUE_CD="AMLGEN", QUEUE_NM="AML general queue", SEGMENT_CD="ALL", MIN_PRIORITY_NR=1, MAX_PRIORITY_NR=5, SLA_BUS_DAYS=20))
        self.write_csv("DB_REFERENCE.CASE_QUEUE", ["QUEUE_CD", "QUEUE_NM", "SEGMENT_CD", "MIN_PRIORITY_NR", "MAX_PRIORITY_NR", "SLA_BUS_DAYS"], q)
        self.write_csv("DB_REFERENCE.UK_BANK_HOLIDAY", ["HOLIDAY_DT", "HOLIDAY_NM"],
                       [dict(HOLIDAY_DT=k, HOLIDAY_NM=v) for k, v in sorted(self.holidays.items()) if 2020 <= k.year <= 2030])
        cal = []
        d = D(1920, 1, 1)
        while d <= D(2030, 12, 31):
            nxt = d + ONE
            cal.append(dict(CAL_DT=d, BUS_DAY_IND="Y" if self.bus_day(d) else "N", YR_MON=d.year * 100 + d.month,
                            YR_NR=d.year, MTH_NR=d.month, DAY_OF_WK_NR=(d.isoweekday() % 7) + 1,
                            MTH_END_IND="Y" if nxt.month != d.month else "N"))
            d = nxt
        self.write_csv("DB_REFERENCE.CALENDAR", ["CAL_DT", "BUS_DAY_IND", "YR_MON", "YR_NR", "MTH_NR", "DAY_OF_WK_NR", "MTH_END_IND"], cal)
        vac = []
        for u, segs, pii, sar in (("AML_ANALYST_RET", ["RET", "UNK"], "Y", "N"), ("AML_ANALYST_CORP", ["BUS", "CIB"], "Y", "N"),
                                  ("AML_ANALYST_WLT", ["WLT"], "Y", "N"), ("MLRO", SEGMENTS + ["UNK"], "Y", "Y"),
                                  ("MI_REPORTING", SEGMENTS + ["UNK"], "N", "N"), ("DEMO_USER", SEGMENTS + ["UNK"], "Y", "Y")):
            for s in segs:
                vac.append(dict(USER_NM=u, SEGMENT_CD=s, PII_ACCESS_IND=pii, SAR_ACCESS_IND=sar))
        self.write_csv("DB_REFERENCE.VIEW_ACCESS_CTRL", ["USER_NM", "SEGMENT_CD", "PII_ACCESS_IND", "SAR_ACCESS_IND"], vac)
        self.write_csv("DB_REFERENCE.BIC_DIRECTORY", ["BIC_CD", "BANK_NM", "CTRY_2_CD", "AUTO_ADDED_IND", "CO_UPD_TMS"],
                       [dict(BIC_CD=OWN_BIC, BANK_NM=OWN_BANK, CTRY_2_CD="GB", AUTO_ADDED_IND="N", CO_UPD_TMS=tms)] +
                       [dict(BIC_CD=b + "XXX", BANK_NM=n, CTRY_2_CD="GB", AUTO_ADDED_IND="N", CO_UPD_TMS=tms) for n, b in PEER_BANKS] +
                       [dict(BIC_CD=s[3], BANK_NM=s[2].upper() + " BANK", CTRY_2_CD=s[0], AUTO_ADDED_IND="N", CO_UPD_TMS=tms) for s in INTL_SUPPLIERS])
        self.write_csv("DB_REFERENCE.RETURN_REASON", ["RETURN_REASON_CD", "RETURN_REASON_DESC", "AUTO_ADDED_IND", "CO_UPD_TMS"],
                       [dict(RETURN_REASON_CD=c, RETURN_REASON_DESC=t, AUTO_ADDED_IND="N", CO_UPD_TMS=tms) for c, t in
                        (("AC01", "Incorrect account number"), ("AC04", "Closed account number"), ("AC06", "Blocked account"),
                         ("AM04", "Insufficient funds"), ("MD07", "End customer deceased"), ("FOCR", "Return following cancellation request"),
                         ("FR01", "Fraud"), ("RR04", "Regulatory reason"))])
        # --- transaction history (prior runs of dailytxn.10)
        fact_cols = [c.split()[0] for c in FINAL_COLS.strip().splitlines()]
        self.write_csv("DB_ODS.AML_TXN_DAILY", fact_cols, self.fact)
        # --- counterparties known before the run date
        hist_cpty = [c for c in self.cpty.values() if c["FIRST_SEEN_DT"] < R]
        for c in hist_cpty:
            c["CO_UPD_TMS"] = dt.datetime.combine(c["LAST_SEEN_DT"] + ONE, dt.time(5, 30))
        self.write_csv("DB_ODS.CPTY", ["CPTY_ID", "CPTY_ACCT_KEY", "CPTY_NORM_NM", "CPTY_BIC_CD", "CPTY_CTRY_CD",
                                       "FIRST_SEEN_DT", "LAST_SEEN_DT", "TXN_CNT", "CO_UPD_TMS"], sorted(hist_cpty, key=lambda c: c["CPTY_ID"]))
        # --- account daily summary history (prior runs of amlmon.15)
        self.summ = self.summarise(self.fact)
        self.write_csv("DB_AML.ACCT_DAILY_SUMM", SUMM_COLS, self.summ.values())
        # --- prior alerts / cases (prior runs of amlmon.20 / .40), excluding planted parties
        self.write_prior_alerts()

    def summarise(self, fact):
        out = {}
        for f in fact:
            if f["REVERSAL_IND"] == "Y" or f["TXN_STATUS_CD"] in ("RJ", "RV") or f["GBP_AMT"] is None:
                continue
            k = (f["ACCT_ID"], f["BOOKING_DT"])
            s = out.get(k)
            if s is None:
                s = out[k] = dict(ACCT_ID=f["ACCT_ID"], BUSINESS_DT=f["BOOKING_DT"], PARTY_ID=f["PARTY_ID"],
                                  SEGMENT_CD=f["SEGMENT_CD"] or "RET", **{c: 0 for c in SUMM_COLS[4:-1]},
                                  _cc=set(), _cd=set(),
                                  CO_UPD_TMS=dt.datetime.combine(f["BOOKING_DT"] + ONE, dt.time(6, 10)))
                for c in SUMM_COLS[4:-1]:
                    if c.endswith("AMT"):
                        s[c] = 0.0
            g = abs(f["GBP_AMT"])
            cr, cash = f["DR_CR_IND"] == "C", f["CASH_IND"] == "Y"
            stp = rule_param("TM_STR01", f["SEGMENT_CD"] if f["SEGMENT_CD"] in SEGMENTS else "RET")
            if cr:
                s["CR_CNT"] += 1; s["CR_GBP_AMT"] += g
                if f["CPTY_ID"]:
                    s["_cc"].add(f["CPTY_ID"])
            else:
                s["DR_CNT"] += 1; s["DR_GBP_AMT"] += g
                if f["CPTY_ID"]:
                    s["_cd"].add(f["CPTY_ID"])
            if cash and cr:
                s["CASH_CR_CNT"] += 1; s["CASH_CR_GBP_AMT"] += g
                if stp["amt"] * stp["pct"] / 100 <= g < stp["amt"]:
                    s["NEAR_THRESHOLD_CASH_CNT"] += 1
            if cash and not cr:
                s["CASH_DR_CNT"] += 1; s["CASH_DR_GBP_AMT"] += g
            if f["XBORDER_IND"] == "Y":
                s["XBORDER_CNT"] += 1; s["XBORDER_GBP_AMT"] += g
            if f["HRC_IND"] == "Y":
                s["HRC_CNT"] += 1; s["HRC_GBP_AMT"] += g
            if f["ROUND_AMT_IND"] == "Y":
                s["ROUND_AMT_CNT"] += 1
            s["MAX_TXN_GBP_AMT"] = max(s["MAX_TXN_GBP_AMT"], g)
            m = MCC.get(f["MCC_CD"])
            if m and not cr and m[4] == "Y":
                s["GAMBLING_GBP_AMT"] += g
            if m and not cr and m[5] == "Y":
                s["CRYPTO_GBP_AMT"] += g
        for s in out.values():
            s["DISTINCT_CPTY_CR_CNT"] = len(s.pop("_cc"))
            s["DISTINCT_CPTY_DR_CNT"] = len(s.pop("_cd"))
            for c in SUMM_COLS:
                if c.endswith("AMT"):
                    s[c] = round(s[c], 2)
        return out

    def write_prior_alerts(self):
        r, R = self.r, self.run
        planted_parties = {s["PARTY_ID"] for s in self.scen}
        cands = [a for a in self.accts.values() if a["profile"] == "std" and a["PRIMARY_PARTY_ID"] not in planted_parties]
        rules = [x for x in {ru[0] for ru in RULES} if x not in ("TM_SAN01", "TM_MUL01", "TM_DRM01")]
        alerts, cases, xref, hist, sars, alert_txn = [], [], [], [], [], []
        aid, cid = 7000000, 300000
        by_party = defaultdict(list)
        for _ in range(140):
            a = r.choice(cands)
            d = self.prev_bus(R - r.randint(2, 75) * ONE)
            rule = r.choice(rules)
            aid += 1
            prm = rule_param(rule, a["SEGMENT_CD"])
            al = dict(ALERT_ID=aid, RULE_CD=rule, PARTY_ID=a["PRIMARY_PARTY_ID"], ACCT_ID=a["ACCT_ID"], BUSINESS_DT=d,
                      ALERT_TMS=dt.datetime.combine(d + ONE, dt.time(6, 40)), ALERT_SCORE=min(100, prm["w"] + r.randint(-10, 30)),
                      HIT_GBP_AMT=round(r.uniform(3000, 60000), 2), HIT_CNT=r.randint(1, 8),
                      LOOKBACK_START_DT=d - (prm["lb"] - 1) * ONE, LOOKBACK_END_DT=d, TRIGGER_TXN_REF=None,
                      TRIGGER_SUPPLIER_CD=None, ALERT_STATUS_CD="NEW", SUPPRESS_REASON_CD=None, CASE_ID=None,
                      HIT_DETAIL=f"{rule} PRIOR RUN ALERT (SEEDED HISTORY)", CO_UPD_TMS=dt.datetime.combine(d + ONE, dt.time(6, 40)))
            alerts.append(al)
            by_party[a["PRIMARY_PARTY_ID"]].append(al)
        for pid, als in by_party.items():
            als.sort(key=lambda x: x["BUSINESS_DT"])
            cid += 1
            first, last = als[0]["BUSINESS_DT"], als[-1]["BUSINESS_DT"]
            age = (R - last).days
            status = "CLOSD" if age > 45 and r.random() < 0.8 else r.choices(["OPEN", "INVST", "ESCAL", "SARFL", "CLOSD"], [25, 35, 10, 8, 22])[0]
            seg = self.parties[pid]["SEGMENT_CD"]
            prio = r.randint(1, 5)
            queue = f"{seg}P1" if prio <= 2 else f"{seg}STD"
            sla = self.add_bus_days(first + ONE, 5 if prio <= 2 else 20)
            close_dt = min(R - ONE, last + r.randint(5, 30) * ONE) if status == "CLOSD" else None
            tot = round(sum(x["HIT_GBP_AMT"] for x in als), 2)
            case = dict(CASE_ID=cid, PARTY_ID=pid, CASE_OPEN_DT=first + ONE, CASE_STATUS_CD=status, CASE_PRIORITY_NR=prio,
                        QUEUE_CD=queue, SLA_DUE_DT=sla, ALERT_CNT=len(als), TOTAL_ALERT_SCORE=sum(x["ALERT_SCORE"] for x in als),
                        TOTAL_HIT_GBP_AMT=tot, RULE_LIST=",".join(sorted({x["RULE_CD"] for x in als})),
                        SAR_CANDIDATE_IND="Y" if status == "SARFL" else "N",
                        RISK_BAND_CD=r.choice(["M", "H", "H", "VH"]) if status in ("ESCAL", "SARFL") else r.choice(["L", "M", "M", "H"]),
                        SEGMENT_CD=seg, FIRST_ALERT_DT=first, LAST_ALERT_DT=last, CASE_CLOSE_DT=close_dt,
                        CLOSE_REASON_CD=("NFA" if r.random() < 0.85 else "SARF") if status == "CLOSD" else None,
                        CO_UPD_TMS=dt.datetime.combine(close_dt or (last + ONE), dt.time(7, 0)))
            cases.append(case)
            hist.append(dict(case, UPD_TMS=dt.datetime.combine(first + ONE, dt.time(7, 0)), HIST_ACTION_CD="I"))
            for x in als:
                x["CASE_ID"] = cid
                x["ALERT_STATUS_CD"] = "CLOSD" if status == "CLOSD" else "CASED"
                xref.append(dict(CASE_ID=cid, ALERT_ID=x["ALERT_ID"], ADDED_DT=x["BUSINESS_DT"] + ONE,
                                 CO_UPD_TMS=dt.datetime.combine(x["BUSINESS_DT"] + ONE, dt.time(7, 0))))
            if status == "SARFL":
                sars.append(dict(CASE_ID=cid, PARTY_ID=pid, IDENT_DT=last + ONE, SAR_REASON_CD=als[0]["RULE_CD"][3:7],
                                 TOTAL_GBP_AMT=tot, SANC_HIT_IND="N", DAML_IND="N",
                                 NARRATIVE_SUMMARY=f"{len(als)} ALERT(S) {case['RULE_LIST']} TOTAL GBP {tot:,.2f} (SEEDED HISTORY)",
                                 SAR_STATUS_CD=r.choice(["DRAFT", "SUBMT"]), CO_UPD_TMS=dt.datetime.combine(last + ONE, dt.time(7, 0))))
        # S17: open alert + case for the suppression scenario
        p, a, d = self.suppress_seed
        aid += 1; cid += 1
        alerts.append(dict(ALERT_ID=aid, RULE_CD="TM_RND01", PARTY_ID=p["PARTY_ID"], ACCT_ID=a["ACCT_ID"], BUSINESS_DT=d,
                           ALERT_TMS=dt.datetime.combine(d + ONE, dt.time(6, 40)), ALERT_SCORE=48, HIT_GBP_AMT=24000.00, HIT_CNT=5,
                           LOOKBACK_START_DT=d - 29 * ONE, LOOKBACK_END_DT=d, TRIGGER_TXN_REF=None, TRIGGER_SUPPLIER_CD=None,
                           ALERT_STATUS_CD="CASED", SUPPRESS_REASON_CD=None, CASE_ID=cid,
                           HIT_DETAIL="TM_RND01 PRIOR RUN ALERT (SEEDED HISTORY)", CO_UPD_TMS=dt.datetime.combine(d + ONE, dt.time(6, 40))))
        case = dict(CASE_ID=cid, PARTY_ID=p["PARTY_ID"], CASE_OPEN_DT=d + ONE, CASE_STATUS_CD="INVST", CASE_PRIORITY_NR=4,
                    QUEUE_CD="BUSSTD", SLA_DUE_DT=self.add_bus_days(d + ONE, 20), ALERT_CNT=1, TOTAL_ALERT_SCORE=48,
                    TOTAL_HIT_GBP_AMT=24000.00, RULE_LIST="TM_RND01", SAR_CANDIDATE_IND="N", RISK_BAND_CD="M", SEGMENT_CD="BUS",
                    FIRST_ALERT_DT=d, LAST_ALERT_DT=d, CASE_CLOSE_DT=None, CLOSE_REASON_CD=None,
                    CO_UPD_TMS=dt.datetime.combine(d + ONE, dt.time(7, 0)))
        cases.append(case)
        hist.append(dict(case, UPD_TMS=dt.datetime.combine(d + ONE, dt.time(7, 0)), HIST_ACTION_CD="I"))
        xref.append(dict(CASE_ID=cid, ALERT_ID=aid, ADDED_DT=d + ONE, CO_UPD_TMS=dt.datetime.combine(d + ONE, dt.time(7, 0))))
        self.prior_alerts = alerts
        ac = ["ALERT_ID", "RULE_CD", "PARTY_ID", "ACCT_ID", "BUSINESS_DT", "ALERT_TMS", "ALERT_SCORE", "HIT_GBP_AMT", "HIT_CNT",
              "LOOKBACK_START_DT", "LOOKBACK_END_DT", "TRIGGER_TXN_REF", "TRIGGER_SUPPLIER_CD", "ALERT_STATUS_CD",
              "SUPPRESS_REASON_CD", "CASE_ID", "HIT_DETAIL", "CO_UPD_TMS"]
        cc = ["CASE_ID", "PARTY_ID", "CASE_OPEN_DT", "CASE_STATUS_CD", "CASE_PRIORITY_NR", "QUEUE_CD", "SLA_DUE_DT", "ALERT_CNT",
              "TOTAL_ALERT_SCORE", "TOTAL_HIT_GBP_AMT", "RULE_LIST", "SAR_CANDIDATE_IND", "RISK_BAND_CD", "SEGMENT_CD",
              "FIRST_ALERT_DT", "LAST_ALERT_DT", "CASE_CLOSE_DT", "CLOSE_REASON_CD", "CO_UPD_TMS"]
        self.write_csv("DB_AML.TM_ALERT", ac, alerts)
        self.write_csv("DB_AML.AML_CASE", cc, cases)
        self.write_csv("DB_AML.AML_CASE_HIST", ["CASE_ID", "UPD_TMS"] + cc[1:-1] + ["HIST_ACTION_CD", "CO_UPD_TMS"], hist)
        self.write_csv("DB_AML.AML_CASE_ALERT_XREF", ["CASE_ID", "ALERT_ID", "ADDED_DT", "CO_UPD_TMS"], xref)
        self.write_csv("DB_AML.SAR_CANDIDATE", ["CASE_ID", "PARTY_ID", "IDENT_DT", "SAR_REASON_CD", "TOTAL_GBP_AMT", "SANC_HIT_IND",
                                                "DAML_IND", "NARRATIVE_SUMMARY", "SAR_STATUS_CD", "CO_UPD_TMS"], sars)

    def add_bus_days(self, d, n):
        while not self.bus_day(d):
            d += ONE
        k = 0
        while k < n:
            d += ONE
            if self.bus_day(d):
                k += 1
        return d

    # ------------------------------------------------------------------ expected results
    def simulate_run_day(self):
        """Apply dailytxn.03 dedupe / restart / reversal logic and dailytxn.10 enrichment."""
        R = self.run
        hist_by_ref = {(f["TXN_REF"], f["SUPPLIER_CD"]): f for f in self.fact}
        loaded = []
        for x in self.daily:
            loaded.append(x)
        for t in self.resends:
            pass                                       # identical to history -> PD, dropped
        fact = {k: dict(v) for k, v in hist_by_ref.items()}
        sc = self.status_change
        fact[(sc["TXN_REF"], sc["SUPPLIER_CD"])]["TXN_STATUS_CD"] = "RJ"
        rv, o = self.reversal
        fact[(o["TXN_REF"], o["SUPPLIER_CD"])]["TXN_STATUS_CD"] = "RV"
        # placeholder accounts: segment UNK
        for x in loaded:
            f = self.enrich(x)
            f["LOAD_TMS"] = f["CO_UPD_TMS"] = dt.datetime.combine(R + ONE, dt.time(5, 30))
            fact[(f["TXN_REF"], f["SUPPLIER_CD"])] = f
        return list(fact.values())

    def screen(self, run_fact):
        names_by_norm = defaultdict(list)
        tok_index = defaultdict(set)
        for n in self.sanc_names:
            names_by_norm[n["NORM_NM"]].append(n)
            if n["QUAL"] != "L":
                for t in n["TOKENS"]:
                    tok_index[t].add(id(n))
        by_id = {id(n): n for n in self.sanc_names}
        comp = {"KP", "IR", "SY"}
        hits = []
        for f in run_fact:
            if f["BOOKING_DT"] != self.run or f["LOAD_TMS"].date() != self.run + ONE:
                continue
            roles = [("CP", f["CPTY_NM"]), ("OR", f["ORDERING_CUST_NM"]), ("BE", f["BENEF_CUST_NM"]), ("MR", f["MERCHANT_NM"])]
            seen = set()
            for role, nm in roles:
                if not nm:
                    continue
                nn = norm(nm)
                toks = set(tokens(nm))
                best = {}
                for n in names_by_norm.get(nn, []):
                    best[n["GROUP_ID"]] = max(best.get(n["GROUP_ID"], ("", 0)), ("EXACT", 100.0), key=lambda z: z[1])
                cand = Counter()
                for t in toks:
                    for i in tok_index.get(t, ()):
                        cand[i] += 1
                for i, m in cand.items():
                    n = by_id[i]
                    if m >= 2 and m / len(n["TOKENS"]) >= 0.75:
                        sc = round(100.0 * m / len(n["TOKENS"]), 2)
                        if n["GROUP_ID"] not in best or best[n["GROUP_ID"]][1] < sc:
                            best[n["GROUP_ID"]] = ("TOKEN", sc)
                for g, (mt, sc) in best.items():
                    if (role, g) not in seen:
                        seen.add((role, g))
                        hits.append(dict(TXN_REF=f["TXN_REF"], SUPPLIER_CD=f["SUPPLIER_CD"], ACCT_ID=f["ACCT_ID"],
                                         NM_ROLE_CD=role, SCREENED_NM=nm, GROUP_ID=g, MATCH_TYP_CD=mt, MATCH_SCORE=sc))
            for cc in {f["CPTY_CTRY_CD"], f["CPTY_BANK_CTRY_CD"]} & comp:
                hits.append(dict(TXN_REF=f["TXN_REF"], SUPPLIER_CD=f["SUPPLIER_CD"], ACCT_ID=f["ACCT_ID"], NM_ROLE_CD="CP",
                                 SCREENED_NM=f["CPTY_NM"], GROUP_ID=-1, MATCH_TYP_CD="CTRY", MATCH_SCORE=100.0, CTRY=cc))
            for b in {f["CPTY_BIC_CD"][:8] if f["CPTY_BIC_CD"] else None, f["INTERMED_BIC_CD"][:8] if f["INTERMED_BIC_CD"] else None}:
                if b and b in self.sanc_bics:
                    hits.append(dict(TXN_REF=f["TXN_REF"], SUPPLIER_CD=f["SUPPLIER_CD"], ACCT_ID=f["ACCT_ID"], NM_ROLE_CD="CP",
                                     SCREENED_NM=f["CPTY_NM"], GROUP_ID=self.sanc_bics[b], MATCH_TYP_CD="BIC", MATCH_SCORE=100.0))
        return hits

    def simulate_rules(self, fact, hits):
        R = self.run
        acct_seg = {a: v["SEGMENT_CD"] for a, v in self.accts.items()}
        txns = [f for f in fact if f["REVERSAL_IND"] != "Y" and f["TXN_STATUS_CD"] not in ("RJ", "RV")
                and f["GBP_AMT"] is not None and f["BOOKING_DT"] >= R - 120 * ONE]
        by_acct = defaultdict(list)
        for f in txns:
            f = dict(f, SEG=acct_seg.get(f["ACCT_ID"], "UNK"), G=abs(f["GBP_AMT"]))
            by_acct[f["ACCT_ID"]].append(f)
        summ = self.summarise([f for f in fact if f["BOOKING_DT"] <= R])
        s_by_acct = defaultdict(dict)
        for (a, d), s in summ.items():
            s_by_acct[a][d] = s
        res = []

        def window(rule, seg):
            p = rule_param(rule, seg)
            return p, (R - (p["lb"] - 1) * ONE if p else None)

        for a, ts in by_acct.items():
            seg = acct_seg.get(a, "UNK")
            if seg not in SEGMENTS:
                continue
            acct = self.accts[a]
            party = self.parties[acct["PRIMARY_PARTY_ID"]]
            p, ws = window("TM_STR01", seg)
            sel = [t for t in ts if ws <= t["BOOKING_DT"] <= R and t["DR_CR_IND"] == "C" and t["CASH_IND"] == "Y"
                   and p["amt"] * p["pct"] / 100 <= t["G"] < p["amt"]]
            if len(sel) >= p["cnt"] and sum(t["G"] for t in sel) > p["amt"] and max(t["BOOKING_DT"] for t in sel) == R:
                res.append(("TM_STR01", a, sum(t["G"] for t in sel), len(sel)))
            # RPM
            p, ws = window("TM_RPM01", seg)
            days = {d: s for d, s in s_by_acct[a].items() if ws <= d <= R}
            if days:
                cr = sum(s["CR_GBP_AMT"] for s in days.values())
                moved = 0.0
                for d, s in days.items():
                    cr3 = sum(s_by_acct[a][dd]["CR_GBP_AMT"] for dd in (d - 2 * ONE, d - ONE, d) if dd in s_by_acct[a])
                    moved += min(s["DR_GBP_AMT"], cr3)
                if cr > p["amt"] and moved * 100 >= cr * p["pct"] and R in days and days[R]["DR_GBP_AMT"] > 0:
                    res.append(("TM_RPM01", a, cr, 0))
            for rule, flt in (("TM_HRC01", lambda t: t["HRC_IND"] == "Y"),
                              ("TM_GMB01", lambda t: t["DR_CR_IND"] == "D" and t["MCC_CD"] in MCC and (MCC[t["MCC_CD"]][4] == "Y" or MCC[t["MCC_CD"]][5] == "Y")),
                              ("TM_CSH01", lambda t: t["DR_CR_IND"] == "C" and t["CASH_IND"] == "Y" and SIC.get(party["SIC_CD"], ("", "", "", "N"))[3] != "Y")):
                p, ws = window(rule, seg)
                sel = [t for t in ts if ws <= t["BOOKING_DT"] <= R and flt(t)]
                if sel and sum(t["G"] for t in sel) > p["amt"] and max(t["BOOKING_DT"] for t in sel) == R:
                    res.append((rule, a, sum(t["G"] for t in sel), len(sel)))
            p, ws = window("TM_RND01", seg)
            sel = [t for t in ts if ws <= t["BOOKING_DT"] <= R and t["ROUND_AMT_IND"] == "Y"]
            if len(sel) >= p["cnt"] and sum(t["G"] for t in sel) >= p["amt"] and max(t["BOOKING_DT"] for t in sel) == R:
                res.append(("TM_RND01", a, sum(t["G"] for t in sel), len(sel)))
            p, ws = window("TM_PEP01", seg)
            if party["PEP_IND"] == "Y":
                sel = [t for t in ts if ws <= t["BOOKING_DT"] <= R and t["G"] > p["amt"]]
                if sel and max(t["BOOKING_DT"] for t in sel) == R:
                    res.append(("TM_PEP01", a, max(t["G"] for t in sel), len(sel)))
            # profile based
            sm = s_by_acct[a].get(R)
            if sm:
                prev = [d for d, s in s_by_acct[a].items() if d < R and s["CR_CNT"] + s["DR_CNT"] > 0]
                last = acct["LAST_CUST_ACTV_DT"] if acct["LAST_CUST_ACTV_DT"] < R else None
                dsp = (R - (max(prev) if prev else (last or acct["OPEN_DT"] or R))).days
                p = rule_param("TM_DRM01", seg)
                if (dsp >= p["cnt"] or acct["ACCT_STATUS_CD"] == "D") and sm["CR_GBP_AMT"] + sm["DR_GBP_AMT"] > p["amt"]:
                    res.append(("TM_DRM01", a, sm["CR_GBP_AMT"] + sm["DR_GBP_AMT"], dsp))
                roll30 = sum(s["CR_GBP_AMT"] for d, s in s_by_acct[a].items() if R - 29 * ONE <= d <= R)
                prior = sum(s["CR_GBP_AMT"] for d, s in s_by_acct[a].items() if R - 120 * ONE <= d <= R - 31 * ONE) / 3
                if sm["CR_CNT"] > 0:
                    p = rule_param("TM_VEL01", seg)
                    if prior > 0 and roll30 / prior >= p["pct"] / 100 and roll30 > p["amt"]:
                        res.append(("TM_VEL01", a, roll30, 0))
                    p = rule_param("TM_TOV01", seg)
                    if party["EXP_MTH_TURNOVER_AMT"] > 0 and roll30 * 100 > party["EXP_MTH_TURNOVER_AMT"] * p["pct"] and roll30 > p["amt"]:
                        res.append(("TM_TOV01", a, roll30, 0))
            if seg == "RET":
                p = rule_param("TM_MUL01", seg)
                sel = [t for t in ts if R - 2 * ONE <= t["BOOKING_DT"] <= R and t["DR_CR_IND"] == "C" and t["CPTY_ID"]]
                if acct["OPEN_DT"] > R - p["lb"] * ONE and sel and len({t["CPTY_ID"] for t in sel}) >= p["cnt"] \
                        and sum(t["G"] for t in sel) > p["amt"] and max(t["BOOKING_DT"] for t in sel) == R:
                    res.append(("TM_MUL01", a, sum(t["G"] for t in sel), len({t["CPTY_ID"] for t in sel})))
        for a in sorted({h["ACCT_ID"] for h in hits if h["ACCT_ID"]}):
            if acct_seg.get(a) in SEGMENTS:
                res.append(("TM_SAN01", a, 0.0, len([h for h in hits if h["ACCT_ID"] == a])))
        # suppression against seeded prior alerts
        prior = {(al["RULE_CD"], al["ACCT_ID"]) for al in self.prior_alerts
                 if R - 30 * ONE <= al["BUSINESS_DT"] <= R - ONE and al["ALERT_STATUS_CD"] != "CLOSD"}
        out = []
        for rule, a, amt, cnt in sorted(res, key=lambda z: (z[0], z[1])):
            acct = self.accts[a]
            sc = next((s["SCENARIO_ID"] for s in self.scen if s["ACCT_ID"] == a), "")
            out.append(dict(RULE_CD=rule, ACCT_ID=a, PARTY_ID=acct["PRIMARY_PARTY_ID"], SEGMENT_CD=acct["SEGMENT_CD"],
                            BUSINESS_DT=R, HIT_GBP_AMT=f"{amt:.2f}", HIT_CNT=cnt,
                            EXPECTED_STATUS="SUPPR" if (rule, a) in prior else "NEW", SCENARIO_ID=sc or "BACKGROUND"))
        return out

    def write_expected(self):
        R = self.run
        run_fact = self.simulate_run_day()
        hits = self.screen(run_fact)
        alerts = self.simulate_rules(run_fact, hits)
        self.write_csv_x("scenario_manifest", ["SCENARIO_ID", "EXPECTED_RULES", "PARTY_ID", "PARTY_NM", "SEGMENT_CD", "ACCT_ID", "DESCRIPTION"], self.scen)
        self.write_csv_x("expected_alerts", ["RULE_CD", "ACCT_ID", "PARTY_ID", "SEGMENT_CD", "BUSINESS_DT", "HIT_GBP_AMT", "HIT_CNT", "EXPECTED_STATUS", "SCENARIO_ID"], alerts)
        g2 = {e["GROUP_ID"]: e for e in self.sanc_entities}
        for h in hits:
            e = g2.get(h["GROUP_ID"])
            h["REGIME_NM"] = e["REGIME"] if e else "COUNTRY: " + h.get("CTRY", "")
            h["SCENARIO_ID"] = next((s["SCENARIO_ID"] for s in self.scen if s["ACCT_ID"] == h["ACCT_ID"]), "BACKGROUND")
        self.write_csv_x("expected_screening_hits", ["TXN_REF", "SUPPLIER_CD", "ACCT_ID", "NM_ROLE_CD", "SCREENED_NM", "GROUP_ID", "REGIME_NM", "MATCH_TYP_CD", "MATCH_SCORE", "SCENARIO_ID"], hits)
        self.write_csv_x("expected_dq_daily", ["CHECK", "KEY", "EXPECTED"], self.dq)
        self.write_csv_x("expected_dq_kyc", ["ERR_NR", "KEY", "DESCRIPTION"], self.kyc_dq)
        self.write_csv_x("expected_dq_refsys", ["CHECK", "KEY", "EXPECTED"], self.ref_dq)
        self.write_csv_x("file_control_totals", ["FILE_ID", "SUPPLIER_CD", "EXTRACT_DT", "REC_CNT", "DR_TOTAL", "CR_TOTAL"], self.ctrl_totals)
        n_daily = len(self.daily) + len(self.resends) + 1 + len(self.file_dups)
        stats = [("run_date (BUSINESS_DT)", R), ("history window", f"{self.hist_start} .. {R - ONE}"),
                 ("parties (KYCSYS PY)", len(self.parties)), ("accounts (KYCSYS AC)", len(self.accts) + 1),
                 ("party-account roles (PA)", len(self.rels)), ("aliases (AL)", len(self.aliases)),
                 ("refsys records (excl. HD/TR)", self.refsys_cnt), ("kycsys records (excl. HD/TR)", self.kycsys_cnt),
                 ("sanctions designations", len(self.sanc_entities)), ("sanctions name rows", len(self.sanc_rows)),
                 ("dailytxn detail records", n_daily), ("dailytxn record length", self.daily_width),
                 ("history txns (DB_ODS.AML_TXN_DAILY seed)", len(self.fact)),
                 ("counterparties (DB_ODS.CPTY seed)", sum(1 for c in self.cpty.values() if c["FIRST_SEEN_DT"] < R)),
                 ("account-days (DB_AML.ACCT_DAILY_SUMM seed)", len(self.summ)),
                 ("prior alerts / cases seeded", f"{len(self.prior_alerts)} / {len({a['CASE_ID'] for a in self.prior_alerts})}"),
                 ("expected alerts on run date", len(alerts)), ("expected screening hits", len(hits))]
        self.write_csv_x("generation_stats", ["METRIC", "VALUE"], [dict(METRIC=k, VALUE=v) for k, v in stats])
        for k, v in stats:
            print(f"  {k:<45} {v}")

    def write_csv_x(self, name, cols, rows):
        with open(self.path("expected", name + ".csv"), "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(cols)
            for row in rows:
                w.writerow(["" if row.get(c) is None else (row[c].isoformat() if isinstance(row.get(c), dt.date) else row[c]) for c in cols])


# ======================================================================================
# layouts shared with the DDL contract
# ======================================================================================
TXN_RAW = [
    ("RECTYPE", 1), ("SUPPLIER_CD", 4), ("FILE_SEQ_NR", 9), ("TXN_REF", 35), ("TXN_SEQ_NR", 4), ("SORT_CD", 6), ("ACCT_NR", 8),
    ("TXN_TYP_CD", 4), ("CHNL_CD", 3), ("DR_CR_IND", 1), ("TXN_AMT", 16), ("TXN_CCY", 3), ("ORIG_AMT", 16), ("ORIG_CCY", 3),
    ("BOOKING_DT", 8), ("VALUE_DT", 8), ("TXN_TMS", 14), ("NARRATIVE", 140), ("CPTY_NM", 140), ("CPTY_SORT_CD", 6),
    ("CPTY_ACCT_NR", 8), ("CPTY_IBAN", 34), ("CPTY_BIC", 11), ("CPTY_BANK_CTRY", 2), ("CPTY_CTRY", 2), ("ORDERING_CUST_NM", 140),
    ("BENEF_CUST_NM", 140), ("PAYMENT_REF", 35), ("E2E_ID", 35), ("UETR", 36), ("SWIFT_MSG_TYP", 3), ("CHARGE_BEARER", 3),
    ("INTERMED_BIC", 11), ("MCC", 4), ("MERCHANT_NM", 40), ("MERCHANT_CTRY", 2), ("MERCHANT_ID", 15), ("TERMINAL_ID", 8),
    ("ATM_ID", 8), ("CARD_TOKEN", 19), ("POS_ENTRY_MODE", 2), ("CARD_PRESENT_IND", 1), ("BRANCH_SORT_CD", 6), ("TELLER_ID", 8),
    ("CASH_IND", 1), ("CHEQUE_NR", 6), ("DEVICE_ID", 40), ("IP_ADDR", 45), ("IP_CTRY", 2), ("SESSION_ID", 36), ("AUTH_METHOD", 2),
    ("COP_RESULT", 2), ("APP_FRAUD_IND", 1), ("RETURN_REASON_CD", 4), ("REVERSAL_IND", 1), ("ORIG_TXN_REF", 35),
    ("BAL_AFTER", 16), ("TXN_STATUS", 2), ("FEE_AMT", 16), ("PURPOSE_CD", 4), ("BATCH_ID", 20), ("EXTRACT_DT", 8),
]

FINAL_COLS = """
TXN_REF
SUPPLIER_CD
BOOKING_DT
VALUE_DT
TXN_TMS
ACCT_ID
SORT_CD
ACCT_NR
PARTY_ID
PRDT_CD
SEGMENT_CD
TXN_TYP_CD
PAY_SCHEME_CD
CHNL_CD
DR_CR_IND
TXN_AMT
TXN_CCY_CD
ORIG_AMT
ORIG_CCY_CD
GBP_AMT
GBP_RATE
CASH_IND
XBORDER_IND
ROUND_AMT_IND
NARRATIVE_TXT
CPTY_ID
CPTY_NM
CPTY_SORT_CD
CPTY_ACCT_NR
CPTY_IBAN
CPTY_BIC_CD
CPTY_BANK_CTRY_CD
CPTY_CTRY_CD
CPTY_CTRY_RISK_CD
CPTY_INTERNAL_IND
CPTY_PARTY_ID
ORDERING_CUST_NM
BENEF_CUST_NM
PAYMENT_REF
E2E_ID
UETR
SWIFT_MSG_TYP_CD
INTERMED_BIC_CD
MCC_CD
MCC_RISK_CD
MERCHANT_NM
MERCHANT_CTRY_CD
CARD_TOKEN
CARD_PRESENT_IND
ATM_ID
BRANCH_SORT_CD
CHEQUE_NR
DEVICE_ID
IP_CTRY_CD
AUTH_METHOD_CD
COP_RESULT_CD
APP_FRAUD_IND
RETURN_REASON_CD
REVERSAL_IND
ORIG_TXN_REF
BAL_AFTER_AMT
TXN_STATUS_CD
FEE_AMT
PURPOSE_CD
PARTY_RISK_RATING_CD
PARTY_PEP_IND
HRC_IND
SANC_HIT_IND
DQ_ERR_IND
BATCH_ID
FILE_SEQ_NR
LOAD_TMS
CO_UPD_TMS
"""

SUMM_COLS = ["ACCT_ID", "BUSINESS_DT", "PARTY_ID", "SEGMENT_CD", "CR_CNT", "CR_GBP_AMT", "DR_CNT", "DR_GBP_AMT",
             "CASH_CR_CNT", "CASH_CR_GBP_AMT", "CASH_DR_CNT", "CASH_DR_GBP_AMT", "XBORDER_CNT", "XBORDER_GBP_AMT",
             "HRC_CNT", "HRC_GBP_AMT", "ROUND_AMT_CNT", "NEAR_THRESHOLD_CASH_CNT", "DISTINCT_CPTY_CR_CNT",
             "DISTINCT_CPTY_DR_CNT", "MAX_TXN_GBP_AMT", "GAMBLING_GBP_AMT", "CRYPTO_GBP_AMT", "CO_UPD_TMS"]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    ap.add_argument("--run-date", default="2026-11-25")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--parties", type=int, default=1000)
    ap.add_argument("--history-days", type=int, default=150)
    a = ap.parse_args()
    print(f"Generating AML demo data: run date {a.run_date}, seed {a.seed}, {a.parties} parties -> {os.path.abspath(a.out)}")
    Gen(a).run_all()
    print("done")


if __name__ == "__main__":
    main()
