-- assumption: No target catalog mapping was supplied, so the source database qualifier is omitted and the table resolves in the current catalog and schema.
-- TODO: manual review required — Teradata SET table row-uniqueness is lost because Delta is multiset; enforce de-duplication in every write path.
-- Teradata FALLBACK and journal clauses are removed because Delta provides storage resilience and time travel.
-- Teradata CHECKSUM, MERGEBLOCKRATIO, and MAP physical-storage options are removed because Delta manages physical storage.
-- CHARACTER SET LATIN is removed because Databricks uses UTF-8; NOT CASESPECIFIC is preserved with UTF8_LCASE collation.
-- TODO: manual review required — verify bounded CHAR/VARCHAR width and fixed-width CHAR padding behavior against downstream consumers.
-- Teradata TIMESTAMP(0) is mapped to timezone-naive TIMESTAMP_NTZ, and its display-only FORMAT clause is removed.
CREATE TABLE DIM_COUNTRY (
    CTRY_2_CD CHAR(2) COLLATE UTF8_LCASE NOT NULL,
    CTRY_3_CD CHAR(3) COLLATE UTF8_LCASE,
    CTRY_NM VARCHAR(50) COLLATE UTF8_LCASE,
    REGION_CD CHAR(3) COLLATE UTF8_LCASE,
    FATF_STATUS_CD CHAR(2) COLLATE UTF8_LCASE,
    CTRY_RISK_CD CHAR(1) COLLATE UTF8_LCASE,
    HRC_IND CHAR(1) COLLATE UTF8_LCASE,
    SANCTIONED_IND CHAR(1) COLLATE UTF8_LCASE,
    CO_UPD_TMS TIMESTAMP_NTZ
);

-- Teradata UNIQUE PRIMARY INDEX is replaced by an informational Delta primary key.
-- TODO: manual review required — the informational primary key does not enforce uniqueness; preserve uniqueness in the write path.
ALTER TABLE DIM_COUNTRY ADD CONSTRAINT XPKDIM_COUNTRY PRIMARY KEY (CTRY_2_CD);
