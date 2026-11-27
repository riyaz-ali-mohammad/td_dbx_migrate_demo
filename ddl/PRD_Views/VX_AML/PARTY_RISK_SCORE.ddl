----------------------------------------
-- Consumption view on the customer risk score.
-- Row filter : customer segment must be granted to the session user.
-- Column mask: customer name and date of birth unless PII_ACCESS_IND = 'Y'
----------------------------------------

REPLACE VIEW VX_AML.PARTY_RISK_SCORE
AS
LOCKING TABLE DB_AML.PARTY_RISK_SCORE       FOR ACCESS
LOCKING TABLE DB_ODS.PARTY                  FOR ACCESS
LOCKING TABLE DB_REFERENCE.VIEW_ACCESS_CTRL FOR ACCESS

SELECT prs.PARTY_ID,
       pty.PARTY_TYP_CD,
       CASE WHEN acc.PII_ACCESS_IND = 'Y' THEN pty.FULL_NM
            ELSE CAST ('*** MASKED ***' AS VARCHAR(100))
       END                                  AS FULL_NM,
       CASE WHEN acc.PII_ACCESS_IND = 'Y' THEN pty.BIRTH_DT
            ELSE CAST (NULL AS DATE)
       END                                  AS BIRTH_DT,
       pty.SEGMENT_CD,
       pty.RESIDENCE_CTRY_CD,
       pty.NATIONALITY_CD,
       pty.PEP_IND,
       pty.KYC_STATUS_CD,
       pty.KYC_REVIEW_DUE_DT,
       prs.SCORE_DT,
       prs.CTRY_SCORE,
       prs.PEP_SCORE,
       prs.OCCP_SCORE,
       prs.PRDT_SCORE,
       prs.CHNL_SCORE,
       prs.ALERT_SCORE,
       prs.SANC_SCORE,
       prs.KYC_SCORE,
       prs.ADV_MEDIA_SCORE,
       prs.TOTAL_SCORE,
       prs.RISK_BAND_CD,
       prs.PREV_RISK_BAND_CD,
       prs.BAND_CHG_IND,
       prs.EDD_REQUIRED_IND,
       prs.NEXT_REVIEW_DT,
       prs.CO_UPD_TMS
FROM
       DB_AML.PARTY_RISK_SCORE         prs

       INNER JOIN
       DB_ODS.PARTY                    pty
          ON  pty.PARTY_ID = prs.PARTY_ID

       INNER JOIN
       DB_REFERENCE.VIEW_ACCESS_CTRL   acc
          ON  acc.SEGMENT_CD = pty.SEGMENT_CD
          AND acc.USER_NM    = USER;
