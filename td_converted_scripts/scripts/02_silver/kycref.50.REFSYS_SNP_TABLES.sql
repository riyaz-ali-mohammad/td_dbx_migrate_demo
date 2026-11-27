-- TODO: manual review required — choose a DBSQL notebook, stored procedure, or Workflows DAG as the BTEQ script wrapper

/**************************************************************************\
* POPULATE CTRY_SNAPSHOT                                                   *
\**************************************************************************/


-- Converted the Teradata database-qualified name to current DBSQL catalog/schema resolution.
DELETE FROM CTRY_SNAPSHOT;

-- Converted Teradata database-qualified names to current DBSQL catalog/schema resolution.
INSERT INTO CTRY_SNAPSHOT
(
       CTRY_2_CD,
       CTRY_3_CD,
       CTRY_NM,
       FATF_STATUS_CD,
       CTRY_RISK_CD,
       HRC_IND
)
SELECT CTRY_2_CD,
       CTRY_3_CD,
       CTRY_NM,
       FATF_STATUS_CD,
       CTRY_RISK_CD,
       CASE WHEN CTRY_RISK_CD = 'H' THEN 'Y' ELSE 'N' END
FROM   CTRY
WHERE  END_DT    = DATE '9999-12-31'
AND    START_DT <= CURRENT_DATE

