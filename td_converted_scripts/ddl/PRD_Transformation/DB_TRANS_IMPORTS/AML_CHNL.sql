-- Converted the Teradata SET table to a Delta table; the existing unique index, rather than SET row de-duplication, supplied the stronger uniqueness contract.
-- Removed Teradata FALLBACK, journal, checksum, merge-block-ratio, map, and LATIN character-set storage clauses because Delta manages resilience and storage and uses UTF-8.
-- No target catalog mapping was supplied, so the source database qualifier was removed and the table resolves in the current catalog and schema.
-- Converted NOT CASESPECIFIC columns to case-insensitive Databricks collations and retained bounded CHAR/VARCHAR types.
-- Converted the Teradata primary-index layout to liquid clustering on CHNL_CD.
CREATE TABLE AML_CHNL (
    CHNL_CD CHAR(3) COLLATE UTF8_LCASE NOT NULL,
    CHNL_DESC VARCHAR(40) COLLATE UTF8_LCASE,
    DIGITAL_IND CHAR(1) COLLATE UTF8_LCASE,
    ACTION_CD CHAR(1) COLLATE UTF8_LCASE
)
CLUSTER BY (CHNL_CD);

-- Converted the UNIQUE PRIMARY INDEX to an informational primary key; Databricks does not enforce uniqueness.
-- TODO: manual review required — enforce CHNL_CD uniqueness in the write path because the Databricks primary key is informational.
ALTER TABLE AML_CHNL ADD CONSTRAINT XPKAML_CHNL PRIMARY KEY (CHNL_CD);
