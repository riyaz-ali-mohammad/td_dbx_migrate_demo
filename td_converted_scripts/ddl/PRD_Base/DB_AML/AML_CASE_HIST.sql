-- assumption: The target catalog and schema are set in the session because no target namespace mapping was supplied.
-- Converted the Teradata SET table to a Delta table and removed FALLBACK, journals, checksum, merge-block-ratio, and map options because Delta manages storage and resilience.
-- Converted timezone-naive TIMESTAMP columns to TIMESTAMP_NTZ, BYTEINT to TINYINT, and INTEGER to INT.
-- Removed display-only FORMAT, LATIN character-set, and COMPRESS clauses; translated NOT CASESPECIFIC columns to UTF8_LCASE collation.
-- TODO: manual review required — verify bounded CHAR/VARCHAR width, padding, and trailing-space behavior against target workloads.
CREATE TABLE AML_CASE_HIST (
    CASE_ID BIGINT NOT NULL,
    UPD_TMS TIMESTAMP_NTZ NOT NULL,
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
    HIST_ACTION_CD CHAR(1) COLLATE UTF8_LCASE,
    CO_UPD_TMS TIMESTAMP_NTZ
);

-- Converted the Teradata unique primary index to an informational Delta primary key constraint.
-- TODO: manual review required — Delta is multiset and does not enforce the original SET-table/UPI uniqueness; enforce uniqueness in the write path.
ALTER TABLE AML_CASE_HIST ADD CONSTRAINT XPKAML_CASE_HIST PRIMARY KEY (CASE_ID, UPD_TMS);
