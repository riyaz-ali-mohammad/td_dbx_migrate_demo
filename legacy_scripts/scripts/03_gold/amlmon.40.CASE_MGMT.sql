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

COLLECT STATISTICS <DB_ENV>DB_AML.TM_ALERT  COLUMN (ALERT_STATUS_CD);
COLLECT STATISTICS <DB_ENV>DB_AML.TM_ALERT  COLUMN (CASE_ID);
COLLECT STATISTICS <DB_ENV>DB_AML.AML_CASE  INDEX  (PARTY_ID);
COLLECT STATISTICS <DB_ENV>DB_AML.AML_CASE  COLUMN (CASE_STATUS_CD);
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* COLLECT ALL NEW (UNCASED) ALERTS                                         *
* ------------------------------------------------------------------------ *
* Alerts without a party are linked to the primary holder of the account. *
* If no new alerts exist the processing continues with the auto-closure.  *
\**************************************************************************/

CREATE VOLATILE TABLE VT_NEW_ALERT AS
(
SELECT al.ALERT_ID                                        AS ALERT_ID,
       al.RULE_CD                                         AS RULE_CD,
       COALESCE (al.PARTY_ID, acs.PRIMARY_PARTY_ID)       AS PARTY_ID,
       al.ACCT_ID                                         AS ACCT_ID,
       al.BUSINESS_DT                                     AS BUSINESS_DT,
       ZEROIFNULL (al.ALERT_SCORE)                        AS ALERT_SCORE,
       ZEROIFNULL (al.HIT_GBP_AMT)                        AS HIT_GBP_AMT
FROM
       <DB_ENV>DB_AML.TM_ALERT              al

       CROSS JOIN
       VT_RUN_DT                            rd

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.ACCT_SNAPSHOT         acs
          ON  acs.ACCT_ID = al.ACCT_ID
WHERE
       al.ALERT_STATUS_CD = 'NEW'
AND    al.CASE_ID IS NULL
AND    al.BUSINESS_DT <= rd.RUN_DT
AND    COALESCE (al.PARTY_ID, acs.PRIMARY_PARTY_ID) IS NOT NULL
) WITH DATA
UNIQUE PRIMARY INDEX (ALERT_ID)
ON COMMIT PRESERVE ROWS
;
.if errorcode <> 0 then .quit errorcode;

SELECT ALERT_ID
FROM   VT_NEW_ALERT
;
.if errorcode <> 0 then .quit errorcode;
.if activitycount = 0 then .goto AUTO_CLOSE;

COLLECT STATISTICS VT_NEW_ALERT INDEX  (ALERT_ID);
COLLECT STATISTICS VT_NEW_ALERT COLUMN (PARTY_ID);
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* FIND AN OPEN CASE TO ATTACH TO                                           *
* ------------------------------------------------------------------------ *
* New alerts join the latest OPEN / INVST case of the party opened within  *
* the last 30 days. Otherwise a new case is created.                       *
\**************************************************************************/

CREATE VOLATILE TABLE VT_OPEN_CASE AS
(
SELECT cse.CASE_ID,
       cse.PARTY_ID,
       cse.CASE_STATUS_CD,
       cse.CASE_PRIORITY_NR,
       cse.SLA_DUE_DT,
       cse.CASE_OPEN_DT
FROM
       <DB_ENV>DB_AML.AML_CASE              cse

       CROSS JOIN
       VT_RUN_DT                            rd
WHERE
       cse.CASE_STATUS_CD IN ('OPEN', 'INVST')
AND    cse.CASE_OPEN_DT   >= rd.RUN_DT - 30
AND    cse.PARTY_ID IN (SELECT PARTY_ID FROM VT_NEW_ALERT)
QUALIFY ROW_NUMBER () OVER (PARTITION BY cse.PARTY_ID
                                ORDER BY cse.CASE_OPEN_DT DESC,
                                         cse.CASE_ID      DESC
                           ) = 1
) WITH DATA
UNIQUE PRIMARY INDEX (PARTY_ID)
ON COMMIT PRESERVE ROWS
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* ALL ALERTS OF THE TARGET CASE (NEW + ALREADY ATTACHED)                   *
\**************************************************************************/

