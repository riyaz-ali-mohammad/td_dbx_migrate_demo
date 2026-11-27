-- Source database qualifier removed because no target Unity Catalog mapping was supplied; the table resolves in the current catalog and schema.
-- Teradata SET, FALLBACK, JOURNAL, CHECKSUM, MERGEBLOCKRATIO, and MAP storage clauses were removed for Delta.
-- CHARACTER SET LATIN was removed; NOT CASESPECIFIC behavior is preserved with UTF8_LCASE collation.
-- The Teradata UNIQUE PRIMARY INDEX was replaced with liquid clustering; its logical key is declared separately.
-- NOTE: DBSQL stores text as UTF-8; transcode source LATIN bytes during ingestion if they are not valid UTF-8.
CREATE TABLE DLYTXN_CPTY (
    TXN_REF VARCHAR(35) COLLATE UTF8_LCASE NOT NULL,
    SUPPLIER_CD CHAR(4) COLLATE UTF8_LCASE NOT NULL,
    CPTY_ID BIGINT,
    CPTY_ACCT_KEY VARCHAR(34) COLLATE UTF8_LCASE,
    CPTY_NORM_NM VARCHAR(140) COLLATE UTF8_LCASE,
    CPTY_CTRY_CD CHAR(2) COLLATE UTF8_LCASE,
    CPTY_BANK_CTRY_CD CHAR(2) COLLATE UTF8_LCASE,
    CPTY_INTERNAL_IND CHAR(1) COLLATE UTF8_LCASE,
    CPTY_ACCT_ID CHAR(14) COLLATE UTF8_LCASE,
    CPTY_PARTY_ID CHAR(12) COLLATE UTF8_LCASE,
    NEW_CPTY_IND CHAR(1) COLLATE UTF8_LCASE
)
CLUSTER BY (TXN_REF, SUPPLIER_CD);

-- TODO: manual review required — Delta primary keys are informational; enforce the source UNIQUE PRIMARY INDEX in the write path.
ALTER TABLE DLYTXN_CPTY
ADD CONSTRAINT XPKDLYTXN_CPTY PRIMARY KEY (TXN_REF, SUPPLIER_CD);
