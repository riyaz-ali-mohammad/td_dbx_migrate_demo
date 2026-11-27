-- Converted the Teradata SET table to Delta; removed FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, MAP, and the primary index.
-- Preserved bounded character types, replaced NOT CASESPECIFIC with UTF8_LCASE collation, and mapped BYTEINT and naive TIMESTAMP.
-- TODO: manual review required — verify CHAR/VARCHAR width and CHAR trailing-space behavior against target workload expectations.
CREATE TABLE DIM_RISK_BAND (
    RISK_BAND_CD CHAR(2) COLLATE UTF8_LCASE NOT NULL,
    RISK_BAND_DESC VARCHAR(30) COLLATE UTF8_LCASE,
    MIN_SCORE SMALLINT,
    MAX_SCORE SMALLINT,
    REVIEW_FREQ_MTHS SMALLINT,
    SORT_ORDER_NR TINYINT,
    CO_UPD_TMS TIMESTAMP_NTZ
);

-- Replaced the Teradata unique primary index with an informational Delta primary key.
-- TODO: manual review required — Delta does not enforce primary-key uniqueness; enforce RISK_BAND_CD uniqueness in the write path.
ALTER TABLE DIM_RISK_BAND ADD CONSTRAINT XPKDIM_RISK_BAND PRIMARY KEY (RISK_BAND_CD);
