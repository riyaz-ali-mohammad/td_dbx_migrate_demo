-- Converted SET and Teradata storage clauses to Delta defaults; mapped BYTEINT and naive TIMESTAMP, removed display FORMAT, used the current namespace, and replaced UPI distribution with liquid clustering.
CREATE TABLE AML_TMS_KYCSYS (
    SSQ_ID TINYINT NOT NULL,
    TMS TIMESTAMP_NTZ NOT NULL
)
CLUSTER BY (SSQ_ID);

-- TODO: manual review required — the source UNIQUE PRIMARY INDEX enforced SSQ_ID uniqueness; Databricks PRIMARY KEY metadata is informational, so enforce uniqueness in the write path.
ALTER TABLE AML_TMS_KYCSYS
ADD CONSTRAINT XPKAML_TMS_KYCSYS PRIMARY KEY (SSQ_ID);
