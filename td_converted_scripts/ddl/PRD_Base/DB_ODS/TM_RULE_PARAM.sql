-- TODO: manual review required — source SET/UNIQUE PRIMARY INDEX uniqueness is not enforced by Delta; enforce the key in the write path
-- Teradata SET, FALLBACK, journal, CHECKSUM, MERGEBLOCKRATIO, and MAP clauses were removed for Delta.
-- The source database qualifier was removed because no target Unity Catalog mapping was supplied.
-- CHARACTER SET clauses and display-only FORMAT masks were removed; NOT CASESPECIFIC uses UTF8_LCASE collation.
-- The Teradata UNIQUE PRIMARY INDEX is represented by an informational primary key below.
CREATE TABLE TM_RULE_PARAM (
    RULE_CD CHAR(8) COLLATE UTF8_LCASE NOT NULL,
    SEGMENT_CD CHAR(3) COLLATE UTF8_LCASE NOT NULL,
    START_DT DATE NOT NULL,
    END_DT DATE NOT NULL DEFAULT DATE '9999-12-31',
    AMT_THRESHOLD DECIMAL(18, 2),
    CNT_THRESHOLD INT,
    LOOKBACK_DAYS SMALLINT,
    PCT_THRESHOLD DECIMAL(7, 2),
    SCORE_WEIGHT SMALLINT,
    ACTIVE_IND CHAR(1) COLLATE UTF8_LCASE,
    RULE_DESC VARCHAR(60) COLLATE UTF8_LCASE,
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- Delta primary keys are informational and do not enforce uniqueness.
ALTER TABLE TM_RULE_PARAM
ADD CONSTRAINT XPKTM_RULE_PARAM PRIMARY KEY (RULE_CD, SEGMENT_CD, START_DT);
