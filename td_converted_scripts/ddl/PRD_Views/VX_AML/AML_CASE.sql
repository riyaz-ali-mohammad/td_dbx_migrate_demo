----------------------------------------
-- Consumption view on AML investigation cases.
-- Row filter : case segment must be granted to the session user.
----------------------------------------

-- Converted Teradata REPLACE VIEW to CREATE OR REPLACE VIEW.
-- Removed LOCKING TABLE FOR ACCESS hints; Delta reads committed snapshots.
-- assumption: Source database names map to schemas with the same names in the current catalog.
-- Preserved Teradata trailing-space comparison semantics with RTRIM.
-- Converted the Teradata USER special register to CURRENT_USER().
CREATE OR REPLACE VIEW VX_AML.AML_CASE
AS
SELECT cse.CASE_ID,
       cse.PARTY_ID,
       cse.CASE_OPEN_DT,
       cse.CASE_STATUS_CD,
       cse.CASE_PRIORITY_NR,
       cse.QUEUE_CD,
       cse.SLA_DUE_DT,
       CASE WHEN RTRIM(cse.CASE_STATUS_CD) <> RTRIM('CLOSD')
             AND cse.SLA_DUE_DT < CURRENT_DATE
            THEN 'Y' ELSE 'N'
       END                                  AS OVER_SLA_IND,
       cse.ALERT_CNT,
       cse.TOTAL_ALERT_SCORE,
       cse.TOTAL_HIT_GBP_AMT,
       cse.RULE_LIST,
       cse.SAR_CANDIDATE_IND,
       cse.RISK_BAND_CD,
       cse.SEGMENT_CD,
       cse.FIRST_ALERT_DT,
       cse.LAST_ALERT_DT,
       cse.CASE_CLOSE_DT,
       cse.CLOSE_REASON_CD,
       cse.CO_UPD_TMS
FROM DB_AML.AML_CASE AS cse
INNER JOIN DB_REFERENCE.VIEW_ACCESS_CTRL AS acc
        ON RTRIM(acc.SEGMENT_CD) = RTRIM(cse.SEGMENT_CD)
       AND RTRIM(acc.USER_NM) = RTRIM(CURRENT_USER());
