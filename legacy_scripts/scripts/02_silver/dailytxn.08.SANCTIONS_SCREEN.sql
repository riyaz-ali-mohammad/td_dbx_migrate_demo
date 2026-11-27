.set WIDTH       300;
.set TITLEDASHES OFF;

/**************************************************************************\
* PREPARATION                                                              *
* ------------------------------------------------------------------------ *
* Screening of the daily payments against the UK consolidated sanctions    *
* list (loaded by kycref.15 / kycref.60). Screened are the counterparty,   *
* ordering customer, beneficiary customer and merchant names, the bank     *
* identifier codes of counterparty and intermediary bank, and the          *
* counterparty / bank country against comprehensively sanctioned regimes.  *
\**************************************************************************/

COLLECT STATISTICS <DB_ENV>DB_ODS.SANC_NAME_TOKEN   INDEX (TOKEN_TXT);
COLLECT STATISTICS <DB_ENV>DB_ODS.SANC_NAME         INDEX (GROUP_ID, NAME_SEQ_NR);
COLLECT STATISTICS <DB_ENV>DB_ODS.SANC_NAME         INDEX (NORM_NM);
COLLECT STATISTICS <DB_ENV>DB_ODS.SANC_ENTITY       INDEX (GROUP_ID);
COLLECT STATISTICS <DB_ENV>DB_ODS.SANC_BIC          INDEX (BIC_CD, GROUP_ID);
COLLECT STATISTICS <DB_ENV>DB_REFERENCE.SANC_REGIME_CTRY INDEX (REGIME_NM, CTRY_2_CD);


/**************************************************************************\
* BUILD THE LIST OF NAMES TO BE SCREENED                                   *
* ------------------------------------------------------------------------ *
* Name roles:  CP = counterparty          OR = ordering customer           *
*              BE = beneficiary customer  MR = merchant                    *
*              IB = intermediary bank (BIC only, no name)                  *
* The name normalisation is identical to the one applied to the sanctions  *
* list in kycref.60 - any change has to be made in both places.            *
\**************************************************************************/

