/* 
Report: Autobot - New Business Quote Offered KPI [FULL]
Window: Prior Month Through Today
Driver: Quote Sent Date
Filters: Premium > 2500, Status = New Business Quote Offered
*/

SELECT
    CONVERT(NVARCHAR(100), qt.quote_code) AS quote_code,
    CONVERT(NVARCHAR(100), op.business_id) AS business_id,
    CONVERT(NVARCHAR(10), qs.quote_sent_dt, 110) AS quote_sent_date,
    CONVERT(NVARCHAR(10), DATEADD(DAY, 3, qs.quote_sent_dt), 110) AS first_follow_up_due_date,
    CONVERT(NVARCHAR(10), DATEADD(DAY, 25, qs.quote_sent_dt), 110) AS second_follow_up_due_date,
    CONVERT(NVARCHAR(10), DATEADD(DAY, 30, qs.quote_sent_dt), 110) AS qcl_due_date,
    CONVERT(NVARCHAR(10), op.proposed_eff_date, 110) AS proposed_eff_date,
    CONVERT(NVARCHAR(10), op.proposed_exp_date, 110) AS proposed_exp_date,
    CONVERT(NVARCHAR(50), ISNULL(op.sub_total_premium, 0)) AS premium,
    CONVERT(NVARCHAR(400), st.main_status_text) AS quote_status
FROM bms_quote_mst qt WITH (NOLOCK)
JOIN bms_options_mst op WITH (NOLOCK)
    ON op.quote_id = qt.quote_id
   AND op.flg_active = 1
LEFT JOIN adm_bm_statuses st WITH (NOLOCK)
    ON st.status_id = qt.status_id
OUTER APPLY
(
    SELECT
        MIN(x.sent_dt) AS quote_sent_dt
    FROM
    (
        SELECT
            cd.created_dt AS sent_dt
        FROM bms_email_confirmation_details cd WITH (NOLOCK)
        JOIN adm_co_lkp_email_process_parameters pp WITH (NOLOCK)
            ON pp.lkp_id = cd.lkp_email_process_parameter_id
        WHERE cd.business_id = op.business_id
          AND cd.quote_id = qt.quote_id
          AND pp.lkp_code = 'QUOTE'
          AND cd.flg_active = 1

        UNION ALL

        SELECT
            tm.created_dt AS sent_dt
        FROM bms_template_memos tm WITH (NOLOCK)
        JOIN adm_co_lkp_email_process_parameters pp WITH (NOLOCK)
            ON pp.lkp_id = tm.lkp_email_process_parameters_id
        WHERE tm.business_id = op.business_id
          AND tm.quote_id = qt.quote_id
          AND pp.lkp_code = 'QUOTE'
          AND tm.flg_active = 1
    ) x
) qs
WHERE qt.flg_active = 1
  AND qs.quote_sent_dt IS NOT NULL
  AND qs.quote_sent_dt >= DATEADD(MONTH, -1, DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()), 0))
  AND qs.quote_sent_dt < DATEADD(DAY, 1, CAST(GETDATE() AS DATE))
  AND ISNULL(op.sub_total_premium, 0) > 2500
  AND CONVERT(NVARCHAR(400), st.main_status_text) = 'New Business Quote Offered'
ORDER BY qs.quote_sent_dt ASC;