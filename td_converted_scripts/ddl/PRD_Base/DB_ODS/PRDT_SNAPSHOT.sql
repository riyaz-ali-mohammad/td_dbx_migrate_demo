-- TODO: manual review required — Delta does not enforce Teradata SET or UNIQUE PRIMARY INDEX uniqueness; enforce uniqueness in the write path
-- TODO: manual review required — verify fixed-width CHAR padding and trailing-space comparison behavior for migrated consumers
-- Converted the two-part Teradata name to an unqualified table because no target catalog mapping was supplied
-- Removed Teradata SET, FALLBACK, journal, checksum, merge-block-ratio, map, and character-set clauses
-- Replaced NOT CASESPECIFIC with the UTF8_LCASE collation
CREATE TABLE PRDT_SNAPSHOT (
    PRDT_CD CHAR(6) COLLATE UTF8_LCASE NOT NULL,
    PRDT_FAMILY_CD CHAR(4) COLLATE UTF8_LCASE,
    SEGMENT_CD CHAR(3) COLLATE UTF8_LCASE,
    PRDT_RISK_CD CHAR(1) COLLATE UTF8_LCASE
);

-- Converted the UNIQUE PRIMARY INDEX to an informational primary key; Delta does not enforce key uniqueness
ALTER TABLE PRDT_SNAPSHOT
ADD CONSTRAINT XPKPRDT_SNAPSHOT PRIMARY KEY (PRDT_CD);
