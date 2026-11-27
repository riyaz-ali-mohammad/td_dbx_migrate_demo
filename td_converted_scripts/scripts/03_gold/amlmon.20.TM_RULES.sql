-- TODO: manual review required — choose the execution wrapper for this migrated BTEQ script: Databricks notebook, stored procedure, or Workflows DAG.
-- TODO: manual review required — confirm whether BTEQ error exits should rely on Databricks fail-fast execution or become explicit SIGNAL/Workflow branches.
-- Converted from BTEQ display and control commands to executable Databricks SQL; display settings and successful exit commands are removed.

/**************************************************************************\
* DETERMINE THE BUSINESS DATE OF THE CURRENT LOAD                          *
\**************************************************************************/

-- Converted Teradata VOLATILE TABLE to a session-scoped TEMP TABLE; PRIMARY INDEX and ON COMMIT clauses are removed.
CREATE TEMP TABLE VT_RUN_DT AS
(
SELECT BUSINESS_DT                 AS RUN_DT,
       LOAD_TMS                    AS LOAD_TMS
FROM   DLYTXN_LOAD_TMS
WHERE  SSQ_ID = 1
)
;

SELECT RUN_DT
FROM   VT_RUN_DT
;
-- Converted from BTEQ ACTIVITYCOUNT validation to an explicit Databricks SQL assertion.
SELECT CASE WHEN COUNT(*) = 0 THEN raise_error('VT_RUN_DT returned no rows (BTEQ exit 8)') ELSE COUNT(*) END AS validated_row_count
FROM VT_RUN_DT;


/**************************************************************************\
* RESOLVE RULE PARAMETERS PER SEGMENT                                      *
* ------------------------------------------------------------------------ *
* Every rule is parameterised per customer segment (RET, BUS, CIB, WLT).   *
* Where no segment specific row exists the 'ALL' row applies. Rules with   *
* neither are not executed for the segment.                                *
\**************************************************************************/

-- Converted Teradata VOLATILE TABLE to a session-scoped TEMP TABLE; PRIMARY INDEX and ON COMMIT clauses are removed.
CREATE TEMP TABLE VT_SEGMENT AS
(
SELECT SEGMENT_CD
FROM   PRDT_SNAPSHOT
WHERE  SEGMENT_CD IS NOT NULL

UNION

SELECT SEGMENT_CD
FROM   TM_RULE_PARAM_SNAPSHOT
WHERE  SEGMENT_CD <> 'ALL'
)
;

-- Converted Teradata VOLATILE TABLE to a session-scoped TEMP TABLE; PRIMARY INDEX and ON COMMIT clauses are removed.
CREATE TEMP TABLE VT_RULE_PARAM AS
(
SELECT rul.RULE_CD                                                    AS RULE_CD,
       seg.SEGMENT_CD                                                 AS SEGMENT_CD,
       COALESCE (sp.AMT_THRESHOLD, ap.AMT_THRESHOLD)                  AS AMT_THRESHOLD,
       COALESCE (sp.CNT_THRESHOLD, ap.CNT_THRESHOLD, 1)               AS CNT_THRESHOLD,
       COALESCE (sp.LOOKBACK_DAYS, ap.LOOKBACK_DAYS, 1)               AS LOOKBACK_DAYS,
       COALESCE (sp.PCT_THRESHOLD, ap.PCT_THRESHOLD, 100)             AS PCT_THRESHOLD,
       COALESCE (sp.SCORE_WEIGHT,  ap.SCORE_WEIGHT, 10)               AS SCORE_WEIGHT,
       rd.RUN_DT - CAST (COALESCE (sp.LOOKBACK_DAYS, ap.LOOKBACK_DAYS, 1) - 1 AS INT)
                                                                      AS WINDOW_START_DT,
       rd.RUN_DT                                                      AS RUN_DT
FROM
       (
        SELECT RULE_CD
        FROM   TM_RULE_PARAM_SNAPSHOT
        GROUP  BY RULE_CD
       )                                          rul

       CROSS JOIN
       VT_SEGMENT                                 seg

       CROSS JOIN
       VT_RUN_DT                                  rd

       LEFT OUTER JOIN
       TM_RULE_PARAM_SNAPSHOT      sp
          ON  sp.RULE_CD    = rul.RULE_CD
          AND sp.SEGMENT_CD = seg.SEGMENT_CD

       LEFT OUTER JOIN
       TM_RULE_PARAM_SNAPSHOT      ap
          ON  ap.RULE_CD    = rul.RULE_CD
          AND ap.SEGMENT_CD = 'ALL'
WHERE
       sp.RULE_CD IS NOT NULL
OR     ap.RULE_CD IS NOT NULL
)
;

SELECT RULE_CD
FROM   VT_RULE_PARAM
;
-- Converted from BTEQ ACTIVITYCOUNT validation to an explicit Databricks SQL assertion.
SELECT CASE WHEN COUNT(*) = 0 THEN raise_error('VT_RULE_PARAM returned no rows (BTEQ exit 9)') ELSE COUNT(*) END AS validated_row_count
FROM VT_RULE_PARAM;


/**************************************************************************\
* EXTRACT THE TRANSACTIONS IN SCOPE OF THE LONGEST LOOKBACK WINDOW         *
* ------------------------------------------------------------------------ *
* Reversed and rejected transactions are excluded. Segment and party are   *
* taken from the account snapshot so every account has exactly one        *
* parameter set.                                                           *
\**************************************************************************/

-- Converted Teradata VOLATILE TABLE to a session-scoped TEMP TABLE; PRIMARY INDEX and ON COMMIT clauses are removed.
CREATE TEMP TABLE VT_WINDOW AS
(
SELECT MIN (WINDOW_START_DT)       AS MIN_START_DT,
       MAX (RUN_DT)                AS RUN_DT
FROM   VT_RULE_PARAM
)
;

-- Converted Teradata VOLATILE TABLE to a session-scoped TEMP TABLE; PRIMARY INDEX and ON COMMIT clauses are removed.
CREATE TEMP TABLE VT_TXN AS
(
SELECT txn.ACCT_ID                                                     AS ACCT_ID,
       COALESCE (acs.PRIMARY_PARTY_ID, txn.PARTY_ID)                   AS PARTY_ID,
       COALESCE (acs.SEGMENT_CD, txn.SEGMENT_CD, 'RET')                AS SEGMENT_CD,
       txn.BOOKING_DT                                                  AS BOOKING_DT,
       txn.TXN_REF                                                     AS TXN_REF,
       txn.SUPPLIER_CD                                                 AS SUPPLIER_CD,
       txn.DR_CR_IND                                                   AS DR_CR_IND,
       ABS (txn.GBP_AMT)                                               AS GBP_AMT,
       COALESCE (txn.CASH_IND, 'N')                                    AS CASH_IND,
       COALESCE (txn.XBORDER_IND, 'N')                                 AS XBORDER_IND,
       COALESCE (txn.ROUND_AMT_IND, 'N')                               AS ROUND_AMT_IND,
       COALESCE (txn.HRC_IND, 'N')                                     AS HRC_IND,
       txn.MCC_CD                                                      AS MCC_CD,
       txn.CPTY_ID                                                     AS CPTY_ID,
       txn.CPTY_CTRY_CD                                                AS CPTY_CTRY_CD,
       COALESCE (txn.PARTY_PEP_IND, 'N')                               AS PARTY_PEP_IND,
       txn.TXN_STATUS_CD                                               AS TXN_STATUS_CD
FROM
       AML_TXN_DAILY         txn

       CROSS JOIN
       VT_WINDOW                            win

       LEFT OUTER JOIN
       ACCT_SNAPSHOT         acs
          ON  acs.ACCT_ID = txn.ACCT_ID
WHERE
       txn.BOOKING_DT BETWEEN win.MIN_START_DT AND win.RUN_DT
AND    COALESCE (txn.REVERSAL_IND, 'N')   <> 'Y'
AND    COALESCE (txn.TXN_STATUS_CD, 'BK') NOT IN ('RJ', 'RV')
AND    txn.GBP_AMT IS NOT NULL
)
;

-- Converted by removing Teradata COLLECT STATISTICS maintenance; Delta/Photon maintains table-level statistics automatically.