CREATE VOLATILE TABLE VT_CASE_ALERT AS
(
SELECT na.ALERT_ID,
       na.PARTY_ID,
       opc.CASE_ID,
       na.RULE_CD,
       na.BUSINESS_DT,
       na.ALERT_SCORE,
       na.HIT_GBP_AMT,
       'N'                         AS ALERT_ORIGIN_CD
FROM
       VT_NEW_ALERT                         na

       LEFT OUTER JOIN
       VT_OPEN_CASE                         opc
          ON  opc.PARTY_ID = na.PARTY_ID

UNION ALL

SELECT al.ALERT_ID,
       opc.PARTY_ID,
       opc.CASE_ID,
       al.RULE_CD,
       al.BUSINESS_DT,
       ZEROIFNULL (al.ALERT_SCORE),
       ZEROIFNULL (al.HIT_GBP_AMT),
       'E'
FROM
       <DB_ENV>DB_AML.TM_ALERT              al

       INNER JOIN
       VT_OPEN_CASE                         opc
          ON  opc.CASE_ID = al.CASE_ID
) WITH DATA
UNIQUE PRIMARY INDEX (ALERT_ID)
ON COMMIT PRESERVE ROWS
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* CONSOLIDATE ALERTS PER PARTY INTO THE CASE WORK TABLE                    *
\**************************************************************************/

DELETE FROM <DB_ENV>DB_TRANS_IMPORTS.AML_CASE_WRK
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.AML_CASE_WRK
(
       PARTY_ID,
       CASE_ID,
       EXISTING_CASE_IND,
       ALERT_CNT,
       TOTAL_ALERT_SCORE,
       TOTAL_HIT_GBP_AMT,
       MAX_RULE_SCORE,
       FIRST_ALERT_DT,
       LAST_ALERT_DT,
       RULE_LIST,
       SEGMENT_CD,
       RISK_BAND_CD
)
SELECT agg.PARTY_ID,
       agg.CASE_ID,
       CASE WHEN agg.CASE_ID IS NULL THEN 'N' ELSE 'Y' END,
       agg.ALERT_CNT,
       agg.TOTAL_ALERT_SCORE,
       agg.TOTAL_HIT_GBP_AMT,
       agg.MAX_RULE_SCORE,
       agg.FIRST_ALERT_DT,
       agg.LAST_ALERT_DT,
       SUBSTR (rul.RULE_LIST, 1, 200),
       COALESCE (psn.SEGMENT_CD, 'RET'),
       COALESCE (prs.RISK_BAND_CD, 'L')
FROM
       (
        SELECT PARTY_ID,
               MAX (CASE_ID)                    AS CASE_ID,
               COUNT (*)                        AS ALERT_CNT,
               SUM (CAST (ALERT_SCORE AS INTEGER))
                                                AS TOTAL_ALERT_SCORE,
               SUM (HIT_GBP_AMT)                AS TOTAL_HIT_GBP_AMT,
               MAX (ALERT_SCORE)                AS MAX_RULE_SCORE,
               MIN (BUSINESS_DT)                AS FIRST_ALERT_DT,
               MAX (BUSINESS_DT)                AS LAST_ALERT_DT
        FROM   VT_CASE_ALERT
        GROUP  BY PARTY_ID
       )                                    agg

       INNER JOIN
       (
        SELECT dst.PARTY_ID,
               TRIM (TRAILING ',' FROM
                     (XMLAGG (TRIM (dst.RULE_CD) || ','
                              ORDER BY dst.RULE_CD) (VARCHAR(400))))
                                                AS RULE_LIST
        FROM   (
                SELECT PARTY_ID,
                       RULE_CD
                FROM   VT_CASE_ALERT
                GROUP  BY PARTY_ID,
                          RULE_CD
               )                    dst
        GROUP  BY dst.PARTY_ID
       )                                    rul
          ON  rul.PARTY_ID = agg.PARTY_ID

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.PARTY_SNAPSHOT        psn
          ON  psn.PARTY_ID = agg.PARTY_ID

       LEFT OUTER JOIN
       <DB_ENV>DB_AML.PARTY_RISK_SCORE      prs
          ON  prs.PARTY_ID = agg.PARTY_ID
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* GENERATE NEW CASE IDENTIFIERS (MAX + CSUM)                               *
\**************************************************************************/

CREATE VOLATILE TABLE VT_NEW_CASE_ID AS
(
SELECT wrk.PARTY_ID,
       mx.MAX_CASE_ID + CSUM (1, wrk.PARTY_ID)        AS NEW_CASE_ID
FROM
       <DB_ENV>DB_TRANS_IMPORTS.AML_CASE_WRK   wrk,
       (
        SELECT COALESCE (MAX (CASE_ID), 0)     AS MAX_CASE_ID
        FROM   <DB_ENV>DB_AML.AML_CASE
       )                                       mx
WHERE
       wrk.CASE_ID IS NULL
) WITH DATA
UNIQUE PRIMARY INDEX (PARTY_ID)
ON COMMIT PRESERVE ROWS
;
.if errorcode <> 0 then .quit errorcode;

