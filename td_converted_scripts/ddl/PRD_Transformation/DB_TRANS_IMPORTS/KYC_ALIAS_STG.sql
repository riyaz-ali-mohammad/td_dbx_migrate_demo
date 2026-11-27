-- TODO: manual review required — Delta does not enforce Teradata SET-table or UNIQUE PRIMARY INDEX uniqueness; enforce uniqueness in the write path
-- TODO: manual review required — confirm target CHAR columns preserve the required fixed-width padding and trailing-space behavior
-- NOTE: CHARACTER SET LATIN was removed because Databricks uses UTF-8; transcode source bytes during ingestion if they are not valid UTF-8
-- Converted the two-part Teradata name to an unqualified target name because no Unity Catalog mapping was supplied
-- Removed Teradata SET, fallback, journal, checksum, merge-block-ratio, and map attributes; replaced the primary-index layout with liquid clustering
-- Replaced NOT CASESPECIFIC with UTF8_LCASE collation and removed CHARACTER SET LATIN
CREATE TABLE KYC_ALIAS_STG (
    PARTY_ID CHAR(12) COLLATE UTF8_LCASE NOT NULL,
    ALIAS_SEQ_NR SMALLINT NOT NULL,
    ALIAS_NM VARCHAR(100) COLLATE UTF8_LCASE,
    ALIAS_TYP_CD CHAR(2) COLLATE UTF8_LCASE,
    ACTION_CD CHAR(1) COLLATE UTF8_LCASE
)
CLUSTER BY (PARTY_ID, ALIAS_SEQ_NR);

-- Converted the Teradata UNIQUE PRIMARY INDEX contract to an informational Delta primary key; write-path enforcement is still required
ALTER TABLE KYC_ALIAS_STG
ADD CONSTRAINT XPKKYC_ALIAS_STG PRIMARY KEY (PARTY_ID, ALIAS_SEQ_NR);
