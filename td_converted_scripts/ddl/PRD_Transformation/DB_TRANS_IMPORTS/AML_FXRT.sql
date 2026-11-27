-- TODO: manual review required — Delta does not enforce Teradata SET or UNIQUE PRIMARY INDEX uniqueness; ensure the write path rejects duplicate keys and full rows.
-- TODO: manual review required — verify fixed-width CHAR padding and trailing-space comparison behavior for downstream consumers.
-- Teradata SET, FALLBACK, journal, CHECKSUM, MERGEBLOCKRATIO, and MAP storage clauses are removed for Delta.
-- The source database qualifier is removed because no target Unity Catalog mapping was supplied.
-- CHARACTER SET LATIN is removed because Databricks uses UTF-8; NOT CASESPECIFIC is preserved with UTF8_LCASE collation.
-- The DATE display FORMAT clause is removed because it does not affect stored values.
CREATE TABLE AML_FXRT (
    CCY_CD CHAR(3) COLLATE UTF8_LCASE NOT NULL,
    RATE_DT DATE NOT NULL,
    RATE_TYP_CD CHAR(2) COLLATE UTF8_LCASE NOT NULL,
    GBP_RATE DECIMAL(18,8),
    ACTION_CD CHAR(1) COLLATE UTF8_LCASE
);

-- The Teradata UNIQUE PRIMARY INDEX is replaced by an informational Delta primary key constraint; physical AMP distribution is removed.
ALTER TABLE AML_FXRT
ADD CONSTRAINT XPKAML_FXRT PRIMARY KEY (CCY_CD, RATE_DT, RATE_TYP_CD);
