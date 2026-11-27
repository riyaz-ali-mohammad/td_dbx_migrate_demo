-- TODO: manual review required — BTEQ script must be hosted in a notebook, stored procedure, or Workflows DAG; choose the execution wrapper and map error exits accordingly
-- assumption: source <DB_ENV> is represented by the Unity Catalog catalog named db_env
/**************************************************************************\
* VERIFY THE REFSYS TIMESTAMP                                              *
* ------------------------------------------------------------------------ *
* Exactly one timestamp row must exist (written by kycref.35).             *
\**************************************************************************/

-- Converted BTEQ conditional exit to a Databricks SQL assertion query.
SELECT assert_true(COUNT(*) = 1, 'AML_TMS_REFSYS must contain exactly one row')
FROM   db_env.db_trans_imports.AML_TMS_REFSYS;


/**************************************************************************\
* COUNTRY RISK: RERUN PROTECTION (CTRY)                                    *
* ------------------------------------------------------------------------ *
* Versions opened by an earlier run of today are removed and the version   *
* they superseded is re-opened, so that the step can be re-executed.       *
\**************************************************************************/


DELETE FROM db_env.db_ods.CTRY
WHERE  START_DT = (SELECT CAST (TMS AS DATE) FROM db_env.db_trans_imports.AML_TMS_REFSYS)
AND    (CTRY_2_CD) IN (SELECT CTRY_2_CD FROM db_env.db_trans_imports.AML_CTRY)
;


-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO db_env.db_ods.CTRY AS TGT
USING (
       SELECT SRC.CTRY_2_CD, TTS.TMS
       FROM (SELECT DISTINCT CTRY_2_CD FROM db_env.db_trans_imports.AML_CTRY) AS SRC
       CROSS JOIN db_env.db_trans_imports.AML_TMS_REFSYS AS TTS
) AS SRC
ON  TGT.CTRY_2_CD = SRC.CTRY_2_CD
AND TGT.END_DT = CAST(SRC.TMS AS DATE) - 1
WHEN MATCHED THEN UPDATE SET END_DT = DATE '9999-12-31';


/**************************************************************************\
* COUNTRY RISK: CLOSE CHANGED AND DELETED VERSIONS                         *
\**************************************************************************/


-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO db_env.db_ods.CTRY AS TGT
USING (
       SELECT SRC.*, TTS.TMS
       FROM db_env.db_trans_imports.AML_CTRY AS SRC
       CROSS JOIN db_env.db_trans_imports.AML_TMS_REFSYS AS TTS
) AS SRC
ON  TGT.CTRY_2_CD = SRC.CTRY_2_CD
AND TGT.END_DT = DATE '9999-12-31'
AND (   SRC.ACTION_CD = 'D'
     OR COALESCE(TGT.CTRY_3_CD, '~') <> COALESCE(SRC.CTRY_3_CD, '~')
     OR COALESCE(TGT.CTRY_NM, '~') <> COALESCE(SRC.CTRY_NM, '~')
     OR COALESCE(TGT.FATF_STATUS_CD, '~') <> COALESCE(SRC.FATF_STATUS_CD, '~')
     OR COALESCE(TGT.HMT_HIGH_RISK_IND, '~') <> COALESCE(SRC.HMT_HIGH_RISK_IND, '~')
     OR COALESCE(TGT.EU_HIGH_RISK_IND, '~') <> COALESCE(SRC.EU_HIGH_RISK_IND, '~')
     OR COALESCE(TGT.BASEL_AML_SCORE, -1) <> COALESCE(SRC.BASEL_AML_SCORE, -1)
     OR COALESCE(TGT.CPI_SCORE, -1) <> COALESCE(SRC.CPI_SCORE, -1)
     OR COALESCE(TGT.OFFSHORE_IND, '~') <> COALESCE(SRC.OFFSHORE_IND, '~')
     OR COALESCE(TGT.REGION_CD, '~') <> COALESCE(SRC.REGION_CD, '~')
     OR COALESCE(SRC.VALID_TO_DT, DATE '9999-12-31') < CAST(SRC.TMS AS DATE)
     OR COALESCE(TGT.CTRY_RISK_CD, '~') <> CASE
            WHEN SRC.FATF_STATUS_CD IN ('BL', 'GL')
              OR SRC.HMT_HIGH_RISK_IND = 'Y'
              OR SRC.EU_HIGH_RISK_IND = 'Y'
              OR SRC.BASEL_AML_SCORE >= 6.50 THEN 'H'
            WHEN SRC.OFFSHORE_IND = 'Y'
              OR SRC.BASEL_AML_SCORE >= 5.00 THEN 'M'
            ELSE 'L'
        END
)
WHEN MATCHED THEN UPDATE SET
     END_DT = CAST(SRC.TMS AS DATE) - 1,
     CO_UPD_TMS = CAST(SRC.TMS AS TIMESTAMP_NTZ);


-- Converted the bounded Teradata VARCHAR cast to a Databricks STRING cast for operational logging.
SELECT 'CLOSED ' || TRIM(CAST(COUNT(*) AS STRING)) || ' VERSIONS IN CTRY'
FROM   db_env.db_ods.CTRY
WHERE  END_DT = (SELECT CAST (TMS AS DATE) - 1 FROM db_env.db_trans_imports.AML_TMS_REFSYS)
;



/**************************************************************************\
* COUNTRY RISK: INSERT NEW VERSIONS                                        *
\**************************************************************************/


