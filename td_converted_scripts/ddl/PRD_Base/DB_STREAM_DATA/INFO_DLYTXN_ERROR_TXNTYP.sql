-- TODO: manual review required — Delta does not enforce the Teradata SET/UPI uniqueness contract; enforce uniqueness in the write path.
-- Teradata SET, FALLBACK, journal, CHECKSUM, MERGEBLOCKRATIO, MAP, and UPI physical-design clauses were removed for Delta.
-- The source database qualifier was removed because no target Unity Catalog mapping was supplied; the table resolves in the current catalog and schema.
-- CHARACTER SET LATIN was removed because Databricks uses UTF-8; NOT CASESPECIFIC was mapped to UTF8_LCASE collation.
-- Teradata TIMESTAMP FORMAT display metadata was removed, and the timezone-naive type was mapped to TIMESTAMP_NTZ.
CREATE TABLE INFO_DLYTXN_ERROR_TXNTYP (
    TXN_TYP_CD CHAR(4) COLLATE UTF8_LCASE NOT NULL,
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
);

-- The Teradata unique primary index was retained as an informational, non-enforced Delta primary key.
ALTER TABLE INFO_DLYTXN_ERROR_TXNTYP
ADD CONSTRAINT XPKINFO_DLYTXN_ERROR_TXNTYP PRIMARY KEY (TXN_TYP_CD);
