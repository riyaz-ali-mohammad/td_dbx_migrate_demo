.set WIDTH       300;
.set TITLEDASHES OFF;


/**************************************************************************\
* TAKE A TIMESTAMP SNAPSHOT                                                *
\**************************************************************************/

DELETE FROM <DB_ENV>DB_TRANS_IMPORTS.AML_TMS_SANCSYS
;
.if errorcode <> 0 then .quit errorcode;


INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.AML_TMS_SANCSYS
(
       SSQ_ID,
       TMS
)
VALUES
(
       1,
       CURRENT_TIMESTAMP(0)
)
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* REMOVE HEADING AND NON NUMERIC GROUP ROWS                                *
* ------------------------------------------------------------------------ *
* The OFSI style list repeats the heading line when files are concatenated. *
\**************************************************************************/


DELETE FROM <DB_ENV>DB_TRANS_IMPORTS.AML_SANCSYS_RAW
WHERE  TRIM (COALESCE (GROUP_ID, '')) = ''
OR     TRIM (OTRANSLATE (GROUP_ID, '0123456789', '          ')) <> ''
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.AML_SANCSYS_RAW INDEX (GROUP_ID);


/**************************************************************************\
* TRUNCATED FILE PROTECTION                                                *
* ------------------------------------------------------------------------ *
* The list is a FULL delivery. If it contains less than half of the currently *
* active designations the file is assumed truncated and the run is aborted *
* (otherwise every missing designation would be delisted).                 *
\**************************************************************************/

SELECT STG.STG_CNT,
       ACT.ACT_CNT
FROM   (SELECT COUNT (DISTINCT GROUP_ID)   AS STG_CNT
        FROM   <DB_ENV>DB_TRANS_IMPORTS.AML_SANCSYS_RAW
       )   STG
       CROSS JOIN
       (SELECT COUNT(*)   AS ACT_CNT
        FROM   <DB_ENV>DB_ODS.SANC_ENTITY
        WHERE  ACTIVE_IND = 'Y'
       )   ACT
WHERE  STG.STG_CNT < ACT.ACT_CNT * 0.5
;
.if errorcode <> 0 then .quit errorcode;
.if activitycount <> 0 then .quit 12;


/**************************************************************************\
* POPULATE SANC_ENTITY_STG                                                 *
* ------------------------------------------------------------------------ *
* One row per designation (GROUP_ID). Attributes are taken from the primary *
* name row; when no primary name exists the most recently updated row wins. *
* Country names are mapped to ISO 3166 alpha-2 via DB_REFERENCE.CTRY_NAME_XREF. *
\**************************************************************************/

DELETE FROM <DB_ENV>DB_TRANS_IMPORTS.SANC_ENTITY_STG
;
.if errorcode <> 0 then .quit errorcode;


INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.SANC_ENTITY_STG
(
       GROUP_ID,
       GROUP_TYP_CD,
       REGIME_NM,
       LISTED_DT,
       LAST_UPD_DT,
       UK_SANC_REF,
       BIRTH_DT,
       NATIONALITY_CTRY_NM,
       NATIONALITY_CTRY_CD,
       ADDR_CTRY_NM,
       ADDR_CTRY_CD,
       PASSPORT_NR
)
SELECT CAST (TRIM (RAW.GROUP_ID) AS INTEGER),
       CASE UPPER (TRIM (RAW.GROUP_TYPE))
            WHEN 'INDIVIDUAL' THEN 'I'
            WHEN 'ENTITY'     THEN 'E'
            WHEN 'SHIP'       THEN 'S'
            ELSE 'E'
       END,
       NULLIF (TRIM (RAW.REGIME), ''),
       CASE WHEN TRIM (RAW.LISTED_ON) LIKE '__/__/____'
             AND SUBSTR (TRIM (RAW.LISTED_ON), 1, 2) <> '00'
             AND SUBSTR (TRIM (RAW.LISTED_ON), 4, 2) <> '00'
            THEN CAST (TRIM (RAW.LISTED_ON) AS DATE FORMAT 'DD/MM/YYYY')
            ELSE NULL
       END,
       CASE WHEN TRIM (RAW.LAST_UPDATED) LIKE '__/__/____'
             AND SUBSTR (TRIM (RAW.LAST_UPDATED), 1, 2) <> '00'
             AND SUBSTR (TRIM (RAW.LAST_UPDATED), 4, 2) <> '00'
            THEN CAST (TRIM (RAW.LAST_UPDATED) AS DATE FORMAT 'DD/MM/YYYY')
            ELSE NULL
       END,
       NULLIF (TRIM (RAW.UK_SANC_LIST_REF), ''),
       CASE WHEN TRIM (RAW.DOB) LIKE '__/__/____'
             AND SUBSTR (TRIM (RAW.DOB), 1, 2) <> '00'
             AND SUBSTR (TRIM (RAW.DOB), 4, 2) <> '00'
            THEN CAST (TRIM (RAW.DOB) AS DATE FORMAT 'DD/MM/YYYY')
            ELSE NULL
       END,
       NULLIF (TRIM (RAW.NATIONALITY), ''),
       NAT.CTRY_2_CD,
       NULLIF (TRIM (RAW.ADDR_CTRY), ''),
       ADR.CTRY_2_CD,
       NULLIF (TRIM (RAW.PASSPORT_NR), '')
FROM   <DB_ENV>DB_TRANS_IMPORTS.AML_SANCSYS_RAW   RAW
       LEFT OUTER JOIN
       <DB_ENV>DB_REFERENCE.CTRY_NAME_XREF   NAT
          ON  NAT.CTRY_NM_TXT = UPPER (TRIM (RAW.NATIONALITY))
       LEFT OUTER JOIN
       <DB_ENV>DB_REFERENCE.CTRY_NAME_XREF   ADR
          ON  ADR.CTRY_NM_TXT = UPPER (TRIM (RAW.ADDR_CTRY))
QUALIFY SUM (1) OVER (PARTITION BY  RAW.GROUP_ID
                          ORDER BY  CASE WHEN UPPER (TRIM (RAW.ALIAS_TYPE)) = 'PRIMARY NAME' THEN 1 ELSE 2 END
                                   ,CASE WHEN TRIM (RAW.LAST_UPDATED) LIKE '__/__/____'
                                         THEN SUBSTR (TRIM (RAW.LAST_UPDATED), 7, 4) ||
                                              SUBSTR (TRIM (RAW.LAST_UPDATED), 4, 2) ||
                                              SUBSTR (TRIM (RAW.LAST_UPDATED), 1, 2)
                                         ELSE '00000000'
                                    END DESC
                                   ,RAW.NAME_6
                      ROWS UNBOUNDED PRECEDING
                     )  =  1
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* MAP NATIONALITY VIA REGIME FOR UNMAPPED STATE BODIES                     *
* ------------------------------------------------------------------------ *
* Entities of a comprehensive country regime without an address country are *
* assigned the regime country (e.g. state owned banks).                    *
\**************************************************************************/


UPDATE STG
FROM   <DB_ENV>DB_TRANS_IMPORTS.SANC_ENTITY_STG        STG,
       <DB_ENV>DB_REFERENCE.SANC_REGIME_CTRY    RGM
SET    ADDR_CTRY_CD = RGM.CTRY_2_CD
WHERE  STG.REGIME_NM         = RGM.REGIME_NM
AND    RGM.COMPREHENSIVE_IND = 'Y'
AND    STG.ADDR_CTRY_CD     IS NULL
AND    STG.GROUP_TYP_CD      = 'E'
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.SANC_ENTITY_STG INDEX (GROUP_ID);


/**************************************************************************\
* POPULATE SANC_NAME_STG                                                   *
* ------------------------------------------------------------------------ *
* FULL_NM = name 1..5 followed by name 6 (surname / entity name).          *
* NORM_NM = shared screening normalisation (see kycref.55 / dailytxn.08).  *
* Duplicate names within a designation are removed.                        *
\**************************************************************************/

