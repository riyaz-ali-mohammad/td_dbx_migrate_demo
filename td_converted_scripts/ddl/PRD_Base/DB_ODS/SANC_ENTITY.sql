-- Teradata SET, FALLBACK, journal, checksum, merge-block-ratio, and MAP physical clauses are removed for Delta.
-- The source database qualifier is omitted because no target Unity Catalog mapping was supplied.
-- CHARACTER SET LATIN is removed; NOT CASESPECIFIC is preserved with UTF8_LCASE collation.
-- Teradata display-only FORMAT clauses are removed, and the naive TIMESTAMP maps to TIMESTAMP_NTZ.
-- TODO: manual review required — verify that consumers relying on fixed-width CHAR blank-padding and trailing-space behavior remain compatible.
CREATE TABLE SANC_ENTITY (
    GROUP_ID INT NOT NULL,
    GROUP_TYP_CD CHAR(1) COLLATE UTF8_LCASE,
    REGIME_NM VARCHAR(100) COLLATE UTF8_LCASE,
    LISTED_DT DATE,
    LAST_UPD_DT DATE,
    UK_SANC_REF VARCHAR(20) COLLATE UTF8_LCASE,
    BIRTH_DT DATE,
    NATIONALITY_CTRY_CD CHAR(2) COLLATE UTF8_LCASE,
    ADDR_CTRY_CD CHAR(2) COLLATE UTF8_LCASE,
    PASSPORT_NR VARCHAR(60) COLLATE UTF8_LCASE,
    ACTIVE_IND CHAR(1) COLLATE UTF8_LCASE DEFAULT 'Y',
    DELISTED_DT DATE,
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- Teradata UNIQUE PRIMARY INDEX is replaced by an informational Delta primary key.
-- TODO: manual review required — Delta does not enforce primary-key uniqueness; enforce GROUP_ID uniqueness in the write path.
ALTER TABLE SANC_ENTITY
ADD CONSTRAINT XPKSANC_ENTITY PRIMARY KEY (GROUP_ID);
