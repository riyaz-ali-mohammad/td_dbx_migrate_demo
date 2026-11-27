-- Converted the Teradata table to a session-resolved Delta table because no target catalog mapping was supplied; removed FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, MAP, and the physical primary index.
-- Converted INTEGER to INT, naive TIMESTAMP columns to TIMESTAMP_NTZ, removed display-only FORMAT and LATIN character-set clauses, and preserved NOT CASESPECIFIC behavior with UTF8_LCASE collation.
-- TODO: manual review required — Teradata SET table row-uniqueness is lost because Delta uses multiset semantics; enforce de-duplication in the write path.
-- TODO: manual review required — verify fixed-width CHAR padding and bounded VARCHAR behavior for source consumers.
CREATE TABLE SANC_ENTITY_HIST (
    GROUP_ID INT NOT NULL,
    START_DT DATE NOT NULL,
    UPD_TMS TIMESTAMP_NTZ NOT NULL,
    END_DT DATE,
    GROUP_TYP_CD CHAR(1) COLLATE UTF8_LCASE,
    REGIME_NM VARCHAR(100) COLLATE UTF8_LCASE,
    LISTED_DT DATE,
    LAST_UPD_DT DATE,
    UK_SANC_REF VARCHAR(20) COLLATE UTF8_LCASE,
    BIRTH_DT DATE,
    NATIONALITY_CTRY_CD CHAR(2) COLLATE UTF8_LCASE,
    ADDR_CTRY_CD CHAR(2) COLLATE UTF8_LCASE,
    ACTION_CD CHAR(1) COLLATE UTF8_LCASE,
    CO_UPD_TMS TIMESTAMP_NTZ
);

-- Converted the UNIQUE PRIMARY INDEX to an informational Delta primary key.
-- TODO: manual review required — Delta primary keys are informational and do not enforce the Teradata UPI uniqueness contract; enforce uniqueness in the write path.
ALTER TABLE SANC_ENTITY_HIST
ADD CONSTRAINT XPKSANC_ENTITY_HIST PRIMARY KEY (GROUP_ID, START_DT, UPD_TMS);
