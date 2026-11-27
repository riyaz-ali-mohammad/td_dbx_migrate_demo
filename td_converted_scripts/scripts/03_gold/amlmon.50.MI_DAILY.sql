-- TODO: manual review required — BTEQ script → notebook / stored procedure / Workflows DAG (choose wrapper)
-- TODO: manual review required — BTEQ .IF ERRORCODE / .QUIT handling requires a procedure SIGNAL or Workflows branch

/**************************************************************************\
* DETERMINE THE BUSINESS DATE OF THE CURRENT LOAD                          *
* ------------------------------------------------------------------------ *
* Month boundaries are derived once: MI is kept for the current and the   *
* previous (last full) month.                                              *
\**************************************************************************/

-- Converted Teradata volatile CTAS to a Databricks session temporary table; PI and commit clauses were removed.
CREATE TEMP TABLE VT_RUN_DT AS
SELECT BUSINESS_DT                                                   AS RUN_DT,
       LOAD_TMS                                                      AS LOAD_TMS,
       BUSINESS_DT - EXTRACT(DAY FROM BUSINESS_DT) + 1               AS CUR_MTH_START_DT,
       ADD_MONTHS(BUSINESS_DT - EXTRACT(DAY FROM BUSINESS_DT) + 1, -1)
                                                                     AS PREV_MTH_START_DT,
       EXTRACT(YEAR FROM BUSINESS_DT) * 100 + EXTRACT(MONTH FROM BUSINESS_DT)
                                                                     AS CUR_YR_MON,
       EXTRACT(YEAR FROM ADD_MONTHS(BUSINESS_DT, -1)) * 100 +
       EXTRACT(MONTH FROM ADD_MONTHS(BUSINESS_DT, -1))               AS PREV_YR_MON
FROM   DLYTXN_LOAD_TMS
WHERE  SSQ_ID = 1;

-- TODO: manual review required — enforce the former ACTIVITYCOUNT = 0 exit in the selected procedure or Workflow wrapper
SELECT RUN_DT
FROM   VT_RUN_DT;


/**************************************************************************\
* RE-POPULATE DIM_RULE                                                     *
* ------------------------------------------------------------------------ *
* Current version per rule and segment, then rolled up to one row per     *
* rule. The rule family is the 3 letter typology in the rule code.        *
\**************************************************************************/

-- Converted Teradata volatile CTAS to a Databricks session temporary table; PI and commit clauses were removed.
CREATE TEMP TABLE VT_RULE_CUR AS
SELECT prm.RULE_CD,
       prm.SEGMENT_CD,
       prm.AMT_THRESHOLD,
       prm.SCORE_WEIGHT,
       prm.ACTIVE_IND,
       prm.RULE_DESC
FROM   TM_RULE_PARAM prm
CROSS JOIN VT_RUN_DT rd
WHERE  prm.START_DT <= rd.RUN_DT
AND    prm.END_DT >= rd.RUN_DT
QUALIFY SUM(1) OVER (
           PARTITION BY prm.RULE_CD, prm.SEGMENT_CD
           ORDER BY prm.START_DT DESC, prm.CO_UPD_TMS DESC
           ROWS UNBOUNDED PRECEDING
       ) = 1;

-- Removed the unmapped Teradata database qualifier.
DELETE FROM DIM_RULE;

-- Removed source database qualifiers and the unsupported CURRENT_TIMESTAMP precision modifier.
INSERT INTO DIM_RULE
(
       RULE_CD,
       RULE_DESC,
       RULE_FAMILY_CD,
       ACTIVE_SEGMENT_CNT,
       MIN_AMT_THRESHOLD,
       MAX_SCORE_WEIGHT,
       CO_UPD_TMS
)
SELECT RULE_CD,
       COALESCE(MAX(CASE WHEN SEGMENT_CD = 'ALL' THEN RULE_DESC END),
                MAX(RULE_DESC)),
       SUBSTR(RULE_CD, 4, 3),
       COUNT(DISTINCT CASE WHEN ACTIVE_IND = 'Y' AND SEGMENT_CD <> 'ALL'
                           THEN SEGMENT_CD END),
       MIN(CASE WHEN ACTIVE_IND = 'Y' THEN AMT_THRESHOLD END),
       MAX(SCORE_WEIGHT),
       CURRENT_TIMESTAMP