UPDATE wrk
FROM   <DB_ENV>DB_TRANS_IMPORTS.AML_CASE_WRK   wrk,
       VT_NEW_CASE_ID                          nid
SET    CASE_ID = nid.NEW_CASE_ID
WHERE  wrk.PARTY_ID = nid.PARTY_ID
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* CASE PRIORITY (1 = HIGHEST)                                              *
* ------------------------------------------------------------------------ *
* Sanctions exposure, Very High customer risk or a total score >= 250     *
* give priority 1. An existing case never loses priority.                  *
\**************************************************************************/

UPDATE <DB_ENV>DB_TRANS_IMPORTS.AML_CASE_WRK
SET    CASE_PRIORITY_NR =
       CASE
          WHEN INDEX (RULE_LIST, 'TM_SAN01') > 0
            OR RISK_BAND_CD      = 'VH'
            OR TOTAL_ALERT_SCORE >= 250                         THEN 1
          WHEN RISK_BAND_CD      = 'H'
            OR TOTAL_ALERT_SCORE >= 150
            OR MAX_RULE_SCORE    >= 90                          THEN 2
          WHEN TOTAL_ALERT_SCORE >= 100
            OR ALERT_CNT         >= 3                           THEN 3
          WHEN TOTAL_ALERT_SCORE >= 50                          THEN 4
          ELSE 5
       END
;
.if errorcode <> 0 then .quit errorcode;

UPDATE wrk
FROM   <DB_ENV>DB_TRANS_IMPORTS.AML_CASE_WRK   wrk,
       VT_OPEN_CASE                            opc
SET    CASE_PRIORITY_NR = opc.CASE_PRIORITY_NR
WHERE  wrk.CASE_ID          = opc.CASE_ID
AND    opc.CASE_PRIORITY_NR < wrk.CASE_PRIORITY_NR
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* WORK QUEUE AND SLA DUE DATE                                              *
* ------------------------------------------------------------------------ *
* Queue by segment and priority band (segment 'ALL' as fallback). The SLA  *
* is the n-th UK business day after the business date (bank holidays      *
* excluded). Default queue AMLGEN with 20 business days.                  *
\**************************************************************************/

CREATE VOLATILE TABLE VT_BUS_DAY AS
(
SELECT cal.CAL_DT                                         AS CAL_DT,
       ROW_NUMBER () OVER (ORDER BY cal.CAL_DT)           AS BUS_DAY_NR
FROM
       <DB_ENV>DB_REFERENCE.CALENDAR        cal

       CROSS JOIN
       VT_RUN_DT                            rd

       LEFT OUTER JOIN
       <DB_ENV>DB_REFERENCE.UK_BANK_HOLIDAY hol
          ON  hol.HOLIDAY_DT = cal.CAL_DT
WHERE
       cal.CAL_DT      >  rd.RUN_DT
AND    cal.CAL_DT      <= rd.RUN_DT + 120
AND    cal.BUS_DAY_IND =  'Y'
AND    hol.HOLIDAY_DT IS NULL
) WITH DATA
UNIQUE PRIMARY INDEX (CAL_DT)
ON COMMIT PRESERVE ROWS
;
.if errorcode <> 0 then .quit errorcode;

CREATE VOLATILE TABLE VT_QUEUE_MATCH AS
(
SELECT wrk.PARTY_ID,
       que.QUEUE_CD,
       COALESCE (que.SLA_BUS_DAYS, 20)          AS SLA_BUS_DAYS
FROM
       <DB_ENV>DB_TRANS_IMPORTS.AML_CASE_WRK   wrk

       INNER JOIN
       <DB_ENV>DB_REFERENCE.CASE_QUEUE         que
          ON  que.SEGMENT_CD IN (wrk.SEGMENT_CD, 'ALL')
          AND wrk.CASE_PRIORITY_NR BETWEEN que.MIN_PRIORITY_NR AND que.MAX_PRIORITY_NR
QUALIFY ROW_NUMBER () OVER (PARTITION BY wrk.PARTY_ID
                                ORDER BY CASE WHEN que.SEGMENT_CD = wrk.SEGMENT_CD
                                              THEN 0 ELSE 1 END,
                                         que.QUEUE_CD
                           ) = 1
) WITH DATA
UNIQUE PRIMARY INDEX (PARTY_ID)
ON COMMIT PRESERVE ROWS
;
.if errorcode <> 0 then .quit errorcode;

