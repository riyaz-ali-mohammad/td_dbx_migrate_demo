-- Converted Teradata MULTISET DDL to a Delta table; removed FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, MAP, and the PRIMARY INDEX because Delta manages durability and physical distribution.
-- Removed the source database qualifier because no target Unity Catalog mapping was supplied; the table resolves in the current catalog and schema.
-- Removed LATIN character-set declarations because Databricks SQL stores strings as UTF-8; preserved NOT CASESPECIFIC behavior with UTF8_LCASE collation.
-- Removed the DATE display FORMAT because it does not affect stored values.
-- TODO: manual review required — verify that downstream use of fixed-width CHAR columns preserves the source's blank-padding and trailing-space behavior.
-- TODO: manual review required — verify that the bounded VARCHAR column retains the source application's expected length/overflow contract.
CREATE TABLE AML_RULE_TXN_WRK (
    RULE_CD CHAR(8) COLLATE UTF8_LCASE NOT NULL,
    ACCT_ID CHAR(14) COLLATE UTF8_LCASE NOT NULL,
    BUSINESS_DT DATE NOT NULL,
    TXN_REF VARCHAR(35) COLLATE UTF8_LCASE NOT NULL,
    SUPPLIER_CD CHAR(4) COLLATE UTF8_LCASE NOT NULL
);
