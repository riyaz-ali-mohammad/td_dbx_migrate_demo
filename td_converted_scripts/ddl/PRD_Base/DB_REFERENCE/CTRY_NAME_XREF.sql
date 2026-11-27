-- Converted the Teradata two-part name to an unqualified table because no target catalog mapping was supplied.
-- Removed SET and Teradata physical storage, journal, checksum, merge-block, map, and primary-index clauses.
-- Removed CHARACTER SET LATIN and translated NOT CASESPECIFIC to a case-insensitive UTF-8 collation.
-- TODO: manual review required — verify bounded VARCHAR/CHAR and fixed-width CHAR behavior against dependent consumers.
CREATE TABLE ctry_name_xref (
  ctry_nm_txt VARCHAR(60) COLLATE UTF8_LCASE NOT NULL,
  ctry_2_cd CHAR(2) COLLATE UTF8_LCASE NOT NULL
);

-- Converted the UNIQUE PRIMARY INDEX contract to an informational Delta primary key.
-- TODO: manual review required — Delta primary keys are informational; enforce ctry_nm_txt uniqueness in the write path.
ALTER TABLE ctry_name_xref
  ADD CONSTRAINT XPKCTRY_NAME_XREF PRIMARY KEY (ctry_nm_txt);
