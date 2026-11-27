/**************************************************************************\
* CLEAR THE PRIMARY WORKTABLES PRIOR TO LOADING                            *
\**************************************************************************/

-- Converted the Teradata database-qualified name to the current Unity Catalog namespace.
DELETE FROM AML_REFSYS_RAW;


/**************************************************************************\
* LOAD THE REFSYS DAILY FIXED-WIDTH EXTRACT                                *
* A = record type (2 bytes), B = business key (30 bytes),                  *
* C = payload (221 bytes); HD and TR records are excluded.                 *
\**************************************************************************/

-- TODO: manual review required — MultiLoad → COPY INTO staging (confirm source path ../data/kycref.refsys.dat).
-- Converted the MultiLoad layout to a one-column temporary text staging table.
CREATE OR REPLACE TEMP TABLE refsys_raw_text_stage (
    value STRING
);

-- Converted the MultiLoad file import to Databricks COPY INTO for line-oriented text.
COPY INTO refsys_raw_text_stage
FROM '../data/kycref.refsys.dat'
FILEFORMAT = TEXT
FORMAT_OPTIONS (
    'wholetext' = 'false'
);

-- Converted positional MultiLoad fields and APPLY filtering to fixed-width substrings.
-- Converted the Teradata database-qualified target to the current Unity Catalog namespace.
-- Converted plain double-quoted column identifiers to unquoted Databricks identifiers.
INSERT INTO AML_REFSYS_RAW (a, b, c)
SELECT
    SUBSTRING(value, 1, 2) AS a,
    SUBSTRING(value, 3, 30) AS b,
    SUBSTRING(value, 33, 221) AS c
FROM refsys_raw_text_stage
WHERE SUBSTRING(value, 1, 2) NOT IN ('HD', 'TR');

-- Removed the temporary staging table after the load.
DROP TABLE refsys_raw_text_stage;
