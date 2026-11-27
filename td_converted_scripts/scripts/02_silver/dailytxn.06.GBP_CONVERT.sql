-- TODO: manual review required — choose a Databricks notebook, stored procedure, or Workflows DAG as the execution wrapper for this former BTEQ script.

-- Teradata optimizer statistics commands removed because Delta maintains table-level statistics and has no indexes.


/**************************************************************************\
* ADD NEW ACCOUNTS TO THE ACCOUNT SNAPSHOT                                 *
* ------------------------------------------------------------------------ *
* Transactions may arrive for accounts which are not yet delivered by      *
* KYCSYS (same day account opening, migrated books). A placeholder entry   *
* is created so that the transaction can be loaded; it is replaced by the  *
* full record with the next KYCSYS load (kycref.55). The account is also   *
* reported in the DQ log (dailytxn.07).                                    *
\**************************************************************************/

-- TODO: manual review required — implement this former BTEQ .IF ERRORCODE / .QUIT behavior with procedure error handling or a Workflows branch.
-- Source database qualifiers removed because no target Unity Catalog mapping was supplied; names resolve in the current catalog and schema.
INSERT INTO ACCT_SNAPSHOT
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
       DLYTXN_LOAD   dtl

       LEFT OUTER JOIN
       ACCT_SNAPSHOT snp
          ON  snp.ACCT_ID = dtl.ACCT_ID
WHERE
       snp.ACCT_ID IS NULL
AND    TRIM (dtl.ACCT_ID) <> ''
GROUP  BY dtl.ACCT_ID
;


/**************************************************************************\
* DETERMINE FALLBACK FX RATES                                              *
* ------------------------------------------------------------------------ *
* The snapshot holds the latest published rate per currency. When the      *
* booking date differs from the snapshot rate date (back-dated postings,   *
* weekend / bank holiday bookings), the latest spot rate published on or   *
* before the booking date is used instead - looking back 10 days at most.  *
\**************************************************************************/

-- TODO: manual review required — confirm CHAR(3) trailing-space comparison and padding behavior for CCY_CD in Databricks.
-- TODO: manual review required — implement this former BTEQ .IF ERRORCODE / .QUIT behavior with procedure error handling or a Workflows branch.
-- Teradata volatile-table syntax, PRIMARY INDEX, and ON COMMIT PRESERVE ROWS replaced with a session-scoped Databricks temporary table.
CREATE TEMP TABLE VT_FX_FALLBACK
(
       CCY_CD      CHAR(3)        NOT NULL,
       BOOKING_DT  DATE           NOT NULL,
       RATE_DT     DATE,
       GBP_RATE    DECIMAL(18,8)
)
;

-- TODO: manual review required — implement this former BTEQ .IF ERRORCODE / .QUIT behavior with procedure error handling or a Workflows branch.
-- Source database qualifiers removed because no target Unity Catalog mapping was supplied; names resolve in the current catalog and schema.
INSERT INTO VT_FX_FALLBACK
SELECT ccy.TXN_CCY,
       ccy.BOOKING_DT,
       fxr.RATE_DT,
       fxr.GBP_RATE
FROM
       (SELECT DISTINCT
               TXN_CCY,
               BOOKING_DT
        FROM   DLYTXN_LOAD
        WHERE  TXN_CCY <> 'GBP'
       )                                ccy

       INNER JOIN
       FX_RATE                          fxr
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

-- Deliberate post-load Teradata column statistics refresh replaced with Databricks ANALYZE TABLE.
ANALYZE TABLE VT_FX_FALLBACK COMPUTE STATISTICS FOR COLUMNS CCY_CD, BOOKING_DT;


/**************************************************************************\
* CONVERT TRANSACTION AMOUNTS TO GBP                                       *
* ------------------------------------------------------------------------ *
* GBP_RATE is expressed as units of currency per 1 GBP, hence              *
* GBP_AMT = TXN_AMT / GBP_RATE.                                            *
* RATE_FALLBACK_IND : N = snapshot rate of booking date                    *
*                     Y = fallback rate from FX history                    *
*                     X = no rate found (reported in dailytxn.07)          *
\**************************************************************************/

-- TODO: manual review required — implement this former BTEQ .IF ERRORCODE / .QUIT behavior with procedure error handling or a Workflows branch.
-- Source database qualifier removed because no target Unity Catalog mapping was supplied; the table resolves in the current catalog and schema.
DELETE FROM DLYTXN_GBP
;

-- TODO: manual review required — implement this former BTEQ .IF ERRORCODE / .QUIT behavior with procedure error handling or a Workflows branch.
-- Source database qualifiers removed because no target Unity Catalog mapping was supplied; names resolve in the current catalog and schema.
-- Teradata NULLIFZERO calls replaced with Databricks NULLIF while retaining explicit quotient precision and scale.
INSERT INTO DLYTXN_GBP
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
          THEN CAST (dtl.TXN_AMT / NULLIF (snp.GBP_RATE, 0) AS DECIMAL(18,2))
          ELSE CAST (dtl.TXN_AMT / NULLIF (fbk.GBP_RATE, 0) AS DECIMAL(18,2))
       END,
       CASE
          WHEN dtl.TXN_CCY = 'GBP'              THEN 'N'
          WHEN snp.RATE_DT = dtl.BOOKING_DT     THEN 'N'
          WHEN fbk.GBP_RATE IS NOT NULL         THEN 'Y'
          ELSE 'X'
       END
FROM
       DLYTXN_LOAD                              dtl

       LEFT OUTER JOIN
       FX_RATE_SNAPSHOT                         snp
          ON  snp.CCY_CD = dtl.TXN_CCY

       LEFT OUTER JOIN
       VT_FX_FALLBACK                           fbk
          ON  fbk.CCY_CD     = dtl.TXN_CCY
          AND fbk.BOOKING_DT = dtl.BOOKING_DT
;

-- Teradata index statistics removed because Delta has no index-statistics equivalent; the deliberate post-load column refresh uses ANALYZE TABLE.
ANALYZE TABLE DLYTXN_GBP COMPUTE STATISTICS FOR COLUMNS RATE_FALLBACK_IND;


/**************************************************************************\
* REPORT FALLBACK RATE USAGE                                               *
* ------------------------------------------------------------------------ *
* Informational output for the batch log only.                             *
\**************************************************************************/

-- TODO: manual review required — implement this former BTEQ .IF ERRORCODE / .QUIT behavior with procedure error handling or a Workflows branch.
-- Source database qualifier removed because no target Unity Catalog mapping was supplied; the table resolves in the current catalog and schema.
SELECT TXN_CCY,
       RATE_FALLBACK_IND,
       COUNT (*)          AS TXN_CNT,
       SUM (TXN_AMT)      AS TXN_AMT,
       SUM (GBP_AMT)      AS GBP_AMT
FROM   DLYTXN_GBP
WHERE  RATE_FALLBACK_IND <> 'N'
GROUP  BY 1, 2
ORDER  BY 1, 2
;

-- TODO: manual review required — implement this former BTEQ .IF ERRORCODE / .QUIT behavior with procedure error handling or a Workflows branch.
-- Cleanup targets the converted Databricks temporary table; the successful BTEQ .QUIT command was removed.
DROP TEMPORARY TABLE VT_FX_FALLBACK
;

