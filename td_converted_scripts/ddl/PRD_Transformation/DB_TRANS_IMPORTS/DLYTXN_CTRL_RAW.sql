-- Source database qualifier removed because no target catalog mapping was supplied; the table resolves in the current catalog and schema.
-- MULTISET was dropped because Delta tables allow duplicate rows by default.
-- FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, and MAP were dropped because Delta and cloud storage manage durability and physical layout.
-- CHARACTER SET LATIN was dropped because Databricks SQL stores strings as UTF-8; transcode non-UTF-8 source bytes during ingestion if necessary.
-- NOT CASESPECIFIC was replaced with UTF8_LCASE column collation.
-- TODO: manual review required — verify downstream consumers preserve the source fixed-width CHAR blank-padding behavior.
-- The non-unique PRIMARY INDEX was replaced with adaptive liquid clustering because Databricks has no AMP distribution index.
CREATE TABLE DLYTXN_CTRL_RAW (
    RECTYPE CHAR(1) COLLATE UTF8_LCASE,
    SUPPLIER_CD CHAR(4) COLLATE UTF8_LCASE,
    FILE_ID CHAR(20) COLLATE UTF8_LCASE,
    EXTRACT_DT CHAR(8) COLLATE UTF8_LCASE,
    REC_CNT CHAR(10) COLLATE UTF8_LCASE,
    DR_TOTAL CHAR(18) COLLATE UTF8_LCASE,
    CR_TOTAL CHAR(18) COLLATE UTF8_LCASE,
    CREATED_TMS CHAR(14) COLLATE UTF8_LCASE
)
CLUSTER BY AUTO;
