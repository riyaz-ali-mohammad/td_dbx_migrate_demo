-- TODO: manual review required — Teradata SET table row-uniqueness is lost because Delta is multiset; enforce de-duplication in the write path.
-- Converted the Teradata table to a Delta table, removed FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, MAP, and display FORMAT clauses, and left the name unqualified because no target catalog mapping was supplied.
-- Removed LATIN character-set clauses, preserved NOT CASESPECIFIC behavior with UTF8_LCASE collation, and mapped the timezone-naive timestamp to TIMESTAMP_NTZ.
CREATE TABLE INFO_DLYTXN_ERROR_LOG (
    ERR_AID DECIMAL(12, 0) NOT NULL,
    ERR_NR SMALLINT NOT NULL,
    ERR_CLASS VARCHAR(20) COLLATE UTF8_LCASE NOT NULL,
    ERR_KEY VARCHAR(80) COLLATE UTF8_LCASE NOT NULL,
    ERR_FIELD VARCHAR(30) COLLATE UTF8_LCASE,
    ERR_TABLE VARCHAR(30) COLLATE UTF8_LCASE,
    ERR_TMS TIMESTAMP_NTZ NOT NULL,
    ERR_PGM_SOURCE VARCHAR(50) COLLATE UTF8_LCASE,
    ERR_DESC VARCHAR(200) COLLATE UTF8_LCASE,
    BUSINESS_DT DATE
);

-- TODO: manual review required — the source UNIQUE PRIMARY INDEX enforced ERR_AID uniqueness, while the Databricks primary key is informational; enforce uniqueness in the write path.
-- Replaced the source UNIQUE PRIMARY INDEX with an informational primary-key constraint.
ALTER TABLE INFO_DLYTXN_ERROR_LOG
ADD CONSTRAINT XPKDLYTXN_ERROR_LOG PRIMARY KEY (ERR_AID);
