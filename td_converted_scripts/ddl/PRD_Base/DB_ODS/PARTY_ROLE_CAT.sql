-- Teradata SET was removed; the source UPI already supplied the table's effective uniqueness contract.
-- The source database qualifier was removed because no target Unity Catalog mapping was supplied.
-- Teradata FALLBACK, journal, checksum, merge-block-ratio, and MAP storage options were removed for Delta.
-- CHARACTER SET LATIN was removed because Databricks strings are UTF-8; NOT CASESPECIFIC became UTF8_LCASE collation.
-- TIMESTAMP(0) became timezone-naive TIMESTAMP_NTZ, and its display-only FORMAT clause was removed.
-- Delta column defaults require the allowColumnDefaults table feature.
CREATE TABLE PARTY_ROLE_CAT (
    CD CHAR(2) COLLATE UTF8_LCASE NOT NULL,
    CD_DESC VARCHAR(60) COLLATE UTF8_LCASE DEFAULT 'UNKNOWN - AUTO ADDED',
    AUTO_ADDED_IND CHAR(1) COLLATE UTF8_LCASE DEFAULT 'N',
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- Teradata UNIQUE PRIMARY INDEX was replaced by an informational Delta primary key.
-- TODO: manual review required — Delta does not enforce primary-key uniqueness; enforce CD uniqueness in the write path.
ALTER TABLE PARTY_ROLE_CAT
ADD CONSTRAINT XPKPARTY_ROLE_CAT PRIMARY KEY (CD);
