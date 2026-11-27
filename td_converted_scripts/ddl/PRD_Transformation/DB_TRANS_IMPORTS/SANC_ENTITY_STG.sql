-- Converted the Teradata SET table to a Delta table; Delta does not enforce full-row uniqueness.
-- Removed Teradata FALLBACK, JOURNAL, CHECKSUM, MERGEBLOCKRATIO, MAP, FORMAT, and CHARACTER SET clauses; translated NOT CASESPECIFIC to UTF8_LCASE collation.
-- The source database qualifier was removed because no target Unity Catalog mapping was supplied.
CREATE TABLE SANC_ENTITY_STG (
    GROUP_ID INT NOT NULL,
    GROUP_TYP_CD CHAR(1) COLLATE UTF8_LCASE,
    REGIME_NM VARCHAR(100) COLLATE UTF8_LCASE,
    LISTED_DT DATE,
    LAST_UPD_DT DATE,
    UK_SANC_REF VARCHAR(20) COLLATE UTF8_LCASE,
    BIRTH_DT DATE,
    NATIONALITY_CTRY_NM VARCHAR(60) COLLATE UTF8_LCASE,
    NATIONALITY_CTRY_CD CHAR(2) COLLATE UTF8_LCASE,
    ADDR_CTRY_NM VARCHAR(60) COLLATE UTF8_LCASE,
    ADDR_CTRY_CD CHAR(2) COLLATE UTF8_LCASE,
    PASSPORT_NR VARCHAR(60) COLLATE UTF8_LCASE
);

-- TODO: manual review required — Delta primary keys are informational; enforce the source UPI uniqueness of GROUP_ID in the write path.
-- Replaced the Teradata UNIQUE PRIMARY INDEX with an informational primary key constraint.
ALTER TABLE SANC_ENTITY_STG
ADD CONSTRAINT XPKSANC_ENTITY_STG PRIMARY KEY (GROUP_ID);
