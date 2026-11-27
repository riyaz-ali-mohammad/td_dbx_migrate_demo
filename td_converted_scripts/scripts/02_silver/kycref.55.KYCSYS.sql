-- TODO: manual review required — BTEQ script → notebook / stored procedure / Workflows DAG (choose wrapper)
-- TODO: manual review required — BTEQ .IF ERRORCODE / .QUIT → SIGNAL or Workflows branch
-- Converted as a Databricks SQL script; statement failures are expected to abort the invoking job.


/**************************************************************************\
* TAKE A TIMESTAMP SNAPSHOT                                                *
* ------------------------------------------------------------------------ *
* All party and account changes of the current KYCSYS delivery receive the *
* same timestamp (history UPD_TMS and CO_UPD_TMS).                         *
\**************************************************************************/

DELETE FROM `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS
;


INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS
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
* BUILD VALID DATE LOOKUP                                                  *
* ------------------------------------------------------------------------ *
* Fixed-width dates are validated against the corporate calendar so that   *
* a bad date never aborts the cast in the downstream INSERT/SELECT.        *
\**************************************************************************/


-- Databricks conversion: session-scoped table replaces Teradata VOLATILE table; PI and ON COMMIT clauses are removed.
CREATE TEMP TABLE VT_VALID_DT
(
       DT_TXT CHAR(8) COLLATE UTF8_LCASE NOT NULL
);

-- Databricks conversion: DATE_FORMAT replaces the Teradata FORMAT cast.
INSERT INTO VT_VALID_DT
SELECT DATE_FORMAT(CAL_DT, 'yyyyMMdd')
FROM   `<DB_ENV>DB_REFERENCE`.CALENDAR
UNION
SELECT '99991231'
FROM   (SELECT 1 AS DUMMY) DMY
;

-- Databricks conversion: refresh column statistics after the load.
ANALYZE TABLE VT_VALID_DT COMPUTE STATISTICS FOR COLUMNS DT_TXT;


/**************************************************************************\
* HOUSEKEEPING OF THE REJECT TABLE                                         *
\**************************************************************************/


DELETE FROM `<DB_ENV>DB_TRANS_IMPORTS`.KYC_KYCSYS_REJ
WHERE  CO_UPD_TMS < CURRENT_TIMESTAMP - INTERVAL '35' DAY
;


/**************************************************************************\
* REJECT UNKNOWN RECORD TYPES                                              *
\**************************************************************************/


INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.KYC_KYCSYS_REJ
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
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_KYCSYS_RAW   G_T1
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS   TTS
WHERE  G_T1.A NOT IN ('PY', 'AC', 'PA', 'AL')
;


/**************************************************************************\
* POPULATE KYC_PARTY_STG                                                   *
* ------------------------------------------------------------------------ *
* Record type 'PY' - PARTY (CUSTOMER)                                      *
*                                                                          *
* Field                          Src   Pos  Len  Type                      *
* PARTY_ID                       B       1   12  k                         *
* PARTY_TYP_CD                   C       2    1  c                         *
* FULL_NM                        C       3  100  c                         *
* BIRTH_DT                       C     103    8  d                         *
* NATIONALITY_CD                 C     111    2  c                         *
* RESIDENCE_CTRY_CD              C     113    2  c                         *
* SIC_CD                         C     115    5  c                         *
* PEP_IND                        C     120    1  f                         *
* PEP_TYP_CD                     C     121    2  c                         *
* ADV_MEDIA_IND                  C     123    1  f                         *
* SEGMENT_CD                     C     124    3  c                         *
* ONBOARD_DT                     C     127    8  d                         *
* KYC_REVIEW_DUE_DT              C     135    8  d                         *
* KYC_STATUS_CD                  C     143    2  c                         *
* CDD_LEVEL_CD                   C     145    3  c                         *
* RISK_RATING_CD                 C     148    1  c                         *
* RM_ID                          C     149    8  c                         *
* POSTCODE                       C     157    8  c                         *
* CO_HOUSE_NR                    C     165    8  c                         *
* INCORP_CTRY_CD                 C     173    2  c                         *
* EXP_MTH_TURNOVER_AMT           C     175   14  n18_2                     *
* SRC_OF_FUNDS_CD                C     189    2  c                         *
* CLOSED_IND                     C     191    1  f                         *
* ACTION_CD                      C       1    1  a                         *
\**************************************************************************/


INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.KYC_KYCSYS_REJ
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
       CASE WHEN TRIM (SUBSTR (G_T1.B, 1, 12)) = ''
            THEN 'INVALID PARTY_ID'
            WHEN (SUBSTR (G_T1.C, 103, 8) NOT IN ('00000000', '        ') AND VD_BIRTH_DT.DT_TXT IS NULL)
            THEN 'INVALID BIRTH_DT'
            WHEN (SUBSTR (G_T1.C, 127, 8) NOT IN ('00000000', '        ') AND VD_ONBOARD_DT.DT_TXT IS NULL)
            THEN 'INVALID ONBOARD_DT'
            WHEN (SUBSTR (G_T1.C, 135, 8) NOT IN ('00000000', '        ') AND VD_KYC_REVIEW_DUE_DT.DT_TXT IS NULL)
            THEN 'INVALID KYC_REVIEW_DUE_DT'
            WHEN TRIM (TRANSLATE (SUBSTR (G_T1.C, 175, 14), '0123456789.-', '            ')) <> ''
            THEN 'INVALID EXP_MTH_TURNOVER_AMT'
            ELSE 'INVALID RECORD'
       END,
       CAST (TTS.TMS AS TIMESTAMP_NTZ)
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_KYCSYS_RAW   G_T1
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS   TTS
       LEFT OUTER JOIN
       VT_VALID_DT   VD_BIRTH_DT
          ON  VD_BIRTH_DT.DT_TXT = SUBSTR (G_T1.C, 103, 8)
       LEFT OUTER JOIN
       VT_VALID_DT   VD_ONBOARD_DT
          ON  VD_ONBOARD_DT.DT_TXT = SUBSTR (G_T1.C, 127, 8)
       LEFT OUTER JOIN
       VT_VALID_DT   VD_KYC_REVIEW_DUE_DT
          ON  VD_KYC_REVIEW_DUE_DT.DT_TXT = SUBSTR (G_T1.C, 135, 8)
WHERE  G_T1.A = 'PY'
AND    (   TRIM (SUBSTR (G_T1.B, 1, 12)) = ''
        OR (SUBSTR (G_T1.C, 103, 8) NOT IN ('00000000', '        ') AND VD_BIRTH_DT.DT_TXT IS NULL)
        OR (SUBSTR (G_T1.C, 127, 8) NOT IN ('00000000', '        ') AND VD_ONBOARD_DT.DT_TXT IS NULL)
        OR (SUBSTR (G_T1.C, 135, 8) NOT IN ('00000000', '        ') AND VD_KYC_REVIEW_DUE_DT.DT_TXT IS NULL)
        OR TRIM (TRANSLATE (SUBSTR (G_T1.C, 175, 14), '0123456789.-', '            ')) <> ''
       )
;

DELETE FROM `<DB_ENV>DB_TRANS_IMPORTS`.KYC_PARTY_STG
;


INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.KYC_PARTY_STG
(
       PARTY_ID,
       PARTY_TYP_CD,
       FULL_NM,
       BIRTH_DT,
       NATIONALITY_CD,
       RESIDENCE_CTRY_CD,
       SIC_CD,
       PEP_IND,
       PEP_TYP_CD,
       ADV_MEDIA_IND,
       SEGMENT_CD,
       ONBOARD_DT,
       KYC_REVIEW_DUE_DT,
       KYC_STATUS_CD,
       CDD_LEVEL_CD,
       RISK_RATING_CD,
       RM_ID,
       POSTCODE,
       CO_HOUSE_NR,
       INCORP_CTRY_CD,
       EXP_MTH_TURNOVER_AMT,
       SRC_OF_FUNDS_CD,
       CLOSED_IND,
       ACTION_CD
)
SELECT TRIM (SUBSTR (G_T1.B, 1, 12)),
       NULLIF (TRIM (SUBSTR (G_T1.C, 2, 1)), ''),
       NULLIF (TRIM (SUBSTR (G_T1.C, 3, 100)), ''),
       CASE WHEN SUBSTR (G_T1.C, 103, 8) IN ('00000000', '        ') THEN NULL
            ELSE TO_DATE(SUBSTR(G_T1.C, 103, 8), 'yyyyMMdd')
       END,
       NULLIF (TRIM (SUBSTR (G_T1.C, 111, 2)), ''),
       NULLIF (TRIM (SUBSTR (G_T1.C, 113, 2)), ''),
       NULLIF (TRIM (SUBSTR (G_T1.C, 115, 5)), ''),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 120, 1)), ''), 'N'),
       NULLIF (TRIM (SUBSTR (G_T1.C, 121, 2)), ''),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 123, 1)), ''), 'N'),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 124, 3)), ''), 'RET'),
       CASE WHEN SUBSTR (G_T1.C, 127, 8) IN ('00000000', '        ') THEN NULL
            ELSE TO_DATE(SUBSTR(G_T1.C, 127, 8), 'yyyyMMdd')
       END,
       CASE WHEN SUBSTR (G_T1.C, 135, 8) IN ('00000000', '        ') THEN NULL
            ELSE TO_DATE(SUBSTR(G_T1.C, 135, 8), 'yyyyMMdd')
       END,
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 143, 2)), ''), 'PE'),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 145, 3)), ''), 'CDD'),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 148, 1)), ''), 'M'),
       NULLIF (TRIM (SUBSTR (G_T1.C, 149, 8)), ''),
       NULLIF (TRIM (SUBSTR (G_T1.C, 157, 8)), ''),
       NULLIF (TRIM (SUBSTR (G_T1.C, 165, 8)), ''),
       NULLIF (TRIM (SUBSTR (G_T1.C, 173, 2)), ''),
       CAST (NULLIF (TRIM (SUBSTR (G_T1.C, 175, 14)), '') AS DECIMAL(18,2)),
       NULLIF (TRIM (SUBSTR (G_T1.C, 189, 2)), ''),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 191, 1)), ''), 'N'),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 1, 1)), ''), 'I')
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_KYCSYS_RAW   G_T1
       LEFT OUTER JOIN
       VT_VALID_DT   VD_BIRTH_DT
          ON  VD_BIRTH_DT.DT_TXT = SUBSTR (G_T1.C, 103, 8)
       LEFT OUTER JOIN
       VT_VALID_DT   VD_ONBOARD_DT
          ON  VD_ONBOARD_DT.DT_TXT = SUBSTR (G_T1.C, 127, 8)
       LEFT OUTER JOIN
       VT_VALID_DT   VD_KYC_REVIEW_DUE_DT
          ON  VD_KYC_REVIEW_DUE_DT.DT_TXT = SUBSTR (G_T1.C, 135, 8)
WHERE  G_T1.A = 'PY'
AND    NOT (   TRIM (SUBSTR (G_T1.B, 1, 12)) = ''
            OR (SUBSTR (G_T1.C, 103, 8) NOT IN ('00000000', '        ') AND VD_BIRTH_DT.DT_TXT IS NULL)
            OR (SUBSTR (G_T1.C, 127, 8) NOT IN ('00000000', '        ') AND VD_ONBOARD_DT.DT_TXT IS NULL)
            OR (SUBSTR (G_T1.C, 135, 8) NOT IN ('00000000', '        ') AND VD_KYC_REVIEW_DUE_DT.DT_TXT IS NULL)
            OR TRIM (TRANSLATE (SUBSTR (G_T1.C, 175, 14), '0123456789.-', '            ')) <> ''
           )
QUALIFY SUM (1) OVER (PARTITION BY  TRIM (SUBSTR (G_T1.B, 1, 12))
                          ORDER BY  G_T1.C DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;

-- Databricks conversion: refresh column statistics after the load.
ANALYZE TABLE `<DB_ENV>DB_TRANS_IMPORTS`.KYC_PARTY_STG COMPUTE STATISTICS FOR COLUMNS PARTY_ID;


/**************************************************************************\
* POPULATE KYC_ACCT_STG                                                    *
* ------------------------------------------------------------------------ *
* Record type 'AC' - ACCOUNT                                               *
*                                                                          *
* Field                          Src   Pos  Len  Type                      *
* ACCT_ID                        B       1   14  k                         *
* SORT_CD                        B       1    6  k                         *
* ACCT_NR                        B       7    8  k                         *
* PRDT_CD                        C       2    6  c                         *
* CCY_CD                         C       8    3  c                         *
* OPEN_DT                        C      11    8  d                         *
* CLOSE_DT                       C      19    8  d                         *
* ACCT_STATUS_CD                 C      27    1  c                         *
* PRIMARY_PARTY_ID               C      28   12  c                         *
* OD_LIMIT_AMT                   C      40   14  n18_2                     *
* LAST_CUST_ACTV_DT              C      54    8  d                         *
* OPEN_CHNL_CD                   C      62    3  c                         *
* ACTION_CD                      C       1    1  a                         *
\**************************************************************************/


INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.KYC_KYCSYS_REJ
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
       CASE WHEN TRIM (SUBSTR (G_T1.B, 1, 14)) = ''
            THEN 'INVALID ACCT_ID'
            WHEN TRIM (SUBSTR (G_T1.B, 1, 6)) = ''
            THEN 'INVALID SORT_CD'
            WHEN TRIM (SUBSTR (G_T1.B, 7, 8)) = ''
            THEN 'INVALID ACCT_NR'
            WHEN (SUBSTR (G_T1.C, 11, 8) NOT IN ('00000000', '        ') AND VD_OPEN_DT.DT_TXT IS NULL)
            THEN 'INVALID OPEN_DT'
            WHEN (SUBSTR (G_T1.C, 19, 8) NOT IN ('00000000', '        ') AND VD_CLOSE_DT.DT_TXT IS NULL)
            THEN 'INVALID CLOSE_DT'
            WHEN TRIM (TRANSLATE (SUBSTR (G_T1.C, 40, 14), '0123456789.-', '            ')) <> ''
            THEN 'INVALID OD_LIMIT_AMT'
            WHEN (SUBSTR (G_T1.C, 54, 8) NOT IN ('00000000', '        ') AND VD_LAST_CUST_ACTV_DT.DT_TXT IS NULL)
            THEN 'INVALID LAST_CUST_ACTV_DT'
            ELSE 'INVALID RECORD'
       END,
       CAST (TTS.TMS AS TIMESTAMP_NTZ)
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_KYCSYS_RAW   G_T1
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS   TTS
       LEFT OUTER JOIN
       VT_VALID_DT   VD_OPEN_DT
          ON  VD_OPEN_DT.DT_TXT = SUBSTR (G_T1.C, 11, 8)
       LEFT OUTER JOIN
       VT_VALID_DT   VD_CLOSE_DT
          ON  VD_CLOSE_DT.DT_TXT = SUBSTR (G_T1.C, 19, 8)
       LEFT OUTER JOIN
       VT_VALID_DT   VD_LAST_CUST_ACTV_DT
          ON  VD_LAST_CUST_ACTV_DT.DT_TXT = SUBSTR (G_T1.C, 54, 8)
WHERE  G_T1.A = 'AC'
AND    (   TRIM (SUBSTR (G_T1.B, 1, 14)) = ''
        OR TRIM (SUBSTR (G_T1.B, 1, 6)) = ''
        OR TRIM (SUBSTR (G_T1.B, 7, 8)) = ''
        OR (SUBSTR (G_T1.C, 11, 8) NOT IN ('00000000', '        ') AND VD_OPEN_DT.DT_TXT IS NULL)
        OR (SUBSTR (G_T1.C, 19, 8) NOT IN ('00000000', '        ') AND VD_CLOSE_DT.DT_TXT IS NULL)
        OR TRIM (TRANSLATE (SUBSTR (G_T1.C, 40, 14), '0123456789.-', '            ')) <> ''
        OR (SUBSTR (G_T1.C, 54, 8) NOT IN ('00000000', '        ') AND VD_LAST_CUST_ACTV_DT.DT_TXT IS NULL)
       )
;

DELETE FROM `<DB_ENV>DB_TRANS_IMPORTS`.KYC_ACCT_STG
;


INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.KYC_ACCT_STG
(
       ACCT_ID,
       SORT_CD,
       ACCT_NR,
       PRDT_CD,
       CCY_CD,
       OPEN_DT,
       CLOSE_DT,
       ACCT_STATUS_CD,
       PRIMARY_PARTY_ID,
       OD_LIMIT_AMT,
       LAST_CUST_ACTV_DT,
       OPEN_CHNL_CD,
       ACTION_CD
)
SELECT TRIM (SUBSTR (G_T1.B, 1, 14)),
       TRIM (SUBSTR (G_T1.B, 1, 6)),
       TRIM (SUBSTR (G_T1.B, 7, 8)),
       NULLIF (TRIM (SUBSTR (G_T1.C, 2, 6)), ''),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 8, 3)), ''), 'GBP'),
       CASE WHEN SUBSTR (G_T1.C, 11, 8) IN ('00000000', '        ') THEN NULL
            ELSE TO_DATE(SUBSTR(G_T1.C, 11, 8), 'yyyyMMdd')
       END,
       CASE WHEN SUBSTR (G_T1.C, 19, 8) IN ('00000000', '        ') THEN NULL
            ELSE TO_DATE(SUBSTR(G_T1.C, 19, 8), 'yyyyMMdd')
       END,
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 27, 1)), ''), 'A'),
       NULLIF (TRIM (SUBSTR (G_T1.C, 28, 12)), ''),
       CAST (NULLIF (TRIM (SUBSTR (G_T1.C, 40, 14)), '') AS DECIMAL(18,2)),
       CASE WHEN SUBSTR (G_T1.C, 54, 8) IN ('00000000', '        ') THEN NULL
            ELSE TO_DATE(SUBSTR(G_T1.C, 54, 8), 'yyyyMMdd')
       END,
       NULLIF (TRIM (SUBSTR (G_T1.C, 62, 3)), ''),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 1, 1)), ''), 'I')
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_KYCSYS_RAW   G_T1
       LEFT OUTER JOIN
       VT_VALID_DT   VD_OPEN_DT
          ON  VD_OPEN_DT.DT_TXT = SUBSTR (G_T1.C, 11, 8)
       LEFT OUTER JOIN
       VT_VALID_DT   VD_CLOSE_DT
          ON  VD_CLOSE_DT.DT_TXT = SUBSTR (G_T1.C, 19, 8)
       LEFT OUTER JOIN
       VT_VALID_DT   VD_LAST_CUST_ACTV_DT
          ON  VD_LAST_CUST_ACTV_DT.DT_TXT = SUBSTR (G_T1.C, 54, 8)
WHERE  G_T1.A = 'AC'
AND    NOT (   TRIM (SUBSTR (G_T1.B, 1, 14)) = ''
            OR TRIM (SUBSTR (G_T1.B, 1, 6)) = ''
            OR TRIM (SUBSTR (G_T1.B, 7, 8)) = ''
            OR (SUBSTR (G_T1.C, 11, 8) NOT IN ('00000000', '        ') AND VD_OPEN_DT.DT_TXT IS NULL)
            OR (SUBSTR (G_T1.C, 19, 8) NOT IN ('00000000', '        ') AND VD_CLOSE_DT.DT_TXT IS NULL)
            OR TRIM (TRANSLATE (SUBSTR (G_T1.C, 40, 14), '0123456789.-', '            ')) <> ''
            OR (SUBSTR (G_T1.C, 54, 8) NOT IN ('00000000', '        ') AND VD_LAST_CUST_ACTV_DT.DT_TXT IS NULL)
           )
QUALIFY SUM (1) OVER (PARTITION BY  TRIM (SUBSTR (G_T1.B, 1, 14))
                          ORDER BY  G_T1.C DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;

-- Databricks conversion: refresh column statistics after the load.
ANALYZE TABLE `<DB_ENV>DB_TRANS_IMPORTS`.KYC_ACCT_STG COMPUTE STATISTICS FOR COLUMNS ACCT_ID;


/**************************************************************************\
* POPULATE KYC_PTAC_STG                                                    *
* ------------------------------------------------------------------------ *
* Record type 'PA' - PARTY / ACCOUNT RELATIONSHIP                          *
*                                                                          *
* Field                          Src   Pos  Len  Type                      *
* PARTY_ID                       B       1   12  k                         *
* ACCT_ID                        B      13   14  k                         *
* ROLE_CD                        C       2    2  k                         *
* START_DT                       C       4    8  d                         *
* END_DT                         C      12    8  d                         *
* OWNERSHIP_PCT                  C      20    6  n5_2                      *
* ACTION_CD                      C       1    1  a                         *
\**************************************************************************/


INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.KYC_KYCSYS_REJ
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
       CASE WHEN TRIM (SUBSTR (G_T1.B, 1, 12)) = ''
            THEN 'INVALID PARTY_ID'
            WHEN TRIM (SUBSTR (G_T1.B, 13, 14)) = ''
            THEN 'INVALID ACCT_ID'
            WHEN TRIM (SUBSTR (G_T1.C, 2, 2)) = ''
            THEN 'INVALID ROLE_CD'
            WHEN (SUBSTR (G_T1.C, 4, 8) NOT IN ('00000000', '        ') AND VD_START_DT.DT_TXT IS NULL)
            THEN 'INVALID START_DT'
            WHEN (SUBSTR (G_T1.C, 12, 8) NOT IN ('00000000', '        ') AND VD_END_DT.DT_TXT IS NULL)
            THEN 'INVALID END_DT'
            WHEN TRIM (TRANSLATE (SUBSTR (G_T1.C, 20, 6), '0123456789.-', '            ')) <> ''
            THEN 'INVALID OWNERSHIP_PCT'
            ELSE 'INVALID RECORD'
       END,
       CAST (TTS.TMS AS TIMESTAMP_NTZ)
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_KYCSYS_RAW   G_T1
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS   TTS
       LEFT OUTER JOIN
       VT_VALID_DT   VD_START_DT
          ON  VD_START_DT.DT_TXT = SUBSTR (G_T1.C, 4, 8)
       LEFT OUTER JOIN
       VT_VALID_DT   VD_END_DT
          ON  VD_END_DT.DT_TXT = SUBSTR (G_T1.C, 12, 8)
WHERE  G_T1.A = 'PA'
AND    (   TRIM (SUBSTR (G_T1.B, 1, 12)) = ''
        OR TRIM (SUBSTR (G_T1.B, 13, 14)) = ''
        OR TRIM (SUBSTR (G_T1.C, 2, 2)) = ''
        OR (SUBSTR (G_T1.C, 4, 8) NOT IN ('00000000', '        ') AND VD_START_DT.DT_TXT IS NULL)
        OR (SUBSTR (G_T1.C, 12, 8) NOT IN ('00000000', '        ') AND VD_END_DT.DT_TXT IS NULL)
        OR TRIM (TRANSLATE (SUBSTR (G_T1.C, 20, 6), '0123456789.-', '            ')) <> ''
       )
;

DELETE FROM `<DB_ENV>DB_TRANS_IMPORTS`.KYC_PTAC_STG
;


INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.KYC_PTAC_STG
(
       PARTY_ID,
       ACCT_ID,
       ROLE_CD,
       START_DT,
       END_DT,
       OWNERSHIP_PCT,
       ACTION_CD
)
SELECT TRIM (SUBSTR (G_T1.B, 1, 12)),
       TRIM (SUBSTR (G_T1.B, 13, 14)),
       TRIM (SUBSTR (G_T1.C, 2, 2)),
       CASE WHEN SUBSTR (G_T1.C, 4, 8) IN ('00000000', '        ') THEN NULL
            ELSE TO_DATE(SUBSTR(G_T1.C, 4, 8), 'yyyyMMdd')
       END,
       CASE WHEN SUBSTR (G_T1.C, 12, 8) IN ('00000000', '        ') THEN NULL
            ELSE TO_DATE(SUBSTR(G_T1.C, 12, 8), 'yyyyMMdd')
       END,
       CAST (NULLIF (TRIM (SUBSTR (G_T1.C, 20, 6)), '') AS DECIMAL(5,2)),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 1, 1)), ''), 'I')
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_KYCSYS_RAW   G_T1
       LEFT OUTER JOIN
       VT_VALID_DT   VD_START_DT
          ON  VD_START_DT.DT_TXT = SUBSTR (G_T1.C, 4, 8)
       LEFT OUTER JOIN
       VT_VALID_DT   VD_END_DT
          ON  VD_END_DT.DT_TXT = SUBSTR (G_T1.C, 12, 8)
WHERE  G_T1.A = 'PA'
AND    NOT (   TRIM (SUBSTR (G_T1.B, 1, 12)) = ''
            OR TRIM (SUBSTR (G_T1.B, 13, 14)) = ''
            OR TRIM (SUBSTR (G_T1.C, 2, 2)) = ''
            OR (SUBSTR (G_T1.C, 4, 8) NOT IN ('00000000', '        ') AND VD_START_DT.DT_TXT IS NULL)
            OR (SUBSTR (G_T1.C, 12, 8) NOT IN ('00000000', '        ') AND VD_END_DT.DT_TXT IS NULL)
            OR TRIM (TRANSLATE (SUBSTR (G_T1.C, 20, 6), '0123456789.-', '            ')) <> ''
           )
QUALIFY SUM (1) OVER (PARTITION BY  TRIM (SUBSTR (G_T1.B, 1, 12)), TRIM (SUBSTR (G_T1.B, 13, 14)), SUBSTR (G_T1.C, 2, 2)
                          ORDER BY  G_T1.C DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;

-- Databricks conversion: refresh column statistics after the load.
ANALYZE TABLE `<DB_ENV>DB_TRANS_IMPORTS`.KYC_PTAC_STG COMPUTE STATISTICS FOR COLUMNS PARTY_ID, ACCT_ID, ROLE_CD;


/**************************************************************************\
* POPULATE KYC_ALIAS_STG                                                   *
* ------------------------------------------------------------------------ *
* Record type 'AL' - PARTY ALIAS / PREVIOUS / TRADING NAME                 *
*                                                                          *
* Field                          Src   Pos  Len  Type                      *
* PARTY_ID                       B       1   12  k                         *
* ALIAS_SEQ_NR                   B      13    3  ksi                       *
* ALIAS_NM                       C       2  100  c                         *
* ALIAS_TYP_CD                   C     102    2  c                         *
* ACTION_CD                      C       1    1  a                         *
\**************************************************************************/


INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.KYC_KYCSYS_REJ
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
       CASE WHEN TRIM (SUBSTR (G_T1.B, 1, 12)) = ''
            THEN 'INVALID PARTY_ID'
            WHEN TRIM (TRANSLATE (SUBSTR (G_T1.B, 13, 3), '0123456789.-', '            ')) <> ''
            THEN 'INVALID ALIAS_SEQ_NR'
            ELSE 'INVALID RECORD'
       END,
       CAST (TTS.TMS AS TIMESTAMP_NTZ)
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_KYCSYS_RAW   G_T1
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS   TTS
WHERE  G_T1.A = 'AL'
AND    (   TRIM (SUBSTR (G_T1.B, 1, 12)) = ''
        OR TRIM (TRANSLATE (SUBSTR (G_T1.B, 13, 3), '0123456789.-', '            ')) <> ''
       )
;

DELETE FROM `<DB_ENV>DB_TRANS_IMPORTS`.KYC_ALIAS_STG
;


INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.KYC_ALIAS_STG
(
       PARTY_ID,
       ALIAS_SEQ_NR,
       ALIAS_NM,
       ALIAS_TYP_CD,
       ACTION_CD
)
SELECT TRIM (SUBSTR (G_T1.B, 1, 12)),
       CAST (NULLIF (TRIM (SUBSTR (G_T1.B, 13, 3)), '') AS SMALLINT),
       NULLIF (TRIM (SUBSTR (G_T1.C, 2, 100)), ''),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 102, 2)), ''), 'AK'),
       COALESCE (NULLIF (TRIM (SUBSTR (G_T1.C, 1, 1)), ''), 'I')
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.AML_KYCSYS_RAW   G_T1
WHERE  G_T1.A = 'AL'
AND    NOT (   TRIM (SUBSTR (G_T1.B, 1, 12)) = ''
            OR TRIM (TRANSLATE (SUBSTR (G_T1.B, 13, 3), '0123456789.-', '            ')) <> ''
           )
QUALIFY SUM (1) OVER (PARTITION BY  TRIM (SUBSTR (G_T1.B, 1, 12)), TRIM (SUBSTR (G_T1.B, 13, 3))
                          ORDER BY  G_T1.C DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;

-- Databricks conversion: refresh column statistics after the load.
ANALYZE TABLE `<DB_ENV>DB_TRANS_IMPORTS`.KYC_ALIAS_STG COMPUTE STATISTICS FOR COLUMNS PARTY_ID, ALIAS_SEQ_NR;


/**************************************************************************\
* DERIVE CDD LEVEL FOR PEPS                                                *
* ------------------------------------------------------------------------ *
* Regulation 35 MLR 2017: every PEP, family member or known close associate *
* is subject to enhanced due diligence regardless of the KYCSYS value.     *
* The original value is still reported as a DQ issue further below.        *
\**************************************************************************/


-- Databricks conversion: temporary CTAS replaces the populated Teradata volatile table.
CREATE TEMP TABLE VT_PEP_CDD_OVERRIDE AS
SELECT PARTY_ID,
       CDD_LEVEL_CD AS ORIG_CDD_LEVEL_CD
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.KYC_PARTY_STG
WHERE  PEP_IND = 'Y'
AND    CDD_LEVEL_CD <> 'EDD';

UPDATE `<DB_ENV>DB_TRANS_IMPORTS`.KYC_PARTY_STG
SET    CDD_LEVEL_CD   = 'EDD',
       RISK_RATING_CD = 'H'
WHERE  PEP_IND       = 'Y'
AND    CDD_LEVEL_CD <> 'EDD'
;


/**************************************************************************\
* ADD NEWLY SEEN CODES TO KYC_STATUS_CAT                                   *
\**************************************************************************/


INSERT INTO `<DB_ENV>DB_ODS`.KYC_STATUS_CAT
(
       CD,
       AUTO_ADDED_IND,
       CO_UPD_TMS
)
SELECT DISTINCT
       STG.KYC_STATUS_CD,
       'Y',
       CAST (TTS.TMS AS TIMESTAMP_NTZ)
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.KYC_PARTY_STG   STG
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS   TTS
WHERE  STG.KYC_STATUS_CD IS NOT NULL
AND    STG.KYC_STATUS_CD NOT IN (SELECT CD FROM `<DB_ENV>DB_ODS`.KYC_STATUS_CAT)
;

-- Databricks conversion: refresh column statistics after the load.
ANALYZE TABLE `<DB_ENV>DB_ODS`.KYC_STATUS_CAT COMPUTE STATISTICS FOR COLUMNS CD;


/**************************************************************************\
* ADD NEWLY SEEN CODES TO CDD_LEVEL_CAT                                    *
\**************************************************************************/


INSERT INTO `<DB_ENV>DB_ODS`.CDD_LEVEL_CAT
(
       CD,
       AUTO_ADDED_IND,
       CO_UPD_TMS
)
SELECT DISTINCT
       STG.CDD_LEVEL_CD,
       'Y',
       CAST (TTS.TMS AS TIMESTAMP_NTZ)
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.KYC_PARTY_STG   STG
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS   TTS
WHERE  STG.CDD_LEVEL_CD IS NOT NULL
AND    STG.CDD_LEVEL_CD NOT IN (SELECT CD FROM `<DB_ENV>DB_ODS`.CDD_LEVEL_CAT)
;

-- Databricks conversion: refresh column statistics after the load.
ANALYZE TABLE `<DB_ENV>DB_ODS`.CDD_LEVEL_CAT COMPUTE STATISTICS FOR COLUMNS CD;


/**************************************************************************\
* ADD NEWLY SEEN CODES TO PARTY_ROLE_CAT                                   *
\**************************************************************************/


INSERT INTO `<DB_ENV>DB_ODS`.PARTY_ROLE_CAT
(
       CD,
       AUTO_ADDED_IND,
       CO_UPD_TMS
)
SELECT DISTINCT
       STG.ROLE_CD,
       'Y',
       CAST (TTS.TMS AS TIMESTAMP_NTZ)
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.KYC_PTAC_STG   STG
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS   TTS
WHERE  STG.ROLE_CD IS NOT NULL
AND    STG.ROLE_CD NOT IN (SELECT CD FROM `<DB_ENV>DB_ODS`.PARTY_ROLE_CAT)
;

-- Databricks conversion: refresh column statistics after the load.
ANALYZE TABLE `<DB_ENV>DB_ODS`.PARTY_ROLE_CAT COMPUTE STATISTICS FOR COLUMNS CD;


/**************************************************************************\
* PARTY: DETERMINE CHANGES                                                 *
* ------------------------------------------------------------------------ *
* N = new party, U = tracked attribute changed, D = party deleted in KYCSYS *
* Unchanged parties re-sent by KYCSYS are ignored.                         *
\**************************************************************************/


-- Databricks conversion: session-scoped table replaces Teradata VOLATILE table; PI and ON COMMIT clauses are removed.
CREATE TEMP TABLE VT_PARTY_CHG
(
       PARTY_ID    CHAR(12) COLLATE UTF8_LCASE NOT NULL,
       CHG_TYP_CD  CHAR(1) COLLATE UTF8_LCASE NOT NULL
);

INSERT INTO VT_PARTY_CHG
(
       PARTY_ID,
       CHG_TYP_CD
)
SELECT STG.PARTY_ID,
       CASE WHEN STG.ACTION_CD = 'D'   THEN 'D'
            WHEN CUR.PARTY_ID IS NULL  THEN 'N'
            ELSE 'U'
       END
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.KYC_PARTY_STG   STG
       LEFT OUTER JOIN
       `<DB_ENV>DB_ODS`.PARTY          CUR
          ON  CUR.PARTY_ID = STG.PARTY_ID
WHERE  (STG.ACTION_CD = 'D' AND CUR.PARTY_ID IS NOT NULL AND CUR.CLOSED_IND = 'N')
OR     (STG.ACTION_CD <> 'D' AND CUR.PARTY_ID IS NULL)
OR     (STG.ACTION_CD <> 'D'
        AND (   COALESCE (CUR.PARTY_TYP_CD, '~') <> COALESCE (STG.PARTY_TYP_CD, '~')
             OR COALESCE (CUR.FULL_NM, '~') <> COALESCE (STG.FULL_NM, '~')
             OR COALESCE (CUR.BIRTH_DT, DATE '0001-01-01') <> COALESCE (STG.BIRTH_DT, DATE '0001-01-01')
             OR COALESCE (CUR.NATIONALITY_CD, '~') <> COALESCE (STG.NATIONALITY_CD, '~')
             OR COALESCE (CUR.RESIDENCE_CTRY_CD, '~') <> COALESCE (STG.RESIDENCE_CTRY_CD, '~')
             OR COALESCE (CUR.SIC_CD, '~') <> COALESCE (STG.SIC_CD, '~')
             OR COALESCE (CUR.PEP_IND, '~') <> COALESCE (STG.PEP_IND, '~')
             OR COALESCE (CUR.PEP_TYP_CD, '~') <> COALESCE (STG.PEP_TYP_CD, '~')
             OR COALESCE (CUR.ADV_MEDIA_IND, '~') <> COALESCE (STG.ADV_MEDIA_IND, '~')
             OR COALESCE (CUR.SEGMENT_CD, '~') <> COALESCE (STG.SEGMENT_CD, '~')
             OR COALESCE (CUR.ONBOARD_DT, DATE '0001-01-01') <> COALESCE (STG.ONBOARD_DT, DATE '0001-01-01')
             OR COALESCE (CUR.KYC_REVIEW_DUE_DT, DATE '0001-01-01') <> COALESCE (STG.KYC_REVIEW_DUE_DT, DATE '0001-01-01')
             OR COALESCE (CUR.KYC_STATUS_CD, '~') <> COALESCE (STG.KYC_STATUS_CD, '~')
             OR COALESCE (CUR.CDD_LEVEL_CD, '~') <> COALESCE (STG.CDD_LEVEL_CD, '~')
             OR COALESCE (CUR.RISK_RATING_CD, '~') <> COALESCE (STG.RISK_RATING_CD, '~')
             OR COALESCE (CUR.RM_ID, '~') <> COALESCE (STG.RM_ID, '~')
             OR COALESCE (CUR.POSTCODE, '~') <> COALESCE (STG.POSTCODE, '~')
             OR COALESCE (CUR.CO_HOUSE_NR, '~') <> COALESCE (STG.CO_HOUSE_NR, '~')
             OR COALESCE (CUR.INCORP_CTRY_CD, '~') <> COALESCE (STG.INCORP_CTRY_CD, '~')
             OR COALESCE (CUR.EXP_MTH_TURNOVER_AMT, -1) <> COALESCE (STG.EXP_MTH_TURNOVER_AMT, -1)
             OR COALESCE (CUR.SRC_OF_FUNDS_CD, '~') <> COALESCE (STG.SRC_OF_FUNDS_CD, '~')
             OR COALESCE (CUR.CLOSED_IND, '~') <> COALESCE (STG.CLOSED_IND, '~')
            )
       )
;

-- Databricks conversion: refresh column statistics after the load.
ANALYZE TABLE VT_PARTY_CHG COMPUTE STATISTICS FOR COLUMNS PARTY_ID;


/**************************************************************************\
* PARTY: CLOSE THE OPEN HISTORY VERSION                                    *
\**************************************************************************/


-- Databricks conversion: MERGE replaces Teradata UPDATE FROM.
MERGE INTO `<DB_ENV>DB_ODS`.PARTY_HIST AS HST
USING (SELECT CHG.PARTY_ID, TTS.TMS
       FROM VT_PARTY_CHG AS CHG
       CROSS JOIN `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS AS TTS) AS SRC
