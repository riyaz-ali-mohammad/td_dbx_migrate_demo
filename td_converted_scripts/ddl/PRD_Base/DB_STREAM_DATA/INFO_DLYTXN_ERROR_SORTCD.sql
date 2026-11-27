-- Converted the Teradata SET table to Delta multiset semantics.
-- Removed Teradata FALLBACK, journal, checksum, merge-block-ratio, and MAP storage options.
-- Removed CHARACTER SET LATIN because Databricks stores strings as UTF-8.
-- Replaced NOT CASESPECIFIC with the UTF8_LCASE collation.
-- Mapped the timezone-naive Teradata TIMESTAMP to TIMESTAMP_NTZ and removed its display-only FORMAT.
-- The source database qualifier was removed because no target Unity Catalog mapping was supplied.
CREATE TABLE INFO_DLYTXN_ERROR_SORTCD (
    SORT_CD CHAR(6) COLLATE UTF8_LCASE NOT NULL,
    ERR_FIELD VARCHAR(30) COLLATE UTF8_LCASE NOT NULL,
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
);

-- TODO: manual review required — the source UNIQUE PRIMARY INDEX and SET-table uniqueness are informational only in Delta; enforce uniqueness for (SORT_CD, ERR_FIELD) in the write path.
-- Replaced the Teradata UNIQUE PRIMARY INDEX with an informational primary key.
ALTER TABLE INFO_DLYTXN_ERROR_SORTCD
ADD CONSTRAINT XPKINFO_DLYTXN_ERROR_SORTCD PRIMARY KEY (SORT_CD, ERR_FIELD);
