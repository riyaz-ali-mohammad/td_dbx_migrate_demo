-- Delta uses multiset semantics; the source SET table's key contract is represented by the informational primary key below.
-- Removed Teradata FALLBACK, journal, checksum, merge-block-ratio, and map storage options, and display-only FORMAT clauses.
-- The source database qualifier is omitted because no target Unity Catalog mapping was supplied; the table resolves in the current catalog and schema.
-- Teradata's timezone-naive TIMESTAMP maps to TIMESTAMP_NTZ.
CREATE TABLE AML_CASE_ALERT_XREF (
    CASE_ID BIGINT NOT NULL,
    ALERT_ID BIGINT NOT NULL,
    ADDED_DT DATE NOT NULL,
    CO_UPD_TMS TIMESTAMP_NTZ
);

-- TODO: manual review required — Delta primary keys are informational, so enforce the source UNIQUE PRIMARY INDEX uniqueness in the write path.
-- Replaced the Teradata UNIQUE PRIMARY INDEX with an informational primary key constraint.
ALTER TABLE AML_CASE_ALERT_XREF
ADD CONSTRAINT XPKAML_CASE_ALERT_XREF PRIMARY KEY (CASE_ID, ALERT_ID);