/**************************************************************************\
* CLEAR THE RULE WORK TABLES                                               *
\**************************************************************************/

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
DELETE FROM AML_RULE_HIT_WRK
;

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
DELETE FROM AML_RULE_TXN_WRK
;


/**************************************************************************\
* RULE TM_STR01 - STRUCTURING / SMURFING                                   *
* ------------------------------------------------------------------------ *
* At least CNT_THRESHOLD cash credits each just below the reporting        *
* threshold (PCT_THRESHOLD % .. 100 %) within LOOKBACK_DAYS whose total    *
* exceeds the threshold. At least one deposit must be on the business day. *
\**************************************************************************/

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
INSERT INTO AML_RULE_HIT_WRK
(
       RULE_CD,
       PARTY_ID,
       ACCT_ID,
       BUSINESS_DT,
       HIT_GBP_AMT,
       HIT_CNT,
       LOOKBACK_START_DT,
       LOOKBACK_END_DT,
       ALERT_SCORE,
       HIT_DETAIL
)
SELECT 'TM_STR01',
       MAX (t.PARTY_ID),
       t.ACCT_ID,
       prm.RUN_DT,
       SUM (t.GBP_AMT),
       COUNT (*),
       prm.WINDOW_START_DT,
       prm.RUN_DT,
       CASE
          WHEN prm.AMT_THRESHOLD IS NULL OR prm.AMT_THRESHOLD = 0
          THEN prm.SCORE_WEIGHT
          WHEN prm.SCORE_WEIGHT * (SUM (t.GBP_AMT) / prm.AMT_THRESHOLD) >= 100
          THEN 100
          ELSE CAST (prm.SCORE_WEIGHT * (SUM (t.GBP_AMT) / prm.AMT_THRESHOLD) AS SMALLINT)
       END,
       'STRUCTURING: ' || TRIM (CAST (COUNT (*) AS VARCHAR(10))) ||
       ' CASH CREDITS BELOW GBP ' ||
       TRIM (FORMAT_NUMBER (prm.AMT_THRESHOLD, 0)) ||
       ' TOTALLING GBP ' ||
       TRIM (FORMAT_NUMBER (SUM (t.GBP_AMT), 2)) ||
       ' IN ' || TRIM (CAST (prm.LOOKBACK_DAYS AS VARCHAR(5))) || ' DAYS'
FROM
       VT_TXN                               t

       INNER JOIN
       VT_RULE_PARAM                        prm
          ON  prm.RULE_CD    = 'TM_STR01'
          AND prm.SEGMENT_CD = t.SEGMENT_CD
WHERE
       t.BOOKING_DT BETWEEN prm.WINDOW_START_DT AND prm.RUN_DT
AND    t.DR_CR_IND = 'C'
AND    t.CASH_IND  = 'Y'
AND    t.GBP_AMT  >= prm.AMT_THRESHOLD * prm.PCT_THRESHOLD / 100
AND    t.GBP_AMT  <  prm.AMT_THRESHOLD
GROUP  BY t.ACCT_ID,
          prm.RUN_DT,
          prm.WINDOW_START_DT,
          prm.AMT_THRESHOLD,
          prm.CNT_THRESHOLD,
          prm.LOOKBACK_DAYS,
          prm.SCORE_WEIGHT
HAVING COUNT (*)        >= prm.CNT_THRESHOLD
AND    SUM (t.GBP_AMT)  >  prm.AMT_THRESHOLD
AND    MAX (t.BOOKING_DT) = prm.RUN_DT
;

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
INSERT INTO AML_RULE_TXN_WRK
(
       RULE_CD,
       ACCT_ID,
       BUSINESS_DT,
       TXN_REF,
       SUPPLIER_CD
)
SELECT hw.RULE_CD,
       t.ACCT_ID,
       hw.BUSINESS_DT,
       t.TXN_REF,
       t.SUPPLIER_CD
FROM
       AML_RULE_HIT_WRK   hw

       INNER JOIN
       VT_TXN                                      t
          ON  t.ACCT_ID = hw.ACCT_ID

       INNER JOIN
       VT_RULE_PARAM                               prm
          ON  prm.RULE_CD    = hw.RULE_CD
          AND prm.SEGMENT_CD = t.SEGMENT_CD
WHERE
       hw.RULE_CD = 'TM_STR01'
AND    t.BOOKING_DT BETWEEN prm.WINDOW_START_DT AND prm.RUN_DT
AND    t.DR_CR_IND = 'C'
AND    t.CASH_IND  = 'Y'
AND    t.GBP_AMT  >= prm.AMT_THRESHOLD * prm.PCT_THRESHOLD / 100
AND    t.GBP_AMT  <  prm.AMT_THRESHOLD
;


/**************************************************************************\
* RULE TM_RPM01 - RAPID MOVEMENT OF FUNDS (PASS-THROUGH)                   *
* ------------------------------------------------------------------------ *
* Funds credited to the account are debited out again within 2 days. For  *
* every day the outflow is capped by the credits of that day and the two  *
* preceding days. Rule fires when the moved-out share reaches             *
* PCT_THRESHOLD % of credits and credits exceed AMT_THRESHOLD.             *
\**************************************************************************/

-- Converted Teradata VOLATILE TABLE to a session-scoped TEMP TABLE; PRIMARY INDEX and ON COMMIT clauses are removed.
CREATE TEMP TABLE VT_RPM_DAY AS
(
SELECT s1.ACCT_ID                                   AS ACCT_ID,
       s1.BUSINESS_DT                               AS BUSINESS_DT,
       MAX (s1.PARTY_ID)                            AS PARTY_ID,
       MAX (s1.CR_CNT + s1.DR_CNT)                  AS TXN_CNT,
       MAX (s1.CR_GBP_AMT)                          AS CR_GBP_AMT,
       MAX (s1.DR_GBP_AMT)                          AS DR_GBP_AMT,
       SUM (s2.CR_GBP_AMT)                          AS CR_3D_GBP_AMT
FROM
       ACCT_DAILY_SUMM       s1

       INNER JOIN
       VT_RULE_PARAM                        prm
          ON  prm.RULE_CD    = 'TM_RPM01'
          AND prm.SEGMENT_CD = COALESCE (s1.SEGMENT_CD, 'RET')

       INNER JOIN
       ACCT_DAILY_SUMM       s2
          ON  s2.ACCT_ID     = s1.ACCT_ID
          AND s2.BUSINESS_DT BETWEEN s1.BUSINESS_DT - 2 AND s1.BUSINESS_DT
WHERE
       s1.BUSINESS_DT BETWEEN prm.WINDOW_START_DT AND prm.RUN_DT
GROUP  BY s1.ACCT_ID,
          s1.BUSINESS_DT
)
;

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
INSERT INTO AML_RULE_HIT_WRK
(
       RULE_CD,
       PARTY_ID,
       ACCT_ID,
       BUSINESS_DT,
       HIT_GBP_AMT,
       HIT_CNT,
       LOOKBACK_START_DT,
       LOOKBACK_END_DT,
       ALERT_SCORE,
       HIT_DETAIL
)
SELECT 'TM_RPM01',
       MAX (dy.PARTY_ID),
       dy.ACCT_ID,
       prm.RUN_DT,
       SUM (CASE WHEN dy.DR_GBP_AMT < dy.CR_3D_GBP_AMT
                 THEN dy.DR_GBP_AMT ELSE dy.CR_3D_GBP_AMT END),
       SUM (dy.TXN_CNT),
       prm.WINDOW_START_DT,
       prm.RUN_DT,
       CASE
          WHEN prm.AMT_THRESHOLD IS NULL OR prm.AMT_THRESHOLD = 0
          THEN prm.SCORE_WEIGHT
          WHEN prm.SCORE_WEIGHT * (SUM (dy.CR_GBP_AMT) / prm.AMT_THRESHOLD) >= 100
          THEN 100
          ELSE CAST (prm.SCORE_WEIGHT * (SUM (dy.CR_GBP_AMT) / prm.AMT_THRESHOLD) AS SMALLINT)
       END,
       'RAPID MOVEMENT: GBP ' ||
       TRIM (FORMAT_NUMBER (SUM (dy.CR_GBP_AMT), 2)) ||
       ' IN, GBP ' ||
       TRIM (FORMAT_NUMBER (SUM (CASE WHEN dy.DR_GBP_AMT < dy.CR_3D_GBP_AMT
                                   THEN dy.DR_GBP_AMT ELSE dy.CR_3D_GBP_AMT END), 2)) ||
       ' OUT WITHIN 2 DAYS'
