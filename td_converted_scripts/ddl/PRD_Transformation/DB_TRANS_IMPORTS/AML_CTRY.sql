-- Converted Teradata SET table to Delta table; the source database qualifier is omitted because no target catalog mapping was supplied.
-- Removed Teradata FALLBACK, journal, checksum, merge-block-ratio, and map storage clauses; Delta manages durability and physical storage.
-- Removed LATIN character-set clauses because Databricks SQL stores strings as UTF-8; preserved NOT CASESPECIFIC with UTF8_LCASE collation.
-- Removed DATE FORMAT display metadata because Databricks SQL renders DATE as YYYY-MM-DD by default.
-- Replaced the Teradata unique primary index with liquid clustering and an informational primary key.
-- TODO: manual review required — Delta does not enforce the source UNIQUE PRIMARY INDEX; enforce CTRY_2_CD uniqueness in the write path.
CREATE TABLE AML_CTRY (
    CTRY_2_CD CHAR(2) COLLATE UTF8_LCASE NOT NULL,
    CTRY_3_CD CHAR(3) COLLATE UTF8_LCASE,
    CTRY_NM VARCHAR(50) COLLATE UTF8_LCASE,
    FATF_STATUS_CD CHAR(2) COLLATE UTF8_LCASE,
    HMT_HIGH_RISK_IND CHAR(1) COLLATE UTF8_LCASE,
    EU_HIGH_RISK_IND CHAR(1) COLLATE UTF8_LCASE,
    BASEL_AML_SCORE DECIMAL(5, 2),
    CPI_SCORE SMALLINT,
    OFFSHORE_IND CHAR(1) COLLATE UTF8_LCASE,
    REGION_CD CHAR(3) COLLATE UTF8_LCASE,
    VALID_FROM_DT DATE,
    VALID_TO_DT DATE,
    ACTION_CD CHAR(1) COLLATE UTF8_LCASE
)
CLUSTER BY (CTRY_2_CD);

-- Preserved the source unique-key contract as an informational Databricks primary key constraint.
ALTER TABLE AML_CTRY
ADD CONSTRAINT XPKAML_CTRY PRIMARY KEY (CTRY_2_CD);
