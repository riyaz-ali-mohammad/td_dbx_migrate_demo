-- Teradata SET becomes a plain Delta table; the source UPI is represented by an informational primary key below.
-- DB_ODS.ACCT is left unqualified because no target Unity Catalog mapping was supplied.
-- Teradata FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, MAP, and the non-unique secondary index were removed.
-- CHARACTER SET LATIN was removed, NOT CASESPECIFIC uses UTF8_LCASE collation, DATE FORMAT clauses were removed, and the naive TIMESTAMP maps to TIMESTAMP_NTZ.
CREATE TABLE ACCT (
    ACCT_ID CHAR(14) COLLATE UTF8_LCASE NOT NULL,
    SORT_CD CHAR(6) COLLATE UTF8_LCASE,
    ACCT_NR CHAR(8) COLLATE UTF8_LCASE,
    PRDT_CD CHAR(6) COLLATE UTF8_LCASE,
    CCY_CD CHAR(3) COLLATE UTF8_LCASE,
    OPEN_DT DATE,
    CLOSE_DT DATE,
    ACCT_STATUS_CD CHAR(1) COLLATE UTF8_LCASE,
    PRIMARY_PARTY_ID CHAR(12) COLLATE UTF8_LCASE,
    OD_LIMIT_AMT DECIMAL(18, 2),
    LAST_CUST_ACTV_DT DATE,
    OPEN_CHNL_CD CHAR(3) COLLATE UTF8_LCASE,
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
);

-- TODO: manual review required — Teradata UNIQUE PRIMARY INDEX enforcement is not preserved by Delta's informational primary key; enforce ACCT_ID uniqueness in the write pipeline.
-- Teradata UNIQUE PRIMARY INDEX XPKACCT is represented as an informational Delta primary key.
ALTER TABLE ACCT ADD CONSTRAINT XPKACCT PRIMARY KEY (ACCT_ID);