-- Converted timezone-naive Teradata timestamp expressions to TIMESTAMP_NTZ.
INSERT INTO db_env.db_ods.CTRY
(
       CTRY_2_CD,
       START_DT,
       END_DT,
       CTRY_3_CD,
       CTRY_NM,
       FATF_STATUS_CD,
       HMT_HIGH_RISK_IND,
       EU_HIGH_RISK_IND,
       BASEL_AML_SCORE,
       CPI_SCORE,
       OFFSHORE_IND,
       REGION_CD,
       CTRY_RISK_CD,
       CO_UPD_TMS
)
SELECT SRC.CTRY_2_CD,
       CAST ((SELECT TMS FROM db_env.db_trans_imports.AML_TMS_REFSYS) AS DATE),
       DATE '9999-12-31',
       SRC.CTRY_3_CD,
       SRC.CTRY_NM,
       SRC.FATF_STATUS_CD,
       SRC.HMT_HIGH_RISK_IND,
       SRC.EU_HIGH_RISK_IND,
       SRC.BASEL_AML_SCORE,
       SRC.CPI_SCORE,
       SRC.OFFSHORE_IND,
       SRC.REGION_CD,
       CASE WHEN SRC.FATF_STATUS_CD IN ('BL', 'GL')
                OR SRC.HMT_HIGH_RISK_IND = 'Y'
                OR SRC.EU_HIGH_RISK_IND  = 'Y'
                OR SRC.BASEL_AML_SCORE  >= 6.50
            THEN 'H'
            WHEN SRC.OFFSHORE_IND = 'Y'
                OR SRC.BASEL_AML_SCORE  >= 5.00
            THEN 'M'
            ELSE 'L'
       END,
       CAST ((SELECT TMS FROM db_env.db_trans_imports.AML_TMS_REFSYS) AS TIMESTAMP_NTZ)
FROM   db_env.db_trans_imports.AML_CTRY   SRC
WHERE  SRC.ACTION_CD <> 'D'
AND    COALESCE (SRC.VALID_TO_DT, DATE '9999-12-31') >= CAST ((SELECT TMS FROM db_env.db_trans_imports.AML_TMS_REFSYS) AS DATE)
AND    NOT EXISTS
       (SELECT 1
        FROM   db_env.db_ods.CTRY   CUR
        WHERE  CUR.CTRY_2_CD = SRC.CTRY_2_CD
        AND    CUR.END_DT = DATE '9999-12-31'
       )
;



/**************************************************************************\
* CURRENCY: RERUN PROTECTION (CCY)                                         *
* ------------------------------------------------------------------------ *
* Versions opened by an earlier run of today are removed and the version   *
* they superseded is re-opened, so that the step can be re-executed.       *
\**************************************************************************/


DELETE FROM db_env.db_ods.CCY
WHERE  START_DT = (SELECT CAST (TMS AS DATE) FROM db_env.db_trans_imports.AML_TMS_REFSYS)
AND    (CCY_CD) IN (SELECT CCY_CD FROM db_env.db_trans_imports.AML_CCY)
;


-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO db_env.db_ods.CCY AS TGT
USING (
  SELECT SRC.CCY_CD, TTS.TMS
  FROM (SELECT DISTINCT CCY_CD FROM db_env.db_trans_imports.AML_CCY) AS SRC
  CROSS JOIN db_env.db_trans_imports.AML_TMS_REFSYS AS TTS
) AS SRC
ON TGT.CCY_CD = SRC.CCY_CD
AND TGT.END_DT = CAST(SRC.TMS AS DATE) - 1
WHEN MATCHED THEN UPDATE SET END_DT = DATE '9999-12-31';


/**************************************************************************\
* CURRENCY: CLOSE CHANGED AND DELETED VERSIONS                             *
\**************************************************************************/


-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO db_env.db_ods.CCY AS TGT
USING (
  SELECT SRC.*, TTS.TMS
  FROM db_env.db_trans_imports.AML_CCY AS SRC
  CROSS JOIN db_env.db_trans_imports.AML_TMS_REFSYS AS TTS
) AS SRC
ON TGT.CCY_CD = SRC.CCY_CD
AND TGT.END_DT = DATE '9999-12-31'
AND (   SRC.ACTION_CD = 'D'
     OR COALESCE(TGT.CCY_NM, '~') <> COALESCE(SRC.CCY_NM, '~')
     OR COALESCE(TGT.MINOR_UNIT_CNT, -1) <> COALESCE(SRC.MINOR_UNIT_CNT, -1)
     OR COALESCE(TGT.CCY_NUM_CD, '~') <> COALESCE(SRC.CCY_NUM_CD, '~')
     OR COALESCE(TGT.ACTIVE_IND, '~') <> COALESCE(SRC.ACTIVE_IND, '~')
)
WHEN MATCHED THEN UPDATE SET
  END_DT = CAST(SRC.TMS AS DATE) - 1,
  CO_UPD_TMS = CAST(SRC.TMS AS TIMESTAMP_NTZ);


-- Converted the bounded Teradata VARCHAR cast to a Databricks STRING cast for operational logging.
SELECT 'CLOSED ' || TRIM(CAST(COUNT(*) AS STRING)) || ' VERSIONS IN CCY'
FROM   db_env.db_ods.CCY
WHERE  END_DT = (SELECT CAST (TMS AS DATE) - 1 FROM db_env.db_trans_imports.AML_TMS_REFSYS)
;



/**************************************************************************\
* CURRENCY: INSERT NEW VERSIONS                                            *
\**************************************************************************/


-- Converted timezone-naive Teradata timestamp expressions to TIMESTAMP_NTZ.
INSERT INTO db_env.db_ods.CCY
(
       CCY_CD,
       START_DT,
       END_DT,
       CCY_NM,
       MINOR_UNIT_CNT,
       CCY_NUM_CD,
       ACTIVE_IND,
       CO_UPD_TMS
)
SELECT SRC.CCY_CD,
       CAST ((SELECT TMS FROM db_env.db_trans_imports.AML_TMS_REFSYS) AS DATE),
       DATE '9999-12-31',
       SRC.CCY_NM,
       SRC.MINOR_UNIT_CNT,
       SRC.CCY_NUM_CD,
       SRC.ACTIVE_IND,
       CAST ((SELECT TMS FROM db_env.db_trans_imports.AML_TMS_REFSYS) AS TIMESTAMP_NTZ)
FROM   db_env.db_trans_imports.AML_CCY   SRC
WHERE  SRC.ACTION_CD <> 'D'
AND    NOT EXISTS
       (SELECT 1
        FROM   db_env.db_ods.CCY   CUR
        WHERE  CUR.CCY_CD = SRC.CCY_CD
        AND    CUR.END_DT = DATE '9999-12-31'
       )
;



/**************************************************************************\
* MERCHANT CATEGORY CODE: RERUN PROTECTION (MCC)                           *
* ------------------------------------------------------------------------ *
* Versions opened by an earlier run of today are removed and the version   *
* they superseded is re-opened, so that the step can be re-executed.       *
\**************************************************************************/