DELETE FROM <DB_ENV>DB_TRANS_IMPORTS.SANC_NAME_STG
;
.if errorcode <> 0 then .quit errorcode;


INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.SANC_NAME_STG
(
       GROUP_ID,
       NAME_SEQ_NR,
       FULL_NM,
       NORM_NM,
       NON_LATIN_NM,
       ALIAS_TYP_CD,
       ALIAS_QUALITY_CD
)
SELECT NMS.GROUP_ID,
       ROW_NUMBER () OVER (PARTITION BY NMS.GROUP_ID
                               ORDER BY NMS.ALIAS_RANK_NR
                                       ,NMS.FULL_NM
                          ),
       NMS.FULL_NM,
       TRIM (OREPLACE (OREPLACE (OTRANSLATE (UPPER (TRIM (NMS.FULL_NM)), '.,''-&/()', '        '), '  ', ' '), '  ', ' ')),
       NMS.NON_LATIN_NM,
       NMS.ALIAS_TYP_CD,
       NMS.ALIAS_QUALITY_CD
FROM
       (SELECT CAST (TRIM (RAW.GROUP_ID) AS INTEGER)   AS GROUP_ID,
               OREPLACE (OREPLACE (TRIM (
                 TRIM (COALESCE (RAW.NAME_1, '')) || ' ' ||
                 TRIM (COALESCE (RAW.NAME_2, '')) || ' ' ||
                 TRIM (COALESCE (RAW.NAME_3, '')) || ' ' ||
                 TRIM (COALESCE (RAW.NAME_4, '')) || ' ' ||
                 TRIM (COALESCE (RAW.NAME_5, '')) || ' ' ||
                 TRIM (COALESCE (RAW.NAME_6, ''))
               ), '  ', ' '), '  ', ' ')   AS FULL_NM,
               NULLIF (TRIM (RAW.NAME_NON_LATIN), '')   AS NON_LATIN_NM,
               CASE WHEN UPPER (TRIM (RAW.ALIAS_TYPE)) = 'PRIMARY NAME'           THEN 'PRI'
                    WHEN UPPER (TRIM (RAW.ALIAS_TYPE)) LIKE 'PRIMARY NAME VARIATION%' THEN 'VAR'
                    WHEN UPPER (TRIM (RAW.ALIAS_TYPE)) LIKE '%VARIATION%'          THEN 'VAR'
                    ELSE 'AKA'
               END   AS ALIAS_TYP_CD,
               CASE UPPER (TRIM (RAW.ALIAS_QUALITY))
                    WHEN 'GOOD' THEN 'G'
                    WHEN 'LOW'  THEN 'L'
                    ELSE 'G'
               END   AS ALIAS_QUALITY_CD,
               CASE WHEN UPPER (TRIM (RAW.ALIAS_TYPE)) = 'PRIMARY NAME' THEN 1
                    WHEN UPPER (TRIM (RAW.ALIAS_TYPE)) LIKE '%VARIATION%' THEN 2
                    ELSE 3
               END   AS ALIAS_RANK_NR
        FROM   <DB_ENV>DB_TRANS_IMPORTS.AML_SANCSYS_RAW   RAW
        QUALIFY SUM (1) OVER (PARTITION BY  RAW.GROUP_ID
                                           ,FULL_NM
                                  ORDER BY  ALIAS_RANK_NR
                              ROWS UNBOUNDED PRECEDING
                             )  =  1
       )   NMS
WHERE  NMS.FULL_NM <> ''
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.SANC_NAME_STG INDEX (GROUP_ID, NAME_SEQ_NR);


/**************************************************************************\
* TOKENISE THE NORMALISED NAMES                                            *
* ------------------------------------------------------------------------ *
* STRTOK_SPLIT_TO_TABLE needs a single in-key: GROUP_ID * 1000 + NAME_SEQ_NR. *
* Noise words (LTD, LIMITED, THE, AL, ...) and single characters are       *
* dropped. Token matching is used by dailytxn.08 for fuzzy screening.      *
\**************************************************************************/


