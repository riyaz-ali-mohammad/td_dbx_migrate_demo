.set WIDTH       300;
.set TITLEDASHES OFF;

/**************************************************************************\
* PREPARATION                                                              *
* ------------------------------------------------------------------------ *
* Collect statistics on all reference snapshots used by the checks         *
\**************************************************************************/

COLLECT STATISTICS <DB_ENV>DB_ODS.ACCT_SNAPSHOT        INDEX (ACCT_ID);
COLLECT STATISTICS <DB_ENV>DB_ODS.CTRY_SNAPSHOT        INDEX (CTRY_2_CD);
COLLECT STATISTICS <DB_ENV>DB_ODS.CCY_SNAPSHOT         INDEX (CCY_CD);
COLLECT STATISTICS <DB_ENV>DB_ODS.SORT_CD_SNAPSHOT     INDEX (SORT_CD);
COLLECT STATISTICS <DB_ENV>DB_ODS.TXN_TYP_SNAPSHOT     INDEX (TXN_TYP_CD);
COLLECT STATISTICS <DB_ENV>DB_ODS.MCC_SNAPSHOT         INDEX (MCC_CD);
COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD   INDEX (TXN_REF, SUPPLIER_CD);
COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD   COLUMN (ACCT_ID);
COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD   COLUMN (CPTY_CTRY);
COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD   COLUMN (CPTY_BANK_CTRY);
COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD   COLUMN (SORT_CD);
COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD   COLUMN (TXN_TYP_CD);
COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_GBP    COLUMN (RATE_FALLBACK_IND);


/**************************************************************************\
* COLLECT UNKNOWN ACCOUNTS                                                 *
* ------------------------------------------------------------------------ *
* Accounts which are not known in the KYC account master, or which only    *
* exist as placeholder in the account snapshot (added by dailytxn.06).     *
\**************************************************************************/

DELETE FROM <DB_ENV>DB_STREAM_DATA.INFO_DLYTXN_ERROR_ACCT
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_STREAM_DATA.INFO_DLYTXN_ERROR_ACCT
(
       ACCT_ID,
       SORT_CD,
       ACCT_NR,
       TXN_CNT,
       CO_UPD_TMS
)
SELECT dtl.ACCT_ID,
       MAX (dtl.SORT_CD),
       MAX (dtl.ACCT_NR),
       COUNT (*),
       MAX (tms.LOAD_TMS)
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD       dtl

       CROSS JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS   tms

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.ACCT_SNAPSHOT               snp
          ON  snp.ACCT_ID = dtl.ACCT_ID
WHERE
       snp.ACCT_ID IS NULL
OR     snp.PLACEHOLDER_IND = 'Y'
GROUP  BY dtl.ACCT_ID
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* COLLECT UNKNOWN COUNTRIES                                                *
\**************************************************************************/

DELETE FROM <DB_ENV>DB_STREAM_DATA.INFO_DLYTXN_ERROR_CTRY
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_STREAM_DATA.INFO_DLYTXN_ERROR_CTRY
(
       CTRY_CD,
       ERR_FIELD,
       CO_UPD_TMS
)
SELECT dtl.CPTY_CTRY,
       'CPTY_CTRY',
       tms.LOAD_TMS
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD       dtl

       CROSS JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS   tms

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.CTRY_SNAPSHOT               snp
          ON  snp.CTRY_2_CD = dtl.CPTY_CTRY
WHERE
       snp.CTRY_2_CD IS NULL
AND    dtl.CPTY_CTRY <> ' '

UNION

SELECT dtl.CPTY_BANK_CTRY,
       'CPTY_BANK_CTRY',
       tms.LOAD_TMS
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD       dtl

       CROSS JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS   tms

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.CTRY_SNAPSHOT               snp
          ON  snp.CTRY_2_CD = dtl.CPTY_BANK_CTRY
WHERE
       snp.CTRY_2_CD IS NULL
AND    dtl.CPTY_BANK_CTRY <> ' '

UNION

SELECT dtl.MERCHANT_CTRY,
       'MERCHANT_CTRY',
       tms.LOAD_TMS
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD       dtl

       CROSS JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS   tms

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.CTRY_SNAPSHOT               snp
          ON  snp.CTRY_2_CD = dtl.MERCHANT_CTRY
