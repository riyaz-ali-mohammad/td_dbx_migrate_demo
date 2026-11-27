/**************************************************************************\
* CLEAR THE PRIMARY WORKTABLES PRIOR TO LOADING                            *
* ------------------------------------------------------------------------ *
* The consolidated sanctions list is delivered as a FULL file every run.   *
\**************************************************************************/

-- Converted the Teradata two-part table name to an unqualified Unity Catalog object because no target catalog/schema mapping was supplied.
DELETE FROM AML_SANCSYS_RAW;


/**************************************************************************\
* LOAD THE PIPE-DELIMITED CONSOLIDATED SANCTIONS FILE                      *
* ------------------------------------------------------------------------ *
* The first record is a header. UTF-8 preserves non-Latin names.           *
\**************************************************************************/

-- TODO: manual review required — MultiLoad → COPY INTO staging + MERGE INTO (confirm source path).
-- Converted the MultiLoad field layout to a temporary Databricks staging table.
CREATE OR REPLACE TEMP TABLE sancsys_raw_stage
(
    group_id STRING,
    name_6 STRING,
    name_1 STRING,
    name_2 STRING,
    name_3 STRING,
    name_4 STRING,
    name_5 STRING,
    title STRING,
    name_non_latin STRING,
    dob STRING,
    town_of_birth STRING,
    ctry_of_birth STRING,
    nationality STRING,
    passport_nr STRING,
    national_id_nr STRING,
    `position` STRING,
    addr_1 STRING,
    addr_ctry STRING,
    other_info STRING,
    group_type STRING,
    alias_type STRING,
    alias_quality STRING,
    regime STRING,
    listed_on STRING,
    uk_sanc_list_dt STRING,
    last_updated STRING,
    uk_sanc_list_ref STRING
);

-- Converted the MultiLoad VARTEXT import to a UTF-8, pipe-delimited COPY INTO operation that skips the header row.
COPY INTO sancsys_raw_stage
FROM '/Volumes/<catalog>/<schema>/<volume>/kycref.sancsys.txt'
FILEFORMAT = CSV
FORMAT_OPTIONS
(
    'header' = 'true',
    'delimiter' = '|',
    'encoding' = 'UTF-8',
    'mode' = 'FAILFAST'
);

-- Converted the MultiLoad insert to a MERGE; the false condition inserts every staged row after the target was cleared.
MERGE INTO AML_SANCSYS_RAW AS target
USING sancsys_raw_stage AS source
ON 1 = 0
WHEN NOT MATCHED THEN INSERT
(
    group_id,
    name_6,
    name_1,
    name_2,
    name_3,
    name_4,
    name_5,
    title,
    name_non_latin,
    dob,
    town_of_birth,
    ctry_of_birth,
    nationality,
    passport_nr,
    national_id_nr,
    `position`,
    addr_1,
    addr_ctry,
    other_info,
    group_type,
    alias_type,
    alias_quality,
    regime,
    listed_on,
    uk_sanc_list_dt,
    last_updated,
    uk_sanc_list_ref
)
VALUES
(
    source.group_id,
    source.name_6,
    source.name_1,
    source.name_2,
    source.name_3,
    source.name_4,
    source.name_5,
    source.title,
    source.name_non_latin,
    source.dob,
    source.town_of_birth,
    source.ctry_of_birth,
    source.nationality,
    source.passport_nr,
    source.national_id_nr,
    source.`position`,
    source.addr_1,
    source.addr_ctry,
    source.other_info,
    source.group_type,
    source.alias_type,
    source.alias_quality,
    source.regime,
    source.listed_on,
    source.uk_sanc_list_dt,
    source.last_updated,
    source.uk_sanc_list_ref
);

-- Removed the temporary staging table that replaces the MultiLoad work and error tables.
DROP TABLE sancsys_raw_stage;
