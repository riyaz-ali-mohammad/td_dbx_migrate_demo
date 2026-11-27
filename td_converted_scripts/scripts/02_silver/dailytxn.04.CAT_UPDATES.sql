-- TODO: manual review required — choose a Databricks notebook, stored procedure, or Workflows DAG as the BTEQ script wrapper

/**************************************************************************\
* COLLECT STATISTICS ON THE CATEGORY TABLES                                *
\**************************************************************************/

-- Converted: removed Teradata index statistics collection for TXN_TYP_CAT because Delta has no indexes.
-- Converted: removed Teradata index statistics collection for CHNL_CAT because Delta has no indexes.
-- Converted: removed Teradata index statistics collection for TXN_STATUS_CAT because Delta has no indexes.
-- Converted: removed Teradata index statistics collection for PURPOSE_CAT because Delta has no indexes.
-- Converted: removed Teradata index statistics collection for AUTH_METHOD_CAT because Delta has no indexes.
-- Converted: removed Teradata index statistics collection for BIC_DIRECTORY because Delta has no indexes.


/**************************************************************************\
* ADD NEW TRANSACTION TYPE CODES TO TXN_TYP_CAT                            *
* ------------------------------------------------------------------------ *
* Codes which are delivered in the daily extract but are not yet known     *
* in the category table are added with a default description and the       *
* AUTO_ADDED_IND set, so that reference data management can complete them. *
\**************************************************************************/

-- TODO: manual review required — BTEQ .IF ERRORCODE / .QUIT must become procedure SIGNAL handling or a Workflows branch
-- Converted: mapped Teradata database names to environment-catalog Unity Catalog names.
INSERT INTO `<DB_ENV>`.DB_ODS.TXN_TYP_CAT
(
       CD,
       CD_DESC,
       AUTO_ADDED_IND,
       CO_UPD_TMS
)
SELECT dtl.TXN_TYP_CD,
       'UNKNOWN - AUTO ADDED',
       'Y',
       MAX(tms.LOAD_TMS)
FROM
       `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD       dtl

       CROSS JOIN
       `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS   tms

       LEFT OUTER JOIN
       `<DB_ENV>`.DB_ODS.TXN_TYP_CAT                 cat
          ON cat.CD = dtl.TXN_TYP_CD
WHERE
       cat.CD IS NULL
AND    dtl.TXN_TYP_CD IS NOT NULL
AND    TRIM(dtl.TXN_TYP_CD) <> ''
GROUP BY dtl.TXN_TYP_CD
;


/**************************************************************************\
* ADD NEW CHANNEL CODES TO CHNL_CAT                                        *
* ------------------------------------------------------------------------ *
* Codes which are delivered in the daily extract but are not yet known     *
* in the category table are added with a default description and the       *
* AUTO_ADDED_IND set, so that reference data management can complete them. *
\**************************************************************************/

-- TODO: manual review required — BTEQ .IF ERRORCODE / .QUIT must become procedure SIGNAL handling or a Workflows branch
-- Converted: mapped Teradata database names to environment-catalog Unity Catalog names.
INSERT INTO `<DB_ENV>`.DB_ODS.CHNL_CAT
(
       CD,
       CD_DESC,
       AUTO_ADDED_IND,
       CO_UPD_TMS
)
SELECT dtl.CHNL_CD,
       'UNKNOWN - AUTO ADDED',
       'Y',
       MAX(tms.LOAD_TMS)
FROM
       `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD       dtl

       CROSS JOIN
       `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS   tms

       LEFT OUTER JOIN
       `<DB_ENV>`.DB_ODS.CHNL_CAT                    cat
          ON cat.CD = dtl.CHNL_CD
WHERE
       cat.CD IS NULL
AND    dtl.CHNL_CD IS NOT NULL
AND    TRIM(dtl.CHNL_CD) <> ''
GROUP BY dtl.CHNL_CD
;


/**************************************************************************\
* ADD NEW TRANSACTION STATUS CODES TO TXN_STATUS_CAT                       *
* ------------------------------------------------------------------------ *
* Codes which are delivered in the daily extract but are not yet known     *
* in the category table are added with a default description and the       *
* AUTO_ADDED_IND set, so that reference data management can complete them. *
\**************************************************************************/

