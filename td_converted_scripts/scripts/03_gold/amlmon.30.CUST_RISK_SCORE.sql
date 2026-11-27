-- TODO: manual review required — BTEQ script → notebook / stored procedure / Workflows DAG (choose wrapper)
-- Converted as a sequential Databricks SQL script; statement errors abort execution automatically.

/**************************************************************************\
* DETERMINE THE BUSINESS DATE OF THE CURRENT LOAD                          *
\**************************************************************************/

-- Converted Teradata volatile-table CTAS to a session-scoped Databricks temporary table; stripped PI and ON COMMIT clauses.
CREATE TEMP TABLE VT_RUN_DT AS
SELECT BUSINESS_DT                 AS RUN_DT,
       LOAD_TMS                    AS LOAD_TMS
FROM   DLYTXN_LOAD_TMS
WHERE  SSQ_ID = 1;

SELECT RUN_DT
FROM   VT_RUN_DT;

-- Converted the BTEQ ACTIVITYCOUNT guard to an explicit SQL assertion.
SELECT assert_true(COUNT(*) > 0, 'No business date found; source exit code 8')
FROM VT_RUN_DT;


/**************************************************************************\
* CHECK THE RISK MODEL REFERENCE DATA                                      *
* ------------------------------------------------------------------------ *
* Without factor weights or risk bands every customer would be scored as  *
* low risk. The step aborts instead.                                       *
\**************************************************************************/

SELECT FACTOR_CD
FROM   RISK_FACTOR_WEIGHT;

-- Converted the BTEQ ACTIVITYCOUNT guard to an explicit SQL assertion.
SELECT assert_true(COUNT(*) > 0, 'Risk factor weights are missing; source exit code 10')
FROM RISK_FACTOR_WEIGHT;

SELECT RISK_BAND_CD
FROM   RISK_BAND;

-- Converted the BTEQ ACTIVITYCOUNT guard to an explicit SQL assertion.
SELECT assert_true(COUNT(*) > 0, 'Risk bands are missing; source exit code 11')
FROM RISK_BAND;


/**************************************************************************\
* CUSTOMERS IN SCOPE                                                       *
\**************************************************************************/

-- Converted Teradata volatile-table CTAS to a session-scoped Databricks temporary table.
CREATE TEMP TABLE VT_PARTY AS
SELECT pty.PARTY_ID,
       pty.PARTY_TYP_CD,
       pty.NATIONALITY_CD,
       pty.RESIDENCE_CTRY_CD,
       pty.INCORP_CTRY_CD,
       pty.SIC_CD,
       COALESCE (pty.PEP_IND, 'N')          AS PEP_IND,
       pty.PEP_TYP_CD,
       COALESCE (pty.ADV_MEDIA_IND, 'N')    AS ADV_MEDIA_IND,
       pty.KYC_STATUS_CD,
       pty.KYC_REVIEW_DUE_DT,
       pty.SEGMENT_CD
FROM   PARTY      pty
WHERE  COALESCE (pty.CLOSED_IND, 'N') <> 'Y';

-- Removed Teradata index-statistics maintenance; Delta has no indexes and maintains table-level statistics automatically.

DELETE FROM AML_RISK_FACTOR_WRK;


/**************************************************************************\
* FACTOR RESCTRY - COUNTRY OF RESIDENCE / REGISTERED ADDRESS               *
\**************************************************************************/

-- Converted Teradata ZEROIFNULL score handling to COALESCE(expr, 0).
INSERT INTO AML_RISK_FACTOR_WRK
(
       PARTY_ID,
       FACTOR_CD,
       FACTOR_VALUE_CD,
       SCORE_PTS
)
SELECT pty.PARTY_ID,
       'RESCTRY',
       COALESCE (TRIM (ctr.CTRY_RISK_CD), 'UNKNOWN'),
       COALESCE(rfw.SCORE_PTS, 0)
FROM
       VT_PARTY                                 pty

       LEFT OUTER JOIN
       CTRY_SNAPSHOT             ctr
          ON  ctr.CTRY_2_CD = pty.RESIDENCE_CTRY_CD

       LEFT OUTER JOIN
       RISK_FACTOR_WEIGHT  rfw
          ON  rfw.FACTOR_CD       = 'RESCTRY'
          AND rfw.FACTOR_VALUE_CD = COALESCE (TRIM (ctr.CTRY_RISK_CD), 'UNKNOWN')
;


/**************************************************************************\
* FACTOR NATCTRY - NATIONALITY (INDIVIDUALS) / INCORPORATION (ENTITIES)    *
\**************************************************************************/

-- Converted Teradata ZEROIFNULL score handling to COALESCE(expr, 0).
INSERT INTO AML_RISK_FACTOR_WRK
(
       PARTY_ID,
       FACTOR_CD,
       FACTOR_VALUE_CD,
       SCORE_PTS
)
SELECT pty.PARTY_ID,
       'NATCTRY',
       COALESCE (TRIM (ctr.CTRY_RISK_CD), 'UNKNOWN'),
       COALESCE(rfw.SCORE_PTS, 0)
