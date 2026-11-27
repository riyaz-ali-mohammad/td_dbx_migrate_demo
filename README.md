# Demo Batch: "AML Transaction Monitoring" Data Product (Teradata → Databricks)

21 Teradata scripts and 137 DDLs (132 tables, 5 views) that run end to end as one medallion pipeline for UK retail and commercial banking anti-money laundering (AML). This is the input for the Genie Migrate + Devin demo. It is entirely banking-domain.

**Synthetic and neutral:** there are no real bank, customer or vendor names. Source systems use neutral placeholders: `REFSYS` (reference data), `KYCSYS` (customer/KYC master), `SANCSYS` (an OFSI-style consolidated sanctions list) and the daily transaction extract (`CBS1` core banking, `PAY1` payments hub, `CRD1` cards). There are no author or revision headers.

## Why this batch

- **One connected flow, not 21 random files.** Three production streams depend on each other:
  - `kycref`: reference data, KYC customer/account master, and the sanctions list
  - `dailytxn`: daily payment and transaction ingestion, enrichment, DQ and sanctions screening
  - `amlmon`: transaction-monitoring rules, customer risk scoring, case management and MI

  `kycref.50/.55/.60` build the `DB_ODS.*_SNAPSHOT`, party/account and sanctions-token tables that `dailytxn.05–.10` enrich and screen against. `amlmon.*` consumes the transaction fact and the KYC model. Migrating all three shows **cross-pipeline lineage** in Unity Catalog.
- **Every table has a DDL.** All 137 DDL objects are referenced by the scripts, and every table the scripts read or write has a DDL. The exceptions are the MultiLoad runtime work tables (`_WRK/_ERR/_UNQ/_LOG`) and the `VOLATILE` tables.
- **It covers the hard Teradata patterns:**

  | Pattern | Count |
  |---|---:|
  | BTEQ `.if errorcode` control flow | 482 |
  | `<DB_ENV>` environment templating | 1,229 |
  | `QUALIFY` (`SUM(1) OVER … ROWS UNBOUNDED PRECEDING`, `ROW_NUMBER`, `RANK`) | 47 |
  | `CSUM` | 17 |
  | Legacy `MSUM` / `MAVG` | 4 |
  | `COLLECT STATISTICS` | 216 |
  | `VOLATILE` tables | 58 |
  | `.goto` / `.label` | 13 |
  | `ACTIVITYCOUNT` checks | 27 |
  | `OREPLACE` / `OTRANSLATE` | 49 |

  It also uses `BT;/ET;` transactions, `MERGE INTO`, `UPDATE … FROM`, `STRTOK_SPLIT_TO_TABLE`, `XMLAGG`, `REGEXP_SUBSTR`, MultiLoad fixed-width and `VARTEXT '|'` layouts, PPI (`RANGE_N`) fact tables, identity columns, SCD2 `*_HIST` tables, DELETE+INSERT reloads, and DQ error-log tables.
- **The size suits a demo:** about 14.7k lines of scripts. That is enough to be credible, and the scripts run in numbered order, so you can migrate one stream live.

## Lineage