WHERE
       snp.CTRY_2_CD IS NULL
AND    dtl.MERCHANT_CTRY <> ' '

UNION

SELECT dtl.IP_CTRY,
       'IP_CTRY',
       tms.LOAD_TMS
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD       dtl

       CROSS JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS   tms

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.CTRY_SNAPSHOT               snp
          ON  snp.CTRY_2_CD = dtl.IP_CTRY
WHERE
       snp.CTRY_2_CD IS NULL
AND    dtl.IP_CTRY <> ' '
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* COLLECT UNKNOWN CURRENCIES                                               *
\**************************************************************************/

DELETE FROM <DB_ENV>DB_STREAM_DATA.INFO_DLYTXN_ERROR_CCY
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_STREAM_DATA.INFO_DLYTXN_ERROR_CCY
(
       CCY_CD,
       CO_UPD_TMS
)
SELECT dtl.TXN_CCY,
       tms.LOAD_TMS
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD       dtl

       CROSS JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS   tms

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.CCY_SNAPSHOT                snp
          ON  snp.CCY_CD = dtl.TXN_CCY
WHERE
       snp.CCY_CD IS NULL
AND    dtl.TXN_CCY <> ' '

UNION

SELECT dtl.ORIG_CCY,
       tms.LOAD_TMS
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD       dtl

       CROSS JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS   tms

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.CCY_SNAPSHOT                snp
          ON  snp.CCY_CD = dtl.ORIG_CCY
WHERE
       snp.CCY_CD IS NULL
AND    dtl.ORIG_CCY <> ' '
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* COLLECT UNKNOWN AND CLOSED SORT CODES                                    *
* ------------------------------------------------------------------------ *
* Closed sort codes are reported with the suffix (CLOSED) in ERR_FIELD.    *
\**************************************************************************/

DELETE FROM <DB_ENV>DB_STREAM_DATA.INFO_DLYTXN_ERROR_SORTCD
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_STREAM_DATA.INFO_DLYTXN_ERROR_SORTCD
(
       SORT_CD,
       ERR_FIELD,
       CO_UPD_TMS
)
SELECT dtl.SORT_CD,
       CASE WHEN snp.SORT_CD IS NULL THEN 'SORT_CD'
            ELSE 'SORT_CD (CLOSED)' END,
       tms.LOAD_TMS
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD       dtl

       CROSS JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS   tms

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.SORT_CD_SNAPSHOT            snp
          ON  snp.SORT_CD = dtl.SORT_CD
WHERE
       (snp.SORT_CD IS NULL OR snp.CLOSED_IND = 'Y')
AND    dtl.SORT_CD <> ' '

UNION

SELECT dtl.CPTY_SORT_CD,
       CASE WHEN snp.SORT_CD IS NULL THEN 'CPTY_SORT_CD'
            ELSE 'CPTY_SORT_CD (CLOSED)' END,
       tms.LOAD_TMS
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD       dtl

       CROSS JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS   tms

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.SORT_CD_SNAPSHOT            snp
          ON  snp.SORT_CD = dtl.CPTY_SORT_CD
WHERE
       (snp.SORT_CD IS NULL OR snp.CLOSED_IND = 'Y')
AND    dtl.CPTY_SORT_CD <> ' '

UNION

SELECT dtl.BRANCH_SORT_CD,
       CASE WHEN snp.SORT_CD IS NULL THEN 'BRANCH_SORT_CD'
            ELSE 'BRANCH_SORT_CD (CLOSED)' END,
       tms.LOAD_TMS
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD       dtl

       CROSS JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS   tms

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.SORT_CD_SNAPSHOT            snp
          ON  snp.SORT_CD = dtl.BRANCH_SORT_CD
WHERE
       (snp.SORT_CD IS NULL OR snp.CLOSED_IND = 'Y')
AND    dtl.BRANCH_SORT_CD <> ' '
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* COLLECT UNKNOWN TRANSACTION TYPES                                        *
\**************************************************************************/