DELETE FROM <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_SCREEN_NM
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_SCREEN_NM
(
       TXN_REF,
       SUPPLIER_CD,
       NM_ROLE_CD,
       RAW_NM,
       NORM_NM,
       CTRY_CD,
       BIC_CD
)
SELECT dtl.TXN_REF,
       dtl.SUPPLIER_CD,
       'CP',
       dtl.CPTY_NM,
       NULLIF (TRIM (OREPLACE (OREPLACE (OTRANSLATE (UPPER (TRIM (dtl.CPTY_NM)), '.,''-&/()', '        '), '  ', ' '), '  ', ' ')), ''),
       COALESCE (NULLIF (dtl.CPTY_CTRY, ' '), NULLIF (dtl.CPTY_BANK_CTRY, ' ')),
       NULLIF (dtl.CPTY_BIC, ' ')
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD   dtl
WHERE
       (dtl.CPTY_NM IS NOT NULL OR dtl.CPTY_BIC <> ' ')
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_SCREEN_NM
(
       TXN_REF,
       SUPPLIER_CD,
       NM_ROLE_CD,
       RAW_NM,
       NORM_NM,
       CTRY_CD,
       BIC_CD
)
SELECT dtl.TXN_REF,
       dtl.SUPPLIER_CD,
       'OR',
       dtl.ORDERING_CUST_NM,
       NULLIF (TRIM (OREPLACE (OREPLACE (OTRANSLATE (UPPER (TRIM (dtl.ORDERING_CUST_NM)), '.,''-&/()', '        '), '  ', ' '), '  ', ' ')), ''),
       NULL,
       NULL
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD   dtl
WHERE
       dtl.ORDERING_CUST_NM IS NOT NULL
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_SCREEN_NM
(
       TXN_REF,
       SUPPLIER_CD,
       NM_ROLE_CD,
       RAW_NM,
       NORM_NM,
       CTRY_CD,
       BIC_CD
)
SELECT dtl.TXN_REF,
       dtl.SUPPLIER_CD,
       'BE',
       dtl.BENEF_CUST_NM,
       NULLIF (TRIM (OREPLACE (OREPLACE (OTRANSLATE (UPPER (TRIM (dtl.BENEF_CUST_NM)), '.,''-&/()', '        '), '  ', ' '), '  ', ' ')), ''),
       NULL,
       NULL
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD   dtl
WHERE
       dtl.BENEF_CUST_NM IS NOT NULL
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_SCREEN_NM
(
       TXN_REF,
       SUPPLIER_CD,
       NM_ROLE_CD,
       RAW_NM,
       NORM_NM,
       CTRY_CD,
       BIC_CD
)
SELECT dtl.TXN_REF,
       dtl.SUPPLIER_CD,
       'MR',
       dtl.MERCHANT_NM,
       NULLIF (TRIM (OREPLACE (OREPLACE (OTRANSLATE (UPPER (TRIM (dtl.MERCHANT_NM)), '.,''-&/()', '        '), '  ', ' '), '  ', ' ')), ''),
       NULLIF (dtl.MERCHANT_CTRY, ' '),
       NULL
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD   dtl
WHERE
       dtl.MERCHANT_NM IS NOT NULL
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_SCREEN_NM
(
       TXN_REF,
       SUPPLIER_CD,
       NM_ROLE_CD,
       RAW_NM,
       NORM_NM,
       CTRY_CD,
       BIC_CD
)
SELECT dtl.TXN_REF,
       dtl.SUPPLIER_CD,
       'IB',
       NULL,
       NULL,
       SUBSTR (dtl.INTERMED_BIC, 5, 2),
       dtl.INTERMED_BIC
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD   dtl
WHERE
       dtl.INTERMED_BIC <> ' '
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_SCREEN_NM INDEX (TXN_REF, SUPPLIER_CD, NM_ROLE_CD);
COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_SCREEN_NM COLUMN (NORM_NM);


/**************************************************************************\
* SPLIT THE NORMALISED NAMES INTO TOKENS                                   *
* ------------------------------------------------------------------------ *
* STRTOK_SPLIT_TO_TABLE accepts a single key column, so the business key   *
* is concatenated and split up again afterwards. Noise words (legal forms, *
* titles, articles) and single character tokens are dropped.               *
\**************************************************************************/

CREATE VOLATILE TABLE VT_SCREEN_SRC
(
       SCREEN_KEY    VARCHAR(50)    NOT NULL,
       NORM_NM       VARCHAR(140)
)
PRIMARY INDEX ( SCREEN_KEY )
ON COMMIT PRESERVE ROWS
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO VT_SCREEN_SRC
SELECT TRIM (TXN_REF) || '|' || SUPPLIER_CD || '|' || NM_ROLE_CD,
       NORM_NM
FROM   <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_SCREEN_NM
WHERE  NORM_NM IS NOT NULL
;
.if errorcode <> 0 then .quit errorcode;

DELETE FROM <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_SCREEN_TOKEN
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_SCREEN_TOKEN
(
       TXN_REF,
       SUPPLIER_CD,
       NM_ROLE_CD,
       TOKEN_SEQ_NR,
       TOKEN_TXT
)
SELECT STRTOK (tok.OUTKEY, '|', 1),
       STRTOK (tok.OUTKEY, '|', 2),
       STRTOK (tok.OUTKEY, '|', 3),
       tok.TOKENNUM,
       tok.TOKEN
FROM
       TABLE (STRTOK_SPLIT_TO_TABLE (VT_SCREEN_SRC.SCREEN_KEY,
                                     VT_SCREEN_SRC.NORM_NM,
                                     ' ')
              RETURNS (OUTKEY    VARCHAR(50)  CHARACTER SET LATIN,
                       TOKENNUM  INTEGER,
                       TOKEN     VARCHAR(60)  CHARACTER SET LATIN)
             )                                    tok

       LEFT OUTER JOIN
       <DB_ENV>DB_REFERENCE.NAME_NOISE_WORD       nsw
          ON  nsw.NOISE_WORD = tok.TOKEN
