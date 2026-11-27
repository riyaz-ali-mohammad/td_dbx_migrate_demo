-- Dropped MULTISET because Delta tables already permit duplicate rows.
-- The source database qualifier was removed because no target catalog/schema mapping was supplied.
-- Removed Teradata FALLBACK, journal, checksum, merge-block-ratio, and MAP storage directives.
-- Removed LATIN character-set declarations and preserved NOT CASESPECIFIC semantics with UTF8_LCASE collation.
-- Removed Teradata display-only DATE and TIMESTAMP FORMAT clauses.
-- Mapped INTEGER to INT and timezone-naive TIMESTAMP(0) to TIMESTAMP_NTZ.
-- Replaced the Teradata primary index and daily range partition with liquid clustering on their access keys.
-- TODO: manual review required — UNIQUE secondary-index enforcement is not preserved; enforce uniqueness in the write pipeline
CREATE TABLE ACCT_DAILY_SUMM (
    ACCT_ID CHAR(14) COLLATE UTF8_LCASE NOT NULL,
    BUSINESS_DT DATE NOT NULL,
    PARTY_ID CHAR(12) COLLATE UTF8_LCASE,
    SEGMENT_CD CHAR(3) COLLATE UTF8_LCASE,
    CR_CNT INT,
    CR_GBP_AMT DECIMAL(18, 2),
    DR_CNT INT,
    DR_GBP_AMT DECIMAL(18, 2),
    CASH_CR_CNT INT,
    CASH_CR_GBP_AMT DECIMAL(18, 2),
    CASH_DR_CNT INT,
    CASH_DR_GBP_AMT DECIMAL(18, 2),
    XBORDER_CNT INT,
    XBORDER_GBP_AMT DECIMAL(18, 2),
    HRC_CNT INT,
    HRC_GBP_AMT DECIMAL(18, 2),
    ROUND_AMT_CNT INT,
    NEAR_THRESHOLD_CASH_CNT INT,
    DISTINCT_CPTY_CR_CNT INT,
    DISTINCT_CPTY_DR_CNT INT,
    MAX_TXN_GBP_AMT DECIMAL(18, 2),
    GAMBLING_GBP_AMT DECIMAL(18, 2),
    CRYPTO_GBP_AMT DECIMAL(18, 2),
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
)
CLUSTER BY (ACCT_ID, BUSINESS_DT);