FROM
       VT_PARTY                                 pty

       LEFT OUTER JOIN
       CTRY_SNAPSHOT             ctr
          ON  ctr.CTRY_2_CD = CASE WHEN pty.PARTY_TYP_CD = 'O'
                                   THEN COALESCE (pty.INCORP_CTRY_CD, pty.RESIDENCE_CTRY_CD)
                                   ELSE COALESCE (pty.NATIONALITY_CD, pty.RESIDENCE_CTRY_CD)
                              END

       LEFT OUTER JOIN
       RISK_FACTOR_WEIGHT  rfw
          ON  rfw.FACTOR_CD       = 'NATCTRY'
          AND rfw.FACTOR_VALUE_CD = COALESCE (TRIM (ctr.CTRY_RISK_CD), 'UNKNOWN')
;


/**************************************************************************\
* FACTOR PEP - POLITICALLY EXPOSED PERSON BY TYPE                          *
* ------------------------------------------------------------------------ *
* DO = domestic, FO = foreign, IO = international organisation,           *
* RC = relative or close associate.                                        *
\**************************************************************************/

-- Converted Teradata ZEROIFNULL score handling to COALESCE(expr, 0).
INSERT INTO AML_RISK_FACTOR_WRK
(
       PARTY_ID,
       FACTOR_CD,
       FACTOR_VALUE_CD,
       SCORE_PTS
)
SELECT pty.PARTY_ID,
       'PEP',
       CASE WHEN pty.PEP_IND = 'Y'
            THEN COALESCE (TRIM (pty.PEP_TYP_CD), 'FO')
            ELSE 'NONE'
       END,
       COALESCE(rfw.SCORE_PTS, 0)
FROM
       VT_PARTY                                 pty

       LEFT OUTER JOIN
       RISK_FACTOR_WEIGHT  rfw
          ON  rfw.FACTOR_CD       = 'PEP'
          AND rfw.FACTOR_VALUE_CD = CASE WHEN pty.PEP_IND = 'Y'
                                         THEN COALESCE (TRIM (pty.PEP_TYP_CD), 'FO')
                                         ELSE 'NONE'
                                    END
;


/**************************************************************************\
* FACTOR OCCP - OCCUPATION / INDUSTRY (SIC) RISK                           *
\**************************************************************************/

-- Converted Teradata ZEROIFNULL score handling to COALESCE(expr, 0).
INSERT INTO AML_RISK_FACTOR_WRK
(
       PARTY_ID,
       FACTOR_CD,
       FACTOR_VALUE_CD,
       SCORE_PTS
)
SELECT pty.PARTY_ID,
       'OCCP',
       COALESCE (TRIM (sic.SIC_RISK_CD), 'UNKNOWN'),
       COALESCE(rfw.SCORE_PTS, 0)
FROM
       VT_PARTY                                 pty

       LEFT OUTER JOIN
       SIC_SNAPSHOT              sic
          ON  sic.SIC_CD = pty.SIC_CD

       LEFT OUTER JOIN
       RISK_FACTOR_WEIGHT  rfw
          ON  rfw.FACTOR_CD       = 'OCCP'
          AND rfw.FACTOR_VALUE_CD = COALESCE (TRIM (sic.SIC_RISK_CD), 'UNKNOWN')
;


/**************************************************************************\
* FACTOR PRDT - HIGHEST PRODUCT RISK ACROSS HELD ACCOUNTS                  *
* ------------------------------------------------------------------------ *
* All active relationships count (holder, joint, signatory, beneficial    *
* owner, power of attorney). Closed accounts are ignored.                  *
\**************************************************************************/

-- Converted Teradata volatile-table CTAS to a session-scoped Databricks temporary table; stripped PI and ON COMMIT clauses.
CREATE TEMP TABLE VT_PARTY_PRDT AS
SELECT rel.PARTY_ID                                       AS PARTY_ID,
       MAX (CASE prd.PRDT_RISK_CD
                 WHEN 'H' THEN 3
                 WHEN 'M' THEN 2
                 WHEN 'L' THEN 1
                 ELSE 0
            END)                                          AS PRDT_RISK_ORD
FROM
       PARTY_ACCT_REL         rel

       CROSS JOIN
       VT_RUN_DT                             rd

       INNER JOIN
       ACCT_SNAPSHOT          acs
          ON  acs.ACCT_ID = rel.ACCT_ID

       LEFT OUTER JOIN
       PRDT_SNAPSHOT          prd
          ON  prd.PRDT_CD = acs.PRDT_CD
WHERE
       rel.START_DT <= rd.RUN_DT
AND    COALESCE (rel.END_DT, DATE '9999-12-31') >= rd.RUN_DT
AND    COALESCE (acs.ACCT_STATUS_CD, 'A') <> 'C'
GROUP  BY rel.PARTY_ID
;

