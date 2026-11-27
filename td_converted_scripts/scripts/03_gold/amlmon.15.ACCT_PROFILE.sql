-- TODO: manual review required — choose a Databricks notebook, stored procedure, or Workflows DAG as the wrapper for this converted BTEQ script.
-- TODO: manual review required — implement the former BTEQ ERRORCODE/ACTIVITYCOUNT exit checks as procedure SIGNAL logic or Workflows task conditions.

/**************************************************************************\
* DETERMINE THE BUSINESS DATE OF THE CURRENT LOAD                          *
* ------------------------------------------------------------------------ *
* All monitoring steps run against the business date taken by the daily   *
* transaction stream (dailytxn.03). The step aborts if no date is found.  *
\**************************************************************************/

-- Converted Teradata volatile table to a Databricks session temporary table; PI and ON COMMIT clauses are removed below.
CREATE TEMP TABLE VT_RUN_DT AS
(
SELECT BUSINESS_DT                 AS RUN_DT,
       LOAD_TMS                    AS LOAD_TMS
FROM   DLYTXN_LOAD_TMS
WHERE  SSQ_ID = 1
);

SELECT RUN_DT
FROM   VT_RUN_DT
;


/**************************************************************************\
* COLLECT STATISTICS ON SOURCE TABLES                                      *
\**************************************************************************/



/**************************************************************************\
* IDENTIFY THE BOOKING DATES TOUCHED BY THE CURRENT LOAD                   *
* ------------------------------------------------------------------------ *
* Late and back-valued postings arrive with booking dates in the past.     *
* Every booking date received in this load (max. 120 days back) is re-     *
* summarised so that rolling windows stay correct.                         *
\**************************************************************************/

-- Converted Teradata volatile table to a Databricks session temporary table; PI and ON COMMIT clauses are removed below.
CREATE TEMP TABLE VT_SUMM_DT AS
(
SELECT DISTINCT
       txn.BOOKING_DT              AS BUSINESS_DT
FROM   AML_TXN_DAILY     txn

       INNER JOIN
       VT_RUN_DT                        rd
          ON  txn.LOAD_TMS = rd.LOAD_TMS
WHERE  txn.BOOKING_DT BETWEEN rd.RUN_DT - 120 AND rd.RUN_DT

UNION

SELECT RUN_DT
FROM   VT_RUN_DT
);


/**************************************************************************\
* RESOLVE THE STRUCTURING THRESHOLD PER SEGMENT                            *
* ------------------------------------------------------------------------ *
* Near-threshold cash = cash credit between PCT_THRESHOLD % of the rule    *
* amount and the amount itself (rule TM_STR01). Segment specific values    *
* override the 'ALL' default. Hard defaults: GBP 10,000 / 90 %.            *
\**************************************************************************/

-- Converted Teradata volatile table to a Databricks session temporary table; PI and ON COMMIT clauses are removed below.
CREATE TEMP TABLE VT_STR_PARAM AS
(
SELECT seg.SEGMENT_CD                                              AS SEGMENT_CD,
       COALESCE (sp.AMT_THRESHOLD, ap.AMT_THRESHOLD, 10000.00)     AS AMT_THRESHOLD,
       COALESCE (sp.PCT_THRESHOLD, ap.PCT_THRESHOLD, 90.00)        AS PCT_THRESHOLD
FROM
       (
        SELECT SEGMENT_CD
        FROM   PRDT_SNAPSHOT
        WHERE  SEGMENT_CD IS NOT NULL
        GROUP  BY SEGMENT_CD
       )                                          seg

       LEFT OUTER JOIN
       TM_RULE_PARAM_SNAPSHOT      sp
          ON  sp.RULE_CD    = 'TM_STR01'
          AND sp.SEGMENT_CD = seg.SEGMENT_CD

       LEFT OUTER JOIN
       TM_RULE_PARAM_SNAPSHOT      ap
          ON  ap.RULE_CD    = 'TM_STR01'
          AND ap.SEGMENT_CD = 'ALL'
);


