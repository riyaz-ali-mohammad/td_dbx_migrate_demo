-- TODO: manual review required — Delta does not enforce Teradata SET-table or UPI uniqueness; enforce MCC_CD and full-row uniqueness in the write path.
-- TODO: manual review required — verify fixed-width CHAR blank-padding and trailing-space behavior against the target runtime.
-- Converted the source two-part name to an unqualified target name because no target catalog mapping was supplied.
-- Removed Teradata SET, FALLBACK, JOURNAL, CHECKSUM, MERGEBLOCKRATIO, and MAP storage/distribution clauses.
-- Removed CHARACTER SET LATIN because Databricks strings use UTF-8; converted NOT CASESPECIFIC to UTF8_LCASE collation.
CREATE TABLE AML_MCC (
    MCC_CD CHAR(4) COLLATE UTF8_LCASE NOT NULL,
    MCC_DESC VARCHAR(50) COLLATE UTF8_LCASE,
    MCC_RISK_CD CHAR(1) COLLATE UTF8_LCASE,
    CASH_LIKE_IND CHAR(1) COLLATE UTF8_LCASE,
    GAMBLING_IND CHAR(1) COLLATE UTF8_LCASE,
    CRYPTO_IND CHAR(1) COLLATE UTF8_LCASE,
    ACTION_CD CHAR(1) COLLATE UTF8_LCASE
);

-- Converted the Teradata UNIQUE PRIMARY INDEX to an informational Delta primary key.
ALTER TABLE AML_MCC ADD CONSTRAINT XPKAML_MCC PRIMARY KEY (MCC_CD);
