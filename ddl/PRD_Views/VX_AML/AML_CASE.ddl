----------------------------------------
-- Consumption view on AML investigation cases.
-- Row filter : case segment must be granted to the session user.
----------------------------------------

REPLACE VIEW VX_AML.AML_CASE
AS
LOCKING TABLE DB_AML.AML_CASE               FOR ACCESS
LOCKING TABLE DB_REFERENCE.VIEW_ACCESS_CTRL FOR ACCESS

SELECT cse.CASE_ID,
       cse.PARTY_ID,
       cse.CASE_OPEN_DT,
       cse.CASE_STATUS_CD,
       cse.CASE_PRIORITY_NR,
       cse.QUEUE_CD,
       cse.SLA_DUE_DT,
       CASE WHEN cse.CASE_STATUS_CD <> 'CLOSD'
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
FROM
       DB_AML.AML_CASE                 cse

       INNER JOIN
       DB_REFERENCE.VIEW_ACCESS_CTRL   acc
          ON  acc.SEGMENT_CD = cse.SEGMENT_CD
          AND acc.USER_NM    = USER;
