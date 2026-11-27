-- TODO: manual review required — Teradata SET table row-uniqueness is lost (Delta is multiset); de-dup at load (SELECT DISTINCT / MERGE) or add a constraint
-- Converted the source database-qualified name to an unqualified table because no target Unity Catalog mapping was supplied.
-- Removed Teradata FALLBACK, JOURNAL, CHECKSUM, MERGEBLOCKRATIO, and MAP physical-storage clauses; Delta manages durability and storage layout.
-- Removed LATIN character-set clauses because Databricks strings use UTF-8, and converted NOT CASESPECIFIC to UTF8_LCASE collation.
-- Replaced the Teradata unique primary index with an informational primary-key constraint; Databricks does not enforce uniqueness.
CREATE TABLE NAME_NOISE_WORD (
    NOISE_WORD VARCHAR(30) COLLATE UTF8_LCASE NOT NULL,
    WORD_TYP_CD CHAR(2) COLLATE UTF8_LCASE,
    CONSTRAINT XPKNAME_NOISE_WORD PRIMARY KEY (NOISE_WORD)
);