-- Converted Teradata ZEROIFNULL score handling to COALESCE(expr, 0).
INSERT INTO AML_RISK_FACTOR_WRK
(
       PARTY_ID,
       FACTOR_CD,
       FACTOR_VALUE_CD,
       SCORE_PTS
)
SELECT pty.PARTY_ID,
       'PRDT',
       CASE ppr.PRDT_RISK_ORD
            WHEN 3 THEN 'H'
            WHEN 2 THEN 'M'
            WHEN 1 THEN 'L'
            ELSE 'UNKNOWN'
       END,
       COALESCE(rfw.SCORE_PTS, 0)
FROM
       VT_PARTY                                 pty

       LEFT OUTER JOIN
       VT_PARTY_PRDT                            ppr
          ON  ppr.PARTY_ID = pty.PARTY_ID

       LEFT OUTER JOIN
       RISK_FACTOR_WEIGHT  rfw
          ON  rfw.FACTOR_CD       = 'PRDT'
          AND rfw.FACTOR_VALUE_CD = CASE ppr.PRDT_RISK_ORD
                                         WHEN 3 THEN 'H'
                                         WHEN 2 THEN 'M'
                                         WHEN 1 THEN 'L'
                                         ELSE 'UNKNOWN'
                                    END
;


/**************************************************************************\
* FACTOR CHNL - ONBOARDING CHANNEL                                         *
* ------------------------------------------------------------------------ *
* Channel of the first account opened. Digital channels are treated as    *
* non-face-to-face (NFTF) onboarding.                                      *
\**************************************************************************/

-- Converted Teradata volatile-table CTAS to a session-scoped Databricks temporary table; stripped PI and ON COMMIT clauses.
CREATE TEMP TABLE VT_PARTY_CHNL AS
SELECT act.PRIMARY_PARTY_ID                    AS PARTY_ID,
       act.OPEN_CHNL_CD                        AS OPEN_CHNL_CD
