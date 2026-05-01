/* ============================================================
   Renewals Forecast
   - In-force and future-expiring policies
   - Excludes endorsements and cancellations
   - Agency + Underwriter aligned to MTD logic
   ============================================================ */

SELECT
    CONVERT(NVARCHAR(50),  ag.agency_code)  AS [Agency Code],
    CONVERT(NVARCHAR(150), ag.agency_name)  AS [Agency Name],

    LTRIM(RTRIM(ISNULL(CONVERT(NVARCHAR(100), usr.first_name), '')))
        + N' '
        + LTRIM(RTRIM(ISNULL(CONVERT(NVARCHAR(100), usr.middle_name), '')))
        + CASE
              WHEN LTRIM(RTRIM(ISNULL(CONVERT(NVARCHAR(100), usr.last_name), ''))) = N''
              THEN N''
              ELSE N' ' + LTRIM(RTRIM(ISNULL(CONVERT(NVARCHAR(100), usr.last_name), '')))
          END                                  AS [Underwriter],

    CONVERT(NVARCHAR(100), qt.policy_number)   AS [Policy Number],
    CONVERT(NVARCHAR(100), sb.submission_code) AS [Submission Number],
    CONVERT(NVARCHAR(100), qt.quote_id)        AS [Quote ID],

    CASE
        WHEN qt.bind_dt IS NULL THEN 'Not Bound'
        WHEN qt.bind_dt IS NOT NULL
             AND qt.trans_finalize_dt IS NULL
             THEN 'Bound – Not Finalized'
        WHEN qt.bind_dt IS NOT NULL
             AND qt.trans_finalize_dt IS NOT NULL
             THEN 'Policy Finalized'
        ELSE 'Unknown'
    END                                        AS [Policy Status],

    ISNULL(CONVERT(NVARCHAR(100), tt.lkp_desc), N'') AS [Transaction Type],

    CONVERT(NVARCHAR(10), op.effective_dt,      110) AS [Effective Date],
    CONVERT(NVARCHAR(10), op.proposed_exp_date, 110) AS [Expiration Date],

    CONVERT(NVARCHAR(50), op.sub_total_premium) AS [Written Premium],

    ISNULL(LTRIM(RTRIM(ins.adr_phy_city)),        N'') AS [Risk City],
    ISNULL(LTRIM(RTRIM(ins.adr_phy_state_code)), N'') AS [Risk State],
    ISNULL(LTRIM(RTRIM(ins.adr_phy_zip)),        N'') AS [Risk Zip]

FROM dbo.bms_options_mst        op   WITH (NOLOCK)
JOIN dbo.bms_quote_mst          qt   WITH (NOLOCK)
     ON qt.quote_id = op.quote_id
LEFT JOIN dbo.bms_submission_mst sb  WITH (NOLOCK)
     ON sb.submission_id = qt.submission_id
LEFT JOIN dbo.bms_quote_insured_mst ins WITH (NOLOCK)
     ON ins.quote_id = qt.quote_id

LEFT JOIN dbo.adm_co_agencies   ag   WITH (NOLOCK)
       ON ag.agency_id = COALESCE(
            qt.original_producer_id,
            sb.original_producer_id
       )

LEFT JOIN dbo.adm_co_users      usr  WITH (NOLOCK)
       ON usr.user_id = op.user_id_acc_executive

LEFT JOIN dbo.adm_bm_lkp_transaction_types tt WITH (NOLOCK)
       ON tt.lkp_id = qt.lkp_transaction_type_id

WHERE
    ISNULL(qt.flg_active, 1) = 1
    AND ISNULL(op.flg_active, 1) = 1

    AND qt.policy_number IS NOT NULL
    AND LTRIM(RTRIM(CONVERT(NVARCHAR(100), qt.policy_number))) <> N''

    AND op.proposed_exp_date > CAST(GETDATE() AS DATE)

    AND (
            tt.lkp_desc IS NULL
         OR (
                tt.lkp_desc NOT IN ('Endorsement','Endorsements',
                                    'Cancellation','Cancellations')
            AND tt.lkp_desc NOT LIKE 'Cancel%'
            )
        );