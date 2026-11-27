----------------------------------------
-- Consumption view on transaction monitoring alerts.
-- Row filter : segment of the alerted party must be granted to the session user.
----------------------------------------

REPLACE VIEW VX_AML.TM_ALERT
AS
LOCKING TABLE DB_AML.TM_ALERT               FOR ACCESS
LOCKING TABLE DB_ODS.PARTY_SNAPSHOT         FOR ACCESS
LOCKING TABLE DB_REFERENCE.VIEW_ACCESS_CTRL FOR ACCESS

SELECT al.ALERT_ID,
       al.RULE_CD,
       al.PARTY_ID,
       al.ACCT_ID,
       COALESCE (psn.SEGMENT_CD, 'RET')     AS SEGMENT_CD,
       al.BUSINESS_DT,
       al.ALERT_TMS,
       al.ALERT_SCORE,
       al.HIT_GBP_AMT,
       al.HIT_CNT,
       al.LOOKBACK_START_DT,
       al.LOOKBACK_END_DT,
       al.TRIGGER_TXN_REF,
       al.TRIGGER_SUPPLIER_CD,
       al.ALERT_STATUS_CD,
       al.SUPPRESS_REASON_CD,
       al.CASE_ID,
       al.HIT_DETAIL,
       al.CO_UPD_TMS
FROM
       DB_AML.TM_ALERT                 al

       LEFT OUTER JOIN
       DB_ODS.PARTY_SNAPSHOT           psn
          ON  psn.PARTY_ID = al.PARTY_ID

       INNER JOIN
       DB_REFERENCE.VIEW_ACCESS_CTRL   acc
          ON  acc.SEGMENT_CD = COALESCE (psn.SEGMENT_CD, 'RET')
          AND acc.USER_NM    = USER;
