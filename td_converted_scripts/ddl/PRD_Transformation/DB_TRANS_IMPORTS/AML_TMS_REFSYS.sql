-- Teradata SET and physical storage options are removed; Delta uses multiset semantics and manages resilience, journaling, checksums, block layout, and data placement.
-- The source database qualifier is omitted because no target Unity Catalog mapping was supplied; the table resolves in the current catalog and schema.
-- BYTEINT maps to TINYINT, and timezone-naive TIMESTAMP(0) maps to TIMESTAMP_NTZ; the display-only FORMAT clause is removed.
CREATE TABLE AML_TMS_REFSYS (
  SSQ_ID TINYINT NOT NULL,
  TMS TIMESTAMP_NTZ NOT NULL
);

-- TODO: manual review required — the Teradata UNIQUE PRIMARY INDEX enforced SSQ_ID uniqueness, while the Delta primary key is informational; enforce uniqueness in the write path.
-- The Teradata UNIQUE PRIMARY INDEX is represented as an informational Delta primary key.
ALTER TABLE AML_TMS_REFSYS
  ADD CONSTRAINT XPKAML_TMS_REFSYS PRIMARY KEY (SSQ_ID);
