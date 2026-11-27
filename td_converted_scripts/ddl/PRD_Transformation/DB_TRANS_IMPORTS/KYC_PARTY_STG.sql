-- assumption: No target catalog/schema mapping was supplied; use the current Databricks catalog and schema.
-- Converted Teradata SET table to Delta table; removed FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, MAP, and primary-index physical layout clauses.
-- Converted LATIN character columns to Databricks UTF-8 and preserved NOT CASESPECIFIC behavior with UTF8_LCASE collation.
-- Removed Teradata DATE FORMAT 'YYYY-MM-DD' display metadata; DATE renders in this layout by default.
-- TODO: manual review required — Teradata SET table row-uniqueness is lost because Delta is multiset; enforce de-duplication in the write path.
-- TODO: manual review required — verify fixed-width CHAR blank-padding behavior at all ingestion and consumption boundaries.
-- TODO: manual review required — verify bounded VARCHAR overflow behavior at all ingestion boundaries.
CREATE TABLE KYC_PARTY_STG (
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
    EXP_MTH_TURNOVER_AMT DECIMAL(18, 2),
    SRC_OF_FUNDS_CD CHAR(2) COLLATE UTF8_LCASE,
    CLOSED_IND CHAR(1) COLLATE UTF8_LCASE,
    ACTION_CD CHAR(1) COLLATE UTF8_LCASE
);

-- Converted the Teradata UNIQUE PRIMARY INDEX to an informational Delta primary key; Delta does not enforce key uniqueness.
-- TODO: manual review required — enforce PARTY_ID uniqueness in the write path because the Delta primary key is informational.
ALTER TABLE KYC_PARTY_STG
ADD CONSTRAINT pk_kyc_party_stg PRIMARY KEY (PARTY_ID);
