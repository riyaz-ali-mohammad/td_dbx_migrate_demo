-- TODO: manual review required — Delta primary keys are informational; enforce SIC_CD uniqueness in the write path to preserve the Teradata UNIQUE PRIMARY INDEX contract.
-- TODO: manual review required — verify fixed-width CHAR padding and trailing-space behavior for downstream consumers.
-- Teradata SET, FALLBACK, journaling, CHECKSUM, MERGEBLOCKRATIO, and MAP storage clauses were removed because Delta does not use them.
-- The DB_ODS qualifier was removed because no target Unity Catalog mapping was supplied; the table resolves in the current catalog and schema.
-- CHARACTER SET LATIN was removed because Databricks uses UTF-8; NOT CASESPECIFIC is preserved with UTF8_LCASE collation.
CREATE TABLE SIC_SNAPSHOT (
    SIC_CD CHAR(5) COLLATE UTF8_LCASE NOT NULL,
    SIC_RISK_CD CHAR(1) COLLATE UTF8_LCASE,
    CASH_INTENSIVE_IND CHAR(1) COLLATE UTF8_LCASE
);

-- The Teradata UNIQUE PRIMARY INDEX was converted to an informational primary-key constraint.
ALTER TABLE SIC_SNAPSHOT
ADD CONSTRAINT XPKSIC_SNAPSHOT PRIMARY KEY (SIC_CD);