UPDATE wrk
FROM   <DB_ENV>DB_TRANS_IMPORTS.AML_CASE_WRK   wrk,
       VT_QUEUE_MATCH                          qmt,
       VT_BUS_DAY                              bdy
SET    QUEUE_CD   = qmt.QUEUE_CD,
       SLA_DUE_DT = bdy.CAL_DT
WHERE  wrk.PARTY_ID   = qmt.PARTY_ID
AND    bdy.BUS_DAY_NR = qmt.SLA_BUS_DAYS
;
.if errorcode <> 0 then .quit errorcode;

UPDATE wrk
FROM   <DB_ENV>DB_TRANS_IMPORTS.AML_CASE_WRK   wrk,
       VT_BUS_DAY                              bdy
SET    QUEUE_CD   = COALESCE (wrk.QUEUE_CD, 'AMLGEN'),
       SLA_DUE_DT = bdy.CAL_DT
WHERE  (wrk.QUEUE_CD IS NULL OR wrk.SLA_DUE_DT IS NULL)
AND    bdy.BUS_DAY_NR = 20
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.AML_CASE_WRK INDEX  (PARTY_ID);
COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.AML_CASE_WRK COLUMN (CASE_ID);
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* HISTORY: BEFORE IMAGES OF EXISTING CASES                                 *
\**************************************************************************/

INSERT INTO <DB_ENV>DB_AML.AML_CASE_HIST
(
       CASE_ID,
       UPD_TMS,
       PARTY_ID,
       CASE_OPEN_DT,
       CASE_STATUS_CD,
       CASE_PRIORITY_NR,
       QUEUE_CD,
       SLA_DUE_DT,
       ALERT_CNT,
       TOTAL_ALERT_SCORE,
       TOTAL_HIT_GBP_AMT,
       RULE_LIST,
       SAR_CANDIDATE_IND,
       RISK_BAND_CD,
       SEGMENT_CD,
       FIRST_ALERT_DT,
       LAST_ALERT_DT,
       CASE_CLOSE_DT,
       CLOSE_REASON_CD,
       HIST_ACTION_CD,
       CO_UPD_TMS
)
SELECT cse.CASE_ID,
       CURRENT_TIMESTAMP(0),
       cse.PARTY_ID,
       cse.CASE_OPEN_DT,
       cse.CASE_STATUS_CD,
       cse.CASE_PRIORITY_NR,
       cse.QUEUE_CD,
       cse.SLA_DUE_DT,
       cse.ALERT_CNT,
       cse.TOTAL_ALERT_SCORE,
       cse.TOTAL_HIT_GBP_AMT,
       cse.RULE_LIST,
       cse.SAR_CANDIDATE_IND,
       cse.RISK_BAND_CD,
       cse.SEGMENT_CD,
       cse.FIRST_ALERT_DT,
       cse.LAST_ALERT_DT,
       cse.CASE_CLOSE_DT,
       cse.CLOSE_REASON_CD,
       'U',
       cse.CO_UPD_TMS
FROM
       <DB_ENV>DB_AML.AML_CASE                 cse

       INNER JOIN
       <DB_ENV>DB_TRANS_IMPORTS.AML_CASE_WRK   wrk
          ON  wrk.CASE_ID = cse.CASE_ID
WHERE
       wrk.EXISTING_CASE_IND = 'Y'
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* UPDATE EXISTING CASES                                                    *
* ------------------------------------------------------------------------ *
* The SLA date only moves forward in time when the priority is raised.    *
\**************************************************************************/

UPDATE cse
FROM   <DB_ENV>DB_AML.AML_CASE                 cse,
       <DB_ENV>DB_TRANS_IMPORTS.AML_CASE_WRK   wrk,
       VT_RUN_DT                               rd
SET    CASE_PRIORITY_NR  = wrk.CASE_PRIORITY_NR,
       QUEUE_CD          = CASE WHEN wrk.CASE_PRIORITY_NR < cse.CASE_PRIORITY_NR
                                THEN wrk.QUEUE_CD ELSE cse.QUEUE_CD END,
       SLA_DUE_DT        = CASE WHEN wrk.CASE_PRIORITY_NR < cse.CASE_PRIORITY_NR
                                 AND wrk.SLA_DUE_DT       < cse.SLA_DUE_DT
                                THEN wrk.SLA_DUE_DT ELSE cse.SLA_DUE_DT END,
       ALERT_CNT         = wrk.ALERT_CNT,
       TOTAL_ALERT_SCORE = wrk.TOTAL_ALERT_SCORE,
       TOTAL_HIT_GBP_AMT = wrk.TOTAL_HIT_GBP_AMT,
       RULE_LIST         = wrk.RULE_LIST,
       RISK_BAND_CD      = wrk.RISK_BAND_CD,
       FIRST_ALERT_DT    = wrk.FIRST_ALERT_DT,
       LAST_ALERT_DT     = wrk.LAST_ALERT_DT,
       CO_UPD_TMS        = rd.LOAD_TMS
