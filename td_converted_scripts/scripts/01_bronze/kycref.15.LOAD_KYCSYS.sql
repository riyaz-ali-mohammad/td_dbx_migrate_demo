-- TODO: manual review required — MultiLoad → COPY INTO staging + MERGE INTO (confirm source path)
-- assumption: DB_TRANS_IMPORTS maps to the current Databricks catalog and schema.
-- Converted the Teradata pre-load DELETE to Databricks SQL and removed the source database qualifier.
DELETE FROM aml_kycsys_raw;

-- Converted the MultiLoad fixed-width layout to a one-column temporary staging table.
CREATE OR REPLACE TEMP TABLE kycsys_raw_stage (
    raw_line STRING
);

-- Converted .IMPORT FORMAT TEXT to COPY INTO; FORCE preserves full reload behavior for the recreated staging table.
COPY INTO kycsys_raw_stage
FROM '../data/kycref.kycsys.dat'
FILEFORMAT = TEXT
COPY_OPTIONS ('force' = 'true');

-- Converted the MultiLoad INSERT and APPLY filter to an insert-only MERGE with fixed-width field extraction.
MERGE INTO aml_kycsys_raw AS target
USING (
    SELECT
        SUBSTRING(raw_line, 1, 2) AS a,
        SUBSTRING(raw_line, 3, 26) AS b,
        SUBSTRING(raw_line, 29, 472) AS c
    FROM kycsys_raw_stage
    WHERE SUBSTRING(raw_line, 1, 2) NOT IN ('HD', 'TR')
) AS source
ON FALSE
WHEN NOT MATCHED THEN
    INSERT (a, b, c)
    VALUES (source.a, source.b, source.c);

-- Removed the temporary replacement for the MultiLoad work and error tables.
DROP TABLE kycsys_raw_stage;
