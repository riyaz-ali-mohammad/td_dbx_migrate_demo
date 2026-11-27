-- TODO: manual review required — Teradata SET/UPI uniqueness is not enforced by Delta's informational primary key; enforce uniqueness in the write path.
-- TODO: manual review required — confirm downstream consumers preserve the source CHAR(n) padding and trailing-space comparison behavior.
-- Converted the Teradata SET table to Delta, removed FALLBACK/JOURNAL/CHECKSUM/MERGEBLOCKRATIO/MAP and display FORMAT clauses, mapped BYTEINT and TIMESTAMP, and preserved case-insensitive columns with collation.
-- The source database qualifier was removed because no target Unity Catalog mapping was supplied; CCY resolves in the current catalog and schema.
CREATE TABLE CCY (
    CCY_CD CHAR(3) COLLATE UTF8_LCASE NOT NULL,
    START_DT DATE NOT NULL,
    END_DT DATE NOT NULL DEFAULT DATE '9999-12-31',
    CCY_NM VARCHAR(30) COLLATE UTF8_LCASE,
    MINOR_UNIT_CNT TINYINT,
    CCY_NUM_CD CHAR(3) COLLATE UTF8_LCASE,
    ACTIVE_IND CHAR(1) COLLATE UTF8_LCASE,
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
)
CLUSTER BY (CCY_CD, START_DT)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- Converted the Teradata UNIQUE PRIMARY INDEX to an informational Delta primary key; clustering above retains the physical-design intent.
ALTER TABLE CCY ADD CONSTRAINT XPKCCY PRIMARY KEY (CCY_CD, START_DT);