ON HST.PARTY_ID = SRC.PARTY_ID
AND HST.END_DT IS NULL
AND HST.START_DT < CAST(SRC.TMS AS DATE)
WHEN MATCHED THEN UPDATE SET
  END_DT = CAST(SRC.TMS AS DATE) - 1,
  CO_UPD_TMS = CAST(SRC.TMS AS TIMESTAMP_NTZ);

-- Databricks conversion: MERGE replaces Teradata UPDATE FROM.
MERGE INTO `<DB_ENV>DB_ODS`.PARTY_HIST AS HST
USING (SELECT CHG.PARTY_ID, TTS.TMS
       FROM VT_PARTY_CHG AS CHG
       CROSS JOIN `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS AS TTS) AS SRC
ON HST.PARTY_ID = SRC.PARTY_ID
AND HST.END_DT IS NULL
AND HST.START_DT = CAST(SRC.TMS AS DATE)
WHEN MATCHED THEN UPDATE SET
  END_DT = CAST(SRC.TMS AS DATE),
  CO_UPD_TMS = CAST(SRC.TMS AS TIMESTAMP_NTZ);


/**************************************************************************\
* PARTY: WRITE NEW HISTORY VERSIONS (NEW / CHANGED)                        *
\**************************************************************************/


INSERT INTO `<DB_ENV>DB_ODS`.PARTY_HIST
(
       PARTY_ID,
       START_DT,
       UPD_TMS,
       END_DT,
       PARTY_TYP_CD,
       FULL_NM,
       BIRTH_DT,
       NATIONALITY_CD,
       RESIDENCE_CTRY_CD,
       SIC_CD,
       PEP_IND,
       PEP_TYP_CD,
       ADV_MEDIA_IND,
       SEGMENT_CD,
       ONBOARD_DT,
       KYC_REVIEW_DUE_DT,
       KYC_STATUS_CD,
       CDD_LEVEL_CD,
       RISK_RATING_CD,
       RM_ID,
       POSTCODE,
       CO_HOUSE_NR,
       INCORP_CTRY_CD,
       EXP_MTH_TURNOVER_AMT,
       SRC_OF_FUNDS_CD,
       CLOSED_IND,
       ACTION_CD,
       CO_UPD_TMS
)
SELECT STG.PARTY_ID,
       CAST (TTS.TMS AS DATE),
       CAST (TTS.TMS AS TIMESTAMP_NTZ),
       NULL,
       STG.PARTY_TYP_CD,
       STG.FULL_NM,
       STG.BIRTH_DT,
       STG.NATIONALITY_CD,
       STG.RESIDENCE_CTRY_CD,
       STG.SIC_CD,
       STG.PEP_IND,
       STG.PEP_TYP_CD,
       STG.ADV_MEDIA_IND,
       STG.SEGMENT_CD,
       STG.ONBOARD_DT,
       STG.KYC_REVIEW_DUE_DT,
       STG.KYC_STATUS_CD,
       STG.CDD_LEVEL_CD,
       STG.RISK_RATING_CD,
       STG.RM_ID,
       STG.POSTCODE,
       STG.CO_HOUSE_NR,
       STG.INCORP_CTRY_CD,
       STG.EXP_MTH_TURNOVER_AMT,
       STG.SRC_OF_FUNDS_CD,
       STG.CLOSED_IND,
       CHG.CHG_TYP_CD,
       CAST (TTS.TMS AS TIMESTAMP_NTZ)
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.KYC_PARTY_STG   STG
       INNER JOIN
       VT_PARTY_CHG         CHG
          ON  CHG.PARTY_ID   = STG.PARTY_ID
          AND CHG.CHG_TYP_CD IN ('N', 'U')
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS   TTS
;


/**************************************************************************\
* PARTY: WRITE CLOSING HISTORY VERSIONS (DELETED)                          *
* ------------------------------------------------------------------------ *
* Deleted parties are retained (closed) for the 5 year MLR retention period. *
\**************************************************************************/


INSERT INTO `<DB_ENV>DB_ODS`.PARTY_HIST
(
       PARTY_ID,
       START_DT,
       UPD_TMS,
       END_DT,
       PARTY_TYP_CD,
       FULL_NM,
       BIRTH_DT,
       NATIONALITY_CD,
       RESIDENCE_CTRY_CD,
       SIC_CD,
       PEP_IND,
       PEP_TYP_CD,
       ADV_MEDIA_IND,
       SEGMENT_CD,
       ONBOARD_DT,
       KYC_REVIEW_DUE_DT,
       KYC_STATUS_CD,
       CDD_LEVEL_CD,
       RISK_RATING_CD,
       RM_ID,
       POSTCODE,
       CO_HOUSE_NR,
       INCORP_CTRY_CD,
       EXP_MTH_TURNOVER_AMT,
       SRC_OF_FUNDS_CD,
       CLOSED_IND,
       ACTION_CD,
       CO_UPD_TMS
)
SELECT CUR.PARTY_ID,
       CAST (TTS.TMS AS DATE),
       CAST (TTS.TMS AS TIMESTAMP_NTZ),
       CAST (TTS.TMS AS DATE),
       CUR.PARTY_TYP_CD,
       CUR.FULL_NM,
       CUR.BIRTH_DT,
       CUR.NATIONALITY_CD,
       CUR.RESIDENCE_CTRY_CD,
       CUR.SIC_CD,
       CUR.PEP_IND,
       CUR.PEP_TYP_CD,
       CUR.ADV_MEDIA_IND,
       CUR.SEGMENT_CD,
       CUR.ONBOARD_DT,
       CUR.KYC_REVIEW_DUE_DT,
       CUR.KYC_STATUS_CD,
       CUR.CDD_LEVEL_CD,
       CUR.RISK_RATING_CD,
       CUR.RM_ID,
       CUR.POSTCODE,
       CUR.CO_HOUSE_NR,
       CUR.INCORP_CTRY_CD,
       CUR.EXP_MTH_TURNOVER_AMT,
       CUR.SRC_OF_FUNDS_CD,
       'Y',
       'D',
       CAST (TTS.TMS AS TIMESTAMP_NTZ)
FROM   `<DB_ENV>DB_ODS`.PARTY    CUR
       INNER JOIN
       VT_PARTY_CHG   CHG
          ON  CHG.PARTY_ID   = CUR.PARTY_ID
          AND CHG.CHG_TYP_CD = 'D'
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS   TTS
;


/**************************************************************************\
* PARTY: APPLY TO THE CURRENT TABLE                                        *
* ------------------------------------------------------------------------ *
* Executed as one transaction so that readers of DB_ODS.PARTY never see a  *
* party missing between the DELETE and the INSERT.                         *
\**************************************************************************/

-- Databricks conversion: atomic SQL procedure preserves the BT/ET transaction boundary.
CREATE OR REPLACE PROCEDURE apply_party_changes_txn()
LANGUAGE SQL
SQL SECURITY DEFINER
AS BEGIN ATOMIC
DELETE FROM `<DB_ENV>DB_ODS`.PARTY
WHERE  PARTY_ID IN (SELECT PARTY_ID FROM VT_PARTY_CHG WHERE CHG_TYP_CD IN ('N', 'U'))
;


INSERT INTO `<DB_ENV>DB_ODS`.PARTY
(
       PARTY_ID,
       PARTY_TYP_CD,
       FULL_NM,
       BIRTH_DT,
       NATIONALITY_CD,
       RESIDENCE_CTRY_CD,
       SIC_CD,
       PEP_IND,
       PEP_TYP_CD,
       ADV_MEDIA_IND,
       SEGMENT_CD,
       ONBOARD_DT,
       KYC_REVIEW_DUE_DT,
       KYC_STATUS_CD,
       CDD_LEVEL_CD,
       RISK_RATING_CD,
       RM_ID,
       POSTCODE,
       CO_HOUSE_NR,
       INCORP_CTRY_CD,
       EXP_MTH_TURNOVER_AMT,
       SRC_OF_FUNDS_CD,
       CLOSED_IND,
       CO_UPD_TMS
)
SELECT STG.PARTY_ID,
       STG.PARTY_TYP_CD,
       STG.FULL_NM,
       STG.BIRTH_DT,
       STG.NATIONALITY_CD,
       STG.RESIDENCE_CTRY_CD,
       STG.SIC_CD,
       STG.PEP_IND,
       STG.PEP_TYP_CD,
       STG.ADV_MEDIA_IND,
       STG.SEGMENT_CD,
       STG.ONBOARD_DT,
       STG.KYC_REVIEW_DUE_DT,
       STG.KYC_STATUS_CD,
       STG.CDD_LEVEL_CD,
       STG.RISK_RATING_CD,
       STG.RM_ID,
       STG.POSTCODE,
       STG.CO_HOUSE_NR,
       STG.INCORP_CTRY_CD,
       STG.EXP_MTH_TURNOVER_AMT,
       STG.SRC_OF_FUNDS_CD,
       STG.CLOSED_IND,
       CAST (TTS.TMS AS TIMESTAMP_NTZ)
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.KYC_PARTY_STG   STG
       INNER JOIN
       VT_PARTY_CHG         CHG
          ON  CHG.PARTY_ID   = STG.PARTY_ID
          AND CHG.CHG_TYP_CD IN ('N', 'U')
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS   TTS
;


-- Databricks conversion: MERGE replaces Teradata UPDATE FROM.
MERGE INTO `<DB_ENV>DB_ODS`.PARTY AS PTY
USING (SELECT CHG.PARTY_ID, TTS.TMS
       FROM VT_PARTY_CHG AS CHG
       CROSS JOIN `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS AS TTS
       WHERE CHG.CHG_TYP_CD = 'D') AS SRC
