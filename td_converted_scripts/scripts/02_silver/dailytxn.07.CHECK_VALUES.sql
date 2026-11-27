-- TODO: manual review required — choose the execution wrapper for this migrated BTEQ script: Databricks notebook, SQL stored procedure, or Workflows DAG.
-- TODO: manual review required — BTEQ ERRORCODE/QUIT behavior must be implemented by the selected wrapper; Databricks statement failures should abort the task or SIGNAL from a procedure.

/**************************************************************************\
* PREPARATION                                                              *
* ------------------------------------------------------------------------ *
* Collect statistics on all reference snapshots used by the checks         *
\**************************************************************************/

-- Databricks has no Teradata indexes, so INDEX statistics are omitted; refresh the explicitly requested column statistics instead.
ANALYZE TABLE IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD') COMPUTE STATISTICS FOR COLUMNS ACCT_ID;
ANALYZE TABLE IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD') COMPUTE STATISTICS FOR COLUMNS CPTY_CTRY;
ANALYZE TABLE IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD') COMPUTE STATISTICS FOR COLUMNS CPTY_BANK_CTRY;
ANALYZE TABLE IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD') COMPUTE STATISTICS FOR COLUMNS SORT_CD;
ANALYZE TABLE IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD') COMPUTE STATISTICS FOR COLUMNS TXN_TYP_CD;
ANALYZE TABLE IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_GBP') COMPUTE STATISTICS FOR COLUMNS RATE_FALLBACK_IND;


/**************************************************************************\
* COLLECT UNKNOWN ACCOUNTS                                                 *
* ------------------------------------------------------------------------ *
* Accounts which are not known in the KYC account master, or which only    *
* exist as placeholder in the account snapshot (added by dailytxn.06).     *
\**************************************************************************/

DELETE FROM IDENTIFIER(:DB_ENV || 'DB_STREAM_DATA.INFO_DLYTXN_ERROR_ACCT')
;

INSERT INTO IDENTIFIER(:DB_ENV || 'DB_STREAM_DATA.INFO_DLYTXN_ERROR_ACCT')
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
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD')       dtl

       CROSS JOIN
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS')   tms

       LEFT OUTER JOIN
       IDENTIFIER(:DB_ENV || 'DB_ODS.ACCT_SNAPSHOT')               snp
          ON  snp.ACCT_ID = dtl.ACCT_ID
WHERE
       snp.ACCT_ID IS NULL
OR     RTRIM(snp.PLACEHOLDER_IND) = 'Y'
GROUP  BY dtl.ACCT_ID
;


/**************************************************************************\
* COLLECT UNKNOWN COUNTRIES                                                *
\**************************************************************************/

DELETE FROM IDENTIFIER(:DB_ENV || 'DB_STREAM_DATA.INFO_DLYTXN_ERROR_CTRY')
;

INSERT INTO IDENTIFIER(:DB_ENV || 'DB_STREAM_DATA.INFO_DLYTXN_ERROR_CTRY')
(
       CTRY_CD,
       ERR_FIELD,
       CO_UPD_TMS
)
SELECT dtl.CPTY_CTRY,
       'CPTY_CTRY',
       tms.LOAD_TMS
FROM
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD')       dtl

       CROSS JOIN
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS')   tms

       LEFT OUTER JOIN
       IDENTIFIER(:DB_ENV || 'DB_ODS.CTRY_SNAPSHOT')               snp
          ON  RTRIM(snp.CTRY_2_CD) = RTRIM(dtl.CPTY_CTRY)
WHERE
       snp.CTRY_2_CD IS NULL
AND    RTRIM(dtl.CPTY_CTRY) <> ''

UNION

SELECT dtl.CPTY_BANK_CTRY,
       'CPTY_BANK_CTRY',
       tms.LOAD_TMS