WHERE  cse.CASE_ID           = wrk.CASE_ID
AND    wrk.EXISTING_CASE_IND = 'Y'
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* OPEN NEW CASES                                                           *
\**************************************************************************/

INSERT INTO <DB_ENV>DB_AML.AML_CASE
(
       CASE_ID,
       PARTY_ID,
       CASE_OPEN_DT,
       CASE_STATUS_CD,
       CASE_PRIORITY_NR,
       QUEUE_CD,
       SLA_DUE_DT,
       ALERT_CNT,
       TOTAL_ALERT_SCORE,
       TOTAL_HIT_GBP_AMT,
       RULE_LIST,
       SAR_CANDIDATE_IND,
       RISK_BAND_CD,
       SEGMENT_CD,
       FIRST_ALERT_DT,
       LAST_ALERT_DT,
       CASE_CLOSE_DT,
       CLOSE_REASON_CD,
       CO_UPD_TMS
)
SELECT wrk.CASE_ID,
       wrk.PARTY_ID,
       rd.RUN_DT,
       'OPEN',
       wrk.CASE_PRIORITY_NR,
       wrk.QUEUE_CD,
       wrk.SLA_DUE_DT,
       wrk.ALERT_CNT,
       wrk.TOTAL_ALERT_SCORE,
       wrk.TOTAL_HIT_GBP_AMT,
       wrk.RULE_LIST,
       'N',
       wrk.RISK_BAND_CD,
       wrk.SEGMENT_CD,
       wrk.FIRST_ALERT_DT,
       wrk.LAST_ALERT_DT,
       NULL,
       NULL,
       rd.LOAD_TMS
FROM
       <DB_ENV>DB_TRANS_IMPORTS.AML_CASE_WRK   wrk

       CROSS JOIN
       VT_RUN_DT                               rd
WHERE
       wrk.EXISTING_CASE_IND = 'N'
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_AML.AML_CASE_HIST
(
       CASE_ID,
       UPD_TMS,
       PARTY_ID,
       CASE_OPEN_DT,
       CASE_STATUS_CD,
       CASE_PRIORITY_NR,
       QUEUE_CD,
       SLA_DUE_DT,
       ALERT_CNT,
       TOTAL_ALERT_SCORE,
       TOTAL_HIT_GBP_AMT,
       RULE_LIST,
       SAR_CANDIDATE_IND,
       RISK_BAND_CD,
       SEGMENT_CD,
       FIRST_ALERT_DT,
       LAST_ALERT_DT,
       CASE_CLOSE_DT,
       CLOSE_REASON_CD,
       HIST_ACTION_CD,
       CO_UPD_TMS
)
SELECT cse.CASE_ID,
       CURRENT_TIMESTAMP(0),
       cse.PARTY_ID,
       cse.CASE_OPEN_DT,
       cse.CASE_STATUS_CD,
       cse.CASE_PRIORITY_NR,
       cse.QUEUE_CD,
       cse.SLA_DUE_DT,
       cse.ALERT_CNT,
       cse.TOTAL_ALERT_SCORE,
       cse.TOTAL_HIT_GBP_AMT,
       cse.RULE_LIST,
       cse.SAR_CANDIDATE_IND,
       cse.RISK_BAND_CD,
       cse.SEGMENT_CD,
       cse.FIRST_ALERT_DT,
       cse.LAST_ALERT_DT,
       cse.CASE_CLOSE_DT,
       cse.CLOSE_REASON_CD,
       'I',
       cse.CO_UPD_TMS
FROM
       <DB_ENV>DB_AML.AML_CASE                 cse

       INNER JOIN
       <DB_ENV>DB_TRANS_IMPORTS.AML_CASE_WRK   wrk
          ON  wrk.CASE_ID = cse.CASE_ID
WHERE
       wrk.EXISTING_CASE_IND = 'N'
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* LINK THE ALERTS TO THEIR CASE                                            *
\**************************************************************************/

INSERT INTO <DB_ENV>DB_AML.AML_CASE_ALERT_XREF
(
       CASE_ID,
       ALERT_ID,
       ADDED_DT,
       CO_UPD_TMS
)
SELECT wrk.CASE_ID,
       na.ALERT_ID,
       rd.RUN_DT,
       rd.LOAD_TMS
