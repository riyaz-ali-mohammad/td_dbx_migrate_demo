-- Converted the Teradata MULTISET table to a managed Delta table and removed the source database qualifier because no target Unity Catalog mapping was supplied.
-- Removed FALLBACK, journal, checksum, merge-block-ratio, and MAP storage options because Delta and cloud storage manage resilience and layout.
-- Removed LATIN character-set clauses and converted NOT CASESPECIFIC columns to UTF8_LCASE collation.
-- Replaced the Teradata PRIMARY INDEX with Delta liquid clustering on the same columns.
CREATE TABLE DLYTXN_SCREEN_TOKEN (
    TXN_REF VARCHAR(35) COLLATE UTF8_LCASE NOT NULL,
    SUPPLIER_CD CHAR(4) COLLATE UTF8_LCASE NOT NULL,
    NM_ROLE_CD CHAR(2) COLLATE UTF8_LCASE NOT NULL,
    TOKEN_SEQ_NR SMALLINT NOT NULL,
    TOKEN_TXT VARCHAR(60) COLLATE UTF8_LCASE
)
CLUSTER BY (TXN_REF, SUPPLIER_CD);
