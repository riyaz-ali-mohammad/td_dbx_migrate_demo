-- TODO: manual review required — Teradata SET table row-uniqueness is lost because Delta is multiset; enforce de-duplication in the write path.
-- TODO: manual review required — verify fixed-width CHAR padding and trailing-space behavior for QUEUE_CD, CASE_STATUS_CD, and AGE_BAND_CD.
-- Converted the two-part Teradata name to an unqualified target name because no Unity Catalog mapping was supplied.
-- Removed Teradata FALLBACK, journal, CHECKSUM, MERGEBLOCKRATIO, and MAP physical-storage clauses.
-- Removed DATE and TIMESTAMP display FORMAT clauses; mapped the naive timestamp to TIMESTAMP_NTZ.
-- Removed LATIN character-set clauses and preserved NOT CASESPECIFIC behavior with UTF8_LCASE collation.
CREATE TABLE CASE_AGEING_DAILY (
    BUSINESS_DT DATE NOT NULL,
    QUEUE_CD CHAR(6) COLLATE UTF8_LCASE NOT NULL,
    CASE_STATUS_CD CHAR(5) COLLATE UTF8_LCASE NOT NULL,
    AGE_BAND_CD CHAR(5) COLLATE UTF8_LCASE NOT NULL,
    CASE_CNT INT,
    OVER_SLA_CNT INT,
    CO_UPD_TMS TIMESTAMP_NTZ
);

-- TODO: manual review required — this informational Delta primary key does not enforce the source UNIQUE PRIMARY INDEX; preserve uniqueness in the write path.
-- Replaced the Teradata UNIQUE PRIMARY INDEX with an informational primary-key constraint.
ALTER TABLE CASE_AGEING_DAILY
ADD CONSTRAINT XPKCASE_AGEING_DAILY
PRIMARY KEY (BUSINESS_DT, QUEUE_CD, CASE_STATUS_CD, AGE_BAND_CD);
