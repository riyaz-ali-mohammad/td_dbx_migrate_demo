-- TODO: manual review required — choose the BTEQ replacement wrapper: Databricks notebook, stored procedure, or Workflows DAG.
-- TODO: manual review required — confirm that statement-failure handling is delegated to the selected wrapper; Databricks aborts failed SQL statements automatically.
-- Databricks migration: BTEQ display controls were removed because they have no SQL equivalent.
-- assumption: deployment substitutes the environment token inside each quoted schema identifier.

/**************************************************************************\
* TAKE A TIMESTAMP SNAPSHOT                                                *
* ------------------------------------------------------------------------ *
* All reference data from the current REFSYS delivery shall receive the    *
* same timestamp. The timestamp drives START_DT / END_DT versioning in     *
* kycref.40 and the snapshot rebuild in kycref.50.                         *
\**************************************************************************/

-- Databricks migration: BTEQ post-statement error checks were removed; the selected Databricks wrapper must govern failure handling.
DELETE FROM `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_REFSYS
;


-- Databricks migration: Teradata-specific functions and data types in this statement use Databricks SQL equivalents.
INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_REFSYS
(
       SSQ_ID,
       TMS
)
VALUES
(
       1,
       CURRENT_TIMESTAMP
)
;


/**************************************************************************\
* ENSURE THE RAW FILE IS NOT EMPTY                                         *
* ------------------------------------------------------------------------ *
* An empty REFSYS delivery must never be processed - it would close every  *
* open reference version in kycref.40.                                     *
\**************************************************************************/

-- Databricks migration: replace the BTEQ ACTIVITYCOUNT exit with an assertion that fails an empty delivery.
SELECT ASSERT_TRUE(COUNT(*) > 0, 'AML_REFSYS_RAW delivery is empty')
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_RAW
;

-- Databricks migration: COLLECT STATISTICS INDEX removed because Delta has no indexes and maintains table statistics automatically.


/**************************************************************************\
* BUILD VALID DATE LOOKUP                                                  *
* ------------------------------------------------------------------------ *
* Fixed-width dates are validated against the corporate calendar so that   *
* a bad date never aborts the cast in the downstream INSERT/SELECT.        *
\**************************************************************************/


-- Databricks migration: CREATE VOLATILE TABLE becomes CREATE TEMP TABLE; character-set, primary-index, and commit clauses are removed.
CREATE TEMP TABLE VT_VALID_DT
(
       DT_TXT CHAR(8) COLLATE UTF8_LCASE NOT NULL
)
;

-- Databricks migration: Teradata CAST FORMAT becomes DATE_FORMAT with Java datetime tokens.
-- Databricks migration: Teradata-specific functions and data types in this statement use Databricks SQL equivalents.
INSERT INTO VT_VALID_DT
SELECT DATE_FORMAT(CAL_DT, 'yyyyMMdd')
FROM   `<DB_ENV>DB_REFERENCE`.CALENDAR
UNION
SELECT '99991231'
FROM   (SELECT 1 AS DUMMY) DMY
;

-- Databricks migration: refresh the temporary lookup column statistics after loading it.
ANALYZE TABLE VT_VALID_DT COMPUTE STATISTICS FOR COLUMNS DT_TXT;


/**************************************************************************\
* HOUSEKEEPING OF THE REJECT TABLE                                         *
* ------------------------------------------------------------------------ *
* Rejects are retained for 35 days for the reference data stewards.        *
\**************************************************************************/


-- Databricks migration: BTEQ post-statement error checks were removed; the selected Databricks wrapper must govern failure handling.
DELETE FROM `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_REJ
WHERE  CO_UPD_TMS < CURRENT_TIMESTAMP - INTERVAL '35' DAY
;


/**************************************************************************\
* REJECT UNKNOWN RECORD TYPES                                              *
\**************************************************************************/


-- Databricks migration: Teradata-specific functions and data types in this statement use Databricks SQL equivalents.
INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_REJ
(
       A,
       B,
       C,
       REJ_REASON,
       CO_UPD_TMS
)
SELECT G_T1.A,
       G_T1.B,
       G_T1.C,
       'UNKNOWN RECORD TYPE ' || TRIM (G_T1.A),
       CAST (TTS.TMS AS TIMESTAMP_NTZ)
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_RAW   G_T1
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_REFSYS   TTS
WHERE  G_T1.A NOT IN ('CT', 'CY', 'FX', 'MC', 'SC', 'TT', 'CH', 'PR', 'OC', 'RT')
;


/**************************************************************************\
* REJECT RECORDS WITH AN INVALID ACTION CODE                               *
\**************************************************************************/


-- Databricks migration: Teradata-specific functions and data types in this statement use Databricks SQL equivalents.
INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_REJ
(
       A,
       B,
       C,
       REJ_REASON,
       CO_UPD_TMS
)
SELECT G_T1.A,
       G_T1.B,
       G_T1.C,
       'INVALID ACTION CODE ' || SUBSTR (G_T1.C, 1, 1),
       CAST (TTS.TMS AS TIMESTAMP_NTZ)
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_RAW   G_T1
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_REFSYS   TTS
WHERE  G_T1.A IN ('CT', 'CY', 'FX', 'MC', 'SC', 'TT', 'CH', 'PR', 'OC', 'RT')
AND    SUBSTR (G_T1.C, 1, 1) NOT IN ('I', 'U', 'D', ' ')
;

