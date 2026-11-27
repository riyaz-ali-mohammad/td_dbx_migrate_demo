-- TODO: manual review required — Teradata SET table row uniqueness is lost because Delta uses multiset semantics; enforce de-duplication in the write path.
-- TODO: manual review required — verify CHAR trailing-space behavior for cd and auto_added_ind because Delta comparisons may differ from Teradata fixed-width semantics.
-- TODO: manual review required — verify bounded VARCHAR behavior for cd_desc on the target runtime.
-- Teradata storage, journaling, checksum, merge-block-ratio, map, and primary-index layout clauses were removed because Delta manages resilience and physical layout.
-- The source database qualifier was removed because no target Unity Catalog mapping was supplied.
-- LATIN character-set clauses were removed because Databricks uses UTF-8; NOT CASESPECIFIC is represented with UTF8_LCASE collation.
-- TIMESTAMP(0) was converted to timezone-naive TIMESTAMP_NTZ, and its display-only FORMAT clause was removed.
-- Column defaults require the Delta allowColumnDefaults table feature.
CREATE TABLE purpose_cat (
  cd CHAR(4) COLLATE UTF8_LCASE NOT NULL,
  cd_desc VARCHAR(60) COLLATE UTF8_LCASE DEFAULT 'UNKNOWN - AUTO ADDED',
  auto_added_ind CHAR(1) COLLATE UTF8_LCASE DEFAULT 'N',
  co_upd_tms TIMESTAMP_NTZ NOT NULL
)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- TODO: manual review required — this informational primary key does not enforce the source UNIQUE PRIMARY INDEX; preserve uniqueness in the write path.
-- The Teradata UNIQUE PRIMARY INDEX was converted to informational primary-key metadata.
ALTER TABLE purpose_cat ADD CONSTRAINT xpkpurpose_cat PRIMARY KEY (cd);