FROM
       VT_RPM_DAY                           dy

       INNER JOIN
       ACCT_DAILY_SUMM       sm
          ON  sm.ACCT_ID     = dy.ACCT_ID
          AND sm.BUSINESS_DT = dy.BUSINESS_DT

       INNER JOIN
       VT_RULE_PARAM                        prm
          ON  prm.RULE_CD    = 'TM_RPM01'
          AND prm.SEGMENT_CD = COALESCE (sm.SEGMENT_CD, 'RET')
GROUP  BY dy.ACCT_ID,
          prm.RUN_DT,
          prm.WINDOW_START_DT,
          prm.AMT_THRESHOLD,
          prm.PCT_THRESHOLD,
          prm.SCORE_WEIGHT
HAVING SUM (dy.CR_GBP_AMT) > prm.AMT_THRESHOLD
AND    SUM (CASE WHEN dy.DR_GBP_AMT < dy.CR_3D_GBP_AMT
                 THEN dy.DR_GBP_AMT ELSE dy.CR_3D_GBP_AMT END) * 100
       >= SUM (dy.CR_GBP_AMT) * prm.PCT_THRESHOLD
AND    MAX (CASE WHEN dy.BUSINESS_DT = prm.RUN_DT AND dy.DR_GBP_AMT > 0
                 THEN 1 ELSE 0 END) = 1
;

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
INSERT INTO AML_RULE_TXN_WRK
(
       RULE_CD,
       ACCT_ID,
       BUSINESS_DT,
       TXN_REF,
       SUPPLIER_CD
)
SELECT hw.RULE_CD,
       t.ACCT_ID,
       hw.BUSINESS_DT,
       t.TXN_REF,
       t.SUPPLIER_CD
FROM
       AML_RULE_HIT_WRK   hw

       INNER JOIN
       VT_TXN                                      t
          ON  t.ACCT_ID = hw.ACCT_ID
WHERE
       hw.RULE_CD = 'TM_RPM01'
AND    t.BOOKING_DT BETWEEN hw.LOOKBACK_START_DT AND hw.LOOKBACK_END_DT
;


/**************************************************************************\
* RULE TM_HRC01 - HIGH RISK JURISDICTION                                   *
* ------------------------------------------------------------------------ *
* Payments to / from FATF black- or grey-listed, HMT high-risk or         *
* offshore jurisdictions (HRC_IND set by dailytxn.10) above the amount.    *
\**************************************************************************/

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
INSERT INTO AML_RULE_HIT_WRK
(
       RULE_CD,
       PARTY_ID,
       ACCT_ID,
       BUSINESS_DT,
       HIT_GBP_AMT,
       HIT_CNT,
       LOOKBACK_START_DT,
       LOOKBACK_END_DT,
       ALERT_SCORE,
       HIT_DETAIL
)
SELECT 'TM_HRC01',
       MAX (t.PARTY_ID),
       t.ACCT_ID,
       prm.RUN_DT,
       SUM (t.GBP_AMT),
       COUNT (*),
       prm.WINDOW_START_DT,
       prm.RUN_DT,
       CASE
          WHEN prm.AMT_THRESHOLD IS NULL OR prm.AMT_THRESHOLD = 0
          THEN prm.SCORE_WEIGHT
          WHEN prm.SCORE_WEIGHT * (SUM (t.GBP_AMT) / prm.AMT_THRESHOLD) >= 100
          THEN 100
          ELSE CAST (prm.SCORE_WEIGHT * (SUM (t.GBP_AMT) / prm.AMT_THRESHOLD) AS SMALLINT)
       END,
       'HIGH RISK JURISDICTION: ' || TRIM (CAST (COUNT (*) AS VARCHAR(10))) ||
       ' PAYMENTS, ' || TRIM (CAST (COUNT (DISTINCT t.CPTY_CTRY_CD) AS VARCHAR(5))) ||
       ' COUNTRIES, GBP ' ||
       TRIM (FORMAT_NUMBER (SUM (t.GBP_AMT), 2)) ||
       ' (LAST ' || COALESCE (TRIM (MAX (t.CPTY_CTRY_CD)), '??') || ')'
FROM
       VT_TXN                               t

       INNER JOIN
       VT_RULE_PARAM                        prm
          ON  prm.RULE_CD    = 'TM_HRC01'
          AND prm.SEGMENT_CD = t.SEGMENT_CD
WHERE
       t.BOOKING_DT BETWEEN prm.WINDOW_START_DT AND prm.RUN_DT
AND    t.HRC_IND = 'Y'
GROUP  BY t.ACCT_ID,
          prm.RUN_DT,
          prm.WINDOW_START_DT,
          prm.AMT_THRESHOLD,
          prm.SCORE_WEIGHT
HAVING SUM (t.GBP_AMT)    >  prm.AMT_THRESHOLD
AND    MAX (t.BOOKING_DT) =  prm.RUN_DT
;

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
INSERT INTO AML_RULE_TXN_WRK
(
       RULE_CD,
       ACCT_ID,
       BUSINESS_DT,
       TXN_REF,
       SUPPLIER_CD
)
SELECT hw.RULE_CD,
       t.ACCT_ID,
       hw.BUSINESS_DT,
       t.TXN_REF,
       t.SUPPLIER_CD
FROM
       AML_RULE_HIT_WRK   hw

       INNER JOIN
       VT_TXN                                      t
          ON  t.ACCT_ID = hw.ACCT_ID
WHERE
       hw.RULE_CD = 'TM_HRC01'
AND    t.BOOKING_DT BETWEEN hw.LOOKBACK_START_DT AND hw.LOOKBACK_END_DT
AND    t.HRC_IND = 'Y'
;


/**************************************************************************\
* RULE TM_RND01 - REPEATED ROUND AMOUNT TRANSFERS                          *
\**************************************************************************/

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
INSERT INTO AML_RULE_HIT_WRK
(
       RULE_CD,
       PARTY_ID,
       ACCT_ID,
       BUSINESS_DT,
       HIT_GBP_AMT,
       HIT_CNT,
       LOOKBACK_START_DT,
       LOOKBACK_END_DT,
       ALERT_SCORE,
       HIT_DETAIL
)
SELECT 'TM_RND01',
       MAX (t.PARTY_ID),
       t.ACCT_ID,
       prm.RUN_DT,
       SUM (t.GBP_AMT),
       COUNT (*),
       prm.WINDOW_START_DT,
       prm.RUN_DT,
       CASE
          WHEN prm.SCORE_WEIGHT * (COUNT (*) * 1.00 / NULLIF (prm.CNT_THRESHOLD, 0)) >= 100
          THEN 100
          ELSE COALESCE (CAST (prm.SCORE_WEIGHT * (COUNT (*) * 1.00 / NULLIF (prm.CNT_THRESHOLD, 0))
                               AS SMALLINT), prm.SCORE_WEIGHT)
       END,
       'ROUND AMOUNTS: ' || TRIM (CAST (COUNT (*) AS VARCHAR(10))) ||
       ' ROUND VALUE PAYMENTS TOTALLING GBP ' ||
       TRIM (FORMAT_NUMBER (SUM (t.GBP_AMT), 2))
FROM
       VT_TXN                               t

       INNER JOIN
       VT_RULE_PARAM                        prm
          ON  prm.RULE_CD    = 'TM_RND01'
          AND prm.SEGMENT_CD = t.SEGMENT_CD
WHERE
       t.BOOKING_DT BETWEEN prm.WINDOW_START_DT AND prm.RUN_DT
AND    t.ROUND_AMT_IND = 'Y'
GROUP  BY t.ACCT_ID,
          prm.RUN_DT,
          prm.WINDOW_START_DT,
          prm.AMT_THRESHOLD,
          prm.CNT_THRESHOLD,
          prm.SCORE_WEIGHT
