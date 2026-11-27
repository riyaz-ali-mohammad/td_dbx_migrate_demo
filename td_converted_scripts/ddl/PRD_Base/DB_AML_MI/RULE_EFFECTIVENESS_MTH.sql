-- Source database qualifier omitted because no target Unity Catalog mapping was supplied; the table resolves in the current catalog and schema.
-- Teradata SET, FALLBACK, journal, CHECKSUM, MERGEBLOCKRATIO, and MAP storage clauses have no Delta DDL equivalent and were removed.
-- Teradata INTEGER columns map to Databricks INT; DECIMAL and SMALLINT retain their source precision and types.
-- CHARACTER SET LATIN was removed because Databricks strings are UTF-8; NOT CASESPECIFIC maps to UTF8_LCASE collation.
-- Teradata's timezone-naive TIMESTAMP(0) maps to TIMESTAMP_NTZ; its display-only FORMAT clause was removed.
CREATE TABLE RULE_EFFECTIVENESS_MTH (
    YR_MON INT NOT NULL,
    RULE_CD CHAR(8) COLLATE UTF8_LCASE NOT NULL,
    ALERT_CNT INT,
    CASED_CNT INT,
    SAR_CNT INT,
    CLOSED_NFA_CNT INT,
    CONVERSION_PCT DECIMAL(7, 2),
    FALSE_POS_PCT DECIMAL(7, 2),
    RANK_IN_MTH SMALLINT,
    CO_UPD_TMS TIMESTAMP_NTZ
);

-- TODO: manual review required — the source UNIQUE PRIMARY INDEX enforced key uniqueness, but the Databricks primary key is informational; enforce uniqueness in the write path.
-- Teradata UNIQUE PRIMARY INDEX distribution was removed and its key contract is retained as an informational primary key.
ALTER TABLE RULE_EFFECTIVENESS_MTH
ADD CONSTRAINT XPKRULE_EFFECTIVENESS_MTH PRIMARY KEY (YR_MON, RULE_CD);
