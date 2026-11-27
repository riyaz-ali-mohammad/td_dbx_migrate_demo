-- TODO: manual review required — Teradata SET table row-uniqueness is lost because Delta is multiset; enforce de-duplication against existing and incoming rows in the write path
-- TODO: manual review required — verify bounded CHAR/VARCHAR width and CHAR padding behavior against consuming applications
-- Converted CREATE SET TABLE to CREATE TABLE; removed Teradata FALLBACK, journal, CHECKSUM, MERGEBLOCKRATIO, and MAP storage clauses
-- Removed the unmapped Teradata database qualifier so the table resolves in the current target catalog and schema
-- Removed LATIN character-set clauses because Databricks uses UTF-8; preserved NOT CASESPECIFIC with UTF8_LCASE collation
CREATE TABLE RISK_BAND (
    RISK_BAND_CD CHAR(2) COLLATE UTF8_LCASE NOT NULL,
    MIN_SCORE SMALLINT NOT NULL,
    MAX_SCORE SMALLINT NOT NULL,
    RISK_BAND_DESC VARCHAR(30) COLLATE UTF8_LCASE,
    REVIEW_FREQ_MTHS SMALLINT,
    CDD_LEVEL_CD CHAR(3) COLLATE UTF8_LCASE
);

-- TODO: manual review required — the converted primary key is informational and does not enforce the source UNIQUE PRIMARY INDEX; preserve uniqueness in the write path
-- Converted the Teradata UNIQUE PRIMARY INDEX to a named informational primary-key constraint
ALTER TABLE RISK_BAND ADD CONSTRAINT XPKRISK_BAND PRIMARY KEY (RISK_BAND_CD);
