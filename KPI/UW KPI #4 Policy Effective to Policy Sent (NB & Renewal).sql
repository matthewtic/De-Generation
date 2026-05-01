/* 
KPI: UW KPI #4 Policy Effective Date to Policy Sent (New Business & Renewal)
Definition: Measures calendar days from policy effective date to policy sent
Scope: New Business + Renewal
Window: Last Two Full Weeks (Mon–Sun)
Driver: Policy Sent Date (DMS preferred, fallback finalize_dt)
*/

;WITH WeekWindow AS
(
    SELECT
        CAST(
            DATEADD(
                DAY,
                - (DATEDIFF(DAY, 0, DATEADD(DAY, -14, CAST(GETDATE() AS date))) % 7),
                DATEADD(DAY, -14, CAST(GETDATE() AS date))
            ) AS date
        ) AS StartDt,
        CAST(
            DATEADD(
                DAY,
                - (DATEDIFF(DAY, 0, CAST(GETDATE() AS date)) % 7),
                CAST(GETDATE() AS date)
            ) AS date
        ) AS EndDt
)
SELECT
    DATEPART(YEAR, COALESCE(dmsPolicy.PolicyToAgtDt, qt.trans_finalize_dt)) AS [Week Year],
    DATEPART(ISO_WEEK, COALESCE(dmsPolicy.PolicyToAgtDt, qt.trans_finalize_dt)) AS [Week Of Year],

    LTRIM(RTRIM(uw.first_name)) +
    CASE WHEN LTRIM(RTRIM(uw.last_name)) = '' THEN ''
         ELSE ' ' + LTRIM(RTRIM(uw.last_name)) END          AS [Underwriter],

    tt.lkp_desc                                             AS [Transaction Type],

    sb.submission_code                                      AS [Submission Number],
    qt.quote_code                                           AS [Quote Number],
    qt.policy_number                                        AS [Policy Number],

    CASE
        WHEN qt.bind_dt IS NULL THEN 'Not Bound'
        WHEN qt.bind_dt IS NOT NULL AND qt.trans_finalize_dt IS NULL THEN 'Bound – Not Finalized'
        WHEN qt.bind_dt IS NOT NULL AND qt.trans_finalize_dt IS NOT NULL THEN 'Policy Finalized'
        ELSE 'Unknown'
    END                                                     AS [Policy Status],

    opx.EffDate                                             AS [Policy Effective Dt],

    CONVERT(date, COALESCE(dmsPolicy.PolicyToAgtDt, qt.trans_finalize_dt)) AS [Policy Sent Dt],

    DATEDIFF(
        DAY,
        opx.EffDate,
        COALESCE(dmsPolicy.PolicyToAgtDt, qt.trans_finalize_dt)
    )                                                       AS [KPI4 Calendar Days Eff→PolicySent],

    CASE
        WHEN DATEDIFF(DAY, opx.EffDate, COALESCE(dmsPolicy.PolicyToAgtDt, qt.trans_finalize_dt)) < 0 THEN 'Data Issue'
        WHEN DATEDIFF(DAY, opx.EffDate, COALESCE(dmsPolicy.PolicyToAgtDt, qt.trans_finalize_dt)) <= 30 THEN 'Green'
        ELSE 'Red'
    END                                                     AS [KPI4 Status]

FROM dbo.bms_quote_mst qt
JOIN dbo.bms_submission_mst sb
     ON sb.submission_id = qt.submission_id
JOIN dbo.adm_co_users uw
     ON uw.user_id = sb.user_id_AccExecutive
LEFT JOIN dbo.adm_bm_lkp_transaction_types tt
     ON tt.lkp_id = qt.lkp_transaction_type_id

OUTER APPLY (
    SELECT TOP 1
           TRY_CONVERT(date, op.effective_dt) AS EffDate
    FROM dbo.bms_options_mst op
    WHERE op.quote_id = qt.quote_id
      AND ISNULL(op.flg_active,1) = 1
    ORDER BY ISNULL(op.updated_dt, op.created_dt) DESC
) opx

OUTER APPLY (
    SELECT MIN(dd.created_dt) AS PolicyToAgtDt
    FROM dbo.dms_file_mst df
    JOIN dbo.dms_document_detail_mst dd
         ON dd.file_id = df.file_id
    WHERE df.submission_number = sb.submission_code
      AND ISNULL(df.flg_active,1) = 1
      AND ISNULL(df.purge_status,0) = 0
      AND ISNULL(dd.purge_status,0) = 0
      AND UPPER(dd.document_name) LIKE '%POLICY%'
      AND UPPER(dd.document_name) LIKE '%TO%'
      AND UPPER(dd.document_name) LIKE '%AG%'
) dmsPolicy

CROSS JOIN WeekWindow ww
WHERE
    tt.lkp_desc IN ('New Business', 'Renewal')
    AND COALESCE(dmsPolicy.PolicyToAgtDt, qt.trans_finalize_dt) IS NOT NULL
    AND CONVERT(date, COALESCE(dmsPolicy.PolicyToAgtDt, qt.trans_finalize_dt)) >= ww.StartDt
    AND CONVERT(date, COALESCE(dmsPolicy.PolicyToAgtDt, qt.trans_finalize_dt)) <  ww.EndDt
    AND ISNULL(qt.flg_active,1) = 1
    AND ISNULL(qt.purge_status,0) = 0
    AND ISNULL(sb.flg_active,1) = 1
    AND ISNULL(sb.purge_status,0) = 0
    AND uw.user_id IS NOT NULL

ORDER BY
    [Underwriter],
    [Policy Sent Dt],
    [Policy Effective Dt];