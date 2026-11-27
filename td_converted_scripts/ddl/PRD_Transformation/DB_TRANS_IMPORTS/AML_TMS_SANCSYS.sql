-- Teradata SET is omitted; the source UPI supplied the table's stronger uniqueness contract.
-- Teradata FALLBACK, JOURNAL, CHECKSUM, MERGEBLOCKRATIO, and MAP physical-storage clauses are omitted for Delta.
-- The source database qualifier is omitted because no target Unity Catalog mapping was supplied.
-- BYTEINT is mapped to TINYINT; timezone-naive TIMESTAMP(0) is mapped to TIMESTAMP_NTZ; FORMAT display metadata is omitted.
CREATE TABLE AML_TMS_SANCSYS (
    SSQ_ID TINYINT NOT NULL,
    TMS TIMESTAMP_NTZ NOT NULL
);

-- TODO: manual review required — Delta does not enforce the source UPI uniqueness; enforce SSQ_ID uniqueness in the write path.
-- The Teradata UNIQUE PRIMARY INDEX is represented by an informational primary key constraint.
ALTER TABLE AML_TMS_SANCSYS
ADD CONSTRAINT XPKAML_TMS_SANCSYS PRIMARY KEY (SSQ_ID);
