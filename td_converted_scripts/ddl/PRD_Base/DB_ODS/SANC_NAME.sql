-- Teradata database qualifier omitted because no target catalog/schema mapping was supplied.
-- Teradata SET semantics are represented by a plain Delta table; the source UPI is handled below.
-- Teradata FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, and MAP storage directives were removed.
-- CHARACTER SET clauses were removed because Databricks uses UTF-8; NOT CASESPECIFIC maps to UTF8_LCASE collation.
-- Teradata TIMESTAMP(0) maps to timezone-naive TIMESTAMP_NTZ; its display-only FORMAT clause was removed.
-- Teradata primary and secondary indexes map to Delta liquid clustering for their key columns.
CREATE TABLE SANC_NAME (
    GROUP_ID INT NOT NULL,
    NAME_SEQ_NR SMALLINT NOT NULL,
    FULL_NM VARCHAR(400) COLLATE UTF8_LCASE,
    NORM_NM VARCHAR(400) COLLATE UTF8_LCASE,
    NON_LATIN_NM VARCHAR(200) COLLATE UTF8_LCASE,
    ALIAS_TYP_CD CHAR(3) COLLATE UTF8_LCASE,
    ALIAS_QUALITY_CD CHAR(1) COLLATE UTF8_LCASE,
    TOKEN_CNT SMALLINT,
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
)
CLUSTER BY (GROUP_ID, NAME_SEQ_NR, NORM_NM);

-- TODO: manual review required — UNIQUE PRIMARY INDEX enforcement is not preserved by an informational Delta primary key; enforce uniqueness in the write pipeline.
-- The Teradata UNIQUE PRIMARY INDEX is represented as an informational primary key.
ALTER TABLE SANC_NAME ADD CONSTRAINT XPKSANC_NAME PRIMARY KEY (GROUP_ID, NAME_SEQ_NR);
