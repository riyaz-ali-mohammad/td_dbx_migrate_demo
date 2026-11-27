/**************************************************************************\
* DERIVE THE COUNTERPARTY KEY FOR EVERY TRANSACTION                        *
* ------------------------------------------------------------------------ *
* The counterparty account key is the IBAN where delivered, otherwise the  *
* UK sort code and account number. The name is normalised with the same    *
* rule as the sanctions list (kycref.60) so that both can be compared.     *
* Card, cash and fee transactions without a counterparty account are not   *
* assigned a counterparty.                                                 *
\**************************************************************************/

-- TODO: manual review required — choose a Databricks notebook, stored procedure, or Workflows DAG as the execution wrapper for this former BTEQ script
-- TODO: manual review required — map BTEQ error exits to procedure failure handling or Workflows task failure behavior
-- TODO: manual review required — confirm fixed-width CHAR padding and trailing-space behavior for counterparty codes and account IDs
-- Converted the Teradata volatile table to a Databricks session-scoped temp table; removed PRIMARY INDEX and ON COMMIT clauses
CREATE TEMP TABLE VT_DLYTXN_CPTY_KEY
(
       TXN_REF            VARCHAR(35)  NOT NULL,
       SUPPLIER_CD        CHAR(4)      NOT NULL,
       BOOKING_DT         DATE,
       CPTY_ACCT_KEY      VARCHAR(34),
       CPTY_NORM_NM       VARCHAR(140),
       CPTY_BIC_CD        CHAR(11),
       CPTY_CTRY_CD       CHAR(2),
       CPTY_BANK_CTRY_CD  CHAR(2),
       CPTY_UK_ACCT_ID    CHAR(14)
);

-- TODO: manual review required — confirm that the retained CHAR(14) casts preserve Teradata overflow and blank-padding behavior
-- Replaced Teradata OREPLACE/OTRANSLATE functions and resolved the source database reference through the current Databricks catalog and schema
INSERT INTO VT_DLYTXN_CPTY_KEY
SELECT dtl.TXN_REF,
       dtl.SUPPLIER_CD,
       dtl.BOOKING_DT,
       COALESCE (NULLIF (TRIM (dtl.CPTY_IBAN), ''),
                 NULLIF (TRIM (dtl.CPTY_SORT_CD || dtl.CPTY_ACCT_NR), '')),
       COALESCE (NULLIF (TRIM (REPLACE (REPLACE (TRANSLATE (UPPER (TRIM (dtl.CPTY_NM)), '.,''-&/()', '        '), '  ', ' '), '  ', ' ')), ''),
                 'UNKNOWN'),
       NULLIF (dtl.CPTY_BIC, ' '),
       NULLIF (dtl.CPTY_CTRY, ' '),
       CASE
          WHEN dtl.CPTY_BANK_CTRY <> ' '                      THEN dtl.CPTY_BANK_CTRY
          WHEN CHARACTER_LENGTH (TRIM (dtl.CPTY_BIC)) = 11    THEN SUBSTR (dtl.CPTY_BIC, 5, 2)
          WHEN dtl.CPTY_IBAN IS NOT NULL                      THEN SUBSTR (dtl.CPTY_IBAN, 1, 2)
          WHEN TRIM (dtl.CPTY_SORT_CD) <> ''                  THEN 'GB'
          ELSE NULL
       END,
       /* UK IBAN: GBkk BBBB SSSSSS AAAAAAAA -> sort code / account number */
       CASE
          WHEN SUBSTR (dtl.CPTY_IBAN, 1, 2) = 'GB'
           AND CHARACTER_LENGTH (dtl.CPTY_IBAN) = 22
          THEN CAST (SUBSTR (dtl.CPTY_IBAN, 9, 14) AS CHAR(14))
          WHEN TRIM (dtl.CPTY_SORT_CD) <> ''
           AND TRIM (dtl.CPTY_ACCT_NR) <> ''
          THEN CAST (dtl.CPTY_SORT_CD || dtl.CPTY_ACCT_NR AS CHAR(14))
          ELSE NULL
       END
FROM
       DLYTXN_LOAD   dtl
WHERE
       COALESCE (NULLIF (TRIM (dtl.CPTY_IBAN), ''),
                 NULLIF (TRIM (dtl.CPTY_SORT_CD || dtl.CPTY_ACCT_NR), '')) IS NOT NULL
;

