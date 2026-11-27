-- Source database qualifier removed because no target Unity Catalog mapping was supplied; the table resolves in the current catalog and schema.
-- Teradata SET was removed; the UNIQUE PRIMARY INDEX contract is retained below as an informational primary key.
-- Teradata FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, and MAP physical-storage clauses were removed for Delta.
-- CHARACTER SET LATIN was removed because Databricks uses UTF-8; NOT CASESPECIFIC was converted to UTF8_LCASE collation.
-- The DATE FORMAT display-only clause was removed.
-- TODO: manual review required — confirm CHAR(12) and CHAR(2) fixed-width padding and trailing-space comparison behavior for dependent workloads.
CREATE TABLE AML_RISK_SCORE_WRK (
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
    RISK_BAND_CD CHAR(2) COLLATE UTF8_LCASE
);

-- The Teradata UNIQUE PRIMARY INDEX was converted to an informational Delta primary key.
-- TODO: manual review required — Delta does not enforce primary-key uniqueness; enforce PARTY_ID uniqueness in the write path.
ALTER TABLE AML_RISK_SCORE_WRK
ADD CONSTRAINT XPKAML_RISK_SCORE_WRK PRIMARY KEY (PARTY_ID);
