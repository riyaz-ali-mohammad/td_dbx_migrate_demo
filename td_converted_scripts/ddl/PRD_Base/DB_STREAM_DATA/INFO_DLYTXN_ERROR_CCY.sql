-- Converted the Teradata SET table and physical storage options to a Delta table.
-- Removed the source database qualifier because no target Unity Catalog mapping was supplied.
-- Preserved CHAR width, replaced NOT CASESPECIFIC with a case-insensitive collation, and removed the LATIN character-set clause.
-- Mapped the timezone-naive Teradata TIMESTAMP to TIMESTAMP_NTZ and removed its display-only FORMAT clause.
CREATE TABLE INFO_DLYTXN_ERROR_CCY (
    CCY_CD CHAR(3) COLLATE UTF8_LCASE NOT NULL,
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
);

-- Converted the Teradata unique primary index to an informational Delta primary key.
-- TODO: manual review required — Delta does not enforce the Teradata SET/UPI uniqueness contract; enforce CCY_CD uniqueness in the write path.
ALTER TABLE INFO_DLYTXN_ERROR_CCY
    ADD CONSTRAINT XPKINFO_DLYTXN_ERROR_CCY PRIMARY KEY (CCY_CD);
