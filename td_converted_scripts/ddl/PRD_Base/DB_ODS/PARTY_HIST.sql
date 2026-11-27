-- TODO: manual review required — Teradata SET table row-uniqueness is lost because Delta is multiset; enforce de-duplication in the write path.
-- TODO: manual review required — bounded CHAR/VARCHAR definitions are retained; validate downstream dependencies on fixed-width padding and length behavior.
-- Converted the Teradata two-part name to an unqualified name because no target Unity Catalog mapping was supplied.
-- Removed Teradata FALLBACK, JOURNAL, CHECKSUM, MERGEBLOCKRATIO, MAP, FORMAT, CHARACTER SET, and COMPRESS clauses; Delta manages storage and UTF-8 encoding, while display formats belong in consuming queries.
-- Preserved NOT CASESPECIFIC behavior with UTF8_LCASE collation, mapped naive TIMESTAMP values to TIMESTAMP_NTZ, and replaced the primary-index layout with liquid clustering.
CREATE TABLE PARTY_HIST (
    PARTY_ID CHAR(12) COLLATE UTF8_LCASE NOT NULL,
    START_DT DATE NOT NULL,
    UPD_TMS TIMESTAMP_NTZ NOT NULL,
    END_DT DATE,
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
    ACTION_CD CHAR(1) COLLATE UTF8_LCASE,
    CO_UPD_TMS TIMESTAMP_NTZ
)
CLUSTER BY (PARTY_ID, START_DT, UPD_TMS);

-- TODO: manual review required — Delta primary keys are informational; enforce the source UNIQUE PRIMARY INDEX contract in the write path.
-- Replaced the Teradata UNIQUE PRIMARY INDEX with an informational primary-key constraint.
ALTER TABLE PARTY_HIST
ADD CONSTRAINT XPKPARTY_HIST PRIMARY KEY (PARTY_ID, START_DT, UPD_TMS);
