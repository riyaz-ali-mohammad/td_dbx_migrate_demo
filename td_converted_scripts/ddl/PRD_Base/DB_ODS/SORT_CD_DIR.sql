-- Converted the Teradata SET table to Delta semantics; removed FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, MAP, display FORMAT clauses, and the physical primary index.
-- Removed LATIN character-set declarations, preserved NOT CASESPECIFIC behavior with UTF8_LCASE collation, and mapped the naive timestamp to TIMESTAMP_NTZ.
CREATE TABLE SORT_CD_DIR (
  SORT_CD CHAR(6) COLLATE UTF8_LCASE NOT NULL,
  START_DT DATE NOT NULL,
  END_DT DATE NOT NULL DEFAULT DATE '9999-12-31',
  BANK_NM VARCHAR(40) COLLATE UTF8_LCASE,
  BRANCH_NM VARCHAR(40) COLLATE UTF8_LCASE,
  BIC_CD CHAR(11) COLLATE UTF8_LCASE,
  FPS_IND CHAR(1) COLLATE UTF8_LCASE,
  CHAPS_IND CHAR(1) COLLATE UTF8_LCASE,
  BACS_IND CHAR(1) COLLATE UTF8_LCASE,
  CLOSED_IND CHAR(1) COLLATE UTF8_LCASE,
  POSTCODE VARCHAR(8) COLLATE UTF8_LCASE,
  CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- TODO: manual review required — the Teradata SET and UNIQUE PRIMARY INDEX uniqueness guarantees are not enforced by Delta; enforce uniqueness in the write path.
-- Preserved the UNIQUE PRIMARY INDEX contract as an informational primary key.
ALTER TABLE SORT_CD_DIR
  ADD CONSTRAINT XPKSORT_CD_DIR PRIMARY KEY (SORT_CD, START_DT);