-- TODO: manual review required — BTEQ .IF ERRORCODE / .QUIT must become procedure SIGNAL handling or a Workflows branch
-- Converted: mapped Teradata database names to environment-catalog Unity Catalog names.
INSERT INTO `<DB_ENV>`.DB_ODS.TXN_STATUS_CAT
(
       CD,
       CD_DESC,
       AUTO_ADDED_IND,
       CO_UPD_TMS
)
SELECT dtl.TXN_STATUS,
       'UNKNOWN - AUTO ADDED',
       'Y',
       MAX(tms.LOAD_TMS)
FROM
       `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD       dtl

       CROSS JOIN
       `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS   tms

       LEFT OUTER JOIN
       `<DB_ENV>`.DB_ODS.TXN_STATUS_CAT              cat
          ON cat.CD = dtl.TXN_STATUS
WHERE
       cat.CD IS NULL
AND    dtl.TXN_STATUS IS NOT NULL
AND    TRIM(dtl.TXN_STATUS) <> ''
GROUP BY dtl.TXN_STATUS
;


/**************************************************************************\
* ADD NEW PAYMENT PURPOSE CODES TO PURPOSE_CAT                             *
* ------------------------------------------------------------------------ *
* Codes which are delivered in the daily extract but are not yet known     *
* in the category table are added with a default description and the       *
* AUTO_ADDED_IND set, so that reference data management can complete them. *
\**************************************************************************/

-- TODO: manual review required — BTEQ .IF ERRORCODE / .QUIT must become procedure SIGNAL handling or a Workflows branch
-- Converted: mapped Teradata database names to environment-catalog Unity Catalog names.
INSERT INTO `<DB_ENV>`.DB_ODS.PURPOSE_CAT
(
       CD,
       CD_DESC,
       AUTO_ADDED_IND,
       CO_UPD_TMS
)
SELECT dtl.PURPOSE_CD,
       'UNKNOWN - AUTO ADDED',
       'Y',
       MAX(tms.LOAD_TMS)
FROM
       `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD       dtl

       CROSS JOIN
       `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS   tms

       LEFT OUTER JOIN
       `<DB_ENV>`.DB_ODS.PURPOSE_CAT                 cat
          ON cat.CD = dtl.PURPOSE_CD
WHERE
       cat.CD IS NULL
AND    dtl.PURPOSE_CD IS NOT NULL
AND    TRIM(dtl.PURPOSE_CD) <> ''
GROUP BY dtl.PURPOSE_CD
;


/**************************************************************************\
* ADD NEW AUTHENTICATION METHOD CODES TO AUTH_METHOD_CAT                   *
* ------------------------------------------------------------------------ *
* Codes which are delivered in the daily extract but are not yet known     *
* in the category table are added with a default description and the       *
* AUTO_ADDED_IND set, so that reference data management can complete them. *
\**************************************************************************/

-- TODO: manual review required — BTEQ .IF ERRORCODE / .QUIT must become procedure SIGNAL handling or a Workflows branch
-- Converted: mapped Teradata database names to environment-catalog Unity Catalog names.
INSERT INTO `<DB_ENV>`.DB_ODS.AUTH_METHOD_CAT
(
       CD,
       CD_DESC,
       AUTO_ADDED_IND,
       CO_UPD_TMS
)
SELECT dtl.AUTH_METHOD,
       'UNKNOWN - AUTO ADDED',
       'Y',
       MAX(tms.LOAD_TMS)
FROM
       `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD       dtl

       CROSS JOIN
       `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS   tms

       LEFT OUTER JOIN
       `<DB_ENV>`.DB_ODS.AUTH_METHOD_CAT             cat
          ON cat.CD = dtl.AUTH_METHOD
WHERE
       cat.CD IS NULL
AND    dtl.AUTH_METHOD IS NOT NULL
AND    TRIM(dtl.AUTH_METHOD) <> ''
GROUP BY dtl.AUTH_METHOD
;


