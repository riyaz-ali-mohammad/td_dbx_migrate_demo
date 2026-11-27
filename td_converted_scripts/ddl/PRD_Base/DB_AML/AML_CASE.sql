-- Converted the Teradata two-part name to an unqualified name because no target catalog mapping was supplied.
-- Dropped SET and Teradata physical storage options; Delta uses multiset semantics and managed cloud storage.
-- Removed Teradata display FORMAT clauses and the column compression hint.
-- Removed LATIN character-set clauses because Databricks stores strings as UTF-8.
-- Preserved NOT CASESPECIFIC behavior with UTF8_LCASE collations.
-- Converted BYTEINT to TINYINT, INTEGER to INT, and timezone-naive TIMESTAMP to TIMESTAMP_NTZ.
-- Dropped the non-unique secondary index; Delta uses file skipping and liquid clustering instead.
CREATE TABLE AML_CASE (
    CASE_ID BIGINT NOT NULL,
    PARTY_ID CHAR(12) COLLATE UTF8_LCASE NOT NULL,
    CASE_OPEN_DT DATE NOT NULL,
    CASE_STATUS_CD CHAR(5) COLLATE UTF8_LCASE NOT NULL,
    CASE_PRIORITY_NR TINYINT,
    QUEUE_CD CHAR(6) COLLATE UTF8_LCASE,
    SLA_DUE_DT DATE,
    ALERT_CNT INT,
    TOTAL_ALERT_SCORE INT,
    TOTAL_HIT_GBP_AMT DECIMAL(18,2),
    RULE_LIST VARCHAR(200) COLLATE UTF8_LCASE,
    SAR_CANDIDATE_IND CHAR(1) COLLATE UTF8_LCASE,
    RISK_BAND_CD CHAR(2) COLLATE UTF8_LCASE,
    SEGMENT_CD CHAR(3) COLLATE UTF8_LCASE,
    FIRST_ALERT_DT DATE,
    LAST_ALERT_DT DATE,
    CASE_CLOSE_DT DATE,
    CLOSE_REASON_CD CHAR(4) COLLATE UTF8_LCASE,
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
);

-- Converted the named UNIQUE PRIMARY INDEX to an informational primary-key constraint.
-- TODO: manual review required — Databricks primary keys are informational; enforce CASE_ID uniqueness in the write pipeline.
ALTER TABLE AML_CASE ADD CONSTRAINT XPKAML_CASE PRIMARY KEY (CASE_ID);