-- Databricks migration: BTEQ post-statement error checks were removed; the selected Databricks wrapper must govern failure handling.
DELETE FROM `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_RAW
WHERE  A IN ('CT', 'CY', 'FX', 'MC', 'SC', 'TT', 'CH', 'PR', 'OC', 'RT')
AND    SUBSTR (C, 1, 1) NOT IN ('I', 'U', 'D', ' ')
;


/**************************************************************************\
* POPULATE AML_CTRY                                                        *
* ------------------------------------------------------------------------ *
* Record type 'CT' - COUNTRY RISK                                          *
*                                                                          *
* Field                          Src   Pos  Len  Type                      *
* CTRY_2_CD                      B       1    2  k                         *
* CTRY_3_CD                      C       2    3  c                         *
* CTRY_NM                        C       5   50  c                         *
* FATF_STATUS_CD                 C      55    2  c                         *
* HMT_HIGH_RISK_IND              C      57    1  f                         *
* EU_HIGH_RISK_IND               C      58    1  f                         *
* BASEL_AML_SCORE                C      59    5  n5_2                      *
* CPI_SCORE                      C      64    3  si                        *
* OFFSHORE_IND                   C      67    1  f                         *
* REGION_CD                      C      68    3  c                         *
* VALID_FROM_DT                  C      71    8  d                         *
* VALID_TO_DT                    C      79    8  d                         *
* ACTION_CD                      C       1    1  a                         *
\**************************************************************************/


-- Databricks migration: Teradata-specific functions and data types in this statement use Databricks SQL equivalents.
INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_REJ
(
       A,
       B,
       C,
       REJ_REASON,
       CO_UPD_TMS
)
SELECT G_T1.A,
       G_T1.B,
       G_T1.C,
       CASE WHEN TRIM (SUBSTR (G_T1.B, 1, 2)) = ''
            THEN 'INVALID CTRY_2_CD'
            WHEN TRIM (TRANSLATE (SUBSTR (G_T1.C, 59, 5), '0123456789.-', '            ')) <> ''
            THEN 'INVALID BASEL_AML_SCORE'
            WHEN TRIM (TRANSLATE (SUBSTR (G_T1.C, 64, 3), '0123456789.-', '            ')) <> ''
            THEN 'INVALID CPI_SCORE'
            WHEN (SUBSTR (G_T1.C, 71, 8) NOT IN ('00000000', '        ') AND VD_VALID_FROM_DT.DT_TXT IS NULL)
            THEN 'INVALID VALID_FROM_DT'
            WHEN (SUBSTR (G_T1.C, 79, 8) NOT IN ('00000000', '        ') AND VD_VALID_TO_DT.DT_TXT IS NULL)
            THEN 'INVALID VALID_TO_DT'
            ELSE 'INVALID RECORD'
       END,
       CAST (TTS.TMS AS TIMESTAMP_NTZ)
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_RAW   G_T1
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_REFSYS   TTS
       LEFT OUTER JOIN
       VT_VALID_DT   VD_VALID_FROM_DT
          ON  VD_VALID_FROM_DT.DT_TXT = SUBSTR (G_T1.C, 71, 8)
       LEFT OUTER JOIN
       VT_VALID_DT   VD_VALID_TO_DT
          ON  VD_VALID_TO_DT.DT_TXT = SUBSTR (G_T1.C, 79, 8)
WHERE  G_T1.A = 'CT'
AND    (   TRIM (SUBSTR (G_T1.B, 1, 2)) = ''
        OR TRIM (TRANSLATE (SUBSTR (G_T1.C, 59, 5), '0123456789.-', '            ')) <> ''
        OR TRIM (TRANSLATE (SUBSTR (G_T1.C, 64, 3), '0123456789.-', '            ')) <> ''
        OR (SUBSTR (G_T1.C, 71, 8) NOT IN ('00000000', '        ') AND VD_VALID_FROM_DT.DT_TXT IS NULL)
        OR (SUBSTR (G_T1.C, 79, 8) NOT IN ('00000000', '        ') AND VD_VALID_TO_DT.DT_TXT IS NULL)
       )
;

-- Databricks migration: BTEQ post-statement error checks were removed; the selected Databricks wrapper must govern failure handling.
DELETE FROM `<DB_ENV>DB_TRANS_IMPORTS`.AML_CTRY
;


-- Databricks migration: Teradata-specific functions and data types in this statement use Databricks SQL equivalents.
INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_CTRY
(
       CTRY_2_CD,
       CTRY_3_CD,
       CTRY_NM,
       FATF_STATUS_CD,
       HMT_HIGH_RISK_IND,
       EU_HIGH_RISK_IND,
       BASEL_AML_SCORE,
       CPI_SCORE,
       OFFSHORE_IND,
       REGION_CD,
       VALID_FROM_DT,
       VALID_TO_DT,
       ACTION_CD
)
SELECT TRIM (SUBSTR (G_T1.B, 1, 2)),
       NULLIF (TRIM (SUBSTR (G_T1.C, 2, 3)), ''),
       NULLIF (TRIM (SUBSTR (G_T1.C, 5, 50)), ''),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 55, 2)), ''), 'NA'),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 57, 1)), ''), 'N'),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 58, 1)), ''), 'N'),
       CAST (NULLIF (TRIM (SUBSTR (G_T1.C, 59, 5)), '') AS DECIMAL(5,2)),
       CAST (NULLIF (TRIM (SUBSTR (G_T1.C, 64, 3)), '') AS SMALLINT),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 67, 1)), ''), 'N'),
       NULLIF (TRIM (SUBSTR (G_T1.C, 68, 3)), ''),
       CASE WHEN SUBSTR (G_T1.C, 71, 8) IN ('00000000', '        ') THEN NULL
            ELSE TO_DATE(SUBSTR(G_T1.C, 71, 8), 'yyyyMMdd')
       END,
       CASE WHEN SUBSTR (G_T1.C, 79, 8) IN ('00000000', '        ') THEN NULL
            ELSE TO_DATE(SUBSTR(G_T1.C, 79, 8), 'yyyyMMdd')
       END,
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 1, 1)), ''), 'I')
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_RAW   G_T1
       LEFT OUTER JOIN
       VT_VALID_DT   VD_VALID_FROM_DT
          ON  VD_VALID_FROM_DT.DT_TXT = SUBSTR (G_T1.C, 71, 8)
       LEFT OUTER JOIN
       VT_VALID_DT   VD_VALID_TO_DT
          ON  VD_VALID_TO_DT.DT_TXT = SUBSTR (G_T1.C, 79, 8)
WHERE  G_T1.A = 'CT'
AND    NOT (   TRIM (SUBSTR (G_T1.B, 1, 2)) = ''
            OR TRIM (TRANSLATE (SUBSTR (G_T1.C, 59, 5), '0123456789.-', '            ')) <> ''
            OR TRIM (TRANSLATE (SUBSTR (G_T1.C, 64, 3), '0123456789.-', '            ')) <> ''
            OR (SUBSTR (G_T1.C, 71, 8) NOT IN ('00000000', '        ') AND VD_VALID_FROM_DT.DT_TXT IS NULL)
            OR (SUBSTR (G_T1.C, 79, 8) NOT IN ('00000000', '        ') AND VD_VALID_TO_DT.DT_TXT IS NULL)
           )
QUALIFY SUM (1) OVER (PARTITION BY  TRIM (SUBSTR (G_T1.B, 1, 2))
                          ORDER BY  G_T1.C DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;

-- Databricks migration: COLLECT STATISTICS INDEX removed because Delta has no indexes and maintains table statistics automatically.


/**************************************************************************\
* POPULATE AML_CCY                                                         *
* ------------------------------------------------------------------------ *
* Record type 'CY' - CURRENCY                                              *
*                                                                          *
* Field                          Src   Pos  Len  Type                      *
* CCY_CD                         B       1    3  k                         *
* CCY_NM                         C       2   30  c                         *
* MINOR_UNIT_CNT                 C      32    1  bt                        *
* CCY_NUM_CD                     C      33    3  c                         *
* ACTIVE_IND                     C      36    1  f                         *
* ACTION_CD                      C       1    1  a                         *
\**************************************************************************/


-- Databricks migration: Teradata-specific functions and data types in this statement use Databricks SQL equivalents.
INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_REJ
(
       A,
       B,
       C,
       REJ_REASON,
       CO_UPD_TMS
)
SELECT G_T1.A,
       G_T1.B,
       G_T1.C,
       CASE WHEN TRIM (SUBSTR (G_T1.B, 1, 3)) = ''
            THEN 'INVALID CCY_CD'
            WHEN TRIM (TRANSLATE (SUBSTR (G_T1.C, 32, 1), '0123456789.-', '            ')) <> ''
            THEN 'INVALID MINOR_UNIT_CNT'
            ELSE 'INVALID RECORD'
       END,
       CAST (TTS.TMS AS TIMESTAMP_NTZ)
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_RAW   G_T1
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_REFSYS   TTS
WHERE  G_T1.A = 'CY'
AND    (   TRIM (SUBSTR (G_T1.B, 1, 3)) = ''
        OR TRIM (TRANSLATE (SUBSTR (G_T1.C, 32, 1), '0123456789.-', '            ')) <> ''
       )
;

-- Databricks migration: BTEQ post-statement error checks were removed; the selected Databricks wrapper must govern failure handling.
DELETE FROM `<DB_ENV>DB_TRANS_IMPORTS`.AML_CCY
;


-- Databricks migration: Teradata-specific functions and data types in this statement use Databricks SQL equivalents.
INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_CCY
(
       CCY_CD,
       CCY_NM,
       MINOR_UNIT_CNT,
       CCY_NUM_CD,
       ACTIVE_IND,
       ACTION_CD
)
SELECT TRIM (SUBSTR (G_T1.B, 1, 3)),
       NULLIF (TRIM (SUBSTR (G_T1.C, 2, 30)), ''),
       CAST (NULLIF (TRIM (SUBSTR (G_T1.C, 32, 1)), '') AS TINYINT),
       NULLIF (TRIM (SUBSTR (G_T1.C, 33, 3)), ''),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 36, 1)), ''), 'N'),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 1, 1)), ''), 'I')
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_RAW   G_T1
WHERE  G_T1.A = 'CY'
AND    NOT (   TRIM (SUBSTR (G_T1.B, 1, 3)) = ''
            OR TRIM (TRANSLATE (SUBSTR (G_T1.C, 32, 1), '0123456789.-', '            ')) <> ''
           )
QUALIFY SUM (1) OVER (PARTITION BY  TRIM (SUBSTR (G_T1.B, 1, 3))
                          ORDER BY  G_T1.C DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;

-- Databricks migration: COLLECT STATISTICS INDEX removed because Delta has no indexes and maintains table statistics automatically.


/**************************************************************************\
* POPULATE AML_FXRT                                                        *
* ------------------------------------------------------------------------ *
* Record type 'FX' - FX RATE TO GBP                                        *
*                                                                          *
* Field                          Src   Pos  Len  Type                      *
* CCY_CD                         B       1    3  k                         *
* RATE_DT                        B       4    8  kd                        *
* RATE_TYP_CD                    C       2    2  c                         *
* GBP_RATE                       C       4   16  n18_8                     *
* ACTION_CD                      C       1    1  a                         *
\**************************************************************************/


-- Databricks migration: Teradata-specific functions and data types in this statement use Databricks SQL equivalents.
INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_REJ
(
       A,
       B,
       C,
       REJ_REASON,
       CO_UPD_TMS
)
SELECT G_T1.A,
       G_T1.B,
       G_T1.C,
       CASE WHEN TRIM (SUBSTR (G_T1.B, 1, 3)) = ''
            THEN 'INVALID CCY_CD'
            WHEN (SUBSTR (G_T1.B, 4, 8) NOT IN ('00000000', '        ') AND VD_RATE_DT.DT_TXT IS NULL)
            THEN 'INVALID RATE_DT'
            WHEN TRIM (TRANSLATE (SUBSTR (G_T1.C, 4, 16), '0123456789.-', '            ')) <> ''
            THEN 'INVALID GBP_RATE'
            ELSE 'INVALID RECORD'
       END,
       CAST (TTS.TMS AS TIMESTAMP_NTZ)
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_RAW   G_T1
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_REFSYS   TTS
       LEFT OUTER JOIN
       VT_VALID_DT   VD_RATE_DT
          ON  VD_RATE_DT.DT_TXT = SUBSTR (G_T1.B, 4, 8)
WHERE  G_T1.A = 'FX'
AND    (   TRIM (SUBSTR (G_T1.B, 1, 3)) = ''
        OR (SUBSTR (G_T1.B, 4, 8) NOT IN ('00000000', '        ') AND VD_RATE_DT.DT_TXT IS NULL)
        OR TRIM (TRANSLATE (SUBSTR (G_T1.C, 4, 16), '0123456789.-', '            ')) <> ''
       )
;

-- Databricks migration: BTEQ post-statement error checks were removed; the selected Databricks wrapper must govern failure handling.
DELETE FROM `<DB_ENV>DB_TRANS_IMPORTS`.AML_FXRT
;


-- Databricks migration: Teradata-specific functions and data types in this statement use Databricks SQL equivalents.
INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_FXRT
(
       CCY_CD,
       RATE_DT,
       RATE_TYP_CD,
       GBP_RATE,
       ACTION_CD
)
SELECT TRIM (SUBSTR (G_T1.B, 1, 3)),
       CASE WHEN SUBSTR (G_T1.B, 4, 8) IN ('00000000', '        ') THEN NULL
            ELSE TO_DATE(SUBSTR(G_T1.B, 4, 8), 'yyyyMMdd')
       END,
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 2, 2)), ''), 'SP'),
       CAST (NULLIF (TRIM (SUBSTR (G_T1.C, 4, 16)), '') AS DECIMAL(18,8)),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 1, 1)), ''), 'I')
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_RAW   G_T1
       LEFT OUTER JOIN
       VT_VALID_DT   VD_RATE_DT
          ON  VD_RATE_DT.DT_TXT = SUBSTR (G_T1.B, 4, 8)
WHERE  G_T1.A = 'FX'
AND    NOT (   TRIM (SUBSTR (G_T1.B, 1, 3)) = ''
            OR (SUBSTR (G_T1.B, 4, 8) NOT IN ('00000000', '        ') AND VD_RATE_DT.DT_TXT IS NULL)
            OR TRIM (TRANSLATE (SUBSTR (G_T1.C, 4, 16), '0123456789.-', '            ')) <> ''
           )
QUALIFY SUM (1) OVER (PARTITION BY  SUBSTR (G_T1.B, 1, 3), SUBSTR (G_T1.B, 4, 8), SUBSTR (G_T1.C, 2, 2)
                          ORDER BY  G_T1.C DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;

-- Databricks migration: COLLECT STATISTICS INDEX removed because Delta has no indexes and maintains table statistics automatically.


/**************************************************************************\
* POPULATE AML_MCC                                                         *
* ------------------------------------------------------------------------ *
* Record type 'MC' - MERCHANT CATEGORY CODE                                *
*                                                                          *
* Field                          Src   Pos  Len  Type                      *
* MCC_CD                         B       1    4  k                         *
* MCC_DESC                       C       2   50  c                         *
* MCC_RISK_CD                    C      52    1  c                         *
* CASH_LIKE_IND                  C      53    1  f                         *
* GAMBLING_IND                   C      54    1  f                         *
* CRYPTO_IND                     C      55    1  f                         *
* ACTION_CD                      C       1    1  a                         *
\**************************************************************************/


-- Databricks migration: Teradata-specific functions and data types in this statement use Databricks SQL equivalents.
INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_REJ
(
       A,
       B,
       C,
       REJ_REASON,
       CO_UPD_TMS
)
SELECT G_T1.A,
       G_T1.B,
       G_T1.C,
       CASE WHEN TRIM (SUBSTR (G_T1.B, 1, 4)) = ''
            THEN 'INVALID MCC_CD'
            ELSE 'INVALID RECORD'
       END,
       CAST (TTS.TMS AS TIMESTAMP_NTZ)
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_RAW   G_T1
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_REFSYS   TTS
WHERE  G_T1.A = 'MC'
AND    (   TRIM (SUBSTR (G_T1.B, 1, 4)) = ''
       )
;

-- Databricks migration: BTEQ post-statement error checks were removed; the selected Databricks wrapper must govern failure handling.
DELETE FROM `<DB_ENV>DB_TRANS_IMPORTS`.AML_MCC
;


-- Databricks migration: Teradata-specific functions and data types in this statement use Databricks SQL equivalents.
INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_MCC
(
       MCC_CD,
       MCC_DESC,
       MCC_RISK_CD,
       CASH_LIKE_IND,
       GAMBLING_IND,
       CRYPTO_IND,
       ACTION_CD
)
SELECT TRIM (SUBSTR (G_T1.B, 1, 4)),
       NULLIF (TRIM (SUBSTR (G_T1.C, 2, 50)), ''),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 52, 1)), ''), 'L'),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 53, 1)), ''), 'N'),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 54, 1)), ''), 'N'),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 55, 1)), ''), 'N'),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 1, 1)), ''), 'I')
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_RAW   G_T1
WHERE  G_T1.A = 'MC'
AND    NOT (   TRIM (SUBSTR (G_T1.B, 1, 4)) = ''
           )
QUALIFY SUM (1) OVER (PARTITION BY  TRIM (SUBSTR (G_T1.B, 1, 4))
                          ORDER BY  G_T1.C DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;

-- Databricks migration: COLLECT STATISTICS INDEX removed because Delta has no indexes and maintains table statistics automatically.


/**************************************************************************\
* POPULATE AML_SORT                                                        *
* ------------------------------------------------------------------------ *
* Record type 'SC' - UK SORT CODE DIRECTORY                                *
*                                                                          *
* Field                          Src   Pos  Len  Type                      *
* SORT_CD                        B       1    6  k                         *
* BANK_NM                        C       2   40  c                         *
* BRANCH_NM                      C      42   40  c                         *
* BIC_CD                         C      82   11  c                         *
* FPS_IND                        C      93    1  f                         *
* CHAPS_IND                      C      94    1  f                         *
* BACS_IND                       C      95    1  f                         *
* CLOSED_IND                     C      96    1  f                         *
* POSTCODE                       C      97    8  c                         *
* ACTION_CD                      C       1    1  a                         *
\**************************************************************************/


-- Databricks migration: Teradata-specific functions and data types in this statement use Databricks SQL equivalents.
INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_REJ
(
       A,
       B,
       C,
       REJ_REASON,
       CO_UPD_TMS
)
SELECT G_T1.A,
       G_T1.B,
       G_T1.C,
       CASE WHEN TRIM (SUBSTR (G_T1.B, 1, 6)) = ''
            THEN 'INVALID SORT_CD'
            ELSE 'INVALID RECORD'
       END,
       CAST (TTS.TMS AS TIMESTAMP_NTZ)
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_RAW   G_T1
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_REFSYS   TTS
WHERE  G_T1.A = 'SC'
AND    (   TRIM (SUBSTR (G_T1.B, 1, 6)) = ''
       )
;

-- Databricks migration: BTEQ post-statement error checks were removed; the selected Databricks wrapper must govern failure handling.
DELETE FROM `<DB_ENV>DB_TRANS_IMPORTS`.AML_SORT
;


-- Databricks migration: Teradata-specific functions and data types in this statement use Databricks SQL equivalents.
INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_SORT
(
       SORT_CD,
       BANK_NM,
       BRANCH_NM,
       BIC_CD,
       FPS_IND,
       CHAPS_IND,
       BACS_IND,
       CLOSED_IND,
       POSTCODE,
       ACTION_CD
)
SELECT TRIM (SUBSTR (G_T1.B, 1, 6)),
       NULLIF (TRIM (SUBSTR (G_T1.C, 2, 40)), ''),
       NULLIF (TRIM (SUBSTR (G_T1.C, 42, 40)), ''),
       NULLIF (TRIM (SUBSTR (G_T1.C, 82, 11)), ''),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 93, 1)), ''), 'N'),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 94, 1)), ''), 'N'),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 95, 1)), ''), 'N'),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 96, 1)), ''), 'N'),
       NULLIF (TRIM (SUBSTR (G_T1.C, 97, 8)), ''),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 1, 1)), ''), 'I')
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_RAW   G_T1
WHERE  G_T1.A = 'SC'
AND    NOT (   TRIM (SUBSTR (G_T1.B, 1, 6)) = ''
           )
QUALIFY SUM (1) OVER (PARTITION BY  TRIM (SUBSTR (G_T1.B, 1, 6))
                          ORDER BY  G_T1.C DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;

-- Databricks migration: COLLECT STATISTICS INDEX removed because Delta has no indexes and maintains table statistics automatically.


/**************************************************************************\
* POPULATE AML_TXTP                                                        *
* ------------------------------------------------------------------------ *
* Record type 'TT' - TRANSACTION TYPE                                      *
*                                                                          *
* Field                          Src   Pos  Len  Type                      *
* TXN_TYP_CD                     B       1    4  k                         *
* TXN_TYP_DESC                   C       2   50  c                         *
* PAY_SCHEME_CD                  C      52    4  c                         *
* DIRECTION_CD                   C      56    1  c                         *
* CASH_IND                       C      57    1  f                         *
* XBORDER_IND                    C      58    1  f                         *
* ACTION_CD                      C       1    1  a                         *
\**************************************************************************/


-- Databricks migration: Teradata-specific functions and data types in this statement use Databricks SQL equivalents.
INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_REJ
(
       A,
       B,
       C,
       REJ_REASON,
       CO_UPD_TMS
)
SELECT G_T1.A,
       G_T1.B,
       G_T1.C,
       CASE WHEN TRIM (SUBSTR (G_T1.B, 1, 4)) = ''
            THEN 'INVALID TXN_TYP_CD'
            ELSE 'INVALID RECORD'
       END,
       CAST (TTS.TMS AS TIMESTAMP_NTZ)
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_RAW   G_T1
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_REFSYS   TTS
WHERE  G_T1.A = 'TT'
AND    (   TRIM (SUBSTR (G_T1.B, 1, 4)) = ''
       )
;

-- Databricks migration: BTEQ post-statement error checks were removed; the selected Databricks wrapper must govern failure handling.
DELETE FROM `<DB_ENV>DB_TRANS_IMPORTS`.AML_TXTP
;


-- Databricks migration: Teradata-specific functions and data types in this statement use Databricks SQL equivalents.
INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_TXTP
(
       TXN_TYP_CD,
       TXN_TYP_DESC,
       PAY_SCHEME_CD,
       DIRECTION_CD,
       CASH_IND,
       XBORDER_IND,
       ACTION_CD
)
SELECT TRIM (SUBSTR (G_T1.B, 1, 4)),
       NULLIF (TRIM (SUBSTR (G_T1.C, 2, 50)), ''),
       NULLIF (TRIM (SUBSTR (G_T1.C, 52, 4)), ''),
       NULLIF (TRIM (SUBSTR (G_T1.C, 56, 1)), ''),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 57, 1)), ''), 'N'),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 58, 1)), ''), 'N'),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 1, 1)), ''), 'I')
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_RAW   G_T1
WHERE  G_T1.A = 'TT'
AND    NOT (   TRIM (SUBSTR (G_T1.B, 1, 4)) = ''
           )
QUALIFY SUM (1) OVER (PARTITION BY  TRIM (SUBSTR (G_T1.B, 1, 4))
                          ORDER BY  G_T1.C DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;

-- Databricks migration: COLLECT STATISTICS INDEX removed because Delta has no indexes and maintains table statistics automatically.


/**************************************************************************\
* POPULATE AML_CHNL                                                        *
* ------------------------------------------------------------------------ *
* Record type 'CH' - CHANNEL                                               *
*                                                                          *
* Field                          Src   Pos  Len  Type                      *
* CHNL_CD                        B       1    3  k                         *
* CHNL_DESC                      C       2   40  c                         *
* DIGITAL_IND                    C      42    1  f                         *
* ACTION_CD                      C       1    1  a                         *
\**************************************************************************/


-- Databricks migration: Teradata-specific functions and data types in this statement use Databricks SQL equivalents.
INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_REJ
(
       A,
       B,
       C,
       REJ_REASON,
       CO_UPD_TMS
)
SELECT G_T1.A,
       G_T1.B,
       G_T1.C,
       CASE WHEN TRIM (SUBSTR (G_T1.B, 1, 3)) = ''
            THEN 'INVALID CHNL_CD'
            ELSE 'INVALID RECORD'
       END,
       CAST (TTS.TMS AS TIMESTAMP_NTZ)
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_RAW   G_T1
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_REFSYS   TTS
WHERE  G_T1.A = 'CH'
AND    (   TRIM (SUBSTR (G_T1.B, 1, 3)) = ''
       )
;

-- Databricks migration: BTEQ post-statement error checks were removed; the selected Databricks wrapper must govern failure handling.
DELETE FROM `<DB_ENV>DB_TRANS_IMPORTS`.AML_CHNL
;


-- Databricks migration: Teradata-specific functions and data types in this statement use Databricks SQL equivalents.
INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_CHNL
(
       CHNL_CD,
       CHNL_DESC,
       DIGITAL_IND,
       ACTION_CD
)
SELECT TRIM (SUBSTR (G_T1.B, 1, 3)),
       NULLIF (TRIM (SUBSTR (G_T1.C, 2, 40)), ''),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 42, 1)), ''), 'N'),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 1, 1)), ''), 'I')
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_RAW   G_T1
WHERE  G_T1.A = 'CH'
AND    NOT (   TRIM (SUBSTR (G_T1.B, 1, 3)) = ''
           )
QUALIFY SUM (1) OVER (PARTITION BY  TRIM (SUBSTR (G_T1.B, 1, 3))
                          ORDER BY  G_T1.C DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;

-- Databricks migration: COLLECT STATISTICS INDEX removed because Delta has no indexes and maintains table statistics automatically.


/**************************************************************************\
* POPULATE AML_PRDT                                                        *
* ------------------------------------------------------------------------ *
* Record type 'PR' - PRODUCT                                               *
*                                                                          *
* Field                          Src   Pos  Len  Type                      *
* PRDT_CD                        B       1    6  k                         *
* PRDT_DESC                      C       2   50  c                         *
* PRDT_FAMILY_CD                 C      52    4  c                         *
* SEGMENT_CD                     C      56    3  c                         *
* PRDT_RISK_CD                   C      59    1  c                         *
* ACTION_CD                      C       1    1  a                         *
\**************************************************************************/


-- Databricks migration: Teradata-specific functions and data types in this statement use Databricks SQL equivalents.
INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_REJ
(
       A,
       B,
       C,
       REJ_REASON,
       CO_UPD_TMS
)
SELECT G_T1.A,
       G_T1.B,
       G_T1.C,
       CASE WHEN TRIM (SUBSTR (G_T1.B, 1, 6)) = ''
            THEN 'INVALID PRDT_CD'
            ELSE 'INVALID RECORD'
       END,
       CAST (TTS.TMS AS TIMESTAMP_NTZ)
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_RAW   G_T1
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_REFSYS   TTS
WHERE  G_T1.A = 'PR'
AND    (   TRIM (SUBSTR (G_T1.B, 1, 6)) = ''
       )
;

-- Databricks migration: BTEQ post-statement error checks were removed; the selected Databricks wrapper must govern failure handling.
DELETE FROM `<DB_ENV>DB_TRANS_IMPORTS`.AML_PRDT
;


-- Databricks migration: Teradata-specific functions and data types in this statement use Databricks SQL equivalents.
INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_PRDT
(
       PRDT_CD,
       PRDT_DESC,
       PRDT_FAMILY_CD,
       SEGMENT_CD,
       PRDT_RISK_CD,
       ACTION_CD
)
SELECT TRIM (SUBSTR (G_T1.B, 1, 6)),
       NULLIF (TRIM (SUBSTR (G_T1.C, 2, 50)), ''),
       NULLIF (TRIM (SUBSTR (G_T1.C, 52, 4)), ''),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 56, 3)), ''), 'RET'),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 59, 1)), ''), 'L'),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 1, 1)), ''), 'I')
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_RAW   G_T1
WHERE  G_T1.A = 'PR'
AND    NOT (   TRIM (SUBSTR (G_T1.B, 1, 6)) = ''
           )
QUALIFY SUM (1) OVER (PARTITION BY  TRIM (SUBSTR (G_T1.B, 1, 6))
                          ORDER BY  G_T1.C DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;

-- Databricks migration: COLLECT STATISTICS INDEX removed because Delta has no indexes and maintains table statistics automatically.


/**************************************************************************\
* POPULATE AML_OCCP                                                        *
* ------------------------------------------------------------------------ *
* Record type 'OC' - OCCUPATION / INDUSTRY (SIC 2007)                      *
*                                                                          *
* Field                          Src   Pos  Len  Type                      *
* SIC_CD                         B       1    5  k                         *
* SIC_DESC                       C       2   60  c                         *
* SIC_RISK_CD                    C      62    1  c                         *
* CASH_INTENSIVE_IND             C      63    1  f                         *
* ACTION_CD                      C       1    1  a                         *
\**************************************************************************/


-- Databricks migration: Teradata-specific functions and data types in this statement use Databricks SQL equivalents.
INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_REJ
(
       A,
       B,
       C,
       REJ_REASON,
       CO_UPD_TMS
)
SELECT G_T1.A,
       G_T1.B,
       G_T1.C,
       CASE WHEN TRIM (SUBSTR (G_T1.B, 1, 5)) = ''
            THEN 'INVALID SIC_CD'
            ELSE 'INVALID RECORD'
       END,
       CAST (TTS.TMS AS TIMESTAMP_NTZ)
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_RAW   G_T1
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_REFSYS   TTS
WHERE  G_T1.A = 'OC'
AND    (   TRIM (SUBSTR (G_T1.B, 1, 5)) = ''
       )
;

-- Databricks migration: BTEQ post-statement error checks were removed; the selected Databricks wrapper must govern failure handling.
DELETE FROM `<DB_ENV>DB_TRANS_IMPORTS`.AML_OCCP
;


-- Databricks migration: Teradata-specific functions and data types in this statement use Databricks SQL equivalents.
INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_OCCP
(
       SIC_CD,
       SIC_DESC,
       SIC_RISK_CD,
       CASH_INTENSIVE_IND,
       ACTION_CD
)
SELECT TRIM (SUBSTR (G_T1.B, 1, 5)),
       NULLIF (TRIM (SUBSTR (G_T1.C, 2, 60)), ''),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 62, 1)), ''), 'L'),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 63, 1)), ''), 'N'),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 1, 1)), ''), 'I')
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_RAW   G_T1
WHERE  G_T1.A = 'OC'
AND    NOT (   TRIM (SUBSTR (G_T1.B, 1, 5)) = ''
           )
QUALIFY SUM (1) OVER (PARTITION BY  TRIM (SUBSTR (G_T1.B, 1, 5))
                          ORDER BY  G_T1.C DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;

-- Databricks migration: COLLECT STATISTICS INDEX removed because Delta has no indexes and maintains table statistics automatically.


/**************************************************************************\
* POPULATE AML_RULE                                                        *
* ------------------------------------------------------------------------ *
* Record type 'RT' - TRANSACTION MONITORING RULE PARAMETER                 *
*                                                                          *
* Field                          Src   Pos  Len  Type                      *
* RULE_CD                        B       1    8  k                         *
* SEGMENT_CD                     B       9    3  k                         *
* AMT_THRESHOLD                  C       2   14  n18_2                     *
* CNT_THRESHOLD                  C      16    5  i                         *
* LOOKBACK_DAYS                  C      21    3  si                        *
* PCT_THRESHOLD                  C      24    7  n7_2                      *
* SCORE_WEIGHT                   C      31    3  si                        *
* ACTIVE_IND                     C      34    1  f                         *
* RULE_DESC                      C      35   60  c                         *
* ACTION_CD                      C       1    1  a                         *
\**************************************************************************/


-- Databricks migration: Teradata-specific functions and data types in this statement use Databricks SQL equivalents.
INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_REJ
(
       A,
       B,
       C,
       REJ_REASON,
       CO_UPD_TMS
)
SELECT G_T1.A,
       G_T1.B,
       G_T1.C,
       CASE WHEN TRIM (SUBSTR (G_T1.B, 1, 8)) = ''
            THEN 'INVALID RULE_CD'
            WHEN TRIM (SUBSTR (G_T1.B, 9, 3)) = ''
            THEN 'INVALID SEGMENT_CD'
            WHEN TRIM (TRANSLATE (SUBSTR (G_T1.C, 2, 14), '0123456789.-', '            ')) <> ''
            THEN 'INVALID AMT_THRESHOLD'
            WHEN TRIM (TRANSLATE (SUBSTR (G_T1.C, 16, 5), '0123456789.-', '            ')) <> ''
            THEN 'INVALID CNT_THRESHOLD'
            WHEN TRIM (TRANSLATE (SUBSTR (G_T1.C, 21, 3), '0123456789.-', '            ')) <> ''
            THEN 'INVALID LOOKBACK_DAYS'
            WHEN TRIM (TRANSLATE (SUBSTR (G_T1.C, 24, 7), '0123456789.-', '            ')) <> ''
            THEN 'INVALID PCT_THRESHOLD'
            WHEN TRIM (TRANSLATE (SUBSTR (G_T1.C, 31, 3), '0123456789.-', '            ')) <> ''
            THEN 'INVALID SCORE_WEIGHT'
            ELSE 'INVALID RECORD'
       END,
       CAST (TTS.TMS AS TIMESTAMP_NTZ)
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_RAW   G_T1
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_REFSYS   TTS
WHERE  G_T1.A = 'RT'
AND    (   TRIM (SUBSTR (G_T1.B, 1, 8)) = ''
        OR TRIM (SUBSTR (G_T1.B, 9, 3)) = ''
        OR TRIM (TRANSLATE (SUBSTR (G_T1.C, 2, 14), '0123456789.-', '            ')) <> ''
        OR TRIM (TRANSLATE (SUBSTR (G_T1.C, 16, 5), '0123456789.-', '            ')) <> ''
        OR TRIM (TRANSLATE (SUBSTR (G_T1.C, 21, 3), '0123456789.-', '            ')) <> ''
        OR TRIM (TRANSLATE (SUBSTR (G_T1.C, 24, 7), '0123456789.-', '            ')) <> ''
        OR TRIM (TRANSLATE (SUBSTR (G_T1.C, 31, 3), '0123456789.-', '            ')) <> ''
       )
;

-- Databricks migration: BTEQ post-statement error checks were removed; the selected Databricks wrapper must govern failure handling.
DELETE FROM `<DB_ENV>DB_TRANS_IMPORTS`.AML_RULE
;


-- Databricks migration: Teradata-specific functions and data types in this statement use Databricks SQL equivalents.
INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_RULE
(
       RULE_CD,
       SEGMENT_CD,
       AMT_THRESHOLD,
       CNT_THRESHOLD,
       LOOKBACK_DAYS,
       PCT_THRESHOLD,
       SCORE_WEIGHT,
       ACTIVE_IND,
       RULE_DESC,
       ACTION_CD
)
SELECT TRIM (SUBSTR (G_T1.B, 1, 8)),
       TRIM (SUBSTR (G_T1.B, 9, 3)),
       CAST (NULLIF (TRIM (SUBSTR (G_T1.C, 2, 14)), '') AS DECIMAL(18,2)),
       CAST (NULLIF (TRIM (SUBSTR (G_T1.C, 16, 5)), '') AS INTEGER),
       CAST (NULLIF (TRIM (SUBSTR (G_T1.C, 21, 3)), '') AS SMALLINT),
       CAST (NULLIF (TRIM (SUBSTR (G_T1.C, 24, 7)), '') AS DECIMAL(7,2)),
       CAST (NULLIF (TRIM (SUBSTR (G_T1.C, 31, 3)), '') AS SMALLINT),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 34, 1)), ''), 'N'),
       NULLIF (TRIM (SUBSTR (G_T1.C, 35, 60)), ''),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 1, 1)), ''), 'I')
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_RAW   G_T1
WHERE  G_T1.A = 'RT'
AND    NOT (   TRIM (SUBSTR (G_T1.B, 1, 8)) = ''
            OR TRIM (SUBSTR (G_T1.B, 9, 3)) = ''
            OR TRIM (TRANSLATE (SUBSTR (G_T1.C, 2, 14), '0123456789.-', '            ')) <> ''
            OR TRIM (TRANSLATE (SUBSTR (G_T1.C, 16, 5), '0123456789.-', '            ')) <> ''
            OR TRIM (TRANSLATE (SUBSTR (G_T1.C, 21, 3), '0123456789.-', '            ')) <> ''
            OR TRIM (TRANSLATE (SUBSTR (G_T1.C, 24, 7), '0123456789.-', '            ')) <> ''
            OR TRIM (TRANSLATE (SUBSTR (G_T1.C, 31, 3), '0123456789.-', '            ')) <> ''
           )
QUALIFY SUM (1) OVER (PARTITION BY  TRIM (SUBSTR (G_T1.B, 1, 8)), TRIM (SUBSTR (G_T1.B, 9, 3))
                          ORDER BY  G_T1.C DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;

-- Databricks migration: COLLECT STATISTICS INDEX removed because Delta has no indexes and maintains table statistics automatically.


/**************************************************************************\
* STANDARDISE FATF STATUS CODES                                            *
* ------------------------------------------------------------------------ *
* Older REFSYS releases sent 'B ' / 'G ' / 'X ' - map to BL / GL / NA.     *
\**************************************************************************/


UPDATE `<DB_ENV>DB_TRANS_IMPORTS`.AML_CTRY
SET    FATF_STATUS_CD = CASE FATF_STATUS_CD
                             WHEN 'B'  THEN 'BL'
                             WHEN 'G'  THEN 'GL'
                             ELSE 'NA'
                        END
WHERE  FATF_STATUS_CD NOT IN ('BL', 'GL', 'NA')
;


/**************************************************************************\
* ALIGN PRODUCT SEGMENTS                                                   *
* ------------------------------------------------------------------------ *
* Only RET / BUS / CIB / WLT are valid customer segments.                  *
\**************************************************************************/


UPDATE `<DB_ENV>DB_TRANS_IMPORTS`.AML_PRDT
SET    SEGMENT_CD = CASE WHEN PRDT_FAMILY_CD = 'BUSI' THEN 'BUS'
                         ELSE 'RET'
                    END
WHERE  SEGMENT_CD NOT IN ('RET', 'BUS', 'CIB', 'WLT')
;

UPDATE `<DB_ENV>DB_TRANS_IMPORTS`.AML_RULE
SET    SEGMENT_CD = 'ALL'
WHERE  SEGMENT_CD = ''
;


/**************************************************************************\
* DROP FX RATES THAT ARE NOT POSITIVE                                      *
* ------------------------------------------------------------------------ *
* A zero rate would divide by zero in dailytxn.06 (GBP conversion).        *
\**************************************************************************/


-- Databricks migration: Teradata-specific functions and data types in this statement use Databricks SQL equivalents.
INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_REFSYS_REJ
(
       A,
       B,
       C,
       REJ_REASON,
       CO_UPD_TMS
)
SELECT 'FX',
       FXR.CCY_CD || DATE_FORMAT(FXR.RATE_DT, 'yyyyMMdd'),
       FXR.ACTION_CD || FXR.RATE_TYP_CD || COALESCE (CAST (FXR.GBP_RATE AS VARCHAR(30)), '<null>'),
       'NON POSITIVE FX RATE',
       CAST (TTS.TMS AS TIMESTAMP_NTZ)
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_FXRT   FXR
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_REFSYS   TTS
WHERE  FXR.ACTION_CD <> 'D'
AND    COALESCE (FXR.GBP_RATE, 0) <= 0
;

-- Databricks migration: BTEQ post-statement error checks were removed; the selected Databricks wrapper must govern failure handling.
DELETE FROM `<DB_ENV>DB_TRANS_IMPORTS`.AML_FXRT
WHERE  COALESCE (GBP_RATE, 0) <= 0
AND    ACTION_CD <> 'D'
;


/**************************************************************************\
* COLLECT STATISTICS ON THE REJECT TABLE                                   *
\**************************************************************************/

-- Databricks migration: COLLECT STATISTICS INDEX removed because Delta has no indexes and maintains table statistics automatically.


/**************************************************************************\
* END OF SCRIPT                                                            *
\**************************************************************************/

-- Databricks migration: the successful BTEQ .QUIT command was removed.