-- Converted the deliberate post-load column statistics refresh to Databricks ANALYZE TABLE
ANALYZE TABLE VT_DLYTXN_CPTY_KEY COMPUTE STATISTICS FOR COLUMNS CPTY_ACCT_KEY, CPTY_NORM_NM;
-- Converted the deliberate post-load column statistics refresh to Databricks ANALYZE TABLE
ANALYZE TABLE VT_DLYTXN_CPTY_KEY COMPUTE STATISTICS FOR COLUMNS CPTY_UK_ACCT_ID;


/**************************************************************************\
* COLLECT COUNTERPARTIES NOT SEEN BEFORE                                   *
* ------------------------------------------------------------------------ *
* One row per account key and normalised name. Where the same counterparty *
* arrives with different BIC / country in one file, the latest booking     *
* wins.                                                                    *
\**************************************************************************/

-- TODO: manual review required — map this BTEQ error exit to procedure failure handling or Workflows task failure behavior
-- Resolved the source database reference through the current Databricks catalog and schema
DELETE FROM DLYTXN_NEW_CPTY;

-- TODO: manual review required — map this BTEQ error exit to procedure failure handling or Workflows task failure behavior
-- Resolved source database references through the current Databricks catalog and schema; retained native QUALIFY semantics
INSERT INTO DLYTXN_NEW_CPTY
(
       CPTY_ACCT_KEY,
       CPTY_NORM_NM,
       CPTY_BIC_CD,
       CPTY_CTRY_CD,
       FIRST_SEEN_DT
)
SELECT vk.CPTY_ACCT_KEY,
       vk.CPTY_NORM_NM,
       vk.CPTY_BIC_CD,
       COALESCE (vk.CPTY_CTRY_CD, vk.CPTY_BANK_CTRY_CD),
       MIN (vk.BOOKING_DT) OVER (PARTITION BY vk.CPTY_ACCT_KEY, vk.CPTY_NORM_NM)
FROM
       VT_DLYTXN_CPTY_KEY            vk

       LEFT OUTER JOIN
       CPTY                           cpt
          ON  cpt.CPTY_ACCT_KEY = vk.CPTY_ACCT_KEY
          AND cpt.CPTY_NORM_NM  = vk.CPTY_NORM_NM
WHERE
       cpt.CPTY_ID IS NULL

QUALIFY ROW_NUMBER () OVER (PARTITION BY vk.CPTY_ACCT_KEY,
                                         vk.CPTY_NORM_NM
                                ORDER BY vk.BOOKING_DT DESC,
                                         vk.TXN_REF DESC
                           ) = 1
;


/**************************************************************************\
* ASSIGN SURROGATE KEYS TO NEW COUNTERPARTIES                              *
* ------------------------------------------------------------------------ *
* New CPTY_ID = highest existing key + running count over the new rows.    *
\**************************************************************************/

-- TODO: manual review required — map this BTEQ error exit to procedure failure handling or Workflows task failure behavior
-- Converted CSUM and ZEROIFNULL to Databricks window and null-handling expressions; resolved source database references through the current namespace
INSERT INTO CPTY
(
       CPTY_ID,
       CPTY_ACCT_KEY,
       CPTY_NORM_NM,
       CPTY_BIC_CD,
       CPTY_CTRY_CD,
       FIRST_SEEN_DT,
       LAST_SEEN_DT,
       TXN_CNT,
       CO_UPD_TMS
)
SELECT mx.MAX_CPTY_ID + SUM (1) OVER (ORDER BY ncp.CPTY_ACCT_KEY, ncp.CPTY_NORM_NM ROWS UNBOUNDED PRECEDING),
       ncp.CPTY_ACCT_KEY,
       ncp.CPTY_NORM_NM,
       ncp.CPTY_BIC_CD,
       ncp.CPTY_CTRY_CD,
       ncp.FIRST_SEEN_DT,
       ncp.FIRST_SEEN_DT,
       0,
       tms.LOAD_TMS
FROM
       DLYTXN_NEW_CPTY   ncp

       CROSS JOIN
       (SELECT COALESCE (MAX (CPTY_ID), 0) AS MAX_CPTY_ID
        FROM   CPTY
       )                                          mx

       CROSS JOIN
       DLYTXN_LOAD_TMS   tms
;


/**************************************************************************\
* MAINTAIN LAST SEEN DATE AND TRANSACTION COUNT                            *
\**************************************************************************/

