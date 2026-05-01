/* 
KPI: UW KPI #1 Submission to Quote Sent (New Business)
Definition: Measures business days from submission intake to first quote sent
Scope: New Business only
Window: Last Two Full Weeks (Mon–Sun)
Driver: Unified Quote Sent Date (DMS or Tracer)
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
    DATEPART(YEAR,     kpi1.QuoteSentDtTime) AS [Week Year],
    DATEPART(ISO_WEEK, kpi1.QuoteSentDtTime) AS [Week Of Year],

    LTRIM(RTRIM(uw.first_name)) +
    CASE WHEN LTRIM(RTRIM(uw.last_name)) = '' THEN ''
         ELSE ' ' + LTRIM(RTRIM(uw.last_name)) END     AS [Underwriter],

    'New Business'                                     AS [Transaction Type],

    sb.submission_code                                 AS [Submission Number],
    qt.quote_code                                      AS [Quote Number],
    qt.policy_number                                   AS [Policy Number],

    CASE
        WHEN qt.bind_dt IS NULL THEN 'Not Bound'
        WHEN qt.bind_dt IS NOT NULL AND qt.trans_finalize_dt IS NULL THEN 'Bound – Not Finalized'
        WHEN qt.bind_dt IS NOT NULL AND qt.trans_finalize_dt IS NOT NULL THEN 'Policy Finalized'
        ELSE 'Unknown'
    END                                                AS [Policy Status],

    opx.EffDate                                        AS [Policy Effective Dt],

    CONVERT(date, sb.created_dt)                       AS [Submission Received Dt],

    CONVERT(date, kpi1.QuoteSentDtTime)                AS [Quote Sent Dt],

    kpi1.BusinessDaysLag                               AS [KPI1 Business Days Submission→Quote],

    CASE
        WHEN kpi1.BusinessDaysLag IS NULL THEN NULL
        WHEN kpi1.BusinessDaysLag < 0  THEN 'Data Issue'
        WHEN kpi1.BusinessDaysLag <= 3 THEN 'Green'
        ELSE 'Red'
    END                                                AS [KPI1 Status]

FROM dbo.bms_submission_mst sb

OUTER APPLY (
    SELECT TOP 1 qt.*
    FROM dbo.bms_quote_mst qt
    LEFT JOIN dbo.adm_bm_lkp_transaction_types tt2
           ON tt2.lkp_id = qt.lkp_transaction_type_id
    WHERE
          qt.submission_id = sb.submission_id
      AND ISNULL(qt.flg_active,1) = 1
      AND ISNULL(qt.purge_status,0) = 0
      AND tt2.lkp_desc = 'New Business'
    ORDER BY
        CASE WHEN qt.bind_dt IS NOT NULL THEN 0 ELSE 1 END,
        qt.quote_id
) qt

JOIN dbo.adm_co_users uw
     ON uw.user_id = sb.user_id_AccExecutive

OUTER APPLY (
    SELECT TOP 1
           TRY_CONVERT(date, op.effective_dt) AS EffDate
    FROM dbo.bms_options_mst op
    WHERE op.quote_id = qt.quote_id
      AND ISNULL(op.flg_active,1) = 1
    ORDER BY ISNULL(op.updated_dt, op.created_dt) DESC
) opx

OUTER APPLY (
    SELECT MIN(dd.created_dt) AS QuoteToAgentDt
    FROM dbo.dms_file_mst df
    JOIN dbo.dms_document_detail_mst dd
         ON dd.file_id = df.file_id
    WHERE df.submission_number = sb.submission_code
      AND ISNULL(df.flg_active,1) = 1
      AND ISNULL(df.purge_status,0) = 0
      AND ISNULL(dd.purge_status,0) = 0
      AND (
              UPPER(LTRIM(RTRIM(dd.document_name))) LIKE '%QUOTE TO AG%'
           OR UPPER(LTRIM(RTRIM(dd.document_name))) LIKE '%QUOTE TO AGENT%'
          )
) dmsQuote

OUTER APPLY (
    SELECT MIN(tr.created_dt) AS QuoteSentDt
    FROM dbo.bms_tracers tr
    JOIN dbo.adm_bm_tracer_sub_types st
         ON st.tracer_sub_type_id = tr.tracer_sub_type_id
    WHERE tr.quote_id = qt.quote_id
      AND st.tracer_type_code = 'SSPNS'
      AND tr.tracer_desc LIKE 'Quote%'
) qs

OUTER APPLY (
    SELECT
        COALESCE(
            dmsQuote.QuoteToAgentDt,
            qs.QuoteSentDt
        ) AS QuoteSentDtTime,

        CASE
            WHEN COALESCE(dmsQuote.QuoteToAgentDt, qs.QuoteSentDt) IS NULL THEN NULL
            ELSE
                DATEDIFF(DAY, sb.created_dt, COALESCE(dmsQuote.QuoteToAgentDt, qs.QuoteSentDt))
                - (DATEDIFF(WEEK, sb.created_dt, COALESCE(dmsQuote.QuoteToAgentDt, qs.QuoteSentDt)) * 2)
                - CASE WHEN DATENAME(WEEKDAY, sb.created_dt) IN ('Saturday','Sunday') THEN 1 ELSE 0 END
                - CASE WHEN DATENAME(WEEKDAY, COALESCE(dmsQuote.QuoteToAgentDt, qs.QuoteSentDt)) = 'Saturday' THEN 1 ELSE 0 END
        END AS BusinessDaysLag
) kpi1

CROSS JOIN WeekWindow ww
WHERE
    qt.quote_id IS NOT NULL
    AND kpi1.QuoteSentDtTime IS NOT NULL
    AND CONVERT(date, kpi1.QuoteSentDtTime) >= ww.StartDt
    AND CONVERT(date, kpi1.QuoteSentDtTime) <  ww.EndDt
    AND ISNULL(sb.flg_active,1) = 1
    AND ISNULL(sb.purge_status,0) = 0
    AND uw.user_id IS NOT NULL

ORDER BY
    [Underwriter],
    [Quote Sent Dt],
    [Policy Effective Dt],
    [Submission Received Dt];