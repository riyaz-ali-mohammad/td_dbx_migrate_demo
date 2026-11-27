----------------------------------------
-- Consumption view on the AML transaction fact.
-- Row filter : only segments granted to the session user in DB_REFERENCE.VIEW_ACCESS_CTRL
-- Column mask: counterparty / customer names, IBAN and card token unless PII_ACCESS_IND = 'Y'
----------------------------------------

-- Converted Teradata REPLACE VIEW to Databricks CREATE OR REPLACE VIEW.
-- Converted Teradata LOCKING FOR ACCESS hints to Delta committed-snapshot reads.
-- assumption: the current catalog contains same-named schemas VX_AML, DB_ODS, and DB_REFERENCE.
-- Converted Teradata USER to the Databricks current_user() function.
-- TODO: manual review required — confirm the bounded VARCHAR(140) mask casts use the intended source overflow mode; the current constant is within the bound.
-- TODO: manual review required — confirm downstream consumers require CHAR(19) trailing-blank padding; RPAD preserves the source fixed width.
CREATE OR REPLACE VIEW VX_AML.AML_TXN_DAILY
AS
SELECT
       txn.TXN_REF,
       txn.SUPPLIER_CD,
       txn.BOOKING_DT,
       txn.VALUE_DT,
       txn.TXN_TMS,
       txn.ACCT_ID,
       txn.SORT_CD,
       txn.ACCT_NR,
       txn.PARTY_ID,
       txn.PRDT_CD,
       txn.SEGMENT_CD,
       txn.TXN_TYP_CD,
       txn.PAY_SCHEME_CD,
       txn.CHNL_CD,
       txn.DR_CR_IND,
       txn.TXN_AMT,
       txn.TXN_CCY_CD,
       txn.ORIG_AMT,
       txn.ORIG_CCY_CD,
       txn.GBP_AMT,
       txn.GBP_RATE,
       txn.CASH_IND,
       txn.XBORDER_IND,
       txn.ROUND_AMT_IND,
       txn.NARRATIVE_TXT,
       txn.CPTY_ID,
       CASE WHEN acc.PII_ACCESS_IND = 'Y' THEN txn.CPTY_NM ELSE CAST ('*** MASKED ***' AS VARCHAR(140)) END
                                                   AS CPTY_NM,
       txn.CPTY_SORT_CD,
       txn.CPTY_ACCT_NR,
       CASE WHEN acc.PII_ACCESS_IND = 'Y' OR txn.CPTY_IBAN IS NULL THEN txn.CPTY_IBAN
            ELSE SUBSTR (txn.CPTY_IBAN, 1, 4) || '**************' || SUBSTR (TRIM (txn.CPTY_IBAN), CHARACTER_LENGTH (TRIM (txn.CPTY_IBAN)) - 3, 4) END
                                                   AS CPTY_IBAN,
       txn.CPTY_BIC_CD,
       txn.CPTY_BANK_CTRY_CD,
       txn.CPTY_CTRY_CD,
       txn.CPTY_CTRY_RISK_CD,
       txn.CPTY_INTERNAL_IND,
       txn.CPTY_PARTY_ID,
       CASE WHEN acc.PII_ACCESS_IND = 'Y' THEN txn.ORDERING_CUST_NM ELSE CAST ('*** MASKED ***' AS VARCHAR(140)) END
                                                   AS ORDERING_CUST_NM,
       CASE WHEN acc.PII_ACCESS_IND = 'Y' THEN txn.BENEF_CUST_NM ELSE CAST ('*** MASKED ***' AS VARCHAR(140)) END
                                                   AS BENEF_CUST_NM,
       txn.PAYMENT_REF,
       txn.E2E_ID,
       txn.UETR,
       txn.SWIFT_MSG_TYP_CD,
       txn.INTERMED_BIC_CD,
       txn.MCC_CD,
       txn.MCC_RISK_CD,
       txn.MERCHANT_NM,
       txn.MERCHANT_CTRY_CD,
       CASE WHEN acc.PII_ACCESS_IND = 'Y' OR txn.CARD_TOKEN IS NULL THEN txn.CARD_TOKEN
            ELSE RPAD ('************' || SUBSTR (TRIM (txn.CARD_TOKEN), CHARACTER_LENGTH (TRIM (txn.CARD_TOKEN)) - 3, 4), 19, ' ') END
                                                   AS CARD_TOKEN,
       txn.CARD_PRESENT_IND,
       txn.ATM_ID,
       txn.BRANCH_SORT_CD,
       txn.CHEQUE_NR,
       txn.DEVICE_ID,
       txn.IP_CTRY_CD,
       txn.AUTH_METHOD_CD,
       txn.COP_RESULT_CD,
       txn.APP_FRAUD_IND,
       txn.RETURN_REASON_CD,
       txn.REVERSAL_IND,
       txn.ORIG_TXN_REF,
       txn.BAL_AFTER_AMT,
       txn.TXN_STATUS_CD,
       txn.FEE_AMT,
       txn.PURPOSE_CD,
       txn.PARTY_RISK_RATING_CD,
       txn.PARTY_PEP_IND,
       txn.HRC_IND,
       txn.SANC_HIT_IND,
       txn.DQ_ERR_IND,
       txn.BATCH_ID,
       txn.FILE_SEQ_NR,
       txn.LOAD_TMS,
       txn.CO_UPD_TMS
FROM
       DB_ODS.AML_TXN_DAILY            txn

       INNER JOIN
       DB_REFERENCE.VIEW_ACCESS_CTRL   acc
          ON  acc.SEGMENT_CD = txn.SEGMENT_CD
          AND acc.USER_NM    = current_user();