FROM   VT_RULE_CUR
GROUP BY RULE_CD;


/**************************************************************************\
* RE-POPULATE DIM_RISK_BAND                                                *
\**************************************************************************/

DELETE FROM DIM_RISK_BAND
;

INSERT INTO DIM_RISK_BAND
(
       RISK_BAND_CD,
       RISK_BAND_DESC,
       MIN_SCORE,
       MAX_SCORE,
       REVIEW_FREQ_MTHS,
       SORT_ORDER_NR,
       CO_UPD_TMS
)
SELECT RISK_BAND_CD,
       RISK_BAND_DESC,
       MIN_SCORE,
       MAX_SCORE,
       REVIEW_FREQ_MTHS,
       ROW_NUMBER () OVER (ORDER BY MIN_SCORE, RISK_BAND_CD),
       CURRENT_TIMESTAMP
FROM   RISK_BAND
;


/**************************************************************************\
* RE-POPULATE DIM_COUNTRY                                                  *
* ------------------------------------------------------------------------ *
* Latest valid version per country. SANCTIONED_IND marks countries under  *
* a comprehensive UK sanctions regime.                                     *
\**************************************************************************/

DELETE FROM DIM_COUNTRY
;

INSERT INTO DIM_COUNTRY
(
       CTRY_2_CD,
       CTRY_3_CD,
       CTRY_NM,
       REGION_CD,
       FATF_STATUS_CD,
       CTRY_RISK_CD,
       HRC_IND,
       SANCTIONED_IND,
       CO_UPD_TMS
)
SELECT ctr.CTRY_2_CD,
       ctr.CTRY_3_CD,
       ctr.CTRY_NM,
       ctr.REGION_CD,
       ctr.FATF_STATUS_CD,
       ctr.CTRY_RISK_CD,
       COALESCE (snp.HRC_IND, 'N'),
       CASE WHEN src.CTRY_2_CD IS NOT NULL THEN 'Y' ELSE 'N' END,
       CURRENT_TIMESTAMP
FROM
       CTRY                   ctr

       CROSS JOIN
       VT_RUN_DT                             rd

       LEFT OUTER JOIN
       CTRY_SNAPSHOT          snp
          ON  snp.CTRY_2_CD = ctr.CTRY_2_CD

       LEFT OUTER JOIN
       (
        SELECT CTRY_2_CD
        FROM   SANC_REGIME_CTRY
        WHERE  COMPREHENSIVE_IND = 'Y'
        GROUP  BY CTRY_2_CD
       )                                     src
          ON  src.CTRY_2_CD = ctr.CTRY_2_CD
WHERE
       ctr.START_DT <= rd.RUN_DT

QUALIFY RANK () OVER (PARTITION BY  ctr.CTRY_2_CD
                          ORDER BY  ctr.START_DT   DESC
                                   ,ctr.CO_UPD_TMS DESC
                     )  =  1
;


/**************************************************************************\
* RE-POPULATE DIM_PRODUCT                                                  *
\**************************************************************************/

DELETE FROM DIM_PRODUCT
;

INSERT INTO DIM_PRODUCT
(
       PRDT_CD,
       PRDT_DESC,
       PRDT_FAMILY_CD,
       SEGMENT_CD,
       PRDT_RISK_CD,
       ACTIVE_ACCT_CNT,
       CO_UPD_TMS
)
SELECT prd.PRDT_CD,
       prd.PRDT_DESC,
       prd.PRDT_FAMILY_CD,
       prd.SEGMENT_CD,
       prd.PRDT_RISK_CD,
       COALESCE(acc.ACCT_CNT, 0),
       CURRENT_TIMESTAMP