ON PTY.PARTY_ID = SRC.PARTY_ID
WHEN MATCHED THEN UPDATE SET
  CLOSED_IND = 'Y',
  CO_UPD_TMS = CAST(SRC.TMS AS TIMESTAMP_NTZ);

END;
-- Databricks conversion: invoke the atomic party change transaction.
CALL apply_party_changes_txn();

-- Databricks conversion: refresh column statistics after the load.
ANALYZE TABLE `<DB_ENV>DB_ODS`.PARTY COMPUTE STATISTICS FOR COLUMNS PARTY_ID;
-- Databricks conversion: refresh column statistics after the load.
ANALYZE TABLE `<DB_ENV>DB_ODS`.PARTY_HIST COMPUTE STATISTICS FOR COLUMNS PARTY_ID, START_DT, UPD_TMS;


/**************************************************************************\
* ACCOUNT: DETERMINE CHANGES                                               *
* ------------------------------------------------------------------------ *
* LAST_CUST_ACTV_DT is refreshed daily by KYCSYS and is not a tracked      *
* attribute - it is updated in place without creating history.             *
\**************************************************************************/


-- Databricks conversion: session-scoped table replaces Teradata VOLATILE table; PI and ON COMMIT clauses are removed.
CREATE TEMP TABLE VT_ACCT_CHG
(
       ACCT_ID     CHAR(14) COLLATE UTF8_LCASE NOT NULL,
       CHG_TYP_CD  CHAR(1) COLLATE UTF8_LCASE NOT NULL
);