FROM
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD')       dtl

       CROSS JOIN
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS')   tms

       LEFT OUTER JOIN
       IDENTIFIER(:DB_ENV || 'DB_ODS.CTRY_SNAPSHOT')               snp
          ON  RTRIM(snp.CTRY_2_CD) = RTRIM(dtl.CPTY_BANK_CTRY)
WHERE
       snp.CTRY_2_CD IS NULL
AND    RTRIM(dtl.CPTY_BANK_CTRY) <> ''

UNION

SELECT dtl.MERCHANT_CTRY,
       'MERCHANT_CTRY',
       tms.LOAD_TMS
FROM
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD')       dtl

       CROSS JOIN
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS')   tms

       LEFT OUTER JOIN
       IDENTIFIER(:DB_ENV || 'DB_ODS.CTRY_SNAPSHOT')               snp
          ON  RTRIM(snp.CTRY_2_CD) = RTRIM(dtl.MERCHANT_CTRY)
WHERE
       snp.CTRY_2_CD IS NULL
AND    RTRIM(dtl.MERCHANT_CTRY) <> ''

UNION

SELECT dtl.IP_CTRY,
       'IP_CTRY',
       tms.LOAD_TMS
FROM
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD')       dtl

       CROSS JOIN
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS')   tms

       LEFT OUTER JOIN
       IDENTIFIER(:DB_ENV || 'DB_ODS.CTRY_SNAPSHOT')               snp
          ON  RTRIM(snp.CTRY_2_CD) = RTRIM(dtl.IP_CTRY)
WHERE
       snp.CTRY_2_CD IS NULL
AND    RTRIM(dtl.IP_CTRY) <> ''
;


/**************************************************************************\
* COLLECT UNKNOWN CURRENCIES                                               *
\**************************************************************************/

DELETE FROM IDENTIFIER(:DB_ENV || 'DB_STREAM_DATA.INFO_DLYTXN_ERROR_CCY')
;

INSERT INTO IDENTIFIER(:DB_ENV || 'DB_STREAM_DATA.INFO_DLYTXN_ERROR_CCY')
(
       CCY_CD,
       CO_UPD_TMS
)
SELECT dtl.TXN_CCY,
       tms.LOAD_TMS
FROM
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD')       dtl

       CROSS JOIN
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS')   tms

       LEFT OUTER JOIN
       IDENTIFIER(:DB_ENV || 'DB_ODS.CCY_SNAPSHOT')                snp
          ON  RTRIM(snp.CCY_CD) = RTRIM(dtl.TXN_CCY)
WHERE
       snp.CCY_CD IS NULL
AND    RTRIM(dtl.TXN_CCY) <> ''

UNION

SELECT dtl.ORIG_CCY,
       tms.LOAD_TMS
FROM
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD')       dtl

       CROSS JOIN
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS')   tms

       LEFT OUTER JOIN
       IDENTIFIER(:DB_ENV || 'DB_ODS.CCY_SNAPSHOT')                snp
          ON  RTRIM(snp.CCY_CD) = RTRIM(dtl.ORIG_CCY)
WHERE
       snp.CCY_CD IS NULL
AND    RTRIM(dtl.ORIG_CCY) <> ''
;


/**************************************************************************\
* COLLECT UNKNOWN AND CLOSED SORT CODES                                    *
* ------------------------------------------------------------------------ *
* Closed sort codes are reported with the suffix (CLOSED) in ERR_FIELD.    *
\**************************************************************************/

DELETE FROM IDENTIFIER(:DB_ENV || 'DB_STREAM_DATA.INFO_DLYTXN_ERROR_SORTCD')
;

INSERT INTO IDENTIFIER(:DB_ENV || 'DB_STREAM_DATA.INFO_DLYTXN_ERROR_SORTCD')
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
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD')       dtl

       CROSS JOIN
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS')   tms

       LEFT OUTER JOIN
       IDENTIFIER(:DB_ENV || 'DB_ODS.SORT_CD_SNAPSHOT')            snp
          ON  RTRIM(snp.SORT_CD) = RTRIM(dtl.SORT_CD)
