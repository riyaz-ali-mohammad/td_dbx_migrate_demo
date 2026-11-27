-- TODO: manual review required — Delta does not enforce Teradata SET or unique-primary-index row uniqueness; enforce uniqueness for (ACCT_ID, BUSINESS_DT) in the write path
-- TODO: manual review required — validate fixed-width CHAR padding and trailing-space comparison behavior for ACCT_ID, PARTY_ID, and SEGMENT_CD
-- Converted the Teradata SET table to a Delta table and removed FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, and MAP physical-storage clauses
-- Removed the source database qualifier because no target Unity Catalog mapping was supplied
-- Removed Teradata CHARACTER SET and FORMAT clauses; preserved NOT CASESPECIFIC behavior with UTF8_LCASE collation
-- Converted INTEGER to INT and timezone-naive TIMESTAMP(0) to TIMESTAMP_NTZ
CREATE TABLE ACCT_BEHAV_PROFILE (
    ACCT_ID CHAR(14) COLLATE UTF8_LCASE NOT NULL,
    BUSINESS_DT DATE NOT NULL,
    PARTY_ID CHAR(12) COLLATE UTF8_LCASE,
    SEGMENT_CD CHAR(3) COLLATE UTF8_LCASE,
    ROLL_7D_CR_GBP_AMT DECIMAL(18,2),
    ROLL_7D_CASH_CR_GBP_AMT DECIMAL(18,2),
    ROLL_7D_NEAR_THRESH_CNT INT,
    ROLL_30D_CR_GBP_AMT DECIMAL(18,2),
    ROLL_30D_DR_GBP_AMT DECIMAL(18,2),
    ROLL_30D_CASH_CR_GBP_AMT DECIMAL(18,2),
    ROLL_30D_ROUND_AMT_CNT INT,
    ROLL_30D_HRC_GBP_AMT DECIMAL(18,2),
    ROLL_3D_CPTY_CR_CNT INT,
    PRIOR_90D_AVG_MTH_CR_AMT DECIMAL(18,2),
    VELOCITY_RATIO DECIMAL(9,2),
    DAYS_SINCE_PREV_ACTV INT,
    CUM_CR_GBP_AMT DECIMAL(18,2),
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
);

-- Converted the Teradata UNIQUE PRIMARY INDEX to an informational Delta primary key constraint
ALTER TABLE ACCT_BEHAV_PROFILE
    ADD CONSTRAINT XPKACCT_BEHAV_PROFILE PRIMARY KEY (ACCT_ID, BUSINESS_DT);