INSERT INTO VT_ACCT_CHG
(
       ACCT_ID,
       CHG_TYP_CD
)
SELECT STG.ACCT_ID,
       CASE WHEN STG.ACTION_CD = 'D'  THEN 'D'
            WHEN CUR.ACCT_ID IS NULL  THEN 'N'
            ELSE 'U'
       END
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.KYC_ACCT_STG   STG
       LEFT OUTER JOIN
       `<DB_ENV>DB_ODS`.ACCT          CUR
          ON  CUR.ACCT_ID = STG.ACCT_ID
WHERE  (STG.ACTION_CD = 'D' AND CUR.ACCT_ID IS NOT NULL AND CUR.ACCT_STATUS_CD <> 'C')
OR     (STG.ACTION_CD <> 'D' AND CUR.ACCT_ID IS NULL)
OR     (STG.ACTION_CD <> 'D'
        AND (   COALESCE (CUR.SORT_CD, '~') <> COALESCE (STG.SORT_CD, '~')
             OR COALESCE (CUR.ACCT_NR, '~') <> COALESCE (STG.ACCT_NR, '~')
             OR COALESCE (CUR.PRDT_CD, '~') <> COALESCE (STG.PRDT_CD, '~')
             OR COALESCE (CUR.CCY_CD, '~') <> COALESCE (STG.CCY_CD, '~')
             OR COALESCE (CUR.OPEN_DT, DATE '0001-01-01') <> COALESCE (STG.OPEN_DT, DATE '0001-01-01')
             OR COALESCE (CUR.CLOSE_DT, DATE '0001-01-01') <> COALESCE (STG.CLOSE_DT, DATE '0001-01-01')
             OR COALESCE (CUR.ACCT_STATUS_CD, '~') <> COALESCE (STG.ACCT_STATUS_CD, '~')
             OR COALESCE (CUR.PRIMARY_PARTY_ID, '~') <> COALESCE (STG.PRIMARY_PARTY_ID, '~')
             OR COALESCE (CUR.OD_LIMIT_AMT, -1) <> COALESCE (STG.OD_LIMIT_AMT, -1)
             OR COALESCE (CUR.OPEN_CHNL_CD, '~') <> COALESCE (STG.OPEN_CHNL_CD, '~')
            )
       )
