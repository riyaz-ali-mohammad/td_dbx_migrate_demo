-- assumption: The target catalog and schema are set in the session; the source DB_AML_MI qualifier was omitted.
-- Teradata SET, FALLBACK, journal, checksum, merge-block-ratio, and map clauses were removed for Delta.
-- CHARACTER SET LATIN was removed because Databricks strings use UTF-8; NOT CASESPECIFIC uses UTF8_LCASE collation.
-- BTEQ TIMESTAMP display FORMAT was removed; the timezone-naive source timestamp maps to TIMESTAMP_NTZ.
CREATE TABLE DIM_RULE (
    RULE_CD CHAR(8) COLLATE UTF8_LCASE NOT NULL,
    RULE_DESC VARCHAR(60) COLLATE UTF8_LCASE,
    RULE_FAMILY_CD CHAR(4) COLLATE UTF8_LCASE,
    ACTIVE_SEGMENT_CNT SMALLINT,
    MIN_AMT_THRESHOLD DECIMAL(18,2),
    MAX_SCORE_WEIGHT SMALLINT,
    CO_UPD_TMS TIMESTAMP_NTZ
);

-- TODO: manual review required — the Teradata UNIQUE PRIMARY INDEX uniqueness contract is informational and not enforced by Delta; enforce RULE_CD uniqueness in the write path.
-- Teradata UNIQUE PRIMARY INDEX was replaced with an informational primary key constraint.
ALTER TABLE DIM_RULE ADD CONSTRAINT XPKDIM_RULE PRIMARY KEY (RULE_CD);
