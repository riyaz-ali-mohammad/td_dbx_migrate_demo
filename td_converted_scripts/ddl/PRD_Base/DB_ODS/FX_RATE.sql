-- TODO: manual review required — Teradata SET table row-uniqueness is lost (Delta is multiset); de-dup at load (SELECT DISTINCT / MERGE) or add a constraint
-- TODO: manual review required — verify fixed-width CHAR padding and trailing-space comparison behavior for migrated consumers
-- Converted the source two-part name to an unqualified target name because no Unity Catalog mapping was supplied.
-- Stripped Teradata SET, FALLBACK, journal, checksum, merge-block-ratio, map, character-set, and display-format clauses.
-- Converted NOT CASESPECIFIC columns to UTF8_LCASE collation and timezone-naive TIMESTAMP(0) to TIMESTAMP_NTZ.
-- Replaced the Teradata primary-index layout with Delta liquid clustering on the same key columns.
CREATE TABLE FX_RATE (
    CCY_CD CHAR(3) COLLATE UTF8_LCASE NOT NULL,
    RATE_DT DATE NOT NULL,
    RATE_TYP_CD CHAR(2) COLLATE UTF8_LCASE NOT NULL,
    GBP_RATE DECIMAL(18, 8) NOT NULL,
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
)
CLUSTER BY (CCY_CD, RATE_DT, RATE_TYP_CD);

-- TODO: manual review required — Delta primary keys are informational; enforce XPKFX_RATE uniqueness in the write path
-- Converted the Teradata UNIQUE PRIMARY INDEX to an informational Delta primary-key constraint.
ALTER TABLE FX_RATE
ADD CONSTRAINT XPKFX_RATE PRIMARY KEY (CCY_CD, RATE_DT, RATE_TYP_CD);