-- TODO: manual review required — map this BTEQ error exit to procedure failure handling or Workflows task failure behavior
-- Converted Teradata UPDATE FROM to Delta MERGE, ZEROIFNULL to COALESCE, and resolved source database references through the current namespace
MERGE INTO CPTY AS cpt
USING (
       SELECT agg.CPTY_ACCT_KEY,
              agg.CPTY_NORM_NM,
              agg.LAST_SEEN_DT,
              agg.TXN_CNT,
              agg.CPTY_BIC_CD,
              tms.LOAD_TMS
       FROM   (SELECT CPTY_ACCT_KEY,
                      CPTY_NORM_NM,
                      MAX (BOOKING_DT)   AS LAST_SEEN_DT,
                      COUNT (*)          AS TXN_CNT,
                      MAX (CPTY_BIC_CD)  AS CPTY_BIC_CD
               FROM   VT_DLYTXN_CPTY_KEY
               GROUP  BY 1, 2
              ) agg
       CROSS JOIN DLYTXN_LOAD_TMS tms
      ) AS src
ON     cpt.CPTY_ACCT_KEY = src.CPTY_ACCT_KEY
AND    cpt.CPTY_NORM_NM  = src.CPTY_NORM_NM
WHEN MATCHED THEN UPDATE SET
       LAST_SEEN_DT = CASE WHEN src.LAST_SEEN_DT > cpt.LAST_SEEN_DT
                           THEN src.LAST_SEEN_DT
                           ELSE cpt.LAST_SEEN_DT END,
       TXN_CNT      = COALESCE (cpt.TXN_CNT, 0) + src.TXN_CNT,
       CPTY_BIC_CD  = COALESCE (cpt.CPTY_BIC_CD, src.CPTY_BIC_CD),
       CO_UPD_TMS   = src.LOAD_TMS
;


/**************************************************************************\
* RESOLVE COUNTERPARTY PER TRANSACTION                                     *
* ------------------------------------------------------------------------ *
* Counterparties holding an account with the bank are flagged as internal  *
* and linked to the primary party of that account. This allows the         *
* transaction monitoring to follow funds between own customers (mule       *
* chains, layering through related accounts).                              *
\**************************************************************************/

-- TODO: manual review required — map this BTEQ error exit to procedure failure handling or Workflows task failure behavior
-- Resolved the source database reference through the current Databricks catalog and schema
DELETE FROM DLYTXN_CPTY;

-- TODO: manual review required — map this BTEQ error exit to procedure failure handling or Workflows task failure behavior
-- Resolved source database references through the current Databricks catalog and schema
INSERT INTO DLYTXN_CPTY
(
       TXN_REF,
       SUPPLIER_CD,
       CPTY_ID,
       CPTY_ACCT_KEY,
       CPTY_NORM_NM,
       CPTY_CTRY_CD,
       CPTY_BANK_CTRY_CD,
       CPTY_INTERNAL_IND,
       CPTY_ACCT_ID,
       CPTY_PARTY_ID,
       NEW_CPTY_IND
)
SELECT vk.TXN_REF,
       vk.SUPPLIER_CD,
       cpt.CPTY_ID,
       vk.CPTY_ACCT_KEY,
       vk.CPTY_NORM_NM,
       COALESCE (vk.CPTY_CTRY_CD, vk.CPTY_BANK_CTRY_CD),
       vk.CPTY_BANK_CTRY_CD,
       CASE WHEN act.ACCT_ID IS NOT NULL THEN 'Y' ELSE 'N' END,
       act.ACCT_ID,
       act.PRIMARY_PARTY_ID,
       CASE WHEN ncp.CPTY_ACCT_KEY IS NOT NULL THEN 'Y' ELSE 'N' END
FROM
       VT_DLYTXN_CPTY_KEY                         vk

       LEFT OUTER JOIN
       CPTY                                        cpt
          ON  cpt.CPTY_ACCT_KEY = vk.CPTY_ACCT_KEY
          AND cpt.CPTY_NORM_NM  = vk.CPTY_NORM_NM

       LEFT OUTER JOIN
       DLYTXN_NEW_CPTY                             ncp
          ON  ncp.CPTY_ACCT_KEY = vk.CPTY_ACCT_KEY
          AND ncp.CPTY_NORM_NM  = vk.CPTY_NORM_NM

       LEFT OUTER JOIN
       ACCT                                        act
          ON  act.ACCT_ID = vk.CPTY_UK_ACCT_ID
;

-- TODO: manual review required — map this BTEQ error exit to procedure failure handling or Workflows task failure behavior
-- Converted cleanup to drop the session-scoped Databricks temp table
DROP TEMPORARY TABLE VT_DLYTXN_CPTY_KEY;


