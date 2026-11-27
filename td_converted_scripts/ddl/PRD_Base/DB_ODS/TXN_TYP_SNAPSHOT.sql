-- Source database qualifier removed because no target Unity Catalog mapping was provided.
-- Teradata SET removed; Delta tables use multiset storage.
-- Teradata physical storage clauses (FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, and MAP) removed for Delta.
-- CHARACTER SET LATIN removed because Databricks SQL uses UTF-8; NOT CASESPECIFIC mapped to UTF8_LCASE collation.
-- TODO: manual review required — validate downstream dependence on Teradata CHAR fixed-width blank-padding semantics.
CREATE TABLE TXN_TYP_SNAPSHOT (
    TXN_TYP_CD CHAR(4) COLLATE UTF8_LCASE NOT NULL,
    PAY_SCHEME_CD CHAR(4) COLLATE UTF8_LCASE,
    DIRECTION_CD CHAR(1) COLLATE UTF8_LCASE,
    CASH_IND CHAR(1) COLLATE UTF8_LCASE,
    XBORDER_IND CHAR(1) COLLATE UTF8_LCASE
);

-- UNIQUE PRIMARY INDEX removed as a distribution mechanism and retained as an informational primary key.
-- TODO: manual review required — Databricks primary keys are informational; enforce TXN_TYP_CD uniqueness in the write path.
ALTER TABLE TXN_TYP_SNAPSHOT
ADD CONSTRAINT XPKTXN_TYP_SNAPSHOT PRIMARY KEY (TXN_TYP_CD);
