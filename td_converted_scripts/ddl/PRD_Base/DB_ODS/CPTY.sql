-- Converted Teradata SET table to Delta; the source UPI is represented by an informational primary key below.
-- Stripped FALLBACK, journal, CHECKSUM, MERGEBLOCKRATIO, and MAP physical-storage clauses; Delta and cloud storage manage durability and layout.
-- Stripped LATIN character-set declarations because Databricks stores strings as UTF-8, and preserved NOT CASESPECIFIC with UTF8_LCASE collation.
-- Stripped DATE/TIMESTAMP display FORMAT clauses and mapped the timezone-naive Teradata TIMESTAMP to TIMESTAMP_NTZ.
-- TODO: manual review required — UNIQUE secondary-index enforcement is not preserved; enforce uniqueness of (CPTY_ACCT_KEY, CPTY_NORM_NM) in the write pipeline.
CREATE TABLE CPTY (
    CPTY_ID BIGINT NOT NULL,
    CPTY_ACCT_KEY VARCHAR(34) COLLATE UTF8_LCASE NOT NULL,
    CPTY_NORM_NM VARCHAR(140) COLLATE UTF8_LCASE NOT NULL,
    CPTY_BIC_CD CHAR(11) COLLATE UTF8_LCASE,
    CPTY_CTRY_CD CHAR(2) COLLATE UTF8_LCASE,
    FIRST_SEEN_DT DATE,
    LAST_SEEN_DT DATE,
    TXN_CNT INT,
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
)
CLUSTER BY AUTO;

-- Converted the Teradata UNIQUE PRIMARY INDEX to a Databricks informational primary key; uniqueness must be enforced by the write pipeline.
-- TODO: manual review required — the primary key is informational and does not enforce CPTY_ID uniqueness.
ALTER TABLE CPTY ADD CONSTRAINT XPKCPTY PRIMARY KEY (CPTY_ID);