HAVING COUNT (*)          >= prm.CNT_THRESHOLD
AND    SUM (t.GBP_AMT)    >= COALESCE (prm.AMT_THRESHOLD, 0)
AND    MAX (t.BOOKING_DT) =  prm.RUN_DT
;

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
INSERT INTO AML_RULE_TXN_WRK
(
       RULE_CD,
       ACCT_ID,
       BUSINESS_DT,
       TXN_REF,
       SUPPLIER_CD
)
SELECT hw.RULE_CD,
       t.ACCT_ID,
       hw.BUSINESS_DT,
       t.TXN_REF,
       t.SUPPLIER_CD
FROM
       AML_RULE_HIT_WRK   hw

       INNER JOIN
       VT_TXN                                      t
          ON  t.ACCT_ID = hw.ACCT_ID
WHERE
       hw.RULE_CD = 'TM_RND01'
AND    t.BOOKING_DT BETWEEN hw.LOOKBACK_START_DT AND hw.LOOKBACK_END_DT
AND    t.ROUND_AMT_IND = 'Y'
;


/**************************************************************************\
* RULE TM_DRM01 - DORMANT ACCOUNT REACTIVATION                             *
* ------------------------------------------------------------------------ *
* CNT_THRESHOLD carries the dormancy period in days (default 365). The     *
* business day turnover of a re-activated account must exceed the amount. *
* Accounts flagged dormant ('D') by the core system are always in scope.  *
\**************************************************************************/

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
INSERT INTO AML_RULE_HIT_WRK
(
       RULE_CD,
       PARTY_ID,
       ACCT_ID,
       BUSINESS_DT,
       HIT_GBP_AMT,
       HIT_CNT,
       LOOKBACK_START_DT,
       LOOKBACK_END_DT,
       ALERT_SCORE,
       HIT_DETAIL
)
SELECT 'TM_DRM01',
       sm.PARTY_ID,
       sm.ACCT_ID,
       prm.RUN_DT,
       sm.CR_GBP_AMT + sm.DR_GBP_AMT,
       sm.CR_CNT + sm.DR_CNT,
       prm.RUN_DT - CAST (pro.DAYS_SINCE_PREV_ACTV AS INT),
       prm.RUN_DT,
       CASE
          WHEN prm.AMT_THRESHOLD IS NULL OR prm.AMT_THRESHOLD = 0
          THEN prm.SCORE_WEIGHT
          WHEN prm.SCORE_WEIGHT * ((sm.CR_GBP_AMT + sm.DR_GBP_AMT) / prm.AMT_THRESHOLD) >= 100
          THEN 100
          ELSE CAST (prm.SCORE_WEIGHT * ((sm.CR_GBP_AMT + sm.DR_GBP_AMT) / prm.AMT_THRESHOLD)
                     AS SMALLINT)
       END,
       'DORMANT REACTIVATION: NO ACTIVITY FOR ' ||
       TRIM (CAST (pro.DAYS_SINCE_PREV_ACTV AS VARCHAR(10))) ||
       ' DAYS, GBP ' ||
       TRIM (FORMAT_NUMBER (sm.CR_GBP_AMT + sm.DR_GBP_AMT, 2)) ||
       ' MOVED ON REACTIVATION (STATUS ' || COALESCE (acs.ACCT_STATUS_CD, '?') || ')'
FROM
       ACCT_DAILY_SUMM       sm

       CROSS JOIN
       VT_RUN_DT                            rd

       INNER JOIN
       ACCT_BEHAV_PROFILE    pro
          ON  pro.ACCT_ID     = sm.ACCT_ID
          AND pro.BUSINESS_DT = sm.BUSINESS_DT

       LEFT OUTER JOIN
       ACCT_SNAPSHOT         acs
          ON  acs.ACCT_ID = sm.ACCT_ID

       INNER JOIN
       VT_RULE_PARAM                        prm
          ON  prm.RULE_CD    = 'TM_DRM01'
          AND prm.SEGMENT_CD = COALESCE (acs.SEGMENT_CD, sm.SEGMENT_CD, 'RET')
WHERE
       sm.BUSINESS_DT = rd.RUN_DT
AND    (   pro.DAYS_SINCE_PREV_ACTV >= COALESCE (prm.CNT_THRESHOLD, 365)
        OR acs.ACCT_STATUS_CD = 'D')
AND    sm.CR_GBP_AMT + sm.DR_GBP_AMT > COALESCE (prm.AMT_THRESHOLD, 0)
;

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
INSERT INTO AML_RULE_TXN_WRK
(
       RULE_CD,
       ACCT_ID,
       BUSINESS_DT,
       TXN_REF,
       SUPPLIER_CD
)
SELECT hw.RULE_CD,
       t.ACCT_ID,
       hw.BUSINESS_DT,
       t.TXN_REF,
       t.SUPPLIER_CD
FROM
       AML_RULE_HIT_WRK   hw

       INNER JOIN
       VT_TXN                                      t
          ON  t.ACCT_ID    = hw.ACCT_ID
          AND t.BOOKING_DT = hw.BUSINESS_DT
WHERE
       hw.RULE_CD = 'TM_DRM01'
;


/**************************************************************************\
* RULE TM_VEL01 - VELOCITY SPIKE AGAINST OWN HISTORY                       *
* ------------------------------------------------------------------------ *
* 30 day credit turnover compared with the average month of the prior 90  *
* days (amlmon.15). PCT_THRESHOLD 500 = five times the normal value.       *
\**************************************************************************/

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
INSERT INTO AML_RULE_HIT_WRK
(
       RULE_CD,
       PARTY_ID,
       ACCT_ID,
       BUSINESS_DT,
       HIT_GBP_AMT,
       HIT_CNT,
       LOOKBACK_START_DT,
       LOOKBACK_END_DT,
       ALERT_SCORE,
       HIT_DETAIL
)
SELECT 'TM_VEL01',
       pro.PARTY_ID,
       pro.ACCT_ID,
       prm.RUN_DT,
       pro.ROLL_30D_CR_GBP_AMT,
       NULL,
       prm.RUN_DT - 29,
       prm.RUN_DT,
       CASE
          WHEN prm.SCORE_WEIGHT * pro.VELOCITY_RATIO / (prm.PCT_THRESHOLD / 100) >= 100
          THEN 100
          ELSE CAST (prm.SCORE_WEIGHT * pro.VELOCITY_RATIO / (prm.PCT_THRESHOLD / 100) AS SMALLINT)
       END,
       'VELOCITY: 30 DAY CREDITS GBP ' ||
       TRIM (FORMAT_NUMBER (pro.ROLL_30D_CR_GBP_AMT, 2)) ||
       ' = ' || TRIM (FORMAT_STRING ('%.2f', pro.VELOCITY_RATIO)) ||
       ' X PRIOR MONTHLY AVERAGE OF GBP ' ||
       TRIM (FORMAT_NUMBER (pro.PRIOR_90D_AVG_MTH_CR_AMT, 2))
FROM
       ACCT_BEHAV_PROFILE    pro

       CROSS JOIN
       VT_RUN_DT                            rd

       INNER JOIN
       ACCT_DAILY_SUMM       sm
          ON  sm.ACCT_ID     = pro.ACCT_ID
          AND sm.BUSINESS_DT = pro.BUSINESS_DT

       INNER JOIN
       VT_RULE_PARAM                        prm
          ON  prm.RULE_CD    = 'TM_VEL01'
          AND prm.SEGMENT_CD = pro.SEGMENT_CD
WHERE
       pro.BUSINESS_DT     = rd.RUN_DT
AND    sm.CR_CNT           > 0
AND    pro.VELOCITY_RATIO >= prm.PCT_THRESHOLD / 100
AND    pro.ROLL_30D_CR_GBP_AMT > COALESCE (prm.AMT_THRESHOLD, 0)
AND    prm.PCT_THRESHOLD   > 0
;

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
INSERT INTO AML_RULE_TXN_WRK
(
       RULE_CD,
       ACCT_ID,
       BUSINESS_DT,
       TXN_REF,
       SUPPLIER_CD
)
SELECT hw.RULE_CD,
       t.ACCT_ID,
       hw.BUSINESS_DT,
       t.TXN_REF,
       t.SUPPLIER_CD
