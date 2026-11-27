-- Removed Teradata SET; the source UPI already supplied the stronger uniqueness contract.
-- Left the table unqualified because no target Unity Catalog mapping was supplied for DB_ODS.
-- Removed FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, and MAP physical-storage clauses; Delta manages durability and layout.
-- Removed CHARACTER SET LATIN because Databricks SQL stores strings as UTF-8.
-- Replaced NOT CASESPECIFIC with UTF8_LCASE collation.
-- TODO: manual review required — verify fixed-width CHAR(3) padding behavior in dependent writes and comparisons.
-- Removed the DATE FORMAT display-only clause; Databricks renders DATE values as yyyy-MM-dd by default.
-- Removed the Teradata UNIQUE PRIMARY INDEX; its logical key is recreated as informational metadata below.
CREATE TABLE FX_RATE_SNAPSHOT (
    CCY_CD CHAR(3) COLLATE UTF8_LCASE NOT NULL,
    RATE_DT DATE NOT NULL,
    GBP_RATE DECIMAL(18, 8) NOT NULL
);

-- Replaced the Teradata UNIQUE PRIMARY INDEX with a named Delta primary key.
-- TODO: manual review required — Delta primary keys are informational; enforce CCY_CD uniqueness in the write path.
ALTER TABLE FX_RATE_SNAPSHOT
ADD CONSTRAINT XPKFX_RATE_SNAPSHOT PRIMARY KEY (CCY_CD);
