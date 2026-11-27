
/**************************************************************************\
* TAKE A TIMESTAMP SNAPSHOT                                                *
* ------------------------------------------------------------------------ *
* All data from current load operation shall receive the same timestamp.   *
* The business date is taken from the header record of the extract.       *
\**************************************************************************/

-- TODO: manual review required — choose a Databricks notebook, stored procedure, or Workflows DAG wrapper for this BTEQ script.
-- TODO: manual review required — map BTEQ .IF ERRORCODE / nonzero .QUIT behavior to procedure SIGNAL handling or Workflows task failure handling.
-- TODO: manual review required — map BTEQ ACTIVITYCOUNT checks to GET DIAGNOSTICS in a procedure or affected-row task metrics in Workflows.
-- TODO: manual review required — restructure BTEQ .GOTO LABEL control flow as a Workflows DAG branch.
-- assumption: <DB_ENV> is the target Unity Catalog placeholder and each Teradata database maps to a same-named schema.
-- Converted the environment-prefixed two-part source name to a catalog.schema.table target name.
DELETE FROM `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS
;

INSERT INTO `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS
(
       SSQ_ID,
       LOAD_TMS,
       BUSINESS_DT,
       FILE_ID,
       SUPPLIER_CD
)
SELECT 1,
       CURRENT_TIMESTAMP,
       TO_DATE(MAX(hdr.EXTRACT_DT), 'yyyyMMdd'),
       MIN (TRIM (hdr.FILE_ID)),
       MIN (TRIM (hdr.SUPPLIER_CD))
FROM
       `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_CTRL_RAW   hdr
WHERE
       hdr.RECTYPE = 'H'
HAVING COUNT (*) > 0
;

/* ------------------------------------------------------------------------ *
 * No header record received means the extract is incomplete -> abort      *
 * ------------------------------------------------------------------------ */


/**************************************************************************\
* RECONCILE TRAILER CONTROL TOTALS AGAINST RECEIVED DETAIL RECORDS         *
* ------------------------------------------------------------------------ *
* Trailer holds the expected record count and the debit / credit totals.   *
* The counts must match exactly, a difference in amount totals is logged   *
* as a warning only (rounding on the source side).                         *
\**************************************************************************/

-- Converted the multi-column IN delete predicate to a correlated EXISTS predicate.
DELETE FROM `<DB_ENV>`.DB_STREAM_DATA.INFO_DLYTXN_CTRL_RECON AS tgt
WHERE EXISTS
      (SELECT 1
       FROM `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_CTRL_RAW AS src
       WHERE src.RECTYPE = 'T'
       AND TRIM(src.FILE_ID) = tgt.FILE_ID
       AND TRIM(src.SUPPLIER_CD) = tgt.SUPPLIER_CD
      );

INSERT INTO `<DB_ENV>`.DB_STREAM_DATA.INFO_DLYTXN_CTRL_RECON
(
       FILE_ID,
       SUPPLIER_CD,
       EXTRACT_DT,
       EXP_REC_CNT,
       ACT_REC_CNT,
       EXP_DR_TOTAL,
       ACT_DR_TOTAL,
       EXP_CR_TOTAL,
       ACT_CR_TOTAL,
       RECON_STATUS_CD,
       CO_UPD_TMS
)
SELECT TRIM (trl.FILE_ID),
       TRIM (trl.SUPPLIER_CD),
       TO_DATE(trl.EXTRACT_DT, 'yyyyMMdd'),
       CAST (trl.REC_CNT  AS INTEGER),
       COALESCE(det.ACT_REC_CNT, 0),
       CAST (TRIM (trl.DR_TOTAL) AS DECIMAL(18,2)),
       COALESCE(det.ACT_DR_TOTAL, 0),
       CAST (TRIM (trl.CR_TOTAL) AS DECIMAL(18,2)),
       COALESCE(det.ACT_CR_TOTAL, 0),
       CASE
          WHEN CAST (trl.REC_CNT AS INTEGER) <> COALESCE(det.ACT_REC_CNT, 0)
          THEN 'CERR'
          WHEN CAST (TRIM (trl.DR_TOTAL) AS DECIMAL(18,2)) <> COALESCE(det.ACT_DR_TOTAL, 0)
            OR CAST (TRIM (trl.CR_TOTAL) AS DECIMAL(18,2)) <> COALESCE(det.ACT_CR_TOTAL, 0)
          THEN 'AWRN'
          ELSE 'OK'
       END,
       tms.LOAD_TMS