FROM   ACCT    act
WHERE  act.PRIMARY_PARTY_ID IS NOT NULL
QUALIFY SUM (1) OVER (PARTITION BY  act.PRIMARY_PARTY_ID
                          ORDER BY  act.OPEN_DT
                                   ,act.ACCT_ID
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;

-- Converted Teradata ZEROIFNULL score handling to COALESCE(expr, 0).
INSERT INTO AML_RISK_FACTOR_WRK
(
       PARTY_ID,
       FACTOR_CD,
       FACTOR_VALUE_CD,
       SCORE_PTS
)
SELECT pty.PARTY_ID,
       'CHNL',
       CASE WHEN chs.DIGITAL_IND = 'Y' THEN 'NFTF' ELSE 'F2F' END,
       COALESCE(rfw.SCORE_PTS, 0)
FROM
       VT_PARTY                                 pty

       LEFT OUTER JOIN
       VT_PARTY_CHNL                            pch
          ON  pch.PARTY_ID = pty.PARTY_ID

       LEFT OUTER JOIN
       CHNL_SNAPSHOT             chs
          ON  chs.CHNL_CD = pch.OPEN_CHNL_CD

       LEFT OUTER JOIN
       RISK_FACTOR_WEIGHT  rfw
          ON  rfw.FACTOR_CD       = 'CHNL'
          AND rfw.FACTOR_VALUE_CD = CASE WHEN chs.DIGITAL_IND = 'Y' THEN 'NFTF' ELSE 'F2F' END
;


/**************************************************************************\
* FACTOR ALERTS - TRANSACTION MONITORING ALERTS IN THE LAST 90 DAYS        *
* ------------------------------------------------------------------------ *
* Suppressed duplicates are not counted.                                   *
\**************************************************************************/

-- Converted Teradata ZEROIFNULL score handling to COALESCE(expr, 0).
INSERT INTO AML_RISK_FACTOR_WRK
(
       PARTY_ID,
       FACTOR_CD,
       FACTOR_VALUE_CD,
       SCORE_PTS
)
SELECT pty.PARTY_ID,
       'ALERTS',
       CASE
          WHEN COALESCE(alc.ALERT_CNT, 0) = 0 THEN '0'
          WHEN alc.ALERT_CNT <= 2             THEN '1-2'
          WHEN alc.ALERT_CNT <= 5             THEN '3-5'
          ELSE '6+'
       END,
       COALESCE(rfw.SCORE_PTS, 0)
FROM
       VT_PARTY                                 pty

       LEFT OUTER JOIN
       (
        SELECT al.PARTY_ID,
               COUNT (*)                AS ALERT_CNT
        FROM   TM_ALERT  al
               CROSS JOIN
               VT_RUN_DT                rd
        WHERE  al.BUSINESS_DT BETWEEN rd.RUN_DT - 89 AND rd.RUN_DT
        AND    al.ALERT_STATUS_CD <> 'SUPPR'
        AND    al.PARTY_ID IS NOT NULL
        GROUP  BY al.PARTY_ID
       )                                        alc
          ON  alc.PARTY_ID = pty.PARTY_ID

       LEFT OUTER JOIN
       RISK_FACTOR_WEIGHT  rfw
          ON  rfw.FACTOR_CD       = 'ALERTS'
          AND rfw.FACTOR_VALUE_CD = CASE
                                       WHEN COALESCE(alc.ALERT_CNT, 0) = 0 THEN '0'
                                       WHEN alc.ALERT_CNT <= 2             THEN '1-2'
                                       WHEN alc.ALERT_CNT <= 5             THEN '3-5'
                                       ELSE '6+'
                                    END
;


/**************************************************************************\
* FACTOR SANC - OPEN OR CONFIRMED SANCTIONS SCREENING HITS                 *
\**************************************************************************/

-- Converted Teradata ZEROIFNULL score handling to COALESCE(expr, 0).
INSERT INTO AML_RISK_FACTOR_WRK
(
       PARTY_ID,
       FACTOR_CD,
       FACTOR_VALUE_CD,
       SCORE_PTS
)
SELECT pty.PARTY_ID,
       'SANC',
       CASE WHEN sht.HIT_CNT > 0 THEN 'OPEN' ELSE 'NONE' END,
       COALESCE(rfw.SCORE_PTS, 0)
FROM
       VT_PARTY                                 pty

       LEFT OUTER JOIN
       (
        SELECT hit.PARTY_ID,
               COUNT (*)                       AS HIT_CNT
        FROM   SANC_SCREEN_HIT  hit
        WHERE  hit.HIT_STATUS_CD IN ('OPEN', 'CONF')
        AND    hit.PARTY_ID IS NOT NULL
        GROUP  BY hit.PARTY_ID
       )                                        sht
          ON  sht.PARTY_ID = pty.PARTY_ID

       LEFT OUTER JOIN
       RISK_FACTOR_WEIGHT  rfw
          ON  rfw.FACTOR_CD       = 'SANC'
          AND rfw.FACTOR_VALUE_CD = CASE WHEN sht.HIT_CNT > 0 THEN 'OPEN' ELSE 'NONE' END
;


/**************************************************************************\
* FACTOR KYC - KYC REVIEW STATUS                                           *
* ------------------------------------------------------------------------ *
* An overdue periodic review overrides the recorded status.                *
\**************************************************************************/

-- Converted Teradata ZEROIFNULL score handling to COALESCE(expr, 0).
INSERT INTO AML_RISK_FACTOR_WRK
(
       PARTY_ID,
       FACTOR_CD,
       FACTOR_VALUE_CD,
       SCORE_PTS
)
SELECT pty.PARTY_ID,
       'KYC',
       CASE WHEN pty.KYC_REVIEW_DUE_DT < rd.RUN_DT THEN 'OVERDUE'
            ELSE COALESCE (TRIM (pty.KYC_STATUS_CD), 'PE')
       END,
       COALESCE(rfw.SCORE_PTS, 0)
FROM
       VT_PARTY                                 pty

       CROSS JOIN
       VT_RUN_DT                                rd

       LEFT OUTER JOIN
       RISK_FACTOR_WEIGHT  rfw
          ON  rfw.FACTOR_CD       = 'KYC'
          AND rfw.FACTOR_VALUE_CD = CASE WHEN pty.KYC_REVIEW_DUE_DT < rd.RUN_DT THEN 'OVERDUE'
                                         ELSE COALESCE (TRIM (pty.KYC_STATUS_CD), 'PE')
                                    END
;


/**************************************************************************\
* FACTOR ADVMEDIA - ADVERSE MEDIA                                          *
\**************************************************************************/

-- Converted Teradata ZEROIFNULL score handling to COALESCE(expr, 0).
INSERT INTO AML_RISK_FACTOR_WRK
(
       PARTY_ID,
       FACTOR_CD,
       FACTOR_VALUE_CD,
       SCORE_PTS
)
SELECT pty.PARTY_ID,
       'ADVMEDIA',
       pty.ADV_MEDIA_IND,
       COALESCE(rfw.SCORE_PTS, 0)
FROM
       VT_PARTY                                 pty

       LEFT OUTER JOIN
       RISK_FACTOR_WEIGHT  rfw
          ON  rfw.FACTOR_CD       = 'ADVMEDIA'
          AND rfw.FACTOR_VALUE_CD = pty.ADV_MEDIA_IND
;

-- Removed routine Teradata statistics collection; Delta maintains table-level statistics automatically.


/**************************************************************************\
* PIVOT THE FACTORS INTO ONE SCORE ROW PER CUSTOMER                        *
\**************************************************************************/

DELETE FROM AML_RISK_SCORE_WRK
;

INSERT INTO AML_RISK_SCORE_WRK
(
       PARTY_ID,
       SCORE_DT,
       CTRY_SCORE,
       PEP_SCORE,
       OCCP_SCORE,
       PRDT_SCORE,
       CHNL_SCORE,
       ALERT_SCORE,
       SANC_SCORE,
       KYC_SCORE,
       ADV_MEDIA_SCORE,
       TOTAL_SCORE,
       RISK_BAND_CD
)
SELECT fct.PARTY_ID,
       rd.RUN_DT,
       SUM (CASE WHEN fct.FACTOR_CD IN ('RESCTRY', 'NATCTRY') THEN fct.SCORE_PTS ELSE 0 END),
       SUM (CASE WHEN fct.FACTOR_CD = 'PEP'      THEN fct.SCORE_PTS ELSE 0 END),
       SUM (CASE WHEN fct.FACTOR_CD = 'OCCP'     THEN fct.SCORE_PTS ELSE 0 END),
       SUM (CASE WHEN fct.FACTOR_CD = 'PRDT'     THEN fct.SCORE_PTS ELSE 0 END),
       SUM (CASE WHEN fct.FACTOR_CD = 'CHNL'     THEN fct.SCORE_PTS ELSE 0 END),
       SUM (CASE WHEN fct.FACTOR_CD = 'ALERTS'   THEN fct.SCORE_PTS ELSE 0 END),
       SUM (CASE WHEN fct.FACTOR_CD = 'SANC'     THEN fct.SCORE_PTS ELSE 0 END),
       SUM (CASE WHEN fct.FACTOR_CD = 'KYC'      THEN fct.SCORE_PTS ELSE 0 END),
       SUM (CASE WHEN fct.FACTOR_CD = 'ADVMEDIA' THEN fct.SCORE_PTS ELSE 0 END),
       SUM (fct.SCORE_PTS),
       NULL
FROM
       AML_RISK_FACTOR_WRK   fct

       CROSS JOIN
       VT_RUN_DT                                      rd
GROUP  BY fct.PARTY_ID,
          rd.RUN_DT
;


/**************************************************************************\
* ASSIGN THE RISK BAND                                                     *
* ------------------------------------------------------------------------ *
* Score ranges from DB_REFERENCE.RISK_BAND. Scores above the highest      *
* band are Very High, unmatched scores default to Low.                     *
\**************************************************************************/

-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO AML_RISK_SCORE_WRK AS wrk
USING RISK_BAND AS rbd
ON wrk.TOTAL_SCORE BETWEEN rbd.MIN_SCORE AND rbd.MAX_SCORE
WHEN MATCHED THEN UPDATE SET RISK_BAND_CD = rbd.RISK_BAND_CD;

-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO AML_RISK_SCORE_WRK AS wrk
USING (
        SELECT MAX(MAX_SCORE) AS MAX_SCORE
        FROM RISK_BAND
      ) AS mxb
ON wrk.RISK_BAND_CD IS NULL
WHEN MATCHED THEN UPDATE SET
  RISK_BAND_CD = CASE WHEN wrk.TOTAL_SCORE > mxb.MAX_SCORE THEN 'VH' ELSE 'L' END;


/**************************************************************************\
* REGULATORY OVERRIDES                                                     *
* ------------------------------------------------------------------------ *
* - open / confirmed sanctions match                 -> Very High          *
* - residence in a prohibited (X) jurisdiction       -> Very High          *
* - PEP (MLR 2017 reg. 35) at least                  -> High               *
\**************************************************************************/

UPDATE AML_RISK_SCORE_WRK
SET    RISK_BAND_CD = 'VH'
WHERE  SANC_SCORE > 0
;

-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO AML_RISK_SCORE_WRK AS wrk
USING AML_RISK_FACTOR_WRK AS fct
ON  fct.PARTY_ID = wrk.PARTY_ID
AND fct.FACTOR_CD = 'RESCTRY'
AND fct.FACTOR_VALUE_CD = 'X'
WHEN MATCHED THEN UPDATE SET RISK_BAND_CD = 'VH';

UPDATE AML_RISK_SCORE_WRK
SET    RISK_BAND_CD = 'H'
WHERE  PEP_SCORE > 0
AND    RISK_BAND_CD IN ('L', 'M')
;

-- Removed routine Teradata index-statistics collection; Delta has no indexes.


/**************************************************************************\
* RESET A PREVIOUS RUN OF THE SAME BUSINESS DATE                           *
* ------------------------------------------------------------------------ *
* History rows opened today are removed and the versions they closed are  *
* re-opened, so that the comparison below is always made against the      *
* state before today's run.                                                *
\**************************************************************************/

-- Converted Teradata volatile-table CTAS to a session-scoped Databricks temporary table; stripped PI and ON COMMIT clauses.
CREATE TEMP TABLE VT_RERUN_PARTY AS
SELECT hst.PARTY_ID
FROM   PARTY_RISK_SCORE_HIST   hst
       CROSS JOIN
       VT_RUN_DT                              rd
WHERE  hst.START_DT = rd.RUN_DT
GROUP  BY hst.PARTY_ID
;

DELETE FROM PARTY_RISK_SCORE_HIST
WHERE  START_DT = (SELECT RUN_DT FROM VT_RUN_DT)
;

UPDATE PARTY_RISK_SCORE_HIST
SET    END_DT = DATE '9999-12-31'
WHERE  END_DT   = (SELECT RUN_DT - 1 FROM VT_RUN_DT)
AND    PARTY_ID IN (SELECT PARTY_ID FROM VT_RERUN_PARTY)
;

DELETE FROM EDD_REVIEW_QUEUE
WHERE  TRIGGER_DT       = (SELECT RUN_DT FROM VT_RUN_DT)
AND    REVIEW_STATUS_CD = 'OPEN'
;


/**************************************************************************\
* COMPARE WITH THE CURRENT VERSION                                         *
* ------------------------------------------------------------------------ *
* CHG_TYP_CD  I = first scoring, C = score or band changed, U = unchanged *
\**************************************************************************/

-- Converted Teradata volatile-table CTAS to a session-scoped Databricks temporary table; stripped PI and ON COMMIT clauses.
CREATE TEMP TABLE VT_RISK_CMP AS
SELECT wrk.PARTY_ID,
       wrk.SCORE_DT,
       wrk.CTRY_SCORE,
       wrk.PEP_SCORE,
       wrk.OCCP_SCORE,
       wrk.PRDT_SCORE,
       wrk.CHNL_SCORE,
       wrk.ALERT_SCORE,
       wrk.SANC_SCORE,
       wrk.KYC_SCORE,
       wrk.ADV_MEDIA_SCORE,
       wrk.TOTAL_SCORE,
       wrk.RISK_BAND_CD,
       hst.RISK_BAND_CD                                           AS OLD_RISK_BAND_CD,
       hst.PEP_SCORE                                              AS OLD_PEP_SCORE,
       hst.SANC_SCORE                                             AS OLD_SANC_SCORE,
       CASE
          WHEN hst.PARTY_ID IS NULL                     THEN 'I'
          WHEN hst.RISK_BAND_CD <> wrk.RISK_BAND_CD
            OR hst.TOTAL_SCORE  <> wrk.TOTAL_SCORE      THEN 'C'
          ELSE 'U'
       END                                                        AS CHG_TYP_CD,
       CASE wrk.RISK_BAND_CD WHEN 'L'  THEN 1 WHEN 'M'  THEN 2
                             WHEN 'H'  THEN 3 WHEN 'VH' THEN 4 ELSE 0 END
                                                                  AS NEW_BAND_ORD,
       CASE hst.RISK_BAND_CD WHEN 'L'  THEN 1 WHEN 'M'  THEN 2
                             WHEN 'H'  THEN 3 WHEN 'VH' THEN 4 ELSE 0 END
                                                                  AS OLD_BAND_ORD,
       CASE
          WHEN hst.PARTY_ID IS NULL                     THEN CAST (NULL AS CHAR(2))
          WHEN hst.RISK_BAND_CD <> wrk.RISK_BAND_CD
            OR hst.TOTAL_SCORE  <> wrk.TOTAL_SCORE      THEN hst.RISK_BAND_CD
          ELSE cur.PREV_RISK_BAND_CD
       END                                                        AS PREV_RISK_BAND_CD,
       CASE
          WHEN hst.PARTY_ID IS NOT NULL
           AND hst.RISK_BAND_CD <> wrk.RISK_BAND_CD     THEN 'Y'
          ELSE 'N'
       END                                                        AS BAND_CHG_IND,
       CASE
          WHEN wrk.RISK_BAND_CD IN ('H', 'VH')
            OR wrk.PEP_SCORE > 0                        THEN 'Y'
          ELSE 'N'
       END                                                        AS EDD_REQUIRED_IND,
       CASE
          WHEN hst.PARTY_ID IS NULL
            OR hst.RISK_BAND_CD <> wrk.RISK_BAND_CD
            OR cur.NEXT_REVIEW_DT IS NULL
          THEN ADD_MONTHS (wrk.SCORE_DT, COALESCE (rbd.REVIEW_FREQ_MTHS, 36))
          ELSE cur.NEXT_REVIEW_DT
       END                                                        AS NEXT_REVIEW_DT
FROM
       AML_RISK_SCORE_WRK    wrk

       LEFT OUTER JOIN
       PARTY_RISK_SCORE_HIST           hst
          ON  hst.PARTY_ID = wrk.PARTY_ID
          AND hst.END_DT   = DATE '9999-12-31'

       LEFT OUTER JOIN
       PARTY_RISK_SCORE                cur
          ON  cur.PARTY_ID = wrk.PARTY_ID

       LEFT OUTER JOIN
       RISK_BAND                 rbd
          ON  rbd.RISK_BAND_CD = wrk.RISK_BAND_CD
;

-- Removed routine Teradata statistics collection; Delta maintains table-level statistics automatically.


/**************************************************************************\
* MAINTAIN THE RISK SCORE HISTORY (SCD TYPE 2)                             *
\**************************************************************************/

-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO PARTY_RISK_SCORE_HIST AS hst
USING (
        SELECT cmp.PARTY_ID, rd.RUN_DT, rd.LOAD_TMS
        FROM VT_RISK_CMP AS cmp
        CROSS JOIN VT_RUN_DT AS rd
        WHERE cmp.CHG_TYP_CD = 'C'
      ) AS src
ON  hst.PARTY_ID = src.PARTY_ID
AND hst.END_DT = DATE '9999-12-31'
WHEN MATCHED THEN UPDATE SET
  END_DT = src.RUN_DT - 1,
  CO_UPD_TMS = src.LOAD_TMS;

INSERT INTO PARTY_RISK_SCORE_HIST
(
       PARTY_ID,
       START_DT,
       END_DT,
       SCORE_DT,
       CTRY_SCORE,
       PEP_SCORE,
       OCCP_SCORE,
       PRDT_SCORE,
       CHNL_SCORE,
       ALERT_SCORE,
       SANC_SCORE,
       KYC_SCORE,
       ADV_MEDIA_SCORE,
       TOTAL_SCORE,
       RISK_BAND_CD,
       PREV_RISK_BAND_CD,
       BAND_CHG_IND,
       EDD_REQUIRED_IND,
       NEXT_REVIEW_DT,
       CO_UPD_TMS
)
SELECT cmp.PARTY_ID,
       rd.RUN_DT,
       DATE '9999-12-31',
       cmp.SCORE_DT,
       cmp.CTRY_SCORE,
       cmp.PEP_SCORE,
       cmp.OCCP_SCORE,
       cmp.PRDT_SCORE,
       cmp.CHNL_SCORE,
       cmp.ALERT_SCORE,
       cmp.SANC_SCORE,
       cmp.KYC_SCORE,
       cmp.ADV_MEDIA_SCORE,
       cmp.TOTAL_SCORE,
       cmp.RISK_BAND_CD,
       cmp.PREV_RISK_BAND_CD,
       cmp.BAND_CHG_IND,
       cmp.EDD_REQUIRED_IND,
       cmp.NEXT_REVIEW_DT,
       rd.LOAD_TMS
FROM
       VT_RISK_CMP                          cmp

       CROSS JOIN
       VT_RUN_DT                            rd
WHERE
       cmp.CHG_TYP_CD IN ('I', 'C')
;


/**************************************************************************\
* APPLY THE CURRENT RISK SCORE                                             *
\**************************************************************************/

MERGE INTO PARTY_RISK_SCORE   tgt
USING
(
 SELECT cmp.PARTY_ID,
        cmp.SCORE_DT,
        cmp.CTRY_SCORE,
        cmp.PEP_SCORE,
        cmp.OCCP_SCORE,
        cmp.PRDT_SCORE,
        cmp.CHNL_SCORE,
        cmp.ALERT_SCORE,
        cmp.SANC_SCORE,
        cmp.KYC_SCORE,
        cmp.ADV_MEDIA_SCORE,
        cmp.TOTAL_SCORE,
        cmp.RISK_BAND_CD,
        cmp.PREV_RISK_BAND_CD,
        cmp.BAND_CHG_IND,
        cmp.EDD_REQUIRED_IND,
        cmp.NEXT_REVIEW_DT,
        rd.LOAD_TMS
 FROM   VT_RISK_CMP   cmp
        CROSS JOIN
        VT_RUN_DT     rd
)                                             src
   ON  tgt.PARTY_ID = src.PARTY_ID
WHEN MATCHED THEN UPDATE SET
       SCORE_DT          = src.SCORE_DT,
       CTRY_SCORE        = src.CTRY_SCORE,
       PEP_SCORE         = src.PEP_SCORE,
       OCCP_SCORE        = src.OCCP_SCORE,
       PRDT_SCORE        = src.PRDT_SCORE,
       CHNL_SCORE        = src.CHNL_SCORE,
       ALERT_SCORE       = src.ALERT_SCORE,
       SANC_SCORE        = src.SANC_SCORE,
       KYC_SCORE         = src.KYC_SCORE,
       ADV_MEDIA_SCORE   = src.ADV_MEDIA_SCORE,
       TOTAL_SCORE       = src.TOTAL_SCORE,
       RISK_BAND_CD      = src.RISK_BAND_CD,
       PREV_RISK_BAND_CD = src.PREV_RISK_BAND_CD,
       BAND_CHG_IND      = src.BAND_CHG_IND,
       EDD_REQUIRED_IND  = src.EDD_REQUIRED_IND,
       NEXT_REVIEW_DT    = src.NEXT_REVIEW_DT,
       CO_UPD_TMS        = src.LOAD_TMS
WHEN NOT MATCHED THEN INSERT
(
       PARTY_ID,
       SCORE_DT,
       CTRY_SCORE,
       PEP_SCORE,
       OCCP_SCORE,
       PRDT_SCORE,
       CHNL_SCORE,
       ALERT_SCORE,
       SANC_SCORE,
       KYC_SCORE,
       ADV_MEDIA_SCORE,
       TOTAL_SCORE,
       RISK_BAND_CD,
       PREV_RISK_BAND_CD,
       BAND_CHG_IND,
       EDD_REQUIRED_IND,
       NEXT_REVIEW_DT,
       CO_UPD_TMS
)
VALUES
(
       src.PARTY_ID,
       src.SCORE_DT,
       src.CTRY_SCORE,
       src.PEP_SCORE,
       src.OCCP_SCORE,
       src.PRDT_SCORE,
       src.CHNL_SCORE,
       src.ALERT_SCORE,
       src.SANC_SCORE,
       src.KYC_SCORE,
       src.ADV_MEDIA_SCORE,
       src.TOTAL_SCORE,
       src.RISK_BAND_CD,
       src.PREV_RISK_BAND_CD,
       src.BAND_CHG_IND,
       src.EDD_REQUIRED_IND,
       src.NEXT_REVIEW_DT,
       src.LOAD_TMS
)
;

-- Removed routine Teradata statistics collection; Delta maintains table-level statistics automatically.


/**************************************************************************\
* ENHANCED DUE DILIGENCE TRIGGERS                                          *
* ------------------------------------------------------------------------ *
* BUP  = band raised to High / Very High (or first scored at that level)   *
* PEP  = customer newly identified as PEP                                  *
* SANC = new sanctions exposure                                            *
* The review is due on the 10th UK business day after the business date.   *
\**************************************************************************/

-- Converted Teradata volatile-table CTAS to a session-scoped Databricks temporary table; stripped PI and ON COMMIT clauses.
CREATE TEMP TABLE VT_EDD_DUE AS
SELECT cal.CAL_DT                          AS DUE_DT
FROM
       CALENDAR        cal

       CROSS JOIN
       VT_RUN_DT                            rd

       LEFT OUTER JOIN
       UK_BANK_HOLIDAY hol
          ON  hol.HOLIDAY_DT = cal.CAL_DT
WHERE
       cal.CAL_DT     >  rd.RUN_DT
AND    cal.CAL_DT     <= rd.RUN_DT + 31
AND    cal.BUS_DAY_IND = 'Y'
AND    hol.HOLIDAY_DT IS NULL
QUALIFY ROW_NUMBER () OVER (ORDER BY cal.CAL_DT) = 10
;

-- Converted Teradata ZEROIFNULL trigger comparisons to COALESCE(expr, 0).
INSERT INTO EDD_REVIEW_QUEUE
(
       PARTY_ID,
       TRIGGER_DT,
       TRIGGER_REASON_CD,
       RISK_BAND_CD,
       PREV_RISK_BAND_CD,
       DUE_DT,
       REVIEW_STATUS_CD,
       CO_UPD_TMS
)
SELECT trg.PARTY_ID,
       rd.RUN_DT,
       trg.TRIGGER_REASON_CD,
       trg.RISK_BAND_CD,
       trg.OLD_RISK_BAND_CD,
       COALESCE (due.DUE_DT, rd.RUN_DT + 14),
       'OPEN',
       rd.LOAD_TMS
FROM
       (
        SELECT PARTY_ID,
               'BUP'                     AS TRIGGER_REASON_CD,
               RISK_BAND_CD,
               OLD_RISK_BAND_CD
        FROM   VT_RISK_CMP
        WHERE  NEW_BAND_ORD >= 3
        AND    (   (CHG_TYP_CD = 'C' AND NEW_BAND_ORD > OLD_BAND_ORD)
                OR  CHG_TYP_CD = 'I')

        UNION ALL

        SELECT PARTY_ID,
               'PEP',
               RISK_BAND_CD,
               OLD_RISK_BAND_CD
        FROM   VT_RISK_CMP
        WHERE  PEP_SCORE > 0
        AND    COALESCE(OLD_PEP_SCORE, 0) = 0

        UNION ALL

        SELECT PARTY_ID,
               'SANC',
               RISK_BAND_CD,
               OLD_RISK_BAND_CD
        FROM   VT_RISK_CMP
        WHERE  SANC_SCORE > 0
        AND    COALESCE(OLD_SANC_SCORE, 0) = 0
       )                                    trg

       CROSS JOIN
       VT_RUN_DT                            rd

       LEFT OUTER JOIN
       VT_EDD_DUE                           due
          ON  1 = 1
WHERE
       NOT EXISTS
       (
        SELECT 1
        FROM   EDD_REVIEW_QUEUE   edd
        WHERE  edd.PARTY_ID          = trg.PARTY_ID
        AND    edd.TRIGGER_DT        = rd.RUN_DT
        AND    edd.TRIGGER_REASON_CD = trg.TRIGGER_REASON_CD
       )
;

-- Removed routine Teradata index-statistics collection; Delta has no indexes.


/**************************************************************************\
* END OF SCRIPT                                                            *
\**************************************************************************/