FROM
       AML_RULE_HIT_WRK   hw

       INNER JOIN
       VT_TXN                                      t
          ON  t.ACCT_ID = hw.ACCT_ID
WHERE
       hw.RULE_CD = 'TM_VEL01'
AND    t.BOOKING_DT BETWEEN hw.LOOKBACK_START_DT AND hw.LOOKBACK_END_DT
AND    t.DR_CR_IND = 'C'
;


/**************************************************************************\
* RULE TM_PEP01 - LARGE TRANSACTION OF A POLITICALLY EXPOSED PERSON        *
\**************************************************************************/

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
INSERT INTO AML_RULE_HIT_WRK
(
       RULE_CD,
       PARTY_ID,
       ACCT_ID,
       BUSINESS_DT,
       HIT_GBP_AMT,
       HIT_CNT,
       LOOKBACK_START_DT,
       LOOKBACK_END_DT,
       ALERT_SCORE,
       HIT_DETAIL
)
SELECT 'TM_PEP01',
       MAX (t.PARTY_ID),
       t.ACCT_ID,
       prm.RUN_DT,
       SUM (t.GBP_AMT),
       COUNT (*),
       prm.WINDOW_START_DT,
       prm.RUN_DT,
       CASE
          WHEN prm.AMT_THRESHOLD IS NULL OR prm.AMT_THRESHOLD = 0
          THEN prm.SCORE_WEIGHT
          WHEN prm.SCORE_WEIGHT * (MAX (t.GBP_AMT) / prm.AMT_THRESHOLD) >= 100
          THEN 100
          ELSE CAST (prm.SCORE_WEIGHT * (MAX (t.GBP_AMT) / prm.AMT_THRESHOLD) AS SMALLINT)
       END,
       'PEP: ' || TRIM (CAST (COUNT (*) AS VARCHAR(10))) ||
       ' TRANSACTIONS ABOVE GBP ' ||
       TRIM (FORMAT_NUMBER (prm.AMT_THRESHOLD, 0)) ||
       ', LARGEST GBP ' ||
       TRIM (FORMAT_NUMBER (MAX (t.GBP_AMT), 2)) ||
       ' (PEP TYPE ' || COALESCE (MAX (pty.PEP_TYP_CD), '??') || ')'
FROM
       VT_TXN                               t

       INNER JOIN
       VT_RULE_PARAM                        prm
          ON  prm.RULE_CD    = 'TM_PEP01'
          AND prm.SEGMENT_CD = t.SEGMENT_CD

       LEFT OUTER JOIN
       PARTY                 pty
          ON  pty.PARTY_ID = t.PARTY_ID
WHERE
       t.BOOKING_DT BETWEEN prm.WINDOW_START_DT AND prm.RUN_DT
AND    (t.PARTY_PEP_IND = 'Y' OR pty.PEP_IND = 'Y')
AND    t.GBP_AMT > COALESCE (prm.AMT_THRESHOLD, 0)
GROUP  BY t.ACCT_ID,
          prm.RUN_DT,
          prm.WINDOW_START_DT,
          prm.AMT_THRESHOLD,
          prm.SCORE_WEIGHT
HAVING MAX (t.BOOKING_DT) = prm.RUN_DT
;

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
INSERT INTO AML_RULE_TXN_WRK
(
       RULE_CD,
       ACCT_ID,
       BUSINESS_DT,
       TXN_REF,
       SUPPLIER_CD
)
SELECT hw.RULE_CD,
       t.ACCT_ID,
       hw.BUSINESS_DT,
       t.TXN_REF,
       t.SUPPLIER_CD
FROM
       AML_RULE_HIT_WRK   hw

       INNER JOIN
       VT_TXN                                      t
          ON  t.ACCT_ID = hw.ACCT_ID

       INNER JOIN
       VT_RULE_PARAM                               prm
          ON  prm.RULE_CD    = hw.RULE_CD
          AND prm.SEGMENT_CD = t.SEGMENT_CD
WHERE
       hw.RULE_CD = 'TM_PEP01'
AND    t.BOOKING_DT BETWEEN hw.LOOKBACK_START_DT AND hw.LOOKBACK_END_DT
AND    t.GBP_AMT > COALESCE (prm.AMT_THRESHOLD, 0)
;


/**************************************************************************\
* RULE TM_TOV01 - TURNOVER INCONSISTENT WITH KYC PROFILE                   *
* ------------------------------------------------------------------------ *
* 30 day credit turnover above PCT_THRESHOLD % of the expected monthly     *
* turnover declared at onboarding / last KYC review.                       *
\**************************************************************************/

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
INSERT INTO AML_RULE_HIT_WRK
(
       RULE_CD,
       PARTY_ID,
       ACCT_ID,
       BUSINESS_DT,
       HIT_GBP_AMT,
       HIT_CNT,
       LOOKBACK_START_DT,
       LOOKBACK_END_DT,
       ALERT_SCORE,
       HIT_DETAIL
)
SELECT 'TM_TOV01',
       pro.PARTY_ID,
       pro.ACCT_ID,
       prm.RUN_DT,
       pro.ROLL_30D_CR_GBP_AMT,
       NULL,
       prm.RUN_DT - 29,
       prm.RUN_DT,
       CASE
          WHEN prm.SCORE_WEIGHT * (pro.ROLL_30D_CR_GBP_AMT * 100 /
                                   (psn.EXP_MTH_TURNOVER_AMT * prm.PCT_THRESHOLD)) >= 100
          THEN 100
          ELSE CAST (prm.SCORE_WEIGHT * (pro.ROLL_30D_CR_GBP_AMT * 100 /
                                         (psn.EXP_MTH_TURNOVER_AMT * prm.PCT_THRESHOLD)) AS SMALLINT)
       END,
       'TURNOVER: 30 DAY CREDITS GBP ' ||
       TRIM (FORMAT_NUMBER (pro.ROLL_30D_CR_GBP_AMT, 2)) ||
       ' VS DECLARED GBP ' ||
       TRIM (FORMAT_NUMBER (psn.EXP_MTH_TURNOVER_AMT, 2)) ||
       ' PER MONTH'
FROM
       ACCT_BEHAV_PROFILE    pro

       CROSS JOIN
       VT_RUN_DT                            rd

       INNER JOIN
       ACCT_DAILY_SUMM       sm
          ON  sm.ACCT_ID     = pro.ACCT_ID
          AND sm.BUSINESS_DT = pro.BUSINESS_DT

       INNER JOIN
       PARTY_SNAPSHOT        psn
          ON  psn.PARTY_ID = pro.PARTY_ID

       INNER JOIN
       VT_RULE_PARAM                        prm
          ON  prm.RULE_CD    = 'TM_TOV01'
          AND prm.SEGMENT_CD = pro.SEGMENT_CD
WHERE
       pro.BUSINESS_DT = rd.RUN_DT
AND    sm.CR_CNT       > 0
AND    psn.EXP_MTH_TURNOVER_AMT > 0
AND    prm.PCT_THRESHOLD        > 0
AND    pro.ROLL_30D_CR_GBP_AMT * 100 > psn.EXP_MTH_TURNOVER_AMT * prm.PCT_THRESHOLD
AND    pro.ROLL_30D_CR_GBP_AMT       > COALESCE (prm.AMT_THRESHOLD, 0)
;

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
INSERT INTO AML_RULE_TXN_WRK
(
       RULE_CD,
       ACCT_ID,
       BUSINESS_DT,
       TXN_REF,
       SUPPLIER_CD
)
SELECT hw.RULE_CD,
       t.ACCT_ID,
       hw.BUSINESS_DT,
       t.TXN_REF,
       t.SUPPLIER_CD
FROM
       AML_RULE_HIT_WRK   hw

       INNER JOIN
       VT_TXN                                      t
          ON  t.ACCT_ID = hw.ACCT_ID
WHERE
       hw.RULE_CD = 'TM_TOV01'
AND    t.BOOKING_DT BETWEEN hw.LOOKBACK_START_DT AND hw.LOOKBACK_END_DT
AND    t.DR_CR_IND = 'C'
;


