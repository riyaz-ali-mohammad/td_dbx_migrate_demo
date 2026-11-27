-- TODO: manual review required — Teradata SET and UNIQUE PRIMARY INDEX uniqueness are not enforced by Delta; enforce uniqueness in the write path
-- TODO: manual review required — verify bounded CHAR/VARCHAR length and CHAR padding behavior for downstream consumers
-- Converted the two-part source name to an unqualified table because no target catalog mapping was supplied
-- Removed Teradata FALLBACK, journal, CHECKSUM, MERGEBLOCKRATIO, MAP, and FORMAT clauses; replaced NOT CASESPECIFIC with UTF8_LCASE collation
CREATE TABLE DLYTXN_NEW_CPTY (
    CPTY_ACCT_KEY VARCHAR(34) COLLATE UTF8_LCASE NOT NULL,
    CPTY_NORM_NM VARCHAR(140) COLLATE UTF8_LCASE NOT NULL,
    CPTY_BIC_CD CHAR(11) COLLATE UTF8_LCASE,
    CPTY_CTRY_CD CHAR(2) COLLATE UTF8_LCASE,
    FIRST_SEEN_DT DATE
);

-- Replaced the Teradata UNIQUE PRIMARY INDEX with an informational Delta primary key
ALTER TABLE DLYTXN_NEW_CPTY
ADD CONSTRAINT XPKDLYTXN_NEW_CPTY PRIMARY KEY (CPTY_ACCT_KEY, CPTY_NORM_NM);
