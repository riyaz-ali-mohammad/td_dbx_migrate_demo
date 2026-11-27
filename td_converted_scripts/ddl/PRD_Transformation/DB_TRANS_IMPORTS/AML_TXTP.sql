-- TODO: manual review required — the source UNIQUE PRIMARY INDEX enforced TXN_TYP_CD uniqueness, but the Delta primary key is informational; enforce uniqueness in the write path
-- Converted the Teradata SET table to a Delta table; its row uniqueness is represented by the source key contract below but is not enforced by Delta
-- Removed the source database qualifier because no target Unity Catalog mapping was supplied
-- Removed Teradata FALLBACK, journal, checksum, merge-block-ratio, and map storage options; Delta manages durability and physical storage
-- Removed LATIN character-set clauses because Databricks stores text as UTF-8, and preserved NOT CASESPECIFIC behavior with UTF8_LCASE collation
CREATE TABLE AML_TXTP (
    TXN_TYP_CD CHAR(4) COLLATE UTF8_LCASE NOT NULL,
    TXN_TYP_DESC VARCHAR(50) COLLATE UTF8_LCASE,
    PAY_SCHEME_CD CHAR(4) COLLATE UTF8_LCASE,
    DIRECTION_CD CHAR(1) COLLATE UTF8_LCASE,
    CASH_IND CHAR(1) COLLATE UTF8_LCASE,
    XBORDER_IND CHAR(1) COLLATE UTF8_LCASE,
    ACTION_CD CHAR(1) COLLATE UTF8_LCASE
);

-- Converted the Teradata UNIQUE PRIMARY INDEX to an informational Delta primary key constraint
ALTER TABLE AML_TXTP ADD CONSTRAINT XPKAML_TXTP PRIMARY KEY (TXN_TYP_CD);