CREATE VOLATILE TABLE VT_SANC_NM_KEY
(
       NM_KEY   BIGINT NOT NULL,
       NORM_NM  VARCHAR(400) CHARACTER SET LATIN NOT CASESPECIFIC
)
PRIMARY INDEX ( NM_KEY )
ON COMMIT PRESERVE ROWS
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO VT_SANC_NM_KEY
SELECT CAST (GROUP_ID AS BIGINT) * 1000 + NAME_SEQ_NR,
       NORM_NM
FROM   <DB_ENV>DB_TRANS_IMPORTS.SANC_NAME_STG
WHERE  NORM_NM IS NOT NULL
;
.if errorcode <> 0 then .quit errorcode;

CREATE VOLATILE TABLE VT_SANC_TOKEN_RAW
(
       NM_KEY        BIGINT NOT NULL,
       TOKEN_SEQ_NR  INTEGER,
       TOKEN_TXT     VARCHAR(400) CHARACTER SET LATIN NOT CASESPECIFIC
)
PRIMARY INDEX ( NM_KEY )
ON COMMIT PRESERVE ROWS
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO VT_SANC_TOKEN_RAW
SELECT TOK.NM_KEY,
       TOK.TOKEN_SEQ_NR,
       TOK.TOKEN_TXT
FROM   TABLE (STRTOK_SPLIT_TO_TABLE (VT_SANC_NM_KEY.NM_KEY,
                                     VT_SANC_NM_KEY.NORM_NM,
                                     ' ')
              RETURNS (NM_KEY        BIGINT,
                       TOKEN_SEQ_NR  INTEGER,
                       TOKEN_TXT     VARCHAR(400) CHARACTER SET LATIN)
             )   TOK
;
.if errorcode <> 0 then .quit errorcode;
DELETE FROM <DB_ENV>DB_TRANS_IMPORTS.SANC_TOKEN_STG
;
.if errorcode <> 0 then .quit errorcode;


INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.SANC_TOKEN_STG
(
       GROUP_ID,
       NAME_SEQ_NR,
       TOKEN_SEQ_NR,
       TOKEN_TXT
)
SELECT CAST (TRW.NM_KEY / 1000 AS INTEGER),
       CAST (TRW.NM_KEY MOD 1000 AS SMALLINT),
       CAST (TRW.TOKEN_SEQ_NR AS SMALLINT),
       CAST (TRIM (TRW.TOKEN_TXT) AS VARCHAR(60))
FROM   VT_SANC_TOKEN_RAW   TRW
WHERE  CHARACTER_LENGTH (TRIM (TRW.TOKEN_TXT)) >= 2
AND    TRIM (TRW.TOKEN_TXT) NOT IN (SELECT NOISE_WORD FROM <DB_ENV>DB_REFERENCE.NAME_NOISE_WORD)
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.SANC_TOKEN_STG INDEX (GROUP_ID, NAME_SEQ_NR, TOKEN_SEQ_NR);


/**************************************************************************\
* SANCTIONS ENTITY: DETERMINE CHANGES                                      *
* ------------------------------------------------------------------------ *
* N = new designation, U = amended or re-designated, D = delisted (no longer *
* present in the full list).                                               *
\**************************************************************************/


CREATE VOLATILE TABLE VT_SANC_CHG
(
       GROUP_ID    INTEGER NOT NULL,
       CHG_TYP_CD  CHAR(1) CHARACTER SET LATIN NOT CASESPECIFIC NOT NULL
)
UNIQUE PRIMARY INDEX ( GROUP_ID )
ON COMMIT PRESERVE ROWS
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO VT_SANC_CHG
(
       GROUP_ID,
       CHG_TYP_CD
)
SELECT STG.GROUP_ID,
       CASE WHEN CUR.GROUP_ID IS NULL THEN 'N' ELSE 'U' END