DELETE FROM <DB_ENV>DB_STREAM_DATA.INFO_DLYTXN_ERROR_TXNTYP
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_STREAM_DATA.INFO_DLYTXN_ERROR_TXNTYP
(
       TXN_TYP_CD,
       CO_UPD_TMS
)
SELECT dtl.TXN_TYP_CD,
       MAX (tms.LOAD_TMS)
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD       dtl

       CROSS JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS   tms

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.TXN_TYP_SNAPSHOT            snp
          ON  snp.TXN_TYP_CD = dtl.TXN_TYP_CD
WHERE
       snp.TXN_TYP_CD IS NULL
AND    dtl.TXN_TYP_CD <> ' '
GROUP  BY dtl.TXN_TYP_CD
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* COLLECT UNKNOWN MERCHANT CATEGORY CODES                                  *
\**************************************************************************/

DELETE FROM <DB_ENV>DB_STREAM_DATA.INFO_DLYTXN_ERROR_MCC
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_STREAM_DATA.INFO_DLYTXN_ERROR_MCC
(
       MCC_CD,
       CO_UPD_TMS
)
SELECT dtl.MCC,
       MAX (tms.LOAD_TMS)
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD       dtl

       CROSS JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS   tms

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.MCC_SNAPSHOT            snp
          ON  snp.MCC_CD = dtl.MCC
WHERE
       snp.MCC_CD IS NULL
AND    dtl.MCC <> ' '
GROUP  BY dtl.MCC
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* COLLECT MISSING FX RATES                                                 *
\**************************************************************************/

DELETE FROM <DB_ENV>DB_STREAM_DATA.INFO_DLYTXN_ERROR_FXRATE
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_STREAM_DATA.INFO_DLYTXN_ERROR_FXRATE
(
       CCY_CD,
       BOOKING_DT,
       TXN_CNT,
       CO_UPD_TMS
)
SELECT gbp.TXN_CCY,
       dtl.BOOKING_DT,
       COUNT (*),
       MAX (tms.LOAD_TMS)
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_GBP        gbp

       INNER JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD       dtl
          ON  dtl.TXN_REF     = gbp.TXN_REF
          AND dtl.SUPPLIER_CD = gbp.SUPPLIER_CD

       CROSS JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS   tms
WHERE
       gbp.RATE_FALLBACK_IND = 'X'
GROUP  BY gbp.TXN_CCY,
          dtl.BOOKING_DT
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* CONSOLIDATE ALL FINDINGS PER TRANSACTION                                 *
* ------------------------------------------------------------------------ *
* All findings are first gathered in a volatile table and then written to  *
* the error log in one go, so that a single error id range is drawn.       *
* ERR_KEY = transaction reference | supplier code.                         *
*                                                                          *
* ERR_NR  CLASS    DESCRIPTION                                             *
*   101   ERROR    account unknown in KYC                                  *
*   102   WARNING  account only known as placeholder                       *
*   201   WARNING  country code unknown                                    *
*   301   ERROR    transaction currency unknown                            *
*   401   WARNING  sort code unknown                                       *
*   402   WARNING  sort code closed                                        *
*   501   WARNING  transaction type unknown                                *
*   601   WARNING  merchant category code unknown                          *
*   701   ERROR    no FX rate available                                    *
*   801   WARNING  zero transaction amount                                 *
*   802   ERROR    invalid debit / credit indicator                        *
*   803   WARNING  booking date in the future                              *
*   804   WARNING  value date more than 30 days before booking date        *
\**************************************************************************/

CREATE VOLATILE TABLE VT_DLYTXN_ERR
(
       ERR_NR          SMALLINT       NOT NULL,
       ERR_CLASS       VARCHAR(20)    NOT NULL,
       ERR_KEY         VARCHAR(80)    NOT NULL,
       ERR_FIELD       VARCHAR(30),
       ERR_TABLE       VARCHAR(30),
       ERR_DESC        VARCHAR(200)
)
PRIMARY INDEX ( ERR_KEY )
ON COMMIT PRESERVE ROWS
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO VT_DLYTXN_ERR
SELECT CASE WHEN snp.ACCT_ID IS NULL THEN 101 ELSE 102 END,
       CASE WHEN snp.ACCT_ID IS NULL THEN 'ERROR' ELSE 'WARNING' END,
       TRIM (dtl.TXN_REF) || '|' || dtl.SUPPLIER_CD,
       'ACCT_ID',
       'ACCT_SNAPSHOT',
       CASE WHEN snp.ACCT_ID IS NULL
            THEN 'Account ' || dtl.ACCT_ID || ' unknown'
            ELSE 'Account ' || dtl.ACCT_ID || ' only known as placeholder'
       END
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD    dtl

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.ACCT_SNAPSHOT            snp
          ON  snp.ACCT_ID = dtl.ACCT_ID
