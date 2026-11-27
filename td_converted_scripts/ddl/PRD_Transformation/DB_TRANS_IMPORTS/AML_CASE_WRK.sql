-- TODO: manual review required — Delta does not enforce Teradata SET/UPI uniqueness; enforce PARTY_ID uniqueness in the write path
-- Teradata SET and physical FALLBACK, JOURNAL, CHECKSUM, MERGEBLOCKRATIO, and MAP clauses are omitted for Delta
-- The source database qualifier is omitted because no target Unity Catalog mapping was supplied
-- CHARACTER SET LATIN is omitted because Databricks uses UTF-8; NOT CASESPECIFIC is preserved with UTF8_LCASE collation
-- Teradata DATE FORMAT display metadata is omitted because DATE already renders as YYYY-MM-DD
-- INTEGER and BYTEINT are mapped to INT and TINYINT
CREATE TABLE AML_CASE_WRK (
    PARTY_ID CHAR(12) COLLATE UTF8_LCASE NOT NULL,
    CASE_ID BIGINT,
    EXISTING_CASE_IND CHAR(1) COLLATE UTF8_LCASE,
    ALERT_CNT INT,
    TOTAL_ALERT_SCORE INT,
    TOTAL_HIT_GBP_AMT DECIMAL(18,2),
    MAX_RULE_SCORE SMALLINT,
    FIRST_ALERT_DT DATE,
    LAST_ALERT_DT DATE,
    RULE_LIST VARCHAR(200) COLLATE UTF8_LCASE,
    SEGMENT_CD CHAR(3) COLLATE UTF8_LCASE,
    RISK_BAND_CD CHAR(2) COLLATE UTF8_LCASE,
    CASE_PRIORITY_NR TINYINT,
    QUEUE_CD CHAR(6) COLLATE UTF8_LCASE,
    SLA_DUE_DT DATE
);

-- Teradata UNIQUE PRIMARY INDEX is represented as an informational Delta primary key
ALTER TABLE AML_CASE_WRK ADD CONSTRAINT XPKAML_CASE_WRK PRIMARY KEY (PARTY_ID);
