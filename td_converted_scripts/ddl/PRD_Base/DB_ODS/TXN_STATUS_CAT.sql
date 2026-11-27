-- TODO: manual review required — Teradata SET table row-uniqueness is lost because Delta permits duplicate rows; enforce de-duplication in every write path.
-- TODO: manual review required — verify bounded CHAR/VARCHAR width and CHAR trailing-space behavior against dependent writes and comparisons.
-- Source database qualifier DB_ODS was removed because no target Unity Catalog mapping was supplied; the table resolves in the current catalog and schema.
-- Teradata FALLBACK, JOURNAL, CHECKSUM, MERGEBLOCKRATIO, and MAP storage options were removed because Delta manages durability and physical storage.
-- CHARACTER SET LATIN was removed because Databricks strings use UTF-8; NOT CASESPECIFIC was mapped to UTF8_LCASE collation.
-- TIMESTAMP(0) was mapped to timezone-naive TIMESTAMP_NTZ, and its display-only FORMAT clause was removed.
-- Column defaults require the Delta allowColumnDefaults table feature.
-- The Teradata UNIQUE PRIMARY INDEX was replaced by liquid clustering; its uniqueness contract is declared separately as an informational primary key.
CREATE TABLE txn_status_cat (
    cd CHAR(2) COLLATE UTF8_LCASE NOT NULL,
    cd_desc VARCHAR(60) COLLATE UTF8_LCASE DEFAULT 'UNKNOWN - AUTO ADDED',
    auto_added_ind CHAR(1) COLLATE UTF8_LCASE DEFAULT 'N',
    co_upd_tms TIMESTAMP_NTZ NOT NULL
)
CLUSTER BY (cd)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- TODO: manual review required — Delta primary keys are informational and do not enforce the source UNIQUE PRIMARY INDEX; enforce cd uniqueness in the write path.
-- The source UNIQUE PRIMARY INDEX name is preserved as the informational primary-key constraint name.
ALTER TABLE txn_status_cat
ADD CONSTRAINT XPKTXN_STATUS_CAT PRIMARY KEY (cd);
