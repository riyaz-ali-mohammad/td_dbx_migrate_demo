-- Converted the Teradata SET table to Delta; the source UPI contract is retained as an informational primary key below.
-- Removed Teradata FALLBACK, journal, checksum, merge-block-ratio, and MAP physical-storage attributes.
-- Removed LATIN character-set clauses because Databricks strings use UTF-8; retained case-insensitive behavior with UTF8_LCASE.
-- Left the table unqualified because no target Unity Catalog mapping was supplied; it resolves in the current catalog and schema.
-- Enabled Delta column defaults for the two DEFAULT expressions.
-- Replaced the Teradata primary-index layout with liquid clustering on the same key columns.
CREATE TABLE view_access_ctrl (
    user_nm VARCHAR(128) COLLATE UTF8_LCASE NOT NULL,
    segment_cd CHAR(3) COLLATE UTF8_LCASE NOT NULL,
    pii_access_ind CHAR(1) COLLATE UTF8_LCASE DEFAULT 'N',
    sar_access_ind CHAR(1) COLLATE UTF8_LCASE DEFAULT 'N'
)
CLUSTER BY (user_nm, segment_cd)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- TODO: manual review required — Delta primary keys are informational, so enforce the source UPI uniqueness in the write path.
-- Converted UNIQUE PRIMARY INDEX XPKVIEW_ACCESS_CTRL to an informational primary-key constraint.
ALTER TABLE view_access_ctrl
ADD CONSTRAINT xpkview_access_ctrl PRIMARY KEY (user_nm, segment_cd);
