-- TODO: manual review required — verify the VARCHAR(60) length contract and transcode any non-UTF-8 LATIN source bytes during ingestion
-- Converted Teradata MULTISET DDL to a Delta table; removed FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, MAP, and the non-unique PRIMARY INDEX physical-storage clauses
-- Left the table unqualified because no target Unity Catalog mapping was supplied; it resolves in the current catalog and schema
-- Preserved NOT CASESPECIFIC behavior with UTF8_LCASE collation, mapped INTEGER to INT and naive TIMESTAMP(0) to TIMESTAMP_NTZ, and removed display-only FORMAT metadata
CREATE TABLE SANC_NAME_TOKEN (
    TOKEN_TXT VARCHAR(60) COLLATE UTF8_LCASE NOT NULL,
    GROUP_ID INT NOT NULL,
    NAME_SEQ_NR SMALLINT NOT NULL,
    TOKEN_SEQ_NR SMALLINT NOT NULL,
    CO_UPD_TMS TIMESTAMP_NTZ
);