;

-- Databricks conversion: refresh column statistics after the load.
ANALYZE TABLE VT_ACCT_CHG COMPUTE STATISTICS FOR COLUMNS ACCT_ID;


/**************************************************************************\
* ACCOUNT: CLOSE THE OPEN HISTORY VERSION                                  *
\**************************************************************************/


-- Databricks conversion: MERGE replaces Teradata UPDATE FROM.
MERGE INTO `<DB_ENV>DB_ODS`.ACCT_HIST AS HST
USING (SELECT CHG.ACCT_ID, TTS.TMS
       FROM VT_ACCT_CHG AS CHG
       CROSS JOIN `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS AS TTS) AS SRC
ON HST.ACCT_ID = SRC.ACCT_ID
AND HST.END_DT IS NULL
WHEN MATCHED THEN UPDATE SET
  END_DT = CASE WHEN HST.START_DT < CAST(SRC.TMS AS DATE)
                THEN CAST(SRC.TMS AS DATE) - 1
                ELSE CAST(SRC.TMS AS DATE) END,
  CO_UPD_TMS = CAST(SRC.TMS AS TIMESTAMP_NTZ);


/**************************************************************************\
* ACCOUNT: WRITE NEW HISTORY VERSIONS                                      *
\**************************************************************************/


INSERT INTO `<DB_ENV>DB_ODS`.ACCT_HIST
(
       ACCT_ID,
       START_DT,
       UPD_TMS,
       END_DT,
       SORT_CD,
       ACCT_NR,
       PRDT_CD,
       CCY_CD,
       OPEN_DT,
       CLOSE_DT,
       ACCT_STATUS_CD,
       PRIMARY_PARTY_ID,
       OD_LIMIT_AMT,
       LAST_CUST_ACTV_DT,
       OPEN_CHNL_CD,
       ACTION_CD,
       CO_UPD_TMS
)
SELECT STG.ACCT_ID,
       CAST (TTS.TMS AS DATE),
       CAST (TTS.TMS AS TIMESTAMP_NTZ),
       NULL,
       STG.SORT_CD,
       STG.ACCT_NR,
       STG.PRDT_CD,
       STG.CCY_CD,
       STG.OPEN_DT,
       STG.CLOSE_DT,
       STG.ACCT_STATUS_CD,
       STG.PRIMARY_PARTY_ID,
       STG.OD_LIMIT_AMT,
       STG.LAST_CUST_ACTV_DT,
       STG.OPEN_CHNL_CD,
       CHG.CHG_TYP_CD,
       CAST (TTS.TMS AS TIMESTAMP_NTZ)
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.KYC_ACCT_STG   STG
       INNER JOIN
       VT_ACCT_CHG         CHG
          ON  CHG.ACCT_ID    = STG.ACCT_ID
          AND CHG.CHG_TYP_CD IN ('N', 'U')
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS   TTS

UNION ALL

SELECT CUR.ACCT_ID,
       CAST (TTS.TMS AS DATE),
       CAST (TTS.TMS AS TIMESTAMP_NTZ),
       CAST (TTS.TMS AS DATE),
       CUR.SORT_CD,
       CUR.ACCT_NR,
       CUR.PRDT_CD,
       CUR.CCY_CD,
       CUR.OPEN_DT,
       COALESCE (CUR.CLOSE_DT, CAST (TTS.TMS AS DATE)),
       'C',
       CUR.PRIMARY_PARTY_ID,
       CUR.OD_LIMIT_AMT,
       CUR.LAST_CUST_ACTV_DT,
       CUR.OPEN_CHNL_CD,
       'D',
       CAST (TTS.TMS AS TIMESTAMP_NTZ)
FROM   `<DB_ENV>DB_ODS`.ACCT    CUR
       INNER JOIN
       VT_ACCT_CHG   CHG
          ON  CHG.ACCT_ID    = CUR.ACCT_ID
          AND CHG.CHG_TYP_CD = 'D'
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS   TTS
;


/**************************************************************************\
* ACCOUNT: APPLY TO THE CURRENT TABLE                                      *
\**************************************************************************/

-- Databricks conversion: atomic SQL procedure preserves the BT/ET transaction boundary.
CREATE OR REPLACE PROCEDURE apply_account_changes_txn()
LANGUAGE SQL
SQL SECURITY DEFINER
AS BEGIN ATOMIC
DELETE FROM `<DB_ENV>DB_ODS`.ACCT
WHERE  ACCT_ID IN (SELECT ACCT_ID FROM VT_ACCT_CHG WHERE CHG_TYP_CD IN ('N', 'U'))
;


INSERT INTO `<DB_ENV>DB_ODS`.ACCT
(
       ACCT_ID,
       SORT_CD,
       ACCT_NR,
       PRDT_CD,
       CCY_CD,
       OPEN_DT,
       CLOSE_DT,
       ACCT_STATUS_CD,
       PRIMARY_PARTY_ID,
       OD_LIMIT_AMT,
       LAST_CUST_ACTV_DT,
       OPEN_CHNL_CD,
       CO_UPD_TMS
)
SELECT STG.ACCT_ID,
       STG.SORT_CD,
       STG.ACCT_NR,
       STG.PRDT_CD,
       STG.CCY_CD,
       STG.OPEN_DT,
       STG.CLOSE_DT,
       STG.ACCT_STATUS_CD,
       STG.PRIMARY_PARTY_ID,
       STG.OD_LIMIT_AMT,
       STG.LAST_CUST_ACTV_DT,
       STG.OPEN_CHNL_CD,
       CAST (TTS.TMS AS TIMESTAMP_NTZ)
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.KYC_ACCT_STG   STG
       INNER JOIN
       VT_ACCT_CHG         CHG
          ON  CHG.ACCT_ID    = STG.ACCT_ID
          AND CHG.CHG_TYP_CD IN ('N', 'U')
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS   TTS
;


-- Databricks conversion: MERGE replaces Teradata UPDATE FROM.
MERGE INTO `<DB_ENV>DB_ODS`.ACCT AS ACC
USING (SELECT CHG.ACCT_ID, TTS.TMS
       FROM VT_ACCT_CHG AS CHG
       CROSS JOIN `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS AS TTS
       WHERE CHG.CHG_TYP_CD = 'D') AS SRC