FROM   <DB_ENV>DB_TRANS_IMPORTS.SANC_ENTITY_STG   STG
       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.SANC_ENTITY      CUR
          ON  CUR.GROUP_ID = STG.GROUP_ID
WHERE  CUR.GROUP_ID IS NULL
OR     CUR.ACTIVE_IND = 'N'
OR     COALESCE (CUR.GROUP_TYP_CD, '~') <> COALESCE (STG.GROUP_TYP_CD, '~')
OR     COALESCE (CUR.REGIME_NM, '~') <> COALESCE (STG.REGIME_NM, '~')
OR     COALESCE (CUR.LISTED_DT, DATE '0001-01-01') <> COALESCE (STG.LISTED_DT, DATE '0001-01-01')
OR     COALESCE (CUR.LAST_UPD_DT, DATE '0001-01-01') <> COALESCE (STG.LAST_UPD_DT, DATE '0001-01-01')
OR     COALESCE (CUR.UK_SANC_REF, '~') <> COALESCE (STG.UK_SANC_REF, '~')
OR     COALESCE (CUR.BIRTH_DT, DATE '0001-01-01') <> COALESCE (STG.BIRTH_DT, DATE '0001-01-01')
OR     COALESCE (CUR.NATIONALITY_CTRY_CD, '~') <> COALESCE (STG.NATIONALITY_CTRY_CD, '~')
OR     COALESCE (CUR.ADDR_CTRY_CD, '~') <> COALESCE (STG.ADDR_CTRY_CD, '~')

UNION ALL

SELECT CUR.GROUP_ID,
       'D'
FROM   <DB_ENV>DB_ODS.SANC_ENTITY   CUR
WHERE  CUR.ACTIVE_IND = 'Y'
AND    CUR.GROUP_ID NOT IN (SELECT GROUP_ID FROM <DB_ENV>DB_TRANS_IMPORTS.SANC_ENTITY_STG)
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS VT_SANC_CHG COLUMN (GROUP_ID);


/**************************************************************************\
* SANCTIONS ENTITY: CLOSE THE OPEN HISTORY VERSION                         *
\**************************************************************************/


UPDATE HST
FROM   <DB_ENV>DB_ODS.SANC_ENTITY_HIST   HST,
       VT_SANC_CHG              CHG,
       <DB_ENV>DB_TRANS_IMPORTS.AML_TMS_SANCSYS   TTS
SET    END_DT     = CASE WHEN HST.START_DT < CAST (TTS.TMS AS DATE)
                         THEN CAST (TTS.TMS AS DATE) - 1
                         ELSE CAST (TTS.TMS AS DATE)
                    END,
       CO_UPD_TMS = CAST (TTS.TMS AS TIMESTAMP(0))
WHERE  HST.GROUP_ID = CHG.GROUP_ID
AND    HST.END_DT  IS NULL
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* SANCTIONS ENTITY: WRITE HISTORY VERSIONS                                 *
\**************************************************************************/


INSERT INTO <DB_ENV>DB_ODS.SANC_ENTITY_HIST
(
       GROUP_ID,
       START_DT,
       UPD_TMS,
       END_DT,
       GROUP_TYP_CD,
       REGIME_NM,
       LISTED_DT,
       LAST_UPD_DT,
       UK_SANC_REF,
       BIRTH_DT,
       NATIONALITY_CTRY_CD,
       ADDR_CTRY_CD,
       ACTION_CD,
       CO_UPD_TMS
)
SELECT STG.GROUP_ID,
       CAST (TTS.TMS AS DATE),
       CAST (TTS.TMS AS TIMESTAMP(0)),
       NULL,
       STG.GROUP_TYP_CD,
       STG.REGIME_NM,
       STG.LISTED_DT,
       STG.LAST_UPD_DT,
       STG.UK_SANC_REF,
       STG.BIRTH_DT,
       STG.NATIONALITY_CTRY_CD,
       STG.ADDR_CTRY_CD,
       CHG.CHG_TYP_CD,
       CAST (TTS.TMS AS TIMESTAMP(0))
