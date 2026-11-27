-- Source database qualifier DB_ODS was omitted because no target Unity Catalog mapping was supplied.
-- Converted SET TABLE to CREATE TABLE; Delta has multiset semantics.
-- Removed Teradata FALLBACK, journal, CHECKSUM, MERGEBLOCKRATIO, and MAP physical-storage clauses.
-- Removed CHARACTER SET LATIN because Databricks uses UTF-8; preserved NOT CASESPECIFIC with UTF8_LCASE collation.
CREATE TABLE MCC_SNAPSHOT (
    MCC_CD CHAR(4) COLLATE UTF8_LCASE NOT NULL,
    MCC_RISK_CD CHAR(1) COLLATE UTF8_LCASE,
    CASH_LIKE_IND CHAR(1) COLLATE UTF8_LCASE,
    GAMBLING_IND CHAR(1) COLLATE UTF8_LCASE,
    CRYPTO_IND CHAR(1) COLLATE UTF8_LCASE
);

-- Converted the Teradata UNIQUE PRIMARY INDEX to a Delta informational PRIMARY KEY.
-- TODO: manual review required — Delta does not enforce the source UPI or SET-table uniqueness; enforce uniqueness in the write path.
ALTER TABLE MCC_SNAPSHOT
    ADD CONSTRAINT XPKMCC_SNAPSHOT PRIMARY KEY (MCC_CD);
