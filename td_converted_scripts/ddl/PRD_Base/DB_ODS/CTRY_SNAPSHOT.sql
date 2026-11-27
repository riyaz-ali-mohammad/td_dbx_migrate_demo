-- TODO: manual review required — Teradata SET/UPI uniqueness is not enforced by Delta; enforce uniqueness on CTRY_2_CD in the write path.
-- Converted the Teradata SET table to a Delta table; removed FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, MAP, and CHARACTER SET LATIN clauses. The source database qualifier is omitted because no target catalog mapping was supplied.
CREATE TABLE CTRY_SNAPSHOT (
    CTRY_2_CD CHAR(2) COLLATE UTF8_LCASE NOT NULL,
    CTRY_3_CD CHAR(3) COLLATE UTF8_LCASE,
    CTRY_NM VARCHAR(50) COLLATE UTF8_LCASE,
    FATF_STATUS_CD CHAR(2) COLLATE UTF8_LCASE,
    CTRY_RISK_CD CHAR(1) COLLATE UTF8_LCASE,
    HRC_IND CHAR(1) COLLATE UTF8_LCASE
);

-- Converted the Teradata UNIQUE PRIMARY INDEX to an informational primary key constraint; Delta does not enforce key uniqueness.
ALTER TABLE CTRY_SNAPSHOT
    ADD CONSTRAINT XPKCTRY_SNAPSHOT PRIMARY KEY (CTRY_2_CD);
