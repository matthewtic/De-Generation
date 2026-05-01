/* 
KPI: UW KPI #5 Renewal Quote Sent Before Effective Date
Definition: Measures days quote is sent prior to renewal effective date
Scope: Renewals Only
Window: Last Two Full Weeks (Mon–Sun)
Driver: Renewal Quote Sent Date (multi-source fallback)
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
    DATEPART(YEAR, COALESCE(q2a.QuoteToAgDt, dms.RenInvDt, qs.QuoteSentDt_Tracer, qt.quote_dt, qt.created_dt)) AS [Week Year],
    DATEPART(ISO_WEEK, COALESCE(q2a.QuoteToAgDt, dms.RenInvDt, qs.QuoteSentDt_Tracer, qt.quote_dt, qt.created_dt)) AS [Week Of Year],

    LTRIM(RTRIM(uw.first_name)) +
    CASE WHEN LTRIM(RTRIM(uw.last_name)) = '' THEN ''
         ELSE ' ' + LTRIM(RTRIM(uw.last_name)) END        AS [Underwriter],

    'Renewal'                                             AS [Transaction Type],

    sb.submission_code                                    AS [Submission Number],
    qt.quote_code                                         AS [Quote Number],
    qt.policy_number                                      AS [Policy Number],

    CASE
        WHEN qt.bind_dt IS NULL THEN 'Not Bound'
        WHEN qt.bind_dt IS NOT NULL AND qt.trans_finalize_dt IS NULL THEN 'Bound – Not Finalized'
        WHEN qt.bind_dt IS NOT NULL AND qt.trans_finalize_dt IS NOT NULL THEN 'Policy Finalized'
        ELSE 'Unknown'
    END                                                   AS [Policy Status],

    opx.EffDate                                           AS [Renewal Effective Dt],

    CONVERT(date, COALESCE(q2a.QuoteToAgDt, dms.RenInvDt, qs.QuoteSentDt_Tracer, qt.quote_dt, qt.created_dt)) AS [Renewal Quote Sent Dt],

    CONVERT(date, qt.trans_finalize_dt)                   AS [Finalize Dt],

    CASE
        WHEN opx.EffDate IS NULL OR COALESCE(q2a.QuoteToAgDt, dms.RenInvDt, qs.QuoteSentDt_Tracer, qt.quote_dt, qt.created_dt) IS NULL THEN NULL
        ELSE DATEDIFF(DAY, COALESCE(q2a.QuoteToAgDt, dms.RenInvDt, qs.QuoteSentDt_Tracer, qt.quote_dt, qt.created_dt), opx.EffDate)
    END AS [KPI5 Days QuoteSentBeforeEff],

    CASE
        WHEN opx.EffDate IS NULL OR COALESCE(q2a.QuoteToAgDt, dms.RenInvDt, qs.QuoteSentDt_Tracer, qt.quote_dt, qt.created_dt) IS NULL THEN NULL
        WHEN DATEDIFF(DAY, COALESCE(q2a.QuoteToAgDt, dms.RenInvDt, qs.QuoteSentDt_Tracer, qt.quote_dt, qt.created_dt), opx.EffDate) < 0 THEN 'Data Issue'
        WHEN DATEDIFF(DAY, COALESCE(q2a.QuoteToAgDt, dms.RenInvDt, qs.QuoteSentDt_Tracer, qt.quote_dt, qt.created_dt), opx.EffDate) >= 45 THEN 'Green'
        ELSE 'Red'
    END AS [KPI5 Status]

FROM dbo.bms_quote_mst qt
JOIN dbo.bms_submission_mst sb
     ON sb.submission_id = qt.submission_id
JOIN dbo.adm_co_users uw
     ON uw.user_id = sb.user_id_AccExecutive
LEFT JOIN dbo.adm_bm_lkp_transaction_types tt
     ON tt.lkp_id = qt.lkp_transaction_type_id

OUTER APPLY (
    SELECT TOP 1 TRY_CONVERT(date, op.effective_dt) AS EffDate
    FROM dbo.bms_options_mst op
    WHERE op.quote_id = qt.quote_id
      AND ISNULL(op.flg_active,1) = 1
    ORDER BY ISNULL(op.updated_dt, op.created_dt) DESC
) opx

OUTER APPLY (
    SELECT MIN(dd.created_dt) AS QuoteToAgDt
    FROM dbo.dms_file_mst df
    JOIN dbo.dms_document_detail_mst dd
         ON dd.file_id = df.file_id
    WHERE df.submission_number = sb.submission_code
      AND ISNULL(df.flg_active,1) = 1
      AND ISNULL(df.purge_status,0) = 0
      AND ISNULL(dd.purge_status,0) = 0
      AND (UPPER(LTRIM(RTRIM(dd.document_name))) LIKE 'QUOTE TO AG%'
           OR UPPER(LTRIM(RTRIM(dd.document_name))) LIKE 'QUOTE TO AGENT%')
) q2a

OUTER APPLY (
    SELECT MIN(tr.created_dt) AS QuoteSentDt_Tracer
    FROM dbo.bms_tracers tr
    WHERE tr.quote_id = qt.quote_id
      AND tr.tracer_desc IN ('Quote Sent','Renewal Quote Sent')
) qs

OUTER APPLY (
    SELECT MIN(dd.created_dt) AS RenInvDt
    FROM dbo.dms_file_mst df
    JOIN dbo.dms_document_detail_mst dd
         ON dd.file_id = df.file_id
    WHERE df.submission_number = sb.submission_code
      AND ISNULL(df.flg_active,1) = 1
      AND ISNULL(df.purge_status,0) = 0
      AND ISNULL(dd.purge_status,0) = 0
      AND UPPER(LTRIM(RTRIM(dd.document_name))) LIKE 'DBI RENEWAL INVOICE%'
) dms

CROSS JOIN WeekWindow ww
WHERE
    tt.lkp_desc IN ('Renewal','Renewals')
    AND COALESCE(q2a.QuoteToAgDt, dms.RenInvDt, qs.QuoteSentDt_Tracer, qt.quote_dt, qt.created_dt) IS NOT NULL
    AND CONVERT(date, COALESCE(q2a.QuoteToAgDt, dms.RenInvDt, qs.QuoteSentDt_Tracer, qt.quote_dt, qt.created_dt)) >= ww.StartDt
    AND CONVERT(date, COALESCE(q2a.QuoteToAgDt, dms.RenInvDt, qs.QuoteSentDt_Tracer, qt.quote_dt, qt.created_dt)) < ww.EndDt
    AND ISNULL(qt.flg_active,1) = 1
    AND ISNULL(qt.purge_status,0) = 0
    AND ISNULL(sb.flg_active,1) = 1
    AND ISNULL(sb.purge_status,0) = 0
    AND uw.user_id IS NOT NULL

ORDER BY
    [Underwriter],
    [Renewal Quote Sent Dt],
    [Renewal Effective Dt];