.set WIDTH       300;
.set TITLEDASHES OFF;

/**************************************************************************\
* PREPARATION                                                              *
\**************************************************************************/

COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD   INDEX (TXN_REF, SUPPLIER_CD);
COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_CPTY   INDEX (TXN_REF, SUPPLIER_CD);
COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_GBP    INDEX (TXN_REF, SUPPLIER_CD);
COLLECT STATISTICS <DB_ENV>DB_ODS.ACCT_SNAPSHOT           INDEX (ACCT_ID);
COLLECT STATISTICS <DB_ENV>DB_ODS.PARTY_SNAPSHOT          INDEX (PARTY_ID);
COLLECT STATISTICS <DB_ENV>DB_ODS.HIGH_RISK_CTRY_SNAPSHOT INDEX (CTRY_2_CD);


/**************************************************************************\
* STEP 1: PREPARE ALL RECEIVED TRANSACTIONS IN A WORK TABLE                *
* ------------------------------------------------------------------------ *
* The typed transaction is enriched with                                   *
*   - account / party attributes from the KYC snapshots                    *
*   - counterparty surrogate key and internal counterparty (dailytxn.05)   *
*   - GBP equivalent amount (dailytxn.06)                                  *
*   - payment scheme, cash and cross border flags from the txn type        *
*   - country risk and high risk country involvement                       *
*   - merchant category risk                                               *
*   - sanctions screening and DQ outcome (dailytxn.08 / dailytxn.07)       *
* ROUND_AMT_IND marks GBP amounts which are an exact multiple of 1,000.    *
\**************************************************************************/

