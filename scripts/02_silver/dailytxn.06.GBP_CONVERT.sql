.set WIDTH       300;
.set TITLEDASHES OFF;

COLLECT STATISTICS <DB_ENV>DB_ODS.ACCT_SNAPSHOT     INDEX (ACCT_ID);
COLLECT STATISTICS <DB_ENV>DB_ODS.FX_RATE_SNAPSHOT  INDEX (CCY_CD);
COLLECT STATISTICS <DB_ENV>DB_ODS.FX_RATE           INDEX (CCY_CD, RATE_DT, RATE_TYP_CD);
COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD COLUMN (TXN_CCY, BOOKING_DT);


/**************************************************************************\
* ADD NEW ACCOUNTS TO THE ACCOUNT SNAPSHOT                                 *
* ------------------------------------------------------------------------ *
* Transactions may arrive for accounts which are not yet delivered by      *
* KYCSYS (same day account opening, migrated books). A placeholder entry   *
* is created so that the transaction can be loaded; it is replaced by the  *
* full record with the next KYCSYS load (kycref.55). The account is also   *
* reported in the DQ log (dailytxn.07).                                    *
\**************************************************************************/

INSERT INTO <DB_ENV>DB_ODS.ACCT_SNAPSHOT
(
       ACCT_ID,
       PRIMARY_PARTY_ID,
       PRDT_CD,
       SEGMENT_CD,
       ACCT_STATUS_CD,
       OPEN_DT,
       LAST_CUST_ACTV_DT,
       PLACEHOLDER_IND
)
SELECT dtl.ACCT_ID,
       NULL,
       NULL,
       'UNK',
       'U',
       MIN (dtl.BOOKING_DT),
       MAX (dtl.BOOKING_DT),
       'Y'
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD   dtl

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.ACCT_SNAPSHOT           snp
          ON  snp.ACCT_ID = dtl.ACCT_ID
WHERE
       snp.ACCT_ID IS NULL
AND    TRIM (dtl.ACCT_ID) <> ''
GROUP  BY dtl.ACCT_ID
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* DETERMINE FALLBACK FX RATES                                              *
* ------------------------------------------------------------------------ *
* The snapshot holds the latest published rate per currency. When the      *
* booking date differs from the snapshot rate date (back-dated postings,   *
* weekend / bank holiday bookings), the latest spot rate published on or   *
* before the booking date is used instead - looking back 10 days at most.  *
\**************************************************************************/

CREATE VOLATILE TABLE VT_FX_FALLBACK
(
       CCY_CD      CHAR(3)        NOT NULL,
       BOOKING_DT  DATE           NOT NULL,
       RATE_DT     DATE,
       GBP_RATE    DECIMAL(18,8)
)
PRIMARY INDEX ( CCY_CD, BOOKING_DT )
ON COMMIT PRESERVE ROWS
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO VT_FX_FALLBACK
SELECT ccy.TXN_CCY,
       ccy.BOOKING_DT,
       fxr.RATE_DT,
       fxr.GBP_RATE
FROM
       (SELECT DISTINCT
               TXN_CCY,
               BOOKING_DT
        FROM   <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD
        WHERE  TXN_CCY <> 'GBP'
       )                                ccy

       INNER JOIN
       <DB_ENV>DB_ODS.FX_RATE           fxr
          ON  fxr.CCY_CD       = ccy.TXN_CCY
          AND fxr.RATE_TYP_CD  = 'SP'
          AND fxr.RATE_DT     <= ccy.BOOKING_DT
          AND fxr.RATE_DT     >= ccy.BOOKING_DT - 10
          AND fxr.GBP_RATE     > 0

QUALIFY ROW_NUMBER () OVER (PARTITION BY ccy.TXN_CCY,
                                         ccy.BOOKING_DT
                                ORDER BY fxr.RATE_DT DESC
                           ) = 1
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS ON VT_FX_FALLBACK COLUMN (CCY_CD, BOOKING_DT);


/**************************************************************************\
* CONVERT TRANSACTION AMOUNTS TO GBP                                       *
* ------------------------------------------------------------------------ *
* GBP_RATE is expressed as units of currency per 1 GBP, hence              *
* GBP_AMT = TXN_AMT / GBP_RATE.                                            *
* RATE_FALLBACK_IND : N = snapshot rate of booking date                    *
*                     Y = fallback rate from FX history                    *
*                     X = no rate found (reported in dailytxn.07)          *
\**************************************************************************/

DELETE FROM <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_GBP
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_GBP
(
       TXN_REF,
       SUPPLIER_CD,
       TXN_CCY,
       TXN_AMT,
       RATE_DT,
       GBP_RATE,
       GBP_AMT,
       RATE_FALLBACK_IND
)
SELECT dtl.TXN_REF,
       dtl.SUPPLIER_CD,
       dtl.TXN_CCY,
       dtl.TXN_AMT,
       CASE
          WHEN dtl.TXN_CCY = 'GBP'              THEN dtl.BOOKING_DT
          WHEN snp.RATE_DT = dtl.BOOKING_DT     THEN snp.RATE_DT
          ELSE fbk.RATE_DT
       END,
       CASE
          WHEN dtl.TXN_CCY = 'GBP'              THEN CAST (1 AS DECIMAL(18,8))
          WHEN snp.RATE_DT = dtl.BOOKING_DT     THEN snp.GBP_RATE
          ELSE fbk.GBP_RATE
       END,
       CASE
          WHEN dtl.TXN_CCY = 'GBP'
          THEN dtl.TXN_AMT
          WHEN snp.RATE_DT = dtl.BOOKING_DT
          THEN CAST (dtl.TXN_AMT / NULLIFZERO (snp.GBP_RATE) AS DECIMAL(18,2))
          ELSE CAST (dtl.TXN_AMT / NULLIFZERO (fbk.GBP_RATE) AS DECIMAL(18,2))
       END,
       CASE
          WHEN dtl.TXN_CCY = 'GBP'              THEN 'N'
          WHEN snp.RATE_DT = dtl.BOOKING_DT     THEN 'N'
          WHEN fbk.GBP_RATE IS NOT NULL         THEN 'Y'
          ELSE 'X'
       END
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD    dtl

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.FX_RATE_SNAPSHOT         snp
          ON  snp.CCY_CD = dtl.TXN_CCY

       LEFT OUTER JOIN
       VT_FX_FALLBACK                          fbk
          ON  fbk.CCY_CD     = dtl.TXN_CCY
          AND fbk.BOOKING_DT = dtl.BOOKING_DT
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_GBP INDEX (TXN_REF, SUPPLIER_CD);
COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_GBP COLUMN (RATE_FALLBACK_IND);


/**************************************************************************\
* REPORT FALLBACK RATE USAGE                                               *
* ------------------------------------------------------------------------ *
* Informational output for the batch log only.                             *
\**************************************************************************/

SELECT TXN_CCY,
       RATE_FALLBACK_IND,
       COUNT (*)          AS TXN_CNT,
       SUM (TXN_AMT)      AS TXN_AMT,
       SUM (GBP_AMT)      AS GBP_AMT
FROM   <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_GBP
WHERE  RATE_FALLBACK_IND <> 'N'
GROUP  BY 1, 2
ORDER  BY 1, 2
;
.if errorcode <> 0 then .quit errorcode;

DROP TABLE VT_FX_FALLBACK
;
.if errorcode <> 0 then .quit errorcode;

.quit 0;

