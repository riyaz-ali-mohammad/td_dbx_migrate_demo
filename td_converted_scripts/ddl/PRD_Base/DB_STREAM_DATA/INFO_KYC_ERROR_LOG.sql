-- Converted the Teradata SET table to a Delta table; the source UPI already prevented duplicate ERR_AID values.
-- Target catalog mapping was not supplied, so the source database qualifier is omitted and the table resolves in the current catalog and schema.
-- Removed Teradata FALLBACK, journal, checksum, merge-block-ratio, map, and primary-index storage directives.
-- Removed LATIN character-set clauses and preserved NOT CASESPECIFIC behavior with UTF8_LCASE collation.
-- Converted the timezone-naive Teradata timestamp to TIMESTAMP_NTZ and removed its display-only FORMAT clause.
CREATE TABLE INFO_KYC_ERROR_LOG (
  ERR_AID DECIMAL(12, 0) NOT NULL,
  ERR_NR SMALLINT NOT NULL,
  ERR_CLASS VARCHAR(20) COLLATE UTF8_LCASE NOT NULL,
  ERR_KEY VARCHAR(80) COLLATE UTF8_LCASE NOT NULL,
  ERR_FIELD VARCHAR(30) COLLATE UTF8_LCASE,
  ERR_TABLE VARCHAR(30) COLLATE UTF8_LCASE,
  ERR_TMS TIMESTAMP_NTZ NOT NULL,
  ERR_PGM_SOURCE VARCHAR(50) COLLATE UTF8_LCASE,
  ERR_DESC VARCHAR(200) COLLATE UTF8_LCASE
);

-- TODO: manual review required — the source UNIQUE PRIMARY INDEX enforced ERR_AID uniqueness, but the Delta primary key is informational; enforce uniqueness in the write path.
-- Converted the named UNIQUE PRIMARY INDEX to an informational primary-key constraint.
ALTER TABLE INFO_KYC_ERROR_LOG
  ADD CONSTRAINT XPKKYC_ERROR_LOG PRIMARY KEY (ERR_AID);