WHERE
       snp.ACCT_ID IS NULL
OR     snp.PLACEHOLDER_IND = 'Y'
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO VT_DLYTXN_ERR
SELECT 201,
       'WARNING',
       TRIM (dtl.TXN_REF) || '|' || dtl.SUPPLIER_CD,
       'CPTY_CTRY',
       'CTRY_SNAPSHOT',
       'Country code ' || dtl.CPTY_CTRY || ' unknown'
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD    dtl

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.CTRY_SNAPSHOT            snp
          ON  snp.CTRY_2_CD = dtl.CPTY_CTRY
WHERE
       snp.CTRY_2_CD IS NULL
AND    dtl.CPTY_CTRY <> ' '
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO VT_DLYTXN_ERR
SELECT 201,
       'WARNING',
       TRIM (dtl.TXN_REF) || '|' || dtl.SUPPLIER_CD,
       'CPTY_BANK_CTRY',
       'CTRY_SNAPSHOT',
       'Country code ' || dtl.CPTY_BANK_CTRY || ' unknown'
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD    dtl

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.CTRY_SNAPSHOT            snp
          ON  snp.CTRY_2_CD = dtl.CPTY_BANK_CTRY
WHERE
       snp.CTRY_2_CD IS NULL
AND    dtl.CPTY_BANK_CTRY <> ' '
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO VT_DLYTXN_ERR
SELECT 201,
       'WARNING',
       TRIM (dtl.TXN_REF) || '|' || dtl.SUPPLIER_CD,
       'MERCHANT_CTRY',
       'CTRY_SNAPSHOT',
       'Country code ' || dtl.MERCHANT_CTRY || ' unknown'
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD    dtl

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.CTRY_SNAPSHOT            snp
          ON  snp.CTRY_2_CD = dtl.MERCHANT_CTRY
WHERE
       snp.CTRY_2_CD IS NULL
AND    dtl.MERCHANT_CTRY <> ' '
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO VT_DLYTXN_ERR
SELECT 201,
       'WARNING',
       TRIM (dtl.TXN_REF) || '|' || dtl.SUPPLIER_CD,
       'IP_CTRY',
       'CTRY_SNAPSHOT',
       'Country code ' || dtl.IP_CTRY || ' unknown'
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD    dtl

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.CTRY_SNAPSHOT            snp
          ON  snp.CTRY_2_CD = dtl.IP_CTRY
WHERE
       snp.CTRY_2_CD IS NULL
AND    dtl.IP_CTRY <> ' '
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO VT_DLYTXN_ERR
SELECT 301,
       'ERROR',
       TRIM (dtl.TXN_REF) || '|' || dtl.SUPPLIER_CD,
       'TXN_CCY',
       'CCY_SNAPSHOT',
       'Currency ' || dtl.TXN_CCY || ' unknown'
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD    dtl

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.CCY_SNAPSHOT             snp
          ON  snp.CCY_CD = dtl.TXN_CCY
WHERE
       snp.CCY_CD IS NULL
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO VT_DLYTXN_ERR
SELECT CASE WHEN snp.SORT_CD IS NULL THEN 401 ELSE 402 END,
       'WARNING',
       TRIM (dtl.TXN_REF) || '|' || dtl.SUPPLIER_CD,
       'SORT_CD',
       'SORT_CD_SNAPSHOT',
       'Sort code ' || dtl.SORT_CD ||
       CASE WHEN snp.SORT_CD IS NULL THEN ' unknown' ELSE ' closed' END
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD    dtl

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.SORT_CD_SNAPSHOT         snp
          ON  snp.SORT_CD = dtl.SORT_CD
WHERE
       (snp.SORT_CD IS NULL OR snp.CLOSED_IND = 'Y')
