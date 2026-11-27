-- Teradata SET semantics, FALLBACK/JOURNAL, CHECKSUM, MERGEBLOCKRATIO, MAP, and display-only FORMAT clauses are removed for Delta.
-- The source database qualifier is omitted because no target Unity Catalog mapping was supplied.
-- CHARACTER SET LATIN is removed because Databricks uses UTF-8; NOT CASESPECIFIC is preserved with UTF8_LCASE collation.
-- Teradata INTEGER maps to INT, and timezone-naive TIMESTAMP(0) maps to TIMESTAMP_NTZ.
CREATE TABLE ALERT_SUMM_DAILY (
    BUSINESS_DT DATE NOT NULL,
    RULE_CD CHAR(8) COLLATE UTF8_LCASE NOT NULL,
    SEGMENT_CD CHAR(3) COLLATE UTF8_LCASE NOT NULL,
    RISK_BAND_CD CHAR(2) COLLATE UTF8_LCASE NOT NULL,
    ALERT_CNT INT,
    PARTY_CNT INT,
    ACCT_CNT INT,
    TOTAL_HIT_GBP_AMT DECIMAL(18,2),
    AVG_ALERT_SCORE DECIMAL(9,2),
    CO_UPD_TMS TIMESTAMP_NTZ
);

-- Teradata UNIQUE PRIMARY INDEX is represented as an informational Delta primary key; physical distribution is managed by Delta.
-- TODO: manual review required — the source UPI uniqueness is not enforced by the informational Delta primary key; enforce uniqueness in the write path.
ALTER TABLE ALERT_SUMM_DAILY ADD CONSTRAINT XPKALERT_SUMM_DAILY PRIMARY KEY (BUSINESS_DT, RULE_CD, SEGMENT_CD, RISK_BAND_CD);
