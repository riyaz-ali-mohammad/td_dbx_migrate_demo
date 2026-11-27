-- TODO: manual review required — Teradata SET table row-uniqueness is lost because Delta is multiset; preserve de-duplication in the write path
-- TODO: manual review required — validate bounded CHAR/VARCHAR and fixed-width CHAR padding behavior against downstream consumers
-- Converted the two-part source name to an unqualified table because no target catalog mapping was supplied; the current catalog and schema will be used
-- Removed Teradata FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, MAP, CHARACTER SET, and display-only FORMAT clauses; mapped NOT CASESPECIFIC columns to UTF8_LCASE and naive TIMESTAMP to TIMESTAMP_NTZ
CREATE TABLE CTRY (
    CTRY_2_CD CHAR(2) COLLATE UTF8_LCASE NOT NULL,
    START_DT DATE NOT NULL,
    END_DT DATE NOT NULL DEFAULT DATE '9999-12-31',
    CTRY_3_CD CHAR(3) COLLATE UTF8_LCASE,
    CTRY_NM VARCHAR(50) COLLATE UTF8_LCASE,
    FATF_STATUS_CD CHAR(2) COLLATE UTF8_LCASE,
    HMT_HIGH_RISK_IND CHAR(1) COLLATE UTF8_LCASE,
    EU_HIGH_RISK_IND CHAR(1) COLLATE UTF8_LCASE,
    BASEL_AML_SCORE DECIMAL(5,2),
    CPI_SCORE SMALLINT,
    OFFSHORE_IND CHAR(1) COLLATE UTF8_LCASE,
    REGION_CD CHAR(3) COLLATE UTF8_LCASE,
    CTRY_RISK_CD CHAR(1) COLLATE UTF8_LCASE,
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- TODO: manual review required — the source UNIQUE PRIMARY INDEX becomes an informational primary key, so uniqueness must be enforced in the write path
-- Replaced the Teradata UNIQUE PRIMARY INDEX with a named informational primary key
ALTER TABLE CTRY ADD CONSTRAINT XPKCTRY PRIMARY KEY (CTRY_2_CD, START_DT);