QUALIFY SUM (1) OVER (PARTITION BY  CTRY_2_CD
                          ORDER BY  START_DT DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;
-- TODO: manual review required — BTEQ .IF ERRORCODE / .QUIT must become SIGNAL or a Workflows branch


/**************************************************************************\
* POPULATE HIGH_RISK_CTRY_SNAPSHOT                                         *
\**************************************************************************/


-- Converted the Teradata database-qualified name to current DBSQL catalog/schema resolution.
DELETE FROM HIGH_RISK_CTRY_SNAPSHOT;

-- Converted Teradata database-qualified names to current DBSQL catalog/schema resolution.
INSERT INTO HIGH_RISK_CTRY_SNAPSHOT
(
       CTRY_2_CD,
       FATF_STATUS_CD,
       HMT_HIGH_RISK_IND,
       EU_HIGH_RISK_IND,
       OFFSHORE_IND,
       CTRY_RISK_CD
)
SELECT CTRY_2_CD,
       FATF_STATUS_CD,
       HMT_HIGH_RISK_IND,
       EU_HIGH_RISK_IND,
       OFFSHORE_IND,
       CTRY_RISK_CD
FROM   CTRY
WHERE  END_DT    = DATE '9999-12-31'
AND    START_DT <= CURRENT_DATE
AND    (   CTRY_RISK_CD = 'H'
        OR OFFSHORE_IND = 'Y'
       )

QUALIFY SUM (1) OVER (PARTITION BY  CTRY_2_CD
                          ORDER BY  START_DT DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;
-- TODO: manual review required — BTEQ .IF ERRORCODE / .QUIT must become SIGNAL or a Workflows branch


/**************************************************************************\
* POPULATE CCY_SNAPSHOT                                                    *
\**************************************************************************/


-- Converted the Teradata database-qualified name to current DBSQL catalog/schema resolution.
DELETE FROM CCY_SNAPSHOT;

-- Converted Teradata database-qualified names to current DBSQL catalog/schema resolution.
INSERT INTO CCY_SNAPSHOT
(
       CCY_CD,
       MINOR_UNIT_CNT
)
SELECT CCY_CD,
       MINOR_UNIT_CNT
FROM   CCY
WHERE  END_DT    = DATE '9999-12-31'
AND    START_DT <= CURRENT_DATE

QUALIFY SUM (1) OVER (PARTITION BY  CCY_CD
                          ORDER BY  START_DT DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;
-- TODO: manual review required — BTEQ .IF ERRORCODE / .QUIT must become SIGNAL or a Workflows branch


/**************************************************************************\
* POPULATE FX_RATE_SNAPSHOT                                                *
* ------------------------------------------------------------------------ *
* Latest available rate per currency. Spot (SP) is preferred over month-end *
* (ME) when both exist for the same date. GBP is always 1.                 *
\**************************************************************************/


-- Converted the Teradata database-qualified name to current DBSQL catalog/schema resolution.
DELETE FROM FX_RATE_SNAPSHOT;

-- Converted Teradata database-qualified names to current DBSQL catalog/schema resolution.
INSERT INTO FX_RATE_SNAPSHOT
(
       CCY_CD,
       RATE_DT,
       GBP_RATE
)
SELECT FXR.CCY_CD,
       FXR.RATE_DT,
       FXR.GBP_RATE
FROM
       (SELECT CCY_CD,
               RATE_DT,
               GBP_RATE
        FROM   FX_RATE
        WHERE  RATE_DT <= CURRENT_DATE
        AND    CCY_CD  <> 'GBP'
        QUALIFY SUM (1) OVER (PARTITION BY  CCY_CD
                                  ORDER BY  RATE_DT DESC
                                           ,CASE WHEN RATE_TYP_CD = 'SP' THEN 1 ELSE 2 END
                              ROWS UNBOUNDED PRECEDING
                             )  =  1
       )   FXR

UNION ALL

SELECT 'GBP',
       CURRENT_DATE,
       1.00000000
FROM   (SELECT 1 AS DUMMY)   DMY
;
-- TODO: manual review required — BTEQ .IF ERRORCODE / .QUIT must become SIGNAL or a Workflows branch


/**************************************************************************\
* POPULATE MCC_SNAPSHOT                                                    *
\**************************************************************************/


-- Converted the Teradata database-qualified name to current DBSQL catalog/schema resolution.
DELETE FROM MCC_SNAPSHOT;

-- Converted Teradata database-qualified names to current DBSQL catalog/schema resolution.
INSERT INTO MCC_SNAPSHOT
(
       MCC_CD,
       MCC_RISK_CD,
       CASH_LIKE_IND,
       GAMBLING_IND,
       CRYPTO_IND
)
SELECT MCC_CD,
       MCC_RISK_CD,
       CASH_LIKE_IND,
       GAMBLING_IND,
       CRYPTO_IND
FROM   MCC
WHERE  END_DT    = DATE '9999-12-31'
AND    START_DT <= CURRENT_DATE

QUALIFY SUM (1) OVER (PARTITION BY  MCC_CD
                          ORDER BY  START_DT DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;
-- TODO: manual review required — BTEQ .IF ERRORCODE / .QUIT must become SIGNAL or a Workflows branch


/**************************************************************************\
* POPULATE SORT_CD_SNAPSHOT                                                *
\**************************************************************************/


-- Converted the Teradata database-qualified name to current DBSQL catalog/schema resolution.
DELETE FROM SORT_CD_SNAPSHOT;

-- Converted Teradata database-qualified names to current DBSQL catalog/schema resolution.
INSERT INTO SORT_CD_SNAPSHOT
(
       SORT_CD,
       BIC_CD,
       CLOSED_IND
)
SELECT SORT_CD,
       BIC_CD,
       CLOSED_IND
FROM   SORT_CD_DIR
WHERE  END_DT    = DATE '9999-12-31'
AND    START_DT <= CURRENT_DATE

QUALIFY SUM (1) OVER (PARTITION BY  SORT_CD
                          ORDER BY  START_DT DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;
-- TODO: manual review required — BTEQ .IF ERRORCODE / .QUIT must become SIGNAL or a Workflows branch


/**************************************************************************\
* POPULATE TXN_TYP_SNAPSHOT                                                *
\**************************************************************************/


-- Converted the Teradata database-qualified name to current DBSQL catalog/schema resolution.
DELETE FROM TXN_TYP_SNAPSHOT;

-- Converted Teradata database-qualified names to current DBSQL catalog/schema resolution.
INSERT INTO TXN_TYP_SNAPSHOT
(
       TXN_TYP_CD,
       PAY_SCHEME_CD,
       DIRECTION_CD,
       CASH_IND,
       XBORDER_IND
)
SELECT TXN_TYP_CD,
       PAY_SCHEME_CD,
       DIRECTION_CD,
       CASH_IND,
       XBORDER_IND
FROM   TXN_TYP
WHERE  END_DT    = DATE '9999-12-31'
AND    START_DT <= CURRENT_DATE

QUALIFY SUM (1) OVER (PARTITION BY  TXN_TYP_CD
                          ORDER BY  START_DT DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;
-- TODO: manual review required — BTEQ .IF ERRORCODE / .QUIT must become SIGNAL or a Workflows branch


/**************************************************************************\
* POPULATE CHNL_SNAPSHOT                                                   *
\**************************************************************************/


-- Converted the Teradata database-qualified name to current DBSQL catalog/schema resolution.
DELETE FROM CHNL_SNAPSHOT;

-- Converted Teradata database-qualified names to current DBSQL catalog/schema resolution.
INSERT INTO CHNL_SNAPSHOT
(
       CHNL_CD,
       DIGITAL_IND
)
SELECT CHNL_CD,
       DIGITAL_IND
FROM   CHNL
WHERE  END_DT    = DATE '9999-12-31'
AND    START_DT <= CURRENT_DATE

QUALIFY SUM (1) OVER (PARTITION BY  CHNL_CD
                          ORDER BY  START_DT DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;
-- TODO: manual review required — BTEQ .IF ERRORCODE / .QUIT must become SIGNAL or a Workflows branch


/**************************************************************************\
* POPULATE PRDT_SNAPSHOT                                                   *
\**************************************************************************/


-- Converted the Teradata database-qualified name to current DBSQL catalog/schema resolution.
DELETE FROM PRDT_SNAPSHOT;

-- Converted Teradata database-qualified names to current DBSQL catalog/schema resolution.
INSERT INTO PRDT_SNAPSHOT
(
       PRDT_CD,
       PRDT_FAMILY_CD,
       SEGMENT_CD,
       PRDT_RISK_CD
)
SELECT PRDT_CD,
       PRDT_FAMILY_CD,
       SEGMENT_CD,
       PRDT_RISK_CD
FROM   PRDT
WHERE  END_DT    = DATE '9999-12-31'
AND    START_DT <= CURRENT_DATE

QUALIFY SUM (1) OVER (PARTITION BY  PRDT_CD
                          ORDER BY  START_DT DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;
-- TODO: manual review required — BTEQ .IF ERRORCODE / .QUIT must become SIGNAL or a Workflows branch


/**************************************************************************\
* POPULATE SIC_SNAPSHOT                                                    *
\**************************************************************************/


-- Converted the Teradata database-qualified name to current DBSQL catalog/schema resolution.
DELETE FROM SIC_SNAPSHOT;

-- Converted Teradata database-qualified names to current DBSQL catalog/schema resolution.
INSERT INTO SIC_SNAPSHOT
(
       SIC_CD,
       SIC_RISK_CD,
       CASH_INTENSIVE_IND
)
SELECT SIC_CD,
       SIC_RISK_CD,
       CASH_INTENSIVE_IND
FROM   SIC_OCCP
WHERE  END_DT    = DATE '9999-12-31'
AND    START_DT <= CURRENT_DATE

QUALIFY SUM (1) OVER (PARTITION BY  SIC_CD
                          ORDER BY  START_DT DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;
-- TODO: manual review required — BTEQ .IF ERRORCODE / .QUIT must become SIGNAL or a Workflows branch


/**************************************************************************\
* POPULATE TM_RULE_PARAM_SNAPSHOT                                          *
\**************************************************************************/


-- Converted the Teradata database-qualified name to current DBSQL catalog/schema resolution.
DELETE FROM TM_RULE_PARAM_SNAPSHOT;

-- Converted Teradata database-qualified names to current DBSQL catalog/schema resolution.
INSERT INTO TM_RULE_PARAM_SNAPSHOT
(
       RULE_CD,
       SEGMENT_CD,
       AMT_THRESHOLD,
       CNT_THRESHOLD,
       LOOKBACK_DAYS,
       PCT_THRESHOLD,
       SCORE_WEIGHT
)
SELECT RULE_CD,
       SEGMENT_CD,
       AMT_THRESHOLD,
       CNT_THRESHOLD,
       LOOKBACK_DAYS,
       PCT_THRESHOLD,
       SCORE_WEIGHT
FROM   TM_RULE_PARAM
WHERE  END_DT    = DATE '9999-12-31'
AND    START_DT <= CURRENT_DATE
AND    ACTIVE_IND = 'Y'

QUALIFY SUM (1) OVER (PARTITION BY  RULE_CD, SEGMENT_CD
                          ORDER BY  START_DT DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;
-- TODO: manual review required — BTEQ .IF ERRORCODE / .QUIT must become SIGNAL or a Workflows branch


/**************************************************************************\
* END OF SCRIPT                                                            *
\**************************************************************************/

