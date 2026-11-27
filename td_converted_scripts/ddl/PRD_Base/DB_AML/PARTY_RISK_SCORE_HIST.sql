-- Removed the source database qualifier because no target Unity Catalog mapping was supplied; the table resolves in the current catalog and schema.
-- Converted the Teradata SET table to a Delta table and removed FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, MAP, and primary-index physical storage clauses.
-- Removed Teradata display FORMAT and compression hints, mapped LATIN NOT CASESPECIFIC columns to UTF8_LCASE collation, and mapped the naive timestamp to TIMESTAMP_NTZ.
-- Enabled the Delta column-default feature for END_DT.
-- TODO: manual review required — verify that downstream consumers preserve the fixed-width blank-padding behavior of the CHAR columns.
CREATE TABLE PARTY_RISK_SCORE_HIST (
      PARTY_ID CHAR(12) COLLATE UTF8_LCASE NOT NULL,
      START_DT DATE NOT NULL,
      END_DT DATE DEFAULT DATE '9999-12-31',
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
)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- Replaced the Teradata unique primary index with an informational Delta primary-key constraint.
-- TODO: manual review required — Delta does not enforce primary-key or SET-table uniqueness; enforce uniqueness for PARTY_ID and START_DT in the write path.
ALTER TABLE PARTY_RISK_SCORE_HIST
ADD CONSTRAINT XPKPARTY_RISK_SCORE_HIST PRIMARY KEY (PARTY_ID, START_DT);
