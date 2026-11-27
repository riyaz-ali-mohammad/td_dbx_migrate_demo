-- TODO: manual review required — choose the production wrapper for this migrated BTEQ job (SQL script, stored procedure, or Workflows DAG).
-- TODO: manual review required — the source .GOTO AUTO_CLOSE branch was rewritten as SQL scripting IF control flow; confirm orchestration and retry behavior.
-- Converted from BTEQ to a callable Databricks SQL procedure; statement failures abort execution naturally.
CREATE OR REPLACE PROCEDURE migrated_aml_case_load()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN

/**************************************************************************\
* DETERMINE THE BUSINESS DATE OF THE CURRENT LOAD                          *
\**************************************************************************/

-- Converted Teradata volatile CTAS to a session-scoped Databricks temporary table.
CREATE TEMP TABLE VT_RUN_DT AS
(
SELECT BUSINESS_DT                 AS RUN_DT,
       LOAD_TMS                    AS LOAD_TMS
FROM   `<DB_ENV>DB_TRANS_IMPORTS`.DLYTXN_LOAD_TMS
WHERE  SSQ_ID = 1
);

SELECT RUN_DT
FROM   VT_RUN_DT
;
-- Converted BTEQ ACTIVITYCOUNT failure handling to an explicit SQL assertion.
IF NOT EXISTS (SELECT 1 FROM VT_RUN_DT) THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No business date found';
END IF;

-- Converted: routine Teradata COLLECT STATISTICS maintenance is omitted because Delta maintains optimizer statistics.


/**************************************************************************\
* COLLECT ALL NEW (UNCASED) ALERTS                                         *
* ------------------------------------------------------------------------ *
* Alerts without a party are linked to the primary holder of the account. *
* If no new alerts exist the processing continues with the auto-closure.  *
\**************************************************************************/

-- Converted Teradata volatile CTAS to a session-scoped Databricks temporary table.
CREATE TEMP TABLE VT_NEW_ALERT AS
(
SELECT al.ALERT_ID                                        AS ALERT_ID,
       al.RULE_CD                                         AS RULE_CD,
       COALESCE (al.PARTY_ID, acs.PRIMARY_PARTY_ID)       AS PARTY_ID,
       al.ACCT_ID                                         AS ACCT_ID,
       al.BUSINESS_DT                                     AS BUSINESS_DT,
       COALESCE(al.ALERT_SCORE, 0)                        AS ALERT_SCORE,
       COALESCE(al.HIT_GBP_AMT, 0)                        AS HIT_GBP_AMT
FROM
       `<DB_ENV>DB_AML`.TM_ALERT              al

       CROSS JOIN
       VT_RUN_DT                            rd

       LEFT OUTER JOIN
       `<DB_ENV>DB_ODS`.ACCT_SNAPSHOT         acs
          ON  acs.ACCT_ID = al.ACCT_ID
WHERE
       al.ALERT_STATUS_CD = 'NEW'
AND    al.CASE_ID IS NULL
AND    al.BUSINESS_DT <= rd.RUN_DT
AND    COALESCE (al.PARTY_ID, acs.PRIMARY_PARTY_ID) IS NOT NULL
);

SELECT ALERT_ID
FROM   VT_NEW_ALERT
;
-- Converted the BTEQ .GOTO AUTO_CLOSE branch to structured SQL control flow.
IF EXISTS (SELECT 1 FROM VT_NEW_ALERT) THEN

-- Converted: temporary-table COLLECT STATISTICS calls are unnecessary on Databricks.


/**************************************************************************\
* FIND AN OPEN CASE TO ATTACH TO                                           *
* ------------------------------------------------------------------------ *
* New alerts join the latest OPEN / INVST case of the party opened within  *
* the last 30 days. Otherwise a new case is created.                       *
\**************************************************************************/

-- Converted Teradata volatile CTAS to a session-scoped Databricks temporary table.
CREATE TEMP TABLE VT_OPEN_CASE AS
(
SELECT cse.CASE_ID,
       cse.PARTY_ID,
       cse.CASE_STATUS_CD,
       cse.CASE_PRIORITY_NR,
       cse.SLA_DUE_DT,
       cse.CASE_OPEN_DT
FROM
       `<DB_ENV>DB_AML`.AML_CASE              cse

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
);


/**************************************************************************\
* ALL ALERTS OF THE TARGET CASE (NEW + ALREADY ATTACHED)                   *
\**************************************************************************/

-- Converted Teradata volatile CTAS to a session-scoped Databricks temporary table.
CREATE TEMP TABLE VT_CASE_ALERT AS
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
       COALESCE(al.ALERT_SCORE, 0),
       COALESCE(al.HIT_GBP_AMT, 0),
       'E'