FROM
       VT_NEW_ALERT                            na

       INNER JOIN
       <DB_ENV>DB_TRANS_IMPORTS.AML_CASE_WRK   wrk
          ON  wrk.PARTY_ID = na.PARTY_ID

       CROSS JOIN
       VT_RUN_DT                               rd
;
.if errorcode <> 0 then .quit errorcode;

UPDATE al
FROM   <DB_ENV>DB_AML.TM_ALERT                 al,
       VT_NEW_ALERT                            na,
       <DB_ENV>DB_TRANS_IMPORTS.AML_CASE_WRK   wrk,
       VT_RUN_DT                               rd
SET    ALERT_STATUS_CD = 'CASED',
       CASE_ID         = wrk.CASE_ID,
       CO_UPD_TMS      = rd.LOAD_TMS
WHERE  al.ALERT_ID  = na.ALERT_ID
AND    wrk.PARTY_ID = na.PARTY_ID
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* SAR CANDIDATES                                                           *
* ------------------------------------------------------------------------ *
* Cases are proposed to the Nominated Officer (POCA 2002 s.330) when       *
*  - priority 1, or                                                        *
*  - sanctions screening alert in the case, or                             *
*  - total value above GBP 50,000 for a High / Very High risk customer.   *
* DAML_IND flags a pending outbound payment, for which a Defence Against   *
* Money Laundering consent request to the NCA is required.                 *
\**************************************************************************/

CREATE VOLATILE TABLE VT_CASE_DOM_RULE AS
(
SELECT rsc.PARTY_ID,
       rsc.RULE_CD
FROM
       (
        SELECT PARTY_ID,
               RULE_CD,
               SUM (CAST (ALERT_SCORE AS INTEGER))   AS RULE_SCORE
        FROM   VT_CASE_ALERT
        GROUP  BY PARTY_ID,
                  RULE_CD
       )                                    rsc
QUALIFY ROW_NUMBER () OVER (PARTITION BY rsc.PARTY_ID
                                ORDER BY rsc.RULE_SCORE DESC,
                                         rsc.RULE_CD
                           ) = 1
) WITH DATA
UNIQUE PRIMARY INDEX (PARTY_ID)
ON COMMIT PRESERVE ROWS
;
.if errorcode <> 0 then .quit errorcode;

CREATE VOLATILE TABLE VT_DAML AS
(
SELECT txn.PARTY_ID,
       COUNT (*)                              AS PENDING_CNT
FROM
       <DB_ENV>DB_ODS.AML_TXN_DAILY            txn

       CROSS JOIN
       VT_RUN_DT                               rd
WHERE
       txn.BOOKING_DT BETWEEN rd.RUN_DT - 5 AND rd.RUN_DT
AND    txn.DR_CR_IND     = 'D'
AND    txn.TXN_STATUS_CD = 'PD'
AND    txn.PARTY_ID IN (SELECT PARTY_ID FROM <DB_ENV>DB_TRANS_IMPORTS.AML_CASE_WRK)
GROUP  BY txn.PARTY_ID
) WITH DATA
UNIQUE PRIMARY INDEX (PARTY_ID)
ON COMMIT PRESERVE ROWS
;
.if errorcode <> 0 then .quit errorcode;

