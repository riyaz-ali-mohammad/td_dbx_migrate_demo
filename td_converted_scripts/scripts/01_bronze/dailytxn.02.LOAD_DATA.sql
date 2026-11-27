/**************************************************************************\
* DATABRICKS SQL DAILY TRANSACTION LOAD                                    *
* ------------------------------------------------------------------------ *
* The target tables must already exist in the current catalog and schema.  *
* The source database qualifier was removed because no Unity Catalog       *
* mapping was supplied.                                                    *
\**************************************************************************/

-- TODO: manual review required — MultiLoad → COPY INTO staging + INSERT (confirm source path and rejected/duplicate-row reconciliation)
-- TODO: manual review required — BTEQ .IF / .LOGOFF error propagation → SIGNAL or Workflows task failure handling
-- Databricks replaces the MultiLoad log/work/error tables and record layouts with a raw text staging table.
CREATE OR REPLACE TEMP TABLE dlytxn_file_stage
(
    raw_line STRING
);

-- Databricks replaces the MultiLoad file import with COPY INTO.
COPY INTO dlytxn_file_stage
FROM '../data/dailytxn.dat'
FILEFORMAT = TEXT;

/**************************************************************************\
* CLEAR THE PRIMARY TARGET TABLES PRIOR TO LOADING                         *
\**************************************************************************/

-- Databricks uses the current catalog and schema because no target namespace mapping was supplied.
DELETE FROM DLYTXN_DATA_RAW;

-- Databricks uses the current catalog and schema because no target namespace mapping was supplied.
DELETE FROM DLYTXN_CTRL_RAW;

/**************************************************************************\
* LOAD DETAIL RECORDS (RECTYPE = 'D')                                      *
* ------------------------------------------------------------------------ *
* DISTINCT preserves MultiLoad's duplicate-insert rejection for the       *
* emptied target, but no separate UNQ reject table is populated.           *
\**************************************************************************/

-- Databricks parses the fixed-width MultiLoad layout with SUBSTRING expressions.
INSERT INTO DLYTXN_DATA_RAW
(
    RECTYPE,
    SUPPLIER_CD,
    FILE_SEQ_NR,
    TXN_REF,
    TXN_SEQ_NR,
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
    EXTRACT_DT
)
SELECT DISTINCT
    SUBSTRING(raw_line, 1, 1),
    SUBSTRING(raw_line, 2, 4),
    SUBSTRING(raw_line, 6, 9),
    SUBSTRING(raw_line, 15, 35),
    SUBSTRING(raw_line, 50, 4),
    SUBSTRING(raw_line, 54, 6),
    SUBSTRING(raw_line, 60, 8),
    SUBSTRING(raw_line, 68, 4),
    SUBSTRING(raw_line, 72, 3),
    SUBSTRING(raw_line, 75, 1),
    SUBSTRING(raw_line, 76, 16),
    SUBSTRING(raw_line, 92, 3),
    SUBSTRING(raw_line, 95, 16),
    SUBSTRING(raw_line, 111, 3),
    SUBSTRING(raw_line, 114, 8),
    SUBSTRING(raw_line, 122, 8),
    SUBSTRING(raw_line, 130, 14),
    SUBSTRING(raw_line, 144, 140),
    SUBSTRING(raw_line, 284, 140),
    SUBSTRING(raw_line, 424, 6),
    SUBSTRING(raw_line, 430, 8),
    SUBSTRING(raw_line, 438, 34),
    SUBSTRING(raw_line, 472, 11),
    SUBSTRING(raw_line, 483, 2),
    SUBSTRING(raw_line, 485, 2),
    SUBSTRING(raw_line, 487, 140),
    SUBSTRING(raw_line, 627, 140),
    SUBSTRING(raw_line, 767, 35),
    SUBSTRING(raw_line, 802, 35),
    SUBSTRING(raw_line, 837, 36),
    SUBSTRING(raw_line, 873, 3),
    SUBSTRING(raw_line, 876, 3),
    SUBSTRING(raw_line, 879, 11),
    SUBSTRING(raw_line, 890, 4),
    SUBSTRING(raw_line, 894, 40),
    SUBSTRING(raw_line, 934, 2),
    SUBSTRING(raw_line, 936, 15),
    SUBSTRING(raw_line, 951, 8),
    SUBSTRING(raw_line, 959, 8),
    SUBSTRING(raw_line, 967, 19),
    SUBSTRING(raw_line, 986, 2),
    SUBSTRING(raw_line, 988, 1),
    SUBSTRING(raw_line, 989, 6),
    SUBSTRING(raw_line, 995, 8),
    SUBSTRING(raw_line, 1003, 1),
    SUBSTRING(raw_line, 1004, 6),
    SUBSTRING(raw_line, 1010, 40),
    SUBSTRING(raw_line, 1050, 45),
    SUBSTRING(raw_line, 1095, 2),
    SUBSTRING(raw_line, 1097, 36),
    SUBSTRING(raw_line, 1133, 2),
    SUBSTRING(raw_line, 1135, 2),
    SUBSTRING(raw_line, 1137, 1),
    SUBSTRING(raw_line, 1138, 4),
    SUBSTRING(raw_line, 1142, 1),
    SUBSTRING(raw_line, 1143, 35),
    SUBSTRING(raw_line, 1178, 16),
    SUBSTRING(raw_line, 1194, 2),
    SUBSTRING(raw_line, 1196, 16),
    SUBSTRING(raw_line, 1212, 4),
    SUBSTRING(raw_line, 1216, 20),
    SUBSTRING(raw_line, 1236, 8)
FROM dlytxn_file_stage
WHERE SUBSTRING(raw_line, 1, 1) = 'D';

/**************************************************************************\
* LOAD HEADER AND TRAILER RECORDS (RECTYPE = 'H' / 'T')                   *
\**************************************************************************/

-- Databricks parses the fixed-width control layout and ignores duplicate records with DISTINCT.
INSERT INTO DLYTXN_CTRL_RAW
(
    RECTYPE,
    SUPPLIER_CD,
    FILE_ID,
    EXTRACT_DT,
    REC_CNT,
    DR_TOTAL,
    CR_TOTAL,
    CREATED_TMS
)
SELECT DISTINCT
    SUBSTRING(raw_line, 1, 1),
    SUBSTRING(raw_line, 2, 4),
    SUBSTRING(raw_line, 6, 20),
    SUBSTRING(raw_line, 26, 8),
    SUBSTRING(raw_line, 34, 10),
    SUBSTRING(raw_line, 44, 18),
    SUBSTRING(raw_line, 62, 18),
    SUBSTRING(raw_line, 80, 14)
FROM dlytxn_file_stage
WHERE SUBSTRING(raw_line, 1, 1) IN ('H', 'T');

-- Databricks removes the session-scoped staging table after the load.
DROP TABLE dlytxn_file_stage;