FROM
       `<DB_ENV>DB_AML`.TM_ALERT              al

       INNER JOIN
       VT_OPEN_CASE                         opc
          ON  opc.CASE_ID = al.CASE_ID
);


/**************************************************************************\
* CONSOLIDATE ALERTS PER PARTY INTO THE CASE WORK TABLE                    *
\**************************************************************************/

DELETE FROM `<DB_ENV>DB_TRANS_IMPORTS`.AML_CASE_WRK
;

INSERT INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_CASE_WRK
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
                     SUBSTR(LISTAGG(TRIM(dst.RULE_CD) || ',', '')
                            WITHIN GROUP (ORDER BY dst.RULE_CD), 1, 400))
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
       `<DB_ENV>DB_ODS`.PARTY_SNAPSHOT        psn
          ON  psn.PARTY_ID = agg.PARTY_ID

       LEFT OUTER JOIN
       `<DB_ENV>DB_AML`.PARTY_RISK_SCORE      prs
          ON  prs.PARTY_ID = agg.PARTY_ID
;


/**************************************************************************\
* GENERATE NEW CASE IDENTIFIERS (MAX + CSUM)                               *
\**************************************************************************/

-- Converted Teradata volatile CTAS to a session-scoped Databricks temporary table.
CREATE TEMP TABLE VT_NEW_CASE_ID AS
(
SELECT wrk.PARTY_ID,
       mx.MAX_CASE_ID + SUM(1) OVER (ORDER BY wrk.PARTY_ID ROWS UNBOUNDED PRECEDING)        AS NEW_CASE_ID
FROM
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_CASE_WRK   wrk,
       (
        SELECT COALESCE (MAX (CASE_ID), 0)     AS MAX_CASE_ID
        FROM   `<DB_ENV>DB_AML`.AML_CASE
       )                                       mx
WHERE
       wrk.CASE_ID IS NULL
);

-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_CASE_WRK AS wrk
USING VT_NEW_CASE_ID AS nid
ON wrk.PARTY_ID = nid.PARTY_ID
WHEN MATCHED THEN UPDATE SET CASE_ID = nid.NEW_CASE_ID;


/**************************************************************************\
* CASE PRIORITY (1 = HIGHEST)                                              *
* ------------------------------------------------------------------------ *
* Sanctions exposure, Very High customer risk or a total score >= 250     *
* give priority 1. An existing case never loses priority.                  *
\**************************************************************************/

UPDATE `<DB_ENV>DB_TRANS_IMPORTS`.AML_CASE_WRK
SET    CASE_PRIORITY_NR =
       CASE
          WHEN INSTR(RULE_LIST, 'TM_SAN01') > 0
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

-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_CASE_WRK AS wrk
USING VT_OPEN_CASE AS opc
ON wrk.CASE_ID = opc.CASE_ID
AND opc.CASE_PRIORITY_NR < wrk.CASE_PRIORITY_NR
WHEN MATCHED THEN UPDATE SET CASE_PRIORITY_NR = opc.CASE_PRIORITY_NR;


/**************************************************************************\
* WORK QUEUE AND SLA DUE DATE                                              *
* ------------------------------------------------------------------------ *
* Queue by segment and priority band (segment 'ALL' as fallback). The SLA  *
* is the n-th UK business day after the business date (bank holidays      *
* excluded). Default queue AMLGEN with 20 business days.                  *
\**************************************************************************/

-- Converted Teradata volatile CTAS to a session-scoped Databricks temporary table.
CREATE TEMP TABLE VT_BUS_DAY AS
(
SELECT cal.CAL_DT                                         AS CAL_DT,
       ROW_NUMBER () OVER (ORDER BY cal.CAL_DT)           AS BUS_DAY_NR
FROM
       `<DB_ENV>DB_REFERENCE`.CALENDAR        cal

       CROSS JOIN
       VT_RUN_DT                            rd

       LEFT OUTER JOIN
       `<DB_ENV>DB_REFERENCE`.UK_BANK_HOLIDAY hol
          ON  hol.HOLIDAY_DT = cal.CAL_DT
WHERE
       cal.CAL_DT      >  rd.RUN_DT
AND    cal.CAL_DT      <= rd.RUN_DT + 120
AND    cal.BUS_DAY_IND =  'Y'
AND    hol.HOLIDAY_DT IS NULL
);

