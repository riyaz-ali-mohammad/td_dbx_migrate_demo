-- TODO: manual review required — choose whether this former BTEQ script runs as a notebook, stored procedure, or Workflows DAG; the linear SQL below assumes notebook/job execution that stops on the first SQL error.
-- assumption: target catalog and schema are configured by the runner; source database qualifiers are omitted because no Unity Catalog mapping was supplied.

/**************************************************************************\
* PREPARATION                                                              *
* ------------------------------------------------------------------------ *
* Screening of the daily payments against the UK consolidated sanctions    *
* list (loaded by kycref.15 / kycref.60). Screened are the counterparty,   *
* ordering customer, beneficiary customer and merchant names, the bank     *
* identifier codes of counterparty and intermediary bank, and the          *
* counterparty / bank country against comprehensively sanctioned regimes.  *
\**************************************************************************/

-- Converted: Teradata INDEX statistics and BTEQ display controls are omitted because Delta has no matching indexes and the runner controls display.

/**************************************************************************\
* BUILD THE LIST OF NAMES TO BE SCREENED                                   *
* ------------------------------------------------------------------------ *
* Name roles:  CP = counterparty          OR = ordering customer           *
*              BE = beneficiary customer  MR = merchant                    *
*              IB = intermediary bank (BIC only, no name)                  *
* The name normalisation is identical to the one applied to the sanctions  *
* list in kycref.60 - any change has to be made in both places.            *
\**************************************************************************/

-- Converted: source database qualifier omitted; SQL execution errors are propagated by the Databricks runner.
DELETE FROM DLYTXN_SCREEN_NM;

-- Converted: OREPLACE/OTRANSLATE mapped to REPLACE/TRANSLATE and source database qualifiers omitted.
INSERT INTO DLYTXN_SCREEN_NM
(
       TXN_REF, SUPPLIER_CD, NM_ROLE_CD, RAW_NM, NORM_NM, CTRY_CD, BIC_CD
)
SELECT dtl.TXN_REF,
       dtl.SUPPLIER_CD,
       'CP',
       dtl.CPTY_NM,
       NULLIF(TRIM(REPLACE(REPLACE(TRANSLATE(UPPER(TRIM(dtl.CPTY_NM)), '.,''-&/()', '        '), '  ', ' '), '  ', ' ')), ''),
       COALESCE(NULLIF(dtl.CPTY_CTRY, ' '), NULLIF(dtl.CPTY_BANK_CTRY, ' ')),
       NULLIF(dtl.CPTY_BIC, ' ')
FROM DLYTXN_LOAD dtl
WHERE dtl.CPTY_NM IS NOT NULL OR dtl.CPTY_BIC <> ' ';

-- Converted: OREPLACE/OTRANSLATE mapped to REPLACE/TRANSLATE and source database qualifiers omitted.
INSERT INTO DLYTXN_SCREEN_NM
(
       TXN_REF, SUPPLIER_CD, NM_ROLE_CD, RAW_NM, NORM_NM, CTRY_CD, BIC_CD
)
SELECT dtl.TXN_REF,
       dtl.SUPPLIER_CD,
       'OR',
       dtl.ORDERING_CUST_NM,
       NULLIF(TRIM(REPLACE(REPLACE(TRANSLATE(UPPER(TRIM(dtl.ORDERING_CUST_NM)), '.,''-&/()', '        '), '  ', ' '), '  ', ' ')), ''),
       NULL,
       NULL
FROM DLYTXN_LOAD dtl
WHERE dtl.ORDERING_CUST_NM IS NOT NULL;

-- Converted: OREPLACE/OTRANSLATE mapped to REPLACE/TRANSLATE and source database qualifiers omitted.
INSERT INTO DLYTXN_SCREEN_NM
(
       TXN_REF, SUPPLIER_CD, NM_ROLE_CD, RAW_NM, NORM_NM, CTRY_CD, BIC_CD
)
SELECT dtl.TXN_REF,
       dtl.SUPPLIER_CD,
       'BE',
       dtl.BENEF_CUST_NM,
       NULLIF(TRIM(REPLACE(REPLACE(TRANSLATE(UPPER(TRIM(dtl.BENEF_CUST_NM)), '.,''-&/()', '        '), '  ', ' '), '  ', ' ')), ''),
       NULL,
       NULL
