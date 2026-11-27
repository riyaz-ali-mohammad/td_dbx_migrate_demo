-- TODO: manual review required — Teradata SET row uniqueness and UNIQUE PRIMARY INDEX enforcement are not preserved by Delta; enforce de-duplication and key uniqueness in the write path.
-- TODO: manual review required — verify bounded VARCHAR/CHAR behavior, including CHAR padding, against all ingestion paths.
-- NOTE: Source LATIN data must be transcoded to UTF-8 during ingestion if its bytes are not valid UTF-8.
-- Converted the Teradata SET table to Delta, removed platform-specific storage, journal, map, and distribution clauses, and mapped NOT CASESPECIFIC to UTF8_LCASE collation.
CREATE TABLE SANC_REGIME_CTRY (
    REGIME_NM VARCHAR(100) COLLATE UTF8_LCASE NOT NULL,
    CTRY_2_CD CHAR(2) COLLATE UTF8_LCASE NOT NULL,
    COMPREHENSIVE_IND CHAR(1) COLLATE UTF8_LCASE
);

-- Converted the UNIQUE PRIMARY INDEX to an informational Delta primary key; Delta does not enforce key uniqueness.
ALTER TABLE SANC_REGIME_CTRY
ADD CONSTRAINT XPKSANC_REGIME_CTRY PRIMARY KEY (REGIME_NM, CTRY_2_CD);
