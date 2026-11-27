.set WIDTH       300;
.set TITLEDASHES OFF;


/**************************************************************************\
* POPULATE CTRY_SNAPSHOT                                                   *
\**************************************************************************/


DELETE FROM <DB_ENV>DB_ODS.CTRY_SNAPSHOT

; INSERT INTO <DB_ENV>DB_ODS.CTRY_SNAPSHOT
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
FROM   <DB_ENV>DB_ODS.CTRY
WHERE  END_DT    = DATE '9999-12-31'
AND    START_DT <= CURRENT_DATE

QUALIFY SUM (1) OVER (PARTITION BY  CTRY_2_CD
                          ORDER BY  START_DT DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_ODS.CTRY_SNAPSHOT INDEX (CTRY_2_CD);


/**************************************************************************\
* POPULATE HIGH_RISK_CTRY_SNAPSHOT                                         *
\**************************************************************************/


DELETE FROM <DB_ENV>DB_ODS.HIGH_RISK_CTRY_SNAPSHOT

; INSERT INTO <DB_ENV>DB_ODS.HIGH_RISK_CTRY_SNAPSHOT
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
FROM   <DB_ENV>DB_ODS.CTRY
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
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_ODS.HIGH_RISK_CTRY_SNAPSHOT INDEX (CTRY_2_CD);


/**************************************************************************\
* POPULATE CCY_SNAPSHOT                                                    *
\**************************************************************************/


DELETE FROM <DB_ENV>DB_ODS.CCY_SNAPSHOT

; INSERT INTO <DB_ENV>DB_ODS.CCY_SNAPSHOT
(
       CCY_CD,
       MINOR_UNIT_CNT
)
SELECT CCY_CD,
       MINOR_UNIT_CNT
FROM   <DB_ENV>DB_ODS.CCY
WHERE  END_DT    = DATE '9999-12-31'
AND    START_DT <= CURRENT_DATE

QUALIFY SUM (1) OVER (PARTITION BY  CCY_CD
                          ORDER BY  START_DT DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_ODS.CCY_SNAPSHOT INDEX (CCY_CD);


/**************************************************************************\
* POPULATE FX_RATE_SNAPSHOT                                                *
* ------------------------------------------------------------------------ *
* Latest available rate per currency. Spot (SP) is preferred over month-end *
* (ME) when both exist for the same date. GBP is always 1.                 *
\**************************************************************************/


DELETE FROM <DB_ENV>DB_ODS.FX_RATE_SNAPSHOT

; INSERT INTO <DB_ENV>DB_ODS.FX_RATE_SNAPSHOT
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
        FROM   <DB_ENV>DB_ODS.FX_RATE
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
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_ODS.FX_RATE_SNAPSHOT INDEX (CCY_CD);


/**************************************************************************\
* POPULATE MCC_SNAPSHOT                                                    *
\**************************************************************************/


DELETE FROM <DB_ENV>DB_ODS.MCC_SNAPSHOT

; INSERT INTO <DB_ENV>DB_ODS.MCC_SNAPSHOT
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
FROM   <DB_ENV>DB_ODS.MCC
WHERE  END_DT    = DATE '9999-12-31'
AND    START_DT <= CURRENT_DATE

QUALIFY SUM (1) OVER (PARTITION BY  MCC_CD
                          ORDER BY  START_DT DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_ODS.MCC_SNAPSHOT INDEX (MCC_CD);


/**************************************************************************\
* POPULATE SORT_CD_SNAPSHOT                                                *
\**************************************************************************/


DELETE FROM <DB_ENV>DB_ODS.SORT_CD_SNAPSHOT

; INSERT INTO <DB_ENV>DB_ODS.SORT_CD_SNAPSHOT
(
       SORT_CD,
       BIC_CD,
       CLOSED_IND
)
SELECT SORT_CD,
       BIC_CD,
       CLOSED_IND
FROM   <DB_ENV>DB_ODS.SORT_CD_DIR
WHERE  END_DT    = DATE '9999-12-31'
AND    START_DT <= CURRENT_DATE

QUALIFY SUM (1) OVER (PARTITION BY  SORT_CD
                          ORDER BY  START_DT DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_ODS.SORT_CD_SNAPSHOT INDEX (SORT_CD);


/**************************************************************************\
* POPULATE TXN_TYP_SNAPSHOT                                                *
\**************************************************************************/


DELETE FROM <DB_ENV>DB_ODS.TXN_TYP_SNAPSHOT

; INSERT INTO <DB_ENV>DB_ODS.TXN_TYP_SNAPSHOT
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
FROM   <DB_ENV>DB_ODS.TXN_TYP
WHERE  END_DT    = DATE '9999-12-31'
AND    START_DT <= CURRENT_DATE

QUALIFY SUM (1) OVER (PARTITION BY  TXN_TYP_CD
                          ORDER BY  START_DT DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_ODS.TXN_TYP_SNAPSHOT INDEX (TXN_TYP_CD);


/**************************************************************************\
* POPULATE CHNL_SNAPSHOT                                                   *
\**************************************************************************/


DELETE FROM <DB_ENV>DB_ODS.CHNL_SNAPSHOT

; INSERT INTO <DB_ENV>DB_ODS.CHNL_SNAPSHOT
(
       CHNL_CD,
       DIGITAL_IND
)
SELECT CHNL_CD,
       DIGITAL_IND
FROM   <DB_ENV>DB_ODS.CHNL
WHERE  END_DT    = DATE '9999-12-31'
AND    START_DT <= CURRENT_DATE

QUALIFY SUM (1) OVER (PARTITION BY  CHNL_CD
                          ORDER BY  START_DT DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_ODS.CHNL_SNAPSHOT INDEX (CHNL_CD);


/**************************************************************************\
* POPULATE PRDT_SNAPSHOT                                                   *
\**************************************************************************/


DELETE FROM <DB_ENV>DB_ODS.PRDT_SNAPSHOT

; INSERT INTO <DB_ENV>DB_ODS.PRDT_SNAPSHOT
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
FROM   <DB_ENV>DB_ODS.PRDT
WHERE  END_DT    = DATE '9999-12-31'
AND    START_DT <= CURRENT_DATE

QUALIFY SUM (1) OVER (PARTITION BY  PRDT_CD
                          ORDER BY  START_DT DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_ODS.PRDT_SNAPSHOT INDEX (PRDT_CD);


/**************************************************************************\
* POPULATE SIC_SNAPSHOT                                                    *
\**************************************************************************/


DELETE FROM <DB_ENV>DB_ODS.SIC_SNAPSHOT

; INSERT INTO <DB_ENV>DB_ODS.SIC_SNAPSHOT
(
       SIC_CD,
       SIC_RISK_CD,
       CASH_INTENSIVE_IND
)
SELECT SIC_CD,
       SIC_RISK_CD,
       CASH_INTENSIVE_IND
FROM   <DB_ENV>DB_ODS.SIC_OCCP
WHERE  END_DT    = DATE '9999-12-31'
AND    START_DT <= CURRENT_DATE

QUALIFY SUM (1) OVER (PARTITION BY  SIC_CD
                          ORDER BY  START_DT DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_ODS.SIC_SNAPSHOT INDEX (SIC_CD);


/**************************************************************************\
* POPULATE TM_RULE_PARAM_SNAPSHOT                                          *
\**************************************************************************/


DELETE FROM <DB_ENV>DB_ODS.TM_RULE_PARAM_SNAPSHOT

; INSERT INTO <DB_ENV>DB_ODS.TM_RULE_PARAM_SNAPSHOT
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
FROM   <DB_ENV>DB_ODS.TM_RULE_PARAM
WHERE  END_DT    = DATE '9999-12-31'
AND    START_DT <= CURRENT_DATE
AND    ACTIVE_IND = 'Y'

QUALIFY SUM (1) OVER (PARTITION BY  RULE_CD, SEGMENT_CD
                          ORDER BY  START_DT DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_ODS.TM_RULE_PARAM_SNAPSHOT INDEX (RULE_CD, SEGMENT_CD);


/**************************************************************************\
* END OF SCRIPT                                                            *
\**************************************************************************/

.quit 0;
