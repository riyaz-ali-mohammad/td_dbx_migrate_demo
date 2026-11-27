-- TODO: manual review required — Teradata SET table row-uniqueness is lost because Delta is multiset; enforce de-duplication in the write path
-- TODO: manual review required — validate bounded VARCHAR and fixed-width CHAR padding/overflow behavior for target writes
-- Converted the Teradata SET table to a Delta table; removed FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, and MAP physical-storage clauses
-- Removed the source database qualifier because no target Unity Catalog mapping was supplied; the table resolves in the current catalog and schema
-- Removed CHARACTER SET clauses because Databricks stores text as UTF-8; preserved NOT CASESPECIFIC with UTF8_LCASE collation
CREATE TABLE SANC_NAME_STG (
    GROUP_ID INT NOT NULL,
    NAME_SEQ_NR SMALLINT NOT NULL,
    FULL_NM VARCHAR(400) COLLATE UTF8_LCASE,
    NORM_NM VARCHAR(400) COLLATE UTF8_LCASE,
    NON_LATIN_NM VARCHAR(200) COLLATE UTF8_LCASE,
    ALIAS_TYP_CD CHAR(3) COLLATE UTF8_LCASE,
    ALIAS_QUALITY_CD CHAR(1) COLLATE UTF8_LCASE
);

-- TODO: manual review required — the Teradata UNIQUE PRIMARY INDEX uniqueness contract becomes an informational Delta primary key; enforce uniqueness in the write path
-- Converted the UNIQUE PRIMARY INDEX to a named informational primary key constraint
ALTER TABLE SANC_NAME_STG
ADD CONSTRAINT XPKSANC_NAME_STG PRIMARY KEY (GROUP_ID, NAME_SEQ_NR);