/**************************************************************************\
* RE-SUMMARISE ACCOUNT ACTIVITY PER BOOKING DATE                           *
* ------------------------------------------------------------------------ *
* Reversed postings and rejected payments are not part of the customer's  *
* behaviour and are excluded. Amounts are always summed as absolute GBP.  *
\**************************************************************************/

DELETE FROM ACCT_DAILY_SUMM
WHERE  BUSINESS_DT IN (SELECT BUSINESS_DT FROM VT_SUMM_DT)
;

-- Converted Teradata ZEROIFNULL calls in this statement to two-argument COALESCE expressions.
INSERT INTO ACCT_DAILY_SUMM
(
       ACCT_ID,
       BUSINESS_DT,
       PARTY_ID,
       SEGMENT_CD,
       CR_CNT,
       CR_GBP_AMT,
       DR_CNT,
       DR_GBP_AMT,
       CASH_CR_CNT,
       CASH_CR_GBP_AMT,
       CASH_DR_CNT,
       CASH_DR_GBP_AMT,
       XBORDER_CNT,
       XBORDER_GBP_AMT,
       HRC_CNT,
       HRC_GBP_AMT,
       ROUND_AMT_CNT,
       NEAR_THRESHOLD_CASH_CNT,
       DISTINCT_CPTY_CR_CNT,
       DISTINCT_CPTY_DR_CNT,
       MAX_TXN_GBP_AMT,
       GAMBLING_GBP_AMT,
       CRYPTO_GBP_AMT,
       CO_UPD_TMS
)
SELECT txn.ACCT_ID,
       txn.BOOKING_DT,
       MAX (txn.PARTY_ID),
       MAX (COALESCE (txn.SEGMENT_CD, 'RET')),
       SUM (CASE WHEN txn.DR_CR_IND = 'C' THEN 1 ELSE 0 END),
       COALESCE (SUM (CASE WHEN txn.DR_CR_IND = 'C' THEN ABS (txn.GBP_AMT) END), 0),
       SUM (CASE WHEN txn.DR_CR_IND = 'D' THEN 1 ELSE 0 END),
       COALESCE (SUM (CASE WHEN txn.DR_CR_IND = 'D' THEN ABS (txn.GBP_AMT) END), 0),
       SUM (CASE WHEN txn.DR_CR_IND = 'C' AND txn.CASH_IND = 'Y' THEN 1 ELSE 0 END),
       COALESCE (SUM (CASE WHEN txn.DR_CR_IND = 'C' AND txn.CASH_IND = 'Y'
                             THEN ABS (txn.GBP_AMT) END), 0),
       SUM (CASE WHEN txn.DR_CR_IND = 'D' AND txn.CASH_IND = 'Y' THEN 1 ELSE 0 END),
       COALESCE (SUM (CASE WHEN txn.DR_CR_IND = 'D' AND txn.CASH_IND = 'Y'
                             THEN ABS (txn.GBP_AMT) END), 0),
       SUM (CASE WHEN txn.XBORDER_IND = 'Y' THEN 1 ELSE 0 END),
       COALESCE (SUM (CASE WHEN txn.XBORDER_IND = 'Y' THEN ABS (txn.GBP_AMT) END), 0),
       SUM (CASE WHEN txn.HRC_IND = 'Y' THEN 1 ELSE 0 END),
       COALESCE (SUM (CASE WHEN txn.HRC_IND = 'Y' THEN ABS (txn.GBP_AMT) END), 0),
       SUM (CASE WHEN txn.ROUND_AMT_IND = 'Y' THEN 1 ELSE 0 END),
       SUM (CASE WHEN txn.DR_CR_IND = 'C'
                  AND txn.CASH_IND  = 'Y'
                  AND ABS (txn.GBP_AMT) >= stp.AMT_THRESHOLD * stp.PCT_THRESHOLD / 100
                  AND ABS (txn.GBP_AMT) <  stp.AMT_THRESHOLD
                 THEN 1 ELSE 0 END),
       COUNT (DISTINCT CASE WHEN txn.DR_CR_IND = 'C' THEN txn.CPTY_ID END),
       COUNT (DISTINCT CASE WHEN txn.DR_CR_IND = 'D' THEN txn.CPTY_ID END),
       MAX (ABS (txn.GBP_AMT)),
       COALESCE (SUM (CASE WHEN txn.DR_CR_IND = 'D' AND mcc.GAMBLING_IND = 'Y'
                             THEN ABS (txn.GBP_AMT) END), 0),
       COALESCE (SUM (CASE WHEN txn.DR_CR_IND = 'D' AND mcc.CRYPTO_IND = 'Y'
                             THEN ABS (txn.GBP_AMT) END), 0),
       MAX (rd.LOAD_TMS)
