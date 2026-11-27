-- Converted Teradata MULTISET table to a Delta table; duplicates remain allowed.
-- Target catalog/schema mapping was not supplied, so the table resolves in the current catalog and schema.
-- Removed Teradata FALLBACK, journals, checksum, merge-block-ratio, map, and primary-index storage directives.
-- Removed LATIN character-set clauses; preserved NOT CASESPECIFIC semantics with UTF8_LCASE collation.
-- Converted INTEGER to INT and replaced the source primary-index layout with liquid clustering on the same keys.
CREATE TABLE DLYTXN_SCREEN_CAND (
      TXN_REF VARCHAR(35) COLLATE UTF8_LCASE NOT NULL,
      SUPPLIER_CD CHAR(4) COLLATE UTF8_LCASE NOT NULL,
      NM_ROLE_CD CHAR(2) COLLATE UTF8_LCASE NOT NULL,
      GROUP_ID INT NOT NULL,
      NAME_SEQ_NR SMALLINT NOT NULL,
      MATCH_TOKEN_CNT SMALLINT,
      SANC_TOKEN_CNT SMALLINT,
      SCREEN_TOKEN_CNT SMALLINT,
      MATCH_TYP_CD CHAR(5) COLLATE UTF8_LCASE,
      MATCH_SCORE DECIMAL(5,2)
)
CLUSTER BY (TXN_REF, SUPPLIER_CD);
