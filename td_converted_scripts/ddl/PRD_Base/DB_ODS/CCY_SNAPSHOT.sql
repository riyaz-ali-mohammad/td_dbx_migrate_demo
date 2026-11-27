-- TODO: manual review required — Teradata SET table row-uniqueness is lost because Delta is multiset; enforce de-duplication in the write path
-- Converted the source two-part name to an unqualified table because no target catalog mapping was supplied
-- Removed Teradata FALLBACK, journal, checksum, merge-block-ratio, and map physical-storage clauses
-- TODO: manual review required — validate that CHAR(3) fixed-width padding and trailing-space comparison behavior is preserved for consumers
-- Removed the LATIN character-set clause, translated NOT CASESPECIFIC to UTF8_LCASE collation, and mapped BYTEINT to TINYINT
CREATE TABLE CCY_SNAPSHOT (
    CCY_CD CHAR(3) COLLATE UTF8_LCASE NOT NULL,
    MINOR_UNIT_CNT TINYINT
);

-- TODO: manual review required — the primary key converted from the Teradata unique primary index is informational and does not enforce uniqueness in Delta
-- Replaced the Teradata unique primary index with a named informational primary key
ALTER TABLE CCY_SNAPSHOT
ADD CONSTRAINT XPKCCY_SNAPSHOT PRIMARY KEY (CCY_CD);
