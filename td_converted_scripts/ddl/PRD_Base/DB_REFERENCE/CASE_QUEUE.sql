-- Teradata SET is removed; the source UPI already supplied the stronger uniqueness contract.
-- Source database qualification is removed because no target Unity Catalog mapping was supplied.
-- FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, and MAP are Teradata physical-storage options with no Delta DDL equivalent.
-- CHARACTER SET LATIN is removed because Databricks uses UTF-8; NOT CASESPECIFIC is preserved with UTF8_LCASE collation.
-- BYTEINT is mapped to the equivalent signed 8-bit TINYINT.
-- The Teradata UPI distribution clause is replaced by liquid clustering on its key.
CREATE TABLE CASE_QUEUE (
    QUEUE_CD CHAR(6) COLLATE UTF8_LCASE NOT NULL,
    QUEUE_NM VARCHAR(50) COLLATE UTF8_LCASE,
    SEGMENT_CD CHAR(3) COLLATE UTF8_LCASE NOT NULL,
    MIN_PRIORITY_NR TINYINT NOT NULL,
    MAX_PRIORITY_NR TINYINT NOT NULL,
    SLA_BUS_DAYS SMALLINT
)
CLUSTER BY (QUEUE_CD);

-- TODO: manual review required — Delta PRIMARY KEY metadata is informational; enforce XPKCASE_QUEUE uniqueness in the write path.
-- The named UNIQUE PRIMARY INDEX is preserved as an informational primary-key contract.
ALTER TABLE CASE_QUEUE ADD CONSTRAINT XPKCASE_QUEUE PRIMARY KEY (QUEUE_CD);
