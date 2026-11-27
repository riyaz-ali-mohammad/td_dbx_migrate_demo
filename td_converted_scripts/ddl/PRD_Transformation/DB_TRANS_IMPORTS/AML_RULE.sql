-- TODO: manual review required — Teradata SET/UPI uniqueness is not enforced by Delta; enforce key uniqueness and de-duplication in the write path.
-- TODO: manual review required — validate fixed-width CHAR padding/trailing-space behavior and bounded VARCHAR behavior with migrated loads and consumers.
-- NOTE: LATIN character-set clauses were removed because Databricks stores UTF-8; transcode any non-UTF-8 source bytes during ingestion.
-- Teradata SET, FALLBACK/JOURNAL, CHECKSUM, MERGEBLOCKRATIO, MAP, and primary-index storage directives were removed for Delta.
-- The source database qualifier was omitted because no target Unity Catalog mapping was supplied; this resolves in the current catalog and schema.
-- INTEGER was mapped to INT; CHARACTER SET LATIN was removed; NOT CASESPECIFIC was mapped to UTF8_LCASE collation.
CREATE TABLE AML_RULE (
    RULE_CD CHAR(8) COLLATE UTF8_LCASE NOT NULL,
    SEGMENT_CD CHAR(3) COLLATE UTF8_LCASE NOT NULL,
    AMT_THRESHOLD DECIMAL(18, 2),
    CNT_THRESHOLD INT,
    LOOKBACK_DAYS SMALLINT,
    PCT_THRESHOLD DECIMAL(7, 2),
    SCORE_WEIGHT SMALLINT,
    ACTIVE_IND CHAR(1) COLLATE UTF8_LCASE,
    RULE_DESC VARCHAR(60) COLLATE UTF8_LCASE,
    ACTION_CD CHAR(1) COLLATE UTF8_LCASE
);

-- Teradata UNIQUE PRIMARY INDEX was converted to an informational Delta primary key constraint.
ALTER TABLE AML_RULE
ADD CONSTRAINT XPKAML_RULE PRIMARY KEY (RULE_CD, SEGMENT_CD);
