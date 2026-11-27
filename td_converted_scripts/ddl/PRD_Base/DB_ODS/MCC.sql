-- TODO: manual review required — Teradata SET table row uniqueness is lost because Delta uses multiset semantics; enforce de-duplication in every write path.
-- TODO: manual review required — verify that fixed-width CHAR padding and bounded VARCHAR behavior remain compatible with dependent workloads.
-- Converted the two-part Teradata name to an unqualified table because no target Unity Catalog mapping was supplied.
-- Removed Teradata FALLBACK, journal, checksum, merge-block-ratio, and map storage options; Delta manages durability and storage layout.
-- Removed display-only FORMAT clauses, removed LATIN character-set clauses, and preserved NOT CASESPECIFIC behavior with UTF8_LCASE collation.
-- Mapped the timezone-naive Teradata TIMESTAMP to TIMESTAMP_NTZ and enabled the Delta column-default feature.
CREATE TABLE mcc (
  mcc_cd CHAR(4) COLLATE UTF8_LCASE NOT NULL,
  start_dt DATE NOT NULL,
  end_dt DATE NOT NULL DEFAULT DATE '9999-12-31',
  mcc_desc VARCHAR(50) COLLATE UTF8_LCASE,
  mcc_risk_cd CHAR(1) COLLATE UTF8_LCASE,
  cash_like_ind CHAR(1) COLLATE UTF8_LCASE,
  gambling_ind CHAR(1) COLLATE UTF8_LCASE,
  crypto_ind CHAR(1) COLLATE UTF8_LCASE,
  co_upd_tms TIMESTAMP_NTZ NOT NULL
)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- TODO: manual review required — the UNIQUE PRIMARY INDEX became an informational PRIMARY KEY and no longer enforces uniqueness; enforce the key in the write path.
-- Replaced the Teradata UNIQUE PRIMARY INDEX with a named informational Delta primary-key constraint.
ALTER TABLE mcc ADD CONSTRAINT xpkmcc PRIMARY KEY (mcc_cd, start_dt);