ON ACC.ACCT_ID = SRC.ACCT_ID
WHEN MATCHED THEN UPDATE SET
  ACCT_STATUS_CD = 'C',
  CLOSE_DT = COALESCE(ACC.CLOSE_DT, CAST(SRC.TMS AS DATE)),
  CO_UPD_TMS = CAST(SRC.TMS AS TIMESTAMP_NTZ);

END;
-- Databricks conversion: invoke the atomic account change transaction.
CALL apply_account_changes_txn();


/**************************************************************************\
* ACCOUNT: REFRESH LAST CUSTOMER ACTIVITY DATE (NO HISTORY)                *
* ------------------------------------------------------------------------ *
* Dormancy (amlmon.20 rule DORMREAC) depends on this date.                 *
\**************************************************************************/


-- Databricks conversion: MERGE replaces Teradata UPDATE FROM.
MERGE INTO `<DB_ENV>DB_ODS`.ACCT AS ACC
USING `<DB_ENV>DB_TRANS_IMPORTS`.KYC_ACCT_STG AS STG
ON ACC.ACCT_ID = STG.ACCT_ID
AND STG.ACTION_CD <> 'D'
AND COALESCE(ACC.LAST_CUST_ACTV_DT, DATE '0001-01-01') <> COALESCE(STG.LAST_CUST_ACTV_DT, DATE '0001-01-01')
WHEN MATCHED THEN UPDATE SET LAST_CUST_ACTV_DT = STG.LAST_CUST_ACTV_DT;

-- Databricks conversion: refresh column statistics after the load.
ANALYZE TABLE `<DB_ENV>DB_ODS`.ACCT COMPUTE STATISTICS FOR COLUMNS ACCT_ID;
-- Databricks conversion: refresh column statistics after the load.
ANALYZE TABLE `<DB_ENV>DB_ODS`.ACCT COMPUTE STATISTICS FOR COLUMNS PRIMARY_PARTY_ID;
-- Databricks conversion: refresh column statistics after the load.
ANALYZE TABLE `<DB_ENV>DB_ODS`.ACCT_HIST COMPUTE STATISTICS FOR COLUMNS ACCT_ID, START_DT, UPD_TMS;


/**************************************************************************\
* PARTY / ACCOUNT RELATIONSHIP                                             *
* ------------------------------------------------------------------------ *
* Skipped when the delivery contains no PA records (weekend files).        *
\**************************************************************************/

-- TODO: manual review required — BTEQ .GOTO LABEL control flow → Workflows DAG
-- The skipped DML is retained because an empty staging source makes it a semantic no-op.


/**************************************************************************\
* RELATIONSHIP: END-DATE REMOVED ROLES                                     *
\**************************************************************************/


-- Databricks conversion: MERGE replaces Teradata UPDATE FROM.
MERGE INTO `<DB_ENV>DB_ODS`.PARTY_ACCT_REL AS REL
USING (SELECT STG.*, TTS.TMS
       FROM `<DB_ENV>DB_TRANS_IMPORTS`.KYC_PTAC_STG AS STG
       CROSS JOIN `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS AS TTS
       WHERE STG.ACTION_CD = 'D'
          OR COALESCE(STG.END_DT, DATE '9999-12-31') < DATE '9999-12-31') AS SRC
ON REL.PARTY_ID = SRC.PARTY_ID
AND REL.ACCT_ID = SRC.ACCT_ID
AND REL.ROLE_CD = SRC.ROLE_CD
AND REL.END_DT = DATE '9999-12-31'
WHEN MATCHED THEN UPDATE SET
  END_DT = COALESCE(SRC.END_DT, CAST(SRC.TMS AS DATE)),
  CO_UPD_TMS = CAST(SRC.TMS AS TIMESTAMP_NTZ);


/**************************************************************************\
* RELATIONSHIP: UPDATE OWNERSHIP OF OPEN ROLES                             *
\**************************************************************************/


-- Databricks conversion: MERGE replaces Teradata UPDATE FROM.
MERGE INTO `<DB_ENV>DB_ODS`.PARTY_ACCT_REL AS REL
USING (SELECT STG.*, TTS.TMS
       FROM `<DB_ENV>DB_TRANS_IMPORTS`.KYC_PTAC_STG AS STG
       CROSS JOIN `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS AS TTS
       WHERE STG.ACTION_CD <> 'D') AS SRC
ON REL.PARTY_ID = SRC.PARTY_ID
AND REL.ACCT_ID = SRC.ACCT_ID
AND REL.ROLE_CD = SRC.ROLE_CD
AND REL.END_DT = DATE '9999-12-31'
AND COALESCE(REL.OWNERSHIP_PCT, -1) <> COALESCE(SRC.OWNERSHIP_PCT, -1)
WHEN MATCHED THEN UPDATE SET
  OWNERSHIP_PCT = SRC.OWNERSHIP_PCT,
  CO_UPD_TMS = CAST(SRC.TMS AS TIMESTAMP_NTZ);


/**************************************************************************\
* RELATIONSHIP: INSERT NEW ROLES                                           *
\**************************************************************************/


INSERT INTO `<DB_ENV>DB_ODS`.PARTY_ACCT_REL
(
       PARTY_ID,
       ACCT_ID,
       ROLE_CD,
       START_DT,
       END_DT,
       OWNERSHIP_PCT,
       CO_UPD_TMS
)
SELECT STG.PARTY_ID,
       STG.ACCT_ID,
       STG.ROLE_CD,
       COALESCE (STG.START_DT, CAST (TTS.TMS AS DATE)),
       COALESCE (STG.END_DT, DATE '9999-12-31'),
       STG.OWNERSHIP_PCT,
       CAST (TTS.TMS AS TIMESTAMP_NTZ)
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.KYC_PTAC_STG   STG
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS   TTS
WHERE  STG.ACTION_CD <> 'D'
AND    NOT EXISTS
       (SELECT 1
        FROM   `<DB_ENV>DB_ODS`.PARTY_ACCT_REL   REL
        WHERE  REL.PARTY_ID = STG.PARTY_ID
        AND    REL.ACCT_ID  = STG.ACCT_ID
        AND    REL.ROLE_CD  = STG.ROLE_CD
        AND    (   REL.END_DT   = DATE '9999-12-31'
                OR REL.START_DT = COALESCE (STG.START_DT, CAST (TTS.TMS AS DATE))
               )
       )
;



/**************************************************************************\
* RELATIONSHIP: END-DATE ROLES ON CLOSED ACCOUNTS                          *
\**************************************************************************/