FROM
       AML_TXN_DAILY         txn

       INNER JOIN
       VT_SUMM_DT                           sd
          ON  sd.BUSINESS_DT = txn.BOOKING_DT

       CROSS JOIN
       VT_RUN_DT                            rd

       LEFT OUTER JOIN
       MCC_SNAPSHOT          mcc
          ON  mcc.MCC_CD = txn.MCC_CD

       LEFT OUTER JOIN
       VT_STR_PARAM                         stp
          ON  stp.SEGMENT_CD = COALESCE (txn.SEGMENT_CD, 'RET')
WHERE
       COALESCE (txn.REVERSAL_IND, 'N')   <> 'Y'
AND    COALESCE (txn.TXN_STATUS_CD, 'BK') NOT IN ('RJ', 'RV')
AND    txn.GBP_AMT IS NOT NULL
GROUP  BY txn.ACCT_ID,
          txn.BOOKING_DT
;



/**************************************************************************\
* BUILD A DENSE 30 DAY ACCOUNT x CALENDAR GRID                             *
* ------------------------------------------------------------------------ *
* Moving aggregates need one row per calendar day, also on days without   *
* activity. Only accounts with activity in the last 30 days are profiled. *
\**************************************************************************/

-- Converted Teradata volatile table to a Databricks session temporary table; PI and ON COMMIT clauses are removed below.
-- Converted Teradata ZEROIFNULL calls in this statement to two-argument COALESCE expressions.
CREATE TEMP TABLE VT_PROF_GRID AS
(
SELECT acc.ACCT_ID                                  AS ACCT_ID,
       cal.CAL_DT                                   AS CAL_DT,
       rd.RUN_DT                                    AS RUN_DT,
       COALESCE (sm.CR_GBP_AMT, 0)                   AS CR_GBP_AMT,
       COALESCE (sm.DR_GBP_AMT, 0)                   AS DR_GBP_AMT,
       COALESCE (sm.CASH_CR_GBP_AMT, 0)              AS CASH_CR_GBP_AMT,
       COALESCE (sm.NEAR_THRESHOLD_CASH_CNT, 0)      AS NEAR_THRESHOLD_CASH_CNT,
       COALESCE (sm.ROUND_AMT_CNT, 0)                AS ROUND_AMT_CNT,
       COALESCE (sm.HRC_GBP_AMT, 0)                  AS HRC_GBP_AMT
FROM
       (
        SELECT s.ACCT_ID
        FROM   ACCT_DAILY_SUMM  s
               CROSS JOIN
               VT_RUN_DT                       r
        WHERE  s.BUSINESS_DT BETWEEN r.RUN_DT - 29 AND r.RUN_DT
        GROUP  BY s.ACCT_ID
       )                                    acc

       CROSS JOIN
       VT_RUN_DT                            rd

       INNER JOIN
       CALENDAR        cal
          ON  cal.CAL_DT BETWEEN rd.RUN_DT - 29 AND rd.RUN_DT

       LEFT OUTER JOIN
       ACCT_DAILY_SUMM       sm
          ON  sm.ACCT_ID     = acc.ACCT_ID
          AND sm.BUSINESS_DT = cal.CAL_DT
);



/**************************************************************************\
* 7 DAY MOVING TOTALS (LEGACY MSUM)                                        *
* ------------------------------------------------------------------------ *
* The GROUP BY resets the moving window per account.                       *
\**************************************************************************/