WHERE
       (snp.SORT_CD IS NULL OR RTRIM(snp.CLOSED_IND) = 'Y')
AND    RTRIM(dtl.SORT_CD) <> ''

UNION

SELECT dtl.CPTY_SORT_CD,
       CASE WHEN snp.SORT_CD IS NULL THEN 'CPTY_SORT_CD'
            ELSE 'CPTY_SORT_CD (CLOSED)' END,
       tms.LOAD_TMS
FROM
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD')       dtl

       CROSS JOIN
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS')   tms

       LEFT OUTER JOIN
       IDENTIFIER(:DB_ENV || 'DB_ODS.SORT_CD_SNAPSHOT')            snp
          ON  RTRIM(snp.SORT_CD) = RTRIM(dtl.CPTY_SORT_CD)
WHERE
       (snp.SORT_CD IS NULL OR RTRIM(snp.CLOSED_IND) = 'Y')
AND    RTRIM(dtl.CPTY_SORT_CD) <> ''

UNION

SELECT dtl.BRANCH_SORT_CD,
       CASE WHEN snp.SORT_CD IS NULL THEN 'BRANCH_SORT_CD'
            ELSE 'BRANCH_SORT_CD (CLOSED)' END,
       tms.LOAD_TMS
FROM
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD')       dtl

       CROSS JOIN
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS')   tms

       LEFT OUTER JOIN
       IDENTIFIER(:DB_ENV || 'DB_ODS.SORT_CD_SNAPSHOT')            snp
          ON  RTRIM(snp.SORT_CD) = RTRIM(dtl.BRANCH_SORT_CD)
WHERE
       (snp.SORT_CD IS NULL OR RTRIM(snp.CLOSED_IND) = 'Y')
AND    RTRIM(dtl.BRANCH_SORT_CD) <> ''
;


/**************************************************************************\
* COLLECT UNKNOWN TRANSACTION TYPES                                        *
\**************************************************************************/

DELETE FROM IDENTIFIER(:DB_ENV || 'DB_STREAM_DATA.INFO_DLYTXN_ERROR_TXNTYP')
;

INSERT INTO IDENTIFIER(:DB_ENV || 'DB_STREAM_DATA.INFO_DLYTXN_ERROR_TXNTYP')
(
       TXN_TYP_CD,
       CO_UPD_TMS
)
SELECT dtl.TXN_TYP_CD,
       MAX (tms.LOAD_TMS)
FROM
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD')       dtl

       CROSS JOIN
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS')   tms

       LEFT OUTER JOIN
       IDENTIFIER(:DB_ENV || 'DB_ODS.TXN_TYP_SNAPSHOT')            snp
          ON  RTRIM(snp.TXN_TYP_CD) = RTRIM(dtl.TXN_TYP_CD)
WHERE
       snp.TXN_TYP_CD IS NULL
AND    RTRIM(dtl.TXN_TYP_CD) <> ''
GROUP  BY dtl.TXN_TYP_CD
;


/**************************************************************************\
* COLLECT UNKNOWN MERCHANT CATEGORY CODES                                  *
\**************************************************************************/

DELETE FROM IDENTIFIER(:DB_ENV || 'DB_STREAM_DATA.INFO_DLYTXN_ERROR_MCC')
;

INSERT INTO IDENTIFIER(:DB_ENV || 'DB_STREAM_DATA.INFO_DLYTXN_ERROR_MCC')
(
       MCC_CD,
       CO_UPD_TMS
)
SELECT dtl.MCC,
       MAX (tms.LOAD_TMS)
FROM
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD')       dtl

       CROSS JOIN
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS')   tms

       LEFT OUTER JOIN
       IDENTIFIER(:DB_ENV || 'DB_ODS.MCC_SNAPSHOT')            snp
          ON  RTRIM(snp.MCC_CD) = RTRIM(dtl.MCC)
WHERE
       snp.MCC_CD IS NULL
