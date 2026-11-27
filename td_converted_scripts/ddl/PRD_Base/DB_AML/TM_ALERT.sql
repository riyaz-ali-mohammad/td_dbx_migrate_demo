-- TODO: manual review required — Teradata SET table row-uniqueness is lost because Delta uses multiset semantics; enforce de-duplication in the write pipeline
-- Converted the unqualified target to use the current catalog and schema because no Unity Catalog mapping was supplied
-- Removed Teradata FALLBACK, journal, checksum, merge-block-ratio, map, primary-index, and secondary-index physical-storage clauses
-- Converted LATIN NOT CASESPECIFIC character columns to UTF-8 columns with UTF8_LCASE collation
-- Removed Teradata display-only FORMAT clauses and mapped timezone-naive TIMESTAMP columns to TIMESTAMP_NTZ
CREATE TABLE TM_ALERT (
      ALERT_ID BIGINT NOT NULL,
      RULE_CD CHAR(8) COLLATE UTF8_LCASE NOT NULL,
      PARTY_ID CHAR(12) COLLATE UTF8_LCASE,
      ACCT_ID CHAR(14) COLLATE UTF8_LCASE NOT NULL,
      BUSINESS_DT DATE NOT NULL,
      ALERT_TMS TIMESTAMP_NTZ NOT NULL,
      ALERT_SCORE SMALLINT,
      HIT_GBP_AMT DECIMAL(18,2),
      HIT_CNT INT,
      LOOKBACK_START_DT DATE,
      LOOKBACK_END_DT DATE,
      TRIGGER_TXN_REF VARCHAR(35) COLLATE UTF8_LCASE,
      TRIGGER_SUPPLIER_CD CHAR(4) COLLATE UTF8_LCASE,
      ALERT_STATUS_CD CHAR(5) COLLATE UTF8_LCASE NOT NULL,
      SUPPRESS_REASON_CD CHAR(4) COLLATE UTF8_LCASE,
      CASE_ID BIGINT,
      HIT_DETAIL VARCHAR(500) COLLATE UTF8_LCASE,
      CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
)
CLUSTER BY AUTO;

-- TODO: manual review required — the source UNIQUE PRIMARY INDEX enforced ALERT_ID uniqueness, while the Delta primary key is informational; enforce uniqueness in the write pipeline
-- Converted the Teradata UNIQUE PRIMARY INDEX to an informational Delta primary key
ALTER TABLE TM_ALERT ADD CONSTRAINT XPKTM_ALERT PRIMARY KEY (ALERT_ID);
