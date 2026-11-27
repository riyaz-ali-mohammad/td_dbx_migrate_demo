-- Teradata MULTISET is implicit in Delta; the keyword was removed.
-- No target catalog mapping was supplied, so the source database qualifier was removed and the table resolves in the current catalog and schema.
-- Delta and cloud storage replace Teradata FALLBACK, journals, checksum, merge-block-ratio, and MAP storage/distribution options.
-- The Teradata non-unique PRIMARY INDEX was removed because Delta does not use AMP-based distribution.
-- CHARACTER SET LATIN was removed because Databricks SQL stores strings as UTF-8; NOT CASESPECIFIC is preserved with UTF8_LCASE collation.
-- TODO: manual review required — verify downstream consumers preserve the source CHAR fixed-width padding and trailing-space behavior.
CREATE TABLE AML_KYCSYS_RAW (
    A CHAR(2) COLLATE UTF8_LCASE,
    B CHAR(26) COLLATE UTF8_LCASE,
    C CHAR(472) COLLATE UTF8_LCASE
);
