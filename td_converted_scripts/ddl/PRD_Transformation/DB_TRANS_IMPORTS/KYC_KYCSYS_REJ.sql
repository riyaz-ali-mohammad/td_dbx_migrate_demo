-- Converted the Teradata MULTISET table to a Delta table; duplicate rows remain allowed.
-- Removed Teradata FALLBACK, journaling, checksum, merge-block-ratio, map, and primary-index physical-storage clauses.
-- Removed the source database qualifier because no target Unity Catalog mapping was supplied; the table resolves in the current catalog and schema.
-- Removed LATIN character-set clauses and preserved NOT CASESPECIFIC behavior with UTF8_LCASE collation.
-- Converted the timezone-naive Teradata timestamp to TIMESTAMP_NTZ and removed its display-only FORMAT clause.
-- TODO: manual review required — verify bounded CHAR/VARCHAR and fixed-width CHAR padding semantics for downstream writers and consumers.
CREATE TABLE kyc_kycsys_rej (
    a CHAR(2) COLLATE UTF8_LCASE,
    b CHAR(26) COLLATE UTF8_LCASE,
    c CHAR(472) COLLATE UTF8_LCASE,
    rej_reason VARCHAR(50) COLLATE UTF8_LCASE,
    co_upd_tms TIMESTAMP_NTZ
);