```
BRONZE (raw landing)                      SILVER (conform / validate)                         GOLD (serve)
────────────────────                      ───────────────────────────                         ─────────────────────────────
REFSYS file ─► kycref.15.LOAD_REFSYS ─►  kycref.35 REFSYS_TRANSFORMATION ─► kycref.40 REFSYS_ODS ─► kycref.50 SNP_TABLES
              (AML_REFSYS_RAW)            (10 record types → AML_* work tables)  (versioned ref: CTRY,     (11 x *_SNAPSHOT)
                                                                                  FX, MCC, SORT, RULES…)          │
KYCSYS file ─► kycref.15.LOAD_KYCSYS ─►  kycref.55 KYCSYS (party, account, roles, alias, SCD hist) ──────────────┤
SANCSYS file ► kycref.15.LOAD_SANCSYS ►  kycref.60 SANCSYS (entities, names, STRTOK tokens, BICs) ───────────────┤
                                                                                                                  ▼
Daily txn ─► dailytxn.02.LOAD_DATA ─► .03 TRANSFORM ─► .04 CAT_UPDATES ─► .05 COUNTERPARTY ─► .06 GBP_CONVERT
file (H/D/T)  (DLYTXN_DATA_RAW +        (recon, typing,   (code/BIC upserts)   (CPTY surrogate keys)  (FX → GBP, placeholder
              DLYTXN_CTRL_RAW)           dedupe → DUP hist)                                             accounts)
          ─► .07 CHECK_VALUES ─► .08 SANCTIONS_SCREEN ─► dailytxn.10 APPLY_DAILY_TXN ─► DB_ODS.AML_TXN_DAILY (+_HIST, PPI)
             (DQ → error logs)     (exact/token/ctry/BIC                                         │
                                    → DB_AML.SANC_SCREEN_HIT)                                    ▼
                         amlmon.15 ACCT_PROFILE ─► amlmon.20 TM_RULES ─► amlmon.30 CUST_RISK_SCORE ─► amlmon.40 CASE_MGMT ─► amlmon.50 MI_DAILY
                         (daily summ + rolling     (12 rules → TM_ALERT)   (factor scoring, SCD2,       (cases, SLA, SAR      (DB_AML_MI dims
                          behaviour profile)                                EDD queue)                   candidates)            and aggregates)
                                                                                                                  │
                                                                                     VX_AML.* (masked, row-filtered consumption views)
```

## The 21 scripts (run order)