DELETE FROM <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_FINAL
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_FINAL
(
       TXN_REF,
       SUPPLIER_CD,
       BOOKING_DT,
       VALUE_DT,
       TXN_TMS,
       ACCT_ID,
       SORT_CD,
       ACCT_NR,
       PARTY_ID,
       PRDT_CD,
       SEGMENT_CD,
       TXN_TYP_CD,
       PAY_SCHEME_CD,
       CHNL_CD,
       DR_CR_IND,
       TXN_AMT,
       TXN_CCY_CD,
       ORIG_AMT,
       ORIG_CCY_CD,
       GBP_AMT,
       GBP_RATE,
       CASH_IND,
       XBORDER_IND,
       ROUND_AMT_IND,
       NARRATIVE_TXT,
       CPTY_ID,
       CPTY_NM,
       CPTY_SORT_CD,
       CPTY_ACCT_NR,
       CPTY_IBAN,
       CPTY_BIC_CD,
       CPTY_BANK_CTRY_CD,
       CPTY_CTRY_CD,
       CPTY_CTRY_RISK_CD,
       CPTY_INTERNAL_IND,
       CPTY_PARTY_ID,
       ORDERING_CUST_NM,
       BENEF_CUST_NM,
       PAYMENT_REF,
       E2E_ID,
       UETR,
       SWIFT_MSG_TYP_CD,
       INTERMED_BIC_CD,
       MCC_CD,
       MCC_RISK_CD,
       MERCHANT_NM,
       MERCHANT_CTRY_CD,
       CARD_TOKEN,
       CARD_PRESENT_IND,
       ATM_ID,
       BRANCH_SORT_CD,
       CHEQUE_NR,
       DEVICE_ID,
       IP_CTRY_CD,
       AUTH_METHOD_CD,
       COP_RESULT_CD,
       APP_FRAUD_IND,
       RETURN_REASON_CD,
       REVERSAL_IND,
       ORIG_TXN_REF,
       BAL_AFTER_AMT,
       TXN_STATUS_CD,
       FEE_AMT,
       PURPOSE_CD,
       PARTY_RISK_RATING_CD,
       PARTY_PEP_IND,
       HRC_IND,
       SANC_HIT_IND,
       DQ_ERR_IND,
       BATCH_ID,
       FILE_SEQ_NR,
       LOAD_TMS,
       CO_UPD_TMS
)
SELECT
       dtl.TXN_REF,
       dtl.SUPPLIER_CD,
       dtl.BOOKING_DT,
       dtl.VALUE_DT,
       dtl.TXN_TMS,
       dtl.ACCT_ID,
       dtl.SORT_CD,
       dtl.ACCT_NR,
       acs.PRIMARY_PARTY_ID,
       acs.PRDT_CD,
       COALESCE (prs.SEGMENT_CD, acs.SEGMENT_CD, 'UNK'),
       dtl.TXN_TYP_CD,
       COALESCE (typ.PAY_SCHEME_CD, 'UNKN'),
       dtl.CHNL_CD,
       dtl.DR_CR_IND,
       dtl.TXN_AMT,
       dtl.TXN_CCY,
       dtl.ORIG_AMT,
       dtl.ORIG_CCY,
       gbp.GBP_AMT,
       gbp.GBP_RATE,
       CASE WHEN typ.CASH_IND = 'Y' OR dtl.CASH_IND = 'Y'
            THEN 'Y' ELSE 'N' END,
       CASE WHEN typ.XBORDER_IND = 'Y'
              OR COALESCE (cpt.CPTY_BANK_CTRY_CD, 'GB') NOT IN ('GB', ' ')
              OR COALESCE (NULLIF (dtl.MERCHANT_CTRY, ' '), 'GB') <> 'GB'
            THEN 'Y' ELSE 'N' END,
       CASE WHEN ABS (gbp.GBP_AMT) >= 1000
             AND ABS (gbp.GBP_AMT) MOD 1000 = 0
            THEN 'Y' ELSE 'N' END,
       dtl.NARRATIVE,
       cpt.CPTY_ID,
       dtl.CPTY_NM,
       dtl.CPTY_SORT_CD,
       dtl.CPTY_ACCT_NR,
       dtl.CPTY_IBAN,
       dtl.CPTY_BIC,
       cpt.CPTY_BANK_CTRY_CD,
       cpt.CPTY_CTRY_CD,
       cct.CTRY_RISK_CD,
       COALESCE (cpt.CPTY_INTERNAL_IND, 'N'),
       cpt.CPTY_PARTY_ID,
       dtl.ORDERING_CUST_NM,
       dtl.BENEF_CUST_NM,
       dtl.PAYMENT_REF,
       dtl.E2E_ID,
       dtl.UETR,
       dtl.SWIFT_MSG_TYP,
       dtl.INTERMED_BIC,
       dtl.MCC,
       mcc.MCC_RISK_CD,
       dtl.MERCHANT_NM,
       dtl.MERCHANT_CTRY,
       dtl.CARD_TOKEN,
       dtl.CARD_PRESENT_IND,
       dtl.ATM_ID,
       dtl.BRANCH_SORT_CD,
       dtl.CHEQUE_NR,
       dtl.DEVICE_ID,
       dtl.IP_CTRY,
       dtl.AUTH_METHOD,
       dtl.COP_RESULT,
       dtl.APP_FRAUD_IND,
       dtl.RETURN_REASON_CD,
       dtl.REVERSAL_IND,
       dtl.ORIG_TXN_REF,
       dtl.BAL_AFTER,
       dtl.TXN_STATUS,
       dtl.FEE_AMT,
       dtl.PURPOSE_CD,
       COALESCE (prs.RISK_RATING_CD, 'U'),
       COALESCE (prs.PEP_IND, 'N'),
       CASE WHEN hr1.CTRY_2_CD IS NOT NULL
              OR hr2.CTRY_2_CD IS NOT NULL
              OR hr3.CTRY_2_CD IS NOT NULL
            THEN 'Y' ELSE 'N' END,
       CASE WHEN hit.TXN_REF IS NOT NULL THEN 'Y' ELSE 'N' END,
       CASE WHEN err.ERR_KEY IS NOT NULL THEN 'Y' ELSE 'N' END,
       dtl.BATCH_ID,
       dtl.FILE_SEQ_NR,
       dtl.LOAD_TMS,
       tms.LOAD_TMS
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD          dtl

       CROSS JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS      tms

       LEFT OUTER JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_CPTY          cpt
          ON  cpt.TXN_REF     = dtl.TXN_REF
          AND cpt.SUPPLIER_CD = dtl.SUPPLIER_CD

       LEFT OUTER JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_GBP           gbp
          ON  gbp.TXN_REF     = dtl.TXN_REF
          AND gbp.SUPPLIER_CD = dtl.SUPPLIER_CD

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.ACCT_SNAPSHOT                  acs
          ON  acs.ACCT_ID = dtl.ACCT_ID

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.PARTY_SNAPSHOT                 prs
          ON  prs.PARTY_ID = acs.PRIMARY_PARTY_ID

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.TXN_TYP_SNAPSHOT               typ
          ON  typ.TXN_TYP_CD = dtl.TXN_TYP_CD

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.CTRY_SNAPSHOT                  cct
          ON  cct.CTRY_2_CD = cpt.CPTY_CTRY_CD

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.HIGH_RISK_CTRY_SNAPSHOT        hr1
          ON  hr1.CTRY_2_CD = cpt.CPTY_CTRY_CD

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.HIGH_RISK_CTRY_SNAPSHOT        hr2
          ON  hr2.CTRY_2_CD = cpt.CPTY_BANK_CTRY_CD

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.HIGH_RISK_CTRY_SNAPSHOT        hr3
          ON  hr3.CTRY_2_CD = dtl.MERCHANT_CTRY

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.MCC_SNAPSHOT                   mcc
          ON  mcc.MCC_CD = dtl.MCC

       LEFT OUTER JOIN
       (SELECT DISTINCT
               TXN_REF,
               SUPPLIER_CD
        FROM   <DB_ENV>DB_AML.SANC_SCREEN_HIT
        WHERE  HIT_STATUS_CD <> 'CLRD'
       )                                             hit
          ON  hit.TXN_REF     = dtl.TXN_REF
          AND hit.SUPPLIER_CD = dtl.SUPPLIER_CD

       LEFT OUTER JOIN
       (SELECT DISTINCT
               lg.ERR_KEY
        FROM   <DB_ENV>DB_STREAM_DATA.INFO_DLYTXN_ERROR_LOG   lg,
               <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS       ts
        WHERE  lg.BUSINESS_DT    = ts.BUSINESS_DT
        AND    lg.ERR_CLASS      = 'ERROR'
        AND    lg.ERR_PGM_SOURCE = 'dailytxn.07.CHECK_VALUES'
       )                                             err
          ON  err.ERR_KEY = TRIM (dtl.TXN_REF) || '|' || dtl.SUPPLIER_CD
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_FINAL INDEX (TXN_REF, SUPPLIER_CD);
COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_FINAL COLUMN (BOOKING_DT);


