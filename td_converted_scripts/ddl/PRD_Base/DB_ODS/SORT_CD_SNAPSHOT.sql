-- Converted the Teradata SET table to a Delta table; removed the source database qualifier because no target catalog mapping was supplied.
-- Removed Teradata FALLBACK, journal, checksum, merge-block-ratio, and map storage options; Delta manages durability and storage layout.
-- Removed CHARACTER SET LATIN because Databricks stores strings as UTF-8, and preserved NOT CASESPECIFIC with UTF8_LCASE collation.
-- TODO: manual review required — confirm downstream logic preserves the fixed-width padding and comparison behavior of the CHAR columns.
CREATE TABLE SORT_CD_SNAPSHOT (
  SORT_CD CHAR(6) COLLATE UTF8_LCASE NOT NULL,
  BIC_CD CHAR(11) COLLATE UTF8_LCASE,
  CLOSED_IND CHAR(1) COLLATE UTF8_LCASE
);

-- Replaced the Teradata unique primary index with an informational Delta primary key; physical AMP distribution is not applicable.
-- TODO: manual review required — Delta does not enforce the source unique primary index; enforce SORT_CD uniqueness in the write path.
ALTER TABLE SORT_CD_SNAPSHOT
  ADD CONSTRAINT XPKSORT_CD_SNAPSHOT PRIMARY KEY (SORT_CD);