-- Converted Teradata volatile CTAS to a session-scoped Databricks temporary table.
CREATE TEMP TABLE VT_QUEUE_MATCH AS
(
SELECT wrk.PARTY_ID,
       que.QUEUE_CD,
       COALESCE (que.SLA_BUS_DAYS, 20)          AS SLA_BUS_DAYS
FROM
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_CASE_WRK   wrk

       INNER JOIN
       `<DB_ENV>DB_REFERENCE`.CASE_QUEUE         que
          ON  que.SEGMENT_CD IN (wrk.SEGMENT_CD, 'ALL')
          AND wrk.CASE_PRIORITY_NR BETWEEN que.MIN_PRIORITY_NR AND que.MAX_PRIORITY_NR
QUALIFY ROW_NUMBER () OVER (PARTITION BY wrk.PARTY_ID
                                ORDER BY CASE WHEN que.SEGMENT_CD = wrk.SEGMENT_CD
                                              THEN 0 ELSE 1 END,
                                         que.QUEUE_CD
                           ) = 1
);

-- Converted Teradata UPDATE FROM to Delta MERGE with a deterministic joined source.
MERGE INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_CASE_WRK AS wrk
USING (
  SELECT qmt.PARTY_ID, qmt.QUEUE_CD, bdy.CAL_DT
  FROM VT_QUEUE_MATCH AS qmt
  INNER JOIN VT_BUS_DAY AS bdy
    ON bdy.BUS_DAY_NR = qmt.SLA_BUS_DAYS
) AS src
ON wrk.PARTY_ID = src.PARTY_ID
WHEN MATCHED THEN UPDATE SET
  QUEUE_CD = src.QUEUE_CD,
  SLA_DUE_DT = src.CAL_DT;

-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO `<DB_ENV>DB_TRANS_IMPORTS`.AML_CASE_WRK AS wrk
USING (SELECT CAL_DT FROM VT_BUS_DAY WHERE BUS_DAY_NR = 20) AS bdy
ON wrk.QUEUE_CD IS NULL OR wrk.SLA_DUE_DT IS NULL
WHEN MATCHED THEN UPDATE SET
  QUEUE_CD = COALESCE(wrk.QUEUE_CD, 'AMLGEN'),
  SLA_DUE_DT = bdy.CAL_DT;

-- Converted: routine Teradata COLLECT STATISTICS maintenance is omitted on Delta.


/**************************************************************************\
* HISTORY: BEFORE IMAGES OF EXISTING CASES                                 *
\**************************************************************************/

INSERT INTO `<DB_ENV>DB_AML`.AML_CASE_HIST
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
       CURRENT_TIMESTAMP,
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
       `<DB_ENV>DB_AML`.AML_CASE                 cse

       INNER JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_CASE_WRK   wrk
          ON  wrk.CASE_ID = cse.CASE_ID
WHERE
       wrk.EXISTING_CASE_IND = 'Y'
;


/**************************************************************************\
* UPDATE EXISTING CASES                                                    *
* ------------------------------------------------------------------------ *
* The SLA date only moves forward in time when the priority is raised.    *
\**************************************************************************/

-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO `<DB_ENV>DB_AML`.AML_CASE AS cse
USING (
  SELECT wrk.*, rd.LOAD_TMS
  FROM `<DB_ENV>DB_TRANS_IMPORTS`.AML_CASE_WRK AS wrk
  CROSS JOIN VT_RUN_DT AS rd
  WHERE wrk.EXISTING_CASE_IND = 'Y'
) AS src
ON cse.CASE_ID = src.CASE_ID
WHEN MATCHED THEN UPDATE SET
  CASE_PRIORITY_NR  = src.CASE_PRIORITY_NR,
  QUEUE_CD          = CASE WHEN src.CASE_PRIORITY_NR < cse.CASE_PRIORITY_NR THEN src.QUEUE_CD ELSE cse.QUEUE_CD END,
  SLA_DUE_DT        = CASE WHEN src.CASE_PRIORITY_NR < cse.CASE_PRIORITY_NR AND src.SLA_DUE_DT < cse.SLA_DUE_DT THEN src.SLA_DUE_DT ELSE cse.SLA_DUE_DT END,
  ALERT_CNT         = src.ALERT_CNT,
  TOTAL_ALERT_SCORE = src.TOTAL_ALERT_SCORE,
  TOTAL_HIT_GBP_AMT = src.TOTAL_HIT_GBP_AMT,
  RULE_LIST         = src.RULE_LIST,
  RISK_BAND_CD      = src.RISK_BAND_CD,
  FIRST_ALERT_DT    = src.FIRST_ALERT_DT,
  LAST_ALERT_DT     = src.LAST_ALERT_DT,
  CO_UPD_TMS        = src.LOAD_TMS;


