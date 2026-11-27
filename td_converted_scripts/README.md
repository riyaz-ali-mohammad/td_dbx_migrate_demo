# Converted scripts (Genie Migrate output)

Databricks SQL produced by **Genie Migrate** (project `barclays-demo-migration-GM`, source dialect Teradata, target Databricks SQL) from the Teradata estate in [`../scripts`](../scripts) and [`../ddl`](../ddl). The folder layout matches the source. Each file is the original name with a `.sql` extension, e.g. `scripts/01_bronze/kycref.15.LOAD_KYCSYS.mld` becomes `scripts/01_bronze/kycref.15.LOAD_KYCSYS.sql`.

This is the **raw first-pass output, before any manual or Devin review**. Genie Migrate marks what it changed with `-- Converted:` comments and anything it could not resolve with `-- TODO:` comments.

## Conversion summary

| Area | Files | Success | Partial success | `TODO` markers |
|---|---:|---:|---:|---:|
| Scripts | 21 | 0 | 21 | 81 |
| DDL | 137 | 9 | 128 | 236 |
| **Total** | **158** | **9** | **149** | **317** |

## Scripts

| Source | Status | `TODO` markers |
|---|---|---:|
| [`scripts/01_bronze/dailytxn.02.LOAD_DATA.mld`](scripts/01_bronze/dailytxn.02.LOAD_DATA.sql) | Partial Success | 2 |
| [`scripts/01_bronze/kycref.15.LOAD_KYCSYS.mld`](scripts/01_bronze/kycref.15.LOAD_KYCSYS.sql) | Partial Success | 1 |
| [`scripts/01_bronze/kycref.15.LOAD_REFSYS.mld`](scripts/01_bronze/kycref.15.LOAD_REFSYS.sql) | Partial Success | 1 |
| [`scripts/01_bronze/kycref.15.LOAD_SANCSYS.mld`](scripts/01_bronze/kycref.15.LOAD_SANCSYS.sql) | Partial Success | 1 |
| [`scripts/02_silver/dailytxn.03.TRANSFORM_DATA.sql`](scripts/02_silver/dailytxn.03.TRANSFORM_DATA.sql) | Partial Success | 5 |
| [`scripts/02_silver/dailytxn.04.CAT_UPDATES.sql`](scripts/02_silver/dailytxn.04.CAT_UPDATES.sql) | Partial Success | 12 |
| [`scripts/02_silver/dailytxn.05.COUNTERPARTY.sql`](scripts/02_silver/dailytxn.05.COUNTERPARTY.sql) | Partial Success | 11 |
| [`scripts/02_silver/dailytxn.06.GBP_CONVERT.sql`](scripts/02_silver/dailytxn.06.GBP_CONVERT.sql) | Partial Success | 9 |
| [`scripts/02_silver/dailytxn.07.CHECK_VALUES.sql`](scripts/02_silver/dailytxn.07.CHECK_VALUES.sql) | Partial Success | 2 |
| [`scripts/02_silver/dailytxn.08.SANCTIONS_SCREEN.sql`](scripts/02_silver/dailytxn.08.SANCTIONS_SCREEN.sql) | Partial Success | 3 |
| [`scripts/02_silver/kycref.35.REFSYS_TRANSFORMATION.sql`](scripts/02_silver/kycref.35.REFSYS_TRANSFORMATION.sql) | Partial Success | 2 |
| [`scripts/02_silver/kycref.40.REFSYS_ODS.sql`](scripts/02_silver/kycref.40.REFSYS_ODS.sql) | Partial Success | 1 |
| [`scripts/02_silver/kycref.50.REFSYS_SNP_TABLES.sql`](scripts/02_silver/kycref.50.REFSYS_SNP_TABLES.sql) | Partial Success | 12 |
| [`scripts/02_silver/kycref.55.KYCSYS.sql`](scripts/02_silver/kycref.55.KYCSYS.sql) | Partial Success | 4 |
| [`scripts/02_silver/kycref.60.SANCSYS.sql`](scripts/02_silver/kycref.60.SANCSYS.sql) | Partial Success | 3 |
| [`scripts/03_gold/amlmon.15.ACCT_PROFILE.sql`](scripts/03_gold/amlmon.15.ACCT_PROFILE.sql) | Partial Success | 2 |
| [`scripts/03_gold/amlmon.20.TM_RULES.sql`](scripts/03_gold/amlmon.20.TM_RULES.sql) | Partial Success | 2 |
| [`scripts/03_gold/amlmon.30.CUST_RISK_SCORE.sql`](scripts/03_gold/amlmon.30.CUST_RISK_SCORE.sql) | Partial Success | 1 |
| [`scripts/03_gold/amlmon.40.CASE_MGMT.sql`](scripts/03_gold/amlmon.40.CASE_MGMT.sql) | Partial Success | 2 |
| [`scripts/03_gold/amlmon.50.MI_DAILY.sql`](scripts/03_gold/amlmon.50.MI_DAILY.sql) | Partial Success | 3 |
| [`scripts/03_gold/dailytxn.10.APPLY_DAILY_TXN.sql`](scripts/03_gold/dailytxn.10.APPLY_DAILY_TXN.sql) | Partial Success | 2 |

## DDL

All DDLs are under [`ddl/`](ddl). The successfully converted ones are:

- [`ddl/PRD_Base/DB_ODS/AML_TXN_DAILY_HIST.ddl`](ddl/PRD_Base/DB_ODS/AML_TXN_DAILY_HIST.sql)
- [`ddl/PRD_Base/DB_STREAM_DATA/HIST_DLYTXN_LOAD_DUP.ddl`](ddl/PRD_Base/DB_STREAM_DATA/HIST_DLYTXN_LOAD_DUP.sql)
- [`ddl/PRD_Transformation/DB_TRANS_IMPORTS/AML_SANCSYS_RAW.ddl`](ddl/PRD_Transformation/DB_TRANS_IMPORTS/AML_SANCSYS_RAW.sql)
- [`ddl/PRD_Transformation/DB_TRANS_IMPORTS/DLYTXN_SCREEN_CAND.ddl`](ddl/PRD_Transformation/DB_TRANS_IMPORTS/DLYTXN_SCREEN_CAND.sql)
- [`ddl/PRD_Transformation/DB_TRANS_IMPORTS/DLYTXN_SCREEN_TOKEN.ddl`](ddl/PRD_Transformation/DB_TRANS_IMPORTS/DLYTXN_SCREEN_TOKEN.sql)
- [`ddl/PRD_Views/VX_AML/AML_CASE.ddl`](ddl/PRD_Views/VX_AML/AML_CASE.sql)
- [`ddl/PRD_Views/VX_AML/PARTY_RISK_SCORE.ddl`](ddl/PRD_Views/VX_AML/PARTY_RISK_SCORE.sql)
- [`ddl/PRD_Views/VX_AML/SAR_CANDIDATE.ddl`](ddl/PRD_Views/VX_AML/SAR_CANDIDATE.sql)
- [`ddl/PRD_Views/VX_AML/TM_ALERT.ddl`](ddl/PRD_Views/VX_AML/TM_ALERT.sql)