/**************************************************************************\
* STEP 2: KEEP THE BEFORE IMAGE OF CHANGED TRANSACTIONS                    *
* ------------------------------------------------------------------------ *
* Transactions that are re-delivered with a new status (e.g. pending ->    *
* booked, returned) or as reversal replace the existing fact row. The      *
* previous version is kept in the history table (HIST_ACTION_CD = U).      *
* Only the last 35 booking days are considered (partition elimination).    *
\**************************************************************************/

INSERT INTO <DB_ENV>DB_ODS.AML_TXN_DAILY_HIST
(
       TXN_REF,
       SUPPLIER_CD,
       BOOKING_DT,
       VALUE_DT,
       TXN_TMS,
       ACCT_ID,
       SORT_CD,
       ACCT_NR,
       PARTY_ID,
       PRDT_CD,
       SEGMENT_CD,
       TXN_TYP_CD,
       PAY_SCHEME_CD,
       CHNL_CD,
       DR_CR_IND,
       TXN_AMT,
       TXN_CCY_CD,
       ORIG_AMT,
       ORIG_CCY_CD,
       GBP_AMT,
       GBP_RATE,
       CASH_IND,
       XBORDER_IND,
       ROUND_AMT_IND,
       NARRATIVE_TXT,
       CPTY_ID,
       CPTY_NM,
       CPTY_SORT_CD,
       CPTY_ACCT_NR,
       CPTY_IBAN,
       CPTY_BIC_CD,
       CPTY_BANK_CTRY_CD,
       CPTY_CTRY_CD,
       CPTY_CTRY_RISK_CD,
       CPTY_INTERNAL_IND,
       CPTY_PARTY_ID,
       ORDERING_CUST_NM,
       BENEF_CUST_NM,
       PAYMENT_REF,
       E2E_ID,
       UETR,
       SWIFT_MSG_TYP_CD,
       INTERMED_BIC_CD,
       MCC_CD,
       MCC_RISK_CD,
       MERCHANT_NM,
       MERCHANT_CTRY_CD,
       CARD_TOKEN,
       CARD_PRESENT_IND,
       ATM_ID,
       BRANCH_SORT_CD,
       CHEQUE_NR,
       DEVICE_ID,
       IP_CTRY_CD,
       AUTH_METHOD_CD,
       COP_RESULT_CD,
       APP_FRAUD_IND,
       RETURN_REASON_CD,
       REVERSAL_IND,
       ORIG_TXN_REF,
       BAL_AFTER_AMT,
       TXN_STATUS_CD,
       FEE_AMT,
       PURPOSE_CD,
       PARTY_RISK_RATING_CD,
       PARTY_PEP_IND,
       HRC_IND,
       SANC_HIT_IND,
       DQ_ERR_IND,
       BATCH_ID,
       FILE_SEQ_NR,
       LOAD_TMS,
       CO_UPD_TMS,
       HIST_ACTION_CD,
       HIST_TMS
)
SELECT
       fct.TXN_REF,
       fct.SUPPLIER_CD,
       fct.BOOKING_DT,
       fct.VALUE_DT,
       fct.TXN_TMS,
       fct.ACCT_ID,
       fct.SORT_CD,
       fct.ACCT_NR,
       fct.PARTY_ID,
       fct.PRDT_CD,
       fct.SEGMENT_CD,
       fct.TXN_TYP_CD,
       fct.PAY_SCHEME_CD,
       fct.CHNL_CD,
       fct.DR_CR_IND,
       fct.TXN_AMT,
       fct.TXN_CCY_CD,
       fct.ORIG_AMT,
       fct.ORIG_CCY_CD,
       fct.GBP_AMT,
       fct.GBP_RATE,
       fct.CASH_IND,
       fct.XBORDER_IND,
       fct.ROUND_AMT_IND,
       fct.NARRATIVE_TXT,
       fct.CPTY_ID,
       fct.CPTY_NM,
       fct.CPTY_SORT_CD,
       fct.CPTY_ACCT_NR,
       fct.CPTY_IBAN,
       fct.CPTY_BIC_CD,
       fct.CPTY_BANK_CTRY_CD,
       fct.CPTY_CTRY_CD,
       fct.CPTY_CTRY_RISK_CD,
       fct.CPTY_INTERNAL_IND,
       fct.CPTY_PARTY_ID,
       fct.ORDERING_CUST_NM,
       fct.BENEF_CUST_NM,
       fct.PAYMENT_REF,
       fct.E2E_ID,
       fct.UETR,
       fct.SWIFT_MSG_TYP_CD,
       fct.INTERMED_BIC_CD,
       fct.MCC_CD,
       fct.MCC_RISK_CD,
       fct.MERCHANT_NM,
       fct.MERCHANT_CTRY_CD,
       fct.CARD_TOKEN,
       fct.CARD_PRESENT_IND,
       fct.ATM_ID,
       fct.BRANCH_SORT_CD,
       fct.CHEQUE_NR,
       fct.DEVICE_ID,
       fct.IP_CTRY_CD,
       fct.AUTH_METHOD_CD,
       fct.COP_RESULT_CD,
       fct.APP_FRAUD_IND,
       fct.RETURN_REASON_CD,
       fct.REVERSAL_IND,
       fct.ORIG_TXN_REF,
       fct.BAL_AFTER_AMT,
       fct.TXN_STATUS_CD,
       fct.FEE_AMT,
       fct.PURPOSE_CD,
       fct.PARTY_RISK_RATING_CD,
       fct.PARTY_PEP_IND,
       fct.HRC_IND,
       fct.SANC_HIT_IND,
       fct.DQ_ERR_IND,
       fct.BATCH_ID,
       fct.FILE_SEQ_NR,
       fct.LOAD_TMS,
       fct.CO_UPD_TMS,
       'U',
       tms.LOAD_TMS