| # | Layer | Script | Lines | What it does | Key targets |
|---|---|---|---:|---|---|
| 1 | Bronze | `kycref.15.LOAD_REFSYS.mld` | 77 | MultiLoad of the fixed-width reference file | `DB_TRANS_IMPORTS.AML_REFSYS_RAW` |
| 2 | Bronze | `kycref.15.LOAD_KYCSYS.mld` | 77 | MultiLoad of the KYC party/account file | `AML_KYCSYS_RAW` |
| 3 | Bronze | `kycref.15.LOAD_SANCSYS.mld` | 156 | MultiLoad `VARTEXT '\|'` of the consolidated sanctions list | `AML_SANCSYS_RAW` |
| 4 | Bronze | `dailytxn.02.LOAD_DATA.mld` | 353 | MultiLoad of the daily transaction file: two layouts (detail and header/trailer), error and uniqueness tables | `DLYTXN_DATA_RAW`, `DLYTXN_CTRL_RAW` |
| 5 | Silver | `kycref.35.REFSYS_TRANSFORMATION.sql` | 1091 | Splits raw records into 10 entity work tables (country, currency, FX, MCC, sort code, txn type, channel, product, SIC, rule thresholds); bad records go to the reject table | `AML_CTRY, AML_FXRT, AML_MCC, AML_RULE …` |
| 6 | Silver | `kycref.40.REFSYS_ODS.sql` | 1095 | Versioned upsert into the ODS reference model; derives country risk (FATF / HMT / Basel) | `DB_ODS.CTRY, FX_RATE, MCC, SORT_CD_DIR, TM_RULE_PARAM …` |
| 7 | Silver | `kycref.50.REFSYS_SNP_TABLES.sql` | 384 | Builds the current-snapshot lookup tables | `DB_ODS.*_SNAPSHOT` (×11) |
| 8 | Silver | `kycref.55.KYCSYS.sql` | 1961 | Party, account, party-account roles and aliases, with SCD history and KYC DQ | `DB_ODS.PARTY(_HIST), ACCT(_HIST), PARTY_ACCT_REL, PARTY/ACCT_SNAPSHOT` |
| 9 | Silver | `kycref.60.SANCSYS.sql` | 718 | Sanctions entities (SCD, delisting), name normalisation, `STRTOK` tokens, sanctioned BICs | `DB_ODS.SANC_ENTITY(_HIST), SANC_NAME, SANC_NAME_TOKEN, SANC_BIC` |
| 10 | Silver | `dailytxn.03.TRANSFORM_DATA.sql` | 835 | Control-total reconciliation, typing, dedupe; duplicates go to history | `DLYTXN_LOAD, INFO_DLYTXN_CTRL_RECON, HIST_DLYTXN_LOAD_DUP` |
| 11 | Silver | `dailytxn.04.CAT_UPDATES.sql` | 370 | Adds newly seen codes and BICs to the category and reference tables | `DB_ODS.*_CAT, DB_REFERENCE.BIC_DIRECTORY, RETURN_REASON` |
| 12 | Silver | `dailytxn.05.COUNTERPARTY.sql` | 248 | Resolves counterparty surrogate keys and detects internal transfers | `DLYTXN_CPTY, DB_ODS.CPTY` |
| 13 | Silver | `dailytxn.06.GBP_CONVERT.sql` | 198 | Converts to GBP with an FX fallback; adds placeholder accounts | `DLYTXN_GBP, DB_ODS.ACCT_SNAPSHOT` |
| 14 | Silver | `dailytxn.07.CHECK_VALUES.sql` | 772 | **DQ gate:** checks accounts, countries, currencies, sort codes, MCCs and FX against the snapshots | `DB_STREAM_DATA.INFO_DLYTXN_ERROR_*` |
| 15 | Silver | `dailytxn.08.SANCTIONS_SCREEN.sql` | 630 | Screens names (exact and token), countries and BICs against the sanctions list | `DB_AML.SANC_SCREEN_HIT` |
| 16 | Gold | `dailytxn.10.APPLY_DAILY_TXN.sql` | 883 | Builds the enriched transaction fact and applies it with history | `DB_ODS.AML_TXN_DAILY`, `AML_TXN_DAILY_HIST` |
| 17 | Gold | `amlmon.15.ACCT_PROFILE.sql` | 553 | Daily account summary and rolling behaviour profile (`MSUM`, `CSUM`, windows) | `DB_AML.ACCT_DAILY_SUMM, ACCT_BEHAV_PROFILE` |
| 18 | Gold | `amlmon.20.TM_RULES.sql` | 1594 | 12 monitoring rules with segment thresholds and suppression | `DB_AML.TM_ALERT, TM_ALERT_TXN` |
| 19 | Gold | `amlmon.30.CUST_RISK_SCORE.sql` | 1014 | Factor-based customer risk score and band, SCD2, EDD triggers | `DB_AML.PARTY_RISK_SCORE(_HIST), EDD_REVIEW_QUEUE` |
| 20 | Gold | `amlmon.40.CASE_MGMT.sql` | 913 | Consolidates alerts into cases; priority, queue, business-day SLA, SAR candidates, auto-close | `DB_AML.AML_CASE(_HIST), AML_CASE_ALERT_XREF, SAR_CANDIDATE` |
| 21 | Gold | `amlmon.50.MI_DAILY.sql` | 777 | BI dimensions and MI aggregates (rule effectiveness, cross-border flows, case ageing) | `DB_AML_MI.DIM_*, ALERT_SUMM_DAILY, RULE_EFFECTIVENESS_MTH …` |

### Transaction-monitoring rules (`amlmon.20`)

Thresholds come from `DB_ODS.TM_RULE_PARAM_SNAPSHOT` by segment (`RET/BUS/CIB/WLT`), with `ALL` as the fallback.