DELETE FROM db_env.db_ods.MCC
WHERE  START_DT = (SELECT CAST (TMS AS DATE) FROM db_env.db_trans_imports.AML_TMS_REFSYS)
AND    (MCC_CD) IN (SELECT MCC_CD FROM db_env.db_trans_imports.AML_MCC)
;


-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO db_env.db_ods.MCC AS TGT
USING (SELECT SRC.MCC_CD, TTS.TMS FROM (SELECT DISTINCT MCC_CD FROM db_env.db_trans_imports.AML_MCC) AS SRC CROSS JOIN db_env.db_trans_imports.AML_TMS_REFSYS AS TTS) AS SRC
ON TGT.MCC_CD = SRC.MCC_CD AND TGT.END_DT = CAST(SRC.TMS AS DATE) - 1
WHEN MATCHED THEN UPDATE SET END_DT = DATE '9999-12-31';


/**************************************************************************\
* MERCHANT CATEGORY CODE: CLOSE CHANGED AND DELETED VERSIONS               *
\**************************************************************************/


-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO db_env.db_ods.MCC AS TGT
USING (SELECT SRC.*, TTS.TMS FROM db_env.db_trans_imports.AML_MCC AS SRC CROSS JOIN db_env.db_trans_imports.AML_TMS_REFSYS AS TTS) AS SRC
ON TGT.MCC_CD = SRC.MCC_CD AND TGT.END_DT = DATE '9999-12-31'
AND (SRC.ACTION_CD = 'D'
 OR COALESCE(TGT.MCC_DESC, '~') <> COALESCE(SRC.MCC_DESC, '~')
 OR COALESCE(TGT.MCC_RISK_CD, '~') <> COALESCE(SRC.MCC_RISK_CD, '~')
 OR COALESCE(TGT.CASH_LIKE_IND, '~') <> COALESCE(SRC.CASH_LIKE_IND, '~')
 OR COALESCE(TGT.GAMBLING_IND, '~') <> COALESCE(SRC.GAMBLING_IND, '~')
 OR COALESCE(TGT.CRYPTO_IND, '~') <> COALESCE(SRC.CRYPTO_IND, '~'))
WHEN MATCHED THEN UPDATE SET END_DT = CAST(SRC.TMS AS DATE) - 1, CO_UPD_TMS = CAST(SRC.TMS AS TIMESTAMP_NTZ);


-- Converted the bounded Teradata VARCHAR cast to a Databricks STRING cast for operational logging.
SELECT 'CLOSED ' || TRIM(CAST(COUNT(*) AS STRING)) || ' VERSIONS IN MCC'
FROM   db_env.db_ods.MCC
WHERE  END_DT = (SELECT CAST (TMS AS DATE) - 1 FROM db_env.db_trans_imports.AML_TMS_REFSYS)
;



/**************************************************************************\
* MERCHANT CATEGORY CODE: INSERT NEW VERSIONS                              *
\**************************************************************************/


-- Converted timezone-naive Teradata timestamp expressions to TIMESTAMP_NTZ.
INSERT INTO db_env.db_ods.MCC
(
       MCC_CD,
       START_DT,
       END_DT,
       MCC_DESC,
       MCC_RISK_CD,
       CASH_LIKE_IND,
       GAMBLING_IND,
       CRYPTO_IND,
       CO_UPD_TMS
)
SELECT SRC.MCC_CD,
       CAST ((SELECT TMS FROM db_env.db_trans_imports.AML_TMS_REFSYS) AS DATE),
       DATE '9999-12-31',
       SRC.MCC_DESC,
       SRC.MCC_RISK_CD,
       SRC.CASH_LIKE_IND,
       SRC.GAMBLING_IND,
       SRC.CRYPTO_IND,
       CAST ((SELECT TMS FROM db_env.db_trans_imports.AML_TMS_REFSYS) AS TIMESTAMP_NTZ)
FROM   db_env.db_trans_imports.AML_MCC   SRC
WHERE  SRC.ACTION_CD <> 'D'
AND    NOT EXISTS
       (SELECT 1
        FROM   db_env.db_ods.MCC   CUR
        WHERE  CUR.MCC_CD = SRC.MCC_CD
        AND    CUR.END_DT = DATE '9999-12-31'
       )
;



/**************************************************************************\
* SORT CODE DIRECTORY: RERUN PROTECTION (SORT_CD_DIR)                      *
* ------------------------------------------------------------------------ *
* Versions opened by an earlier run of today are removed and the version   *
* they superseded is re-opened, so that the step can be re-executed.       *
\**************************************************************************/


DELETE FROM db_env.db_ods.SORT_CD_DIR
WHERE  START_DT = (SELECT CAST (TMS AS DATE) FROM db_env.db_trans_imports.AML_TMS_REFSYS)
AND    (SORT_CD) IN (SELECT SORT_CD FROM db_env.db_trans_imports.AML_SORT)
;


-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO db_env.db_ods.SORT_CD_DIR AS TGT
USING (SELECT SRC.SORT_CD, TTS.TMS FROM (SELECT DISTINCT SORT_CD FROM db_env.db_trans_imports.AML_SORT) AS SRC CROSS JOIN db_env.db_trans_imports.AML_TMS_REFSYS AS TTS) AS SRC
ON TGT.SORT_CD = SRC.SORT_CD AND TGT.END_DT = CAST(SRC.TMS AS DATE) - 1
WHEN MATCHED THEN UPDATE SET END_DT = DATE '9999-12-31';


/**************************************************************************\
* SORT CODE DIRECTORY: CLOSE CHANGED AND DELETED VERSIONS                  *
\**************************************************************************/


