.set WIDTH       300;
.set TITLEDASHES OFF;

/**************************************************************************\
* DERIVE THE COUNTERPARTY KEY FOR EVERY TRANSACTION                        *
* ------------------------------------------------------------------------ *
* The counterparty account key is the IBAN where delivered, otherwise the  *
* UK sort code and account number. The name is normalised with the same    *
* rule as the sanctions list (kycref.60) so that both can be compared.     *
* Card, cash and fee transactions without a counterparty account are not   *
* assigned a counterparty.                                                 *
\**************************************************************************/

CREATE VOLATILE TABLE VT_DLYTXN_CPTY_KEY
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
)
PRIMARY INDEX ( TXN_REF, SUPPLIER_CD )
ON COMMIT PRESERVE ROWS
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO VT_DLYTXN_CPTY_KEY
SELECT dtl.TXN_REF,
       dtl.SUPPLIER_CD,
       dtl.BOOKING_DT,
       COALESCE (NULLIF (TRIM (dtl.CPTY_IBAN), ''),
                 NULLIF (TRIM (dtl.CPTY_SORT_CD || dtl.CPTY_ACCT_NR), '')),
       COALESCE (NULLIF (TRIM (OREPLACE (OREPLACE (OTRANSLATE (UPPER (TRIM (dtl.CPTY_NM)), '.,''-&/()', '        '), '  ', ' '), '  ', ' ')), ''),
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
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD   dtl
WHERE
       COALESCE (NULLIF (TRIM (dtl.CPTY_IBAN), ''),
                 NULLIF (TRIM (dtl.CPTY_SORT_CD || dtl.CPTY_ACCT_NR), '')) IS NOT NULL
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS ON VT_DLYTXN_CPTY_KEY COLUMN (CPTY_ACCT_KEY, CPTY_NORM_NM);
COLLECT STATISTICS ON VT_DLYTXN_CPTY_KEY COLUMN (CPTY_UK_ACCT_ID);
COLLECT STATISTICS <DB_ENV>DB_ODS.CPTY INDEX (CPTY_ACCT_KEY, CPTY_NORM_NM);


/**************************************************************************\
* COLLECT COUNTERPARTIES NOT SEEN BEFORE                                   *
* ------------------------------------------------------------------------ *
* One row per account key and normalised name. Where the same counterparty *
* arrives with different BIC / country in one file, the latest booking     *
* wins.                                                                    *
\**************************************************************************/

DELETE FROM <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_NEW_CPTY
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_NEW_CPTY
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
       <DB_ENV>DB_ODS.CPTY           cpt
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
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* ASSIGN SURROGATE KEYS TO NEW COUNTERPARTIES                              *
* ------------------------------------------------------------------------ *
* New CPTY_ID = highest existing key + running count over the new rows.    *
\**************************************************************************/

INSERT INTO <DB_ENV>DB_ODS.CPTY
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
SELECT mx.MAX_CPTY_ID + CSUM (1, ncp.CPTY_ACCT_KEY, ncp.CPTY_NORM_NM),
       ncp.CPTY_ACCT_KEY,
       ncp.CPTY_NORM_NM,
       ncp.CPTY_BIC_CD,
       ncp.CPTY_CTRY_CD,
       ncp.FIRST_SEEN_DT,
       ncp.FIRST_SEEN_DT,
       0,
       tms.LOAD_TMS
FROM
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_NEW_CPTY   ncp

       CROSS JOIN
       (SELECT ZEROIFNULL (MAX (CPTY_ID)) AS MAX_CPTY_ID
        FROM   <DB_ENV>DB_ODS.CPTY
       )                                          mx

       CROSS JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS   tms
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* MAINTAIN LAST SEEN DATE AND TRANSACTION COUNT                            *
\**************************************************************************/

UPDATE cpt
FROM   <DB_ENV>DB_ODS.CPTY   cpt,
       (SELECT CPTY_ACCT_KEY,
               CPTY_NORM_NM,
               MAX (BOOKING_DT)   AS LAST_SEEN_DT,
               COUNT (*)          AS TXN_CNT,
               MAX (CPTY_BIC_CD)  AS CPTY_BIC_CD
        FROM   VT_DLYTXN_CPTY_KEY
        GROUP  BY 1, 2
       )                     agg,
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_LOAD_TMS tms
SET    LAST_SEEN_DT = CASE WHEN agg.LAST_SEEN_DT > cpt.LAST_SEEN_DT
                           THEN agg.LAST_SEEN_DT
                           ELSE cpt.LAST_SEEN_DT END,
       TXN_CNT      = ZEROIFNULL (cpt.TXN_CNT) + agg.TXN_CNT,
       CPTY_BIC_CD  = COALESCE (cpt.CPTY_BIC_CD, agg.CPTY_BIC_CD),
       CO_UPD_TMS   = tms.LOAD_TMS
WHERE  cpt.CPTY_ACCT_KEY = agg.CPTY_ACCT_KEY
AND    cpt.CPTY_NORM_NM  = agg.CPTY_NORM_NM
;
.if errorcode <> 0 then .quit errorcode;


/**************************************************************************\
* RESOLVE COUNTERPARTY PER TRANSACTION                                     *
* ------------------------------------------------------------------------ *
* Counterparties holding an account with the bank are flagged as internal  *
* and linked to the primary party of that account. This allows the         *
* transaction monitoring to follow funds between own customers (mule       *
* chains, layering through related accounts).                              *
\**************************************************************************/

DELETE FROM <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_CPTY
;
.if errorcode <> 0 then .quit errorcode;

INSERT INTO <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_CPTY
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
       <DB_ENV>DB_ODS.CPTY                        cpt
          ON  cpt.CPTY_ACCT_KEY = vk.CPTY_ACCT_KEY
          AND cpt.CPTY_NORM_NM  = vk.CPTY_NORM_NM

       LEFT OUTER JOIN
       <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_NEW_CPTY   ncp
          ON  ncp.CPTY_ACCT_KEY = vk.CPTY_ACCT_KEY
          AND ncp.CPTY_NORM_NM  = vk.CPTY_NORM_NM

       LEFT OUTER JOIN
       <DB_ENV>DB_ODS.ACCT                        act
          ON  act.ACCT_ID = vk.CPTY_UK_ACCT_ID
;
.if errorcode <> 0 then .quit errorcode;

COLLECT STATISTICS <DB_ENV>DB_TRANS_IMPORTS.DLYTXN_CPTY INDEX (TXN_REF, SUPPLIER_CD);
COLLECT STATISTICS <DB_ENV>DB_ODS.CPTY INDEX (CPTY_ID);

DROP TABLE VT_DLYTXN_CPTY_KEY
;
.if errorcode <> 0 then .quit errorcode;

.quit 0;

