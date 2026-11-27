-- Converted the Teradata two-part name to an unqualified table because no target catalog mapping was supplied.
-- Removed SET, FALLBACK, JOURNAL, CHECKSUM, MERGEBLOCKRATIO, MAP, FORMAT, and CHARACTER SET clauses; Delta manages the corresponding storage concerns and display formats are not stored.
-- Mapped BYTEINT to TINYINT, naive TIMESTAMP(0) to TIMESTAMP_NTZ, and NOT CASESPECIFIC to UTF8_LCASE collation.
-- TODO: manual review required — enforce the source SET/unique-primary-index uniqueness contract in the write path because the Delta primary key is informational.
-- TODO: manual review required — validate fixed-width CHAR padding and trailing-space comparison behavior for FILE_ID and SUPPLIER_CD in consuming workloads.
CREATE TABLE DLYTXN_LOAD_TMS (
    SSQ_ID TINYINT NOT NULL,
    LOAD_TMS TIMESTAMP_NTZ NOT NULL,
    BUSINESS_DT DATE NOT NULL,
    FILE_ID CHAR(20) COLLATE UTF8_LCASE,
    SUPPLIER_CD CHAR(4) COLLATE UTF8_LCASE
)
CLUSTER BY (SSQ_ID);

-- Replaced the Teradata UNIQUE PRIMARY INDEX with an informational primary key while retaining SSQ_ID as the liquid-clustering key.
ALTER TABLE DLYTXN_LOAD_TMS
ADD CONSTRAINT XPKDLYTXN_LOAD_TMS PRIMARY KEY (SSQ_ID);