-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO db_env.db_ods.SORT_CD_DIR AS TGT
USING (SELECT SRC.*, TTS.TMS FROM db_env.db_trans_imports.AML_SORT AS SRC CROSS JOIN db_env.db_trans_imports.AML_TMS_REFSYS AS TTS) AS SRC
ON TGT.SORT_CD = SRC.SORT_CD AND TGT.END_DT = DATE '9999-12-31'
AND (SRC.ACTION_CD = 'D'
 OR COALESCE(TGT.BANK_NM, '~') <> COALESCE(SRC.BANK_NM, '~')
 OR COALESCE(TGT.BRANCH_NM, '~') <> COALESCE(SRC.BRANCH_NM, '~')
 OR COALESCE(TGT.BIC_CD, '~') <> COALESCE(SRC.BIC_CD, '~')
 OR COALESCE(TGT.FPS_IND, '~') <> COALESCE(SRC.FPS_IND, '~')
 OR COALESCE(TGT.CHAPS_IND, '~') <> COALESCE(SRC.CHAPS_IND, '~')
 OR COALESCE(TGT.BACS_IND, '~') <> COALESCE(SRC.BACS_IND, '~')
 OR COALESCE(TGT.CLOSED_IND, '~') <> COALESCE(SRC.CLOSED_IND, '~')
 OR COALESCE(TGT.POSTCODE, '~') <> COALESCE(SRC.POSTCODE, '~'))
WHEN MATCHED THEN UPDATE SET END_DT = CAST(SRC.TMS AS DATE) - 1, CO_UPD_TMS = CAST(SRC.TMS AS TIMESTAMP_NTZ);


-- Converted the bounded Teradata VARCHAR cast to a Databricks STRING cast for operational logging.
SELECT 'CLOSED ' || TRIM(CAST(COUNT(*) AS STRING)) || ' VERSIONS IN SORT_CD_DIR'
FROM   db_env.db_ods.SORT_CD_DIR
WHERE  END_DT = (SELECT CAST (TMS AS DATE) - 1 FROM db_env.db_trans_imports.AML_TMS_REFSYS)
;



/**************************************************************************\
* SORT CODE DIRECTORY: INSERT NEW VERSIONS                                 *
\**************************************************************************/


-- Converted timezone-naive Teradata timestamp expressions to TIMESTAMP_NTZ.
INSERT INTO db_env.db_ods.SORT_CD_DIR
(
       SORT_CD,
       START_DT,
       END_DT,
       BANK_NM,
       BRANCH_NM,
       BIC_CD,
       FPS_IND,
       CHAPS_IND,
       BACS_IND,
       CLOSED_IND,
       POSTCODE,
       CO_UPD_TMS
)
SELECT SRC.SORT_CD,
       CAST ((SELECT TMS FROM db_env.db_trans_imports.AML_TMS_REFSYS) AS DATE),
       DATE '9999-12-31',
       SRC.BANK_NM,
       SRC.BRANCH_NM,
       SRC.BIC_CD,
       SRC.FPS_IND,
       SRC.CHAPS_IND,
       SRC.BACS_IND,
       SRC.CLOSED_IND,
       SRC.POSTCODE,
       CAST ((SELECT TMS FROM db_env.db_trans_imports.AML_TMS_REFSYS) AS TIMESTAMP_NTZ)
FROM   db_env.db_trans_imports.AML_SORT   SRC
WHERE  SRC.ACTION_CD <> 'D'
AND    NOT EXISTS
       (SELECT 1
        FROM   db_env.db_ods.SORT_CD_DIR   CUR
        WHERE  CUR.SORT_CD = SRC.SORT_CD
        AND    CUR.END_DT = DATE '9999-12-31'
       )
;



/**************************************************************************\
* TRANSACTION TYPE: RERUN PROTECTION (TXN_TYP)                             *
* ------------------------------------------------------------------------ *
* Versions opened by an earlier run of today are removed and the version   *
* they superseded is re-opened, so that the step can be re-executed.       *
\**************************************************************************/


DELETE FROM db_env.db_ods.TXN_TYP
WHERE  START_DT = (SELECT CAST (TMS AS DATE) FROM db_env.db_trans_imports.AML_TMS_REFSYS)
AND    (TXN_TYP_CD) IN (SELECT TXN_TYP_CD FROM db_env.db_trans_imports.AML_TXTP)
;


-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO db_env.db_ods.TXN_TYP AS TGT
USING (SELECT SRC.TXN_TYP_CD, TTS.TMS FROM (SELECT DISTINCT TXN_TYP_CD FROM db_env.db_trans_imports.AML_TXTP) AS SRC CROSS JOIN db_env.db_trans_imports.AML_TMS_REFSYS AS TTS) AS SRC
ON TGT.TXN_TYP_CD = SRC.TXN_TYP_CD AND TGT.END_DT = CAST(SRC.TMS AS DATE) - 1
WHEN MATCHED THEN UPDATE SET END_DT = DATE '9999-12-31';


/**************************************************************************\
* TRANSACTION TYPE: CLOSE CHANGED AND DELETED VERSIONS                     *
\**************************************************************************/


-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO db_env.db_ods.TXN_TYP AS TGT
USING (SELECT SRC.*, TTS.TMS FROM db_env.db_trans_imports.AML_TXTP AS SRC CROSS JOIN db_env.db_trans_imports.AML_TMS_REFSYS AS TTS) AS SRC
ON TGT.TXN_TYP_CD = SRC.TXN_TYP_CD AND TGT.END_DT = DATE '9999-12-31'
AND (SRC.ACTION_CD = 'D'
 OR COALESCE(TGT.TXN_TYP_DESC, '~') <> COALESCE(SRC.TXN_TYP_DESC, '~')
 OR COALESCE(TGT.PAY_SCHEME_CD, '~') <> COALESCE(SRC.PAY_SCHEME_CD, '~')
 OR COALESCE(TGT.DIRECTION_CD, '~') <> COALESCE(SRC.DIRECTION_CD, '~')
 OR COALESCE(TGT.CASH_IND, '~') <> COALESCE(SRC.CASH_IND, '~')
 OR COALESCE(TGT.XBORDER_IND, '~') <> COALESCE(SRC.XBORDER_IND, '~'))
WHEN MATCHED THEN UPDATE SET END_DT = CAST(SRC.TMS AS DATE) - 1, CO_UPD_TMS = CAST(SRC.TMS AS TIMESTAMP_NTZ);


-- Converted the bounded Teradata VARCHAR cast to a Databricks STRING cast for operational logging.
SELECT 'CLOSED ' || TRIM(CAST(COUNT(*) AS STRING)) || ' VERSIONS IN TXN_TYP'
FROM   db_env.db_ods.TXN_TYP
WHERE  END_DT = (SELECT CAST (TMS AS DATE) - 1 FROM db_env.db_trans_imports.AML_TMS_REFSYS)
;