DELETE FROM <DB_ENV>DB_AML.SAR_CANDIDATE
WHERE  SAR_STATUS_CD = 'DRAFT'
AND    CASE_ID IN (SELECT CASE_ID FROM <DB_ENV>DB_TRANS_IMPORTS.AML_CASE_WRK)
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_AML.SAR_CANDIDATE
(
       CASE_ID,
       PARTY_ID,
       IDENT_DT,
       SAR_REASON_CD,
       TOTAL_GBP_AMT,
       SANC_HIT_IND,
       DAML_IND,
       NARRATIVE_SUMMARY,
       SAR_STATUS_CD,
       CO_UPD_TMS
)
SELECT wrk.CASE_ID,
       wrk.PARTY_ID,
       rd.RUN_DT,
       CASE SUBSTR (dom.RULE_CD, 4, 3)
            WHEN 'STR' THEN 'STRC'
            WHEN 'RPM' THEN 'LAYR'
            WHEN 'HRC' THEN 'HRJR'
            WHEN 'RND' THEN 'RNDA'
            WHEN 'DRM' THEN 'DORM'
            WHEN 'VEL' THEN 'VELO'
            WHEN 'PEP' THEN 'PEPS'
            WHEN 'TOV' THEN 'TURN'
            WHEN 'CSH' THEN 'CASH'
            WHEN 'MUL' THEN 'MULE'
            WHEN 'GMB' THEN 'GAMB'
            WHEN 'SAN' THEN 'SANC'
            ELSE 'OTHR'
       END,
       wrk.TOTAL_HIT_GBP_AMT,
       CASE WHEN INDEX (wrk.RULE_LIST, 'TM_SAN01') > 0 THEN 'Y' ELSE 'N' END,
       CASE WHEN dml.PENDING_CNT > 0 THEN 'Y' ELSE 'N' END,
       SUBSTR (
       'CASE ' || TRIM (CAST (wrk.CASE_ID AS VARCHAR(20))) ||
       ' / PARTY ' || TRIM (wrk.PARTY_ID) ||
       ' (' || TRIM (wrk.SEGMENT_CD) || ', RISK ' || TRIM (wrk.RISK_BAND_CD) || '): ' ||
       TRIM (CAST (wrk.ALERT_CNT AS VARCHAR(10))) || ' ALERT(S) ON ' ||
       COALESCE (wrk.RULE_LIST, '-') ||
       ' BETWEEN ' || CAST (CAST (wrk.FIRST_ALERT_DT AS FORMAT 'DD/MM/YYYY') AS CHAR(10)) ||
       ' AND '     || CAST (CAST (wrk.LAST_ALERT_DT  AS FORMAT 'DD/MM/YYYY') AS CHAR(10)) ||
       ', TOTAL VALUE GBP ' ||
       TRIM (CAST (CAST (ZEROIFNULL (wrk.TOTAL_HIT_GBP_AMT) AS FORMAT 'ZZZ,ZZZ,ZZ9.99') AS VARCHAR(20))) ||
       '. DOMINANT TYPOLOGY ' || TRIM (dom.RULE_CD) || '.' ||
       CASE WHEN INDEX (wrk.RULE_LIST, 'TM_SAN01') > 0
            THEN ' OPEN SANCTIONS SCREENING MATCH - CONSIDER OFSI REPORTING.'
            ELSE ''
       END ||
       CASE WHEN dml.PENDING_CNT > 0
            THEN ' ' || TRIM (CAST (dml.PENDING_CNT AS VARCHAR(10))) ||
                 ' OUTBOUND PAYMENT(S) PENDING - DAML CONSENT REQUIRED BEFORE RELEASE.'
            ELSE ''
       END
       , 1, 1000),
       'DRAFT',
       rd.LOAD_TMS
FROM
       <DB_ENV>DB_TRANS_IMPORTS.AML_CASE_WRK   wrk

       CROSS JOIN
       VT_RUN_DT                               rd

       INNER JOIN
       VT_CASE_DOM_RULE                        dom
          ON  dom.PARTY_ID = wrk.PARTY_ID

       LEFT OUTER JOIN
       VT_DAML                                 dml
          ON  dml.PARTY_ID = wrk.PARTY_ID
WHERE
       (   wrk.CASE_PRIORITY_NR = 1
        OR INDEX (wrk.RULE_LIST, 'TM_SAN01') > 0
        OR (    wrk.TOTAL_HIT_GBP_AMT > 50000
            AND wrk.RISK_BAND_CD IN ('H', 'VH')))
AND    NOT EXISTS
       (
        SELECT 1
        FROM   <DB_ENV>DB_AML.SAR_CANDIDATE   sar
        WHERE  sar.CASE_ID = wrk.CASE_ID
       )
;
.if errorcode <> 0 then .quit errorcode;

UPDATE cse
FROM   <DB_ENV>DB_AML.AML_CASE                 cse,
       <DB_ENV>DB_AML.SAR_CANDIDATE            sar,
       <DB_ENV>DB_TRANS_IMPORTS.AML_CASE_WRK   wrk
SET    SAR_CANDIDATE_IND = 'Y'
WHERE  cse.CASE_ID = sar.CASE_ID
AND    cse.CASE_ID = wrk.CASE_ID
AND    COALESCE (cse.SAR_CANDIDATE_IND, 'N') <> 'Y'
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_AML.AML_CASE            INDEX (CASE_ID);
COLLECT STATISTICS <DB_ENV>DB_AML.AML_CASE_ALERT_XREF INDEX (CASE_ID, ALERT_ID);
COLLECT STATISTICS <DB_ENV>DB_AML.SAR_CANDIDATE       INDEX (CASE_ID);
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* AUTO-CLOSURE OF STALE CASES                                              *
* ------------------------------------------------------------------------ *
* OPEN cases (not yet picked up by an investigator) of parties without    *
* any alert in the last 90 days are closed with No Further Action.        *
* SAR candidates are never closed automatically.                           *
\**************************************************************************/