WHERE
       nsw.NOISE_WORD IS NULL
AND    CHARACTER_LENGTH (TRIM (tok.TOKEN)) >= 2
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_SCREEN_TOKEN COLUMN (TOKEN_TXT);
COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_SCREEN_TOKEN COLUMN (TXN_REF, SUPPLIER_CD, NM_ROLE_CD);

DROP TABLE VT_SCREEN_SRC
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* CANDIDATES 1 - EXACT NAME MATCH                                          *
* ------------------------------------------------------------------------ *
* Normalised screened name equals a normalised name or alias of an         *
* active designated person / entity. Score 100.                            *
\**************************************************************************/

DELETE FROM <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_SCREEN_CAND
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_SCREEN_CAND
(
       TXN_REF,
       SUPPLIER_CD,
       NM_ROLE_CD,
       GROUP_ID,
       NAME_SEQ_NR,
       MATCH_TOKEN_CNT,
       SANC_TOKEN_CNT,
       SCREEN_TOKEN_CNT,
       MATCH_TYP_CD,
       MATCH_SCORE
)
SELECT scr.TXN_REF,
       scr.SUPPLIER_CD,
       scr.NM_ROLE_CD,
       snm.GROUP_ID,
       snm.NAME_SEQ_NR,
       snm.TOKEN_CNT,
       snm.TOKEN_CNT,
       snm.TOKEN_CNT,
       'EXACT',
       100.00
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_SCREEN_NM  scr

       INNER JOIN
       <DB_ENV>DB_ODS.SANC_NAME                   snm
          ON  snm.NORM_NM = scr.NORM_NM

       INNER JOIN
       <DB_ENV>DB_ODS.SANC_ENTITY                 sen
          ON  sen.GROUP_ID   = snm.GROUP_ID
          AND sen.ACTIVE_IND = 'Y'
WHERE
       scr.NORM_NM IS NOT NULL
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* CANDIDATES 2 - TOKEN MATCH                                               *
* ------------------------------------------------------------------------ *
* Fuzzy match on name tokens: at least two distinct tokens of the screened *
* name are found in one listed name, and they cover at least 75 percent    *
* of the tokens of the listed name. This catches re-ordered names          *
* (SURNAME FORENAME), additional middle names and added legal forms.       *
* Score = covered percentage, capped at 99 to rank below exact matches.    *
* Low quality aliases (ALIAS_QUALITY_CD = L) need full coverage.           *
\**************************************************************************/

INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_SCREEN_CAND
(
       TXN_REF,
       SUPPLIER_CD,
       NM_ROLE_CD,
       GROUP_ID,
       NAME_SEQ_NR,
       MATCH_TOKEN_CNT,
       SANC_TOKEN_CNT,
       SCREEN_TOKEN_CNT,
       MATCH_TYP_CD,
       MATCH_SCORE
)
SELECT mtc.TXN_REF,
       mtc.SUPPLIER_CD,
       mtc.NM_ROLE_CD,
       mtc.GROUP_ID,
       mtc.NAME_SEQ_NR,
       mtc.MATCH_TOKEN_CNT,
       snm.TOKEN_CNT,
       stc.SCREEN_TOKEN_CNT,
       'TOKEN',
       CASE
          WHEN mtc.MATCH_TOKEN_CNT * 100.00 / snm.TOKEN_CNT >= 99.00
          THEN 99.00
          ELSE CAST (mtc.MATCH_TOKEN_CNT * 100.00 / snm.TOKEN_CNT AS DECIMAL(5,2))
       END
