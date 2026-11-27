-- Teradata SET and physical FALLBACK, JOURNAL, CHECKSUM, MERGEBLOCKRATIO, and MAP clauses were removed; Delta manages storage layout and durability.
-- The source database qualifier was omitted because no target catalog and schema mapping was supplied.
-- CHARACTER SET LATIN was removed because Databricks uses UTF-8; NOT CASESPECIFIC was mapped to UTF8_LCASE collation.
-- INTEGER was mapped to INT, and timezone-naive TIMESTAMP(0) was mapped to TIMESTAMP_NTZ; the display-only FORMAT clause was removed.
-- TODO: manual review required — confirm CHAR(3) fixed-width padding and VARCHAR(40) bounded-value behavior remain compatible with all writers and consumers.
CREATE TABLE DIM_SEGMENT (
    SEGMENT_CD CHAR(3) COLLATE UTF8_LCASE NOT NULL,
    SEGMENT_DESC VARCHAR(40) COLLATE UTF8_LCASE,
    PARTY_CNT INT,
    CO_UPD_TMS TIMESTAMP_NTZ
);

-- The Teradata UNIQUE PRIMARY INDEX was replaced by a named informational Delta primary key.
-- TODO: manual review required — Delta primary keys are not enforced; the write path must enforce SEGMENT_CD uniqueness.
ALTER TABLE DIM_SEGMENT
ADD CONSTRAINT XPKDIM_SEGMENT PRIMARY KEY (SEGMENT_CD);