/**************************************************************************\
* TRANSACTION TYPE: INSERT NEW VERSIONS                                    *
\**************************************************************************/


-- Converted timezone-naive Teradata timestamp expressions to TIMESTAMP_NTZ.
INSERT INTO db_env.db_ods.TXN_TYP
(
       TXN_TYP_CD,
       START_DT,
       END_DT,
       TXN_TYP_DESC,
       PAY_SCHEME_CD,
       DIRECTION_CD,
       CASH_IND,
       XBORDER_IND,
       CO_UPD_TMS
)
SELECT SRC.TXN_TYP_CD,
       CAST ((SELECT TMS FROM db_env.db_trans_imports.AML_TMS_REFSYS) AS DATE),
       DATE '9999-12-31',
       SRC.TXN_TYP_DESC,
       SRC.PAY_SCHEME_CD,
       SRC.DIRECTION_CD,
       SRC.CASH_IND,
       SRC.XBORDER_IND,
       CAST ((SELECT TMS FROM db_env.db_trans_imports.AML_TMS_REFSYS) AS TIMESTAMP_NTZ)
FROM   db_env.db_trans_imports.AML_TXTP   SRC
WHERE  SRC.ACTION_CD <> 'D'
AND    NOT EXISTS
       (SELECT 1
        FROM   db_env.db_ods.TXN_TYP   CUR
        WHERE  CUR.TXN_TYP_CD = SRC.TXN_TYP_CD
        AND    CUR.END_DT = DATE '9999-12-31'
       )
;



/**************************************************************************\
* CHANNEL: RERUN PROTECTION (CHNL)                                         *
* ------------------------------------------------------------------------ *
* Versions opened by an earlier run of today are removed and the version   *
* they superseded is re-opened, so that the step can be re-executed.       *
\**************************************************************************/


DELETE FROM db_env.db_ods.CHNL
WHERE  START_DT = (SELECT CAST (TMS AS DATE) FROM db_env.db_trans_imports.AML_TMS_REFSYS)
AND    (CHNL_CD) IN (SELECT CHNL_CD FROM db_env.db_trans_imports.AML_CHNL)
;


-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO db_env.db_ods.CHNL AS TGT
USING (SELECT SRC.CHNL_CD, TTS.TMS FROM (SELECT DISTINCT CHNL_CD FROM db_env.db_trans_imports.AML_CHNL) AS SRC CROSS JOIN db_env.db_trans_imports.AML_TMS_REFSYS AS TTS) AS SRC
ON TGT.CHNL_CD = SRC.CHNL_CD AND TGT.END_DT = CAST(SRC.TMS AS DATE) - 1
WHEN MATCHED THEN UPDATE SET END_DT = DATE '9999-12-31';


/**************************************************************************\
* CHANNEL: CLOSE CHANGED AND DELETED VERSIONS                              *
\**************************************************************************/


-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO db_env.db_ods.CHNL AS TGT
USING (SELECT SRC.*, TTS.TMS FROM db_env.db_trans_imports.AML_CHNL AS SRC CROSS JOIN db_env.db_trans_imports.AML_TMS_REFSYS AS TTS) AS SRC
ON TGT.CHNL_CD = SRC.CHNL_CD AND TGT.END_DT = DATE '9999-12-31'
AND (SRC.ACTION_CD = 'D'
 OR COALESCE(TGT.CHNL_DESC, '~') <> COALESCE(SRC.CHNL_DESC, '~')
 OR COALESCE(TGT.DIGITAL_IND, '~') <> COALESCE(SRC.DIGITAL_IND, '~'))
WHEN MATCHED THEN UPDATE SET END_DT = CAST(SRC.TMS AS DATE) - 1, CO_UPD_TMS = CAST(SRC.TMS AS TIMESTAMP_NTZ);


-- Converted the bounded Teradata VARCHAR cast to a Databricks STRING cast for operational logging.
SELECT 'CLOSED ' || TRIM(CAST(COUNT(*) AS STRING)) || ' VERSIONS IN CHNL'
FROM   db_env.db_ods.CHNL
WHERE  END_DT = (SELECT CAST (TMS AS DATE) - 1 FROM db_env.db_trans_imports.AML_TMS_REFSYS)
;



/**************************************************************************\
* CHANNEL: INSERT NEW VERSIONS                                             *
\**************************************************************************/


-- Converted timezone-naive Teradata timestamp expressions to TIMESTAMP_NTZ.
INSERT INTO db_env.db_ods.CHNL
(
       CHNL_CD,
       START_DT,
       END_DT,
       CHNL_DESC,
       DIGITAL_IND,
       CO_UPD_TMS
)
SELECT SRC.CHNL_CD,
       CAST ((SELECT TMS FROM db_env.db_trans_imports.AML_TMS_REFSYS) AS DATE),
       DATE '9999-12-31',
       SRC.CHNL_DESC,
       SRC.DIGITAL_IND,
       CAST ((SELECT TMS FROM db_env.db_trans_imports.AML_TMS_REFSYS) AS TIMESTAMP_NTZ)
FROM   db_env.db_trans_imports.AML_CHNL   SRC
WHERE  SRC.ACTION_CD <> 'D'
AND    NOT EXISTS
       (SELECT 1
        FROM   db_env.db_ods.CHNL   CUR
        WHERE  CUR.CHNL_CD = SRC.CHNL_CD
        AND    CUR.END_DT = DATE '9999-12-31'
       )
;



/**************************************************************************\
* PRODUCT: RERUN PROTECTION (PRDT)                                         *
* ------------------------------------------------------------------------ *
* Versions opened by an earlier run of today are removed and the version   *
* they superseded is re-opened, so that the step can be re-executed.       *
\**************************************************************************/


DELETE FROM db_env.db_ods.PRDT
WHERE  START_DT = (SELECT CAST (TMS AS DATE) FROM db_env.db_trans_imports.AML_TMS_REFSYS)
AND    (PRDT_CD) IN (SELECT PRDT_CD FROM db_env.db_trans_imports.AML_PRDT)
;


