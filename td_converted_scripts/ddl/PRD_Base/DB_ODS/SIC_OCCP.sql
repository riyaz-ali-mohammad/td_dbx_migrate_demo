-- TODO: manual review required — Teradata SET table row-uniqueness is lost because Delta is multiset; enforce de-duplication in every write path.
-- The source database qualifier was removed because no target Unity Catalog mapping was supplied.
-- Teradata FALLBACK, JOURNAL, CHECKSUM, MERGEBLOCKRATIO, and MAP storage options were removed; Delta and cloud storage manage durability and layout.
-- CHARACTER SET LATIN was removed because Databricks uses UTF-8; NOT CASESPECIFIC was mapped to UTF8_LCASE collation.
-- Teradata display-only FORMAT clauses were removed, and timezone-naive TIMESTAMP(0) was mapped to TIMESTAMP_NTZ.
-- The column default requires the Delta allowColumnDefaults table feature.
CREATE TABLE SIC_OCCP (
  SIC_CD CHAR(5) COLLATE UTF8_LCASE NOT NULL,
  START_DT DATE NOT NULL,
  END_DT DATE NOT NULL DEFAULT DATE '9999-12-31',
  SIC_DESC VARCHAR(60) COLLATE UTF8_LCASE,
  SIC_RISK_CD CHAR(1) COLLATE UTF8_LCASE,
  CASH_INTENSIVE_IND CHAR(1) COLLATE UTF8_LCASE,
  CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- TODO: manual review required — the source UNIQUE PRIMARY INDEX enforced key uniqueness, but the Databricks primary key is informational; enforce uniqueness in the write path.
-- The Teradata UNIQUE PRIMARY INDEX was replaced with an informational primary key constraint.
ALTER TABLE SIC_OCCP ADD CONSTRAINT XPKSIC_OCCP PRIMARY KEY (SIC_CD, START_DT);
