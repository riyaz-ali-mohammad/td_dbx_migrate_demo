----------------------------------------
-- Consumption view on transaction monitoring alerts.
-- Row filter : segment of the alerted party must be granted to the session user.
----------------------------------------

-- Converted Teradata REPLACE VIEW to CREATE OR REPLACE VIEW.
-- Removed Teradata FOR ACCESS locking hints; Delta reads a committed snapshot.
-- assumption: Teradata databases map to same-named schemas in the current Unity Catalog.
-- Converted the Teradata USER session expression to CURRENT_USER().
CREATE OR REPLACE VIEW vx_aml.tm_alert
AS
SELECT al.alert_id,
       al.rule_cd,
       al.party_id,
       al.acct_id,
       COALESCE(psn.segment_cd, 'RET') AS segment_cd,
       al.business_dt,
       al.alert_tms,
       al.alert_score,
       al.hit_gbp_amt,
       al.hit_cnt,
       al.lookback_start_dt,
       al.lookback_end_dt,
       al.trigger_txn_ref,
       al.trigger_supplier_cd,
       al.alert_status_cd,
       al.suppress_reason_cd,
       al.case_id,
       al.hit_detail,
       al.co_upd_tms
FROM db_aml.tm_alert AS al
LEFT OUTER JOIN db_ods.party_snapshot AS psn
    ON psn.party_id = al.party_id
INNER JOIN db_reference.view_access_ctrl AS acc
    ON acc.segment_cd = COALESCE(psn.segment_cd, 'RET')
   AND acc.user_nm = CURRENT_USER();
