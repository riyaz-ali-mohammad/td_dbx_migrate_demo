-- Teradata database qualifier removed because no target catalog/schema mapping was supplied.
-- Teradata SET, FALLBACK, journal, CHECKSUM, MERGEBLOCKRATIO, and MAP physical clauses were removed for Delta.
-- CHARACTER SET LATIN was removed because Databricks uses UTF-8; NOT CASESPECIFIC became UTF8_LCASE collation.
-- The DATE display FORMAT was removed because it does not affect stored values.
-- The Teradata UPI columns are used for liquid clustering.
CREATE TABLE DLYTXN_GBP (
    TXN_REF VARCHAR(35) COLLATE UTF8_LCASE NOT NULL,
    SUPPLIER_CD CHAR(4) COLLATE UTF8_LCASE NOT NULL,
    TXN_CCY CHAR(3) COLLATE UTF8_LCASE,
    TXN_AMT DECIMAL(18,2),
    RATE_DT DATE,
    GBP_RATE DECIMAL(18,8),
    GBP_AMT DECIMAL(18,2),
    RATE_FALLBACK_IND CHAR(1) COLLATE UTF8_LCASE
)
CLUSTER BY (TXN_REF, SUPPLIER_CD);

-- TODO: manual review required — the Teradata UNIQUE PRIMARY INDEX and SET-table uniqueness are not enforced by Delta; enforce duplicate rejection in the write path.
-- The Teradata UNIQUE PRIMARY INDEX is retained as an informational Delta primary key.
ALTER TABLE DLYTXN_GBP
ADD CONSTRAINT XPKDLYTXN_GBP PRIMARY KEY (TXN_REF, SUPPLIER_CD);