AND    dtl.SORT_CD <> ' '
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO VT_DLYTXN_ERR
SELECT CASE WHEN snp.SORT_CD IS NULL THEN 401 ELSE 402 END,
       'WARNING',
       TRIM (dtl.TXN_REF) || '|' || dtl.SUPPLIER_CD,
       'CPTY_SORT_CD',
       'SORT_CD_SNAPSHOT',
       'Sort code ' || dtl.CPTY_SORT_CD ||
       CASE WHEN snp.SORT_CD IS NULL THEN ' unknown' ELSE ' closed' END
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD    dtl

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.SORT_CD_SNAPSHOT         snp
          ON  snp.SORT_CD = dtl.CPTY_SORT_CD
WHERE
       (snp.SORT_CD IS NULL OR snp.CLOSED_IND = 'Y')
AND    dtl.CPTY_SORT_CD <> ' '
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO VT_DLYTXN_ERR
SELECT CASE WHEN snp.SORT_CD IS NULL THEN 401 ELSE 402 END,
       'WARNING',
       TRIM (dtl.TXN_REF) || '|' || dtl.SUPPLIER_CD,
       'BRANCH_SORT_CD',
       'SORT_CD_SNAPSHOT',
       'Sort code ' || dtl.BRANCH_SORT_CD ||
       CASE WHEN snp.SORT_CD IS NULL THEN ' unknown' ELSE ' closed' END
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD    dtl

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.SORT_CD_SNAPSHOT         snp
          ON  snp.SORT_CD = dtl.BRANCH_SORT_CD
WHERE
       (snp.SORT_CD IS NULL OR snp.CLOSED_IND = 'Y')
AND    dtl.BRANCH_SORT_CD <> ' '
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO VT_DLYTXN_ERR
SELECT 501,
       'WARNING',
       TRIM (dtl.TXN_REF) || '|' || dtl.SUPPLIER_CD,
       'TXN_TYP_CD',
       'TXN_TYP_SNAPSHOT',
       'Transaction type ' || dtl.TXN_TYP_CD || ' unknown'
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD    dtl

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.TXN_TYP_SNAPSHOT         snp
          ON  snp.TXN_TYP_CD = dtl.TXN_TYP_CD
WHERE
       snp.TXN_TYP_CD IS NULL
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO VT_DLYTXN_ERR
SELECT 601,
       'WARNING',
       TRIM (dtl.TXN_REF) || '|' || dtl.SUPPLIER_CD,
       'MCC',
       'MCC_SNAPSHOT',
       'Merchant category code ' || dtl.MCC || ' unknown'
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD    dtl

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.MCC_SNAPSHOT             snp
          ON  snp.MCC_CD = dtl.MCC
WHERE
       snp.MCC_CD IS NULL
AND    dtl.MCC <> ' '
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO VT_DLYTXN_ERR
SELECT 701,
       'ERROR',
       TRIM (gbp.TXN_REF) || '|' || gbp.SUPPLIER_CD,
       'TXN_CCY',
       'FX_RATE',
       'No GBP rate for ' || gbp.TXN_CCY || ' within 10 days of booking date'
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_GBP     gbp
WHERE
       gbp.RATE_FALLBACK_IND = 'X'
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO VT_DLYTXN_ERR
SELECT CASE
          WHEN dtl.DR_CR_IND NOT IN ('D', 'C')                 THEN 802
          WHEN dtl.TXN_AMT = 0                                 THEN 801
          WHEN dtl.BOOKING_DT > tms.BUSINESS_DT                THEN 803
          ELSE 804
       END,
       CASE WHEN dtl.DR_CR_IND NOT IN ('D', 'C') THEN 'ERROR' ELSE 'WARNING' END,
       TRIM (dtl.TXN_REF) || '|' || dtl.SUPPLIER_CD,
       CASE
          WHEN dtl.DR_CR_IND NOT IN ('D', 'C')                 THEN 'DR_CR_IND'
          WHEN dtl.TXN_AMT = 0                                 THEN 'TXN_AMT'
          WHEN dtl.BOOKING_DT > tms.BUSINESS_DT                THEN 'BOOKING_DT'
          ELSE 'VALUE_DT'
       END,
       'DLYTXN_LOAD',
       CASE
          WHEN dtl.DR_CR_IND NOT IN ('D', 'C')                 THEN 'Invalid debit/credit indicator ' || dtl.DR_CR_IND
          WHEN dtl.TXN_AMT = 0                                 THEN 'Zero transaction amount'
          WHEN dtl.BOOKING_DT > tms.BUSINESS_DT                THEN 'Booking date in the future'
          ELSE 'Value date more than 30 days before booking date'
       END
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD       dtl

       CROSS JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS   tms