/**************************************************************************\
* RULE TM_CSH01 - CASH ACTIVITY FOR NON CASH-INTENSIVE CUSTOMERS           *
\**************************************************************************/

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
INSERT INTO AML_RULE_HIT_WRK
(
       RULE_CD,
       PARTY_ID,
       ACCT_ID,
       BUSINESS_DT,
       HIT_GBP_AMT,
       HIT_CNT,
       LOOKBACK_START_DT,
       LOOKBACK_END_DT,
       ALERT_SCORE,
       HIT_DETAIL
)
SELECT 'TM_CSH01',
       MAX (t.PARTY_ID),
       t.ACCT_ID,
       prm.RUN_DT,
       SUM (t.GBP_AMT),
       COUNT (*),
       prm.WINDOW_START_DT,
       prm.RUN_DT,
       CASE
          WHEN prm.AMT_THRESHOLD IS NULL OR prm.AMT_THRESHOLD = 0
          THEN prm.SCORE_WEIGHT
          WHEN prm.SCORE_WEIGHT * (SUM (t.GBP_AMT) / prm.AMT_THRESHOLD) >= 100
          THEN 100
          ELSE CAST (prm.SCORE_WEIGHT * (SUM (t.GBP_AMT) / prm.AMT_THRESHOLD) AS SMALLINT)
       END,
       'CASH: GBP ' ||
       TRIM (FORMAT_NUMBER (SUM (t.GBP_AMT), 2)) ||
       ' CASH CREDITED IN ' || TRIM (CAST (prm.LOOKBACK_DAYS AS VARCHAR(5))) ||
       ' DAYS, SIC ' || COALESCE (TRIM (MAX (psn.SIC_CD)), 'NONE') || ' NOT CASH INTENSIVE'
FROM
       VT_TXN                               t

       INNER JOIN
       VT_RULE_PARAM                        prm
          ON  prm.RULE_CD    = 'TM_CSH01'
          AND prm.SEGMENT_CD = t.SEGMENT_CD

       LEFT OUTER JOIN
       PARTY_SNAPSHOT        psn
          ON  psn.PARTY_ID = t.PARTY_ID

       LEFT OUTER JOIN
       SIC_SNAPSHOT          sic
          ON  sic.SIC_CD = psn.SIC_CD
WHERE
       t.BOOKING_DT BETWEEN prm.WINDOW_START_DT AND prm.RUN_DT
AND    t.DR_CR_IND = 'C'
AND    t.CASH_IND  = 'Y'
AND    COALESCE (sic.CASH_INTENSIVE_IND, 'N') <> 'Y'
GROUP  BY t.ACCT_ID,
          prm.RUN_DT,
          prm.WINDOW_START_DT,
          prm.AMT_THRESHOLD,
          prm.LOOKBACK_DAYS,
          prm.SCORE_WEIGHT
HAVING SUM (t.GBP_AMT)    >  prm.AMT_THRESHOLD
AND    MAX (t.BOOKING_DT) =  prm.RUN_DT
;

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
INSERT INTO AML_RULE_TXN_WRK
(
       RULE_CD,
       ACCT_ID,
       BUSINESS_DT,
       TXN_REF,
       SUPPLIER_CD
)
SELECT hw.RULE_CD,
       t.ACCT_ID,
       hw.BUSINESS_DT,
       t.TXN_REF,
       t.SUPPLIER_CD
FROM
       AML_RULE_HIT_WRK   hw

       INNER JOIN
       VT_TXN                                      t
          ON  t.ACCT_ID = hw.ACCT_ID
WHERE
       hw.RULE_CD = 'TM_CSH01'
AND    t.BOOKING_DT BETWEEN hw.LOOKBACK_START_DT AND hw.LOOKBACK_END_DT
AND    t.DR_CR_IND = 'C'
AND    t.CASH_IND  = 'Y'
;


/**************************************************************************\
* RULE TM_MUL01 - MONEY MULE FAN-IN ON NEWLY OPENED RETAIL ACCOUNTS        *
* ------------------------------------------------------------------------ *
* Accounts opened less than LOOKBACK_DAYS ago receiving funds from at      *
* least CNT_THRESHOLD distinct payers within 3 days.                       *
\**************************************************************************/

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
INSERT INTO AML_RULE_HIT_WRK
(
       RULE_CD,
       PARTY_ID,
       ACCT_ID,
       BUSINESS_DT,
       HIT_GBP_AMT,
       HIT_CNT,
       LOOKBACK_START_DT,
       LOOKBACK_END_DT,
       ALERT_SCORE,
       HIT_DETAIL
)
SELECT 'TM_MUL01',
       MAX (t.PARTY_ID),
       t.ACCT_ID,
       prm.RUN_DT,
       SUM (t.GBP_AMT),
       COUNT (DISTINCT t.CPTY_ID),
       prm.RUN_DT - 2,
       prm.RUN_DT,
       CASE
          WHEN prm.SCORE_WEIGHT * (COUNT (DISTINCT t.CPTY_ID) * 1.00 /
                                   NULLIF (prm.CNT_THRESHOLD, 0)) >= 100
          THEN 100
          ELSE COALESCE (CAST (prm.SCORE_WEIGHT * (COUNT (DISTINCT t.CPTY_ID) * 1.00 /
                                                   NULLIF (prm.CNT_THRESHOLD, 0)) AS SMALLINT),
                         prm.SCORE_WEIGHT)
       END,
       'MULE FAN-IN: ' || TRIM (CAST (COUNT (DISTINCT t.CPTY_ID) AS VARCHAR(10))) ||
       ' DISTINCT PAYERS IN 3 DAYS, GBP ' ||
       TRIM (FORMAT_NUMBER (SUM (t.GBP_AMT), 2)) ||
       ', ACCOUNT OPENED ' || DATE_FORMAT (MAX (acs.OPEN_DT), 'yyyy-MM-dd')
FROM
       VT_TXN                               t

       INNER JOIN
       ACCT_SNAPSHOT         acs
          ON  acs.ACCT_ID = t.ACCT_ID

       INNER JOIN
       VT_RULE_PARAM                        prm
          ON  prm.RULE_CD    = 'TM_MUL01'
          AND prm.SEGMENT_CD = t.SEGMENT_CD
WHERE
       t.SEGMENT_CD = 'RET'
AND    t.BOOKING_DT BETWEEN prm.RUN_DT - 2 AND prm.RUN_DT
AND    t.DR_CR_IND  = 'C'
AND    t.CPTY_ID   IS NOT NULL
AND    acs.OPEN_DT  > prm.RUN_DT - CAST (prm.LOOKBACK_DAYS AS INT)
GROUP  BY t.ACCT_ID,
          prm.RUN_DT,
          prm.AMT_THRESHOLD,
          prm.CNT_THRESHOLD,
          prm.SCORE_WEIGHT
HAVING COUNT (DISTINCT t.CPTY_ID) >= prm.CNT_THRESHOLD
AND    SUM (t.GBP_AMT)            >  COALESCE (prm.AMT_THRESHOLD, 0)
AND    MAX (t.BOOKING_DT)         =  prm.RUN_DT
;

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
INSERT INTO AML_RULE_TXN_WRK
(
       RULE_CD,
       ACCT_ID,
       BUSINESS_DT,
       TXN_REF,
       SUPPLIER_CD
)
SELECT hw.RULE_CD,
       t.ACCT_ID,
       hw.BUSINESS_DT,
       t.TXN_REF,
       t.SUPPLIER_CD
FROM
       AML_RULE_HIT_WRK   hw

       INNER JOIN
       VT_TXN                                      t
          ON  t.ACCT_ID = hw.ACCT_ID
WHERE
       hw.RULE_CD = 'TM_MUL01'
AND    t.BOOKING_DT BETWEEN hw.LOOKBACK_START_DT AND hw.LOOKBACK_END_DT
AND    t.DR_CR_IND = 'C'
AND    t.CPTY_ID  IS NOT NULL
;