/**************************************************************************\
* OPEN NEW CASES                                                           *
\**************************************************************************/

INSERT INTO `<DB_ENV>DB_AML`.AML_CASE
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
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_CASE_WRK   wrk

       CROSS JOIN
       VT_RUN_DT                               rd
WHERE
       wrk.EXISTING_CASE_IND = 'N'
;

INSERT INTO `<DB_ENV>DB_AML`.AML_CASE_HIST
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
       CURRENT_TIMESTAMP,
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
       `<DB_ENV>DB_AML`.AML_CASE                 cse

       INNER JOIN
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_CASE_WRK   wrk
          ON  wrk.CASE_ID = cse.CASE_ID
WHERE
       wrk.EXISTING_CASE_IND = 'N'
;


/**************************************************************************\
* LINK THE ALERTS TO THEIR CASE                                            *
\**************************************************************************/

INSERT INTO `<DB_ENV>DB_AML`.AML_CASE_ALERT_XREF
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
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_CASE_WRK   wrk
          ON  wrk.PARTY_ID = na.PARTY_ID

       CROSS JOIN
       VT_RUN_DT                               rd
;

-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO `<DB_ENV>DB_AML`.TM_ALERT AS al
USING (
  SELECT na.ALERT_ID, wrk.CASE_ID, rd.LOAD_TMS
  FROM VT_NEW_ALERT AS na
  INNER JOIN `<DB_ENV>DB_TRANS_IMPORTS`.AML_CASE_WRK AS wrk
    ON wrk.PARTY_ID = na.PARTY_ID
  CROSS JOIN VT_RUN_DT AS rd
) AS src
ON al.ALERT_ID = src.ALERT_ID
WHEN MATCHED THEN UPDATE SET
  ALERT_STATUS_CD = 'CASED',
  CASE_ID = src.CASE_ID,
  CO_UPD_TMS = src.LOAD_TMS;


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

-- Converted Teradata volatile CTAS to a session-scoped Databricks temporary table.
CREATE TEMP TABLE VT_CASE_DOM_RULE AS
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
);

-- Converted Teradata volatile CTAS to a session-scoped Databricks temporary table.
CREATE TEMP TABLE VT_DAML AS
(
SELECT txn.PARTY_ID,
       COUNT (*)                              AS PENDING_CNT
FROM
       `<DB_ENV>DB_ODS`.AML_TXN_DAILY            txn

       CROSS JOIN
       VT_RUN_DT                               rd
WHERE
       txn.BOOKING_DT BETWEEN rd.RUN_DT - 5 AND rd.RUN_DT
AND    txn.DR_CR_IND     = 'D'
AND    txn.TXN_STATUS_CD = 'PD'
AND    txn.PARTY_ID IN (SELECT PARTY_ID FROM `<DB_ENV>DB_TRANS_IMPORTS`.AML_CASE_WRK)
GROUP  BY txn.PARTY_ID
);

DELETE FROM `<DB_ENV>DB_AML`.SAR_CANDIDATE
WHERE  SAR_STATUS_CD = 'DRAFT'
AND    CASE_ID IN (SELECT CASE_ID FROM `<DB_ENV>DB_TRANS_IMPORTS`.AML_CASE_WRK)
;

INSERT INTO `<DB_ENV>DB_AML`.SAR_CANDIDATE
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
       CASE WHEN INSTR(wrk.RULE_LIST, 'TM_SAN01') > 0 THEN 'Y' ELSE 'N' END,
       CASE WHEN dml.PENDING_CNT > 0 THEN 'Y' ELSE 'N' END,
       SUBSTR (
       'CASE ' || TRIM (CAST (wrk.CASE_ID AS VARCHAR(20))) ||
       ' / PARTY ' || TRIM (wrk.PARTY_ID) ||
       ' (' || TRIM (wrk.SEGMENT_CD) || ', RISK ' || TRIM (wrk.RISK_BAND_CD) || '): ' ||
       TRIM (CAST (wrk.ALERT_CNT AS VARCHAR(10))) || ' ALERT(S) ON ' ||
       COALESCE (wrk.RULE_LIST, '-') ||
       ' BETWEEN ' || DATE_FORMAT(wrk.FIRST_ALERT_DT, 'dd/MM/yyyy') ||
       ' AND '     || DATE_FORMAT(wrk.LAST_ALERT_DT, 'dd/MM/yyyy') ||
       ', TOTAL VALUE GBP ' ||
       FORMAT_NUMBER(COALESCE(wrk.TOTAL_HIT_GBP_AMT, 0), 2) ||
       '. DOMINANT TYPOLOGY ' || TRIM (dom.RULE_CD) || '.' ||
       CASE WHEN INSTR(wrk.RULE_LIST, 'TM_SAN01') > 0
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
       `<DB_ENV>DB_TRANS_IMPORTS`.AML_CASE_WRK   wrk

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
        OR INSTR(wrk.RULE_LIST, 'TM_SAN01') > 0
        OR (    wrk.TOTAL_HIT_GBP_AMT > 50000
            AND wrk.RISK_BAND_CD IN ('H', 'VH')))