FROM
       <DB_ENV>DB_ODS.AML_TXN_DAILY                  fct

       CROSS JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS      tms

       INNER JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_FINAL         fin
          ON  fin.TXN_REF     = fct.TXN_REF
          AND fin.SUPPLIER_CD = fct.SUPPLIER_CD
          AND fin.BOOKING_DT  = fct.BOOKING_DT
WHERE
       fct.BOOKING_DT BETWEEN tms.BUSINESS_DT - 35 AND tms.BUSINESS_DT
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* STEP 3: REMOVE THE CHANGED TRANSACTIONS FROM THE FACT TABLE              *
\**************************************************************************/

DELETE FROM <DB_ENV>DB_ODS.AML_TXN_DAILY
WHERE  (TXN_REF, SUPPLIER_CD, BOOKING_DT) IN
       (SELECT fin.TXN_REF,
               fin.SUPPLIER_CD,
               fin.BOOKING_DT
        FROM   <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_FINAL   fin
       )
AND    BOOKING_DT BETWEEN (SELECT BUSINESS_DT - 35
                           FROM   <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS
                           WHERE  SSQ_ID = 1)
                      AND (SELECT BUSINESS_DT
                           FROM   <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS
                           WHERE  SSQ_ID = 1)
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* STEP 4: APPLY ALL RECEIVED TRANSACTIONS TO THE FACT TABLE                *
\**************************************************************************/