/**************************************************************************\
* RULE TM_GMB01 - GAMBLING AND CRYPTO-ASSET SPEND                          *
\**************************************************************************/

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
INSERT INTO AML_RULE_HIT_WRK
(
       RULE_CD,
       PARTY_ID,
       ACCT_ID,
       BUSINESS_DT,
       HIT_GBP_AMT,
       HIT_CNT,
       LOOKBACK_START_DT,
       LOOKBACK_END_DT,
       ALERT_SCORE,
       HIT_DETAIL
)
SELECT 'TM_GMB01',
       MAX (t.PARTY_ID),
       t.ACCT_ID,
       prm.RUN_DT,
       SUM (t.GBP_AMT),
       COUNT (*),
       prm.WINDOW_START_DT,
       prm.RUN_DT,
       CASE
          WHEN prm.AMT_THRESHOLD IS NULL OR prm.AMT_THRESHOLD = 0
          THEN prm.SCORE_WEIGHT
          WHEN prm.SCORE_WEIGHT * (SUM (t.GBP_AMT) / prm.AMT_THRESHOLD) >= 100
          THEN 100
          ELSE CAST (prm.SCORE_WEIGHT * (SUM (t.GBP_AMT) / prm.AMT_THRESHOLD) AS SMALLINT)
       END,
       'GAMBLING/CRYPTO: GBP ' ||
       TRIM (FORMAT_NUMBER (SUM (CASE WHEN mcc.GAMBLING_IND = 'Y' THEN t.GBP_AMT ELSE 0 END), 2)) ||
       ' GAMBLING, GBP ' ||
       TRIM (FORMAT_NUMBER (SUM (CASE WHEN mcc.CRYPTO_IND = 'Y' THEN t.GBP_AMT ELSE 0 END), 2)) ||
       ' CRYPTO IN ' || TRIM (CAST (prm.LOOKBACK_DAYS AS VARCHAR(5))) || ' DAYS'
FROM
       VT_TXN                               t

       INNER JOIN
       MCC_SNAPSHOT          mcc
          ON  mcc.MCC_CD = t.MCC_CD

       INNER JOIN
       VT_RULE_PARAM                        prm
          ON  prm.RULE_CD    = 'TM_GMB01'
          AND prm.SEGMENT_CD = t.SEGMENT_CD
WHERE
       t.BOOKING_DT BETWEEN prm.WINDOW_START_DT AND prm.RUN_DT
AND    t.DR_CR_IND = 'D'
AND    (mcc.GAMBLING_IND = 'Y' OR mcc.CRYPTO_IND = 'Y')
GROUP  BY t.ACCT_ID,
          prm.RUN_DT,
          prm.WINDOW_START_DT,
          prm.AMT_THRESHOLD,
          prm.LOOKBACK_DAYS,
          prm.SCORE_WEIGHT
HAVING SUM (t.GBP_AMT)    >  prm.AMT_THRESHOLD
AND    MAX (t.BOOKING_DT) =  prm.RUN_DT
;

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
INSERT INTO AML_RULE_TXN_WRK
(
       RULE_CD,
       ACCT_ID,
       BUSINESS_DT,
       TXN_REF,
       SUPPLIER_CD
)
SELECT hw.RULE_CD,
       t.ACCT_ID,
       hw.BUSINESS_DT,
       t.TXN_REF,
       t.SUPPLIER_CD
FROM
       AML_RULE_HIT_WRK   hw

       INNER JOIN
       VT_TXN                                      t
          ON  t.ACCT_ID = hw.ACCT_ID

       INNER JOIN
       MCC_SNAPSHOT                 mcc
          ON  mcc.MCC_CD = t.MCC_CD
WHERE
       hw.RULE_CD = 'TM_GMB01'
AND    t.BOOKING_DT BETWEEN hw.LOOKBACK_START_DT AND hw.LOOKBACK_END_DT
AND    t.DR_CR_IND = 'D'
AND    (mcc.GAMBLING_IND = 'Y' OR mcc.CRYPTO_IND = 'Y')
;


/**************************************************************************\
* RULE TM_SAN01 - SANCTIONS SCREENING HIT                                  *
* ------------------------------------------------------------------------ *
* Every account with an open screening hit (dailytxn.08) on the business  *
* date raises an alert. Several hits on the same payment count once.      *
\**************************************************************************/

-- Converted Teradata VOLATILE TABLE to a session-scoped TEMP TABLE; PRIMARY INDEX and ON COMMIT clauses are removed.
CREATE TEMP TABLE VT_SAN_TXN AS
(
SELECT hit.ACCT_ID                       AS ACCT_ID,
       MAX (hit.PARTY_ID)                AS PARTY_ID,
       hit.TXN_REF                       AS TXN_REF,
       hit.SUPPLIER_CD                   AS SUPPLIER_CD,
       MAX (hit.MATCH_SCORE)             AS MATCH_SCORE,
       COUNT (DISTINCT hit.GROUP_ID)     AS GROUP_CNT,
       MAX (hit.REGIME_NM)               AS REGIME_NM
FROM
       SANC_SCREEN_HIT       hit

       CROSS JOIN
       VT_RUN_DT                            rd
WHERE
       hit.BUSINESS_DT   = rd.RUN_DT
AND    hit.HIT_STATUS_CD = 'OPEN'
AND    hit.ACCT_ID IS NOT NULL
GROUP  BY hit.ACCT_ID,
          hit.TXN_REF,
          hit.SUPPLIER_CD
)
;

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
INSERT INTO AML_RULE_HIT_WRK
(
       RULE_CD,
       PARTY_ID,
       ACCT_ID,
       BUSINESS_DT,
       HIT_GBP_AMT,
       HIT_CNT,
       LOOKBACK_START_DT,
       LOOKBACK_END_DT,
       ALERT_SCORE,
       HIT_DETAIL
)
SELECT 'TM_SAN01',
       COALESCE (MAX (acs.PRIMARY_PARTY_ID), MAX (san.PARTY_ID)),
       san.ACCT_ID,
       prm.RUN_DT,
       COALESCE (SUM (t.GBP_AMT), 0),
       COUNT (*),
       prm.RUN_DT,
       prm.RUN_DT,
       CASE
          WHEN prm.SCORE_WEIGHT * MAX (san.MATCH_SCORE) / 100 >= 100
          THEN 100
          ELSE COALESCE (CAST (prm.SCORE_WEIGHT * MAX (san.MATCH_SCORE) / 100 AS SMALLINT),
                         prm.SCORE_WEIGHT)
       END,
       'SANCTIONS: ' || TRIM (CAST (COUNT (*) AS VARCHAR(10))) ||
       ' PAYMENTS MATCHED ' || TRIM (CAST (SUM (san.GROUP_CNT) AS VARCHAR(10))) ||
       ' LISTED ENTRIES, BEST SCORE ' ||
       TRIM (FORMAT_STRING ('%.2f', MAX (san.MATCH_SCORE))) ||
       ', REGIME ' || COALESCE (SUBSTR (MAX (san.REGIME_NM), 1, 60), 'UNKNOWN')
FROM
       VT_SAN_TXN                           san

       LEFT OUTER JOIN
       VT_TXN                               t
          ON  t.ACCT_ID     = san.ACCT_ID
          AND t.TXN_REF     = san.TXN_REF
          AND t.SUPPLIER_CD = san.SUPPLIER_CD

       LEFT OUTER JOIN
       ACCT_SNAPSHOT         acs
          ON  acs.ACCT_ID = san.ACCT_ID

       INNER JOIN
       VT_RULE_PARAM                        prm
          ON  prm.RULE_CD    = 'TM_SAN01'
          AND prm.SEGMENT_CD = COALESCE (acs.SEGMENT_CD, 'RET')
GROUP  BY san.ACCT_ID,
          prm.RUN_DT,
          prm.SCORE_WEIGHT
;

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
INSERT INTO AML_RULE_TXN_WRK
(
       RULE_CD,
       ACCT_ID,
       BUSINESS_DT,
       TXN_REF,
       SUPPLIER_CD
)
SELECT hw.RULE_CD,
       san.ACCT_ID,
       hw.BUSINESS_DT,
       san.TXN_REF,
       san.SUPPLIER_CD
FROM
       AML_RULE_HIT_WRK   hw

       INNER JOIN
       VT_SAN_TXN                                  san
          ON  san.ACCT_ID = hw.ACCT_ID
WHERE
       hw.RULE_CD = 'TM_SAN01'
;

-- Converted by removing Teradata COLLECT STATISTICS maintenance; Delta/Photon maintains table-level statistics automatically.


