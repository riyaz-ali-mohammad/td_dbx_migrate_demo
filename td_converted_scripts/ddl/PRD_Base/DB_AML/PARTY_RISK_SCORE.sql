-- TODO: manual review required — Teradata SET full-row uniqueness and UNIQUE PRIMARY INDEX enforcement are not enforced by Delta; enforce de-duplication and PARTY_ID uniqueness in the write path
-- TODO: manual review required — verify that consumers preserve the source CHAR(n) fixed-width padding and trailing-space comparison semantics
-- Removed Teradata FALLBACK, journal, checksum, merge-block-ratio, and MAP physical-storage options; Delta manages durability and storage layout
-- Removed the source database qualifier because no target Unity Catalog mapping was supplied; the table resolves in the current catalog and schema
-- Removed LATIN character-set and display-only FORMAT clauses; Databricks stores strings as UTF-8 and formats values at query time
-- Replaced NOT CASESPECIFIC with UTF8_LCASE collation and removed Teradata COMPRESS hints because Delta handles encoding
-- Mapped timezone-naive Teradata TIMESTAMP(0) to TIMESTAMP_NTZ
CREATE TABLE PARTY_RISK_SCORE (
    PARTY_ID CHAR(12) COLLATE UTF8_LCASE NOT NULL,
    SCORE_DT DATE NOT NULL,
    CTRY_SCORE SMALLINT,
    PEP_SCORE SMALLINT,
    OCCP_SCORE SMALLINT,
    PRDT_SCORE SMALLINT,
    CHNL_SCORE SMALLINT,
    ALERT_SCORE SMALLINT,
    SANC_SCORE SMALLINT,
    KYC_SCORE SMALLINT,
    ADV_MEDIA_SCORE SMALLINT,
    TOTAL_SCORE SMALLINT,
    RISK_BAND_CD CHAR(2) COLLATE UTF8_LCASE,
    PREV_RISK_BAND_CD CHAR(2) COLLATE UTF8_LCASE,
    BAND_CHG_IND CHAR(1) COLLATE UTF8_LCASE,
    EDD_REQUIRED_IND CHAR(1) COLLATE UTF8_LCASE,
    NEXT_REVIEW_DT DATE,
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
);

-- Replaced the Teradata UNIQUE PRIMARY INDEX with an informational Databricks primary key constraint
ALTER TABLE PARTY_RISK_SCORE
    ADD CONSTRAINT XPKPARTY_RISK_SCORE PRIMARY KEY (PARTY_ID);
