-- TODO: manual review required — the Teradata SET table and UNIQUE PRIMARY INDEX enforced uniqueness, while Delta primary keys are informational; enforce CCY_CD uniqueness in the write path
-- TODO: manual review required — verify that consumers preserve Teradata CHAR fixed-width padding and bounded CHAR/VARCHAR contracts
-- The source database qualifier was omitted because no target Unity Catalog mapping was supplied; the table resolves in the current catalog and schema.
-- Teradata FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, and MAP storage attributes were removed because Delta manages durability and physical storage.
-- CHARACTER SET LATIN was removed because Databricks uses UTF-8; NOT CASESPECIFIC was mapped to UTF8_LCASE collation.
-- BYTEINT was mapped to TINYINT.
CREATE TABLE AML_CCY (
  CCY_CD CHAR(3) COLLATE UTF8_LCASE NOT NULL,
  CCY_NM VARCHAR(30) COLLATE UTF8_LCASE,
  MINOR_UNIT_CNT TINYINT,
  CCY_NUM_CD CHAR(3) COLLATE UTF8_LCASE,
  ACTIVE_IND CHAR(1) COLLATE UTF8_LCASE,
  ACTION_CD CHAR(1) COLLATE UTF8_LCASE
);

-- The Teradata UNIQUE PRIMARY INDEX was converted to an informational Delta primary key constraint.
ALTER TABLE AML_CCY ADD CONSTRAINT XPKAML_CCY PRIMARY KEY (CCY_CD);
