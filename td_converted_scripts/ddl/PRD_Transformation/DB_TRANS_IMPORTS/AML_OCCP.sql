-- assumption: No target catalog/schema mapping was supplied; AML_OCCP resolves in the current catalog and schema.
-- Removed Teradata SET, FALLBACK, JOURNAL, CHECKSUM, MERGEBLOCKRATIO, MAP, and primary-index storage clauses.
-- TODO: manual review required — verify bounded CHAR/VARCHAR and fixed-width CHAR padding behavior for dependent writes and comparisons.
-- Stripped CHARACTER SET LATIN because Databricks strings are UTF-8; mapped NOT CASESPECIFIC to UTF8_LCASE collation.
CREATE TABLE AML_OCCP (
    SIC_CD CHAR(5) COLLATE UTF8_LCASE NOT NULL,
    SIC_DESC VARCHAR(60) COLLATE UTF8_LCASE,
    SIC_RISK_CD CHAR(1) COLLATE UTF8_LCASE,
    CASH_INTENSIVE_IND CHAR(1) COLLATE UTF8_LCASE,
    ACTION_CD CHAR(1) COLLATE UTF8_LCASE
);

-- Replaced the Teradata unique primary index with an informational Delta primary key.
-- TODO: manual review required — Delta primary keys are informational; enforce SIC_CD uniqueness in the write path.
ALTER TABLE AML_OCCP ADD CONSTRAINT XPKAML_OCCP PRIMARY KEY (SIC_CD);