AND    RTRIM(dtl.MCC) <> ''
GROUP  BY dtl.MCC
;


/**************************************************************************\
* COLLECT MISSING FX RATES                                                 *
\**************************************************************************/

DELETE FROM IDENTIFIER(:DB_ENV || 'DB_STREAM_DATA.INFO_DLYTXN_ERROR_FXRATE')
;

INSERT INTO IDENTIFIER(:DB_ENV || 'DB_STREAM_DATA.INFO_DLYTXN_ERROR_FXRATE')
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
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_GBP')        gbp

       INNER JOIN
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD')       dtl
          ON  RTRIM(dtl.TXN_REF) = RTRIM(gbp.TXN_REF)
          AND RTRIM(dtl.SUPPLIER_CD) = RTRIM(gbp.SUPPLIER_CD)

       CROSS JOIN
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS')   tms
WHERE
       RTRIM(gbp.RATE_FALLBACK_IND) = 'X'
GROUP  BY gbp.TXN_CCY,
          dtl.BOOKING_DT
;


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

-- CREATE VOLATILE TABLE becomes a session-scoped TEMP TABLE; PRIMARY INDEX and ON COMMIT clauses have no Databricks equivalent.
CREATE TEMP TABLE VT_DLYTXN_ERR
(
       ERR_NR          SMALLINT       NOT NULL,
       ERR_CLASS       VARCHAR(20)    NOT NULL,
       ERR_KEY         VARCHAR(80)    NOT NULL,
       ERR_FIELD       VARCHAR(30),
       ERR_TABLE       VARCHAR(30),
       ERR_DESC        VARCHAR(200)
)
;

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
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD')    dtl

       LEFT OUTER JOIN
       IDENTIFIER(:DB_ENV || 'DB_ODS.ACCT_SNAPSHOT')            snp
          ON  snp.ACCT_ID = dtl.ACCT_ID
WHERE
       snp.ACCT_ID IS NULL
OR     RTRIM(snp.PLACEHOLDER_IND) = 'Y'
;

INSERT INTO VT_DLYTXN_ERR
SELECT 201,
       'WARNING',
       TRIM (dtl.TXN_REF) || '|' || dtl.SUPPLIER_CD,
       'CPTY_CTRY',
       'CTRY_SNAPSHOT',
       'Country code ' || dtl.CPTY_CTRY || ' unknown'
FROM
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD')    dtl

       LEFT OUTER JOIN
       IDENTIFIER(:DB_ENV || 'DB_ODS.CTRY_SNAPSHOT')            snp
          ON  RTRIM(snp.CTRY_2_CD) = RTRIM(dtl.CPTY_CTRY)
WHERE
       snp.CTRY_2_CD IS NULL
AND    RTRIM(dtl.CPTY_CTRY) <> ''
;

INSERT INTO VT_DLYTXN_ERR
SELECT 201,
       'WARNING',
       TRIM (dtl.TXN_REF) || '|' || dtl.SUPPLIER_CD,
       'CPTY_BANK_CTRY',
       'CTRY_SNAPSHOT',
       'Country code ' || dtl.CPTY_BANK_CTRY || ' unknown'
FROM
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD')    dtl

       LEFT OUTER JOIN
       IDENTIFIER(:DB_ENV || 'DB_ODS.CTRY_SNAPSHOT')            snp
          ON  RTRIM(snp.CTRY_2_CD) = RTRIM(dtl.CPTY_BANK_CTRY)
WHERE
       snp.CTRY_2_CD IS NULL
AND    RTRIM(dtl.CPTY_BANK_CTRY) <> ''
;

INSERT INTO VT_DLYTXN_ERR
SELECT 201,
       'WARNING',
       TRIM (dtl.TXN_REF) || '|' || dtl.SUPPLIER_CD,
       'MERCHANT_CTRY',
       'CTRY_SNAPSHOT',
       'Country code ' || dtl.MERCHANT_CTRY || ' unknown'
