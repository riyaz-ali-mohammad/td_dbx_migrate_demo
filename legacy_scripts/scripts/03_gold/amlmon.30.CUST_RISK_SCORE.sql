.set WIDTH       300;
.set TITLEDASHES OFF;

/**************************************************************************\
* DETERMINE THE BUSINESS DATE OF THE CURRENT LOAD                          *
\**************************************************************************/

CREATE VOLATILE TABLE VT_RUN_DT AS
(
SELECT BUSINESS_DT                 AS RUN_DT,
       LOAD_TMS                    AS LOAD_TMS
FROM   <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS
WHERE  SSQ_ID = 1
) WITH DATA
UNIQUE PRIMARY INDEX (RUN_DT)
ON COMMIT PRESERVE ROWS
;
.if errorcode <> 0 then .quit errorcode;

SELECT RUN_DT
FROM   VT_RUN_DT
;
.if errorcode <> 0 then .quit errorcode;
.if activitycount = 0 then .quit 8;


/**************************************************************************\
* CHECK THE RISK MODEL REFERENCE DATA                                      *
* ------------------------------------------------------------------------ *
* Without factor weights or risk bands every customer would be scored as  *
* low risk. The step aborts instead.                                       *
\**************************************************************************/

SELECT FACTOR_CD
FROM   <DB_ENV>DB_REFERENCE.RISK_FACTOR_WEIGHT
;
.if errorcode <> 0 then .quit errorcode;
.if activitycount = 0 then .quit 10;

SELECT RISK_BAND_CD
FROM   <DB_ENV>DB_REFERENCE.RISK_BAND
;
.if errorcode <> 0 then .quit errorcode;
.if activitycount = 0 then .quit 11;


/**************************************************************************\
* CUSTOMERS IN SCOPE                                                       *
\**************************************************************************/

CREATE VOLATILE TABLE VT_PARTY AS
(
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
FROM   <DB_ENV>DB_ODS.PARTY      pty
WHERE  COALESCE (pty.CLOSED_IND, 'N') <> 'Y'
) WITH DATA
UNIQUE PRIMARY INDEX (PARTY_ID)
ON COMMIT PRESERVE ROWS
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS VT_PARTY INDEX (PARTY_ID);
COLLECT STATISTICS <DB_ENV>DB_REFERENCE.RISK_FACTOR_WEIGHT INDEX (FACTOR_CD, FACTOR_VALUE_CD);
COLLECT STATISTICS <DB_ENV>DB_ODS.PARTY_ACCT_REL INDEX (ACCT_ID);
.if errorcode <> 0 then .quit errorcode;

DELETE FROM <DB_ENV>DB_TRANS_IMPORTS.AML_RISK_FACTOR_WRK
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* FACTOR RESCTRY - COUNTRY OF RESIDENCE / REGISTERED ADDRESS               *
\**************************************************************************/

INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.AML_RISK_FACTOR_WRK
(
       PARTY_ID,
       FACTOR_CD,
       FACTOR_VALUE_CD,
       SCORE_PTS
)
SELECT pty.PARTY_ID,
       'RESCTRY',
       COALESCE (TRIM (ctr.CTRY_RISK_CD), 'UNKNOWN'),
       ZEROIFNULL (rfw.SCORE_PTS)
FROM
       VT_PARTY                                 pty

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.CTRY_SNAPSHOT             ctr
          ON  ctr.CTRY_2_CD = pty.RESIDENCE_CTRY_CD

       LEFT OUTER JOIN
       <DB_ENV>DB_REFERENCE.RISK_FACTOR_WEIGHT  rfw
          ON  rfw.FACTOR_CD       = 'RESCTRY'
          AND rfw.FACTOR_VALUE_CD = COALESCE (TRIM (ctr.CTRY_RISK_CD), 'UNKNOWN')
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* FACTOR NATCTRY - NATIONALITY (INDIVIDUALS) / INCORPORATION (ENTITIES)    *
\**************************************************************************/

INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.AML_RISK_FACTOR_WRK
(
       PARTY_ID,
       FACTOR_CD,
       FACTOR_VALUE_CD,
       SCORE_PTS
)
SELECT pty.PARTY_ID,
       'NATCTRY',
       COALESCE (TRIM (ctr.CTRY_RISK_CD), 'UNKNOWN'),
       ZEROIFNULL (rfw.SCORE_PTS)
FROM
       VT_PARTY                                 pty

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.CTRY_SNAPSHOT             ctr
          ON  ctr.CTRY_2_CD = CASE WHEN pty.PARTY_TYP_CD = 'O'
                                   THEN COALESCE (pty.INCORP_CTRY_CD, pty.RESIDENCE_CTRY_CD)
                                   ELSE COALESCE (pty.NATIONALITY_CD, pty.RESIDENCE_CTRY_CD)
                              END

       LEFT OUTER JOIN
       <DB_ENV>DB_REFERENCE.RISK_FACTOR_WEIGHT  rfw
          ON  rfw.FACTOR_CD       = 'NATCTRY'
          AND rfw.FACTOR_VALUE_CD = COALESCE (TRIM (ctr.CTRY_RISK_CD), 'UNKNOWN')
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* FACTOR PEP - POLITICALLY EXPOSED PERSON BY TYPE                          *
* ------------------------------------------------------------------------ *
* DO = domestic, FO = foreign, IO = international organisation,           *
* RC = relative or close associate.                                        *
\**************************************************************************/

INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.AML_RISK_FACTOR_WRK
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
       ZEROIFNULL (rfw.SCORE_PTS)
FROM
       VT_PARTY                                 pty

       LEFT OUTER JOIN
       <DB_ENV>DB_REFERENCE.RISK_FACTOR_WEIGHT  rfw
          ON  rfw.FACTOR_CD       = 'PEP'
          AND rfw.FACTOR_VALUE_CD = CASE WHEN pty.PEP_IND = 'Y'
                                         THEN COALESCE (TRIM (pty.PEP_TYP_CD), 'FO')
                                         ELSE 'NONE'
                                    END
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* FACTOR OCCP - OCCUPATION / INDUSTRY (SIC) RISK                           *
\**************************************************************************/

INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.AML_RISK_FACTOR_WRK
(
       PARTY_ID,
       FACTOR_CD,
       FACTOR_VALUE_CD,
       SCORE_PTS
)
SELECT pty.PARTY_ID,
       'OCCP',
       COALESCE (TRIM (sic.SIC_RISK_CD), 'UNKNOWN'),
       ZEROIFNULL (rfw.SCORE_PTS)
FROM
       VT_PARTY                                 pty

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.SIC_SNAPSHOT              sic
          ON  sic.SIC_CD = pty.SIC_CD

       LEFT OUTER JOIN
       <DB_ENV>DB_REFERENCE.RISK_FACTOR_WEIGHT  rfw
          ON  rfw.FACTOR_CD       = 'OCCP'
          AND rfw.FACTOR_VALUE_CD = COALESCE (TRIM (sic.SIC_RISK_CD), 'UNKNOWN')
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* FACTOR PRDT - HIGHEST PRODUCT RISK ACROSS HELD ACCOUNTS                  *
* ------------------------------------------------------------------------ *
* All active relationships count (holder, joint, signatory, beneficial    *
* owner, power of attorney). Closed accounts are ignored.                  *
\**************************************************************************/

