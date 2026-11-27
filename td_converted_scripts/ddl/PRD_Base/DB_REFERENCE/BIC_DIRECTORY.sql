-- Converted Teradata SET DDL to Delta table DDL; removed FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, MAP, and the source database qualifier because no target catalog mapping was supplied.
-- Removed CHARACTER SET LATIN because Databricks strings are UTF-8; mapped NOT CASESPECIFIC to UTF8_LCASE collation; mapped the naive TIMESTAMP to TIMESTAMP_NTZ and removed its display-only FORMAT.
-- TODO: manual review required — confirm retained bounded CHAR/VARCHAR columns preserve the source workloads' expected overflow and CHAR blank-padding behavior.
CREATE TABLE BIC_DIRECTORY (
    BIC_CD CHAR(11) COLLATE UTF8_LCASE NOT NULL,
    BANK_NM VARCHAR(60) COLLATE UTF8_LCASE,
    CTRY_2_CD CHAR(2) COLLATE UTF8_LCASE,
    AUTO_ADDED_IND CHAR(1) COLLATE UTF8_LCASE DEFAULT 'N',
    CO_UPD_TMS TIMESTAMP_NTZ
)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- Converted the Teradata UNIQUE PRIMARY INDEX to an informational Delta primary key; physical distribution is managed by Delta.
-- TODO: manual review required — Delta does not enforce primary-key uniqueness; enforce BIC_CD uniqueness in the write path.
ALTER TABLE BIC_DIRECTORY ADD CONSTRAINT XPKBIC_DIRECTORY PRIMARY KEY (BIC_CD);