| Rule | Typology |
|---|---|
| `TM_STR01` | Structuring: repeated cash credits just under the threshold |
| `TM_RPM01` | Rapid movement: funds in, then out within 2 days |
| `TM_HRC01` | High-risk jurisdictions (FATF black/grey list, HMT, EU) |
| `TM_RND01` | Round-amount transfers |
| `TM_DRM01` | Dormant account reactivation |
| `TM_VEL01` | Velocity spike against the prior 90-day behaviour |
| `TM_PEP01` | Large PEP transactions |
| `TM_TOV01` | Turnover above the declared expected turnover |
| `TM_CSH01` | Cash activity for non-cash-intensive occupations |
| `TM_MUL01` | Money-mule fan-in on newly opened retail accounts |
| `TM_GMB01` | Gambling and crypto spend |
| `TM_SAN01` | Sanctions screening hits |

## DDLs (`ddl/`, same folder structure as `PRD_Databases`)

| Database | # | Role |
|---|---:|---|
| `PRD_Transformation/DB_TRANS_IMPORTS` | 41 | Bronze raw tables and Silver/Gold work tables |
| `PRD_Base/DB_ODS` | 45 | Silver conformed reference, KYC and sanctions model; Gold transaction fact |
| `PRD_Base/DB_AML` | 12 | Gold AML outputs: behaviour, alerts, screening hits, risk scores, cases, SARs |
| `PRD_Base/DB_AML_MI` | 12 | Gold BI dimensions and aggregates |
| `PRD_Base/DB_REFERENCE` | 11 | Static reference data (two tables are maintained by the batch) |
| `PRD_Base/DB_STREAM_DATA` | 11 | DQ error logs, control recon and duplicate history |
| `PRD_Views/VX_AML` | 5 | Consumption views with PII masking and segment row filters |

## Tables to seed with synthetic data (maintained outside this batch)

| Table | Expected content |
|---|---|
| `DB_REFERENCE.SANC_REGIME_CTRY` | Regime name → ISO2 country, with a comprehensive-sanctions flag |
| `DB_REFERENCE.CTRY_NAME_XREF` | Country name text in the sanctions list → ISO2 |
| `DB_REFERENCE.NAME_NOISE_WORD` | Words dropped during name matching: LTD, LIMITED, PLC, LLP, MR, MRS, THE, AND, CO … |
| `DB_REFERENCE.RISK_FACTOR_WEIGHT` | Points for each factor value (see below) |
| `DB_REFERENCE.RISK_BAND` | `L / M / H / VH` score ranges, review frequency (months) and CDD level |
| `DB_REFERENCE.CASE_QUEUE` | One queue per segment × priority range, with SLA in business days. Examples: `RETP1` (RET, priority 1–2, 5 days), `RETSTD` (RET, 3–5, 20 days), the same pairs for BUS/CIB/WLT, and `AMLGEN` (ALL, 1–5, 20 days), which is also the default |
| `DB_REFERENCE.CALENDAR` | At least 3 years back and 4 months forward, with `BUS_DAY_IND` set |
| `DB_REFERENCE.UK_BANK_HOLIDAY` | England & Wales bank holidays |
| `DB_REFERENCE.VIEW_ACCESS_CTRL` | Demo users × segment, with PII and SAR access flags |

`RISK_FACTOR_WEIGHT` factor codes, with the values each one takes:

| `FACTOR_CD` | `FACTOR_VALUE_CD` |
|---|---|
| `RESCTRY`, `NATCTRY` | `L, M, H, X, UNKNOWN` |
| `PEP` | `DO, FO, IO, RC, NONE` |
| `OCCP`, `PRDT` | `L, M, H, UNKNOWN` |
| `CHNL` | `F2F, NFTF` |
| `ALERTS` | `0, 1-2, 3-5, 6+` |
| `SANC` | `OPEN, NONE` |
| `KYC` | `OVERDUE, VE, PE, EX, RF` |
| `ADVMEDIA` | `Y, N` |

Synthetic versions of all seed tables and landing files, plus expected results, are in `../td_banking_data/` (generator in `../td_banking_data/datagen/`).

