/* 
KPI: UW KPI #2 Binder Request to Binder Sent (New Business & Renewal)
Definition: Measures business days from binder request to binder sent
Scope: New Business + Renewal
Window: Last Two Full Weeks (Mon–Sun)
Driver: Binder Sent Date (DMS)
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
    DATEPART(YEAR,     bind_sent.BinderSentDt) AS [Week Year],
    DATEPART(ISO_WEEK, bind_sent.BinderSentDt) AS [Week Of Year],

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

    bind_req.BinderRequestDt                                AS [Binder Requested DtTime],
    bind_sent.BinderSentDt                                  AS [Binder Sent DtTime],
    CONVERT(date, bind_sent.BinderSentDt)                   AS [Binder Sent Dt],

    kpi2.BusinessDaysLag                                    AS [KPI2 Business Days Request→BinderSent],

    CASE
        WHEN bind_req.BinderRequestDt IS NULL THEN 'No Binder Request Found'
        WHEN bind_sent.BinderSentDt IS NULL THEN 'No Binder Sent Found'
        WHEN kpi2.BusinessDaysLag IS NULL THEN NULL
        WHEN kpi2.BusinessDaysLag < 0 THEN 'Data Issue'
        WHEN kpi2.BusinessDaysLag <= 5 THEN 'Green'
        ELSE 'Red'
    END                                                     AS [KPI2 Status]

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
    SELECT MIN(dd.created_dt) AS BinderRequestDt
    FROM dbo.dms_file_mst df
    JOIN dbo.dms_document_detail_mst dd
         ON dd.file_id = df.file_id
    WHERE df.submission_number = sb.submission_code
      AND ISNULL(df.flg_active,1) = 1
      AND ISNULL(df.purge_status,0) = 0
      AND ISNULL(dd.purge_status,0) = 0
      AND (
            UPPER(dd.document_name) LIKE '%RTB%'
         OR UPPER(dd.document_name) LIKE '%REQ TO BIND%'
         OR UPPER(dd.document_name) LIKE '%BIND REQ%'
         OR UPPER(dd.document_name) LIKE '%REQUEST TO BIND%'
         OR UPPER(dd.document_name) LIKE '%BIND REQUEST%'
      )
) bind_req

OUTER APPLY (
    SELECT TOP 1 dd.created_dt AS BinderSentDt
    FROM dbo.dms_file_mst df
    JOIN dbo.dms_document_detail_mst dd
         ON dd.file_id = df.file_id
    WHERE df.submission_number = sb.submission_code
      AND ISNULL(df.flg_active,1) = 1
      AND ISNULL(df.purge_status,0) = 0
      AND ISNULL(dd.purge_status,0) = 0
      AND (
            UPPER(dd.document_name) LIKE 'BINDER TO AG%'
         OR UPPER(dd.document_name) LIKE 'BINDER TO AGT%'
         OR UPPER(dd.document_name) LIKE 'BINDER TO AGENT%'
      )
      AND bind_req.BinderRequestDt IS NOT NULL
      AND dd.created_dt >= bind_req.BinderRequestDt
    ORDER BY dd.created_dt
) bind_sent

OUTER APPLY (
    SELECT
        CASE
            WHEN bind_req.BinderRequestDt IS NULL OR bind_sent.BinderSentDt IS NULL THEN NULL
            ELSE
                DATEDIFF(DAY, CAST(bind_req.BinderRequestDt AS date), CAST(bind_sent.BinderSentDt AS date)) + 1
                - (DATEDIFF(WEEK, CAST(bind_req.BinderRequestDt AS date), CAST(bind_sent.BinderSentDt AS date)) * 2)
                - CASE WHEN DATENAME(WEEKDAY, CAST(bind_req.BinderRequestDt AS date)) = 'Sunday' THEN 1 ELSE 0 END
                - CASE WHEN DATENAME(WEEKDAY, CAST(bind_sent.BinderSentDt AS date)) = 'Saturday' THEN 1 ELSE 0 END
        END AS BusinessDaysLag
) kpi2

CROSS JOIN WeekWindow ww
WHERE
    tt.lkp_desc IN ('New Business', 'Renewal')
    AND bind_sent.BinderSentDt IS NOT NULL
    AND CONVERT(date, bind_sent.BinderSentDt) >= ww.StartDt
    AND CONVERT(date, bind_sent.BinderSentDt) <  ww.EndDt
    AND ISNULL(qt.flg_active,1) = 1
    AND ISNULL(qt.purge_status,0) = 0
    AND ISNULL(sb.flg_active,1) = 1
    AND ISNULL(sb.purge_status,0) = 0
    AND uw.user_id IS NOT NULL

ORDER BY
    [Underwriter],
    [Binder Sent Dt],
    [Policy Effective Dt];