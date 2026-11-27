-- Converted the Teradata two-part name to an unqualified table because no target catalog mapping was supplied.
-- Removed MULTISET, FALLBACK, journal, CHECKSUM, MERGEBLOCKRATIO, and MAP storage clauses; Delta manages these concerns.
-- Removed CHARACTER SET LATIN and translated NOT CASESPECIFIC to UTF8_LCASE column collation.
-- TODO: manual review required — validate fixed-width CHAR padding and trailing-space behavior for dependent queries.
-- TODO: manual review required — validate bounded VARCHAR length behavior for existing writers and consumers.
-- Converted the timezone-naive TIMESTAMP(0) to TIMESTAMP_NTZ and removed its display-only FORMAT clause.
-- Removed the Teradata named primary index; Delta does not use AMP distribution indexes.
CREATE TABLE AML_REFSYS_REJ (
    A CHAR(2) COLLATE UTF8_LCASE,
    B CHAR(30) COLLATE UTF8_LCASE,
    C CHAR(221) COLLATE UTF8_LCASE,
    REJ_REASON VARCHAR(50) COLLATE UTF8_LCASE,
    CO_UPD_TMS TIMESTAMP_NTZ
);
