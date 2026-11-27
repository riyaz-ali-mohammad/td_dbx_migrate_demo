-- Teradata SET semantics, fallback/journaling, checksum, merge-block ratio, and map placement have no direct Delta DDL equivalent and were removed.
-- The source database qualifier was removed because no target Unity Catalog mapping was supplied; this table resolves in the current catalog and schema.
-- CHARACTER SET LATIN was removed because Databricks uses UTF-8; NOT CASESPECIFIC is preserved with UTF8_LCASE collation.
-- Bounded CHAR/VARCHAR widths are retained, and the timezone-naive timestamp is mapped to TIMESTAMP_NTZ; its display-only FORMAT was removed.
CREATE TABLE DIM_TXN_TYPE (
    TXN_TYP_CD CHAR(4) COLLATE UTF8_LCASE NOT NULL,
    TXN_TYP_DESC VARCHAR(50) COLLATE UTF8_LCASE,
    PAY_SCHEME_CD CHAR(4) COLLATE UTF8_LCASE,
    DIRECTION_CD CHAR(1) COLLATE UTF8_LCASE,
    CASH_IND CHAR(1) COLLATE UTF8_LCASE,
    XBORDER_IND CHAR(1) COLLATE UTF8_LCASE,
    CO_UPD_TMS TIMESTAMP_NTZ
);

-- The Teradata unique primary index is represented as an informational Delta primary key; physical AMP distribution was removed.
-- TODO: manual review required — Delta primary keys are informational, so enforce TXN_TYP_CD uniqueness in the write path.
ALTER TABLE DIM_TXN_TYPE
ADD CONSTRAINT XPKDIM_TXN_TYPE PRIMARY KEY (TXN_TYP_CD);
