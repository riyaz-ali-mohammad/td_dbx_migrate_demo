-- TODO: manual review required — Teradata SET table row-uniqueness is lost because Delta permits duplicate rows; enforce de-duplication in the write path.
-- TODO: manual review required — verify that target CHAR padding and overflow behavior preserves the fixed-width source contract.
-- The source database qualifier was removed because no target Unity Catalog mapping was supplied.
-- Teradata FALLBACK, JOURNAL, CHECKSUM, MERGEBLOCKRATIO, and MAP physical-storage clauses were removed; CHARACTER SET was removed and NOT CASESPECIFIC became UTF8_LCASE collation.
CREATE TABLE HIGH_RISK_CTRY_SNAPSHOT (
    CTRY_2_CD CHAR(2) COLLATE UTF8_LCASE NOT NULL,
    FATF_STATUS_CD CHAR(2) COLLATE UTF8_LCASE,
    HMT_HIGH_RISK_IND CHAR(1) COLLATE UTF8_LCASE,
    EU_HIGH_RISK_IND CHAR(1) COLLATE UTF8_LCASE,
    OFFSHORE_IND CHAR(1) COLLATE UTF8_LCASE,
    CTRY_RISK_CD CHAR(1) COLLATE UTF8_LCASE
);

-- TODO: manual review required — this primary key is informational and does not enforce the UNIQUE PRIMARY INDEX contract; enforce uniqueness in the write path.
-- The Teradata UNIQUE PRIMARY INDEX was replaced by an informational primary key constraint.
ALTER TABLE HIGH_RISK_CTRY_SNAPSHOT
ADD CONSTRAINT XPKHIGH_RISK_CTRY_SNAPSHOT PRIMARY KEY (CTRY_2_CD);