/**************************************************************************\
* ADD NEW BANK IDENTIFIER CODES TO BIC_DIRECTORY                           *
* ------------------------------------------------------------------------ *
* BICs of the counterparty bank and of any intermediary bank are added.    *
* Only syntactically valid 8 or 11 character BICs are taken. 8 character   *
* BICs are padded with XXX to the primary office BIC. The country is taken *
* from positions 5-6 of the BIC.                                           *
\**************************************************************************/

-- TODO: manual review required — BTEQ .IF ERRORCODE / .QUIT must become procedure SIGNAL handling or a Workflows branch
-- Converted: mapped Teradata database names to environment-catalog Unity Catalog names.
INSERT INTO `<DB_ENV>`.DB_REFERENCE.BIC_DIRECTORY
(
       BIC_CD,
       BANK_NM,
       CTRY_2_CD,
       AUTO_ADDED_IND,
       CO_UPD_TMS
)
SELECT new_bic.BIC_CD,
       'UNKNOWN - AUTO ADDED',
       SUBSTR(new_bic.BIC_CD, 5, 2),
       'Y',
       MAX(tms.LOAD_TMS)
FROM
       (SELECT CASE WHEN CHARACTER_LENGTH(TRIM(CPTY_BIC)) = 8
                    THEN TRIM(CPTY_BIC) || 'XXX'
                    ELSE TRIM(CPTY_BIC)
               END AS BIC_CD
        FROM `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD
        WHERE CHARACTER_LENGTH(TRIM(CPTY_BIC)) IN (8, 11)

        UNION

        SELECT CASE WHEN CHARACTER_LENGTH(TRIM(INTERMED_BIC)) = 8
                    THEN TRIM(INTERMED_BIC) || 'XXX'
                    ELSE TRIM(INTERMED_BIC)
               END
        FROM `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD
        WHERE CHARACTER_LENGTH(TRIM(INTERMED_BIC)) IN (8, 11)
       ) new_bic

       CROSS JOIN
       `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS   tms

       LEFT OUTER JOIN
       `<DB_ENV>`.DB_REFERENCE.BIC_DIRECTORY         bic
          ON bic.BIC_CD = new_bic.BIC_CD
WHERE
       bic.BIC_CD IS NULL
AND    SUBSTR(new_bic.BIC_CD, 5, 2) BETWEEN 'AA' AND 'ZZ'
GROUP BY new_bic.BIC_CD
;


/**************************************************************************\
* NORMALISE 8 CHARACTER BICS IN THE LOAD TABLE                             *
\**************************************************************************/

-- TODO: manual review required — BTEQ .IF ERRORCODE / .QUIT must become procedure SIGNAL handling or a Workflows branch
-- Converted: mapped the Teradata database name to an environment-catalog Unity Catalog name.
UPDATE `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD
SET
       CPTY_BIC = TRIM(CPTY_BIC) || 'XXX'
WHERE
       CHARACTER_LENGTH(TRIM(CPTY_BIC)) = 8
;

