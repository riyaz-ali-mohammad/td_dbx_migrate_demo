-- TODO: manual review required — Teradata SET table row-uniqueness is lost because Delta is multiset; enforce de-duplication in the write path.
-- TODO: manual review required — verify that consumers of CCY_CD retain the required CHAR(3) fixed-width padding and trailing-space comparison behavior.
-- Converted the two-part source name to an unqualified table because no target catalog mapping was supplied; stripped Teradata FALLBACK, JOURNAL, CHECKSUM, MERGEBLOCKRATIO, MAP, CHARACTER SET, and display FORMAT clauses.
CREATE TABLE info_dlytxn_error_fxrate (
    ccy_cd CHAR(3) COLLATE UTF8_LCASE NOT NULL,
    booking_dt DATE NOT NULL,
    txn_cnt INT,
    co_upd_tms TIMESTAMP_NTZ NOT NULL
);

-- Converted the Teradata unique primary index to an informational Databricks primary key constraint.
ALTER TABLE info_dlytxn_error_fxrate
ADD CONSTRAINT XPKINFO_DLYTXN_ERROR_FXRATE PRIMARY KEY (ccy_cd, booking_dt);
