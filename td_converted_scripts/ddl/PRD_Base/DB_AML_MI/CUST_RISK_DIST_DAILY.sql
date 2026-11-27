-- TODO: manual review required — Delta does not enforce Teradata SET row uniqueness or the UNIQUE PRIMARY INDEX; enforce uniqueness in the write path.
-- TODO: manual review required — validate that fixed-width CHAR padding and trailing-space comparisons remain equivalent for downstream consumers.
-- Teradata SET, FALLBACK, JOURNAL, CHECKSUM, MERGEBLOCKRATIO, and MAP storage clauses have no Delta DDL equivalent and were removed.
-- The source database qualifier was removed because no target Unity Catalog mapping was supplied; the table resolves in the current catalog and schema.
-- Teradata display-only FORMAT clauses were removed, CHARACTER SET LATIN was removed because Databricks uses UTF-8, and NOT CASESPECIFIC was mapped to UTF8_LCASE collation.
-- Teradata INTEGER and timezone-naive TIMESTAMP(0) were mapped to INT and TIMESTAMP_NTZ.
-- The Teradata UNIQUE PRIMARY INDEX was replaced by liquid clustering; its key contract is added separately as an informational primary key.
CREATE TABLE CUST_RISK_DIST_DAILY (
    BUSINESS_DT DATE NOT NULL,
    SEGMENT_CD CHAR(3) COLLATE UTF8_LCASE NOT NULL,
    RISK_BAND_CD CHAR(2) COLLATE UTF8_LCASE NOT NULL,
    PARTY_CNT INT,
    PEP_CNT INT,
    EDD_CNT INT,
    BAND_UP_CNT INT,
    BAND_DOWN_CNT INT,
    CO_UPD_TMS TIMESTAMP_NTZ
)
CLUSTER BY (BUSINESS_DT, SEGMENT_CD, RISK_BAND_CD);

-- The Teradata UNIQUE PRIMARY INDEX key is retained as informational metadata; Delta does not enforce primary-key uniqueness.
ALTER TABLE CUST_RISK_DIST_DAILY
ADD CONSTRAINT pk_cust_risk_dist_daily
PRIMARY KEY (BUSINESS_DT, SEGMENT_CD, RISK_BAND_CD);