FROM   <DB_ENV>DB_TRANS_IMPORTS.SANC_ENTITY_STG   STG
       INNER JOIN
       VT_SANC_CHG            CHG
          ON  CHG.GROUP_ID   = STG.GROUP_ID
          AND CHG.CHG_TYP_CD IN ('N', 'U')
       CROSS JOIN
       <DB_ENV>DB_TRANS_IMPORTS.AML_TMS_SANCSYS   TTS

UNION ALL

SELECT CUR.GROUP_ID,
       CAST (TTS.TMS AS DATE),
       CAST (TTS.TMS AS TIMESTAMP(0)),
       CAST (TTS.TMS AS DATE),
       CUR.GROUP_TYP_CD,
       CUR.REGIME_NM,
       CUR.LISTED_DT,
       CUR.LAST_UPD_DT,
       CUR.UK_SANC_REF,
       CUR.BIRTH_DT,
       CUR.NATIONALITY_CTRY_CD,
       CUR.ADDR_CTRY_CD,
       'D',
       CAST (TTS.TMS AS TIMESTAMP(0))
FROM   <DB_ENV>DB_ODS.SANC_ENTITY   CUR
       INNER JOIN
       VT_SANC_CHG         CHG
          ON  CHG.GROUP_ID   = CUR.GROUP_ID
          AND CHG.CHG_TYP_CD = 'D'
       CROSS JOIN
       <DB_ENV>DB_TRANS_IMPORTS.AML_TMS_SANCSYS   TTS
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* SANCTIONS ENTITY: APPLY TO THE CURRENT TABLE                             *
* ------------------------------------------------------------------------ *
* Delisted designations are kept (ACTIVE_IND = 'N') for audit of historic  *
* screening decisions.                                                     *
\**************************************************************************/

BT;


DELETE FROM <DB_ENV>DB_ODS.SANC_ENTITY
WHERE  GROUP_ID IN (SELECT GROUP_ID FROM VT_SANC_CHG WHERE CHG_TYP_CD IN ('N', 'U'))
;
.if errorcode <> 0 then .quit errorcode;


INSERT INTO <DB_ENV>DB_ODS.SANC_ENTITY
(
       GROUP_ID,
       GROUP_TYP_CD,
       REGIME_NM,
       LISTED_DT,
       LAST_UPD_DT,
       UK_SANC_REF,
       BIRTH_DT,
       NATIONALITY_CTRY_CD,
       ADDR_CTRY_CD,
       PASSPORT_NR,
       ACTIVE_IND,
       DELISTED_DT,
       CO_UPD_TMS
)
SELECT STG.GROUP_ID,
       STG.GROUP_TYP_CD,
       STG.REGIME_NM,
       STG.LISTED_DT,
       STG.LAST_UPD_DT,
       STG.UK_SANC_REF,
       STG.BIRTH_DT,
       STG.NATIONALITY_CTRY_CD,
       STG.ADDR_CTRY_CD,
       STG.PASSPORT_NR,
       'Y',
       NULL,
       CAST (TTS.TMS AS TIMESTAMP(0))
FROM   <DB_ENV>DB_TRANS_IMPORTS.SANC_ENTITY_STG   STG
       INNER JOIN
       VT_SANC_CHG            CHG
          ON  CHG.GROUP_ID   = STG.GROUP_ID
          AND CHG.CHG_TYP_CD IN ('N', 'U')
       CROSS JOIN
       <DB_ENV>DB_TRANS_IMPORTS.AML_TMS_SANCSYS   TTS
;
.if errorcode <> 0 then .quit errorcode;


UPDATE ENT
FROM   <DB_ENV>DB_ODS.SANC_ENTITY   ENT,
       VT_SANC_CHG         CHG,
       <DB_ENV>DB_TRANS_IMPORTS.AML_TMS_SANCSYS   TTS