FROM
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD')    dtl

       LEFT OUTER JOIN
       IDENTIFIER(:DB_ENV || 'DB_ODS.CTRY_SNAPSHOT')            snp
          ON  RTRIM(snp.CTRY_2_CD) = RTRIM(dtl.MERCHANT_CTRY)
WHERE
       snp.CTRY_2_CD IS NULL
AND    RTRIM(dtl.MERCHANT_CTRY) <> ''
;

INSERT INTO VT_DLYTXN_ERR
SELECT 201,
       'WARNING',
       TRIM (dtl.TXN_REF) || '|' || dtl.SUPPLIER_CD,
       'IP_CTRY',
       'CTRY_SNAPSHOT',
       'Country code ' || dtl.IP_CTRY || ' unknown'
FROM
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD')    dtl

       LEFT OUTER JOIN
       IDENTIFIER(:DB_ENV || 'DB_ODS.CTRY_SNAPSHOT')            snp
          ON  RTRIM(snp.CTRY_2_CD) = RTRIM(dtl.IP_CTRY)
WHERE
       snp.CTRY_2_CD IS NULL
AND    RTRIM(dtl.IP_CTRY) <> ''
;

INSERT INTO VT_DLYTXN_ERR
SELECT 301,
       'ERROR',
       TRIM (dtl.TXN_REF) || '|' || dtl.SUPPLIER_CD,
       'TXN_CCY',
       'CCY_SNAPSHOT',
       'Currency ' || dtl.TXN_CCY || ' unknown'
FROM
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD')    dtl

       LEFT OUTER JOIN
       IDENTIFIER(:DB_ENV || 'DB_ODS.CCY_SNAPSHOT')             snp
          ON  RTRIM(snp.CCY_CD) = RTRIM(dtl.TXN_CCY)
WHERE
       snp.CCY_CD IS NULL
;

INSERT INTO VT_DLYTXN_ERR
SELECT CASE WHEN snp.SORT_CD IS NULL THEN 401 ELSE 402 END,
       'WARNING',
       TRIM (dtl.TXN_REF) || '|' || dtl.SUPPLIER_CD,
       'SORT_CD',
       'SORT_CD_SNAPSHOT',
       'Sort code ' || dtl.SORT_CD ||
       CASE WHEN snp.SORT_CD IS NULL THEN ' unknown' ELSE ' closed' END
FROM
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD')    dtl

       LEFT OUTER JOIN
       IDENTIFIER(:DB_ENV || 'DB_ODS.SORT_CD_SNAPSHOT')         snp
          ON  RTRIM(snp.SORT_CD) = RTRIM(dtl.SORT_CD)
WHERE
       (snp.SORT_CD IS NULL OR RTRIM(snp.CLOSED_IND) = 'Y')
AND    RTRIM(dtl.SORT_CD) <> ''
;

INSERT INTO VT_DLYTXN_ERR
SELECT CASE WHEN snp.SORT_CD IS NULL THEN 401 ELSE 402 END,
       'WARNING',
       TRIM (dtl.TXN_REF) || '|' || dtl.SUPPLIER_CD,
       'CPTY_SORT_CD',
       'SORT_CD_SNAPSHOT',
       'Sort code ' || dtl.CPTY_SORT_CD ||
       CASE WHEN snp.SORT_CD IS NULL THEN ' unknown' ELSE ' closed' END
FROM
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD')    dtl

       LEFT OUTER JOIN
       IDENTIFIER(:DB_ENV || 'DB_ODS.SORT_CD_SNAPSHOT')         snp
          ON  RTRIM(snp.SORT_CD) = RTRIM(dtl.CPTY_SORT_CD)
WHERE
       (snp.SORT_CD IS NULL OR RTRIM(snp.CLOSED_IND) = 'Y')
AND    RTRIM(dtl.CPTY_SORT_CD) <> ''
;

