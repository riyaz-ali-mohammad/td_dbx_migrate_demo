-- Source database qualifier omitted because no target Unity Catalog mapping was supplied.
-- Teradata SET is omitted; the UNIQUE PRIMARY INDEX already prevented duplicate ACCT_ID values.
-- Teradata FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, and MAP physical-storage clauses are omitted for Delta.
-- CHARACTER SET LATIN is omitted because Databricks uses UTF-8; NOT CASESPECIFIC is preserved with UTF8_LCASE collation.
-- Teradata DATE FORMAT 'YYYY-MM-DD' display metadata is omitted because it matches Databricks DATE rendering.
-- UNIQUE PRIMARY INDEX distribution is replaced with adaptive liquid clustering; its key contract is added below.
CREATE TABLE KYC_ACCT_STG (
    ACCT_ID CHAR(14) COLLATE UTF8_LCASE NOT NULL,
    SORT_CD CHAR(6) COLLATE UTF8_LCASE,
    ACCT_NR CHAR(8) COLLATE UTF8_LCASE,
    PRDT_CD CHAR(6) COLLATE UTF8_LCASE,
    CCY_CD CHAR(3) COLLATE UTF8_LCASE,
    OPEN_DT DATE,
    CLOSE_DT DATE,
    ACCT_STATUS_CD CHAR(1) COLLATE UTF8_LCASE,
    PRIMARY_PARTY_ID CHAR(12) COLLATE UTF8_LCASE,
    OD_LIMIT_AMT DECIMAL(18,2),
    LAST_CUST_ACTV_DT DATE,
    OPEN_CHNL_CD CHAR(3) COLLATE UTF8_LCASE,
    ACTION_CD CHAR(1) COLLATE UTF8_LCASE
)
CLUSTER BY AUTO;

-- TODO: manual review required — Delta PRIMARY KEY metadata is informational; enforce ACCT_ID uniqueness in the write path.
-- Teradata UNIQUE PRIMARY INDEX XPKKYC_ACCT_STG is represented as an informational primary key.
ALTER TABLE KYC_ACCT_STG
ADD CONSTRAINT XPKKYC_ACCT_STG PRIMARY KEY (ACCT_ID);