INSERT INTO <DB_ENV>DB_ODS.AML_TXN_DAILY
(
       TXN_REF,
       SUPPLIER_CD,
       BOOKING_DT,
       VALUE_DT,
       TXN_TMS,
       ACCT_ID,
       SORT_CD,
       ACCT_NR,
       PARTY_ID,
       PRDT_CD,
       SEGMENT_CD,
       TXN_TYP_CD,
       PAY_SCHEME_CD,
       CHNL_CD,
       DR_CR_IND,
       TXN_AMT,
       TXN_CCY_CD,
       ORIG_AMT,
       ORIG_CCY_CD,
       GBP_AMT,
       GBP_RATE,
       CASH_IND,
       XBORDER_IND,
       ROUND_AMT_IND,
       NARRATIVE_TXT,
       CPTY_ID,
       CPTY_NM,
       CPTY_SORT_CD,
       CPTY_ACCT_NR,
       CPTY_IBAN,
       CPTY_BIC_CD,
       CPTY_BANK_CTRY_CD,
       CPTY_CTRY_CD,
       CPTY_CTRY_RISK_CD,
       CPTY_INTERNAL_IND,
       CPTY_PARTY_ID,
       ORDERING_CUST_NM,
       BENEF_CUST_NM,
       PAYMENT_REF,
       E2E_ID,
       UETR,
       SWIFT_MSG_TYP_CD,
       INTERMED_BIC_CD,
       MCC_CD,
       MCC_RISK_CD,
       MERCHANT_NM,
       MERCHANT_CTRY_CD,
       CARD_TOKEN,
       CARD_PRESENT_IND,
       ATM_ID,
       BRANCH_SORT_CD,
       CHEQUE_NR,
       DEVICE_ID,
       IP_CTRY_CD,
       AUTH_METHOD_CD,
       COP_RESULT_CD,
       APP_FRAUD_IND,
       RETURN_REASON_CD,
       REVERSAL_IND,
       ORIG_TXN_REF,
       BAL_AFTER_AMT,
       TXN_STATUS_CD,
       FEE_AMT,
       PURPOSE_CD,
       PARTY_RISK_RATING_CD,
       PARTY_PEP_IND,
       HRC_IND,
       SANC_HIT_IND,
       DQ_ERR_IND,
       BATCH_ID,
       FILE_SEQ_NR,
       LOAD_TMS,
       CO_UPD_TMS
)
SELECT
       fin.TXN_REF,
       fin.SUPPLIER_CD,
       fin.BOOKING_DT,
       fin.VALUE_DT,
       fin.TXN_TMS,
       fin.ACCT_ID,
       fin.SORT_CD,
       fin.ACCT_NR,
       fin.PARTY_ID,
       fin.PRDT_CD,
       fin.SEGMENT_CD,
       fin.TXN_TYP_CD,
       fin.PAY_SCHEME_CD,
       fin.CHNL_CD,
       fin.DR_CR_IND,
       fin.TXN_AMT,
       fin.TXN_CCY_CD,
       fin.ORIG_AMT,
       fin.ORIG_CCY_CD,
       fin.GBP_AMT,
       fin.GBP_RATE,
       fin.CASH_IND,
       fin.XBORDER_IND,
       fin.ROUND_AMT_IND,
       fin.NARRATIVE_TXT,
       fin.CPTY_ID,
       fin.CPTY_NM,
       fin.CPTY_SORT_CD,
       fin.CPTY_ACCT_NR,
       fin.CPTY_IBAN,
       fin.CPTY_BIC_CD,
       fin.CPTY_BANK_CTRY_CD,
       fin.CPTY_CTRY_CD,
       fin.CPTY_CTRY_RISK_CD,
       fin.CPTY_INTERNAL_IND,
       fin.CPTY_PARTY_ID,
       fin.ORDERING_CUST_NM,
       fin.BENEF_CUST_NM,
       fin.PAYMENT_REF,
       fin.E2E_ID,
       fin.UETR,
       fin.SWIFT_MSG_TYP_CD,
       fin.INTERMED_BIC_CD,
       fin.MCC_CD,
       fin.MCC_RISK_CD,
       fin.MERCHANT_NM,
       fin.MERCHANT_CTRY_CD,
       fin.CARD_TOKEN,
       fin.CARD_PRESENT_IND,
       fin.ATM_ID,
       fin.BRANCH_SORT_CD,
       fin.CHEQUE_NR,
       fin.DEVICE_ID,
       fin.IP_CTRY_CD,
       fin.AUTH_METHOD_CD,
       fin.COP_RESULT_CD,
       fin.APP_FRAUD_IND,
       fin.RETURN_REASON_CD,
       fin.REVERSAL_IND,
       fin.ORIG_TXN_REF,
       fin.BAL_AFTER_AMT,
       fin.TXN_STATUS_CD,
       fin.FEE_AMT,
       fin.PURPOSE_CD,
       fin.PARTY_RISK_RATING_CD,
       fin.PARTY_PEP_IND,
       fin.HRC_IND,
       fin.SANC_HIT_IND,
       fin.DQ_ERR_IND,
       fin.BATCH_ID,
       fin.FILE_SEQ_NR,
       fin.LOAD_TMS,
       fin.CO_UPD_TMS
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_FINAL   fin
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* STEP 5: FLAG THE ORIGINAL TRANSACTION OF A REVERSAL                      *
* ------------------------------------------------------------------------ *
* A reversal references the transaction it reverses (ORIG_TXN_REF). The    *
* original is set to status RV after its before image has been written     *
* to history, so that the transaction monitoring does not count both the   *
* original and the reversal. Reversals are matched within 90 days.         *
\**************************************************************************/

