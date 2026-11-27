-- Converted the Teradata two-part name to an unqualified table because no target catalog mapping was supplied.
-- Dropped SET and Teradata-only FALLBACK, journal, checksum, merge-block-ratio, map, and primary-index storage clauses.
-- Preserved bounded character columns and case-insensitive semantics; Databricks stores text as UTF-8.
-- Mapped the timezone-naive Teradata timestamp to TIMESTAMP_NTZ and removed its display-only FORMAT clause.
-- Enabled the Delta column-default feature for AUTO_ADDED_IND.
CREATE TABLE RETURN_REASON (
    RETURN_REASON_CD CHAR(4) COLLATE UTF8_LCASE NOT NULL,
    RETURN_REASON_DESC VARCHAR(60) COLLATE UTF8_LCASE,
    AUTO_ADDED_IND CHAR(1) COLLATE UTF8_LCASE DEFAULT 'N',
    CO_UPD_TMS TIMESTAMP_NTZ
)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- TODO: manual review required — Databricks primary keys are informational; enforce XPKRETURN_REASON uniqueness in the write path.
-- Converted the Teradata UNIQUE PRIMARY INDEX into an informational primary-key constraint.
ALTER TABLE RETURN_REASON
ADD CONSTRAINT XPKRETURN_REASON PRIMARY KEY (RETURN_REASON_CD);