AND    NOT EXISTS
       (
        SELECT 1
        FROM   `<DB_ENV>DB_AML`.SAR_CANDIDATE   sar
        WHERE  sar.CASE_ID = wrk.CASE_ID
       )
;

-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO `<DB_ENV>DB_AML`.AML_CASE AS cse
USING (
  SELECT sar.CASE_ID
  FROM `<DB_ENV>DB_AML`.SAR_CANDIDATE AS sar
  INNER JOIN `<DB_ENV>DB_TRANS_IMPORTS`.AML_CASE_WRK AS wrk
    ON wrk.CASE_ID = sar.CASE_ID
) AS src
ON cse.CASE_ID = src.CASE_ID
AND COALESCE(cse.SAR_CANDIDATE_IND, 'N') <> 'Y'
WHEN MATCHED THEN UPDATE SET SAR_CANDIDATE_IND = 'Y';

-- Converted: routine Teradata index statistics maintenance is omitted on Delta.


/**************************************************************************\
* AUTO-CLOSURE OF STALE CASES                                              *
* ------------------------------------------------------------------------ *
* OPEN cases (not yet picked up by an investigator) of parties without    *
* any alert in the last 90 days are closed with No Further Action.        *
* SAR candidates are never closed automatically.                           *
\**************************************************************************/

END IF;

-- The AUTO_CLOSE label is now the continuation after the structured IF block.

-- Converted Teradata volatile CTAS to a session-scoped Databricks temporary table.
CREATE TEMP TABLE VT_AUTO_CLOSE AS
(
SELECT cse.CASE_ID
FROM
       `<DB_ENV>DB_AML`.AML_CASE              cse

       CROSS JOIN
       VT_RUN_DT                            rd
WHERE
       cse.CASE_STATUS_CD = 'OPEN'
AND    COALESCE (cse.SAR_CANDIDATE_IND, 'N') <> 'Y'
AND    COALESCE (cse.LAST_ALERT_DT, cse.CASE_OPEN_DT) < rd.RUN_DT - 90
AND    NOT EXISTS
       (
        SELECT 1
        FROM   `<DB_ENV>DB_AML`.TM_ALERT   al
        WHERE  al.PARTY_ID     = cse.PARTY_ID
        AND    al.BUSINESS_DT >= rd.RUN_DT - 90
        AND    al.ALERT_STATUS_CD <> 'SUPPR'
       )
);

INSERT INTO `<DB_ENV>DB_AML`.AML_CASE_HIST
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
       CURRENT_TIMESTAMP,
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
       `<DB_ENV>DB_AML`.AML_CASE              cse

       INNER JOIN
       VT_AUTO_CLOSE                        acl
          ON  acl.CASE_ID = cse.CASE_ID
;

-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO `<DB_ENV>DB_AML`.AML_CASE AS cse
USING (
  SELECT acl.CASE_ID, rd.RUN_DT, rd.LOAD_TMS
  FROM VT_AUTO_CLOSE AS acl
  CROSS JOIN VT_RUN_DT AS rd
) AS src
ON cse.CASE_ID = src.CASE_ID
WHEN MATCHED THEN UPDATE SET
  CASE_STATUS_CD = 'CLOSD',
  CASE_CLOSE_DT = src.RUN_DT,
  CLOSE_REASON_CD = 'NFA',
  CO_UPD_TMS = src.LOAD_TMS;

-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO `<DB_ENV>DB_AML`.TM_ALERT AS al
USING (
  SELECT acl.CASE_ID, rd.LOAD_TMS
  FROM VT_AUTO_CLOSE AS acl
  CROSS JOIN VT_RUN_DT AS rd
) AS src
ON al.CASE_ID = src.CASE_ID
AND al.ALERT_STATUS_CD <> 'CLOSD'
WHEN MATCHED THEN UPDATE SET
  ALERT_STATUS_CD = 'CLOSD',
  CO_UPD_TMS = src.LOAD_TMS;

-- Converted: routine Teradata COLLECT STATISTICS maintenance is omitted on Delta.


/**************************************************************************\
* END OF SCRIPT                                                            *
\**************************************************************************/

END;
