-- Source database qualifier removed because no target catalog mapping was supplied; the table resolves in the current catalog and schema.
-- Teradata SET was removed because Delta tables use multiset semantics.
-- Teradata FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, and MAP physical options were removed because Delta manages durability and storage layout.
-- CHARACTER SET LATIN was removed because Databricks uses UTF-8; NOT CASESPECIFIC was replaced with UTF8_LCASE collation.
-- INTEGER was replaced with INT.
CREATE TABLE TM_RULE_PARAM_SNAPSHOT (
    RULE_CD CHAR(8) COLLATE UTF8_LCASE NOT NULL,
    SEGMENT_CD CHAR(3) COLLATE UTF8_LCASE NOT NULL,
    AMT_THRESHOLD DECIMAL(18,2),
    CNT_THRESHOLD INT,
    LOOKBACK_DAYS SMALLINT,
    PCT_THRESHOLD DECIMAL(7,2),
    SCORE_WEIGHT SMALLINT
);

-- UNIQUE PRIMARY INDEX was replaced with an informational Delta primary key constraint.
-- TODO: manual review required — Delta does not enforce the source UPI/SET uniqueness; enforce uniqueness on (RULE_CD, SEGMENT_CD) in every write path.
ALTER TABLE TM_RULE_PARAM_SNAPSHOT
ADD CONSTRAINT XPKTM_RULE_PARAM_SNAPSHOT PRIMARY KEY (RULE_CD, SEGMENT_CD);
