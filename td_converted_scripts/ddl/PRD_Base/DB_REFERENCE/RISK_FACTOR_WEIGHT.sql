-- Teradata database qualifier omitted because no target Unity Catalog mapping was supplied; the table resolves in the current catalog and schema.
-- Teradata SET, FALLBACK, journal, CHECKSUM, MERGEBLOCKRATIO, and MAP storage clauses have no Delta DDL equivalent and were removed.
-- CHARACTER SET LATIN was removed because Databricks SQL stores strings as UTF-8; NOT CASESPECIFIC is preserved with UTF8_LCASE collation.
CREATE TABLE RISK_FACTOR_WEIGHT (
    FACTOR_CD CHAR(8) COLLATE UTF8_LCASE NOT NULL,
    FACTOR_VALUE_CD VARCHAR(20) COLLATE UTF8_LCASE NOT NULL,
    SCORE_PTS SMALLINT NOT NULL,
    FACTOR_DESC VARCHAR(60) COLLATE UTF8_LCASE
);

-- Teradata UNIQUE PRIMARY INDEX distribution was removed and its key contract is retained as an informational Delta primary key.
-- TODO: manual review required — Delta primary keys are informational; enforce FACTOR_CD and FACTOR_VALUE_CD uniqueness in the write path.
ALTER TABLE RISK_FACTOR_WEIGHT
ADD CONSTRAINT XPKRISK_FACTOR_WEIGHT PRIMARY KEY (FACTOR_CD, FACTOR_VALUE_CD);
