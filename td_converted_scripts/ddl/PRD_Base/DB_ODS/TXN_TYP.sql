-- TODO: manual review required — validate bounded CHAR/VARCHAR width and fixed-width padding behavior for downstream consumers.
-- Converted the Teradata SET table to Delta; removed FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, and MAP storage clauses.
-- Removed LATIN character-set and display FORMAT clauses; preserved NOT CASESPECIFIC behavior with UTF8_LCASE collation.
-- Mapped the timezone-naive Teradata timestamp to TIMESTAMP_NTZ and replaced the primary-index layout with liquid clustering.
-- Left the table unqualified because no target Unity Catalog mapping was supplied.
CREATE TABLE txn_typ (
    txn_typ_cd CHAR(4) COLLATE UTF8_LCASE NOT NULL,
    start_dt DATE NOT NULL,
    end_dt DATE NOT NULL DEFAULT DATE '9999-12-31',
    txn_typ_desc VARCHAR(50) COLLATE UTF8_LCASE,
    pay_scheme_cd CHAR(4) COLLATE UTF8_LCASE,
    direction_cd CHAR(1) COLLATE UTF8_LCASE,
    cash_ind CHAR(1) COLLATE UTF8_LCASE,
    xborder_ind CHAR(1) COLLATE UTF8_LCASE,
    co_upd_tms TIMESTAMP_NTZ NOT NULL
)
CLUSTER BY (txn_typ_cd, start_dt)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- TODO: manual review required — Delta PRIMARY KEY constraints are informational; enforce TXN_TYP_CD/START_DT uniqueness in the write path.
-- Converted the Teradata UNIQUE PRIMARY INDEX to an informational primary-key constraint.
ALTER TABLE txn_typ
ADD CONSTRAINT XPKTXN_TYP PRIMARY KEY (txn_typ_cd, start_dt);
