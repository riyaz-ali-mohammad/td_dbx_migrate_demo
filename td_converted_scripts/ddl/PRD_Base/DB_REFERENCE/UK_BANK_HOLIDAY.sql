-- TODO: manual review required — Teradata SET table row-uniqueness is lost (Delta is multiset); de-dup at load (SELECT DISTINCT / MERGE) or add a constraint
-- Converted the two-part Teradata name to an unqualified name because no target Unity Catalog mapping was supplied.
-- Removed Teradata physical storage and resilience options; Delta manages storage, durability, and rollback.
-- Removed the DATE display FORMAT because it does not affect stored values.
-- Removed CHARACTER SET LATIN because Databricks uses UTF-8, and preserved NOT CASESPECIFIC with a case-insensitive collation.
CREATE TABLE uk_bank_holiday (
    holiday_dt DATE NOT NULL,
    holiday_nm VARCHAR(50) COLLATE UTF8_LCASE
);

-- TODO: manual review required — the source UNIQUE PRIMARY INDEX enforced key uniqueness, while the Delta primary key is informational; enforce uniqueness in the write path.
-- Converted the Teradata UNIQUE PRIMARY INDEX to an informational primary key constraint.
ALTER TABLE uk_bank_holiday
ADD CONSTRAINT xpkuk_bank_holiday PRIMARY KEY (holiday_dt);
