/* 
KPI: UW KPI #3 Endorsement Request to Endorsement Sent
Definition: Measures business days from endorsement request to endorsement sent
Scope: Endorsements Only
Window: Last Two Full Weeks (Mon–Sun)
Driver: Endorsement Sent Date (DMS preferred, fallback tracer)
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
    DATEPART(YEAR, COALESCE(dms.EndtToAgtDt, edx.SentDt)) AS [Week Year],
    DATEPART(ISO_WEEK, COALESCE(dms.EndtToAgtDt, edx.SentDt)) AS [Week Of Year],

    LTRIM(RTRIM(uw.first_name)) +
    CASE WHEN LTRIM(RTRIM(uw.last_name)) = '' THEN ''
         ELSE ' ' + LTRIM(RTRIM(uw.last_name)) END      AS [Underwriter],

    'Endorsement'                                       AS [Transaction Type],

    qt.quote_code                                       AS [Quote Number],
    qt.policy_number                                    AS [Policy Number],

    CASE
        WHEN qt.bind_dt IS NULL THEN 'Not Bound'
        WHEN qt.bind_dt IS NOT NULL AND qt.trans_finalize_dt IS NULL THEN 'Bound – Not Finalized'
        WHEN qt.bind_dt IS NOT NULL AND qt.trans_finalize_dt IS NOT NULL THEN 'Policy Finalized'
        ELSE 'Unknown'
    END                                                 AS [Policy Status],

    opx.EffDate                                         AS [Endorsement Effective Dt],

    edx.RequestDt                                       AS [Endorsement Requested DtTime],
    COALESCE(dms.EndtToAgtDt, edx.SentDt)              AS [Endorsement Sent DtTime],
    CONVERT(date, COALESCE(dms.EndtToAgtDt, edx.SentDt)) AS [Endorsement Sent Dt],

    kpi3.BusinessDaysLag                                AS [KPI3 Business Days Request→Sent],

    CASE
        WHEN edx.RequestDt IS NULL THEN 'No Endorsement Request Found'
        WHEN COALESCE(dms.EndtToAgtDt, edx.SentDt) IS NULL THEN 'No Endorsement Sent Found'
        WHEN kpi3.BusinessDaysLag IS NULL THEN NULL
        WHEN kpi3.BusinessDaysLag < 0 THEN 'Data Issue'
        WHEN kpi3.BusinessDaysLag <= 5 THEN 'Green'
        ELSE 'Red'
    END                                                  AS [KPI3 Status]

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
    SELECT
        MAX(CASE
                WHEN tr.tracer_desc LIKE 'Endorsement % start on policy No.%'
                  OR tr.tracer_desc LIKE 'Internal Endorsement% start on policy No.%'
                    THEN tr.created_dt
            END) AS RequestDt,
        MAX(CASE
                WHEN tr.tracer_desc LIKE 'Endorsement % Finalized on policy No.%'
                  OR tr.tracer_desc LIKE 'Internal Endorsement% Finalized on policy No.%'
                    THEN tr.created_dt
            END) AS SentDt
    FROM dbo.bms_tracers tr
    WHERE tr.quote_id = qt.quote_id
      AND tr.tracer_desc LIKE '%Endorsement%policy No.%'
) edx

OUTER APPLY (
    SELECT TOP 1 dd.created_dt AS EndtToAgtDt
    FROM dbo.dms_file_mst df
    JOIN dbo.dms_document_detail_mst dd
         ON dd.file_id = df.file_id
    WHERE df.submission_number = sb.submission_code
      AND ISNULL(df.flg_active,1) = 1
      AND ISNULL(df.purge_status,0) = 0
      AND ISNULL(dd.purge_status,0) = 0
      AND UPPER(dd.document_name) LIKE '%ENDT%'
      AND UPPER(dd.document_name) LIKE '%TO%'
      AND UPPER(dd.document_name) LIKE '%AG%'
      AND edx.RequestDt IS NOT NULL
      AND dd.created_dt >= edx.RequestDt
    ORDER BY dd.created_dt
) dms

OUTER APPLY (
    SELECT
        CASE
            WHEN edx.RequestDt IS NULL OR COALESCE(dms.EndtToAgtDt, edx.SentDt) IS NULL THEN NULL
            ELSE
                DATEDIFF(DAY, CAST(edx.RequestDt AS date), CAST(COALESCE(dms.EndtToAgtDt, edx.SentDt) AS date)) + 1
                - (DATEDIFF(WEEK, CAST(edx.RequestDt AS date), CAST(COALESCE(dms.EndtToAgtDt, edx.SentDt) AS date)) * 2)
                - CASE WHEN DATENAME(WEEKDAY, CAST(edx.RequestDt AS date)) = 'Sunday' THEN 1 ELSE 0 END
                - CASE WHEN DATENAME(WEEKDAY, CAST(COALESCE(dms.EndtToAgtDt, edx.SentDt) AS date)) = 'Saturday' THEN 1 ELSE 0 END
        END AS BusinessDaysLag
) kpi3

CROSS JOIN WeekWindow ww
WHERE
    tt.lkp_desc IN ('Endorsement','Endorsements')
    AND COALESCE(dms.EndtToAgtDt, edx.SentDt) IS NOT NULL
    AND CONVERT(date, COALESCE(dms.EndtToAgtDt, edx.SentDt)) >= ww.StartDt
    AND CONVERT(date, COALESCE(dms.EndtToAgtDt, edx.SentDt)) <  ww.EndDt
    AND ISNULL(qt.flg_active,1) = 1
    AND ISNULL(qt.purge_status,0) = 0
    AND ISNULL(sb.flg_active,1) = 1
    AND ISNULL(sb.purge_status,0) = 0
    AND uw.user_id IS NOT NULL

ORDER BY
    [Underwriter],
    [Endorsement Sent Dt],
    [Endorsement Effective Dt];