FROM
       (SELECT tkn.TXN_REF,
               tkn.SUPPLIER_CD,
               tkn.NM_ROLE_CD,
               snt.GROUP_ID,
               snt.NAME_SEQ_NR,
               COUNT (DISTINCT tkn.TOKEN_TXT)     AS MATCH_TOKEN_CNT
        FROM   <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_SCREEN_TOKEN   tkn
               INNER JOIN
               <DB_ENV>DB_ODS.SANC_NAME_TOKEN                 snt
                  ON  snt.TOKEN_TXT = tkn.TOKEN_TXT
        GROUP  BY 1, 2, 3, 4, 5
        HAVING COUNT (DISTINCT tkn.TOKEN_TXT) >= 2
       )                                          mtc

       INNER JOIN
       <DB_ENV>DB_ODS.SANC_NAME                   snm
          ON  snm.GROUP_ID    = mtc.GROUP_ID
          AND snm.NAME_SEQ_NR = mtc.NAME_SEQ_NR

       INNER JOIN
       <DB_ENV>DB_ODS.SANC_ENTITY                 sen
          ON  sen.GROUP_ID   = mtc.GROUP_ID
          AND sen.ACTIVE_IND = 'Y'

       INNER JOIN
       (SELECT TXN_REF,
               SUPPLIER_CD,
               NM_ROLE_CD,
               COUNT (DISTINCT TOKEN_TXT)         AS SCREEN_TOKEN_CNT
        FROM   <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_SCREEN_TOKEN
        GROUP  BY 1, 2, 3
       )                                          stc
          ON  stc.TXN_REF     = mtc.TXN_REF
          AND stc.SUPPLIER_CD = mtc.SUPPLIER_CD
          AND stc.NM_ROLE_CD  = mtc.NM_ROLE_CD
WHERE
       snm.TOKEN_CNT > 0
AND    mtc.MATCH_TOKEN_CNT * 1.00 / snm.TOKEN_CNT >= 0.75
AND    (   COALESCE (snm.ALIAS_QUALITY_CD, 'G') <> 'L'
        OR mtc.MATCH_TOKEN_CNT >= snm.TOKEN_CNT)
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* CANDIDATES 3 - SANCTIONED COUNTRY                                        *
* ------------------------------------------------------------------------ *
* Counterparty country or counterparty bank country belongs to a regime    *
* with comprehensive (country wide) sanctions. Not tied to a designated    *
* person, hence GROUP_ID = -1 and NAME_SEQ_NR = 0. Score 80.               *
\**************************************************************************/

INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_SCREEN_CAND
(
       TXN_REF,
       SUPPLIER_CD,
       NM_ROLE_CD,
       GROUP_ID,
       NAME_SEQ_NR,
       MATCH_TOKEN_CNT,
       SANC_TOKEN_CNT,
       SCREEN_TOKEN_CNT,
       MATCH_TYP_CD,
       MATCH_SCORE
)
SELECT DISTINCT
       cpt.TXN_REF,
       cpt.SUPPLIER_CD,
       'CP',
       -1,
       0,
       0,
       0,
       0,
       'CTRY',
       80.00
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_CPTY       cpt

       INNER JOIN
       <DB_ENV>DB_REFERENCE.SANC_REGIME_CTRY      rgc
          ON  rgc.CTRY_2_CD IN (cpt.CPTY_CTRY_CD, cpt.CPTY_BANK_CTRY_CD)
          AND rgc.COMPREHENSIVE_IND = 'Y'
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_SCREEN_CAND
(
       TXN_REF,
       SUPPLIER_CD,
       NM_ROLE_CD,
       GROUP_ID,
       NAME_SEQ_NR,
       MATCH_TOKEN_CNT,
       SANC_TOKEN_CNT,
       SCREEN_TOKEN_CNT,
       MATCH_TYP_CD,
       MATCH_SCORE
)
SELECT DISTINCT
       scr.TXN_REF,
       scr.SUPPLIER_CD,
       scr.NM_ROLE_CD,
       -1,
       0,
       0,
       0,
       0,
       'CTRY',
       80.00
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_SCREEN_NM  scr

       INNER JOIN
       <DB_ENV>DB_REFERENCE.SANC_REGIME_CTRY      rgc
          ON  rgc.CTRY_2_CD = scr.CTRY_CD
          AND rgc.COMPREHENSIVE_IND = 'Y'