You also need 4 synthetic landing files: REFSYS (fixed width, 10 record types), KYCSYS (fixed width: `PY/AC/PA/AL`), SANCSYS (pipe-delimited) and the daily transaction file (fixed width with H/D/T records). The record layouts are documented in the banner comments of `kycref.35`, `kycref.55`, `kycref.15.LOAD_SANCSYS` and `dailytxn.02`.

### Code values the streams share

| Field | Values |
|---|---|
| Segments | `RET` retail, `BUS` business, `CIB` corporate, `WLT` wealth; `UNK` = placeholder account |
| Risk rating / band | Party rating `L/M/H`; scored band `L/M/H/VH`; country risk `L/M/H` (plus `X` = prohibited) |
| `TXN_STATUS_CD` | `BK` booked, `PD` pending (drives the DAML flag), `RJ` rejected, `RV` reversed |
| Alert status | `NEW / SUPPR / CASED / CLOSD` |
| Case status | `OPEN / INVST / ESCAL / SARFL / CLOSD` |
| FX | `GBP_RATE` is in currency units per 1 GBP. `RATE_FALLBACK_IND`: `N` = rate for the booking date, `Y` = earlier rate used, `X` = no rate found |
| Name normalisation | Same rule in `kycref.60` and `dailytxn.08`: `OTRANSLATE` punctuation → space, collapse spaces, `STRTOK` tokens minus noise words |

## Teradata → Databricks conversion points to show

| Teradata construct | Target on Databricks |
|---|---|
| MultiLoad `.mld` (`.LAYOUT`, multi-layout `APPLY … WHERE RECTYPE`, `VARTEXT`, ERR/UV tables) | Auto Loader / Lakeflow Declarative Pipelines into Bronze, with a rescued-data column; header/trailer recon as expectations |
| BTEQ `.IF ERRORCODE` / `.IF ACTIVITYCOUNT` / `.QUIT n` / `.GOTO` | Lakeflow Jobs task dependencies, condition tasks and SQL scripting error handling |
| `QUALIFY SUM(1) OVER(...) = 1`, `CSUM`, `MSUM/MAVG` | `QUALIFY ROW_NUMBER() OVER(...) = 1` and ANSI window frames |
| `MAX(id) + CSUM(1,…)` surrogates, identity columns | `GENERATED … AS IDENTITY` or `ROW_NUMBER` |
| DELETE+INSERT reloads; `*_HIST` SCD tables | `MERGE INTO` / `AUTO CDC` (`APPLY CHANGES`, SCD Type 2) |
| `STRTOK_SPLIT_TO_TABLE`, `OREPLACE`, `OTRANSLATE`, `XMLAGG` | `explode(split())`, `replace`, `translate`, `array_join(collect_list())` |
| PPI `RANGE_N` partitions, PI/USI/NUSI, `COLLECT STATISTICS` | Liquid clustering and predictive optimisation (drop them) |
| `VOLATILE` tables | Temp views / CTEs / session temp tables |
| `<DB_ENV>` prefix templating | Unity Catalog `catalog.schema` plus DAB variables per environment |
| `CHECK_VALUES` → `INFO_*_ERROR_LOG` | Pipeline expectations and Lakehouse Monitoring |
| `LOCKING … FOR ACCESS` views with `USER`-based masking and row filters | UC row filters and column masks, ABAC tags on PII; metric views |

## Optional extensions

- **AI moment:** have Genie or Agent Bricks draft the SAR narrative from `SAR_CANDIDATE` + `TM_ALERT_TXN`, or build an AML investigator Genie space over the `VX_AML` views.
- **KPI layer:** add a UC metric view over `TM_ALERT` / `AML_CASE`: alert-to-SAR conversion, SLA breach rate and high-risk-country flows by month.
- **Orchestration story:** add ksh `.unx` wrappers (`kycref.01.CHECK_AND_PREPARE.unx`, `dailytxn.01.PREPARE_DATA.unx`) to show them being converted into a single Lakeflow Job DAG.
