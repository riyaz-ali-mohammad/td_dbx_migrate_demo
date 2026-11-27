-- Converted the Teradata SET table to a Delta table; removed FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, MAP, and the unmapped source database qualifier.
-- Removed LATIN character-set clauses, preserved NOT CASESPECIFIC with UTF8_LCASE collation, removed display-only FORMAT clauses, and mapped INTEGER and naive TIMESTAMP types.
-- TODO: manual review required — validate downstream fixed-width CHAR blank-padding behavior after migration.
CREATE TABLE INFO_DLYTXN_CTRL_RECON (
    FILE_ID CHAR(20) COLLATE UTF8_LCASE NOT NULL,
    SUPPLIER_CD CHAR(4) COLLATE UTF8_LCASE NOT NULL,
    EXTRACT_DT DATE,
    EXP_REC_CNT INT,
    ACT_REC_CNT INT,
    EXP_DR_TOTAL DECIMAL(18,2),
    ACT_DR_TOTAL DECIMAL(18,2),
    EXP_CR_TOTAL DECIMAL(18,2),
    ACT_CR_TOTAL DECIMAL(18,2),
    RECON_STATUS_CD CHAR(4) COLLATE UTF8_LCASE,
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
);

-- Converted the UNIQUE PRIMARY INDEX to an informational primary-key constraint.
-- TODO: manual review required — Delta does not enforce the Teradata SET/UPI uniqueness contract; enforce uniqueness in the write path.
ALTER TABLE INFO_DLYTXN_CTRL_RECON
ADD CONSTRAINT XPKINFO_DLYTXN_CTRL_RECON PRIMARY KEY (FILE_ID, SUPPLIER_CD);
