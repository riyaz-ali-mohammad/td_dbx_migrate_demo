-- Converted Teradata MULTISET, storage, journaling, map, and primary-index clauses to Delta table syntax; duplicates remain allowed and the former PI key uses liquid clustering.
-- Source database qualifier omitted because no target Unity Catalog mapping was supplied; the table resolves in the current catalog and schema.
-- NOTE: DBSQL stores text as UTF-8; transcode source LATIN bytes during ingestion if they are not valid UTF-8.
-- TODO: manual review required — validate downstream behavior that depends on fixed CHAR padding or bounded VARCHAR overflow semantics.
CREATE TABLE AML_RISK_FACTOR_WRK (
    PARTY_ID CHAR(12) COLLATE UTF8_LCASE NOT NULL,
    FACTOR_CD CHAR(8) COLLATE UTF8_LCASE NOT NULL,
    FACTOR_VALUE_CD VARCHAR(20) COLLATE UTF8_LCASE,
    SCORE_PTS SMALLINT
)
CLUSTER BY (PARTY_ID);
