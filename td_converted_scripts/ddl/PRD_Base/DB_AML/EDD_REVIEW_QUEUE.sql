-- TODO: manual review required — Teradata SET table row-uniqueness is lost because Delta is multiset; enforce de-duplication in the write path
-- TODO: manual review required — verify fixed-width CHAR padding and trailing-space behavior in dependent reads and writes
-- Converted the Teradata two-part name to an unqualified target name because no Unity Catalog mapping was supplied
-- Removed Teradata FALLBACK, journal, checksum, merge-block-ratio, and map storage clauses because Delta manages storage and resilience
-- Removed LATIN character-set clauses and mapped NOT CASESPECIFIC columns to UTF8_LCASE collation
-- Removed Teradata display-only FORMAT clauses and mapped the timezone-naive TIMESTAMP to TIMESTAMP_NTZ
-- Enabled the Delta column-default feature for REVIEW_STATUS_CD
CREATE TABLE EDD_REVIEW_QUEUE (
    PARTY_ID CHAR(12) COLLATE UTF8_LCASE NOT NULL,
    TRIGGER_DT DATE NOT NULL,
    TRIGGER_REASON_CD CHAR(4) COLLATE UTF8_LCASE NOT NULL,
    RISK_BAND_CD CHAR(2) COLLATE UTF8_LCASE,
    PREV_RISK_BAND_CD CHAR(2) COLLATE UTF8_LCASE,
    DUE_DT DATE,
    REVIEW_STATUS_CD CHAR(4) COLLATE UTF8_LCASE DEFAULT 'OPEN',
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- TODO: manual review required — Delta primary keys are informational; enforce the source UNIQUE PRIMARY INDEX uniqueness in the write path
-- Replaced the Teradata UNIQUE PRIMARY INDEX with a named informational primary-key constraint
ALTER TABLE EDD_REVIEW_QUEUE
ADD CONSTRAINT XPKEDD_REVIEW_QUEUE PRIMARY KEY (PARTY_ID, TRIGGER_DT, TRIGGER_REASON_CD);
