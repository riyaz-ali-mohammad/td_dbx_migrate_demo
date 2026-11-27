-- Converted Teradata SET, FALLBACK, journal, CHECKSUM, MERGEBLOCKRATIO, and MAP options to Delta defaults.
-- Removed CHARACTER SET LATIN, preserved NOT CASESPECIFIC with UTF8_LCASE collation, and removed the display-only FORMAT clause.
-- Mapped the timezone-naive TIMESTAMP to TIMESTAMP_NTZ and left the table unqualified because no target catalog mapping was supplied.
-- TODO: manual review required — Teradata SET table row-uniqueness is lost because Delta is multiset; enforce de-duplication in the write path.
-- TODO: manual review required — verify bounded VARCHAR(35) and fixed-width CHAR(4) padding/overflow behavior in target ingestion and consumers.
CREATE TABLE TM_ALERT_TXN (
    ALERT_ID BIGINT NOT NULL,
    TXN_REF VARCHAR(35) COLLATE UTF8_LCASE NOT NULL,
    SUPPLIER_CD CHAR(4) COLLATE UTF8_LCASE NOT NULL,
    CO_UPD_TMS TIMESTAMP_NTZ
)
CLUSTER BY (ALERT_ID, TXN_REF, SUPPLIER_CD);

-- Converted the UNIQUE PRIMARY INDEX to an informational primary key; liquid clustering above replaces its physical distribution role.
-- TODO: manual review required — Delta primary keys are informational and do not enforce the source uniqueness contract.
ALTER TABLE TM_ALERT_TXN
ADD CONSTRAINT XPKTM_ALERT_TXN PRIMARY KEY (ALERT_ID, TXN_REF, SUPPLIER_CD);