WHERE
       scr.NM_ROLE_CD IN ('MR', 'IB')
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* CANDIDATES 4 - DESIGNATED BANK IDENTIFIER CODE                           *
* ------------------------------------------------------------------------ *
* BIC of counterparty bank or intermediary bank belongs to a designated    *
* entity. Compared on the 8 character institution / location part as       *
* well, as branch codes are often omitted. Score 100.                      *
\**************************************************************************/

INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_SCREEN_CAND
(
       TXN_REF,
       SUPPLIER_CD,
       NM_ROLE_CD,
       GROUP_ID,
       NAME_SEQ_NR,
       MATCH_TOKEN_CNT,
       SANC_TOKEN_CNT,
       SCREEN_TOKEN_CNT,
       MATCH_TYP_CD,
       MATCH_SCORE
)
SELECT scr.TXN_REF,
       scr.SUPPLIER_CD,
       scr.NM_ROLE_CD,
       sbc.GROUP_ID,
       0,
       0,
       0,
       0,
       'BIC',
       CASE WHEN sbc.BIC_CD = scr.BIC_CD THEN 100.00 ELSE 95.00 END
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_SCREEN_NM  scr

       INNER JOIN
       <DB_ENV>DB_ODS.SANC_BIC                    sbc
          ON  SUBSTR (sbc.BIC_CD, 1, 8) = SUBSTR (scr.BIC_CD, 1, 8)

       INNER JOIN
       <DB_ENV>DB_ODS.SANC_ENTITY                 sen
          ON  sen.GROUP_ID   = sbc.GROUP_ID
          AND sen.ACTIVE_IND = 'Y'
WHERE
       scr.BIC_CD IS NOT NULL
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_SCREEN_CAND COLUMN (TXN_REF, SUPPLIER_CD, NM_ROLE_CD, GROUP_ID);


/**************************************************************************\
* WRITE NEW SCREENING HITS                                                 *
* ------------------------------------------------------------------------ *
* Best candidate per transaction, name role and listed entity. Hits which  *
* were already raised for the same transaction (re-delivery, status        *
* update) are not raised again so that the screening analysts do not see   *
* duplicates in their queue. HIT_ID is an identity column.                 *
\**************************************************************************/

