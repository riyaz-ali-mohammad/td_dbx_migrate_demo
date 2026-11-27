-- assumption: No target Unity Catalog mapping was supplied, so ACCT_HIST resolves in the current catalog and schema.
-- Converted the Teradata SET table to Delta multiset semantics.
-- TODO: manual review required — Teradata SET table row-uniqueness is lost; enforce de-duplication in the write path.
-- Removed Teradata FALLBACK, journals, checksum, merge-block-ratio, and map storage options; Delta manages durability and layout.
-- Removed LATIN character-set clauses and applied UTF8_LCASE collations to preserve NOT CASESPECIFIC comparisons.
-- Preserved fixed-width CHAR declarations.
-- TODO: manual review required — verify fixed-width CHAR blank-padding and trailing-space behavior in consuming workloads.
-- Removed display-only DATE/TIMESTAMP FORMAT clauses and mapped timezone-naive TIMESTAMP columns to TIMESTAMP_NTZ.
-- Replaced the Teradata primary-index distribution with Delta liquid clustering on the same access keys.
CREATE TABLE ACCT_HIST (
    ACCT_ID CHAR(14) COLLATE UTF8_LCASE NOT NULL,
    START_DT DATE NOT NULL,
    UPD_TMS TIMESTAMP_NTZ NOT NULL,
    END_DT DATE,
    SORT_CD CHAR(6) COLLATE UTF8_LCASE,
    ACCT_NR CHAR(8) COLLATE UTF8_LCASE,
    PRDT_CD CHAR(6) COLLATE UTF8_LCASE,
    CCY_CD CHAR(3) COLLATE UTF8_LCASE,
    OPEN_DT DATE,
    CLOSE_DT DATE,
    ACCT_STATUS_CD CHAR(1) COLLATE UTF8_LCASE,
    PRIMARY_PARTY_ID CHAR(12) COLLATE UTF8_LCASE,
    OD_LIMIT_AMT DECIMAL(18, 2),
    LAST_CUST_ACTV_DT DATE,
    OPEN_CHNL_CD CHAR(3) COLLATE UTF8_LCASE,
    ACTION_CD CHAR(1) COLLATE UTF8_LCASE,
    CO_UPD_TMS TIMESTAMP_NTZ
)
CLUSTER BY (ACCT_ID, START_DT, UPD_TMS);

-- Converted the UNIQUE PRIMARY INDEX contract to an informational Delta primary key.
-- TODO: manual review required — Delta primary keys are not enforced; preserve ACCT_ID/START_DT/UPD_TMS uniqueness in the write path.
ALTER TABLE ACCT_HIST
ADD CONSTRAINT XPKACCT_HIST PRIMARY KEY (ACCT_ID, START_DT, UPD_TMS);
