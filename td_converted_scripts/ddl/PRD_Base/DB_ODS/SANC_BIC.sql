-- TODO: manual review required — Teradata SET table full-row uniqueness is lost because Delta uses multiset semantics; de-duplicate against both existing and incoming rows in the write path.
-- Converted the two-part source name to an unqualified target name because no Unity Catalog mapping was supplied; the current catalog and schema will be used.
-- Dropped SET and Teradata physical storage, recovery, journaling, checksum, merge-block, and map clauses; Delta manages these concerns.
-- Preserved CHAR width, replaced LATIN NOT CASESPECIFIC with UTF-8 case-insensitive collation, mapped INTEGER to INT and naive TIMESTAMP(0) to TIMESTAMP_NTZ, and removed display-only FORMAT.
CREATE TABLE SANC_BIC (
    BIC_CD CHAR(11) COLLATE UTF8_LCASE NOT NULL,
    GROUP_ID INT NOT NULL,
    CO_UPD_TMS TIMESTAMP_NTZ
);

-- TODO: manual review required — the Teradata UNIQUE PRIMARY INDEX uniqueness contract becomes an informational, unenforced Delta primary key; enforce uniqueness in the write path.
-- Replaced the UNIQUE PRIMARY INDEX with a named informational primary key constraint; Teradata AMP distribution is not carried over.
ALTER TABLE SANC_BIC ADD CONSTRAINT XPKSANC_BIC PRIMARY KEY (BIC_CD, GROUP_ID);
