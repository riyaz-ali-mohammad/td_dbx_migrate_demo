-- Converted the Teradata MULTISET table to a Delta table; duplicate rows remain allowed.
-- Removed the source database qualifier because no target catalog/schema mapping was supplied.
-- Removed FALLBACK, journals, checksum, merge-block-ratio, MAP, and PRIMARY INDEX physical settings; Delta manages durability and layout.
-- Removed LATIN character-set clauses because DBSQL uses UTF-8 and applied UTF8_LCASE to preserve NOT CASESPECIFIC comparisons.
-- TODO: manual review required — verify downstream consumers retain the required fixed-width CHAR padding and overflow behavior.
CREATE TABLE AML_REFSYS_RAW (
    A CHAR(2) COLLATE UTF8_LCASE,
    B CHAR(30) COLLATE UTF8_LCASE,
    C CHAR(221) COLLATE UTF8_LCASE
);
