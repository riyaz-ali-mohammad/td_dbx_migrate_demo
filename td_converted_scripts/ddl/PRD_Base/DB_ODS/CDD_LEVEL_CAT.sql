-- TODO: manual review required — Teradata SET row-uniqueness is not enforced by Delta; ensure the write path rejects duplicate rows
-- Converted the Teradata two-part name to an unqualified name because no target Unity Catalog mapping was supplied
-- Removed Teradata FALLBACK, journal, checksum, merge-block-ratio, and map storage options; Delta manages durability and storage layout
-- TODO: manual review required — verify bounded CHAR/VARCHAR behavior and CHAR trailing-space semantics in downstream writes and comparisons
-- Removed LATIN character-set clauses and converted NOT CASESPECIFIC columns to UTF8_LCASE collation
-- Converted timezone-naive TIMESTAMP(0) to TIMESTAMP_NTZ and removed the display-only FORMAT clause
-- Enabled the Delta column-default table feature for the retained literal defaults
CREATE TABLE CDD_LEVEL_CAT (
    CD CHAR(3) COLLATE UTF8_LCASE NOT NULL,
    CD_DESC VARCHAR(60) COLLATE UTF8_LCASE DEFAULT 'UNKNOWN - AUTO ADDED',
    AUTO_ADDED_IND CHAR(1) COLLATE UTF8_LCASE DEFAULT 'N',
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- TODO: manual review required — this primary key is informational in Delta, so uniqueness must be enforced by the write path
-- Converted the Teradata UNIQUE PRIMARY INDEX to an informational primary-key constraint
ALTER TABLE CDD_LEVEL_CAT
ADD CONSTRAINT XPKCDD_LEVEL_CAT PRIMARY KEY (CD);
