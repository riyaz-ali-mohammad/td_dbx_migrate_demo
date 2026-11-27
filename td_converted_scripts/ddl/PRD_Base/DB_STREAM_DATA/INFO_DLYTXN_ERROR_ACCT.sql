-- Converted the Teradata SET table to a Delta table; stripped FALLBACK, JOURNAL, CHECKSUM, MERGEBLOCKRATIO, MAP, CHARACTER SET, and display FORMAT clauses; mapped NOT CASESPECIFIC to UTF8_LCASE and the naive timestamp to TIMESTAMP_NTZ.
-- TODO: manual review required — Delta does not enforce Teradata SET row uniqueness; ensure the controlled write path rejects duplicate rows.
-- TODO: manual review required — confirm that consumers preserve the source CHAR fixed-width padding and trailing-space comparison behavior.
CREATE TABLE INFO_DLYTXN_ERROR_ACCT (
    ACCT_ID CHAR(14) COLLATE UTF8_LCASE NOT NULL,
    SORT_CD CHAR(6) COLLATE UTF8_LCASE,
    ACCT_NR CHAR(8) COLLATE UTF8_LCASE,
    TXN_CNT INTEGER,
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
)
CLUSTER BY (ACCT_ID);

-- Converted the Teradata UNIQUE PRIMARY INDEX to an informational Delta primary key; liquid clustering replaces its physical distribution role.
-- TODO: manual review required — Delta primary keys are informational, so ACCT_ID uniqueness must be enforced by the write path.
ALTER TABLE INFO_DLYTXN_ERROR_ACCT
ADD CONSTRAINT XPKINFO_DLYTXN_ERROR_ACCT PRIMARY KEY (ACCT_ID);
