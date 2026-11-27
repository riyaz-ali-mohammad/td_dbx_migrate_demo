-- Converted the Teradata SET table to a Delta table; removed FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, MAP, and the source database qualifier because no target catalog mapping was supplied.
-- Converted LATIN NOT CASESPECIFIC columns to UTF-8 CHAR columns with case-insensitive collation.
-- TODO: manual review required — Delta does not enforce Teradata SET or UNIQUE PRIMARY INDEX uniqueness; enforce CHNL_CD and full-row uniqueness in the write path.
-- TODO: manual review required — validate downstream dependencies on fixed-width CHAR padding and trailing-space comparison behavior.
CREATE TABLE CHNL_SNAPSHOT (
    CHNL_CD CHAR(3) COLLATE UTF8_LCASE NOT NULL,
    DIGITAL_IND CHAR(1) COLLATE UTF8_LCASE
);

-- Converted the Teradata UNIQUE PRIMARY INDEX to an informational Delta primary key.
-- TODO: manual review required — this primary key records the contract but does not enforce uniqueness.
ALTER TABLE CHNL_SNAPSHOT
ADD CONSTRAINT XPKCHNL_SNAPSHOT PRIMARY KEY (CHNL_CD);
