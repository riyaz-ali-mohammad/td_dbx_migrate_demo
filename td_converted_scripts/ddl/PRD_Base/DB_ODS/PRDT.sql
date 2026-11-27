-- TODO: manual review required — Teradata SET table row-uniqueness is lost because Delta is multiset; enforce de-duplication in the write path.
-- TODO: manual review required — verify that consumers preserve Teradata CHAR fixed-width blank-padding and trailing-space comparison semantics.
-- TODO: manual review required — verify that VARCHAR length limits remain compatible with all write paths.
-- Converted the unqualified target to the current catalog/schema, removed Teradata physical storage, journaling, map, and display-format clauses, and enabled Delta column defaults.
CREATE TABLE PRDT (
    PRDT_CD CHAR(6) COLLATE UTF8_LCASE NOT NULL,
    START_DT DATE NOT NULL,
    END_DT DATE NOT NULL DEFAULT DATE '9999-12-31',
    PRDT_DESC VARCHAR(50) COLLATE UTF8_LCASE,
    PRDT_FAMILY_CD CHAR(4) COLLATE UTF8_LCASE,
    SEGMENT_CD CHAR(3) COLLATE UTF8_LCASE,
    PRDT_RISK_CD CHAR(1) COLLATE UTF8_LCASE,
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- TODO: manual review required — Delta primary keys are informational and do not enforce the source UNIQUE PRIMARY INDEX contract.
-- Replaced the Teradata UNIQUE PRIMARY INDEX with a named informational primary key.
ALTER TABLE PRDT ADD CONSTRAINT XPKPRDT PRIMARY KEY (PRDT_CD, START_DT);