FROM
       `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_CTRL_RAW   trl

       CROSS JOIN
       `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS   tms

       LEFT OUTER JOIN
       (SELECT TRIM (SUPPLIER_CD)                                   AS SUPPLIER_CD,
               COUNT (*)                                            AS ACT_REC_CNT,
               SUM (CASE WHEN DR_CR_IND = 'D'
                         THEN ABS (CAST (CASE WHEN TRIM (TXN_AMT) = '' THEN '0'
                                              ELSE TRIM (TXN_AMT) END AS DECIMAL(18,2)))
                         ELSE 0 END)                                AS ACT_DR_TOTAL,
               SUM (CASE WHEN DR_CR_IND = 'C'
                         THEN ABS (CAST (CASE WHEN TRIM (TXN_AMT) = '' THEN '0'
                                              ELSE TRIM (TXN_AMT) END AS DECIMAL(18,2)))
                         ELSE 0 END)                                AS ACT_CR_TOTAL
        FROM   `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_DATA_RAW
        WHERE  RECTYPE = 'D'
        GROUP  BY 1
       )                                          det
          ON  det.SUPPLIER_CD = TRIM (trl.SUPPLIER_CD)
WHERE
       trl.RECTYPE = 'T'
;

/* ------------------------------------------------------------------------ *
 * Hard stop when record counts do not match the trailer                    *
 * ------------------------------------------------------------------------ */
SELECT rcn.FILE_ID,
       rcn.SUPPLIER_CD,
       rcn.EXP_REC_CNT,
       rcn.ACT_REC_CNT
FROM
       `<DB_ENV>`.DB_STREAM_DATA.INFO_DLYTXN_CTRL_RECON   rcn

       INNER JOIN
       `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS        tms
          ON  tms.LOAD_TMS = rcn.CO_UPD_TMS
WHERE
       rcn.RECON_STATUS_CD = 'CERR'
;


/**************************************************************************\
* MODIFY ANY INVALID DATES IN RAW DATA                                     *
* ------------------------------------------------------------------------ *
* This is a workaround in order to prevent failures in the processing when-*
* ever the source sends low / high values ("00000000", "99999999") or      *
* blanks instead of a valid date. Booking date falls back to the extract   *
* date, value date falls back to booking date.                             *
\**************************************************************************/

UPDATE `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_DATA_RAW
SET
       BOOKING_DT = EXTRACT_DT
WHERE
       BOOKING_DT IN ('00000000', '99999999', ' ')
OR     SUBSTR (BOOKING_DT, 5, 2) NOT BETWEEN '01' AND '12'
OR     SUBSTR (BOOKING_DT, 7, 2) NOT BETWEEN '01' AND '31'
;

UPDATE `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_DATA_RAW
SET
       VALUE_DT = BOOKING_DT
WHERE
       VALUE_DT IN ('00000000', '99999999', ' ')
OR     SUBSTR (VALUE_DT, 5, 2) NOT BETWEEN '01' AND '12'
OR     SUBSTR (VALUE_DT, 7, 2) NOT BETWEEN '01' AND '31'
;

UPDATE `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_DATA_RAW
SET
       TXN_TMS = BOOKING_DT || '000000'
WHERE
       SUBSTR (TXN_TMS, 1, 8) IN ('00000000', '99999999', ' ')
OR     SUBSTR (TXN_TMS, 9, 2) > '23'
OR     SUBSTR (TXN_TMS, 11, 2) > '59'
OR     SUBSTR (TXN_TMS, 13, 2) > '59'
;


/**************************************************************************\
* MODIFY ANY BLANK OR NON NUMERIC AMOUNTS IN RAW DATA                      *
\**************************************************************************/

UPDATE `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_DATA_RAW
SET
       TXN_AMT = '0'
WHERE
       TRIM (TXN_AMT) = ''
OR     TRY_CAST(TRIM (TXN_AMT) AS DECIMAL(18,2)) IS NULL
;

UPDATE `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_DATA_RAW
SET
       ORIG_AMT = TXN_AMT,
       ORIG_CCY = TXN_CCY
WHERE
       TRIM (ORIG_AMT) = ''
OR     TRY_CAST(TRIM (ORIG_AMT) AS DECIMAL(18,2)) IS NULL
;

UPDATE `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_DATA_RAW
SET
       FEE_AMT = '0'
WHERE
       TRIM (FEE_AMT) = ''
OR     TRY_CAST(TRIM (FEE_AMT) AS DECIMAL(18,2)) IS NULL
;

UPDATE `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_DATA_RAW
SET
       BAL_AFTER = NULL
WHERE
       TRIM (BAL_AFTER) = ''
OR     TRY_CAST(TRIM (BAL_AFTER) AS DECIMAL(18,2)) IS NULL
;

UPDATE `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_DATA_RAW
SET
       FILE_SEQ_NR = '0'
WHERE
       TRY_CAST(TRIM (FILE_SEQ_NR) AS INTEGER) IS NULL
;


/**************************************************************************\
* TYPE THE RAW RECORDS INTO A VOLATILE WORKTABLE                           *
* ------------------------------------------------------------------------ *
* Sign convention: amounts arrive unsigned, reversals arrive with a        *
* leading minus sign. The sign is kept as delivered, direction of the      *
* money flow is carried in DR_CR_IND.                                      *
* DUP_RANK = 1 marks the surviving record per TXN_REF / SUPPLIER_CD        *
* (highest file sequence number wins).                                     *
\**************************************************************************/

-- TODO: manual review required — confirm CHAR(14) overflow and blank-padding behavior for ACCT_ID.
-- Converted the Teradata volatile CTAS to a Databricks session-scoped temporary table and preserved CHAR(14) width with validation and RPAD.
CREATE TEMP TABLE VT_DLYTXN_TYPED
AS
(
SELECT TRIM (raw.SUPPLIER_CD)                                        AS SUPPLIER_CD,
       CAST (TRIM (raw.FILE_SEQ_NR) AS INTEGER)                      AS FILE_SEQ_NR,
       TRIM (raw.TXN_REF)                                            AS TXN_REF,
       CAST (CASE WHEN TRIM (raw.TXN_SEQ_NR) = '' THEN '0'
                  ELSE TRIM (raw.TXN_SEQ_NR) END AS SMALLINT)        AS TXN_SEQ_NR,
       CASE
          WHEN LENGTH(raw.SORT_CD || raw.ACCT_NR) > 14
          THEN RAISE_ERROR('ACCT_ID exceeds CHAR(14)')
          ELSE RPAD(raw.SORT_CD || raw.ACCT_NR, 14, ' ')
       END                                                           AS ACCT_ID,
       raw.SORT_CD                                                   AS SORT_CD,
       raw.ACCT_NR                                                   AS ACCT_NR,
       UPPER (raw.TXN_TYP_CD)                                        AS TXN_TYP_CD,
       UPPER (raw.CHNL_CD)                                           AS CHNL_CD,
       UPPER (raw.DR_CR_IND)                                         AS DR_CR_IND,
       CAST (TRIM (raw.TXN_AMT)  AS DECIMAL(18,2))                   AS TXN_AMT,
       UPPER (raw.TXN_CCY)                                           AS TXN_CCY,
       CAST (TRIM (raw.ORIG_AMT) AS DECIMAL(18,2))                   AS ORIG_AMT,
       UPPER (raw.ORIG_CCY)                                          AS ORIG_CCY,
       TO_DATE(raw.BOOKING_DT, 'yyyyMMdd')                            AS BOOKING_DT,
       TO_DATE(raw.VALUE_DT, 'yyyyMMdd')                              AS VALUE_DT,
       TO_TIMESTAMP(raw.TXN_TMS, 'yyyyMMddHHmmss')                    AS TXN_TMS,
       NULLIF (TRIM (raw.NARRATIVE), '')                             AS NARRATIVE,
       NULLIF (TRIM (raw.CPTY_NM), '')                               AS CPTY_NM,
       raw.CPTY_SORT_CD                                              AS CPTY_SORT_CD,
       raw.CPTY_ACCT_NR                                              AS CPTY_ACCT_NR,
       NULLIF(REPLACE(UPPER(TRIM(raw.CPTY_IBAN)), ' ', ''), '') AS CPTY_IBAN,
       UPPER (raw.CPTY_BIC)                                          AS CPTY_BIC,
       UPPER (raw.CPTY_BANK_CTRY)                                    AS CPTY_BANK_CTRY,
       UPPER (raw.CPTY_CTRY)                                         AS CPTY_CTRY,
       NULLIF (TRIM (raw.ORDERING_CUST_NM), '')                      AS ORDERING_CUST_NM,
       NULLIF (TRIM (raw.BENEF_CUST_NM), '')                         AS BENEF_CUST_NM,
       NULLIF (TRIM (raw.PAYMENT_REF), '')                           AS PAYMENT_REF,
       NULLIF (TRIM (raw.E2E_ID), '')                                AS E2E_ID,
       raw.UETR                                                      AS UETR,
       raw.SWIFT_MSG_TYP                                             AS SWIFT_MSG_TYP,
       raw.CHARGE_BEARER                                             AS CHARGE_BEARER,
       UPPER (raw.INTERMED_BIC)                                      AS INTERMED_BIC,
       raw.MCC                                                       AS MCC,
       NULLIF (TRIM (raw.MERCHANT_NM), '')                           AS MERCHANT_NM,
       UPPER (raw.MERCHANT_CTRY)                                     AS MERCHANT_CTRY,
       NULLIF (TRIM (raw.MERCHANT_ID), '')                           AS MERCHANT_ID,
       raw.TERMINAL_ID                                               AS TERMINAL_ID,
       raw.ATM_ID                                                    AS ATM_ID,
       raw.CARD_TOKEN                                                AS CARD_TOKEN,
       raw.POS_ENTRY_MODE                                            AS POS_ENTRY_MODE,
       COALESCE (NULLIF (raw.CARD_PRESENT_IND, ' '), 'N')            AS CARD_PRESENT_IND,
       raw.BRANCH_SORT_CD                                            AS BRANCH_SORT_CD,
       raw.TELLER_ID                                                 AS TELLER_ID,
       COALESCE (NULLIF (raw.CASH_IND, ' '), 'N')                    AS CASH_IND,
       raw.CHEQUE_NR                                                 AS CHEQUE_NR,
       NULLIF (TRIM (raw.DEVICE_ID), '')                             AS DEVICE_ID,
       NULLIF (TRIM (raw.IP_ADDR), '')                               AS IP_ADDR,
       UPPER (raw.IP_CTRY)                                           AS IP_CTRY,
       NULLIF (TRIM (raw.SESSION_ID), '')                            AS SESSION_ID,
       UPPER (raw.AUTH_METHOD)                                       AS AUTH_METHOD,
       UPPER (raw.COP_RESULT)                                        AS COP_RESULT,
       COALESCE (NULLIF (raw.APP_FRAUD_IND, ' '), 'N')               AS APP_FRAUD_IND,
       UPPER (raw.RETURN_REASON_CD)                                  AS RETURN_REASON_CD,
       COALESCE (NULLIF (raw.REVERSAL_IND, ' '), 'N')                AS REVERSAL_IND,
       NULLIF (TRIM (raw.ORIG_TXN_REF), '')                          AS ORIG_TXN_REF,
       CAST (TRIM (raw.BAL_AFTER) AS DECIMAL(18,2))                  AS BAL_AFTER,
       UPPER (raw.TXN_STATUS)                                        AS TXN_STATUS,
       CAST (TRIM (raw.FEE_AMT)  AS DECIMAL(18,2))                   AS FEE_AMT,
       UPPER (raw.PURPOSE_CD)                                        AS PURPOSE_CD,
       NULLIF (TRIM (raw.BATCH_ID), '')                              AS BATCH_ID,
       TO_DATE(raw.EXTRACT_DT, 'yyyyMMdd')                            AS EXTRACT_DT,
       tms.LOAD_TMS                                                  AS LOAD_TMS,
       SUM (1) OVER (PARTITION BY TRIM (raw.TXN_REF),
                                  TRIM (raw.SUPPLIER_CD)
                         ORDER BY CAST (TRIM (raw.FILE_SEQ_NR) AS INTEGER) DESC,
                                  raw.TXN_TMS DESC
                     ROWS UNBOUNDED PRECEDING
                    )                                                AS DUP_RANK
FROM
       `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_DATA_RAW   raw

       CROSS JOIN
       `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS   tms
WHERE
       raw.RECTYPE = 'D'
AND    TRIM (raw.TXN_REF) <> ''
);



/**************************************************************************\
* KEEP DUPLICATES WITHIN THE FILE IN HISTORY                               *
* ------------------------------------------------------------------------ *
* Duplicates based on the business key (Transaction Reference and         *
* Supplier Code) are dealt with via the window rank computed above. All    *
* but the record with the highest file sequence number go to history.      *
\**************************************************************************/

INSERT INTO `<DB_ENV>`.DB_STREAM_DATA.HIST_DLYTXN_LOAD_DUP
(
       SUPPLIER_CD,
       FILE_SEQ_NR,
       TXN_REF,
       TXN_SEQ_NR,
       ACCT_ID,
       SORT_CD,
       ACCT_NR,
       TXN_TYP_CD,
       CHNL_CD,
       DR_CR_IND,
       TXN_AMT,
       TXN_CCY,
       ORIG_AMT,
       ORIG_CCY,
       BOOKING_DT,
       VALUE_DT,
       TXN_TMS,
       NARRATIVE,
       CPTY_NM,
       CPTY_SORT_CD,
       CPTY_ACCT_NR,
       CPTY_IBAN,
       CPTY_BIC,
       CPTY_BANK_CTRY,
       CPTY_CTRY,
       ORDERING_CUST_NM,
       BENEF_CUST_NM,
       PAYMENT_REF,
       E2E_ID,
       UETR,
       SWIFT_MSG_TYP,
       CHARGE_BEARER,
       INTERMED_BIC,
       MCC,
       MERCHANT_NM,
       MERCHANT_CTRY,
       MERCHANT_ID,
       TERMINAL_ID,
       ATM_ID,
       CARD_TOKEN,
       POS_ENTRY_MODE,
       CARD_PRESENT_IND,
       BRANCH_SORT_CD,
       TELLER_ID,
       CASH_IND,
       CHEQUE_NR,
       DEVICE_ID,
       IP_ADDR,
       IP_CTRY,
       SESSION_ID,
       AUTH_METHOD,
       COP_RESULT,
       APP_FRAUD_IND,
       RETURN_REASON_CD,
       REVERSAL_IND,
       ORIG_TXN_REF,
       BAL_AFTER,
       TXN_STATUS,
       FEE_AMT,
       PURPOSE_CD,
       BATCH_ID,
       EXTRACT_DT,
       LOAD_TMS,
       DUP_REASON_CD,
       DUP_TMS
)
SELECT
       vt.SUPPLIER_CD,
       vt.FILE_SEQ_NR,
       vt.TXN_REF,
       vt.TXN_SEQ_NR,
       vt.ACCT_ID,
       vt.SORT_CD,
       vt.ACCT_NR,
       vt.TXN_TYP_CD,
       vt.CHNL_CD,
       vt.DR_CR_IND,
       vt.TXN_AMT,
       vt.TXN_CCY,
       vt.ORIG_AMT,
       vt.ORIG_CCY,
       vt.BOOKING_DT,
       vt.VALUE_DT,
       vt.TXN_TMS,
       vt.NARRATIVE,
       vt.CPTY_NM,
       vt.CPTY_SORT_CD,
       vt.CPTY_ACCT_NR,
       vt.CPTY_IBAN,
       vt.CPTY_BIC,
       vt.CPTY_BANK_CTRY,
       vt.CPTY_CTRY,
       vt.ORDERING_CUST_NM,
       vt.BENEF_CUST_NM,
       vt.PAYMENT_REF,
       vt.E2E_ID,
       vt.UETR,
       vt.SWIFT_MSG_TYP,
       vt.CHARGE_BEARER,
       vt.INTERMED_BIC,
       vt.MCC,
       vt.MERCHANT_NM,
       vt.MERCHANT_CTRY,
       vt.MERCHANT_ID,
       vt.TERMINAL_ID,
       vt.ATM_ID,
       vt.CARD_TOKEN,
       vt.POS_ENTRY_MODE,
       vt.CARD_PRESENT_IND,
       vt.BRANCH_SORT_CD,
       vt.TELLER_ID,
       vt.CASH_IND,
       vt.CHEQUE_NR,
       vt.DEVICE_ID,
       vt.IP_ADDR,
       vt.IP_CTRY,
       vt.SESSION_ID,
       vt.AUTH_METHOD,
       vt.COP_RESULT,
       vt.APP_FRAUD_IND,
       vt.RETURN_REASON_CD,
       vt.REVERSAL_IND,
       vt.ORIG_TXN_REF,
       vt.BAL_AFTER,
       vt.TXN_STATUS,
       vt.FEE_AMT,
       vt.PURPOSE_CD,
       vt.BATCH_ID,
       vt.EXTRACT_DT,
       vt.LOAD_TMS,
       'FD',
       vt.LOAD_TMS
FROM
       VT_DLYTXN_TYPED   vt
WHERE
       vt.DUP_RANK > 1
;


/**************************************************************************\
* FILTER THE DATA INTO A WORKTABLE WITH ONLY UNIQUE TRANSACTIONS           *
\**************************************************************************/

DELETE FROM `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD
;

INSERT INTO `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD
(
       SUPPLIER_CD,
       FILE_SEQ_NR,
       TXN_REF,
       TXN_SEQ_NR,
       ACCT_ID,
       SORT_CD,
       ACCT_NR,
       TXN_TYP_CD,
       CHNL_CD,
       DR_CR_IND,
       TXN_AMT,
       TXN_CCY,
       ORIG_AMT,
       ORIG_CCY,
       BOOKING_DT,
       VALUE_DT,
       TXN_TMS,
       NARRATIVE,
       CPTY_NM,
       CPTY_SORT_CD,
       CPTY_ACCT_NR,
       CPTY_IBAN,
       CPTY_BIC,
       CPTY_BANK_CTRY,
       CPTY_CTRY,
       ORDERING_CUST_NM,
       BENEF_CUST_NM,
       PAYMENT_REF,
       E2E_ID,
       UETR,
       SWIFT_MSG_TYP,
       CHARGE_BEARER,
       INTERMED_BIC,
       MCC,
       MERCHANT_NM,
       MERCHANT_CTRY,
       MERCHANT_ID,
       TERMINAL_ID,
       ATM_ID,
       CARD_TOKEN,
       POS_ENTRY_MODE,
       CARD_PRESENT_IND,
       BRANCH_SORT_CD,
       TELLER_ID,
       CASH_IND,
       CHEQUE_NR,
       DEVICE_ID,
       IP_ADDR,
       IP_CTRY,
       SESSION_ID,
       AUTH_METHOD,
       COP_RESULT,
       APP_FRAUD_IND,
       RETURN_REASON_CD,
       REVERSAL_IND,
       ORIG_TXN_REF,
       BAL_AFTER,
       TXN_STATUS,
       FEE_AMT,
       PURPOSE_CD,
       BATCH_ID,
       EXTRACT_DT,
       LOAD_TMS
)
SELECT
       vt.SUPPLIER_CD,
       vt.FILE_SEQ_NR,
       vt.TXN_REF,
       vt.TXN_SEQ_NR,
       vt.ACCT_ID,
       vt.SORT_CD,
       vt.ACCT_NR,
       vt.TXN_TYP_CD,
       vt.CHNL_CD,
       vt.DR_CR_IND,
       vt.TXN_AMT,
       vt.TXN_CCY,
       vt.ORIG_AMT,
       vt.ORIG_CCY,
       vt.BOOKING_DT,
       vt.VALUE_DT,
       vt.TXN_TMS,
       vt.NARRATIVE,
       vt.CPTY_NM,
       vt.CPTY_SORT_CD,
       vt.CPTY_ACCT_NR,
       vt.CPTY_IBAN,
       vt.CPTY_BIC,
       vt.CPTY_BANK_CTRY,
       vt.CPTY_CTRY,
       vt.ORDERING_CUST_NM,
       vt.BENEF_CUST_NM,
       vt.PAYMENT_REF,
       vt.E2E_ID,
       vt.UETR,
       vt.SWIFT_MSG_TYP,
       vt.CHARGE_BEARER,
       vt.INTERMED_BIC,
       vt.MCC,
       vt.MERCHANT_NM,
       vt.MERCHANT_CTRY,
       vt.MERCHANT_ID,
       vt.TERMINAL_ID,
       vt.ATM_ID,
       vt.CARD_TOKEN,
       vt.POS_ENTRY_MODE,
       vt.CARD_PRESENT_IND,
       vt.BRANCH_SORT_CD,
       vt.TELLER_ID,
       vt.CASH_IND,
       vt.CHEQUE_NR,
       vt.DEVICE_ID,
       vt.IP_ADDR,
       vt.IP_CTRY,
       vt.SESSION_ID,
       vt.AUTH_METHOD,
       vt.COP_RESULT,
       vt.APP_FRAUD_IND,
       vt.RETURN_REASON_CD,
       vt.REVERSAL_IND,
       vt.ORIG_TXN_REF,
       vt.BAL_AFTER,
       vt.TXN_STATUS,
       vt.FEE_AMT,
       vt.PURPOSE_CD,
       vt.BATCH_ID,
       vt.EXTRACT_DT,
       vt.LOAD_TMS
FROM
       VT_DLYTXN_TYPED   vt
WHERE
       vt.DUP_RANK = 1
;

-- Converted the volatile-table cleanup to Databricks temporary-table syntax.
DROP TEMPORARY TABLE VT_DLYTXN_TYPED;


/**************************************************************************\
* REMOVE TRANSACTIONS WHICH HAVE ALREADY BEEN PROCESSED                    *
* ------------------------------------------------------------------------ *
* Source systems re-send transactions in case of a restart. A record that  *
* is already present in the fact table with the same status and reversal  *
* flag is moved to the duplicate history (reason PD) and dropped from the  *
* load. Status changes and reversals are kept, they are applied as an     *
* update with before-image in dailytxn.10.                                 *
* The 35 day window allows partition elimination on the fact table.        *
\**************************************************************************/

INSERT INTO `<DB_ENV>`.DB_STREAM_DATA.HIST_DLYTXN_LOAD_DUP
(
       SUPPLIER_CD,
       FILE_SEQ_NR,
       TXN_REF,
       TXN_SEQ_NR,
       ACCT_ID,
       SORT_CD,
       ACCT_NR,
       TXN_TYP_CD,
       CHNL_CD,
       DR_CR_IND,
       TXN_AMT,
       TXN_CCY,
       ORIG_AMT,
       ORIG_CCY,
       BOOKING_DT,
       VALUE_DT,
       TXN_TMS,
       NARRATIVE,
       CPTY_NM,
       CPTY_SORT_CD,
       CPTY_ACCT_NR,
       CPTY_IBAN,
       CPTY_BIC,
       CPTY_BANK_CTRY,
       CPTY_CTRY,
       ORDERING_CUST_NM,
       BENEF_CUST_NM,
       PAYMENT_REF,
       E2E_ID,
       UETR,
       SWIFT_MSG_TYP,
       CHARGE_BEARER,
       INTERMED_BIC,
       MCC,
       MERCHANT_NM,
       MERCHANT_CTRY,
       MERCHANT_ID,
       TERMINAL_ID,
       ATM_ID,
       CARD_TOKEN,
       POS_ENTRY_MODE,
       CARD_PRESENT_IND,
       BRANCH_SORT_CD,
       TELLER_ID,
       CASH_IND,
       CHEQUE_NR,
       DEVICE_ID,
       IP_ADDR,
       IP_CTRY,
       SESSION_ID,
       AUTH_METHOD,
       COP_RESULT,
       APP_FRAUD_IND,
       RETURN_REASON_CD,
       REVERSAL_IND,
       ORIG_TXN_REF,
       BAL_AFTER,
       TXN_STATUS,
       FEE_AMT,
       PURPOSE_CD,
       BATCH_ID,
       EXTRACT_DT,
       LOAD_TMS,
       DUP_REASON_CD,
       DUP_TMS
)
SELECT
       dtl.SUPPLIER_CD,
       dtl.FILE_SEQ_NR,
       dtl.TXN_REF,
       dtl.TXN_SEQ_NR,
       dtl.ACCT_ID,
       dtl.SORT_CD,
       dtl.ACCT_NR,
       dtl.TXN_TYP_CD,
       dtl.CHNL_CD,
       dtl.DR_CR_IND,
       dtl.TXN_AMT,
       dtl.TXN_CCY,
       dtl.ORIG_AMT,
       dtl.ORIG_CCY,
       dtl.BOOKING_DT,
       dtl.VALUE_DT,
       dtl.TXN_TMS,
       dtl.NARRATIVE,
       dtl.CPTY_NM,
       dtl.CPTY_SORT_CD,
       dtl.CPTY_ACCT_NR,
       dtl.CPTY_IBAN,
       dtl.CPTY_BIC,
       dtl.CPTY_BANK_CTRY,
       dtl.CPTY_CTRY,
       dtl.ORDERING_CUST_NM,
       dtl.BENEF_CUST_NM,
       dtl.PAYMENT_REF,
       dtl.E2E_ID,
       dtl.UETR,
       dtl.SWIFT_MSG_TYP,
       dtl.CHARGE_BEARER,
       dtl.INTERMED_BIC,
       dtl.MCC,
       dtl.MERCHANT_NM,
       dtl.MERCHANT_CTRY,
       dtl.MERCHANT_ID,
       dtl.TERMINAL_ID,
       dtl.ATM_ID,
       dtl.CARD_TOKEN,
       dtl.POS_ENTRY_MODE,
       dtl.CARD_PRESENT_IND,
       dtl.BRANCH_SORT_CD,
       dtl.TELLER_ID,
       dtl.CASH_IND,
       dtl.CHEQUE_NR,
       dtl.DEVICE_ID,
       dtl.IP_ADDR,
       dtl.IP_CTRY,
       dtl.SESSION_ID,
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
       dtl.BATCH_ID,
       dtl.EXTRACT_DT,
       dtl.LOAD_TMS,
       'PD',
       tms.LOAD_TMS
FROM
       `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD       dtl

       CROSS JOIN
       `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS   tms

       INNER JOIN
       `<DB_ENV>`.DB_ODS.AML_TXN_DAILY               fct
          ON  fct.TXN_REF        = dtl.TXN_REF
          AND fct.SUPPLIER_CD    = dtl.SUPPLIER_CD
          AND fct.BOOKING_DT     = dtl.BOOKING_DT
WHERE
       fct.BOOKING_DT BETWEEN tms.BUSINESS_DT - 35 AND tms.BUSINESS_DT
AND    COALESCE (fct.TXN_STATUS_CD, ' ') = COALESCE (dtl.TXN_STATUS, ' ')
AND    COALESCE (fct.REVERSAL_IND,  'N') = COALESCE (dtl.REVERSAL_IND, 'N')
;

-- Converted the multi-column IN delete predicate to a correlated EXISTS predicate and made the cross join explicit.
DELETE FROM `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD AS tgt
WHERE EXISTS
      (SELECT 1
       FROM `<DB_ENV>`.DB_STREAM_DATA.HIST_DLYTXN_LOAD_DUP AS dup
       CROSS JOIN `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS AS tms
       WHERE dup.DUP_TMS = tms.LOAD_TMS
       AND dup.DUP_REASON_CD = 'PD'
       AND dup.TXN_REF = tgt.TXN_REF
       AND dup.SUPPLIER_CD = tgt.SUPPLIER_CD
      );


/**************************************************************************\
* SANITY CHECK - NOTHING LEFT TO PROCESS                                   *
* ------------------------------------------------------------------------ *
* An empty load after duplicate removal is not an error (restart after a   *
* successful run), the downstream steps are still executed to refresh the  *
* reference snapshots.                                                     *
\**************************************************************************/

SELECT COUNT (*)
FROM   `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD
HAVING COUNT (*) = 0
;




