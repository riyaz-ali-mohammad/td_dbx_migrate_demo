-- Converted Teradata SET/storage clauses, character settings, data types, display FORMAT, and primary-index distribution to Databricks SQL.
-- TODO: manual review required — Teradata SET and UNIQUE PRIMARY INDEX enforcement are informational only in Delta; enforce uniqueness in the write path.
CREATE TABLE DIM_PRODUCT (
    PRDT_CD CHAR(6) COLLATE UTF8_LCASE NOT NULL,
    PRDT_DESC VARCHAR(50) COLLATE UTF8_LCASE,
    PRDT_FAMILY_CD CHAR(4) COLLATE UTF8_LCASE,
    SEGMENT_CD CHAR(3) COLLATE UTF8_LCASE,
    PRDT_RISK_CD CHAR(1) COLLATE UTF8_LCASE,
    ACTIVE_ACCT_CNT INT,
    CO_UPD_TMS TIMESTAMP_NTZ
)
CLUSTER BY (PRDT_CD);

-- Converted the Teradata UNIQUE PRIMARY INDEX to an informational Delta primary-key constraint.
ALTER TABLE DIM_PRODUCT
ADD CONSTRAINT XPKDIM_PRODUCT PRIMARY KEY (PRDT_CD);