SET    ACTIVE_IND  = 'N',
       DELISTED_DT = CAST (TTS.TMS AS DATE),
       CO_UPD_TMS  = CAST (TTS.TMS AS TIMESTAMP(0))
WHERE  ENT.GROUP_ID   = CHG.GROUP_ID
AND    CHG.CHG_TYP_CD = 'D'
;
.if errorcode <> 0 then .quit errorcode;

ET;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_ODS.SANC_ENTITY INDEX (GROUP_ID);
COLLECT STATISTICS <DB_ENV>DB_ODS.SANC_ENTITY_HIST INDEX (GROUP_ID, START_DT, UPD_TMS);


/**************************************************************************\
* RELOAD SANC_NAME FOR ACTIVE DESIGNATIONS                                 *
* ------------------------------------------------------------------------ *
* TOKEN_CNT = number of distinct significant tokens; used as denominator of *
* the token match score in dailytxn.08.                                    *
\**************************************************************************/

BT;

DELETE FROM <DB_ENV>DB_ODS.SANC_NAME
;
.if errorcode <> 0 then .quit errorcode;


INSERT INTO <DB_ENV>DB_ODS.SANC_NAME
(
       GROUP_ID,
       NAME_SEQ_NR,
       FULL_NM,
       NORM_NM,
       NON_LATIN_NM,
       ALIAS_TYP_CD,
       ALIAS_QUALITY_CD,
       TOKEN_CNT,
       CO_UPD_TMS
)
SELECT NMS.GROUP_ID,
       NMS.NAME_SEQ_NR,
       NMS.FULL_NM,
       NMS.NORM_NM,
       NMS.NON_LATIN_NM,
       NMS.ALIAS_TYP_CD,
       NMS.ALIAS_QUALITY_CD,
       COALESCE (TKC.TOKEN_CNT, 0),
       CAST (TTS.TMS AS TIMESTAMP(0))
FROM   <DB_ENV>DB_TRANS_IMPORTS.SANC_NAME_STG   NMS
       INNER JOIN
       <DB_ENV>DB_ODS.SANC_ENTITY    ENT
          ON  ENT.GROUP_ID   = NMS.GROUP_ID
          AND ENT.ACTIVE_IND = 'Y'
       LEFT OUTER JOIN
       (SELECT GROUP_ID,
               NAME_SEQ_NR,
               COUNT (DISTINCT TOKEN_TXT)   AS TOKEN_CNT
        FROM   <DB_ENV>DB_TRANS_IMPORTS.SANC_TOKEN_STG
        GROUP  BY GROUP_ID,
                  NAME_SEQ_NR
       )   TKC
          ON  TKC.GROUP_ID    = NMS.GROUP_ID
          AND TKC.NAME_SEQ_NR = NMS.NAME_SEQ_NR
       CROSS JOIN
       <DB_ENV>DB_TRANS_IMPORTS.AML_TMS_SANCSYS   TTS
;
.if errorcode <> 0 then .quit errorcode;

ET;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* RELOAD SANC_NAME_TOKEN FOR ACTIVE DESIGNATIONS                           *
* ------------------------------------------------------------------------ *
* Low quality aliases (ALIAS_QUALITY_CD = 'L') are excluded from token     *
* matching to limit false positives; they are still exact matched.         *
\**************************************************************************/

BT;

DELETE FROM <DB_ENV>DB_ODS.SANC_NAME_TOKEN
;
.if errorcode <> 0 then .quit errorcode;


INSERT INTO <DB_ENV>DB_ODS.SANC_NAME_TOKEN
(
       TOKEN_TXT,
       GROUP_ID,
       NAME_SEQ_NR,
       TOKEN_SEQ_NR,
       CO_UPD_TMS
)
SELECT TOK.TOKEN_TXT,
       TOK.GROUP_ID,
       TOK.NAME_SEQ_NR,
       TOK.TOKEN_SEQ_NR,
       CAST (TTS.TMS AS TIMESTAMP(0))
