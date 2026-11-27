-- Teradata SET and physical FALLBACK, JOURNAL, CHECKSUM, MERGEBLOCKRATIO, and MAP options are removed for Delta.
-- The source database qualifier is removed because no target Unity Catalog mapping was supplied.
-- CHARACTER SET LATIN is removed; NOT CASESPECIFIC is preserved with UTF8_LCASE collation.
-- Teradata display FORMAT clauses are removed, and timezone-naive TIMESTAMP(0) maps to TIMESTAMP_NTZ.
-- The non-unique secondary index is replaced by liquid clustering on ACCT_ID.
CREATE TABLE PARTY_ACCT_REL (
    PARTY_ID CHAR(12) COLLATE UTF8_LCASE NOT NULL,
    ACCT_ID CHAR(14) COLLATE UTF8_LCASE NOT NULL,
    ROLE_CD CHAR(2) COLLATE UTF8_LCASE NOT NULL,
    START_DT DATE NOT NULL,
    END_DT DATE DEFAULT DATE '9999-12-31',
    OWNERSHIP_PCT DECIMAL(5,2),
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
)
CLUSTER BY (ACCT_ID)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- The Teradata UNIQUE PRIMARY INDEX is represented as an informational Delta primary key.
-- TODO: manual review required — Delta does not enforce the source UPI uniqueness; enforce it in the write pipeline.
ALTER TABLE PARTY_ACCT_REL
    ADD CONSTRAINT XPKPARTY_ACCT_REL PRIMARY KEY (PARTY_ID, ACCT_ID, ROLE_CD, START_DT);