WHERE
       dtl.DR_CR_IND NOT IN ('D', 'C')
OR     dtl.TXN_AMT = 0
OR     dtl.BOOKING_DT > tms.BUSINESS_DT
OR     dtl.VALUE_DT   < dtl.BOOKING_DT - 30
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* WRITE THE ERROR LOG                                                      *
* ------------------------------------------------------------------------ *
* Re-runs for the same business date replace the previous findings of      *
* this program. New error ids continue the existing number range.          *
\**************************************************************************/

DELETE FROM <DB_ENV>DB_STREAM_DATA.INFO_DLYTXN_ERROR_LOG
WHERE  ERR_PGM_SOURCE = 'dailytxn.07.CHECK_VALUES'
AND    BUSINESS_DT    = (SELECT BUSINESS_DT
                         FROM   <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS
                         WHERE  SSQ_ID = 1)
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_STREAM_DATA.INFO_DLYTXN_ERROR_LOG
(
       ERR_AID,
       ERR_NR,
       ERR_CLASS,
       ERR_KEY,
       ERR_FIELD,
       ERR_TABLE,
       ERR_TMS,
       ERR_PGM_SOURCE,
       ERR_DESC,
       BUSINESS_DT
)
SELECT mx.MAX_ERR_AID + CSUM (1, err.ERR_KEY, err.ERR_NR, err.ERR_FIELD),
       err.ERR_NR,
       err.ERR_CLASS,
       err.ERR_KEY,
       err.ERR_FIELD,
       err.ERR_TABLE,
       tms.LOAD_TMS,
       'dailytxn.07.CHECK_VALUES',
       err.ERR_DESC,
       tms.BUSINESS_DT
FROM
       VT_DLYTXN_ERR                              err

       CROSS JOIN
       (SELECT ZEROIFNULL (MAX (ERR_AID)) AS MAX_ERR_AID
        FROM   <DB_ENV>DB_STREAM_DATA.INFO_DLYTXN_ERROR_LOG
       )                                          mx

       CROSS JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS   tms
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_STREAM_DATA.INFO_DLYTXN_ERROR_LOG COLUMN (ERR_KEY);
COLLECT STATISTICS <DB_ENV>DB_STREAM_DATA.INFO_DLYTXN_ERROR_LOG COLUMN (BUSINESS_DT);


/**************************************************************************\
* DQ GATE                                                                  *
* ------------------------------------------------------------------------ *
* Summary of the findings for the batch log. When more than 5 percent of   *
* the transactions carry an ERROR finding, the stream is stopped before    *
* the fact table is touched (return code 8, operator action required).     *
\**************************************************************************/

SELECT ERR_NR,
       ERR_CLASS,
       ERR_FIELD,
       COUNT (*)  AS ERR_CNT
FROM   VT_DLYTXN_ERR
GROUP  BY 1, 2, 3
ORDER  BY 1, 3
;
.if errorcode <> 0 then .quit errorcode;

SELECT err.ERR_TXN_CNT,
       tot.TXN_CNT
FROM
       (SELECT COUNT (DISTINCT ERR_KEY) AS ERR_TXN_CNT
        FROM   VT_DLYTXN_ERR
        WHERE  ERR_CLASS = 'ERROR'
       )                                      err

       CROSS JOIN
       (SELECT COUNT (*) AS TXN_CNT
        FROM   <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD
       )                                      tot
WHERE
       err.ERR_TXN_CNT > tot.TXN_CNT * 0.05
;
.if errorcode <> 0 then .quit errorcode;
.if activitycount > 0 then .quit 8;

DROP TABLE VT_DLYTXN_ERR
;
.if errorcode <> 0 then .quit errorcode;

.quit 0;

