-- Converted Teradata MULTISET DDL to a Delta CREATE TABLE; duplicate rows remain permitted.
-- Removed the source database qualifier because no target Unity Catalog mapping was supplied.
-- Removed FALLBACK, JOURNAL, CHECKSUM, MERGEBLOCKRATIO, and MAP physical-storage options; Delta manages durability and layout.
-- Removed CHARACTER SET LATIN because Databricks stores strings as UTF-8.
-- Replaced NOT CASESPECIFIC with UTF8_LCASE column collation.
-- Removed DATE FORMAT clauses because they were display-only metadata.
-- Removed the non-unique PRIMARY INDEX because Delta does not use Teradata AMP distribution.
-- TODO: manual review required — confirm downstream logic preserves Teradata CHAR trailing-space semantics and bounded VARCHAR expectations.
CREATE TABLE AML_RULE_HIT_WRK (
      RULE_CD CHAR(8) COLLATE UTF8_LCASE NOT NULL,
      PARTY_ID CHAR(12) COLLATE UTF8_LCASE,
      ACCT_ID CHAR(14) COLLATE UTF8_LCASE NOT NULL,
      BUSINESS_DT DATE NOT NULL,
      HIT_GBP_AMT DECIMAL(18,2),
      HIT_CNT INT,
      LOOKBACK_START_DT DATE,
      LOOKBACK_END_DT DATE,
      ALERT_SCORE SMALLINT,
      TRIGGER_TXN_REF VARCHAR(35) COLLATE UTF8_LCASE,
      TRIGGER_SUPPLIER_CD CHAR(4) COLLATE UTF8_LCASE,
      HIT_DETAIL VARCHAR(500) COLLATE UTF8_LCASE
);
