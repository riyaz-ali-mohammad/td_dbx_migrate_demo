-- Teradata database qualification was removed because no target catalog mapping was supplied; the table resolves in the current catalog and schema.
-- Teradata SET semantics were removed; Delta tables use multiset semantics.
-- Teradata FALLBACK, JOURNAL, CHECKSUM, MERGEBLOCKRATIO, and MAP physical-storage options were removed for Delta.
-- CHARACTER SET LATIN was removed because Databricks uses UTF-8; NOT CASESPECIFIC was converted to UTF8_LCASE collation.
CREATE TABLE AML_PRDT (
    PRDT_CD CHAR(6) COLLATE UTF8_LCASE NOT NULL,
    PRDT_DESC VARCHAR(50) COLLATE UTF8_LCASE,
    PRDT_FAMILY_CD CHAR(4) COLLATE UTF8_LCASE,
    SEGMENT_CD CHAR(3) COLLATE UTF8_LCASE,
    PRDT_RISK_CD CHAR(1) COLLATE UTF8_LCASE,
    ACTION_CD CHAR(1) COLLATE UTF8_LCASE
);

-- TODO: manual review required — Delta primary keys are informational; enforce PRDT_CD uniqueness in the write path.
-- Teradata UNIQUE PRIMARY INDEX was converted to an informational primary key constraint.
ALTER TABLE AML_PRDT ADD CONSTRAINT XPKAML_PRDT PRIMARY KEY (PRDT_CD);