-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO db_env.db_ods.PRDT AS TGT
USING (SELECT SRC.PRDT_CD, TTS.TMS FROM (SELECT DISTINCT PRDT_CD FROM db_env.db_trans_imports.AML_PRDT) AS SRC CROSS JOIN db_env.db_trans_imports.AML_TMS_REFSYS AS TTS) AS SRC
ON TGT.PRDT_CD = SRC.PRDT_CD AND TGT.END_DT = CAST(SRC.TMS AS DATE) - 1
WHEN MATCHED THEN UPDATE SET END_DT = DATE '9999-12-31';


/**************************************************************************\
* PRODUCT: CLOSE CHANGED AND DELETED VERSIONS                              *
\**************************************************************************/


-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO db_env.db_ods.PRDT AS TGT
USING (SELECT SRC.*, TTS.TMS FROM db_env.db_trans_imports.AML_PRDT AS SRC CROSS JOIN db_env.db_trans_imports.AML_TMS_REFSYS AS TTS) AS SRC
ON TGT.PRDT_CD = SRC.PRDT_CD AND TGT.END_DT = DATE '9999-12-31'
AND (SRC.ACTION_CD = 'D'
 OR COALESCE(TGT.PRDT_DESC, '~') <> COALESCE(SRC.PRDT_DESC, '~')
 OR COALESCE(TGT.PRDT_FAMILY_CD, '~') <> COALESCE(SRC.PRDT_FAMILY_CD, '~')
 OR COALESCE(TGT.SEGMENT_CD, '~') <> COALESCE(SRC.SEGMENT_CD, '~')
 OR COALESCE(TGT.PRDT_RISK_CD, '~') <> COALESCE(SRC.PRDT_RISK_CD, '~'))
WHEN MATCHED THEN UPDATE SET END_DT = CAST(SRC.TMS AS DATE) - 1, CO_UPD_TMS = CAST(SRC.TMS AS TIMESTAMP_NTZ);


-- Converted the bounded Teradata VARCHAR cast to a Databricks STRING cast for operational logging.
SELECT 'CLOSED ' || TRIM(CAST(COUNT(*) AS STRING)) || ' VERSIONS IN PRDT'
FROM   db_env.db_ods.PRDT
WHERE  END_DT = (SELECT CAST (TMS AS DATE) - 1 FROM db_env.db_trans_imports.AML_TMS_REFSYS)
;



/**************************************************************************\
* PRODUCT: INSERT NEW VERSIONS                                             *
\**************************************************************************/


-- Converted timezone-naive Teradata timestamp expressions to TIMESTAMP_NTZ.
INSERT INTO db_env.db_ods.PRDT
(
       PRDT_CD,
       START_DT,
       END_DT,
       PRDT_DESC,
       PRDT_FAMILY_CD,
       SEGMENT_CD,
       PRDT_RISK_CD,
       CO_UPD_TMS
)
SELECT SRC.PRDT_CD,
       CAST ((SELECT TMS FROM db_env.db_trans_imports.AML_TMS_REFSYS) AS DATE),
       DATE '9999-12-31',
       SRC.PRDT_DESC,
       SRC.PRDT_FAMILY_CD,
       SRC.SEGMENT_CD,
       SRC.PRDT_RISK_CD,
       CAST ((SELECT TMS FROM db_env.db_trans_imports.AML_TMS_REFSYS) AS TIMESTAMP_NTZ)
FROM   db_env.db_trans_imports.AML_PRDT   SRC
WHERE  SRC.ACTION_CD <> 'D'
AND    NOT EXISTS
       (SELECT 1
        FROM   db_env.db_ods.PRDT   CUR
        WHERE  CUR.PRDT_CD = SRC.PRDT_CD
        AND    CUR.END_DT = DATE '9999-12-31'
       )
;



/**************************************************************************\
* OCCUPATION / INDUSTRY: RERUN PROTECTION (SIC_OCCP)                       *
* ------------------------------------------------------------------------ *
* Versions opened by an earlier run of today are removed and the version   *
* they superseded is re-opened, so that the step can be re-executed.       *
\**************************************************************************/


DELETE FROM db_env.db_ods.SIC_OCCP
WHERE  START_DT = (SELECT CAST (TMS AS DATE) FROM db_env.db_trans_imports.AML_TMS_REFSYS)
AND    (SIC_CD) IN (SELECT SIC_CD FROM db_env.db_trans_imports.AML_OCCP)
;


-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO db_env.db_ods.SIC_OCCP AS TGT
USING (SELECT SRC.SIC_CD, TTS.TMS FROM (SELECT DISTINCT SIC_CD FROM db_env.db_trans_imports.AML_OCCP) AS SRC CROSS JOIN db_env.db_trans_imports.AML_TMS_REFSYS AS TTS) AS SRC
ON TGT.SIC_CD = SRC.SIC_CD AND TGT.END_DT = CAST(SRC.TMS AS DATE) - 1
WHEN MATCHED THEN UPDATE SET END_DT = DATE '9999-12-31';


/**************************************************************************\
* OCCUPATION / INDUSTRY: CLOSE CHANGED AND DELETED VERSIONS                *
\**************************************************************************/


-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO db_env.db_ods.SIC_OCCP AS TGT
USING (SELECT SRC.*, TTS.TMS FROM db_env.db_trans_imports.AML_OCCP AS SRC CROSS JOIN db_env.db_trans_imports.AML_TMS_REFSYS AS TTS) AS SRC
ON TGT.SIC_CD = SRC.SIC_CD AND TGT.END_DT = DATE '9999-12-31'
AND (SRC.ACTION_CD = 'D'
 OR COALESCE(TGT.SIC_DESC, '~') <> COALESCE(SRC.SIC_DESC, '~')
 OR COALESCE(TGT.SIC_RISK_CD, '~') <> COALESCE(SRC.SIC_RISK_CD, '~')
 OR COALESCE(TGT.CASH_INTENSIVE_IND, '~') <> COALESCE(SRC.CASH_INTENSIVE_IND, '~'))
WHEN MATCHED THEN UPDATE SET END_DT = CAST(SRC.TMS AS DATE) - 1, CO_UPD_TMS = CAST(SRC.TMS AS TIMESTAMP_NTZ);