INSERT INTO VT_DLYTXN_ERR
SELECT CASE WHEN snp.SORT_CD IS NULL THEN 401 ELSE 402 END,
       'WARNING',
       TRIM (dtl.TXN_REF) || '|' || dtl.SUPPLIER_CD,
       'BRANCH_SORT_CD',
       'SORT_CD_SNAPSHOT',
       'Sort code ' || dtl.BRANCH_SORT_CD ||
       CASE WHEN snp.SORT_CD IS NULL THEN ' unknown' ELSE ' closed' END
FROM
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD')    dtl

       LEFT OUTER JOIN
       IDENTIFIER(:DB_ENV || 'DB_ODS.SORT_CD_SNAPSHOT')         snp
          ON  RTRIM(snp.SORT_CD) = RTRIM(dtl.BRANCH_SORT_CD)
WHERE
       (snp.SORT_CD IS NULL OR RTRIM(snp.CLOSED_IND) = 'Y')
AND    RTRIM(dtl.BRANCH_SORT_CD) <> ''
;

INSERT INTO VT_DLYTXN_ERR
SELECT 501,
       'WARNING',
       TRIM (dtl.TXN_REF) || '|' || dtl.SUPPLIER_CD,
       'TXN_TYP_CD',
       'TXN_TYP_SNAPSHOT',
       'Transaction type ' || dtl.TXN_TYP_CD || ' unknown'
FROM
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD')    dtl

       LEFT OUTER JOIN
       IDENTIFIER(:DB_ENV || 'DB_ODS.TXN_TYP_SNAPSHOT')         snp
          ON  RTRIM(snp.TXN_TYP_CD) = RTRIM(dtl.TXN_TYP_CD)
WHERE
       snp.TXN_TYP_CD IS NULL
;

INSERT INTO VT_DLYTXN_ERR
SELECT 601,
       'WARNING',
       TRIM (dtl.TXN_REF) || '|' || dtl.SUPPLIER_CD,
       'MCC',
       'MCC_SNAPSHOT',
       'Merchant category code ' || dtl.MCC || ' unknown'
FROM
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD')    dtl

       LEFT OUTER JOIN
       IDENTIFIER(:DB_ENV || 'DB_ODS.MCC_SNAPSHOT')             snp
          ON  RTRIM(snp.MCC_CD) = RTRIM(dtl.MCC)
WHERE
       snp.MCC_CD IS NULL
AND    RTRIM(dtl.MCC) <> ''
;

INSERT INTO VT_DLYTXN_ERR
SELECT 701,
       'ERROR',
       TRIM (gbp.TXN_REF) || '|' || gbp.SUPPLIER_CD,
       'TXN_CCY',
       'FX_RATE',
       'No GBP rate for ' || gbp.TXN_CCY || ' within 10 days of booking date'
FROM
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_GBP')     gbp
WHERE
       RTRIM(gbp.RATE_FALLBACK_IND) = 'X'
;

INSERT INTO VT_DLYTXN_ERR
SELECT CASE
          WHEN RTRIM(dtl.DR_CR_IND) NOT IN ('D', 'C')                 THEN 802
          WHEN dtl.TXN_AMT = 0                                 THEN 801
          WHEN dtl.BOOKING_DT > tms.BUSINESS_DT                THEN 803
          ELSE 804
       END,
       CASE WHEN RTRIM(dtl.DR_CR_IND) NOT IN ('D', 'C') THEN 'ERROR' ELSE 'WARNING' END,
       TRIM (dtl.TXN_REF) || '|' || dtl.SUPPLIER_CD,
       CASE
          WHEN RTRIM(dtl.DR_CR_IND) NOT IN ('D', 'C')                 THEN 'DR_CR_IND'
          WHEN dtl.TXN_AMT = 0                                 THEN 'TXN_AMT'
          WHEN dtl.BOOKING_DT > tms.BUSINESS_DT                THEN 'BOOKING_DT'
          ELSE 'VALUE_DT'
       END,
       'DLYTXN_LOAD',
       CASE
          WHEN RTRIM(dtl.DR_CR_IND) NOT IN ('D', 'C')                 THEN 'Invalid debit/credit indicator ' || dtl.DR_CR_IND
          WHEN dtl.TXN_AMT = 0                                 THEN 'Zero transaction amount'
          WHEN dtl.BOOKING_DT > tms.BUSINESS_DT                THEN 'Booking date in the future'
          ELSE 'Value date more than 30 days before booking date'
       END
