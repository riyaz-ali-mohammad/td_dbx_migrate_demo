-- TODO: manual review required — Teradata SET full-row uniqueness is not enforced by Delta; enforce de-duplication in the write path.
-- TODO: manual review required — Verify bounded CHAR/VARCHAR width and fixed-width padding behavior for downstream consumers.
-- The source database qualifier was removed because no target Unity Catalog mapping was supplied.
-- Teradata SET and physical FALLBACK, JOURNAL, CHECKSUM, MERGEBLOCKRATIO, and MAP clauses were removed for Delta.
-- CHARACTER SET LATIN was removed; NOT CASESPECIFIC was converted to the UTF8_LCASE collation.
CREATE TABLE DLYTXN_SCREEN_NM (
    TXN_REF VARCHAR(35) COLLATE UTF8_LCASE NOT NULL,
    SUPPLIER_CD CHAR(4) COLLATE UTF8_LCASE NOT NULL,
    NM_ROLE_CD CHAR(2) COLLATE UTF8_LCASE NOT NULL,
    RAW_NM VARCHAR(140) COLLATE UTF8_LCASE,
    NORM_NM VARCHAR(140) COLLATE UTF8_LCASE,
    CTRY_CD CHAR(2) COLLATE UTF8_LCASE,
    BIC_CD CHAR(11) COLLATE UTF8_LCASE
);

-- TODO: manual review required — The source UPI uniqueness contract becomes an informational, non-enforced Delta primary key; enforce uniqueness in the write path.
-- The Teradata UNIQUE PRIMARY INDEX was converted to a named informational primary key; AMP distribution was removed.
ALTER TABLE DLYTXN_SCREEN_NM
ADD CONSTRAINT XPKDLYTXN_SCREEN_NM PRIMARY KEY (TXN_REF, SUPPLIER_CD, NM_ROLE_CD);
