-- TODO: manual review required — verify fixed-width CHAR padding behavior in downstream writes and comparisons.
-- Converted the Teradata SET table to a Delta table; Delta has multiset write semantics.
-- Removed the source database qualifier because no target Unity Catalog mapping was supplied.
-- Removed FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, MAP, and LATIN character-set clauses.
-- Replaced NOT CASESPECIFIC with the UTF8_LCASE collation and preserved declared CHAR/VARCHAR widths.
CREATE TABLE AML_SORT (
    SORT_CD CHAR(6) COLLATE UTF8_LCASE NOT NULL,
    BANK_NM VARCHAR(40) COLLATE UTF8_LCASE,
    BRANCH_NM VARCHAR(40) COLLATE UTF8_LCASE,
    BIC_CD CHAR(11) COLLATE UTF8_LCASE,
    FPS_IND CHAR(1) COLLATE UTF8_LCASE,
    CHAPS_IND CHAR(1) COLLATE UTF8_LCASE,
    BACS_IND CHAR(1) COLLATE UTF8_LCASE,
    CLOSED_IND CHAR(1) COLLATE UTF8_LCASE,
    POSTCODE VARCHAR(8) COLLATE UTF8_LCASE,
    ACTION_CD CHAR(1) COLLATE UTF8_LCASE
);

-- TODO: manual review required — Delta PRIMARY KEY metadata is informational; enforce SORT_CD uniqueness in the write path.
-- Converted the UNIQUE PRIMARY INDEX to a named informational PRIMARY KEY constraint.
ALTER TABLE AML_SORT ADD CONSTRAINT XPKAML_SORT PRIMARY KEY (SORT_CD);
