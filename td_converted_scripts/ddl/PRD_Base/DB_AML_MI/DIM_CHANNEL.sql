-- TODO: manual review required — Teradata SET table row-uniqueness is lost (Delta is multiset); de-dup at load (SELECT DISTINCT / MERGE) or add a constraint
-- Converted the unqualified target table to the current catalog/schema because no Unity Catalog mapping was supplied; removed Teradata FALLBACK, JOURNAL, CHECKSUM, MERGEBLOCKRATIO, and MAP storage options.
-- Preserved bounded character columns, replaced NOT CASESPECIFIC with UTF8_LCASE collation, and removed Teradata LATIN character-set clauses.
-- Mapped the timezone-naive Teradata timestamp to TIMESTAMP_NTZ and removed its display-only FORMAT clause.
CREATE TABLE DIM_CHANNEL (
    CHNL_CD CHAR(3) COLLATE UTF8_LCASE NOT NULL,
    CHNL_DESC VARCHAR(40) COLLATE UTF8_LCASE,
    DIGITAL_IND CHAR(1) COLLATE UTF8_LCASE,
    CO_UPD_TMS TIMESTAMP_NTZ
);

-- TODO: manual review required — the converted primary key is informational and does not enforce the source UNIQUE PRIMARY INDEX; preserve uniqueness in the write path.
-- Converted the Teradata UNIQUE PRIMARY INDEX to an informational Delta primary-key constraint.
ALTER TABLE DIM_CHANNEL ADD CONSTRAINT XPKDIM_CHANNEL PRIMARY KEY (CHNL_CD);
