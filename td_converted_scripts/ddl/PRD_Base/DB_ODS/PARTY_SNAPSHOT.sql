-- Converted the Teradata SET table to a Delta table; stripped FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, and MAP physical-storage clauses.
-- The source database qualifier is omitted because no target Unity Catalog mapping was supplied; the table resolves in the current catalog and schema.
-- Stripped CHARACTER SET LATIN, mapped NOT CASESPECIFIC to UTF8_LCASE collation, and removed the DATE display FORMAT clause.
CREATE TABLE PARTY_SNAPSHOT (
    PARTY_ID CHAR(12) COLLATE UTF8_LCASE NOT NULL,
    PARTY_TYP_CD CHAR(1) COLLATE UTF8_LCASE,
    SEGMENT_CD CHAR(3) COLLATE UTF8_LCASE,
    RISK_RATING_CD CHAR(1) COLLATE UTF8_LCASE,
    PEP_IND CHAR(1) COLLATE UTF8_LCASE,
    RESIDENCE_CTRY_CD CHAR(2) COLLATE UTF8_LCASE,
    SIC_CD CHAR(5) COLLATE UTF8_LCASE,
    KYC_STATUS_CD CHAR(2) COLLATE UTF8_LCASE,
    EXP_MTH_TURNOVER_AMT DECIMAL(18, 2),
    ONBOARD_DT DATE
);

-- TODO: manual review required — Delta primary keys are informational; enforce the source SET / UNIQUE PRIMARY INDEX uniqueness for PARTY_ID in the write path.
-- Converted the Teradata UNIQUE PRIMARY INDEX to an informational Delta primary key constraint.
ALTER TABLE PARTY_SNAPSHOT
ADD CONSTRAINT XPKPARTY_SNAPSHOT PRIMARY KEY (PARTY_ID);
