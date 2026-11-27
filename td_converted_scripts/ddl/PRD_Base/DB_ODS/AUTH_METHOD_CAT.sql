-- TODO: manual review required — Teradata SET table row-uniqueness is lost because Delta is multiset; enforce de-duplication across incoming and existing rows in the write path.
-- TODO: manual review required — verify fixed-width CHAR padding and bounded VARCHAR behavior for dependent writers and consumers.
-- Source database qualifier removed because no target catalog mapping was supplied; the table resolves in the current catalog and schema.
-- Teradata FALLBACK, journal, CHECKSUM, MERGEBLOCKRATIO, MAP, and UNIQUE PRIMARY INDEX physical-storage clauses were removed for Delta.
-- CHARACTER SET LATIN was removed because Databricks uses UTF-8; NOT CASESPECIFIC was replaced with UTF8_LCASE collation.
-- Teradata TIMESTAMP(0) was replaced with timezone-naive TIMESTAMP_NTZ, and its display-only FORMAT clause was removed.
-- Delta column defaults require the allowColumnDefaults table feature.
CREATE TABLE AUTH_METHOD_CAT (
    CD CHAR(2) COLLATE UTF8_LCASE NOT NULL,
    CD_DESC VARCHAR(60) COLLATE UTF8_LCASE DEFAULT 'UNKNOWN - AUTO ADDED',
    AUTO_ADDED_IND CHAR(1) COLLATE UTF8_LCASE DEFAULT 'N',
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- TODO: manual review required — Delta primary keys are informational and do not enforce the source UNIQUE PRIMARY INDEX; preserve uniqueness in the write path.
-- The Teradata UNIQUE PRIMARY INDEX contract is retained as an informational primary key constraint.
ALTER TABLE AUTH_METHOD_CAT
ADD CONSTRAINT XPKAUTH_METHOD_CAT PRIMARY KEY (CD);
