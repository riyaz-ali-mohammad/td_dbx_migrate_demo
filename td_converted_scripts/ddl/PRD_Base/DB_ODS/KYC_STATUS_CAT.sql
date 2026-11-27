-- TODO: manual review required — the Teradata UNIQUE PRIMARY INDEX enforced CD uniqueness; the Databricks PRIMARY KEY is informational, so enforce uniqueness in the write path.
-- TODO: manual review required — confirm bounded CHAR/VARCHAR padding and length behavior matches downstream workload expectations.
-- The two-part Teradata name is left unqualified because no target Unity Catalog mapping was supplied.
-- Teradata SET, FALLBACK, journal, CHECKSUM, MERGEBLOCKRATIO, MAP, and primary-index distribution clauses were removed for Delta.
-- CHARACTER SET LATIN was removed because Databricks uses UTF-8; NOT CASESPECIFIC was mapped to UTF8_LCASE collation.
-- The Teradata TIMESTAMP display FORMAT was removed, and the timezone-naive TIMESTAMP was mapped to TIMESTAMP_NTZ.
-- Delta column defaults require the allowColumnDefaults table feature.
CREATE TABLE kyc_status_cat (
  cd CHAR(2) COLLATE UTF8_LCASE NOT NULL,
  cd_desc VARCHAR(60) COLLATE UTF8_LCASE DEFAULT 'UNKNOWN - AUTO ADDED',
  auto_added_ind CHAR(1) COLLATE UTF8_LCASE DEFAULT 'N',
  co_upd_tms TIMESTAMP_NTZ NOT NULL
)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- The Teradata UNIQUE PRIMARY INDEX was replaced by an informational Databricks PRIMARY KEY constraint.
ALTER TABLE kyc_status_cat
  ADD CONSTRAINT XPKKYC_STATUS_CAT PRIMARY KEY (cd);
