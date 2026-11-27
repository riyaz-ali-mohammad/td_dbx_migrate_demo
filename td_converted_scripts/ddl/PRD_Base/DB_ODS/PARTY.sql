-- TODO: manual review required — Teradata SET table row-uniqueness is lost because Delta is multiset; enforce de-duplication in the write path.
-- TODO: manual review required — verify bounded CHAR/VARCHAR length and fixed-width blank-padding behavior for downstream consumers.
-- Removed Teradata FALLBACK, journal, CHECKSUM, MERGEBLOCKRATIO, and MAP physical-storage clauses; Delta and cloud storage manage durability and layout.
-- Removed the source database qualifier because no target Unity Catalog mapping was supplied; the table resolves in the current catalog and schema.
-- Removed LATIN character-set clauses because Databricks strings use UTF-8, and preserved NOT CASESPECIFIC semantics with UTF8_LCASE collation.
-- Removed Teradata display-only DATE/TIMESTAMP FORMAT clauses and column COMPRESS hints; Delta manages encoding automatically.
-- Mapped the timezone-naive Teradata TIMESTAMP to TIMESTAMP_NTZ.
CREATE TABLE PARTY (
      PARTY_ID CHAR(12) COLLATE UTF8_LCASE NOT NULL,
      PARTY_TYP_CD CHAR(1) COLLATE UTF8_LCASE,
      FULL_NM VARCHAR(100) COLLATE UTF8_LCASE,
      BIRTH_DT DATE,
      NATIONALITY_CD CHAR(2) COLLATE UTF8_LCASE,
      RESIDENCE_CTRY_CD CHAR(2) COLLATE UTF8_LCASE,
      SIC_CD CHAR(5) COLLATE UTF8_LCASE,
      PEP_IND CHAR(1) COLLATE UTF8_LCASE,
      PEP_TYP_CD CHAR(2) COLLATE UTF8_LCASE,
      ADV_MEDIA_IND CHAR(1) COLLATE UTF8_LCASE,
      SEGMENT_CD CHAR(3) COLLATE UTF8_LCASE,
      ONBOARD_DT DATE,
      KYC_REVIEW_DUE_DT DATE,
      KYC_STATUS_CD CHAR(2) COLLATE UTF8_LCASE,
      CDD_LEVEL_CD CHAR(3) COLLATE UTF8_LCASE,
      RISK_RATING_CD CHAR(1) COLLATE UTF8_LCASE,
      RM_ID CHAR(8) COLLATE UTF8_LCASE,
      POSTCODE VARCHAR(8) COLLATE UTF8_LCASE,
      CO_HOUSE_NR CHAR(8) COLLATE UTF8_LCASE,
      INCORP_CTRY_CD CHAR(2) COLLATE UTF8_LCASE,
      EXP_MTH_TURNOVER_AMT DECIMAL(18,2),
      SRC_OF_FUNDS_CD CHAR(2) COLLATE UTF8_LCASE,
      CLOSED_IND CHAR(1) COLLATE UTF8_LCASE,
      CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
);

-- TODO: manual review required — Delta primary keys are informational and do not enforce the source UNIQUE PRIMARY INDEX uniqueness contract.
-- Replaced the Teradata UNIQUE PRIMARY INDEX with an informational primary key constraint.
ALTER TABLE PARTY ADD CONSTRAINT XPKPARTY PRIMARY KEY (PARTY_ID);
