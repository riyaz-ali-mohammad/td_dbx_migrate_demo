-- Converted the Teradata SET table to a Delta table; removed FALLBACK, journal, CHECKSUM, MERGEBLOCKRATIO, and MAP storage clauses.
-- Removed LATIN character-set and display FORMAT metadata, mapped NOT CASESPECIFIC columns to UTF8_LCASE collation, and removed Teradata value compression.
-- Mapped the timezone-naive TIMESTAMP(0) column to TIMESTAMP_NTZ.
-- Replaced the UNIQUE PRIMARY INDEX distribution with liquid clustering and enabled Delta column defaults.
CREATE TABLE SAR_CANDIDATE (
    CASE_ID BIGINT NOT NULL,
    PARTY_ID CHAR(12) COLLATE UTF8_LCASE NOT NULL,
    IDENT_DT DATE NOT NULL,
    SAR_REASON_CD CHAR(4) COLLATE UTF8_LCASE,
    TOTAL_GBP_AMT DECIMAL(18,2),
    SANC_HIT_IND CHAR(1) COLLATE UTF8_LCASE,
    DAML_IND CHAR(1) COLLATE UTF8_LCASE,
    NARRATIVE_SUMMARY VARCHAR(1000) COLLATE UTF8_LCASE,
    SAR_STATUS_CD CHAR(5) COLLATE UTF8_LCASE DEFAULT 'DRAFT',
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
)
CLUSTER BY (CASE_ID)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- TODO: manual review required — the source UNIQUE PRIMARY INDEX enforced CASE_ID uniqueness, while this Delta primary key is informational; enforce uniqueness in the write path.
-- Preserved the UNIQUE PRIMARY INDEX contract as a named informational primary key.
ALTER TABLE SAR_CANDIDATE ADD CONSTRAINT XPKSAR_CANDIDATE PRIMARY KEY (CASE_ID);
