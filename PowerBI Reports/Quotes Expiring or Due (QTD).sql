/* ===================== Quotes Expiring or Due (QTD)
   (Eff Dates Window Defined Below, Premium > 2,500)
   Agency Name + Agency Code aligned to MTD logic
================================================ */

;WITH Q1Window AS
(
    SELECT
        CONVERT(date, '2026-04-01') AS StartDt,
        CONVERT(date, '2026-06-30') AS EndDt
)
SELECT 
    CONVERT(NVARCHAR(100), sb.submission_code)                       AS [Submission Number],
    CONVERT(NVARCHAR(100), qt.quote_code)                            AS [Quote Number],

    LTRIM(RTRIM(ISNULL(CONVERT(NVARCHAR(100), usr.first_name), ''))) + N' ' +
    LTRIM(RTRIM(ISNULL(CONVERT(NVARCHAR(100), usr.middle_name), ''))) + N' ' +
    LTRIM(RTRIM(ISNULL(CONVERT(NVARCHAR(100), usr.last_name), '')))  AS [UWBroker],

    CONVERT(NVARCHAR(400), ins.insured_name)                         AS [Insured Name],

    CONVERT(NVARCHAR(100), ISNULL(ag.agency_code, N''))              AS [Agency Code],
    CONVERT(NVARCHAR(400), ISNULL(ag.agency_name, N''))              AS [Agency Name],

    LEFT(CONVERT(NVARCHAR(4000), tt.lkp_desc), 400)                  AS [Transaction Type],
    CONVERT(NVARCHAR(50), ISNULL(op.sub_total_premium, 0))           AS [Premium],
    CONVERT(NVARCHAR(10), op.proposed_eff_date, 110)                 AS [Proposed Eff Date],
    CONVERT(NVARCHAR(10), op.proposed_exp_date, 110)                 AS [Proposed Exp Date],

    CASE 
        WHEN op.proposed_eff_date IS NULL THEN NULL
        ELSE CONVERT(
            NVARCHAR(10),
            DATEDIFF(
                DAY,
                CONVERT(date, GETDATE()),
                CONVERT(date, op.proposed_eff_date)
            )
        )
    END                                                              AS [Days Until Effective Date],

    LEFT(CONVERT(NVARCHAR(4000), st.main_status_text), 400)          AS [Quote Status]

FROM bms_quote_mst qt            WITH (NOLOCK)
JOIN bms_options_mst op          WITH (NOLOCK)
     ON op.quote_id = qt.quote_id
JOIN bms_quote_insured_mst ins   WITH (NOLOCK)
     ON ins.quote_id = qt.quote_id
JOIN adm_co_users usr            WITH (NOLOCK)
     ON usr.user_id = op.user_id_acc_executive
LEFT JOIN adm_bm_lkp_transaction_types tt WITH (NOLOCK)
     ON tt.lkp_id = qt.lkp_transaction_type_id
LEFT JOIN bms_submission_mst sb  WITH (NOLOCK)
     ON sb.submission_id = qt.submission_id
LEFT JOIN adm_bm_statuses st     WITH (NOLOCK)
     ON st.status_id = qt.status_id

LEFT JOIN adm_co_agencies ag     WITH (NOLOCK)
       ON ag.agency_id = COALESCE(
            qt.original_producer_id,
            sb.original_producer_id
       )

CROSS APPLY Q1Window w
WHERE qt.flg_active = 1
  AND op.flg_active = 1
  AND op.proposed_eff_date >= w.StartDt
  AND op.proposed_eff_date <= w.EndDt
  AND ISNULL(op.sub_total_premium, 0) > 2500

  AND 1 = CASE 
            WHEN (
                SELECT COUNT(1)
                FROM bms_email_confirmation_details cd WITH (NOLOCK)
                JOIN adm_co_lkp_email_process_parameters pp WITH (NOLOCK)
                  ON pp.lkp_id = cd.lkp_email_process_parameter_id
                WHERE cd.business_id = op.business_id
                  AND cd.quote_id   = qt.quote_id
                  AND pp.lkp_code IN ('QUOTE','RENEWAL_QUOTE')
                  AND cd.flg_active = 1
            ) > 0
            OR (
                SELECT COUNT(1)
                FROM bms_template_memos tm WITH (NOLOCK)
                JOIN adm_co_lkp_email_process_parameters pp WITH (NOLOCK)
                  ON pp.lkp_id = tm.lkp_email_process_parameters_id
                WHERE tm.business_id = op.business_id
                  AND tm.quote_id    = qt.quote_id
                  AND pp.lkp_code IN ('QUOTE','RENEWAL_QUOTE')
                  AND tm.flg_active  = 1
            ) > 0
            THEN 1 ELSE 0 
          END

  AND st.status_code IN (
        'NB_QUOTE_OFFERED',
        'NB_BINDER_CANCELLED',
        'NB_BINDER_REQUESTED',
        'REN_QUOTE_OFFERED',
        'REN_BINDER_CANCELLED',
        'REN_BINDER_REQUESTED'
  )

ORDER BY
    op.proposed_eff_date ASC,
    sb.submission_code,
    qt.quote_code;