-- Converted the bounded Teradata VARCHAR cast to a Databricks STRING cast for operational logging.
SELECT 'CLOSED ' || TRIM(CAST(COUNT(*) AS STRING)) || ' VERSIONS IN SIC_OCCP'
FROM   db_env.db_ods.SIC_OCCP
WHERE  END_DT = (SELECT CAST (TMS AS DATE) - 1 FROM db_env.db_trans_imports.AML_TMS_REFSYS)
;



/**************************************************************************\
* OCCUPATION / INDUSTRY: INSERT NEW VERSIONS                               *
\**************************************************************************/


-- Converted timezone-naive Teradata timestamp expressions to TIMESTAMP_NTZ.
INSERT INTO db_env.db_ods.SIC_OCCP
(
       SIC_CD,
       START_DT,
       END_DT,
       SIC_DESC,
       SIC_RISK_CD,
       CASH_INTENSIVE_IND,
       CO_UPD_TMS
)
SELECT SRC.SIC_CD,
       CAST ((SELECT TMS FROM db_env.db_trans_imports.AML_TMS_REFSYS) AS DATE),
       DATE '9999-12-31',
       SRC.SIC_DESC,
       SRC.SIC_RISK_CD,
       SRC.CASH_INTENSIVE_IND,
       CAST ((SELECT TMS FROM db_env.db_trans_imports.AML_TMS_REFSYS) AS TIMESTAMP_NTZ)
FROM   db_env.db_trans_imports.AML_OCCP   SRC
WHERE  SRC.ACTION_CD <> 'D'
AND    NOT EXISTS
       (SELECT 1
        FROM   db_env.db_ods.SIC_OCCP   CUR
        WHERE  CUR.SIC_CD = SRC.SIC_CD
        AND    CUR.END_DT = DATE '9999-12-31'
       )
;



/**************************************************************************\
* TRANSACTION MONITORING RULE PARAMETERS: RERUN PROTECTION (TM_RULE_PARAM) *
* ------------------------------------------------------------------------ *
* Versions opened by an earlier run of today are removed and the version   *
* they superseded is re-opened, so that the step can be re-executed.       *
\**************************************************************************/


-- Converted multi-column IN to correlated EXISTS for Databricks SQL.
DELETE FROM db_env.db_ods.TM_RULE_PARAM AS TGT
WHERE TGT.START_DT = (SELECT CAST(TMS AS DATE) FROM db_env.db_trans_imports.AML_TMS_REFSYS)
AND EXISTS (
  SELECT 1
  FROM db_env.db_trans_imports.AML_RULE AS SRC
  WHERE SRC.RULE_CD = TGT.RULE_CD
    AND SRC.SEGMENT_CD = TGT.SEGMENT_CD
);


-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO db_env.db_ods.TM_RULE_PARAM AS TGT
USING (SELECT SRC.RULE_CD, SRC.SEGMENT_CD, TTS.TMS FROM (SELECT DISTINCT RULE_CD, SEGMENT_CD FROM db_env.db_trans_imports.AML_RULE) AS SRC CROSS JOIN db_env.db_trans_imports.AML_TMS_REFSYS AS TTS) AS SRC
ON TGT.RULE_CD = SRC.RULE_CD AND TGT.SEGMENT_CD = SRC.SEGMENT_CD AND TGT.END_DT = CAST(SRC.TMS AS DATE) - 1
WHEN MATCHED THEN UPDATE SET END_DT = DATE '9999-12-31';


/**************************************************************************\
* TRANSACTION MONITORING RULE PARAMETERS: CLOSE CHANGED AND DELETED VERSIONS *
\**************************************************************************/


-- Converted Teradata UPDATE FROM to Delta MERGE.
MERGE INTO db_env.db_ods.TM_RULE_PARAM AS TGT
USING (SELECT SRC.*, TTS.TMS FROM db_env.db_trans_imports.AML_RULE AS SRC CROSS JOIN db_env.db_trans_imports.AML_TMS_REFSYS AS TTS) AS SRC
ON TGT.RULE_CD = SRC.RULE_CD AND TGT.SEGMENT_CD = SRC.SEGMENT_CD AND TGT.END_DT = DATE '9999-12-31'
AND (SRC.ACTION_CD = 'D'
 OR COALESCE(TGT.AMT_THRESHOLD, -1) <> COALESCE(SRC.AMT_THRESHOLD, -1)
 OR COALESCE(TGT.CNT_THRESHOLD, -1) <> COALESCE(SRC.CNT_THRESHOLD, -1)
 OR COALESCE(TGT.LOOKBACK_DAYS, -1) <> COALESCE(SRC.LOOKBACK_DAYS, -1)
 OR COALESCE(TGT.PCT_THRESHOLD, -1) <> COALESCE(SRC.PCT_THRESHOLD, -1)
 OR COALESCE(TGT.SCORE_WEIGHT, -1) <> COALESCE(SRC.SCORE_WEIGHT, -1)
 OR COALESCE(TGT.ACTIVE_IND, '~') <> COALESCE(SRC.ACTIVE_IND, '~')
 OR COALESCE(TGT.RULE_DESC, '~') <> COALESCE(SRC.RULE_DESC, '~'))
WHEN MATCHED THEN UPDATE SET END_DT = CAST(SRC.TMS AS DATE) - 1, CO_UPD_TMS = CAST(SRC.TMS AS TIMESTAMP_NTZ);


-- Converted the bounded Teradata VARCHAR cast to a Databricks STRING cast for operational logging.
SELECT 'CLOSED ' || TRIM(CAST(COUNT(*) AS STRING)) || ' VERSIONS IN TM_RULE_PARAM'
FROM   db_env.db_ods.TM_RULE_PARAM
WHERE  END_DT = (SELECT CAST (TMS AS DATE) - 1 FROM db_env.db_trans_imports.AML_TMS_REFSYS)
;



/**************************************************************************\
* TRANSACTION MONITORING RULE PARAMETERS: INSERT NEW VERSIONS              *
\**************************************************************************/


