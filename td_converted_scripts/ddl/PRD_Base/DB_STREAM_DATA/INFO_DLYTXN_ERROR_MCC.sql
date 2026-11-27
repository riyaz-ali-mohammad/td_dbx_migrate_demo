-- TODO: manual review required — Teradata SET table row-uniqueness is lost (Delta is multiset); enforce de-duplication in every write path
-- TODO: manual review required — verify that target CHAR(4) fixed-width and trailing-space behavior matches dependent consumers
-- Converted the Teradata two-part name to an unqualified name because no target Unity Catalog mapping was supplied
-- Removed Teradata FALLBACK, JOURNAL, CHECKSUM, MERGEBLOCKRATIO, and MAP physical-storage clauses
-- Removed CHARACTER SET LATIN and mapped NOT CASESPECIFIC to UTF8_LCASE collation
-- Mapped timezone-naive TIMESTAMP(0) to TIMESTAMP_NTZ and removed its display-only FORMAT clause
CREATE TABLE INFO_DLYTXN_ERROR_MCC (
    MCC_CD CHAR(4) COLLATE UTF8_LCASE NOT NULL,
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
);

-- TODO: manual review required — the source UPI uniqueness contract is informational only in Delta and must be enforced by the write path
-- Replaced the Teradata UNIQUE PRIMARY INDEX with a named informational PRIMARY KEY constraint
ALTER TABLE INFO_DLYTXN_ERROR_MCC
ADD CONSTRAINT XPKINFO_DLYTXN_ERROR_MCC PRIMARY KEY (MCC_CD);