FROM DLYTXN_LOAD dtl
WHERE dtl.BENEF_CUST_NM IS NOT NULL;

-- Converted: OREPLACE/OTRANSLATE mapped to REPLACE/TRANSLATE and source database qualifiers omitted.
INSERT INTO DLYTXN_SCREEN_NM
(
       TXN_REF, SUPPLIER_CD, NM_ROLE_CD, RAW_NM, NORM_NM, CTRY_CD, BIC_CD
)
SELECT dtl.TXN_REF,
       dtl.SUPPLIER_CD,
       'MR',
       dtl.MERCHANT_NM,
       NULLIF(TRIM(REPLACE(REPLACE(TRANSLATE(UPPER(TRIM(dtl.MERCHANT_NM)), '.,''-&/()', '        '), '  ', ' '), '  ', ' ')), ''),
       NULLIF(dtl.MERCHANT_CTRY, ' '),
       NULL
FROM DLYTXN_LOAD dtl
WHERE dtl.MERCHANT_NM IS NOT NULL;

-- Converted: source database qualifiers omitted.
INSERT INTO DLYTXN_SCREEN_NM
(
       TXN_REF, SUPPLIER_CD, NM_ROLE_CD, RAW_NM, NORM_NM, CTRY_CD, BIC_CD
)
SELECT dtl.TXN_REF,
       dtl.SUPPLIER_CD,
       'IB',
       NULL,
       NULL,
       SUBSTR(dtl.INTERMED_BIC, 5, 2),
       dtl.INTERMED_BIC
FROM DLYTXN_LOAD dtl
WHERE dtl.INTERMED_BIC <> ' ';

-- Converted: routine job statistics refreshes omitted because Delta maintains table-level statistics.

/**************************************************************************\
* SPLIT THE NORMALISED NAMES INTO TOKENS                                   *
\**************************************************************************/

-- TODO: manual review required — confirm that the target supports bounded VARCHAR columns in session temporary tables.
-- Converted: VOLATILE TABLE mapped to TEMP TABLE; PRIMARY INDEX and ON COMMIT clauses removed.
CREATE TEMP TABLE VT_SCREEN_SRC
(
       SCREEN_KEY VARCHAR(50) NOT NULL,
       NORM_NM    VARCHAR(140)
);

-- Converted: source database qualifier omitted.
INSERT INTO VT_SCREEN_SRC
SELECT TRIM(TXN_REF) || '|' || SUPPLIER_CD || '|' || NM_ROLE_CD,
       NORM_NM
FROM DLYTXN_SCREEN_NM
WHERE NORM_NM IS NOT NULL;

-- Converted: source database qualifier omitted.
DELETE FROM DLYTXN_SCREEN_TOKEN;

-- Converted: STRTOK_SPLIT_TO_TABLE mapped to filtered POSEXPLODE; STRTOK mapped to TRY_ELEMENT_AT over nonempty tokens; positions remain one-based.
INSERT INTO DLYTXN_SCREEN_TOKEN
(
       TXN_REF, SUPPLIER_CD, NM_ROLE_CD, TOKEN_SEQ_NR, TOKEN_TXT
)
SELECT TRY_ELEMENT_AT(FILTER(SPLIT(tok.OUTKEY, '[|]'), x -> LENGTH(x) > 0), 1),
       TRY_ELEMENT_AT(FILTER(SPLIT(tok.OUTKEY, '[|]'), x -> LENGTH(x) > 0), 2),
       TRY_ELEMENT_AT(FILTER(SPLIT(tok.OUTKEY, '[|]'), x -> LENGTH(x) > 0), 3),
       tok.TOKENNUM,
       tok.TOKEN
FROM
(
       SELECT src.SCREEN_KEY AS OUTKEY,
              pos + 1 AS TOKENNUM,
              token AS TOKEN
       FROM VT_SCREEN_SRC src
       LATERAL VIEW POSEXPLODE(FILTER(SPLIT(src.NORM_NM, ' '), x -> LENGTH(x) > 0)) exploded AS pos, token
) tok
LEFT OUTER JOIN NAME_NOISE_WORD nsw
  ON nsw.NOISE_WORD = tok.TOKEN