CREATE VOLATILE TABLE VT_PARTY_PRDT AS
(
SELECT rel.PARTY_ID                                       AS PARTY_ID,
       MAX (CASE prd.PRDT_RISK_CD
                 WHEN 'H' THEN 3
                 WHEN 'M' THEN 2
                 WHEN 'L' THEN 1
                 ELSE 0
            END)                                          AS PRDT_RISK_ORD
FROM
       <DB_ENV>DB_ODS.PARTY_ACCT_REL         rel

       CROSS JOIN
       VT_RUN_DT                             rd

       INNER JOIN
       <DB_ENV>DB_ODS.ACCT_SNAPSHOT          acs
          ON  acs.ACCT_ID = rel.ACCT_ID

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.PRDT_SNAPSHOT          prd
          ON  prd.PRDT_CD = acs.PRDT_CD
WHERE
       rel.START_DT <= rd.RUN_DT
AND    COALESCE (rel.END_DT, DATE '9999-12-31') >= rd.RUN_DT
AND    COALESCE (acs.ACCT_STATUS_CD, 'A') <> 'C'
GROUP  BY rel.PARTY_ID
) WITH DATA
UNIQUE PRIMARY INDEX (PARTY_ID)
ON COMMIT PRESERVE ROWS
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.AML_RISK_FACTOR_WRK
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
       ZEROIFNULL (rfw.SCORE_PTS)
FROM
       VT_PARTY                                 pty

       LEFT OUTER JOIN
       VT_PARTY_PRDT                            ppr
          ON  ppr.PARTY_ID = pty.PARTY_ID

       LEFT OUTER JOIN
       <DB_ENV>DB_REFERENCE.RISK_FACTOR_WEIGHT  rfw
          ON  rfw.FACTOR_CD       = 'PRDT'
          AND rfw.FACTOR_VALUE_CD = CASE ppr.PRDT_RISK_ORD
                                         WHEN 3 THEN 'H'
                                         WHEN 2 THEN 'M'
                                         WHEN 1 THEN 'L'
                                         ELSE 'UNKNOWN'
                                    END
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* FACTOR CHNL - ONBOARDING CHANNEL                                         *
* ------------------------------------------------------------------------ *
* Channel of the first account opened. Digital channels are treated as    *
* non-face-to-face (NFTF) onboarding.                                      *
\**************************************************************************/

