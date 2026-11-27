----------------------------------------
-- Consumption view on SAR candidates (tipping-off sensitive, POCA 2002 s.333A).
-- Only users with SAR_ACCESS_IND = 'Y' for the case segment see any rows.
----------------------------------------

-- Converted Teradata REPLACE VIEW to Databricks CREATE OR REPLACE VIEW.
-- assumption: Teradata databases are provisioned as schemas in the current Unity Catalog.
-- assumption: LOCKING TABLE FOR ACCESS clauses were dropped; Delta reads a committed snapshot.
-- Converted the Teradata USER expression to the Databricks current_user() function.
CREATE OR REPLACE VIEW VX_AML.SAR_CANDIDATE
AS
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
          AND acc.USER_NM        = current_user()
          AND acc.SAR_ACCESS_IND = 'Y';
