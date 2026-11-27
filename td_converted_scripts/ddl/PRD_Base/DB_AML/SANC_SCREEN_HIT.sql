-- assumption: No target catalog/schema mapping was supplied, so the source database qualifier is omitted and the table resolves in the current namespace.
-- Converted Teradata MULTISET and physical storage clauses to a standard Delta table; FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, MAP, and PRIMARY INDEX have no logical Databricks equivalent.
-- Converted LATIN NOT CASESPECIFIC columns to UTF-8 bounded character columns with case-insensitive collation.
-- Converted INTEGER to INT, removed display-only FORMAT clauses, mapped the naive timestamp to TIMESTAMP_NTZ, and removed unsupported identity bounds and cycling.
-- Enabled the Delta column-default feature for HIT_STATUS_CD.
-- TODO: manual review required — identity column semantics differ; confirm the surrogate-key strategy and whether writes must run concurrently.
CREATE TABLE SANC_SCREEN_HIT (
    HIT_ID BIGINT GENERATED ALWAYS AS IDENTITY (
        START WITH 1
        INCREMENT BY 1
    ),
    TXN_REF VARCHAR(35) COLLATE UTF8_LCASE NOT NULL,
    SUPPLIER_CD CHAR(4) COLLATE UTF8_LCASE NOT NULL,
    BUSINESS_DT DATE NOT NULL,
    ACCT_ID CHAR(14) COLLATE UTF8_LCASE,
    PARTY_ID CHAR(12) COLLATE UTF8_LCASE,
    NM_ROLE_CD CHAR(2) COLLATE UTF8_LCASE NOT NULL,
    SCREENED_NM VARCHAR(140) COLLATE UTF8_LCASE,
    GROUP_ID INT NOT NULL,
    MATCHED_NM VARCHAR(400) COLLATE UTF8_LCASE,
    REGIME_NM VARCHAR(100) COLLATE UTF8_LCASE,
    MATCH_TYP_CD CHAR(5) COLLATE UTF8_LCASE NOT NULL,
    MATCH_SCORE DECIMAL(5, 2),
    HIT_STATUS_CD CHAR(5) COLLATE UTF8_LCASE DEFAULT 'OPEN',
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');