-- Converted Teradata volatile table to a Databricks session temporary table; PI and ON COMMIT clauses are removed below.
CREATE TEMP TABLE VT_PROF_7D AS
(
-- Converted Teradata MSUM functions and their GROUP BY partition reset to ANSI window aggregates.
SELECT ACCT_ID,
       CAL_DT,
       SUM (CR_GBP_AMT) OVER (
           PARTITION BY ACCT_ID ORDER BY CAL_DT
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS ROLL_7D_CR_GBP_AMT,
       SUM (CASH_CR_GBP_AMT) OVER (
           PARTITION BY ACCT_ID ORDER BY CAL_DT
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS ROLL_7D_CASH_CR_GBP_AMT,
       SUM (NEAR_THRESHOLD_CASH_CNT) OVER (
           PARTITION BY ACCT_ID ORDER BY CAL_DT
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS ROLL_7D_NEAR_THRESH_CNT,
       RUN_DT
FROM   VT_PROF_GRID
QUALIFY CAL_DT = RUN_DT
);


/**************************************************************************\
* 30 DAY ROLLING TOTALS (ANSI WINDOW)                                      *
\**************************************************************************/

-- Converted Teradata volatile table to a Databricks session temporary table; PI and ON COMMIT clauses are removed below.
CREATE TEMP TABLE VT_PROF_30D AS
(
SELECT ACCT_ID,
       SUM (CR_GBP_AMT)      OVER (PARTITION BY ACCT_ID ORDER BY CAL_DT
                                   ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS ROLL_30D_CR_GBP_AMT,
       SUM (DR_GBP_AMT)      OVER (PARTITION BY ACCT_ID ORDER BY CAL_DT
                                   ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS ROLL_30D_DR_GBP_AMT,
       SUM (CASH_CR_GBP_AMT) OVER (PARTITION BY ACCT_ID ORDER BY CAL_DT
                                   ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS ROLL_30D_CASH_CR_GBP_AMT,
       SUM (ROUND_AMT_CNT)   OVER (PARTITION BY ACCT_ID ORDER BY CAL_DT
                                   ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS ROLL_30D_ROUND_AMT_CNT,
       SUM (HRC_GBP_AMT)     OVER (PARTITION BY ACCT_ID ORDER BY CAL_DT
                                   ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS ROLL_30D_HRC_GBP_AMT
FROM   VT_PROF_GRID
QUALIFY CAL_DT = RUN_DT
);


/**************************************************************************\
* PRIOR PERIOD BASELINE (DAYS -120 .. -31 = 3 MONTHS)                      *
\**************************************************************************/

-- Converted Teradata volatile table to a Databricks session temporary table; PI and ON COMMIT clauses are removed below.
-- Converted Teradata ZEROIFNULL call in this statement to a two-argument COALESCE expression.
CREATE TEMP TABLE VT_PROF_PRIOR AS
(
SELECT grd.ACCT_ID                                              AS ACCT_ID,
       COALESCE (SUM (sm.CR_GBP_AMT), 0) / 3                     AS PRIOR_90D_AVG_MTH_CR_AMT
FROM
       (SELECT DISTINCT ACCT_ID FROM VT_PROF_GRID)   grd

       CROSS JOIN
       VT_RUN_DT                                     rd

       LEFT OUTER JOIN
       ACCT_DAILY_SUMM                sm
          ON  sm.ACCT_ID     = grd.ACCT_ID
          AND sm.BUSINESS_DT BETWEEN rd.RUN_DT - 120 AND rd.RUN_DT - 31
GROUP  BY grd.ACCT_ID
);


/**************************************************************************\
* DISTINCT PAYERS IN THE LAST 3 DAYS (FAN-IN INDICATOR)                    *
* ------------------------------------------------------------------------ *
* Distinct counts cannot be rolled up from the daily summary, therefore   *
* they are taken directly from the transaction fact.                       *
\**************************************************************************/

-- Converted Teradata volatile table to a Databricks session temporary table; PI and ON COMMIT clauses are removed below.
CREATE TEMP TABLE VT_PROF_CPTY AS
(
SELECT txn.ACCT_ID                               AS ACCT_ID,
       COUNT (DISTINCT txn.CPTY_ID)              AS ROLL_3D_CPTY_CR_CNT
FROM
       AML_TXN_DAILY      txn

       CROSS JOIN
       VT_RUN_DT                         rd
WHERE
       txn.BOOKING_DT BETWEEN rd.RUN_DT - 2 AND rd.RUN_DT
AND    txn.DR_CR_IND = 'C'
AND    txn.CPTY_ID IS NOT NULL
AND    COALESCE (txn.REVERSAL_IND, 'N')   <> 'Y'
AND    COALESCE (txn.TXN_STATUS_CD, 'BK') NOT IN ('RJ', 'RV')
GROUP  BY txn.ACCT_ID
);


/**************************************************************************\
* DAYS SINCE PREVIOUS CUSTOMER ACTIVITY                                    *
* ------------------------------------------------------------------------ *
* Full summary history is searched. If no earlier summary exists the last  *
* activity date from the KYC account feed, or the open date, is used.     *
\**************************************************************************/

-- Converted Teradata volatile table to a Databricks session temporary table; PI and ON COMMIT clauses are removed below.
CREATE TEMP TABLE VT_PROF_PREV AS
(
-- Converted Teradata DATE subtraction to DATEDIFF so the result remains an integer day count.
SELECT grd.ACCT_ID                                                  AS ACCT_ID,
       DATEDIFF(
           rd.RUN_DT,
           COALESCE (prv.PREV_ACTV_DT,
                     CASE WHEN acs.LAST_CUST_ACTV_DT < rd.RUN_DT
                          THEN acs.LAST_CUST_ACTV_DT
                     END,
                     acs.OPEN_DT,
                     rd.RUN_DT))                                    AS DAYS_SINCE_PREV_ACTV
FROM
       (SELECT DISTINCT ACCT_ID FROM VT_PROF_GRID)   grd

       CROSS JOIN
       VT_RUN_DT                                     rd

       LEFT OUTER JOIN
       (
        SELECT s.ACCT_ID,
               MAX (s.BUSINESS_DT)       AS PREV_ACTV_DT
        FROM   ACCT_DAILY_SUMM  s
               CROSS JOIN
               VT_RUN_DT                       r
        WHERE  s.BUSINESS_DT < r.RUN_DT
        AND    s.CR_CNT + s.DR_CNT > 0
        GROUP  BY s.ACCT_ID
       )                                             prv
          ON  prv.ACCT_ID = grd.ACCT_ID

       LEFT OUTER JOIN
       ACCT_SNAPSHOT                  acs
          ON  acs.ACCT_ID = grd.ACCT_ID
);


/**************************************************************************\
* YEAR-TO-DATE CUMULATIVE CREDITS (LEGACY CSUM)                            *
\**************************************************************************/

-- Converted Teradata volatile table to a Databricks session temporary table; PI and ON COMMIT clauses are removed below.
CREATE TEMP TABLE VT_PROF_CUM_ALL AS
(
-- Converted Teradata CSUM and its GROUP BY partition reset to an ANSI cumulative window aggregate.
SELECT sm.ACCT_ID,
       sm.BUSINESS_DT,
       SUM (sm.CR_GBP_AMT) OVER (
           PARTITION BY sm.ACCT_ID ORDER BY sm.BUSINESS_DT
           ROWS UNBOUNDED PRECEDING)              AS CUM_CR_GBP_AMT
FROM
       ACCT_DAILY_SUMM      sm

       INNER JOIN
       (SELECT DISTINCT ACCT_ID FROM VT_PROF_GRID)   grd
          ON  grd.ACCT_ID = sm.ACCT_ID

       CROSS JOIN
       VT_RUN_DT                           rd
WHERE
       sm.BUSINESS_DT BETWEEN TRUNC (rd.RUN_DT, 'Y') AND rd.RUN_DT
);

-- Converted Teradata volatile table to a Databricks session temporary table; PI and ON COMMIT clauses are removed below.
CREATE TEMP TABLE VT_PROF_CUM AS
(
SELECT ACCT_ID,
       CUM_CR_GBP_AMT
FROM   VT_PROF_CUM_ALL
QUALIFY SUM (1) OVER (PARTITION BY  ACCT_ID
                          ORDER BY  BUSINESS_DT DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
);


/**************************************************************************\
* POPULATE THE ACCOUNT BEHAVIOUR PROFILE FOR THE BUSINESS DATE             *
\**************************************************************************/

DELETE FROM ACCT_BEHAV_PROFILE
WHERE  BUSINESS_DT = (SELECT RUN_DT FROM VT_RUN_DT)
;

-- Converted Teradata ZEROIFNULL and NULLIFZERO calls to COALESCE and NULLIF.
INSERT INTO ACCT_BEHAV_PROFILE
(
       ACCT_ID,
       BUSINESS_DT,
       PARTY_ID,
       SEGMENT_CD,
       ROLL_7D_CR_GBP_AMT,
       ROLL_7D_CASH_CR_GBP_AMT,
       ROLL_7D_NEAR_THRESH_CNT,
       ROLL_30D_CR_GBP_AMT,
       ROLL_30D_DR_GBP_AMT,
       ROLL_30D_CASH_CR_GBP_AMT,
       ROLL_30D_ROUND_AMT_CNT,
       ROLL_30D_HRC_GBP_AMT,
       ROLL_3D_CPTY_CR_CNT,
       PRIOR_90D_AVG_MTH_CR_AMT,
       VELOCITY_RATIO,
       DAYS_SINCE_PREV_ACTV,
       CUM_CR_GBP_AMT,
       CO_UPD_TMS
)
SELECT p7.ACCT_ID,
       rd.RUN_DT,
       acs.PRIMARY_PARTY_ID,
       COALESCE (acs.SEGMENT_CD, 'RET'),
       p7.ROLL_7D_CR_GBP_AMT,
       p7.ROLL_7D_CASH_CR_GBP_AMT,
       p7.ROLL_7D_NEAR_THRESH_CNT,
       p30.ROLL_30D_CR_GBP_AMT,
       p30.ROLL_30D_DR_GBP_AMT,
       p30.ROLL_30D_CASH_CR_GBP_AMT,
       p30.ROLL_30D_ROUND_AMT_CNT,
       p30.ROLL_30D_HRC_GBP_AMT,
       COALESCE (cpt.ROLL_3D_CPTY_CR_CNT, 0),
       ppr.PRIOR_90D_AVG_MTH_CR_AMT,
       CASE
          WHEN ppr.PRIOR_90D_AVG_MTH_CR_AMT IS NULL
            OR ppr.PRIOR_90D_AVG_MTH_CR_AMT = 0
          THEN NULL
          WHEN p30.ROLL_30D_CR_GBP_AMT / ppr.PRIOR_90D_AVG_MTH_CR_AMT > 9999999
          THEN 9999999.99
          ELSE CAST (p30.ROLL_30D_CR_GBP_AMT / NULLIF (ppr.PRIOR_90D_AVG_MTH_CR_AMT, 0)
                     AS DECIMAL(9,2))
       END,
       prv.DAYS_SINCE_PREV_ACTV,
       COALESCE (cum.CUM_CR_GBP_AMT, 0),
       rd.LOAD_TMS
FROM
       VT_PROF_7D                           p7

       CROSS JOIN
       VT_RUN_DT                            rd

       INNER JOIN
       VT_PROF_30D                          p30
          ON  p30.ACCT_ID = p7.ACCT_ID

       INNER JOIN
       VT_PROF_PRIOR                        ppr
          ON  ppr.ACCT_ID = p7.ACCT_ID

       INNER JOIN
       VT_PROF_PREV                         prv
          ON  prv.ACCT_ID = p7.ACCT_ID

       LEFT OUTER JOIN
       VT_PROF_CPTY                         cpt
          ON  cpt.ACCT_ID = p7.ACCT_ID

       LEFT OUTER JOIN
       VT_PROF_CUM                          cum
          ON  cum.ACCT_ID = p7.ACCT_ID

       LEFT OUTER JOIN
       ACCT_SNAPSHOT         acs
          ON  acs.ACCT_ID = p7.ACCT_ID
;



/**************************************************************************\
* END OF SCRIPT                                                            *
\**************************************************************************/