-- Converted timezone-naive Teradata timestamp expressions to TIMESTAMP_NTZ.
INSERT INTO db_env.db_ods.TM_RULE_PARAM
(
       RULE_CD,
       SEGMENT_CD,
       START_DT,
       END_DT,
       AMT_THRESHOLD,
       CNT_THRESHOLD,
       LOOKBACK_DAYS,
       PCT_THRESHOLD,
       SCORE_WEIGHT,
       ACTIVE_IND,
       RULE_DESC,
       CO_UPD_TMS
)
SELECT SRC.RULE_CD,
       SRC.SEGMENT_CD,
       CAST ((SELECT TMS FROM db_env.db_trans_imports.AML_TMS_REFSYS) AS DATE),
       DATE '9999-12-31',
       SRC.AMT_THRESHOLD,
       SRC.CNT_THRESHOLD,
       SRC.LOOKBACK_DAYS,
       SRC.PCT_THRESHOLD,
       SRC.SCORE_WEIGHT,
       SRC.ACTIVE_IND,
       SRC.RULE_DESC,
       CAST ((SELECT TMS FROM db_env.db_trans_imports.AML_TMS_REFSYS) AS TIMESTAMP_NTZ)
FROM   db_env.db_trans_imports.AML_RULE   SRC
WHERE  SRC.ACTION_CD <> 'D'
AND    NOT EXISTS
       (SELECT 1
        FROM   db_env.db_ods.TM_RULE_PARAM   CUR
        WHERE  CUR.RULE_CD = SRC.RULE_CD
        AND    CUR.SEGMENT_CD = SRC.SEGMENT_CD
        AND    CUR.END_DT = DATE '9999-12-31'
       )
;



/**************************************************************************\
* FX RATES: APPLY THE DELIVERED RATES                                      *
* ------------------------------------------------------------------------ *
* FX rates are not versioned - one rate per currency, date and rate type.  *
* Corrections overwrite the previously delivered rate.                     *
\**************************************************************************/


-- Preserved the supported MERGE and mapped its timezone-naive timestamp expression to TIMESTAMP_NTZ.
MERGE INTO db_env.db_ods.FX_RATE AS TGT
USING
(
       SELECT FXR.CCY_CD,
              FXR.RATE_DT,
              FXR.RATE_TYP_CD,
              FXR.GBP_RATE,
              CAST (TTS.TMS AS TIMESTAMP_NTZ)   AS LOAD_TMS
       FROM   db_env.db_trans_imports.AML_FXRT   FXR
              CROSS JOIN
              db_env.db_trans_imports.AML_TMS_REFSYS   TTS
       WHERE  FXR.ACTION_CD <> 'D'
       AND    FXR.GBP_RATE   > 0
)   SRC
   ON  TGT.CCY_CD      = SRC.CCY_CD
   AND TGT.RATE_DT     = SRC.RATE_DT
   AND TGT.RATE_TYP_CD = SRC.RATE_TYP_CD
WHEN MATCHED THEN UPDATE
SET    GBP_RATE   = SRC.GBP_RATE,
       CO_UPD_TMS = SRC.LOAD_TMS
WHEN NOT MATCHED THEN INSERT
(
       CCY_CD,
       RATE_DT,
       RATE_TYP_CD,
       GBP_RATE,
       CO_UPD_TMS
)
VALUES
(
       SRC.CCY_CD,
       SRC.RATE_DT,
       SRC.RATE_TYP_CD,
       SRC.GBP_RATE,
       SRC.LOAD_TMS
)
;


/**************************************************************************\
* FX RATES: REMOVE WITHDRAWN RATES                                         *
\**************************************************************************/


-- Converted multi-column IN to correlated EXISTS for Databricks SQL.
DELETE FROM db_env.db_ods.FX_RATE AS TGT
WHERE EXISTS (
  SELECT 1
  FROM db_env.db_trans_imports.AML_FXRT AS SRC
  WHERE SRC.ACTION_CD = 'D'
    AND SRC.CCY_CD = TGT.CCY_CD
    AND SRC.RATE_DT = TGT.RATE_DT
    AND SRC.RATE_TYP_CD = TGT.RATE_TYP_CD
);


/**************************************************************************\
* FX RATES: GBP BASE RATE                                                  *
* ------------------------------------------------------------------------ *
* GBP is the reporting currency and is never delivered by REFSYS.          *
\**************************************************************************/


-- Converted timezone-naive Teradata timestamp expressions to TIMESTAMP_NTZ.
INSERT INTO db_env.db_ods.FX_RATE
(
       CCY_CD,
       RATE_DT,
       RATE_TYP_CD,
       GBP_RATE,
       CO_UPD_TMS
)
SELECT 'GBP',
       CAST (TTS.TMS AS DATE),
       'SP',
       1.00000000,
       CAST (TTS.TMS AS TIMESTAMP_NTZ)
FROM   db_env.db_trans_imports.AML_TMS_REFSYS   TTS
WHERE  NOT EXISTS
       (SELECT 1
        FROM   db_env.db_ods.FX_RATE   FXR
        WHERE  FXR.CCY_CD      = 'GBP'
        AND    FXR.RATE_DT     = CAST (TTS.TMS AS DATE)
        AND    FXR.RATE_TYP_CD = 'SP'
       )
;



/**************************************************************************\
* FX RATES: PURGE RATES OLDER THAN SEVEN YEARS                             *
* ------------------------------------------------------------------------ *
* Retention aligned to the Money Laundering Regulations 2017 record keeping *
* requirement (5 years) plus two years contingency.                        *
\**************************************************************************/


DELETE FROM db_env.db_ods.FX_RATE
WHERE  RATE_DT < ADD_MONTHS (CURRENT_DATE, -84)
;


/**************************************************************************\
* RULE PARAMETERS: ENSURE A DEFAULT SEGMENT EXISTS FOR EVERY RULE          *
* ------------------------------------------------------------------------ *
* The rule engine (amlmon.20) falls back to segment ALL when no segment    *
* specific threshold exists. Log rules without an ALL row.                 *
\**************************************************************************/

SELECT RULE_CD
FROM   db_env.db_ods.TM_RULE_PARAM
WHERE  END_DT = DATE '9999-12-31'
GROUP  BY RULE_CD
HAVING SUM (CASE WHEN SEGMENT_CD = 'ALL' THEN 1 ELSE 0 END) = 0
;


/**************************************************************************\
* END OF SCRIPT                                                            *
\**************************************************************************/

