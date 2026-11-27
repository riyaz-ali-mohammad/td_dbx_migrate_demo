----------------------------------------
-- Consumption view on SAR candidates (tipping-off sensitive, POCA 2002 s.333A).
-- Only users with SAR_ACCESS_IND = 'Y' for the case segment see any rows.
----------------------------------------

REPLACE VIEW VX_AML.SAR_CANDIDATE
AS
LOCKING TABLE DB_AML.SAR_CANDIDATE          FOR ACCESS
LOCKING TABLE DB_AML.AML_CASE               FOR ACCESS
LOCKING TABLE DB_REFERENCE.VIEW_ACCESS_CTRL FOR ACCESS

SELECT sar.CASE_ID,
       sar.PARTY_ID,
       cse.SEGMENT_CD,
       cse.CASE_STATUS_CD,
       cse.CASE_PRIORITY_NR,
       cse.QUEUE_CD,
       sar.IDENT_DT,
       sar.SAR_REASON_CD,
       sar.TOTAL_GBP_AMT,
       sar.SANC_HIT_IND,
       sar.DAML_IND,
       sar.NARRATIVE_SUMMARY,
       sar.SAR_STATUS_CD,
       sar.CO_UPD_TMS
FROM
       DB_AML.SAR_CANDIDATE            sar

       INNER JOIN
       DB_AML.AML_CASE                 cse
          ON  cse.CASE_ID = sar.CASE_ID

       INNER JOIN
       DB_REFERENCE.VIEW_ACCESS_CTRL   acc
          ON  acc.SEGMENT_CD     = cse.SEGMENT_CD
          AND acc.USER_NM        = USER
          AND acc.SAR_ACCESS_IND = 'Y';