INSERT INTO <DB_ENV>DB_AML.SANC_SCREEN_HIT
(
       TXN_REF,
       SUPPLIER_CD,
       BUSINESS_DT,
       ACCT_ID,
       PARTY_ID,
       NM_ROLE_CD,
       SCREENED_NM,
       GROUP_ID,
       MATCHED_NM,
       REGIME_NM,
       MATCH_TYP_CD,
       MATCH_SCORE,
       HIT_STATUS_CD,
       CO_UPD_TMS
)
SELECT cnd.TXN_REF,
       cnd.SUPPLIER_CD,
       tms.BUSINESS_DT,
       dtl.ACCT_ID,
       acs.PRIMARY_PARTY_ID,
       cnd.NM_ROLE_CD,
       CASE
          WHEN cnd.MATCH_TYP_CD = 'BIC'  THEN scr.BIC_CD
          WHEN cnd.MATCH_TYP_CD = 'CTRY' AND cnd.NM_ROLE_CD = 'CP'
          THEN COALESCE (scr.RAW_NM, cpt.CPTY_ACCT_KEY)
          ELSE scr.RAW_NM
       END,
       cnd.GROUP_ID,
       CASE
          WHEN cnd.MATCH_TYP_CD = 'CTRY'
          THEN 'COUNTRY ' || COALESCE (rgc.CTRY_2_CD, '')
          WHEN cnd.MATCH_TYP_CD = 'BIC'
          THEN 'BIC OF GROUP ' || TRIM (CAST (cnd.GROUP_ID AS VARCHAR(11)))
          ELSE snm.FULL_NM
       END,
       COALESCE (sen.REGIME_NM, rgc.REGIME_NM),
       cnd.MATCH_TYP_CD,
       cnd.MATCH_SCORE,
       'OPEN',
       tms.LOAD_TMS
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_SCREEN_CAND   cnd

       CROSS JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS      tms

       INNER JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD          dtl
          ON  dtl.TXN_REF     = cnd.TXN_REF
          AND dtl.SUPPLIER_CD = cnd.SUPPLIER_CD

       LEFT OUTER JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_SCREEN_NM     scr
          ON  scr.TXN_REF     = cnd.TXN_REF
          AND scr.SUPPLIER_CD = cnd.SUPPLIER_CD
          AND scr.NM_ROLE_CD  = cnd.NM_ROLE_CD

       LEFT OUTER JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_CPTY          cpt
          ON  cpt.TXN_REF     = cnd.TXN_REF
          AND cpt.SUPPLIER_CD = cnd.SUPPLIER_CD

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.ACCT_SNAPSHOT                  acs
          ON  acs.ACCT_ID = dtl.ACCT_ID

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.SANC_NAME                      snm
          ON  snm.GROUP_ID    = cnd.GROUP_ID
          AND snm.NAME_SEQ_NR = cnd.NAME_SEQ_NR

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.SANC_ENTITY                    sen
          ON  sen.GROUP_ID = cnd.GROUP_ID

       LEFT OUTER JOIN
       <DB_ENV>DB_REFERENCE.SANC_REGIME_CTRY         rgc
          ON  cnd.MATCH_TYP_CD      = 'CTRY'
          AND rgc.COMPREHENSIVE_IND = 'Y'
          AND rgc.CTRY_2_CD IN (COALESCE (cpt.CPTY_CTRY_CD, scr.CTRY_CD),
                                COALESCE (cpt.CPTY_BANK_CTRY_CD, scr.CTRY_CD))
WHERE
       NOT EXISTS
       (SELECT 1
        FROM   <DB_ENV>DB_AML.SANC_SCREEN_HIT   hit
        WHERE  hit.TXN_REF     = cnd.TXN_REF
        AND    hit.SUPPLIER_CD = cnd.SUPPLIER_CD
        AND    hit.GROUP_ID    = cnd.GROUP_ID
        AND    hit.NM_ROLE_CD  = cnd.NM_ROLE_CD
       )

QUALIFY ROW_NUMBER () OVER (PARTITION BY cnd.TXN_REF,
                                         cnd.SUPPLIER_CD,
                                         cnd.NM_ROLE_CD,
                                         cnd.GROUP_ID
                                ORDER BY cnd.MATCH_SCORE DESC,
                                         cnd.MATCH_TYP_CD ASC,
                                         cnd.NAME_SEQ_NR ASC,
                                         rgc.REGIME_NM ASC
                           ) = 1
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_AML.SANC_SCREEN_HIT INDEX (TXN_REF, SUPPLIER_CD);
COLLECT STATISTICS <DB_ENV>DB_AML.SANC_SCREEN_HIT COLUMN (BUSINESS_DT);


/**************************************************************************\
* SCREENING SUMMARY FOR THE BATCH LOG                                      *
\**************************************************************************/

SELECT hit.MATCH_TYP_CD,
       hit.NM_ROLE_CD,
       COUNT (*)                      AS HIT_CNT,
       COUNT (DISTINCT hit.TXN_REF)   AS TXN_CNT
FROM
       <DB_ENV>DB_AML.SANC_SCREEN_HIT             hit

       INNER JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS   tms
          ON  tms.LOAD_TMS = hit.CO_UPD_TMS
GROUP  BY 1, 2
ORDER  BY 1, 2
;
.if errorcode <> 0 then .quit errorcode;

.quit 0;

