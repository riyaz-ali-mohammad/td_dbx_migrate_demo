-- Source database qualifier omitted because no target catalog/schema mapping was supplied.
-- Teradata SET, FALLBACK, journal, checksum, merge-block-ratio, and MAP options are removed; Delta manages storage and has multiset semantics.
-- CHARACTER SET LATIN is removed because Databricks uses UTF-8; NOT CASESPECIFIC is preserved with UTF8_LCASE collation.
-- Teradata TIMESTAMP(0) is mapped to timezone-naive TIMESTAMP_NTZ, and its display-only FORMAT clause is removed.
-- Delta column defaults require the allowColumnDefaults table feature.
-- TODO: manual review required — verify bounded CHAR/VARCHAR width, CHAR padding, and trailing-space behavior for downstream consumers.
CREATE TABLE TXN_TYP_CAT (
    CD CHAR(4) COLLATE UTF8_LCASE NOT NULL,
    CD_DESC VARCHAR(60) COLLATE UTF8_LCASE DEFAULT 'UNKNOWN - AUTO ADDED',
    AUTO_ADDED_IND CHAR(1) COLLATE UTF8_LCASE DEFAULT 'N',
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- Teradata UNIQUE PRIMARY INDEX is represented as an informational Delta primary key.
-- TODO: manual review required — Delta does not enforce primary-key uniqueness; enforce CD uniqueness in the write path.
ALTER TABLE TXN_TYP_CAT
ADD CONSTRAINT XPKTXN_TYP_CAT PRIMARY KEY (CD);