FROM
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD')       dtl

       CROSS JOIN
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS')   tms
WHERE
       RTRIM(dtl.DR_CR_IND) NOT IN ('D', 'C')
OR     dtl.TXN_AMT = 0
OR     dtl.BOOKING_DT > tms.BUSINESS_DT
OR     dtl.VALUE_DT   < dtl.BOOKING_DT - 30
;


/**************************************************************************\
* WRITE THE ERROR LOG                                                      *
* ------------------------------------------------------------------------ *
* Re-runs for the same business date replace the previous findings of      *
* this program. New error ids continue the existing number range.          *
\**************************************************************************/

DELETE FROM IDENTIFIER(:DB_ENV || 'DB_STREAM_DATA.INFO_DLYTXN_ERROR_LOG')
WHERE  RTRIM(ERR_PGM_SOURCE) = 'dailytxn.07.CHECK_VALUES'
AND    BUSINESS_DT    = (SELECT BUSINESS_DT
                         FROM   IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS')
                         WHERE  SSQ_ID = 1)
;

INSERT INTO IDENTIFIER(:DB_ENV || 'DB_STREAM_DATA.INFO_DLYTXN_ERROR_LOG')
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
-- Teradata CSUM becomes an ANSI cumulative window aggregate.
SELECT mx.MAX_ERR_AID + SUM(1) OVER (
          ORDER BY err.ERR_KEY, err.ERR_NR, err.ERR_FIELD
          ROWS UNBOUNDED PRECEDING
       ),
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
       -- Teradata ZEROIFNULL becomes COALESCE.
       (SELECT COALESCE(MAX(ERR_AID), 0) AS MAX_ERR_AID
        FROM   IDENTIFIER(:DB_ENV || 'DB_STREAM_DATA.INFO_DLYTXN_ERROR_LOG')
       )                                          mx

       CROSS JOIN
       IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS')   tms
;

-- Teradata column statistics refresh becomes ANALYZE TABLE for Delta.
ANALYZE TABLE IDENTIFIER(:DB_ENV || 'DB_STREAM_DATA.INFO_DLYTXN_ERROR_LOG') COMPUTE STATISTICS FOR COLUMNS ERR_KEY;
ANALYZE TABLE IDENTIFIER(:DB_ENV || 'DB_STREAM_DATA.INFO_DLYTXN_ERROR_LOG') COMPUTE STATISTICS FOR COLUMNS BUSINESS_DT;


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

-- The BTEQ ACTIVITYCOUNT/QUIT gate becomes a Databricks assertion that fails the task when the five-percent threshold is exceeded.
SELECT ASSERT_TRUE(
          err.ERR_TXN_CNT <= tot.TXN_CNT * 0.05,
          'DQ gate failed: ERROR findings affect more than 5 percent of transactions'
       )
FROM
       (SELECT COUNT(DISTINCT ERR_KEY) AS ERR_TXN_CNT
        FROM   VT_DLYTXN_ERR
        WHERE  RTRIM(ERR_CLASS) = 'ERROR'
       )                                      err

       CROSS JOIN
       (SELECT COUNT(*) AS TXN_CNT
        FROM   IDENTIFIER(:DB_ENV || 'DB_TRANS_IMPORTS.DLYTXN_LOAD')
       )                                      tot
;

-- The converted volatile table must be dropped as a temporary table.
DROP TEMPORARY TABLE VT_DLYTXN_ERR
;