CREATE VOLATILE TABLE VT_PARTY_CHNL AS
(
SELECT act.PRIMARY_PARTY_ID                    AS PARTY_ID,
       act.OPEN_CHNL_CD                        AS OPEN_CHNL_CD
FROM   <DB_ENV>DB_ODS.ACCT    act
WHERE  act.PRIMARY_PARTY_ID IS NOT NULL
QUALIFY SUM (1) OVER (PARTITION BY  act.PRIMARY_PARTY_ID
                          ORDER BY  act.OPEN_DT
                                   ,act.ACCT_ID
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
) WITH DATA
UNIQUE PRIMARY INDEX (PARTY_ID)
ON COMMIT PRESERVE ROWS
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.AML_RISK_FACTOR_WRK
(
       PARTY_ID,
       FACTOR_CD,
       FACTOR_VALUE_CD,
       SCORE_PTS
)
SELECT pty.PARTY_ID,
       'CHNL',
       CASE WHEN chs.DIGITAL_IND = 'Y' THEN 'NFTF' ELSE 'F2F' END,
       ZEROIFNULL (rfw.SCORE_PTS)
FROM
       VT_PARTY                                 pty

       LEFT OUTER JOIN
       VT_PARTY_CHNL                            pch
          ON  pch.PARTY_ID = pty.PARTY_ID

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.CHNL_SNAPSHOT             chs
          ON  chs.CHNL_CD = pch.OPEN_CHNL_CD

       LEFT OUTER JOIN
       <DB_ENV>DB_REFERENCE.RISK_FACTOR_WEIGHT  rfw
          ON  rfw.FACTOR_CD       = 'CHNL'
          AND rfw.FACTOR_VALUE_CD = CASE WHEN chs.DIGITAL_IND = 'Y' THEN 'NFTF' ELSE 'F2F' END
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* FACTOR ALERTS - TRANSACTION MONITORING ALERTS IN THE LAST 90 DAYS        *
* ------------------------------------------------------------------------ *
* Suppressed duplicates are not counted.                                   *
\**************************************************************************/

INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.AML_RISK_FACTOR_WRK
(
       PARTY_ID,
       FACTOR_CD,
       FACTOR_VALUE_CD,
       SCORE_PTS
)
SELECT pty.PARTY_ID,
       'ALERTS',
       CASE
          WHEN ZEROIFNULL (alc.ALERT_CNT) = 0 THEN '0'
          WHEN alc.ALERT_CNT <= 2             THEN '1-2'
          WHEN alc.ALERT_CNT <= 5             THEN '3-5'
          ELSE '6+'
       END,
       ZEROIFNULL (rfw.SCORE_PTS)
FROM
       VT_PARTY                                 pty

       LEFT OUTER JOIN
       (
        SELECT al.PARTY_ID,
               COUNT (*)                AS ALERT_CNT
        FROM   <DB_ENV>DB_AML.TM_ALERT  al
               CROSS JOIN
               VT_RUN_DT                rd
        WHERE  al.BUSINESS_DT BETWEEN rd.RUN_DT - 89 AND rd.RUN_DT
        AND    al.ALERT_STATUS_CD <> 'SUPPR'
        AND    al.PARTY_ID IS NOT NULL
        GROUP  BY al.PARTY_ID
       )                                        alc
          ON  alc.PARTY_ID = pty.PARTY_ID

       LEFT OUTER JOIN
       <DB_ENV>DB_REFERENCE.RISK_FACTOR_WEIGHT  rfw
          ON  rfw.FACTOR_CD       = 'ALERTS'
          AND rfw.FACTOR_VALUE_CD = CASE
                                       WHEN ZEROIFNULL (alc.ALERT_CNT) = 0 THEN '0'
                                       WHEN alc.ALERT_CNT <= 2             THEN '1-2'
                                       WHEN alc.ALERT_CNT <= 5             THEN '3-5'
                                       ELSE '6+'
                                    END
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* FACTOR SANC - OPEN OR CONFIRMED SANCTIONS SCREENING HITS                 *
\**************************************************************************/

INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.AML_RISK_FACTOR_WRK
(
       PARTY_ID,
       FACTOR_CD,
       FACTOR_VALUE_CD,
       SCORE_PTS
)
SELECT pty.PARTY_ID,
       'SANC',
       CASE WHEN sht.HIT_CNT > 0 THEN 'OPEN' ELSE 'NONE' END,
       ZEROIFNULL (rfw.SCORE_PTS)
FROM
       VT_PARTY                                 pty

       LEFT OUTER JOIN
       (
        SELECT hit.PARTY_ID,
               COUNT (*)                       AS HIT_CNT
        FROM   <DB_ENV>DB_AML.SANC_SCREEN_HIT  hit
        WHERE  hit.HIT_STATUS_CD IN ('OPEN', 'CONF')
        AND    hit.PARTY_ID IS NOT NULL
        GROUP  BY hit.PARTY_ID
       )                                        sht
          ON  sht.PARTY_ID = pty.PARTY_ID

       LEFT OUTER JOIN
       <DB_ENV>DB_REFERENCE.RISK_FACTOR_WEIGHT  rfw
          ON  rfw.FACTOR_CD       = 'SANC'
          AND rfw.FACTOR_VALUE_CD = CASE WHEN sht.HIT_CNT > 0 THEN 'OPEN' ELSE 'NONE' END
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* FACTOR KYC - KYC REVIEW STATUS                                           *
* ------------------------------------------------------------------------ *
* An overdue periodic review overrides the recorded status.                *
\**************************************************************************/

INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.AML_RISK_FACTOR_WRK
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
       ZEROIFNULL (rfw.SCORE_PTS)
FROM
       VT_PARTY                                 pty

       CROSS JOIN
       VT_RUN_DT                                rd

       LEFT OUTER JOIN
       <DB_ENV>DB_REFERENCE.RISK_FACTOR_WEIGHT  rfw
          ON  rfw.FACTOR_CD       = 'KYC'
          AND rfw.FACTOR_VALUE_CD = CASE WHEN pty.KYC_REVIEW_DUE_DT < rd.RUN_DT THEN 'OVERDUE'
                                         ELSE COALESCE (TRIM (pty.KYC_STATUS_CD), 'PE')
                                    END
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* FACTOR ADVMEDIA - ADVERSE MEDIA                                          *
\**************************************************************************/

INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.AML_RISK_FACTOR_WRK
(
       PARTY_ID,
       FACTOR_CD,
       FACTOR_VALUE_CD,
       SCORE_PTS
)
SELECT pty.PARTY_ID,
       'ADVMEDIA',
       pty.ADV_MEDIA_IND,
       ZEROIFNULL (rfw.SCORE_PTS)
FROM
       VT_PARTY                                 pty

       LEFT OUTER JOIN
       <DB_ENV>DB_REFERENCE.RISK_FACTOR_WEIGHT  rfw
          ON  rfw.FACTOR_CD       = 'ADVMEDIA'
          AND rfw.FACTOR_VALUE_CD = pty.ADV_MEDIA_IND
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.AML_RISK_FACTOR_WRK INDEX  (PARTY_ID);
COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.AML_RISK_FACTOR_WRK COLUMN (FACTOR_CD);
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* PIVOT THE FACTORS INTO ONE SCORE ROW PER CUSTOMER                        *
\**************************************************************************/

DELETE FROM <DB_ENV>DB_TRANS_IMPORTS.AML_RISK_SCORE_WRK
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.AML_RISK_SCORE_WRK
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
       <DB_ENV>DB_TRANS_IMPORTS.AML_RISK_FACTOR_WRK   fct

       CROSS JOIN
       VT_RUN_DT                                      rd
GROUP  BY fct.PARTY_ID,
          rd.RUN_DT
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* ASSIGN THE RISK BAND                                                     *
* ------------------------------------------------------------------------ *
* Score ranges from DB_REFERENCE.RISK_BAND. Scores above the highest      *
* band are Very High, unmatched scores default to Low.                     *
\**************************************************************************/

UPDATE wrk
FROM   <DB_ENV>DB_TRANS_IMPORTS.AML_RISK_SCORE_WRK   wrk,
       <DB_ENV>DB_REFERENCE.RISK_BAND                rbd
SET    RISK_BAND_CD = rbd.RISK_BAND_CD
WHERE  wrk.TOTAL_SCORE BETWEEN rbd.MIN_SCORE AND rbd.MAX_SCORE
;
.if errorcode <> 0 then .quit errorcode;

UPDATE wrk
FROM   <DB_ENV>DB_TRANS_IMPORTS.AML_RISK_SCORE_WRK   wrk,
       (
        SELECT MAX (MAX_SCORE)       AS MAX_SCORE
        FROM   <DB_ENV>DB_REFERENCE.RISK_BAND
       )                                             mxb
SET    RISK_BAND_CD = CASE WHEN wrk.TOTAL_SCORE > mxb.MAX_SCORE
                           THEN 'VH'
                           ELSE 'L'
                      END
WHERE  wrk.RISK_BAND_CD IS NULL
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* REGULATORY OVERRIDES                                                     *
* ------------------------------------------------------------------------ *
* - open / confirmed sanctions match                 -> Very High          *
* - residence in a prohibited (X) jurisdiction       -> Very High          *
* - PEP (MLR 2017 reg. 35) at least                  -> High               *
\**************************************************************************/

UPDATE <DB_ENV>DB_TRANS_IMPORTS.AML_RISK_SCORE_WRK
SET    RISK_BAND_CD = 'VH'
WHERE  SANC_SCORE > 0
;
.if errorcode <> 0 then .quit errorcode;

UPDATE wrk
FROM   <DB_ENV>DB_TRANS_IMPORTS.AML_RISK_SCORE_WRK    wrk,
       <DB_ENV>DB_TRANS_IMPORTS.AML_RISK_FACTOR_WRK   fct
SET    RISK_BAND_CD = 'VH'
WHERE  fct.PARTY_ID        = wrk.PARTY_ID
AND    fct.FACTOR_CD       = 'RESCTRY'
AND    fct.FACTOR_VALUE_CD = 'X'
;
.if errorcode <> 0 then .quit errorcode;

UPDATE <DB_ENV>DB_TRANS_IMPORTS.AML_RISK_SCORE_WRK
SET    RISK_BAND_CD = 'H'
WHERE  PEP_SCORE > 0
AND    RISK_BAND_CD IN ('L', 'M')
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.AML_RISK_SCORE_WRK INDEX (PARTY_ID);
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* RESET A PREVIOUS RUN OF THE SAME BUSINESS DATE                           *
* ------------------------------------------------------------------------ *
* History rows opened today are removed and the versions they closed are  *
* re-opened, so that the comparison below is always made against the      *
* state before today's run.                                                *
\**************************************************************************/

CREATE VOLATILE TABLE VT_RERUN_PARTY AS
(
SELECT hst.PARTY_ID
FROM   <DB_ENV>DB_AML.PARTY_RISK_SCORE_HIST   hst
       CROSS JOIN
       VT_RUN_DT                              rd
WHERE  hst.START_DT = rd.RUN_DT
GROUP  BY hst.PARTY_ID
) WITH DATA
UNIQUE PRIMARY INDEX (PARTY_ID)
ON COMMIT PRESERVE ROWS
;
.if errorcode <> 0 then .quit errorcode;

DELETE FROM <DB_ENV>DB_AML.PARTY_RISK_SCORE_HIST
WHERE  START_DT = (SELECT RUN_DT FROM VT_RUN_DT)
;
.if errorcode <> 0 then .quit errorcode;

UPDATE <DB_ENV>DB_AML.PARTY_RISK_SCORE_HIST
SET    END_DT = DATE '9999-12-31'
WHERE  END_DT   = (SELECT RUN_DT - 1 FROM VT_RUN_DT)
AND    PARTY_ID IN (SELECT PARTY_ID FROM VT_RERUN_PARTY)
;
.if errorcode <> 0 then .quit errorcode;

DELETE FROM <DB_ENV>DB_AML.EDD_REVIEW_QUEUE
WHERE  TRIGGER_DT       = (SELECT RUN_DT FROM VT_RUN_DT)
AND    REVIEW_STATUS_CD = 'OPEN'
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* COMPARE WITH THE CURRENT VERSION                                         *
* ------------------------------------------------------------------------ *
* CHG_TYP_CD  I = first scoring, C = score or band changed, U = unchanged *
\**************************************************************************/

CREATE VOLATILE TABLE VT_RISK_CMP AS
(
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
       <DB_ENV>DB_TRANS_IMPORTS.AML_RISK_SCORE_WRK    wrk

       LEFT OUTER JOIN
       <DB_ENV>DB_AML.PARTY_RISK_SCORE_HIST           hst
          ON  hst.PARTY_ID = wrk.PARTY_ID
          AND hst.END_DT   = DATE '9999-12-31'

       LEFT OUTER JOIN
       <DB_ENV>DB_AML.PARTY_RISK_SCORE                cur
          ON  cur.PARTY_ID = wrk.PARTY_ID

       LEFT OUTER JOIN
       <DB_ENV>DB_REFERENCE.RISK_BAND                 rbd
          ON  rbd.RISK_BAND_CD = wrk.RISK_BAND_CD
) WITH DATA
UNIQUE PRIMARY INDEX (PARTY_ID)
ON COMMIT PRESERVE ROWS
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS VT_RISK_CMP INDEX  (PARTY_ID);
COLLECT STATISTICS VT_RISK_CMP COLUMN (CHG_TYP_CD);
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* MAINTAIN THE RISK SCORE HISTORY (SCD TYPE 2)                             *
\**************************************************************************/

UPDATE hst
FROM   <DB_ENV>DB_AML.PARTY_RISK_SCORE_HIST   hst,
       VT_RISK_CMP                            cmp,
       VT_RUN_DT                              rd
SET    END_DT     = rd.RUN_DT - 1,
       CO_UPD_TMS = rd.LOAD_TMS
WHERE  hst.PARTY_ID   = cmp.PARTY_ID
AND    hst.END_DT     = DATE '9999-12-31'
AND    cmp.CHG_TYP_CD = 'C'
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_AML.PARTY_RISK_SCORE_HIST
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
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* APPLY THE CURRENT RISK SCORE                                             *
\**************************************************************************/

MERGE INTO <DB_ENV>DB_AML.PARTY_RISK_SCORE   tgt
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
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_AML.PARTY_RISK_SCORE      INDEX  (PARTY_ID);
COLLECT STATISTICS <DB_ENV>DB_AML.PARTY_RISK_SCORE      COLUMN (RISK_BAND_CD);
COLLECT STATISTICS <DB_ENV>DB_AML.PARTY_RISK_SCORE_HIST INDEX  (PARTY_ID, START_DT);
COLLECT STATISTICS <DB_ENV>DB_AML.PARTY_RISK_SCORE_HIST COLUMN (END_DT);
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* ENHANCED DUE DILIGENCE TRIGGERS                                          *
* ------------------------------------------------------------------------ *
* BUP  = band raised to High / Very High (or first scored at that level)   *
* PEP  = customer newly identified as PEP                                  *
* SANC = new sanctions exposure                                            *
* The review is due on the 10th UK business day after the business date.   *
\**************************************************************************/

CREATE VOLATILE TABLE VT_EDD_DUE AS
(
SELECT cal.CAL_DT                          AS DUE_DT
FROM
       <DB_ENV>DB_REFERENCE.CALENDAR        cal

       CROSS JOIN
       VT_RUN_DT                            rd

       LEFT OUTER JOIN
       <DB_ENV>DB_REFERENCE.UK_BANK_HOLIDAY hol
          ON  hol.HOLIDAY_DT = cal.CAL_DT
WHERE
       cal.CAL_DT     >  rd.RUN_DT
AND    cal.CAL_DT     <= rd.RUN_DT + 31
AND    cal.BUS_DAY_IND = 'Y'
AND    hol.HOLIDAY_DT IS NULL
QUALIFY ROW_NUMBER () OVER (ORDER BY cal.CAL_DT) = 10
) WITH DATA
UNIQUE PRIMARY INDEX (DUE_DT)
ON COMMIT PRESERVE ROWS
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_AML.EDD_REVIEW_QUEUE
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
        AND    ZEROIFNULL (OLD_PEP_SCORE) = 0

        UNION ALL

        SELECT PARTY_ID,
               'SANC',
               RISK_BAND_CD,
               OLD_RISK_BAND_CD
        FROM   VT_RISK_CMP
        WHERE  SANC_SCORE > 0
        AND    ZEROIFNULL (OLD_SANC_SCORE) = 0
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
        FROM   <DB_ENV>DB_AML.EDD_REVIEW_QUEUE   edd
        WHERE  edd.PARTY_ID          = trg.PARTY_ID
        AND    edd.TRIGGER_DT        = rd.RUN_DT
        AND    edd.TRIGGER_REASON_CD = trg.TRIGGER_REASON_CD
       )
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_AML.EDD_REVIEW_QUEUE INDEX (PARTY_ID, TRIGGER_DT, TRIGGER_REASON_CD);
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* END OF SCRIPT                                                            *
\**************************************************************************/

.quit 0;