FROM
       PRDT                   prd

       CROSS JOIN
       VT_RUN_DT                             rd

       LEFT OUTER JOIN
       (
        SELECT PRDT_CD,
               COUNT (*)                AS ACCT_CNT
        FROM   ACCT_SNAPSHOT
        WHERE  ACCT_STATUS_CD = 'A'
        GROUP  BY PRDT_CD
       )                                     acc
          ON  acc.PRDT_CD = prd.PRDT_CD
WHERE
       prd.START_DT <= rd.RUN_DT

QUALIFY SUM (1) OVER (PARTITION BY  prd.PRDT_CD
                          ORDER BY  prd.START_DT DESC
                                   ,prd.PRDT_DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;


/**************************************************************************\
* RE-POPULATE DIM_CHANNEL                                                  *
\**************************************************************************/

DELETE FROM DIM_CHANNEL
;

INSERT INTO DIM_CHANNEL
(
       CHNL_CD,
       CHNL_DESC,
       DIGITAL_IND,
       CO_UPD_TMS
)
SELECT chn.CHNL_CD,
       chn.CHNL_DESC,
       chn.DIGITAL_IND,
       CURRENT_TIMESTAMP
FROM
       CHNL                   chn

       CROSS JOIN
       VT_RUN_DT                             rd
WHERE
       chn.START_DT <= rd.RUN_DT

QUALIFY SUM (1) OVER (PARTITION BY  chn.CHNL_CD
                          ORDER BY  chn.START_DT DESC
                                   ,chn.CHNL_DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;


/**************************************************************************\
* RE-POPULATE DIM_TXN_TYPE                                                 *
\**************************************************************************/

DELETE FROM DIM_TXN_TYPE
;

INSERT INTO DIM_TXN_TYPE
(
       TXN_TYP_CD,
       TXN_TYP_DESC,
       PAY_SCHEME_CD,
       DIRECTION_CD,
       CASH_IND,
       XBORDER_IND,
       CO_UPD_TMS
)
SELECT ttp.TXN_TYP_CD,
       ttp.TXN_TYP_DESC,
       ttp.PAY_SCHEME_CD,
       ttp.DIRECTION_CD,
       ttp.CASH_IND,
       ttp.XBORDER_IND,
       CURRENT_TIMESTAMP
FROM
       TXN_TYP                ttp

       CROSS JOIN
       VT_RUN_DT                             rd
WHERE
       ttp.START_DT <= rd.RUN_DT

QUALIFY SUM (1) OVER (PARTITION BY  ttp.TXN_TYP_CD
                          ORDER BY  ttp.START_DT DESC
                                   ,ttp.TXN_TYP_DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;


/**************************************************************************\
* RE-POPULATE DIM_SEGMENT                                                  *
\**************************************************************************/

DELETE FROM DIM_SEGMENT
;

INSERT INTO DIM_SEGMENT
(
       SEGMENT_CD,
       SEGMENT_DESC,
       PARTY_CNT,
       CO_UPD_TMS
)
SELECT seg.SEGMENT_CD,
       CASE seg.SEGMENT_CD
            WHEN 'RET' THEN 'RETAIL BANKING'
            WHEN 'BUS' THEN 'BUSINESS BANKING'
            WHEN 'CIB' THEN 'CORPORATE AND INVESTMENT BANKING'
            WHEN 'WLT' THEN 'PRIVATE BANK AND WEALTH'
            ELSE 'UNKNOWN SEGMENT'
       END,
       COALESCE(pty.PARTY_CNT, 0),
       CURRENT_TIMESTAMP
FROM
       (
        SELECT SEGMENT_CD
        FROM   PRDT_SNAPSHOT
        WHERE  SEGMENT_CD IS NOT NULL

        UNION

        SELECT SEGMENT_CD
        FROM   PARTY_SNAPSHOT
        WHERE  SEGMENT_CD IS NOT NULL
       )                                     seg

       LEFT OUTER JOIN
       (
        SELECT SEGMENT_CD,
               COUNT (*)                AS PARTY_CNT
        FROM   PARTY_SNAPSHOT
        GROUP  BY SEGMENT_CD
       )                                     pty
          ON  pty.SEGMENT_CD = seg.SEGMENT_CD
;


/**************************************************************************\
* ALERT_SUMM_DAILY - LAST 7 BUSINESS DATES                                 *
* ------------------------------------------------------------------------ *
* Rebuilt for 7 days to pick up late status changes. Risk band is taken   *
* as at the alert date from the risk score history.                        *
\**************************************************************************/

DELETE FROM ALERT_SUMM_DAILY
WHERE  BUSINESS_DT BETWEEN (SELECT RUN_DT - 6 FROM VT_RUN_DT)
                       AND (SELECT RUN_DT     FROM VT_RUN_DT)
;

INSERT INTO ALERT_SUMM_DAILY
(
       BUSINESS_DT,
       RULE_CD,
       SEGMENT_CD,
       RISK_BAND_CD,
       ALERT_CNT,
       PARTY_CNT,
       ACCT_CNT,
       TOTAL_HIT_GBP_AMT,
       AVG_ALERT_SCORE,
       CO_UPD_TMS
)
SELECT al.BUSINESS_DT,
       al.RULE_CD,
       COALESCE (psn.SEGMENT_CD, 'UNK'),
       COALESCE (hst.RISK_BAND_CD, 'NA'),
       COUNT (*),
       COUNT (DISTINCT al.PARTY_ID),
       COUNT (DISTINCT al.ACCT_ID),
       COALESCE(SUM(al.HIT_GBP_AMT), 0),
       CAST (AVG (CAST (al.ALERT_SCORE AS DECIMAL(9,2))) AS DECIMAL(9,2)),
       CURRENT_TIMESTAMP
FROM
       TM_ALERT               al

       CROSS JOIN
       VT_RUN_DT                             rd

       LEFT OUTER JOIN
       PARTY_SNAPSHOT         psn
          ON  psn.PARTY_ID = al.PARTY_ID

       LEFT OUTER JOIN
       PARTY_RISK_SCORE_HIST  hst
          ON  hst.PARTY_ID = al.PARTY_ID
          AND al.BUSINESS_DT BETWEEN hst.START_DT AND hst.END_DT
WHERE
       al.BUSINESS_DT BETWEEN rd.RUN_DT - 6 AND rd.RUN_DT
AND    al.ALERT_STATUS_CD <> 'SUPPR'
GROUP  BY al.BUSINESS_DT,
          al.RULE_CD,
          COALESCE (psn.SEGMENT_CD, 'UNK'),
          COALESCE (hst.RISK_BAND_CD, 'NA')
;


/**************************************************************************\
* RULE_EFFECTIVENESS_MTH - CURRENT AND PREVIOUS MONTH                      *
* ------------------------------------------------------------------------ *
* CONVERSION_PCT = SAR candidates / alerts                                 *
* FALSE_POS_PCT  = cases closed NFA / cased alerts                         *
* RANK_IN_MTH    = rank of the rule by conversion within the month         *
\**************************************************************************/

DELETE FROM RULE_EFFECTIVENESS_MTH
WHERE  YR_MON IN (SELECT CUR_YR_MON  FROM VT_RUN_DT
                  UNION
                  SELECT PREV_YR_MON FROM VT_RUN_DT)
;

INSERT INTO RULE_EFFECTIVENESS_MTH
(
       YR_MON,
       RULE_CD,
       ALERT_CNT,
       CASED_CNT,
       SAR_CNT,
       CLOSED_NFA_CNT,
       CONVERSION_PCT,
       FALSE_POS_PCT,
       RANK_IN_MTH,
       CO_UPD_TMS
)
SELECT eff.YR_MON,
       eff.RULE_CD,
       eff.ALERT_CNT,
       eff.CASED_CNT,
       eff.SAR_CNT,
       eff.CLOSED_NFA_CNT,
       CAST (eff.SAR_CNT * 100.00 / NULLIF(eff.ALERT_CNT, 0) AS DECIMAL(7,2)),
       CAST (eff.CLOSED_NFA_CNT * 100.00 / NULLIF(eff.CASED_CNT, 0) AS DECIMAL(7,2)),
       RANK () OVER (PARTITION BY eff.YR_MON
                         ORDER BY eff.SAR_CNT * 100.00 / NULLIF(eff.ALERT_CNT, 0) DESC,
                                  eff.ALERT_CNT DESC),
       CURRENT_TIMESTAMP
FROM
       (
        SELECT EXTRACT (YEAR FROM al.BUSINESS_DT) * 100 +
               EXTRACT (MONTH FROM al.BUSINESS_DT)                          AS YR_MON,
               al.RULE_CD                                                   AS RULE_CD,
               COUNT (*)                                                    AS ALERT_CNT,
               COUNT (al.CASE_ID)                                           AS CASED_CNT,
               SUM (CASE WHEN sar.CASE_ID IS NOT NULL THEN 1 ELSE 0 END)    AS SAR_CNT,
               SUM (CASE WHEN cse.CASE_STATUS_CD  = 'CLOSD'
                          AND cse.CLOSE_REASON_CD = 'NFA'
                         THEN 1 ELSE 0 END)                                 AS CLOSED_NFA_CNT
        FROM
               TM_ALERT            al

               CROSS JOIN
               VT_RUN_DT                          rd

               LEFT OUTER JOIN
               AML_CASE            cse
                  ON  cse.CASE_ID = al.CASE_ID

               LEFT OUTER JOIN
               SAR_CANDIDATE       sar
                  ON  sar.CASE_ID = al.CASE_ID
        WHERE
               al.BUSINESS_DT BETWEEN rd.PREV_MTH_START_DT AND rd.RUN_DT
        AND    al.ALERT_STATUS_CD <> 'SUPPR'
        GROUP  BY 1, 2
       )                                     eff
;


/**************************************************************************\
* XBORDER_FLOW_MTH - CROSS-BORDER FLOWS BY COUNTRY                         *
* ------------------------------------------------------------------------ *
* The country of the counterparty, else of the counterparty bank, else    *
* of the merchant. Domestic (GB) flows are excluded.                       *
\**************************************************************************/

DELETE FROM XBORDER_FLOW_MTH
WHERE  YR_MON IN (SELECT CUR_YR_MON  FROM VT_RUN_DT
                  UNION
                  SELECT PREV_YR_MON FROM VT_RUN_DT)
;

INSERT INTO XBORDER_FLOW_MTH
(
       YR_MON,
       CTRY_2_CD,
       DR_CR_IND,
       FATF_STATUS_CD,
       CTRY_RISK_CD,
       TXN_CNT,
       GBP_AMT,
       PARTY_CNT,
       CO_UPD_TMS
)
SELECT flw.YR_MON,
       flw.CTRY_2_CD,
       flw.DR_CR_IND,
       MAX (ctr.FATF_STATUS_CD),
       MAX (ctr.CTRY_RISK_CD),
       COUNT (*),
       SUM (flw.GBP_AMT),
       COUNT (DISTINCT flw.PARTY_ID),
       CURRENT_TIMESTAMP
FROM
       (
        SELECT EXTRACT (YEAR FROM txn.BOOKING_DT) * 100 +
               EXTRACT (MONTH FROM txn.BOOKING_DT)                    AS YR_MON,
               COALESCE (txn.CPTY_CTRY_CD,
                         txn.CPTY_BANK_CTRY_CD,
                         txn.MERCHANT_CTRY_CD)                        AS CTRY_2_CD,
               txn.DR_CR_IND                                          AS DR_CR_IND,
               ABS (txn.GBP_AMT)                                      AS GBP_AMT,
               txn.PARTY_ID                                           AS PARTY_ID
        FROM
               AML_TXN_DAILY       txn

               CROSS JOIN
               VT_RUN_DT                          rd
        WHERE
               txn.BOOKING_DT BETWEEN rd.PREV_MTH_START_DT AND rd.RUN_DT
        AND    txn.XBORDER_IND = 'Y'
        AND    COALESCE (txn.REVERSAL_IND, 'N')   <> 'Y'
        AND    COALESCE (txn.TXN_STATUS_CD, 'BK') NOT IN ('RJ', 'RV')
       )                                     flw

       LEFT OUTER JOIN
       CTRY_SNAPSHOT          ctr
          ON  ctr.CTRY_2_CD = flw.CTRY_2_CD
WHERE
       flw.CTRY_2_CD IS NOT NULL
AND    flw.CTRY_2_CD <> 'GB'
AND    flw.DR_CR_IND IN ('D', 'C')
GROUP  BY flw.YR_MON,
          flw.CTRY_2_CD,
          flw.DR_CR_IND
;


/**************************************************************************\
* CASE_AGEING_DAILY - OPEN CASES BY AGE IN UK BUSINESS DAYS                *
* ------------------------------------------------------------------------ *
* A running business-day counter (CSUM) over the calendar gives the age   *
* as the difference of the counter between opening and business date.     *
\**************************************************************************/

-- Converted the volatile table and Teradata CSUM to a Databricks TEMP TABLE with an ANSI running window.
CREATE TEMP TABLE VT_BUS_CAL AS
SELECT cal.CAL_DT,
       SUM(CASE WHEN cal.BUS_DAY_IND = 'Y' AND hol.HOLIDAY_DT IS NULL
                THEN 1 ELSE 0 END)
           OVER (ORDER BY cal.CAL_DT ROWS UNBOUNDED PRECEDING)     AS BUS_DAY_SEQ
FROM
       CALENDAR         cal

       CROSS JOIN
       VT_RUN_DT                             rd

       LEFT OUTER JOIN
       UK_BANK_HOLIDAY  hol
          ON  hol.HOLIDAY_DT = cal.CAL_DT
WHERE
       cal.CAL_DT BETWEEN rd.RUN_DT - 1095 AND rd.RUN_DT;

DELETE FROM CASE_AGEING_DAILY
WHERE  BUSINESS_DT = (SELECT RUN_DT FROM VT_RUN_DT)
;

INSERT INTO CASE_AGEING_DAILY
(
       BUSINESS_DT,
       QUEUE_CD,
       CASE_STATUS_CD,
       AGE_BAND_CD,
       CASE_CNT,
       OVER_SLA_CNT,
       CO_UPD_TMS
)
SELECT age.RUN_DT,
       age.QUEUE_CD,
       age.CASE_STATUS_CD,
       CASE
          WHEN age.AGE_BUS_DAYS <=  5 THEN '0-5'
          WHEN age.AGE_BUS_DAYS <= 10 THEN '6-10'
          WHEN age.AGE_BUS_DAYS <= 20 THEN '11-20'
          WHEN age.AGE_BUS_DAYS <= 30 THEN '21-30'
          ELSE '30+'
       END,
       COUNT (*),
       SUM (CASE WHEN age.SLA_DUE_DT < age.RUN_DT THEN 1 ELSE 0 END),
       CURRENT_TIMESTAMP
FROM
       (
        SELECT rd.RUN_DT                                             AS RUN_DT,
               COALESCE (cse.QUEUE_CD, 'AMLGEN')                     AS QUEUE_CD,
               cse.CASE_STATUS_CD                                    AS CASE_STATUS_CD,
               cse.SLA_DUE_DT                                        AS SLA_DUE_DT,
               COALESCE (bnw.BUS_DAY_SEQ - bop.BUS_DAY_SEQ, 999)     AS AGE_BUS_DAYS
        FROM
               AML_CASE            cse

               CROSS JOIN
               VT_RUN_DT                          rd

               LEFT OUTER JOIN
               VT_BUS_CAL                         bop
                  ON  bop.CAL_DT = cse.CASE_OPEN_DT

               LEFT OUTER JOIN
               VT_BUS_CAL                         bnw
                  ON  bnw.CAL_DT = rd.RUN_DT
        WHERE
               cse.CASE_STATUS_CD <> 'CLOSD'
        AND    cse.CASE_OPEN_DT   <= rd.RUN_DT
       )                                     age
GROUP  BY age.RUN_DT,
          age.QUEUE_CD,
          age.CASE_STATUS_CD,
          4
;


/**************************************************************************\
* CUST_RISK_DIST_DAILY - CUSTOMER RISK DISTRIBUTION                        *
* ------------------------------------------------------------------------ *
* Band movements are taken from the risk score history: versions opened   *
* on the business date compared with the version they replaced.           *
\**************************************************************************/

-- Converted the Teradata volatile CTAS to a Databricks session temporary table; PI and commit clauses were removed.
CREATE TEMP TABLE VT_BAND_MOVE AS
SELECT nwh.PARTY_ID,
       CASE WHEN CASE nwh.RISK_BAND_CD WHEN 'L' THEN 1 WHEN 'M' THEN 2
                                       WHEN 'H' THEN 3 WHEN 'VH' THEN 4 ELSE 0 END
               > CASE olh.RISK_BAND_CD WHEN 'L' THEN 1 WHEN 'M' THEN 2
                                       WHEN 'H' THEN 3 WHEN 'VH' THEN 4 ELSE 0 END
            THEN 'UP'
            WHEN CASE nwh.RISK_BAND_CD WHEN 'L' THEN 1 WHEN 'M' THEN 2
                                       WHEN 'H' THEN 3 WHEN 'VH' THEN 4 ELSE 0 END
               < CASE olh.RISK_BAND_CD WHEN 'L' THEN 1 WHEN 'M' THEN 2
                                       WHEN 'H' THEN 3 WHEN 'VH' THEN 4 ELSE 0 END
            THEN 'DN'
            ELSE 'EQ'
       END                                                      AS MOVE_CD
FROM
       PARTY_RISK_SCORE_HIST  nwh

       CROSS JOIN
       VT_RUN_DT                             rd

       INNER JOIN
       PARTY_RISK_SCORE_HIST  olh
          ON  olh.PARTY_ID = nwh.PARTY_ID
          AND olh.END_DT   = rd.RUN_DT - 1
WHERE
       nwh.START_DT = rd.RUN_DT;

DELETE FROM CUST_RISK_DIST_DAILY
WHERE  BUSINESS_DT = (SELECT RUN_DT FROM VT_RUN_DT)
;

INSERT INTO CUST_RISK_DIST_DAILY
(
       BUSINESS_DT,
       SEGMENT_CD,
       RISK_BAND_CD,
       PARTY_CNT,
       PEP_CNT,
       EDD_CNT,
       BAND_UP_CNT,
       BAND_DOWN_CNT,
       CO_UPD_TMS
)
SELECT rd.RUN_DT,
       COALESCE (psn.SEGMENT_CD, 'UNK'),
       COALESCE (prs.RISK_BAND_CD, 'NA'),
       COUNT (*),
       SUM (CASE WHEN prs.PEP_SCORE > 0 OR psn.PEP_IND = 'Y' THEN 1 ELSE 0 END),
       SUM (CASE WHEN prs.EDD_REQUIRED_IND = 'Y'            THEN 1 ELSE 0 END),
       SUM (CASE WHEN mov.MOVE_CD = 'UP'                     THEN 1 ELSE 0 END),
       SUM (CASE WHEN mov.MOVE_CD = 'DN'                     THEN 1 ELSE 0 END),
       CURRENT_TIMESTAMP
FROM
       PARTY_RISK_SCORE       prs

       CROSS JOIN
       VT_RUN_DT                             rd

       LEFT OUTER JOIN
       PARTY_SNAPSHOT         psn
          ON  psn.PARTY_ID = prs.PARTY_ID

       LEFT OUTER JOIN
       VT_BAND_MOVE                          mov
          ON  mov.PARTY_ID = prs.PARTY_ID
GROUP  BY rd.RUN_DT,
          COALESCE (psn.SEGMENT_CD, 'UNK'),
          COALESCE (prs.RISK_BAND_CD, 'NA')
;


/**************************************************************************\
* COLLECT STATISTICS ON THE MI TABLES                                      *
\**************************************************************************/

-- Teradata index-statistics maintenance was removed because Delta has no indexes and Photon maintains table statistics automatically.


/**************************************************************************\
* END OF SCRIPT                                                            *
\**************************************************************************/