FROM   <DB_ENV>DB_TRANS_IMPORTS.SANC_TOKEN_STG   TOK
       INNER JOIN
       <DB_ENV>DB_ODS.SANC_NAME       NMS
          ON  NMS.GROUP_ID    = TOK.GROUP_ID
          AND NMS.NAME_SEQ_NR = TOK.NAME_SEQ_NR
       CROSS JOIN
       <DB_ENV>DB_TRANS_IMPORTS.AML_TMS_SANCSYS   TTS
WHERE  NMS.ALIAS_QUALITY_CD <> 'L'
;
.if errorcode <> 0 then .quit errorcode;

ET;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_ODS.SANC_NAME INDEX (GROUP_ID, NAME_SEQ_NR);
COLLECT STATISTICS <DB_ENV>DB_ODS.SANC_NAME INDEX (NORM_NM);
COLLECT STATISTICS <DB_ENV>DB_ODS.SANC_NAME_TOKEN INDEX (TOKEN_TXT);


/**************************************************************************\
* EXTRACT SANCTIONED BIC CODES                                             *
* ------------------------------------------------------------------------ *
* OTHER_INFO frequently carries 'BIC: XXXXXXXX' or 'SWIFT/BIC XXXXXXXXXXX'. *
* Both the 8 and 11 character forms are stored as delivered; dailytxn.08   *
* matches on the first 8 characters of the counterparty BIC.               *
\**************************************************************************/

DELETE FROM <DB_ENV>DB_ODS.SANC_BIC
;
.if errorcode <> 0 then .quit errorcode;


INSERT INTO <DB_ENV>DB_ODS.SANC_BIC
(
       BIC_CD,
       GROUP_ID,
       CO_UPD_TMS
)
SELECT DISTINCT
       BIC.BIC_CD,
       BIC.GROUP_ID,
       CAST (TTS.TMS AS TIMESTAMP(0))
FROM
       (SELECT CAST (TRIM (RAW.GROUP_ID) AS INTEGER)   AS GROUP_ID,
               CAST (REGEXP_REPLACE (REGEXP_SUBSTR (UPPER (RAW.OTHER_INFO),
                                                    '(SWIFT/BIC|SWIFT|BIC)[ :/]{1,3}[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?',
                                                    1, 1, 'c'),
                                     '^(SWIFT/BIC|SWIFT|BIC)[ :/]{1,3}', '', 1, 0, 'c')
                     AS CHAR(11))   AS BIC_CD
        FROM   <DB_ENV>DB_TRANS_IMPORTS.AML_SANCSYS_RAW   RAW
        WHERE  INDEX (UPPER (RAW.OTHER_INFO), 'BIC') > 0
        OR     INDEX (UPPER (RAW.OTHER_INFO), 'SWIFT') > 0
       )   BIC
       INNER JOIN
       <DB_ENV>DB_ODS.SANC_ENTITY   ENT
          ON  ENT.GROUP_ID   = BIC.GROUP_ID
          AND ENT.ACTIVE_IND = 'Y'
       CROSS JOIN
       <DB_ENV>DB_TRANS_IMPORTS.AML_TMS_SANCSYS   TTS
WHERE  BIC.BIC_CD IS NOT NULL
AND    TRIM (BIC.BIC_CD) <> ''
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_ODS.SANC_BIC INDEX (BIC_CD, GROUP_ID);


/**************************************************************************\
* REPORT DESIGNATION MOVEMENTS                                             *
\**************************************************************************/

SELECT CHG_TYP_CD,
       COUNT(*)
FROM   VT_SANC_CHG
GROUP  BY CHG_TYP_CD
ORDER  BY CHG_TYP_CD
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* DROP VOLATILE TABLES                                                     *
\**************************************************************************/

DROP TABLE VT_SANC_NM_KEY;
DROP TABLE VT_SANC_TOKEN_RAW;
DROP TABLE VT_SANC_CHG;


/**************************************************************************\
* END OF SCRIPT                                                            *
\**************************************************************************/

.quit 0;
