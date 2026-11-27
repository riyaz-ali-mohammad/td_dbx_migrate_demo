-- Converted the Teradata SET table to Delta table syntax; Delta permits duplicate rows.
-- Stripped FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, and MAP physical-storage clauses.
-- Left the table unqualified because no target catalog and schema mapping was supplied.
-- Stripped LATIN character-set clauses and mapped NOT CASESPECIFIC to UTF8_LCASE collation.
-- TODO: manual review required — verify that target CHAR fixed-width padding and overflow behavior matches dependent workloads.
-- Removed Teradata DATE display FORMAT clauses; DATE values retain the same stored semantics.
-- Enabled the Delta column-default feature for PLACEHOLDER_IND.
CREATE TABLE ACCT_SNAPSHOT (
    ACCT_ID CHAR(14) COLLATE UTF8_LCASE NOT NULL,
    PRIMARY_PARTY_ID CHAR(12) COLLATE UTF8_LCASE,
    PRDT_CD CHAR(6) COLLATE UTF8_LCASE,
    SEGMENT_CD CHAR(3) COLLATE UTF8_LCASE,
    ACCT_STATUS_CD CHAR(1) COLLATE UTF8_LCASE,
    OPEN_DT DATE,
    LAST_CUST_ACTV_DT DATE,
    PLACEHOLDER_IND CHAR(1) COLLATE UTF8_LCASE DEFAULT 'N'
)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- Replaced the Teradata UNIQUE PRIMARY INDEX with an informational Delta primary key.
-- TODO: manual review required — Delta primary keys are not enforced; preserve ACCT_ID uniqueness in the write path.
ALTER TABLE ACCT_SNAPSHOT
ADD CONSTRAINT XPKACCT_SNAPSHOT PRIMARY KEY (ACCT_ID);