-- Databricks conversion: MERGE replaces Teradata UPDATE FROM.
MERGE INTO `<DB_ENV>DB_ODS`.PARTY_ACCT_REL AS REL
USING (SELECT CHG.ACCT_ID, TTS.TMS
       FROM VT_ACCT_CHG AS CHG
       CROSS JOIN `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS AS TTS
       WHERE CHG.CHG_TYP_CD = 'D') AS SRC
ON REL.ACCT_ID = SRC.ACCT_ID
AND REL.END_DT = DATE '9999-12-31'
WHEN MATCHED THEN UPDATE SET
  END_DT = CAST(SRC.TMS AS DATE),
  CO_UPD_TMS = CAST(SRC.TMS AS TIMESTAMP_NTZ);

-- Databricks conversion: refresh column statistics after the load.
ANALYZE TABLE `<DB_ENV>DB_ODS`.PARTY_ACCT_REL COMPUTE STATISTICS FOR COLUMNS PARTY_ID, ACCT_ID, ROLE_CD, START_DT;
-- Databricks conversion: refresh column statistics after the load.
ANALYZE TABLE `<DB_ENV>DB_ODS`.PARTY_ACCT_REL COMPUTE STATISTICS FOR COLUMNS ACCT_ID;


/**************************************************************************\
* PARTY ALIAS                                                              *
* ------------------------------------------------------------------------ *
* Aliases are screened against the sanctions list by the customer screening *
* process. ALIAS_NORM_NM uses the same normalisation as kycref.60 and      *
* dailytxn.08 - DO NOT CHANGE ONE WITHOUT THE OTHERS.                      *
\**************************************************************************/

-- TODO: manual review required — BTEQ .GOTO LABEL control flow → Workflows DAG
-- The skipped DML is retained because an empty staging source makes it a semantic no-op.

-- Databricks conversion: correlated EXISTS replaces Teradata multi-column IN deletion.
DELETE FROM `<DB_ENV>DB_ODS`.PARTY_ALIAS AS TGT
WHERE EXISTS (
  SELECT 1
  FROM `<DB_ENV>DB_TRANS_IMPORTS`.KYC_ALIAS_STG AS STG
  WHERE STG.PARTY_ID = TGT.PARTY_ID
    AND STG.ALIAS_SEQ_NR = TGT.ALIAS_SEQ_NR
);


INSERT INTO `<DB_ENV>DB_ODS`.PARTY_ALIAS
(
       PARTY_ID,
       ALIAS_SEQ_NR,
       ALIAS_NM,
       ALIAS_NORM_NM,
       ALIAS_TYP_CD,
       CO_UPD_TMS
)
SELECT STG.PARTY_ID,
       STG.ALIAS_SEQ_NR,
       STG.ALIAS_NM,
       TRIM (REPLACE (REPLACE (TRANSLATE (UPPER (TRIM (STG.ALIAS_NM)), '.,''-&/()', '        '), '  ', ' '), '  ', ' ')),
       STG.ALIAS_TYP_CD,
       CAST (TTS.TMS AS TIMESTAMP_NTZ)
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.KYC_ALIAS_STG   STG
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS   TTS
WHERE  STG.ACTION_CD <> 'D'
AND    STG.ALIAS_NM IS NOT NULL
;


-- Databricks conversion: refresh column statistics after the load.
ANALYZE TABLE `<DB_ENV>DB_ODS`.PARTY_ALIAS COMPUTE STATISTICS FOR COLUMNS PARTY_ID, ALIAS_SEQ_NR;


/**************************************************************************\
* POPULATE PARTY_SNAPSHOT                                                  *
\**************************************************************************/


DELETE FROM `<DB_ENV>DB_ODS`.PARTY_SNAPSHOT

; INSERT INTO `<DB_ENV>DB_ODS`.PARTY_SNAPSHOT
(
       PARTY_ID,
       PARTY_TYP_CD,
       SEGMENT_CD,
       RISK_RATING_CD,
       PEP_IND,
       RESIDENCE_CTRY_CD,
       SIC_CD,
       KYC_STATUS_CD,
       EXP_MTH_TURNOVER_AMT,
       ONBOARD_DT
)
SELECT PARTY_ID,
       PARTY_TYP_CD,
       SEGMENT_CD,
       RISK_RATING_CD,
       PEP_IND,
       RESIDENCE_CTRY_CD,
       SIC_CD,
       KYC_STATUS_CD,
       EXP_MTH_TURNOVER_AMT,
       ONBOARD_DT
FROM   `<DB_ENV>DB_ODS`.PARTY
;

-- Databricks conversion: refresh column statistics after the load.
ANALYZE TABLE `<DB_ENV>DB_ODS`.PARTY_SNAPSHOT COMPUTE STATISTICS FOR COLUMNS PARTY_ID;


/**************************************************************************\
* POPULATE ACCT_SNAPSHOT                                                   *
* ------------------------------------------------------------------------ *
* Placeholder rows (PLACEHOLDER_IND = 'Y') are created by dailytxn.06 for  *
* accounts seen in transactions before KYCSYS delivered them. They are kept *
* until the real account arrives and then replaced.                        *
\**************************************************************************/


DELETE FROM `<DB_ENV>DB_ODS`.ACCT_SNAPSHOT
WHERE  PLACEHOLDER_IND = 'N'
OR     ACCT_ID IN (SELECT ACCT_ID FROM `<DB_ENV>DB_ODS`.ACCT)
;


INSERT INTO `<DB_ENV>DB_ODS`.ACCT_SNAPSHOT
(
       ACCT_ID,
       PRIMARY_PARTY_ID,
       PRDT_CD,
       SEGMENT_CD,
       ACCT_STATUS_CD,
       OPEN_DT,
       LAST_CUST_ACTV_DT,
       PLACEHOLDER_IND
)
SELECT ACC.ACCT_ID,
       ACC.PRIMARY_PARTY_ID,
       ACC.PRDT_CD,
       COALESCE (PTY.SEGMENT_CD, PRD.SEGMENT_CD, 'RET'),
       ACC.ACCT_STATUS_CD,
       ACC.OPEN_DT,
       ACC.LAST_CUST_ACTV_DT,
       'N'
FROM   `<DB_ENV>DB_ODS`.ACCT              ACC
       LEFT OUTER JOIN
       `<DB_ENV>DB_ODS`.PARTY_SNAPSHOT    PTY
          ON  PTY.PARTY_ID = ACC.PRIMARY_PARTY_ID
       LEFT OUTER JOIN
       `<DB_ENV>DB_ODS`.PRDT_SNAPSHOT     PRD
          ON  PRD.PRDT_CD  = ACC.PRDT_CD
;

-- Databricks conversion: refresh column statistics after the load.
ANALYZE TABLE `<DB_ENV>DB_ODS`.ACCT_SNAPSHOT COMPUTE STATISTICS FOR COLUMNS ACCT_ID;
-- Databricks conversion: refresh column statistics after the load.
ANALYZE TABLE `<DB_ENV>DB_ODS`.ACCT_SNAPSHOT COMPUTE STATISTICS FOR COLUMNS PRIMARY_PARTY_ID;


/**************************************************************************\
* DATA QUALITY: HOUSEKEEPING                                               *
* ------------------------------------------------------------------------ *
* Error log entries are retained for 90 days.                              *
\**************************************************************************/


DELETE FROM `<DB_ENV>DB_STREAM_DATA`.INFO_KYC_ERROR_LOG
WHERE  ERR_TMS < CURRENT_TIMESTAMP - INTERVAL '90' DAY
;


/**************************************************************************\
* DATA QUALITY 101: UNKNOWN PRIMARY PARTY                                  *
\**************************************************************************/


INSERT INTO `<DB_ENV>DB_STREAM_DATA`.INFO_KYC_ERROR_LOG
(
       ERR_AID,
       ERR_NR,
       ERR_CLASS,
       ERR_KEY,
       ERR_FIELD,
       ERR_TABLE,
       ERR_TMS,
       ERR_PGM_SOURCE,
       ERR_DESC
)
SELECT MXA.MAX_AID + SUM(1) OVER (ORDER BY ACC.ACCT_ID ROWS UNBOUNDED PRECEDING),
       101,
       'REFERENTIAL',
       ACC.ACCT_ID,
       'PRIMARY_PARTY_ID',
       'ACCT',
       CAST (TTS.TMS AS TIMESTAMP_NTZ),
       'kycref.55.KYCSYS',
       'Primary party ' || COALESCE (TRIM (ACC.PRIMARY_PARTY_ID), '<blank>') || ' not known to KYCSYS'
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.KYC_ACCT_STG   ACC
       LEFT OUTER JOIN
       `<DB_ENV>DB_ODS`.PARTY_SNAPSHOT   PTY
          ON  PTY.PARTY_ID = ACC.PRIMARY_PARTY_ID
       CROSS JOIN
       (SELECT COALESCE (MAX (ERR_AID), 0)   AS MAX_AID
        FROM   `<DB_ENV>DB_STREAM_DATA`.INFO_KYC_ERROR_LOG
       )   MXA
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS   TTS
WHERE  PTY.PARTY_ID IS NULL
AND    ACC.ACTION_CD <> 'D'
;


/**************************************************************************\
* DATA QUALITY 102: PEP WITHOUT ENHANCED DUE DILIGENCE                     *
\**************************************************************************/


INSERT INTO `<DB_ENV>DB_STREAM_DATA`.INFO_KYC_ERROR_LOG
(
       ERR_AID,
       ERR_NR,
       ERR_CLASS,
       ERR_KEY,
       ERR_FIELD,
       ERR_TABLE,
       ERR_TMS,
       ERR_PGM_SOURCE,
       ERR_DESC
)
SELECT MXA.MAX_AID + SUM(1) OVER (ORDER BY OVR.PARTY_ID ROWS UNBOUNDED PRECEDING),
       102,
       'REGULATORY',
       OVR.PARTY_ID,
       'CDD_LEVEL_CD',
       'PARTY',
       CAST (TTS.TMS AS TIMESTAMP_NTZ),
       'kycref.55.KYCSYS',
       'PEP delivered with CDD level ' || TRIM (COALESCE (OVR.ORIG_CDD_LEVEL_CD, '<blank>')) || ' - overridden to EDD'
FROM   VT_PEP_CDD_OVERRIDE   OVR
       CROSS JOIN
       (SELECT COALESCE (MAX (ERR_AID), 0)   AS MAX_AID
        FROM   `<DB_ENV>DB_STREAM_DATA`.INFO_KYC_ERROR_LOG
       )   MXA
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS   TTS
WHERE  1 = 1
;


/**************************************************************************\
* DATA QUALITY 103: KYC REVIEW OVERDUE (LOGGED ONCE PER 30 DAYS)           *
\**************************************************************************/


INSERT INTO `<DB_ENV>DB_STREAM_DATA`.INFO_KYC_ERROR_LOG
(
       ERR_AID,
       ERR_NR,
       ERR_CLASS,
       ERR_KEY,
       ERR_FIELD,
       ERR_TABLE,
       ERR_TMS,
       ERR_PGM_SOURCE,
       ERR_DESC
)
SELECT MXA.MAX_AID + SUM(1) OVER (ORDER BY PTY.PARTY_ID ROWS UNBOUNDED PRECEDING),
       103,
       'REGULATORY',
       PTY.PARTY_ID,
       'KYC_REVIEW_DUE_DT',
       'PARTY',
       CAST (TTS.TMS AS TIMESTAMP_NTZ),
       'kycref.55.KYCSYS',
       'KYC periodic review overdue since ' || DATE_FORMAT(PTY.KYC_REVIEW_DUE_DT, 'yyyy-MM-dd')
FROM   `<DB_ENV>DB_ODS`.PARTY   PTY
       CROSS JOIN
       (SELECT COALESCE (MAX (ERR_AID), 0)   AS MAX_AID
        FROM   `<DB_ENV>DB_STREAM_DATA`.INFO_KYC_ERROR_LOG
       )   MXA
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS   TTS
WHERE  PTY.KYC_REVIEW_DUE_DT < CAST (TTS.TMS AS DATE)
AND    PTY.CLOSED_IND = 'N'
AND    NOT EXISTS
       (SELECT 1
        FROM   `<DB_ENV>DB_STREAM_DATA`.INFO_KYC_ERROR_LOG   ELG
        WHERE  ELG.ERR_NR  = 103
        AND    ELG.ERR_KEY = PTY.PARTY_ID
        AND    ELG.ERR_TMS > CURRENT_TIMESTAMP - INTERVAL '30' DAY
       )
;


/**************************************************************************\
* DATA QUALITY 104: UNKNOWN NATIONALITY                                    *
\**************************************************************************/


INSERT INTO `<DB_ENV>DB_STREAM_DATA`.INFO_KYC_ERROR_LOG
(
       ERR_AID,
       ERR_NR,
       ERR_CLASS,
       ERR_KEY,
       ERR_FIELD,
       ERR_TABLE,
       ERR_TMS,
       ERR_PGM_SOURCE,
       ERR_DESC
)
SELECT MXA.MAX_AID + SUM(1) OVER (ORDER BY STG.PARTY_ID ROWS UNBOUNDED PRECEDING),
       104,
       'REFERENCE',
       STG.PARTY_ID,
       'NATIONALITY_CD',
       'PARTY',
       CAST (TTS.TMS AS TIMESTAMP_NTZ),
       'kycref.55.KYCSYS',
       'Unknown nationality country ' || TRIM (STG.NATIONALITY_CD)
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.KYC_PARTY_STG   STG
       LEFT OUTER JOIN
       `<DB_ENV>DB_ODS`.CTRY_SNAPSHOT   CTR
          ON  CTR.CTRY_2_CD = STG.NATIONALITY_CD
       CROSS JOIN
       (SELECT COALESCE (MAX (ERR_AID), 0)   AS MAX_AID
        FROM   `<DB_ENV>DB_STREAM_DATA`.INFO_KYC_ERROR_LOG
       )   MXA
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS   TTS
WHERE  STG.NATIONALITY_CD IS NOT NULL
AND    CTR.CTRY_2_CD IS NULL
AND    STG.ACTION_CD <> 'D'
;


/**************************************************************************\
* DATA QUALITY 105: UNKNOWN COUNTRY OF RESIDENCE                           *
\**************************************************************************/


INSERT INTO `<DB_ENV>DB_STREAM_DATA`.INFO_KYC_ERROR_LOG
(
       ERR_AID,
       ERR_NR,
       ERR_CLASS,
       ERR_KEY,
       ERR_FIELD,
       ERR_TABLE,
       ERR_TMS,
       ERR_PGM_SOURCE,
       ERR_DESC
)
SELECT MXA.MAX_AID + SUM(1) OVER (ORDER BY STG.PARTY_ID ROWS UNBOUNDED PRECEDING),
       105,
       'REFERENCE',
       STG.PARTY_ID,
       'RESIDENCE_CTRY_CD',
       'PARTY',
       CAST (TTS.TMS AS TIMESTAMP_NTZ),
       'kycref.55.KYCSYS',
       'Unknown country of residence ' || TRIM (STG.RESIDENCE_CTRY_CD)
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.KYC_PARTY_STG   STG
       LEFT OUTER JOIN
       `<DB_ENV>DB_ODS`.CTRY_SNAPSHOT   CTR
          ON  CTR.CTRY_2_CD = STG.RESIDENCE_CTRY_CD
       CROSS JOIN
       (SELECT COALESCE (MAX (ERR_AID), 0)   AS MAX_AID
        FROM   `<DB_ENV>DB_STREAM_DATA`.INFO_KYC_ERROR_LOG
       )   MXA
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS   TTS
WHERE  STG.RESIDENCE_CTRY_CD IS NOT NULL
AND    CTR.CTRY_2_CD IS NULL
AND    STG.ACTION_CD <> 'D'
;


/**************************************************************************\
* DATA QUALITY 106: UNKNOWN PRODUCT                                        *
\**************************************************************************/


INSERT INTO `<DB_ENV>DB_STREAM_DATA`.INFO_KYC_ERROR_LOG
(
       ERR_AID,
       ERR_NR,
       ERR_CLASS,
       ERR_KEY,
       ERR_FIELD,
       ERR_TABLE,
       ERR_TMS,
       ERR_PGM_SOURCE,
       ERR_DESC
)
SELECT MXA.MAX_AID + SUM(1) OVER (ORDER BY STG.ACCT_ID ROWS UNBOUNDED PRECEDING),
       106,
       'REFERENCE',
       STG.ACCT_ID,
       'PRDT_CD',
       'ACCT',
       CAST (TTS.TMS AS TIMESTAMP_NTZ),
       'kycref.55.KYCSYS',
       'Unknown product code ' || COALESCE (TRIM (STG.PRDT_CD), '<blank>')
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.KYC_ACCT_STG   STG
       LEFT OUTER JOIN
       `<DB_ENV>DB_ODS`.PRDT_SNAPSHOT   PRD
          ON  PRD.PRDT_CD = STG.PRDT_CD
       CROSS JOIN
       (SELECT COALESCE (MAX (ERR_AID), 0)   AS MAX_AID
        FROM   `<DB_ENV>DB_STREAM_DATA`.INFO_KYC_ERROR_LOG
       )   MXA
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS   TTS
WHERE  PRD.PRDT_CD IS NULL
AND    STG.ACTION_CD <> 'D'
;


/**************************************************************************\
* DATA QUALITY 107: ACCOUNT WITHOUT RELATIONSHIP                           *
\**************************************************************************/


INSERT INTO `<DB_ENV>DB_STREAM_DATA`.INFO_KYC_ERROR_LOG
(
       ERR_AID,
       ERR_NR,
       ERR_CLASS,
       ERR_KEY,
       ERR_FIELD,
       ERR_TABLE,
       ERR_TMS,
       ERR_PGM_SOURCE,
       ERR_DESC
)
SELECT MXA.MAX_AID + SUM(1) OVER (ORDER BY ACC.ACCT_ID ROWS UNBOUNDED PRECEDING),
       107,
       'REFERENTIAL',
       ACC.ACCT_ID,
       'ACCT_ID',
       'PARTY_ACCT_REL',
       CAST (TTS.TMS AS TIMESTAMP_NTZ),
       'kycref.55.KYCSYS',
       'Open account without any open party relationship'
FROM   `<DB_ENV>DB_ODS`.ACCT   ACC
       INNER JOIN
       VT_ACCT_CHG   CHG
          ON  CHG.ACCT_ID = ACC.ACCT_ID
       CROSS JOIN
       (SELECT COALESCE (MAX (ERR_AID), 0)   AS MAX_AID
        FROM   `<DB_ENV>DB_STREAM_DATA`.INFO_KYC_ERROR_LOG
       )   MXA
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS   TTS
WHERE  ACC.ACCT_STATUS_CD <> 'C'
AND    NOT EXISTS
       (SELECT 1
        FROM   `<DB_ENV>DB_ODS`.PARTY_ACCT_REL   REL
        WHERE  REL.ACCT_ID = ACC.ACCT_ID
        AND    REL.END_DT  = DATE '9999-12-31'
       )
;


/**************************************************************************\
* DATA QUALITY 108: HIGH RISK PARTY WITHOUT EDD                            *
\**************************************************************************/


INSERT INTO `<DB_ENV>DB_STREAM_DATA`.INFO_KYC_ERROR_LOG
(
       ERR_AID,
       ERR_NR,
       ERR_CLASS,
       ERR_KEY,
       ERR_FIELD,
       ERR_TABLE,
       ERR_TMS,
       ERR_PGM_SOURCE,
       ERR_DESC
)
SELECT MXA.MAX_AID + SUM(1) OVER (ORDER BY STG.PARTY_ID ROWS UNBOUNDED PRECEDING),
       108,
       'REGULATORY',
       STG.PARTY_ID,
       'CDD_LEVEL_CD',
       'PARTY',
       CAST (TTS.TMS AS TIMESTAMP_NTZ),
       'kycref.55.KYCSYS',
       'High risk party with CDD level ' || TRIM (STG.CDD_LEVEL_CD)
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.KYC_PARTY_STG   STG
       CROSS JOIN
       (SELECT COALESCE (MAX (ERR_AID), 0)   AS MAX_AID
        FROM   `<DB_ENV>DB_STREAM_DATA`.INFO_KYC_ERROR_LOG
       )   MXA
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS   TTS
WHERE  STG.RISK_RATING_CD = 'H'
AND    STG.CDD_LEVEL_CD <> 'EDD'
AND    STG.ACTION_CD <> 'D'
;


/**************************************************************************\
* DATA QUALITY 109: UK ORGANISATION WITHOUT COMPANY NUMBER                 *
\**************************************************************************/


INSERT INTO `<DB_ENV>DB_STREAM_DATA`.INFO_KYC_ERROR_LOG
(
       ERR_AID,
       ERR_NR,
       ERR_CLASS,
       ERR_KEY,
       ERR_FIELD,
       ERR_TABLE,
       ERR_TMS,
       ERR_PGM_SOURCE,
       ERR_DESC
)
SELECT MXA.MAX_AID + SUM(1) OVER (ORDER BY STG.PARTY_ID ROWS UNBOUNDED PRECEDING),
       109,
       'REGULATORY',
       STG.PARTY_ID,
       'CO_HOUSE_NR',
       'PARTY',
       CAST (TTS.TMS AS TIMESTAMP_NTZ),
       'kycref.55.KYCSYS',
       'UK organisation without Companies House number'
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.KYC_PARTY_STG   STG
       CROSS JOIN
       (SELECT COALESCE (MAX (ERR_AID), 0)   AS MAX_AID
        FROM   `<DB_ENV>DB_STREAM_DATA`.INFO_KYC_ERROR_LOG
       )   MXA
       CROSS JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_TMS_KYCSYS   TTS
WHERE  STG.PARTY_TYP_CD = 'O'
AND    STG.INCORP_CTRY_CD = 'GB'
AND    STG.CO_HOUSE_NR IS NULL
AND    STG.ACTION_CD <> 'D'
;

-- Databricks conversion: refresh column statistics after the load.
ANALYZE TABLE `<DB_ENV>DB_STREAM_DATA`.INFO_KYC_ERROR_LOG COMPUTE STATISTICS FOR COLUMNS ERR_AID;


/**************************************************************************\
* DROP VOLATILE TABLES                                                     *
\**************************************************************************/

-- Databricks conversion: drop the converted session-scoped temporary tables.
DROP TEMPORARY TABLE VT_PARTY_CHG;
DROP TEMPORARY TABLE VT_ACCT_CHG;
DROP TEMPORARY TABLE VT_PEP_CDD_OVERRIDE;
DROP TEMPORARY TABLE VT_VALID_DT;


/**************************************************************************\
* END OF SCRIPT                                                            *
\**************************************************************************/

