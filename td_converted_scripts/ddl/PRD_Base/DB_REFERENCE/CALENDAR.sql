-- TODO: manual review required — Teradata SET table row-uniqueness is lost because Delta is multiset; enforce de-duplication across incoming and existing rows in the write path
-- TODO: manual review required — verify fixed-width CHAR(1) blank-padding and comparison behavior for downstream consumers
-- Converted Teradata table DDL: removed SET and physical FALLBACK, JOURNAL, CHECKSUM, MERGEBLOCKRATIO, and MAP options; omitted the source database qualifier because no target catalog mapping was supplied
-- Converted column definitions: removed display-only FORMAT and LATIN character-set clauses, preserved NOT CASESPECIFIC with UTF8_LCASE collation, and mapped BYTEINT to TINYINT
CREATE TABLE CALENDAR (
    CAL_DT DATE NOT NULL,
    BUS_DAY_IND CHAR(1) COLLATE UTF8_LCASE,
    YR_MON INT,
    YR_NR SMALLINT,
    MTH_NR TINYINT,
    DAY_OF_WK_NR TINYINT,
    MTH_END_IND CHAR(1) COLLATE UTF8_LCASE
);

-- TODO: manual review required — Delta PRIMARY KEY metadata is informational and does not enforce the source UNIQUE PRIMARY INDEX
-- Converted the named UNIQUE PRIMARY INDEX to an informational primary key constraint
ALTER TABLE CALENDAR ADD CONSTRAINT XPKCALENDAR PRIMARY KEY (CAL_DT);