-- TODO: manual review required — BTEQ .IF ERRORCODE / .QUIT must become procedure SIGNAL handling or a Workflows branch
-- Converted: mapped the Teradata database name to an environment-catalog Unity Catalog name.
UPDATE `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD
SET
       INTERMED_BIC = TRIM(INTERMED_BIC) || 'XXX'
WHERE
       CHARACTER_LENGTH(TRIM(INTERMED_BIC)) = 8
;


/**************************************************************************\
* ADD NEW RETURN REASON CODES                                              *
* ------------------------------------------------------------------------ *
* Returned / rejected payments (BACS ARUCS / ADDACS, FPS returns, SWIFT    *
* returns) carry a reason code. New codes are added to the reference.      *
\**************************************************************************/

-- TODO: manual review required — BTEQ .IF ERRORCODE / .QUIT must become procedure SIGNAL handling or a Workflows branch
-- Converted: mapped Teradata database names to environment-catalog Unity Catalog names.
INSERT INTO `<DB_ENV>`.DB_REFERENCE.RETURN_REASON
(
       RETURN_REASON_CD,
       RETURN_REASON_DESC,
       AUTO_ADDED_IND,
       CO_UPD_TMS
)
SELECT dtl.RETURN_REASON_CD,
       'UNKNOWN - AUTO ADDED',
       'Y',
       MAX(tms.LOAD_TMS)
FROM
       `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD       dtl

       CROSS JOIN
       `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS   tms

       LEFT OUTER JOIN
       `<DB_ENV>`.DB_REFERENCE.RETURN_REASON         rsn
          ON rsn.RETURN_REASON_CD = dtl.RETURN_REASON_CD
WHERE
       rsn.RETURN_REASON_CD IS NULL
AND    TRIM(dtl.RETURN_REASON_CD) <> ''
GROUP BY dtl.RETURN_REASON_CD
;


/**************************************************************************\
* REFRESH DESCRIPTIONS OF AUTO ADDED TRANSACTION TYPES                     *
* ------------------------------------------------------------------------ *
* Once reference data management has completed a transaction type in       *
* REFSYS (DB_ODS.TXN_TYP), the auto-added category entry is updated.       *
\**************************************************************************/

-- TODO: manual review required — BTEQ .IF ERRORCODE / .QUIT must become procedure SIGNAL handling or a Workflows branch
-- Converted: replaced Teradata UPDATE FROM with Delta MERGE and mapped database names to environment-catalog Unity Catalog names.
MERGE INTO `<DB_ENV>`.DB_ODS.TXN_TYP_CAT AS cat
USING (
       SELECT typ.TXN_TYP_CD,
              typ.TXN_TYP_DESC,
              tms.LOAD_TMS
       FROM   (SELECT TXN_TYP_CD,
                      TXN_TYP_DESC
               FROM   `<DB_ENV>`.DB_ODS.TXN_TYP
               WHERE  START_DT <= CURRENT_DATE
               AND    END_DT   > CURRENT_DATE
               QUALIFY SUM(1) OVER (PARTITION BY TXN_TYP_CD
                                    ORDER BY START_DT DESC
                                    ROWS UNBOUNDED PRECEDING) = 1
              ) AS typ
       CROSS JOIN `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS AS tms
      ) AS src
ON  cat.CD = src.TXN_TYP_CD
AND cat.AUTO_ADDED_IND = 'Y'
WHEN MATCHED THEN UPDATE SET
       CD_DESC        = src.TXN_TYP_DESC,
       AUTO_ADDED_IND = 'N',
       CO_UPD_TMS     = src.LOAD_TMS
;

-- TODO: manual review required — BTEQ .IF ERRORCODE / .QUIT must become procedure SIGNAL handling or a Workflows branch
-- Converted: replaced Teradata UPDATE FROM with Delta MERGE and mapped database names to environment-catalog Unity Catalog names.
MERGE INTO `<DB_ENV>`.DB_ODS.CHNL_CAT AS cat
USING (
       SELECT chn.CHNL_CD,
              chn.CHNL_DESC,
              tms.LOAD_TMS
       FROM   (SELECT CHNL_CD,
                      CHNL_DESC
               FROM   `<DB_ENV>`.DB_ODS.CHNL
               WHERE  START_DT <= CURRENT_DATE
               AND    END_DT   > CURRENT_DATE
               QUALIFY SUM(1) OVER (PARTITION BY CHNL_CD
                                    ORDER BY START_DT DESC
                                    ROWS UNBOUNDED PRECEDING) = 1
              ) AS chn
       CROSS JOIN `<DB_ENV>`.DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS AS tms
      ) AS src
ON  cat.CD = src.CHNL_CD
AND cat.AUTO_ADDED_IND = 'Y'
WHEN MATCHED THEN UPDATE SET
       CD_DESC        = src.CHNL_DESC,
       AUTO_ADDED_IND = 'N',
       CO_UPD_TMS     = src.LOAD_TMS
;


/**************************************************************************\
* END OF SCRIPT                                                            *
\**************************************************************************/

-- Converted: removed final Teradata index statistics collection for TXN_TYP_CAT because Delta has no indexes.
-- Converted: removed final Teradata index statistics collection for CHNL_CAT because Delta has no indexes.
-- Converted: removed final Teradata index statistics collection for BIC_DIRECTORY because Delta has no indexes.