.label AUTO_CLOSE

CREATE VOLATILE TABLE VT_AUTO_CLOSE AS
(
SELECT cse.CASE_ID
FROM
       <DB_ENV>DB_AML.AML_CASE              cse

       CROSS JOIN
       VT_RUN_DT                            rd
WHERE
       cse.CASE_STATUS_CD = 'OPEN'
AND    COALESCE (cse.SAR_CANDIDATE_IND, 'N') <> 'Y'
AND    COALESCE (cse.LAST_ALERT_DT, cse.CASE_OPEN_DT) < rd.RUN_DT - 90
AND    NOT EXISTS
       (
        SELECT 1
        FROM   <DB_ENV>DB_AML.TM_ALERT   al
        WHERE  al.PARTY_ID     = cse.PARTY_ID
        AND    al.BUSINESS_DT >= rd.RUN_DT - 90
        AND    al.ALERT_STATUS_CD <> 'SUPPR'
       )
) WITH DATA
UNIQUE PRIMARY INDEX (CASE_ID)
ON COMMIT PRESERVE ROWS
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_AML.AML_CASE_HIST
(
       CASE_ID,
       UPD_TMS,
       PARTY_ID,
       CASE_OPEN_DT,
       CASE_STATUS_CD,
       CASE_PRIORITY_NR,
       QUEUE_CD,
       SLA_DUE_DT,
       ALERT_CNT,
       TOTAL_ALERT_SCORE,
       TOTAL_HIT_GBP_AMT,
       RULE_LIST,
       SAR_CANDIDATE_IND,
       RISK_BAND_CD,
       SEGMENT_CD,
       FIRST_ALERT_DT,
       LAST_ALERT_DT,
       CASE_CLOSE_DT,
       CLOSE_REASON_CD,
       HIST_ACTION_CD,
       CO_UPD_TMS
)
SELECT cse.CASE_ID,
       CURRENT_TIMESTAMP(0),
       cse.PARTY_ID,
       cse.CASE_OPEN_DT,
       cse.CASE_STATUS_CD,
       cse.CASE_PRIORITY_NR,
       cse.QUEUE_CD,
       cse.SLA_DUE_DT,
       cse.ALERT_CNT,
       cse.TOTAL_ALERT_SCORE,
       cse.TOTAL_HIT_GBP_AMT,
       cse.RULE_LIST,
       cse.SAR_CANDIDATE_IND,
       cse.RISK_BAND_CD,
       cse.SEGMENT_CD,
       cse.FIRST_ALERT_DT,
       cse.LAST_ALERT_DT,
       cse.CASE_CLOSE_DT,
       cse.CLOSE_REASON_CD,
       'U',
       cse.CO_UPD_TMS
FROM
       <DB_ENV>DB_AML.AML_CASE              cse

       INNER JOIN
       VT_AUTO_CLOSE                        acl
          ON  acl.CASE_ID = cse.CASE_ID
;
.if errorcode <> 0 then .quit errorcode;

UPDATE cse
FROM   <DB_ENV>DB_AML.AML_CASE              cse,
       VT_AUTO_CLOSE                        acl,
       VT_RUN_DT                            rd
SET    CASE_STATUS_CD  = 'CLOSD',
       CASE_CLOSE_DT   = rd.RUN_DT,
       CLOSE_REASON_CD = 'NFA',
       CO_UPD_TMS      = rd.LOAD_TMS
WHERE  cse.CASE_ID = acl.CASE_ID
;
.if errorcode <> 0 then .quit errorcode;

UPDATE al
FROM   <DB_ENV>DB_AML.TM_ALERT              al,
       VT_AUTO_CLOSE                        acl,
       VT_RUN_DT                            rd
SET    ALERT_STATUS_CD = 'CLOSD',
       CO_UPD_TMS      = rd.LOAD_TMS
WHERE  al.CASE_ID = acl.CASE_ID
AND    al.ALERT_STATUS_CD <> 'CLOSD'
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_AML.AML_CASE      COLUMN (CASE_STATUS_CD);
COLLECT STATISTICS <DB_ENV>DB_AML.AML_CASE_HIST INDEX  (CASE_ID, UPD_TMS);
COLLECT STATISTICS <DB_ENV>DB_AML.TM_ALERT      COLUMN (ALERT_STATUS_CD);
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* END OF SCRIPT                                                            *
\**************************************************************************/

.quit 0;