/**************************************************************************\
* DETERMINE THE TRIGGERING TRANSACTION PER HIT                             *
* ------------------------------------------------------------------------ *
* The largest contributing transaction (latest on ties) is shown to the   *
* investigator as the alert trigger.                                       *
\**************************************************************************/

-- Converted Teradata UPDATE FROM to Databricks Delta MERGE while preserving QUALIFY-based trigger selection.
MERGE INTO AML_RULE_HIT_WRK AS hw
USING (
        SELECT rtw.RULE_CD,
               rtw.ACCT_ID,
               rtw.TXN_REF,
               rtw.SUPPLIER_CD
        FROM   AML_RULE_TXN_WRK   rtw

               INNER JOIN
               VT_TXN                                      t
                  ON  t.ACCT_ID     = rtw.ACCT_ID
                  AND t.TXN_REF     = rtw.TXN_REF
                  AND t.SUPPLIER_CD = rtw.SUPPLIER_CD
        QUALIFY ROW_NUMBER () OVER (PARTITION BY rtw.RULE_CD,
                                                 rtw.ACCT_ID
                                        ORDER BY t.GBP_AMT    DESC,
                                                 t.BOOKING_DT DESC,
                                                 rtw.TXN_REF
                                   ) = 1
      ) AS trg
ON  hw.RULE_CD = trg.RULE_CD
AND hw.ACCT_ID = trg.ACCT_ID
WHEN MATCHED THEN UPDATE SET
     hw.TRIGGER_TXN_REF     = trg.TXN_REF,
     hw.TRIGGER_SUPPLIER_CD = trg.SUPPLIER_CD
;


/**************************************************************************\
* REMOVE ALERTS OF A PREVIOUS RUN FOR THE SAME BUSINESS DATE               *
* ------------------------------------------------------------------------ *
* Only alerts not yet taken into case management are removed, so the      *
* step can be restarted without loss of investigator work.                 *
\**************************************************************************/

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
DELETE FROM TM_ALERT_TXN
WHERE  ALERT_ID IN
       (
        SELECT al.ALERT_ID
        FROM   TM_ALERT   al
               CROSS JOIN
               VT_RUN_DT                 rd
        WHERE  al.BUSINESS_DT = rd.RUN_DT
        AND    al.ALERT_STATUS_CD IN ('NEW', 'SUPPR')
       )
;

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
DELETE FROM TM_ALERT
WHERE  BUSINESS_DT     = (SELECT RUN_DT FROM VT_RUN_DT)
AND    ALERT_STATUS_CD IN ('NEW', 'SUPPR')
;


/**************************************************************************\
* ALERT SUPPRESSION                                                        *
* ------------------------------------------------------------------------ *
* An alert of the same rule for the same account raised within the last   *
* 30 days and not yet closed suppresses the new alert (reason DUPL).      *
* Hits that already exist as cased / closed alerts for the business date  *
* (restart after case management) are not raised again.                   *
\**************************************************************************/

-- Converted Teradata VOLATILE TABLE to a session-scoped TEMP TABLE; PRIMARY INDEX and ON COMMIT clauses are removed.
CREATE TEMP TABLE VT_ALERT_CAND AS
(
SELECT hw.RULE_CD,
       hw.PARTY_ID,
       hw.ACCT_ID,
       hw.BUSINESS_DT,
       hw.HIT_GBP_AMT,
       hw.HIT_CNT,
       hw.LOOKBACK_START_DT,
       hw.LOOKBACK_END_DT,
       hw.ALERT_SCORE,
       hw.TRIGGER_TXN_REF,
       hw.TRIGGER_SUPPLIER_CD,
       hw.HIT_DETAIL,
       CASE WHEN prv.ALERT_CNT > 0 THEN 'SUPPR' ELSE 'NEW'  END    AS ALERT_STATUS_CD,
       CASE WHEN prv.ALERT_CNT > 0 THEN 'DUPL'  ELSE NULL   END    AS SUPPRESS_REASON_CD
FROM
       AML_RULE_HIT_WRK   hw

       LEFT OUTER JOIN
       (
        SELECT al.RULE_CD,
               al.ACCT_ID,
               COUNT (*)                   AS ALERT_CNT
        FROM   TM_ALERT     al
               CROSS JOIN
               VT_RUN_DT                   rd
        WHERE  al.BUSINESS_DT BETWEEN rd.RUN_DT - 30 AND rd.RUN_DT - 1
        AND    al.ALERT_STATUS_CD <> 'CLOSD'
        GROUP  BY al.RULE_CD,
                  al.ACCT_ID
       )                                           prv
          ON  prv.RULE_CD = hw.RULE_CD
          AND prv.ACCT_ID = hw.ACCT_ID

       LEFT OUTER JOIN
       (
        SELECT al.RULE_CD,
               al.ACCT_ID
        FROM   TM_ALERT     al
               CROSS JOIN
               VT_RUN_DT                   rd
        WHERE  al.BUSINESS_DT = rd.RUN_DT
        GROUP  BY al.RULE_CD,
                  al.ACCT_ID
       )                                           tdy
          ON  tdy.RULE_CD = hw.RULE_CD
          AND tdy.ACCT_ID = hw.ACCT_ID
WHERE
       tdy.ACCT_ID IS NULL
)
;


/**************************************************************************\
* RAISE THE ALERTS                                                         *
\**************************************************************************/

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
INSERT INTO TM_ALERT
(
       ALERT_ID,
       RULE_CD,
       PARTY_ID,
       ACCT_ID,
       BUSINESS_DT,
       ALERT_TMS,
       ALERT_SCORE,
       HIT_GBP_AMT,
       HIT_CNT,
       LOOKBACK_START_DT,
       LOOKBACK_END_DT,
       TRIGGER_TXN_REF,
       TRIGGER_SUPPLIER_CD,
       ALERT_STATUS_CD,
       SUPPRESS_REASON_CD,
       CASE_ID,
       HIT_DETAIL,
       CO_UPD_TMS
)
SELECT mx.MAX_ALERT_ID +
       ROW_NUMBER () OVER (ORDER BY cnd.RULE_CD,
                                    cnd.ACCT_ID),
       cnd.RULE_CD,
       cnd.PARTY_ID,
       cnd.ACCT_ID,
       cnd.BUSINESS_DT,
       CURRENT_TIMESTAMP,
       cnd.ALERT_SCORE,
       cnd.HIT_GBP_AMT,
       cnd.HIT_CNT,
       cnd.LOOKBACK_START_DT,
       cnd.LOOKBACK_END_DT,
       cnd.TRIGGER_TXN_REF,
       cnd.TRIGGER_SUPPLIER_CD,
       cnd.ALERT_STATUS_CD,
       cnd.SUPPRESS_REASON_CD,
       NULL,
       cnd.HIT_DETAIL,
       rd.LOAD_TMS
FROM
       VT_ALERT_CAND                        cnd

       CROSS JOIN
       VT_RUN_DT                            rd

       CROSS JOIN
       (
        SELECT COALESCE (MAX (ALERT_ID), 0)   AS MAX_ALERT_ID
        FROM   TM_ALERT
       )                                    mx
;

-- Converted source database qualification to session-resolved Databricks objects because no target catalog/schema mapping was supplied.
INSERT INTO TM_ALERT_TXN
(
       ALERT_ID,
       TXN_REF,
       SUPPLIER_CD,
       CO_UPD_TMS
)
SELECT DISTINCT
       al.ALERT_ID,
       rtw.TXN_REF,
       rtw.SUPPLIER_CD,
       rd.LOAD_TMS
FROM
       TM_ALERT                     al

       CROSS JOIN
       VT_RUN_DT                                   rd

       INNER JOIN
       AML_RULE_TXN_WRK   rtw
          ON  rtw.RULE_CD     = al.RULE_CD
          AND rtw.ACCT_ID     = al.ACCT_ID
          AND rtw.BUSINESS_DT = al.BUSINESS_DT
WHERE
       al.BUSINESS_DT = rd.RUN_DT
AND    al.ALERT_STATUS_CD IN ('NEW', 'SUPPR')
;

-- Converted by removing Teradata COLLECT STATISTICS maintenance; Delta/Photon maintains table-level statistics automatically.


/**************************************************************************\
* END OF SCRIPT                                                            *
\**************************************************************************/

