-- Source database qualifier omitted because no target Unity Catalog mapping was supplied.
-- Teradata SET, FALLBACK/JOURNAL, CHECKSUM, MERGEBLOCKRATIO, MAP, and primary-index storage clauses are removed for Delta.
-- CHARACTER SET LATIN is removed because Databricks uses UTF-8; NOT CASESPECIFIC is preserved with UTF8_LCASE collation.
-- TODO: manual review required — verify the bounded CHAR/VARCHAR contracts and CHAR trailing-pad behavior against consuming workloads.
-- TIMESTAMP(0) is mapped to timezone-naive TIMESTAMP_NTZ; its display-only FORMAT clause is removed.
CREATE TABLE INFO_DLYTXN_ERROR_CTRY (
    CTRY_CD CHAR(2) COLLATE UTF8_LCASE NOT NULL,
    ERR_FIELD VARCHAR(30) COLLATE UTF8_LCASE NOT NULL,
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
);

-- UNIQUE PRIMARY INDEX is represented as an informational Databricks primary key.
-- TODO: manual review required — Databricks does not enforce primary-key uniqueness; enforce the source UPI contract in the write path.
ALTER TABLE INFO_DLYTXN_ERROR_CTRY
ADD CONSTRAINT XPKINFO_DLYTXN_ERROR_CTRY PRIMARY KEY (CTRY_CD, ERR_FIELD);