CREATE VOLATILE TABLE VT_REVERSED_TXN
AS
(
SELECT fct.TXN_REF,
       fct.SUPPLIER_CD,
       fct.BOOKING_DT
FROM
       <DB_ENV>DB_ODS.AML_TXN_DAILY                  fct

       CROSS JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS      tms

       INNER JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_FINAL         rev
          ON  rev.ORIG_TXN_REF = fct.TXN_REF
          AND rev.SUPPLIER_CD  = fct.SUPPLIER_CD
          AND rev.ACCT_ID      = fct.ACCT_ID
WHERE
       rev.REVERSAL_IND = 'Y'
AND    fct.BOOKING_DT BETWEEN tms.BUSINESS_DT - 90 AND tms.BUSINESS_DT
AND    COALESCE (fct.TXN_STATUS_CD, ' ') <> 'RV'
AND    fct.REVERSAL_IND = 'N'

QUALIFY SUM (1) OVER (PARTITION BY  fct.TXN_REF,
                                    fct.SUPPLIER_CD
                          ORDER BY  fct.BOOKING_DT DESC
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
)
WITH DATA
PRIMARY INDEX ( TXN_REF, SUPPLIER_CD )
ON COMMIT PRESERVE ROWS
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_ODS.AML_TXN_DAILY_HIST
(
       TXN_REF,
       SUPPLIER_CD,
       BOOKING_DT,
       VALUE_DT,
       TXN_TMS,
       ACCT_ID,
       SORT_CD,
       ACCT_NR,
       PARTY_ID,
       PRDT_CD,
       SEGMENT_CD,
       TXN_TYP_CD,
       PAY_SCHEME_CD,
       CHNL_CD,
       DR_CR_IND,
       TXN_AMT,
       TXN_CCY_CD,
       ORIG_AMT,
       ORIG_CCY_CD,
       GBP_AMT,
       GBP_RATE,
       CASH_IND,
       XBORDER_IND,
       ROUND_AMT_IND,
       NARRATIVE_TXT,
       CPTY_ID,
       CPTY_NM,
       CPTY_SORT_CD,
       CPTY_ACCT_NR,
       CPTY_IBAN,
       CPTY_BIC_CD,
       CPTY_BANK_CTRY_CD,
       CPTY_CTRY_CD,
       CPTY_CTRY_RISK_CD,
       CPTY_INTERNAL_IND,
       CPTY_PARTY_ID,
       ORDERING_CUST_NM,
       BENEF_CUST_NM,
       PAYMENT_REF,
       E2E_ID,
       UETR,
       SWIFT_MSG_TYP_CD,
       INTERMED_BIC_CD,
       MCC_CD,
       MCC_RISK_CD,
       MERCHANT_NM,
       MERCHANT_CTRY_CD,
       CARD_TOKEN,
       CARD_PRESENT_IND,
       ATM_ID,
       BRANCH_SORT_CD,
       CHEQUE_NR,
       DEVICE_ID,
       IP_CTRY_CD,
       AUTH_METHOD_CD,
       COP_RESULT_CD,
       APP_FRAUD_IND,
       RETURN_REASON_CD,
       REVERSAL_IND,
       ORIG_TXN_REF,
       BAL_AFTER_AMT,
       TXN_STATUS_CD,
       FEE_AMT,
       PURPOSE_CD,
       PARTY_RISK_RATING_CD,
       PARTY_PEP_IND,
       HRC_IND,
       SANC_HIT_IND,
       DQ_ERR_IND,
       BATCH_ID,
       FILE_SEQ_NR,
       LOAD_TMS,
       CO_UPD_TMS,
       HIST_ACTION_CD,
       HIST_TMS
)
SELECT
       fct.TXN_REF,
       fct.SUPPLIER_CD,
       fct.BOOKING_DT,
       fct.VALUE_DT,
       fct.TXN_TMS,
       fct.ACCT_ID,
       fct.SORT_CD,
       fct.ACCT_NR,
       fct.PARTY_ID,
       fct.PRDT_CD,
       fct.SEGMENT_CD,
       fct.TXN_TYP_CD,
       fct.PAY_SCHEME_CD,
       fct.CHNL_CD,
       fct.DR_CR_IND,
       fct.TXN_AMT,
       fct.TXN_CCY_CD,
       fct.ORIG_AMT,
       fct.ORIG_CCY_CD,
       fct.GBP_AMT,
       fct.GBP_RATE,
       fct.CASH_IND,
       fct.XBORDER_IND,
       fct.ROUND_AMT_IND,
       fct.NARRATIVE_TXT,
       fct.CPTY_ID,
       fct.CPTY_NM,
       fct.CPTY_SORT_CD,
       fct.CPTY_ACCT_NR,
       fct.CPTY_IBAN,
       fct.CPTY_BIC_CD,
       fct.CPTY_BANK_CTRY_CD,
       fct.CPTY_CTRY_CD,
       fct.CPTY_CTRY_RISK_CD,
       fct.CPTY_INTERNAL_IND,
       fct.CPTY_PARTY_ID,
       fct.ORDERING_CUST_NM,
       fct.BENEF_CUST_NM,
       fct.PAYMENT_REF,
       fct.E2E_ID,
       fct.UETR,
       fct.SWIFT_MSG_TYP_CD,
       fct.INTERMED_BIC_CD,
       fct.MCC_CD,
       fct.MCC_RISK_CD,
       fct.MERCHANT_NM,
       fct.MERCHANT_CTRY_CD,
       fct.CARD_TOKEN,
       fct.CARD_PRESENT_IND,
       fct.ATM_ID,
       fct.BRANCH_SORT_CD,
       fct.CHEQUE_NR,
       fct.DEVICE_ID,
       fct.IP_CTRY_CD,
       fct.AUTH_METHOD_CD,
       fct.COP_RESULT_CD,
       fct.APP_FRAUD_IND,
       fct.RETURN_REASON_CD,
       fct.REVERSAL_IND,
       fct.ORIG_TXN_REF,
       fct.BAL_AFTER_AMT,
       fct.TXN_STATUS_CD,
       fct.FEE_AMT,
       fct.PURPOSE_CD,
       fct.PARTY_RISK_RATING_CD,
       fct.PARTY_PEP_IND,
       fct.HRC_IND,
       fct.SANC_HIT_IND,
       fct.DQ_ERR_IND,
       fct.BATCH_ID,
       fct.FILE_SEQ_NR,
       fct.LOAD_TMS,
       fct.CO_UPD_TMS,
       'R',
       tms.LOAD_TMS
FROM
       <DB_ENV>DB_ODS.AML_TXN_DAILY                  fct

       CROSS JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS      tms

       INNER JOIN
       VT_REVERSED_TXN                               vrt
          ON  vrt.TXN_REF     = fct.TXN_REF
          AND vrt.SUPPLIER_CD = fct.SUPPLIER_CD
          AND vrt.BOOKING_DT  = fct.BOOKING_DT
;
.if errorcode <> 0 then .quit errorcode;

UPDATE fct
FROM   <DB_ENV>DB_ODS.AML_TXN_DAILY              fct,
       VT_REVERSED_TXN                           vrt,
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS  tms
SET    TXN_STATUS_CD = 'RV',
       CO_UPD_TMS    = tms.LOAD_TMS
WHERE  fct.TXN_REF     = vrt.TXN_REF
AND    fct.SUPPLIER_CD = vrt.SUPPLIER_CD
AND    fct.BOOKING_DT  = vrt.BOOKING_DT
;
.if errorcode <> 0 then .quit errorcode;

DROP TABLE VT_REVERSED_TXN
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* STEP 6: STATISTICS AND LOAD SUMMARY                                      *
\**************************************************************************/

COLLECT STATISTICS <DB_ENV>DB_ODS.AML_TXN_DAILY COLUMN (PARTITION);
COLLECT STATISTICS <DB_ENV>DB_ODS.AML_TXN_DAILY COLUMN (BOOKING_DT);
COLLECT STATISTICS <DB_ENV>DB_ODS.AML_TXN_DAILY INDEX  (ACCT_ID);
COLLECT STATISTICS <DB_ENV>DB_ODS.AML_TXN_DAILY INDEX  (TXN_REF, SUPPLIER_CD, BOOKING_DT);
COLLECT STATISTICS <DB_ENV>DB_ODS.AML_TXN_DAILY_HIST COLUMN (PARTITION);

SELECT fin.SUPPLIER_CD,
       fin.PAY_SCHEME_CD,
       fin.DR_CR_IND,
       COUNT (*)                                                AS TXN_CNT,
       SUM (fin.GBP_AMT)                                        AS GBP_AMT,
       SUM (CASE WHEN fin.HRC_IND      = 'Y' THEN 1 ELSE 0 END) AS HRC_CNT,
       SUM (CASE WHEN fin.SANC_HIT_IND = 'Y' THEN 1 ELSE 0 END) AS SANC_HIT_CNT,
       SUM (CASE WHEN fin.DQ_ERR_IND   = 'Y' THEN 1 ELSE 0 END) AS DQ_ERR_CNT
FROM   <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_FINAL   fin
GROUP  BY 1, 2, 3
ORDER  BY 1, 2, 3
;
.if errorcode <> 0 then .quit errorcode;

.quit 0;

