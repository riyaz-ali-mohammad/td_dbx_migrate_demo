-- TODO: manual review required — Teradata SET table row-uniqueness is lost because Delta uses multiset semantics; enforce de-duplication in the write path.
-- TODO: manual review required — verify fixed-width CHAR padding and trailing-space comparison behavior for dependent workloads.
-- Source database qualifier omitted because no target Unity Catalog mapping was supplied; the table resolves in the current catalog and schema.
-- Teradata FALLBACK, JOURNAL, CHECKSUM, MERGEBLOCKRATIO, MAP, and primary-index physical layout clauses have no Delta equivalent and were removed.
-- CHARACTER SET LATIN was removed because Databricks uses UTF-8; NOT CASESPECIFIC was translated to UTF8_LCASE collation; DATE FORMAT display metadata was removed.
CREATE TABLE KYC_PTAC_STG (
    PARTY_ID CHAR(12) COLLATE UTF8_LCASE NOT NULL,
    ACCT_ID CHAR(14) COLLATE UTF8_LCASE NOT NULL,
    ROLE_CD CHAR(2) COLLATE UTF8_LCASE NOT NULL,
    START_DT DATE,
    END_DT DATE,
    OWNERSHIP_PCT DECIMAL(5,2),
    ACTION_CD CHAR(1) COLLATE UTF8_LCASE
);

-- TODO: manual review required — the primary key translated from the UNIQUE PRIMARY INDEX is informational in Delta; enforce uniqueness in the write path.
-- The Teradata UNIQUE PRIMARY INDEX was replaced by an informational primary-key constraint.
ALTER TABLE KYC_PTAC_STG
ADD CONSTRAINT XPKKYC_PTAC_STG PRIMARY KEY (PARTY_ID, ACCT_ID, ROLE_CD);
