-- Converted Teradata SET table to Delta; the source UPI made the SET table's full-row duplicate rule redundant.
-- Removed Teradata FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, MAP, CHARACTER SET, and display FORMAT clauses.
-- Preserved NOT CASESPECIFIC columns with UTF8_LCASE collation and enabled Delta column defaults.
CREATE TABLE CHNL_CAT (
    CD CHAR(3) COLLATE UTF8_LCASE NOT NULL,
    CD_DESC VARCHAR(60) COLLATE UTF8_LCASE DEFAULT 'UNKNOWN - AUTO ADDED',
    AUTO_ADDED_IND CHAR(1) COLLATE UTF8_LCASE DEFAULT 'N',
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- TODO: manual review required — the source UNIQUE PRIMARY INDEX enforced CD uniqueness; the Delta primary key is informational, so enforce uniqueness in the write path.
-- Replaced the Teradata UNIQUE PRIMARY INDEX with a named informational primary key.
ALTER TABLE CHNL_CAT ADD CONSTRAINT XPKCHNL_CAT PRIMARY KEY (CD);