WHERE nsw.NOISE_WORD IS NULL
  AND CHARACTER_LENGTH(TRIM(tok.TOKEN)) >= 2;

-- Converted: routine job statistics refreshes omitted because Delta maintains table-level statistics.

-- Converted: volatile-table cleanup uses Databricks temporary-table syntax.
DROP TEMPORARY TABLE VT_SCREEN_SRC;

/**************************************************************************\
* CANDIDATES 1 - EXACT NAME MATCH                                          *
\**************************************************************************/

-- Converted: source database qualifier omitted.
DELETE FROM DLYTXN_SCREEN_CAND;

-- Converted: source database qualifiers omitted.
INSERT INTO DLYTXN_SCREEN_CAND
(
       TXN_REF, SUPPLIER_CD, NM_ROLE_CD, GROUP_ID, NAME_SEQ_NR,
       MATCH_TOKEN_CNT, SANC_TOKEN_CNT, SCREEN_TOKEN_CNT, MATCH_TYP_CD, MATCH_SCORE
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
FROM DLYTXN_SCREEN_NM scr
INNER JOIN SANC_NAME snm
  ON snm.NORM_NM = scr.NORM_NM
INNER JOIN SANC_ENTITY sen
  ON sen.GROUP_ID = snm.GROUP_ID
 AND sen.ACTIVE_IND = 'Y'
WHERE scr.NORM_NM IS NOT NULL;

/**************************************************************************\
* CANDIDATES 2 - TOKEN MATCH                                               *
\**************************************************************************/

-- Converted: source database qualifiers omitted; explicit DECIMAL result scale retained for the scored division.
INSERT INTO DLYTXN_SCREEN_CAND
(
       TXN_REF, SUPPLIER_CD, NM_ROLE_CD, GROUP_ID, NAME_SEQ_NR,
       MATCH_TOKEN_CNT, SANC_TOKEN_CNT, SCREEN_TOKEN_CNT, MATCH_TYP_CD, MATCH_SCORE
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
          WHEN mtc.MATCH_TOKEN_CNT * 100.00 / snm.TOKEN_CNT >= 99.00 THEN 99.00
          ELSE CAST(mtc.MATCH_TOKEN_CNT * 100.00 / snm.TOKEN_CNT AS DECIMAL(5,2))
       END
FROM
(
       SELECT tkn.TXN_REF,
              tkn.SUPPLIER_CD,
              tkn.NM_ROLE_CD,
              snt.GROUP_ID,
              snt.NAME_SEQ_NR,
              COUNT(DISTINCT tkn.TOKEN_TXT) AS MATCH_TOKEN_CNT
       FROM DLYTXN_SCREEN_TOKEN tkn
       INNER JOIN SANC_NAME_TOKEN snt
         ON snt.TOKEN_TXT = tkn.TOKEN_TXT
       GROUP BY 1, 2, 3, 4, 5
       HAVING COUNT(DISTINCT tkn.TOKEN_TXT) >= 2
) mtc
INNER JOIN SANC_NAME snm
  ON snm.GROUP_ID = mtc.GROUP_ID
 AND snm.NAME_SEQ_NR = mtc.NAME_SEQ_NR
INNER JOIN SANC_ENTITY sen
  ON sen.GROUP_ID = mtc.GROUP_ID
 AND sen.ACTIVE_IND = 'Y'
INNER JOIN
(
       SELECT TXN_REF,
              SUPPLIER_CD,
              NM_ROLE_CD,
              COUNT(DISTINCT TOKEN_TXT) AS SCREEN_TOKEN_CNT
       FROM DLYTXN_SCREEN_TOKEN
       GROUP BY 1, 2, 3
) stc
  ON stc.TXN_REF = mtc.TXN_REF
 AND stc.SUPPLIER_CD = mtc.SUPPLIER_CD
 AND stc.NM_ROLE_CD = mtc.NM_ROLE_CD
WHERE snm.TOKEN_CNT > 0
  AND mtc.MATCH_TOKEN_CNT * 1.00 / snm.TOKEN_CNT >= 0.75
  AND (COALESCE(snm.ALIAS_QUALITY_CD, 'G') <> 'L'
       OR mtc.MATCH_TOKEN_CNT >= snm.TOKEN_CNT);

/**************************************************************************\
* CANDIDATES 3 - SANCTIONED COUNTRY                                        *
\**************************************************************************/

-- Converted: source database qualifiers omitted.
INSERT INTO DLYTXN_SCREEN_CAND
(
       TXN_REF, SUPPLIER_CD, NM_ROLE_CD, GROUP_ID, NAME_SEQ_NR,
       MATCH_TOKEN_CNT, SANC_TOKEN_CNT, SCREEN_TOKEN_CNT, MATCH_TYP_CD, MATCH_SCORE
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
FROM DLYTXN_CPTY cpt
INNER JOIN SANC_REGIME_CTRY rgc
  ON rgc.CTRY_2_CD IN (cpt.CPTY_CTRY_CD, cpt.CPTY_BANK_CTRY_CD)
 AND rgc.COMPREHENSIVE_IND = 'Y';

-- Converted: source database qualifiers omitted.
INSERT INTO DLYTXN_SCREEN_CAND
(
       TXN_REF, SUPPLIER_CD, NM_ROLE_CD, GROUP_ID, NAME_SEQ_NR,
       MATCH_TOKEN_CNT, SANC_TOKEN_CNT, SCREEN_TOKEN_CNT, MATCH_TYP_CD, MATCH_SCORE
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
FROM DLYTXN_SCREEN_NM scr
INNER JOIN SANC_REGIME_CTRY rgc
  ON rgc.CTRY_2_CD = scr.CTRY_CD
 AND rgc.COMPREHENSIVE_IND = 'Y'
WHERE scr.NM_ROLE_CD IN ('MR', 'IB');

/**************************************************************************\
* CANDIDATES 4 - DESIGNATED BANK IDENTIFIER CODE                           *
\**************************************************************************/

-- Converted: source database qualifiers omitted.
INSERT INTO DLYTXN_SCREEN_CAND
(
       TXN_REF, SUPPLIER_CD, NM_ROLE_CD, GROUP_ID, NAME_SEQ_NR,
       MATCH_TOKEN_CNT, SANC_TOKEN_CNT, SCREEN_TOKEN_CNT, MATCH_TYP_CD, MATCH_SCORE
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
FROM DLYTXN_SCREEN_NM scr
INNER JOIN SANC_BIC sbc
  ON SUBSTR(sbc.BIC_CD, 1, 8) = SUBSTR(scr.BIC_CD, 1, 8)
INNER JOIN SANC_ENTITY sen
  ON sen.GROUP_ID = sbc.GROUP_ID
 AND sen.ACTIVE_IND = 'Y'
WHERE scr.BIC_CD IS NOT NULL;

-- Converted: routine job statistics refresh omitted because Delta maintains table-level statistics.

/**************************************************************************\
* WRITE NEW SCREENING HITS                                                 *
\**************************************************************************/

-- TODO: manual review required — source mode was not supplied; confirm the VARCHAR(11) cast overflow contract for GROUP_ID.
-- assumption: GROUP_ID fits within 11 characters; the guard raises on non-pad overflow rather than silently truncating.
-- Converted: source database qualifiers omitted; bounded VARCHAR cast implemented with an explicit overflow guard; native QUALIFY retained.
INSERT INTO SANC_SCREEN_HIT
(
       TXN_REF, SUPPLIER_CD, BUSINESS_DT, ACCT_ID, PARTY_ID, NM_ROLE_CD,
       SCREENED_NM, GROUP_ID, MATCHED_NM, REGIME_NM, MATCH_TYP_CD,
       MATCH_SCORE, HIT_STATUS_CD, CO_UPD_TMS
)
SELECT cnd.TXN_REF,
       cnd.SUPPLIER_CD,
       tms.BUSINESS_DT,
       dtl.ACCT_ID,
       acs.PRIMARY_PARTY_ID,
       cnd.NM_ROLE_CD,
       CASE
          WHEN cnd.MATCH_TYP_CD = 'BIC' THEN scr.BIC_CD
          WHEN cnd.MATCH_TYP_CD = 'CTRY' AND cnd.NM_ROLE_CD = 'CP'
          THEN COALESCE(scr.RAW_NM, cpt.CPTY_ACCT_KEY)
          ELSE scr.RAW_NM
       END,
       cnd.GROUP_ID,
       CASE
          WHEN cnd.MATCH_TYP_CD = 'CTRY'
          THEN 'COUNTRY ' || COALESCE(rgc.CTRY_2_CD, '')
          WHEN cnd.MATCH_TYP_CD = 'BIC'
          THEN 'BIC OF GROUP ' || TRIM(
                 IF(COALESCE(LENGTH(RTRIM(CAST(cnd.GROUP_ID AS STRING))), 0) <= 11,
                    SUBSTRING(CAST(cnd.GROUP_ID AS STRING), 1, 11),
                    RAISE_ERROR('VARCHAR(11) overflow')))
          ELSE snm.FULL_NM
       END,
       COALESCE(sen.REGIME_NM, rgc.REGIME_NM),
       cnd.MATCH_TYP_CD,
       cnd.MATCH_SCORE,
       'OPEN',
       tms.LOAD_TMS
FROM DLYTXN_SCREEN_CAND cnd
CROSS JOIN DLYTXN_LOAD_TMS tms
INNER JOIN DLYTXN_LOAD dtl
  ON dtl.TXN_REF = cnd.TXN_REF
 AND dtl.SUPPLIER_CD = cnd.SUPPLIER_CD
LEFT OUTER JOIN DLYTXN_SCREEN_NM scr
  ON scr.TXN_REF = cnd.TXN_REF
 AND scr.SUPPLIER_CD = cnd.SUPPLIER_CD
 AND scr.NM_ROLE_CD = cnd.NM_ROLE_CD
LEFT OUTER JOIN DLYTXN_CPTY cpt
  ON cpt.TXN_REF = cnd.TXN_REF
 AND cpt.SUPPLIER_CD = cnd.SUPPLIER_CD
LEFT OUTER JOIN ACCT_SNAPSHOT acs
  ON acs.ACCT_ID = dtl.ACCT_ID
LEFT OUTER JOIN SANC_NAME snm
  ON snm.GROUP_ID = cnd.GROUP_ID
 AND snm.NAME_SEQ_NR = cnd.NAME_SEQ_NR
LEFT OUTER JOIN SANC_ENTITY sen
  ON sen.GROUP_ID = cnd.GROUP_ID
LEFT OUTER JOIN SANC_REGIME_CTRY rgc
  ON cnd.MATCH_TYP_CD = 'CTRY'
 AND rgc.COMPREHENSIVE_IND = 'Y'
 AND rgc.CTRY_2_CD IN (COALESCE(cpt.CPTY_CTRY_CD, scr.CTRY_CD),
                       COALESCE(cpt.CPTY_BANK_CTRY_CD, scr.CTRY_CD))
WHERE NOT EXISTS
(
       SELECT 1
       FROM SANC_SCREEN_HIT hit
       WHERE hit.TXN_REF = cnd.TXN_REF
         AND hit.SUPPLIER_CD = cnd.SUPPLIER_CD
         AND hit.GROUP_ID = cnd.GROUP_ID
         AND hit.NM_ROLE_CD = cnd.NM_ROLE_CD
)
QUALIFY ROW_NUMBER() OVER
(
       PARTITION BY cnd.TXN_REF, cnd.SUPPLIER_CD, cnd.NM_ROLE_CD, cnd.GROUP_ID
       ORDER BY cnd.MATCH_SCORE DESC,
                cnd.MATCH_TYP_CD ASC,
                cnd.NAME_SEQ_NR ASC,
                rgc.REGIME_NM ASC
) = 1;

-- Converted: routine job statistics refreshes omitted because Delta maintains table-level statistics.

/**************************************************************************\
* SCREENING SUMMARY FOR THE BATCH LOG                                      *
\**************************************************************************/

-- Converted: source database qualifiers omitted; terminal BTEQ success command removed.
SELECT hit.MATCH_TYP_CD,
       hit.NM_ROLE_CD,
       COUNT(*) AS HIT_CNT,
       COUNT(DISTINCT hit.TXN_REF) AS TXN_CNT
FROM SANC_SCREEN_HIT hit
INNER JOIN DLYTXN_LOAD_TMS tms
  ON tms.LOAD_TMS = hit.CO_UPD_TMS
GROUP BY 1, 2
ORDER BY 1, 2;
