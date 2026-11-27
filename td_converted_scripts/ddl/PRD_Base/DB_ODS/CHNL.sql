-- Converted the Teradata SET table to a Delta table; Delta does not enforce SET row uniqueness.
-- Removed Teradata FALLBACK, journal, checksum, merge-block-ratio, and map storage options.
-- Removed display-only FORMAT and LATIN character-set clauses; preserved NOT CASESPECIFIC with UTF8_LCASE.
-- Mapped the timezone-naive Teradata TIMESTAMP to TIMESTAMP_NTZ.
-- Omitted the source database qualifier because no target catalog/schema mapping was supplied.
-- TODO: manual review required — Delta primary keys are informational; enforce XPKCHNL uniqueness in the write path.
CREATE TABLE CHNL (
    CHNL_CD CHAR(3) COLLATE UTF8_LCASE NOT NULL,
    START_DT DATE NOT NULL,
    END_DT DATE NOT NULL DEFAULT DATE '9999-12-31',
    CHNL_DESC VARCHAR(40) COLLATE UTF8_LCASE,
    DIGITAL_IND CHAR(1) COLLATE UTF8_LCASE,
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- Replaced the Teradata UNIQUE PRIMARY INDEX with an informational Delta primary key.
ALTER TABLE CHNL ADD CONSTRAINT XPKCHNL PRIMARY KEY (CHNL_CD, START_DT);
