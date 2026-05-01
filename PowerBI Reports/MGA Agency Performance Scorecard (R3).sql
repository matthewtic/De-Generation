/* ============================================================
   Agency KPI – Rolling 3 Months
   Window: last 3 months through today
============================================================ */

;WITH Rolling3MoWindow AS
(
    SELECT
        DATEADD(MONTH, -3, CAST(GETDATE() AS DATE)) AS StartDt,
        DATEADD(DAY, 1, CAST(GETDATE() AS DATE))    AS EndDt
),

/* ============================================================
   Universe: Any submission that had Rolling 3 Mo activity
   (Created OR Quote Started OR Bound)
============================================================ */
SubmissionUniverse AS
(
    SELECT DISTINCT
        sb.submission_id,
        sb.original_producer_id AS AgencyID
    FROM dbo.bms_submission_mst sb
    CROSS JOIN Rolling3MoWindow mw
    LEFT JOIN dbo.bms_quote_mst qt
           ON qt.submission_id = sb.submission_id
          AND ISNULL(qt.flg_active, 1) = 1
          AND ISNULL(qt.purge_status, 0) = 0
    WHERE
          ISNULL(sb.flg_active, 1) = 1
      AND ISNULL(sb.purge_status, 0) = 0
      AND sb.original_producer_id IS NOT NULL
      AND
      (
          (sb.created_dt >= mw.StartDt AND sb.created_dt < mw.EndDt)
          OR (COALESCE(qt.quote_dt, qt.created_dt) >= mw.StartDt
              AND COALESCE(qt.quote_dt, qt.created_dt) <  mw.EndDt)
          OR (qt.bind_dt IS NOT NULL
              AND qt.bind_dt >= mw.StartDt
              AND qt.bind_dt <  mw.EndDt)
      )
),

/* ============================================================
   New Intake: submissions created in Rolling 3 Mo
============================================================ */
SubmissionsCreatedMTD AS
(
    SELECT
        sb.original_producer_id AS AgencyID,
        COUNT(DISTINCT sb.submission_id) AS SubmissionsCreatedMTD
    FROM dbo.bms_submission_mst sb
    CROSS JOIN Rolling3MoWindow mw
    WHERE
          ISNULL(sb.flg_active, 1) = 1
      AND ISNULL(sb.purge_status, 0) = 0
      AND sb.original_producer_id IS NOT NULL
      AND sb.created_dt >= mw.StartDt
      AND sb.created_dt <  mw.EndDt
    GROUP BY sb.original_producer_id
),

/* ============================================================
   Submissions with any Rolling 3 Mo activity
   (Created/Quoted/Bound)
============================================================ */
SubmissionsActivityMTD AS
(
    SELECT
        su.AgencyID,
        COUNT(DISTINCT su.submission_id) AS SubmissionsActivityMTD
    FROM SubmissionUniverse su
    GROUP BY su.AgencyID
),

/* ============================================================
   Quote starts (Cohort = quote started in Rolling 3 Mo)
============================================================ */
QuoteStartAgg AS
(
    SELECT
        su.AgencyID,

        COUNT(DISTINCT
            CASE
                WHEN COALESCE(qt.quote_dt, qt.created_dt) >= mw.StartDt
                 AND COALESCE(qt.quote_dt, qt.created_dt) <  mw.EndDt
                THEN sb.submission_id
                ELSE NULL
            END
        ) AS SubmissionsQuotedMTD,

        COUNT(DISTINCT
            CASE
                WHEN COALESCE(qt.quote_dt, qt.created_dt) >= mw.StartDt
                 AND COALESCE(qt.quote_dt, qt.created_dt) <  mw.EndDt
                THEN qt.quote_id
                ELSE NULL
            END
        ) AS QuotesStartedMTD,

        SUM(
            CASE
                WHEN COALESCE(qt.quote_dt, qt.created_dt) >= mw.StartDt
                 AND COALESCE(qt.quote_dt, qt.created_dt) <  mw.EndDt
                THEN 1 ELSE 0
            END
        ) AS RawQuoteRowsStartedMTD,

        COUNT(DISTINCT
            CASE
                WHEN COALESCE(qt.quote_dt, qt.created_dt) >= mw.StartDt
                 AND COALESCE(qt.quote_dt, qt.created_dt) <  mw.EndDt
                 AND qt.bind_dt IS NOT NULL
                THEN qt.quote_id
                ELSE NULL
            END
        ) AS QuotesStartedMTD_BoundToDate,

        COUNT(DISTINCT
            CASE
                WHEN COALESCE(qt.quote_dt, qt.created_dt) >= mw.StartDt
                 AND COALESCE(qt.quote_dt, qt.created_dt) <  mw.EndDt
                 AND ISNULL(tt.lkp_desc, '') = 'New Business'
                THEN qt.quote_id
                ELSE NULL
            END
        ) AS NewBusiness_QuotesStartedMTD,

        COUNT(DISTINCT
            CASE
                WHEN COALESCE(qt.quote_dt, qt.created_dt) >= mw.StartDt
                 AND COALESCE(qt.quote_dt, qt.created_dt) <  mw.EndDt
                 AND ISNULL(tt.lkp_desc, '') = 'New Business'
                 AND qt.bind_dt IS NOT NULL
                THEN qt.quote_id
                ELSE NULL
            END
        ) AS NewBusiness_QuotesBoundToDate,

        COUNT(DISTINCT
            CASE
                WHEN COALESCE(qt.quote_dt, qt.created_dt) >= mw.StartDt
                 AND COALESCE(qt.quote_dt, qt.created_dt) <  mw.EndDt
                 AND ISNULL(tt.lkp_desc, '') IN ('Renewal','Renewals')
                THEN qt.quote_id
                ELSE NULL
            END
        ) AS Renewal_QuotesStartedMTD,

        COUNT(DISTINCT
            CASE
                WHEN COALESCE(qt.quote_dt, qt.created_dt) >= mw.StartDt
                 AND COALESCE(qt.quote_dt, qt.created_dt) <  mw.EndDt
                 AND ISNULL(tt.lkp_desc, '') IN ('Renewal','Renewals')
                 AND qt.bind_dt IS NOT NULL
                THEN qt.quote_id
                ELSE NULL
            END
        ) AS Renewal_QuotesBoundToDate

    FROM SubmissionUniverse su
    JOIN dbo.bms_submission_mst sb
         ON sb.submission_id = su.submission_id
    LEFT JOIN dbo.bms_quote_mst qt
           ON qt.submission_id = sb.submission_id
          AND ISNULL(qt.flg_active, 1) = 1
          AND ISNULL(qt.purge_status, 0) = 0
    LEFT JOIN dbo.adm_bm_lkp_transaction_types tt
           ON tt.lkp_id = qt.lkp_transaction_type_id
    CROSS JOIN Rolling3MoWindow mw
    WHERE
          ISNULL(sb.flg_active, 1) = 1
      AND ISNULL(sb.purge_status, 0) = 0
    GROUP BY su.AgencyID
),

/* ============================================================
   PRODUCTION (Binds in Rolling 3 Mo) + Premium/Fee dollars
   using OPTIONS OUTER APPLY
   - Dollars are "Quote Options Proxy" (latest option record)
============================================================ */
ProductionAgg AS
(
    SELECT
        su.AgencyID,

        COUNT(DISTINCT
            CASE
                WHEN qt.bind_dt IS NOT NULL
                 AND qt.bind_dt >= mw.StartDt
                 AND qt.bind_dt <  mw.EndDt
                THEN qt.quote_id
                ELSE NULL
            END
        ) AS BindsInMTD,

        COUNT(DISTINCT
            CASE
                WHEN qt.bind_dt IS NOT NULL
                 AND qt.bind_dt >= mw.StartDt
                 AND qt.bind_dt <  mw.EndDt
                 AND COALESCE(qt.quote_dt, qt.created_dt) >= mw.StartDt
                 AND COALESCE(qt.quote_dt, qt.created_dt) <  mw.EndDt
                THEN qt.quote_id
                ELSE NULL
            END
        ) AS BindsInMTD_FromQuotesStartedMTD,

        /* Days-to-bind rollup pieces */
        SUM(
            CASE
                WHEN qt.bind_dt IS NOT NULL
                 AND qt.bind_dt >= mw.StartDt
                 AND qt.bind_dt <  mw.EndDt
                 AND COALESCE(qt.quote_dt, qt.created_dt) IS NOT NULL
                THEN CONVERT(DECIMAL(18,2),
                     DATEDIFF(DAY, COALESCE(qt.quote_dt, qt.created_dt), qt.bind_dt)
                )
                ELSE 0
            END
        ) AS SumDaysToBind_MTD_Binds,

        SUM(
            CASE
                WHEN qt.bind_dt IS NOT NULL
                 AND qt.bind_dt >= mw.StartDt
                 AND qt.bind_dt <  mw.EndDt
                 AND COALESCE(qt.quote_dt, qt.created_dt) IS NOT NULL
                THEN 1 ELSE 0
            END
        ) AS CntDaysToBind_MTD_Binds,

        SUM(
            CASE
                WHEN qt.bind_dt IS NOT NULL
                 AND qt.bind_dt >= mw.StartDt
                 AND qt.bind_dt <  mw.EndDt
                THEN ISNULL(opx.BoundPrem, 0)
                ELSE 0
            END
        ) AS TotalBoundPremiumMTD,

        SUM(
            CASE
                WHEN qt.bind_dt IS NOT NULL
                 AND qt.bind_dt >= mw.StartDt
                 AND qt.bind_dt <  mw.EndDt
                THEN ISNULL(opx.BoundFees, 0)
                ELSE 0
            END
        ) AS TotalBoundFeesMTD,

        SUM(
            CASE
                WHEN qt.bind_dt IS NOT NULL
                 AND qt.bind_dt >= mw.StartDt
                 AND qt.bind_dt <  mw.EndDt
                 AND COALESCE(qt.quote_dt, qt.created_dt) >= mw.StartDt
                 AND COALESCE(qt.quote_dt, qt.created_dt) <  mw.EndDt
                THEN ISNULL(opx.BoundPrem, 0)
                ELSE 0
            END
        ) AS TotalBoundPremiumMTD_FromQuotesStartedMTD,

        SUM(
            CASE
                WHEN qt.bind_dt IS NOT NULL
                 AND qt.bind_dt >= mw.StartDt
                 AND qt.bind_dt <  mw.EndDt
                 AND COALESCE(qt.quote_dt, qt.created_dt) >= mw.StartDt
                 AND COALESCE(qt.quote_dt, qt.created_dt) <  mw.EndDt
                THEN ISNULL(opx.BoundFees, 0)
                ELSE 0
            END
        ) AS TotalBoundFeesMTD_FromQuotesStartedMTD,

        /* NB / Renewal production splits (bind_dt in Rolling 3 Mo) */
        COUNT(DISTINCT
            CASE
                WHEN qt.bind_dt IS NOT NULL
                 AND qt.bind_dt >= mw.StartDt
                 AND qt.bind_dt <  mw.EndDt
                 AND ISNULL(tt.lkp_desc,'') = 'New Business'
                THEN qt.quote_id
                ELSE NULL
            END
        ) AS NewBusiness_BindsInMTD,

        COUNT(DISTINCT
            CASE
                WHEN qt.bind_dt IS NOT NULL
                 AND qt.bind_dt >= mw.StartDt
                 AND qt.bind_dt <  mw.EndDt
                 AND ISNULL(tt.lkp_desc,'') IN ('Renewal','Renewals')
                THEN qt.quote_id
                ELSE NULL
            END
        ) AS Renewal_BindsInMTD,

        SUM(
            CASE
                WHEN qt.bind_dt IS NOT NULL
                 AND qt.bind_dt >= mw.StartDt
                 AND qt.bind_dt <  mw.EndDt
                 AND ISNULL(tt.lkp_desc,'') = 'New Business'
                THEN ISNULL(opx.BoundPrem, 0)
                ELSE 0
            END
        ) AS NewBusiness_BoundPremiumMTD,

        SUM(
            CASE
                WHEN qt.bind_dt IS NOT NULL
                 AND qt.bind_dt >= mw.StartDt
                 AND qt.bind_dt <  mw.EndDt
                 AND ISNULL(tt.lkp_desc,'') IN ('Renewal','Renewals')
                THEN ISNULL(opx.BoundPrem, 0)
                ELSE 0
            END
        ) AS Renewal_BoundPremiumMTD

    FROM SubmissionUniverse su
    JOIN dbo.bms_submission_mst sb
         ON sb.submission_id = su.submission_id
    LEFT JOIN dbo.bms_quote_mst qt
           ON qt.submission_id = sb.submission_id
          AND ISNULL(qt.flg_active, 1) = 1
          AND ISNULL(qt.purge_status, 0) = 0
    LEFT JOIN dbo.adm_bm_lkp_transaction_types tt
           ON tt.lkp_id = qt.lkp_transaction_type_id

    OUTER APPLY
    (
        SELECT TOP 1
            TRY_CONVERT(
                DECIMAL(18,2),
                REPLACE(REPLACE(CONVERT(NVARCHAR(100), op.sub_total_premium), ',', ''), '$','')
            ) AS BoundPrem,

            TRY_CONVERT(
                DECIMAL(18,2),
                ISNULL(op.total_fee_taxable, 0) + ISNULL(op.total_fee_non_taxable, 0)
            ) AS BoundFees
        FROM dbo.bms_options_mst op
        WHERE op.quote_id = qt.quote_id
          AND ISNULL(op.flg_active, 1) = 1
        ORDER BY ISNULL(op.updated_dt, op.created_dt) DESC
    ) opx

    CROSS JOIN Rolling3MoWindow mw
    WHERE
          ISNULL(sb.flg_active, 1) = 1
      AND ISNULL(sb.purge_status, 0) = 0
    GROUP BY su.AgencyID
),

/* ============================================================
   DECLINES CREATED in Rolling 3 Mo + Declined Premium
   using QUOTE_CLOSED + OPTIONS
============================================================ */
DeclineAgg AS
(
    SELECT
        su.AgencyID,
        COUNT(DISTINCT qt.quote_id) AS DeclinesCreatedMTD,
        SUM(ISNULL(dpx.DeclPrem, 0)) AS TotalDeclinedPremiumMTD
    FROM SubmissionUniverse su
    JOIN dbo.bms_submission_mst sb
           ON sb.submission_id = su.submission_id
    JOIN dbo.bms_quote_mst qt
           ON qt.submission_id = sb.submission_id
          AND ISNULL(qt.flg_active, 1) = 1
          AND ISNULL(qt.purge_status, 0) = 0
    JOIN dbo.bms_quote_closed qc
           ON qc.quote_id = qt.quote_id

    OUTER APPLY
    (
        SELECT TOP 1
            TRY_CONVERT(
                DECIMAL(18,2),
                REPLACE(REPLACE(CONVERT(NVARCHAR(100), op.sub_total_premium), ',', ''), '$','')
            ) AS DeclPrem
        FROM dbo.bms_options_mst op
        WHERE op.quote_id = qt.quote_id
          AND ISNULL(op.flg_active, 1) = 1
        ORDER BY ISNULL(op.updated_dt, op.created_dt) DESC
    ) dpx

    CROSS JOIN Rolling3MoWindow mw
    WHERE
          ISNULL(qc.flg_active, 1) = 1
      AND ISNULL(qc.flg_decline, 0) = 1
      AND qc.created_dt >= mw.StartDt
      AND qc.created_dt <  mw.EndDt
      AND ISNULL(sb.flg_active, 1) = 1
      AND ISNULL(sb.purge_status, 0) = 0
    GROUP BY su.AgencyID
),

AgencyMetrics AS
(
    SELECT
        ag.agency_code,
        ag.agency_name,

        ISNULL(sc.SubmissionsCreatedMTD, 0) AS SubmissionsCreatedMTD,
        ISNULL(sa.SubmissionsActivityMTD, 0) AS SubmissionsActivityMTD,

        ISNULL(qs.SubmissionsQuotedMTD,         0) AS SubmissionsQuotedMTD,
        ISNULL(qs.QuotesStartedMTD,             0) AS QuotesStartedMTD,
        ISNULL(qs.RawQuoteRowsStartedMTD,       0) AS RawQuoteRowsStartedMTD,
        ISNULL(qs.QuotesStartedMTD_BoundToDate, 0) AS QuotesStartedMTD_BoundToDate,

        ISNULL(qs.NewBusiness_QuotesStartedMTD,   0) AS NewBusiness_QuotesStartedMTD,
        ISNULL(qs.NewBusiness_QuotesBoundToDate,  0) AS NewBusiness_QuotesBoundToDate,
        ISNULL(qs.Renewal_QuotesStartedMTD,       0) AS Renewal_QuotesStartedMTD,
        ISNULL(qs.Renewal_QuotesBoundToDate,      0) AS Renewal_QuotesBoundToDate,

        ISNULL(da.DeclinesCreatedMTD,             0) AS DeclinesCreatedMTD,
        ISNULL(da.TotalDeclinedPremiumMTD,        0) AS TotalDeclinedPremiumMTD,

        ISNULL(pa.BindsInMTD, 0) AS BindsInMTD,
        ISNULL(pa.BindsInMTD_FromQuotesStartedMTD, 0) AS BindsInMTD_FromQuotesStartedMTD,

        ISNULL(pa.TotalBoundPremiumMTD, 0) AS TotalBoundPremiumMTD,
        ISNULL(pa.TotalBoundFeesMTD,    0) AS TotalBoundFeesMTD,

        ISNULL(pa.TotalBoundPremiumMTD_FromQuotesStartedMTD, 0) AS TotalBoundPremiumMTD_FromQuotesStartedMTD,
        ISNULL(pa.TotalBoundFeesMTD_FromQuotesStartedMTD,    0) AS TotalBoundFeesMTD_FromQuotesStartedMTD,

        ISNULL(pa.SumDaysToBind_MTD_Binds, 0) AS SumDaysToBind_MTD_Binds,
        ISNULL(pa.CntDaysToBind_MTD_Binds, 0) AS CntDaysToBind_MTD_Binds,

        ISNULL(pa.NewBusiness_BindsInMTD, 0) AS NewBusiness_BindsInMTD,
        ISNULL(pa.Renewal_BindsInMTD,     0) AS Renewal_BindsInMTD,
        ISNULL(pa.NewBusiness_BoundPremiumMTD, 0) AS NewBusiness_BoundPremiumMTD,
        ISNULL(pa.Renewal_BoundPremiumMTD,     0) AS Renewal_BoundPremiumMTD

    FROM
    (
        SELECT DISTINCT AgencyID FROM SubmissionUniverse
        UNION
        SELECT DISTINCT AgencyID FROM SubmissionsCreatedMTD
    ) a
    JOIN dbo.adm_co_agencies ag
         ON ag.agency_id = a.AgencyID
    LEFT JOIN SubmissionsCreatedMTD   sc ON sc.AgencyID = a.AgencyID
    LEFT JOIN SubmissionsActivityMTD  sa ON sa.AgencyID = a.AgencyID
    LEFT JOIN QuoteStartAgg           qs ON qs.AgencyID = a.AgencyID
    LEFT JOIN ProductionAgg           pa ON pa.AgencyID = a.AgencyID
    LEFT JOIN DeclineAgg              da ON da.AgencyID = a.AgencyID
    WHERE ISNULL(ag.flg_active, 1) = 1
),

AgencyRollup AS
(
    SELECT
        CASE
            WHEN agency_code IN ('AGT044','AGT070','AGT071') THEN 'AGT044'
            WHEN agency_code IN ('AGT092','AGT093')          THEN 'AGT092'
            WHEN agency_code IN ('AGT059','AGT055')          THEN 'AGT055'
            ELSE agency_code
        END AS AgencyCode,

        CASE
            WHEN agency_code IN ('AGT044','AGT070','AGT071')
                THEN 'HUB International Northwest, LLC'
            WHEN agency_code IN ('AGT092','AGT093')
                THEN 'RISQ Consulting'
            WHEN agency_code IN ('AGT059','AGT055')
                THEN 'Nissi'
            ELSE agency_name
        END AS AgencyName,

        SubmissionsCreatedMTD,
        SubmissionsActivityMTD,
        SubmissionsQuotedMTD,
        QuotesStartedMTD,
        RawQuoteRowsStartedMTD,
        QuotesStartedMTD_BoundToDate,

        NewBusiness_QuotesStartedMTD,
        NewBusiness_QuotesBoundToDate,
        Renewal_QuotesStartedMTD,
        Renewal_QuotesBoundToDate,

        DeclinesCreatedMTD,

        BindsInMTD,
        BindsInMTD_FromQuotesStartedMTD,

        TotalBoundPremiumMTD,
        TotalBoundFeesMTD,
        TotalDeclinedPremiumMTD,

        TotalBoundPremiumMTD_FromQuotesStartedMTD,
        TotalBoundFeesMTD_FromQuotesStartedMTD,

        SumDaysToBind_MTD_Binds,
        CntDaysToBind_MTD_Binds,

        NewBusiness_BindsInMTD,
        Renewal_BindsInMTD,
        NewBusiness_BoundPremiumMTD,
        Renewal_BoundPremiumMTD
    FROM AgencyMetrics
),

/* ============================================================
   Final aggregation to agency rollup grain
============================================================ */
FinalAgg AS
(
    SELECT
        r.AgencyCode,
        r.AgencyName,

        SUM(r.SubmissionsCreatedMTD)               AS SubmissionsCreatedMTD,
        SUM(r.SubmissionsActivityMTD)              AS SubmissionsActivityMTD,

        SUM(r.SubmissionsQuotedMTD)                AS SubmissionsQuotedMTD,
        SUM(r.QuotesStartedMTD)                    AS QuotesStartedMTD,
        SUM(r.RawQuoteRowsStartedMTD)              AS RawQuoteRowsStartedMTD,
        SUM(r.QuotesStartedMTD_BoundToDate)        AS QuotesStartedMTD_BoundToDate,

        SUM(r.NewBusiness_QuotesStartedMTD)        AS NewBusiness_QuotesStartedMTD,
        SUM(r.NewBusiness_QuotesBoundToDate)       AS NewBusiness_QuotesBoundToDate,
        SUM(r.Renewal_QuotesStartedMTD)            AS Renewal_QuotesStartedMTD,
        SUM(r.Renewal_QuotesBoundToDate)           AS Renewal_QuotesBoundToDate,

        SUM(r.DeclinesCreatedMTD)                  AS DeclinesCreatedMTD,

        SUM(r.BindsInMTD)                          AS BindsInMTD,
        SUM(r.BindsInMTD_FromQuotesStartedMTD)     AS BindsInMTD_FromQuotesStartedMTD,

        SUM(r.TotalBoundPremiumMTD)                AS TotalBoundPremiumMTD,
        SUM(r.TotalBoundFeesMTD)                   AS TotalBoundFeesMTD,
        SUM(r.TotalDeclinedPremiumMTD)             AS TotalDeclinedPremiumMTD,

        SUM(r.TotalBoundPremiumMTD_FromQuotesStartedMTD) AS TotalBoundPremiumMTD_FromQuotesStartedMTD,
        SUM(r.TotalBoundFeesMTD_FromQuotesStartedMTD)    AS TotalBoundFeesMTD_FromQuotesStartedMTD,

        SUM(r.SumDaysToBind_MTD_Binds)             AS SumDaysToBind_MTD_Binds,
        SUM(r.CntDaysToBind_MTD_Binds)             AS CntDaysToBind_MTD_Binds,

        SUM(r.NewBusiness_BindsInMTD)              AS NewBusiness_BindsInMTD,
        SUM(r.Renewal_BindsInMTD)                  AS Renewal_BindsInMTD,
        SUM(r.NewBusiness_BoundPremiumMTD)         AS NewBusiness_BoundPremiumMTD,
        SUM(r.Renewal_BoundPremiumMTD)             AS Renewal_BoundPremiumMTD
    FROM AgencyRollup r
    GROUP BY r.AgencyCode, r.AgencyName
)

SELECT
    CONVERT(NVARCHAR(50),  f.AgencyCode)  AS [Agency Code],
    CONVERT(NVARCHAR(150), f.AgencyName)  AS [Agency Name],

    f.SubmissionsCreatedMTD  AS [Submissions Created Rolling 3 Mo (New Intake)],
    f.SubmissionsActivityMTD AS [Submissions with Rolling 3 Mo Activity (Created/Quoted/Bound)],

    f.SubmissionsQuotedMTD         AS [Submissions Quoted Rolling 3 Mo (Had a Quote Started)],
    f.QuotesStartedMTD             AS [Quotes Started Rolling 3 Mo (Cohort)],
    f.RawQuoteRowsStartedMTD       AS [Raw Quote Rows Started Rolling 3 Mo],
    f.QuotesStartedMTD_BoundToDate AS [Quotes Started Rolling 3 Mo That Are Bound (To Date)],

    CONVERT(DECIMAL(18,4),
        CASE
            WHEN f.SubmissionsCreatedMTD = 0 THEN NULL
            ELSE CONVERT(DECIMAL(18,4), f.SubmissionsQuotedMTD)
                 / NULLIF(CONVERT(DECIMAL(18,4), f.SubmissionsCreatedMTD), 0)
        END
    ) AS [Submission→Quote % (vs New Intake)],

    CONVERT(DECIMAL(18,4),
        CASE
            WHEN f.SubmissionsActivityMTD = 0 THEN NULL
            ELSE CONVERT(DECIMAL(18,4), f.SubmissionsQuotedMTD)
                 / NULLIF(CONVERT(DECIMAL(18,4), f.SubmissionsActivityMTD), 0)
        END
    ) AS [Submission→Quote % (vs Rolling 3 Mo Activity Submissions)],

    CONVERT(DECIMAL(18,4),
        CASE
            WHEN f.QuotesStartedMTD = 0 THEN NULL
            ELSE CONVERT(DECIMAL(18,4), f.QuotesStartedMTD_BoundToDate)
                 / NULLIF(CONVERT(DECIMAL(18,4), f.QuotesStartedMTD), 0)
        END
    ) AS [Quote→Bind % (Pipeline Cohort)],

    f.NewBusiness_QuotesStartedMTD  AS [New Business Quotes Started Rolling 3 Mo],
    f.NewBusiness_QuotesBoundToDate AS [New Business Quotes Bound (To Date)],

    CONVERT(DECIMAL(18,4),
        CASE
            WHEN f.NewBusiness_QuotesStartedMTD = 0 THEN NULL
            ELSE CONVERT(DECIMAL(18,4), f.NewBusiness_QuotesBoundToDate)
                 / NULLIF(CONVERT(DECIMAL(18,4), f.NewBusiness_QuotesStartedMTD), 0)
        END
    ) AS [New Business Quote→Bind % (Pipeline)],

    f.Renewal_QuotesStartedMTD  AS [Renewal Quotes Started Rolling 3 Mo],
    f.Renewal_QuotesBoundToDate AS [Renewal Quotes Bound (To Date)],

    CONVERT(DECIMAL(18,4),
        CASE
            WHEN f.Renewal_QuotesStartedMTD = 0 THEN NULL
            ELSE CONVERT(DECIMAL(18,4), f.Renewal_QuotesBoundToDate)
                 / NULLIF(CONVERT(DECIMAL(18,4), f.Renewal_QuotesStartedMTD), 0)
        END
    ) AS [Renewal Quote→Bind % (Pipeline)],

    f.DeclinesCreatedMTD AS [Declines Created Rolling 3 Mo],

    CONVERT(DECIMAL(18,4),
        CASE
            WHEN f.SubmissionsQuotedMTD = 0 THEN NULL
            ELSE CONVERT(DECIMAL(18,4), f.DeclinesCreatedMTD)
                 / NULLIF(CONVERT(DECIMAL(18,4), f.SubmissionsQuotedMTD), 0)
        END
    ) AS [Decline Rate % (vs Submissions Quoted Rolling 3 Mo)],

    f.BindsInMTD AS [Binds in Rolling 3 Mo (Production)],
    f.BindsInMTD_FromQuotesStartedMTD AS [Binds in Rolling 3 Mo from Quotes Started Rolling 3 Mo],

    (f.BindsInMTD - f.BindsInMTD_FromQuotesStartedMTD)
        AS [Binds in Rolling 3 Mo from Prior-Period Quotes (Carryover)],

    CONVERT(DECIMAL(18,4),
        CASE
            WHEN f.BindsInMTD = 0 THEN NULL
            ELSE CONVERT(DECIMAL(18,4), (f.BindsInMTD - f.BindsInMTD_FromQuotesStartedMTD))
                 / NULLIF(CONVERT(DECIMAL(18,4), f.BindsInMTD), 0)
        END
    ) AS [Carryover % of Rolling 3 Mo Binds],

    CONVERT(DECIMAL(18,4),
        CASE
            WHEN f.SubmissionsCreatedMTD = 0 THEN NULL
            ELSE CONVERT(DECIMAL(18,4), f.BindsInMTD)
                 / NULLIF(CONVERT(DECIMAL(18,4), f.SubmissionsCreatedMTD), 0)
        END
    ) AS [Binds ÷ New Intake Submissions % (Production Throughput)],

    CONVERT(DECIMAL(18,4),
        CASE
            WHEN f.SubmissionsActivityMTD = 0 THEN NULL
            ELSE CONVERT(DECIMAL(18,4), f.BindsInMTD)
                 / NULLIF(CONVERT(DECIMAL(18,4), f.SubmissionsActivityMTD), 0)
        END
    ) AS [Binds ÷ Rolling 3 Mo Activity Submissions % (Production Throughput)],

    /* Quote Options Proxy labeling */
    CONVERT(DECIMAL(18,2), f.TotalBoundPremiumMTD) AS [Bound Premium in Rolling 3 Mo (Quote Options Proxy)],
    CONVERT(DECIMAL(18,2), f.TotalBoundFeesMTD)    AS [Bound Fees in Rolling 3 Mo (Quote Options Proxy)],

    CONVERT(DECIMAL(18,2), f.TotalDeclinedPremiumMTD)
        AS [Declined Premium from Declines Created Rolling 3 Mo (Quote Options Proxy)],

    /* Dollar hit ratio: Bound ÷ (Bound + Declined) */
    CONVERT(DECIMAL(18,4),
        CASE
            WHEN (f.TotalBoundPremiumMTD + f.TotalDeclinedPremiumMTD) = 0 THEN NULL
            ELSE
                CONVERT(DECIMAL(18,6), f.TotalBoundPremiumMTD)
                / NULLIF(CONVERT(DECIMAL(18,6), (f.TotalBoundPremiumMTD + f.TotalDeclinedPremiumMTD)), 0)
        END
    ) AS [Dollar Hit Ratio % (Bound ÷ (Bound+Declined))],

    /* NB/Renewal production splits */
    f.NewBusiness_BindsInMTD AS [New Business Binds in Rolling 3 Mo],
    f.Renewal_BindsInMTD     AS [Renewal Binds in Rolling 3 Mo],
    CONVERT(DECIMAL(18,2), f.NewBusiness_BoundPremiumMTD) AS [New Business Bound Premium in Rolling 3 Mo (Quote Options Proxy)],
    CONVERT(DECIMAL(18,2), f.Renewal_BoundPremiumMTD)     AS [Renewal Bound Premium in Rolling 3 Mo (Quote Options Proxy)],

    CONVERT(DECIMAL(18,2),
        CASE
            WHEN f.BindsInMTD = 0 THEN NULL
            ELSE f.TotalBoundPremiumMTD / NULLIF(CONVERT(DECIMAL(18,2), f.BindsInMTD), 0)
        END
    ) AS [Avg Bound Premium per Bind (Quote Options Proxy)],

    CONVERT(DECIMAL(18,2), f.TotalBoundPremiumMTD_FromQuotesStartedMTD)
        AS [Bound Premium in Rolling 3 Mo from Quotes Started Rolling 3 Mo (Quote Options Proxy)],

    CONVERT(DECIMAL(18,2),
        (f.TotalBoundPremiumMTD - f.TotalBoundPremiumMTD_FromQuotesStartedMTD)
    ) AS [Bound Premium in Rolling 3 Mo from Carryover Quotes (Quote Options Proxy)],

    CONVERT(DECIMAL(18,2), f.TotalBoundFeesMTD_FromQuotesStartedMTD)
        AS [Bound Fees in Rolling 3 Mo from Quotes Started Rolling 3 Mo (Quote Options Proxy)],

    CONVERT(DECIMAL(18,2),
        (f.TotalBoundFeesMTD - f.TotalBoundFeesMTD_FromQuotesStartedMTD)
    ) AS [Bound Fees in Rolling 3 Mo from Carryover Quotes (Quote Options Proxy)],

    /* ============================================================
       SCORE SET (4 scores) with clamped multipliers (0..1)
    ============================================================ */

    /* 1) MVS (Overall) */
    CONVERT(DECIMAL(18,2),
        CASE
            WHEN f.SubmissionsCreatedMTD = 0 THEN NULL
            ELSE
            (
                (f.TotalBoundPremiumMTD + f.TotalBoundFeesMTD)

                /* ThroughputCapped = MIN(1, Binds/NewIntake) */
                * (CASE
                        WHEN f.BindsInMTD >= f.SubmissionsCreatedMTD THEN 1.0
                        ELSE CONVERT(DECIMAL(18,6), f.BindsInMTD)
                             / NULLIF(CONVERT(DECIMAL(18,6), f.SubmissionsCreatedMTD), 0)
                   END)

                /* DeclineSmoothed clamped: MAX(0, 1 - Declines/(Quoted+10)) */
                * (CASE
                        WHEN (1.0 -
                              (CONVERT(DECIMAL(18,6), f.DeclinesCreatedMTD)
                               / NULLIF(CONVERT(DECIMAL(18,6), f.SubmissionsQuotedMTD) + 10.0, 0)
                              )
                             ) < 0.0
                        THEN 0.0
                        ELSE (1.0 -
                              (CONVERT(DECIMAL(18,6), f.DeclinesCreatedMTD)
                               / NULLIF(CONVERT(DECIMAL(18,6), f.SubmissionsQuotedMTD) + 10.0, 0)
                              )
                             )
                   END)

                /* VolumeRamp = NewIntake/(NewIntake+15) */
                * (CONVERT(DECIMAL(18,6), f.SubmissionsCreatedMTD)
                   / NULLIF(CONVERT(DECIMAL(18,6), f.SubmissionsCreatedMTD) + 15.0, 0)
                  )
            ) / 1000.0
        END
    ) AS [MVS (Overall)],

    /* 2) MVS (Momentum) */
    CONVERT(DECIMAL(18,2),
        CASE
            WHEN f.SubmissionsCreatedMTD = 0 THEN NULL
            ELSE
            (
                (f.TotalBoundPremiumMTD + f.TotalBoundFeesMTD)

                /* ThroughputCapped */
                * (CASE
                        WHEN f.BindsInMTD >= f.SubmissionsCreatedMTD THEN 1.0
                        ELSE CONVERT(DECIMAL(18,6), f.BindsInMTD)
                             / NULLIF(CONVERT(DECIMAL(18,6), f.SubmissionsCreatedMTD), 0)
                   END)

                /* CohortShare clamped: MIN(1, CohortBinds/AllBinds) (0 if no binds) */
                * (CASE
                        WHEN f.BindsInMTD = 0 THEN 0.0
                        ELSE
                            CASE
                                WHEN (CONVERT(DECIMAL(18,6), f.BindsInMTD_FromQuotesStartedMTD)
                                      / NULLIF(CONVERT(DECIMAL(18,6), f.BindsInMTD), 0)
                                     ) > 1.0
                                THEN 1.0
                                ELSE (CONVERT(DECIMAL(18,6), f.BindsInMTD_FromQuotesStartedMTD)
                                      / NULLIF(CONVERT(DECIMAL(18,6), f.BindsInMTD), 0)
                                     )
                            END
                   END)

                /* DeclineSmoothed clamped */
                * (CASE
                        WHEN (1.0 -
                              (CONVERT(DECIMAL(18,6), f.DeclinesCreatedMTD)
                               / NULLIF(CONVERT(DECIMAL(18,6), f.SubmissionsQuotedMTD) + 10.0, 0)
                              )
                             ) < 0.0
                        THEN 0.0
                        ELSE (1.0 -
                              (CONVERT(DECIMAL(18,6), f.DeclinesCreatedMTD)
                               / NULLIF(CONVERT(DECIMAL(18,6), f.SubmissionsQuotedMTD) + 10.0, 0)
                              )
                             )
                   END)

                /* VolumeRamp */
                * (CONVERT(DECIMAL(18,6), f.SubmissionsCreatedMTD)
                   / NULLIF(CONVERT(DECIMAL(18,6), f.SubmissionsCreatedMTD) + 15.0, 0)
                  )
            ) / 1000.0
        END
    ) AS [MVS (Momentum)],

    /* 3) Ops Efficiency Score (0–100) */
    CONVERT(DECIMAL(18,2),
        CASE
            WHEN f.SubmissionsActivityMTD = 0 THEN NULL
            WHEN f.QuotesStartedMTD = 0 THEN NULL
            ELSE
            (
                100.0

                /* SQ = SubmissionsQuoted / Activity */
                * (CONVERT(DECIMAL(18,6), f.SubmissionsQuotedMTD)
                   / NULLIF(CONVERT(DECIMAL(18,6), f.SubmissionsActivityMTD), 0)
                  )

                /* QB = Cohort Quote->Bind */
                * (CONVERT(DECIMAL(18,6), f.QuotesStartedMTD_BoundToDate)
                   / NULLIF(CONVERT(DECIMAL(18,6), f.QuotesStartedMTD), 0)
                  )

                /* (1-DR) clamped with smoothing */
                * (CASE
                        WHEN (1.0 -
                              (CONVERT(DECIMAL(18,6), f.DeclinesCreatedMTD)
                               / NULLIF(CONVERT(DECIMAL(18,6), f.SubmissionsQuotedMTD) + 10.0, 0)
                              )
                             ) < 0.0
                        THEN 0.0
                        ELSE (1.0 -
                              (CONVERT(DECIMAL(18,6), f.DeclinesCreatedMTD)
                               / NULLIF(CONVERT(DECIMAL(18,6), f.SubmissionsQuotedMTD) + 10.0, 0)
                              )
                             )
                   END)

                /* Speed = 1 / (1 + AvgDays/10) (0 if no binds w/ dates) */
                * (CASE
                        WHEN f.CntDaysToBind_MTD_Binds = 0 THEN 0.0
                        ELSE
                            1.0 / (1.0 +
                                (
                                    (CONVERT(DECIMAL(18,6), f.SumDaysToBind_MTD_Binds)
                                     / NULLIF(CONVERT(DECIMAL(18,6), f.CntDaysToBind_MTD_Binds), 0)
                                    ) / 10.0
                                )
                            )
                   END)

                /* VolumeFactor (credibility) based on Activity submissions */
                * (CASE
                        WHEN f.SubmissionsActivityMTD >= 20 THEN 1.0
                        WHEN f.SubmissionsActivityMTD <= 0 THEN 0.0
                        ELSE CONVERT(DECIMAL(18,6), f.SubmissionsActivityMTD) / 20.0
                   END)
            )
        END
    ) AS [Ops Efficiency Score (0–100)],

    /* 4) Pipeline Health (0–100) */
    CONVERT(DECIMAL(18,2),
        CASE
            WHEN f.SubmissionsCreatedMTD = 0 THEN NULL
            WHEN f.QuotesStartedMTD = 0 THEN NULL
            ELSE
            (
                100.0

                /* QB cohort */
                * (CONVERT(DECIMAL(18,6), f.QuotesStartedMTD_BoundToDate)
                   / NULLIF(CONVERT(DECIMAL(18,6), f.QuotesStartedMTD), 0)
                  )

                /* DeclineSmoothed clamped */
                * (CASE
                        WHEN (1.0 -
                              (CONVERT(DECIMAL(18,6), f.DeclinesCreatedMTD)
                               / NULLIF(CONVERT(DECIMAL(18,6), f.SubmissionsQuotedMTD) + 10.0, 0)
                              )
                             ) < 0.0
                        THEN 0.0
                        ELSE (1.0 -
                              (CONVERT(DECIMAL(18,6), f.DeclinesCreatedMTD)
                               / NULLIF(CONVERT(DECIMAL(18,6), f.SubmissionsQuotedMTD) + 10.0, 0)
                              )
                             )
                   END)

                /* VolumeRamp */
                * (CONVERT(DECIMAL(18,6), f.SubmissionsCreatedMTD)
                   / NULLIF(CONVERT(DECIMAL(18,6), f.SubmissionsCreatedMTD) + 15.0, 0)
                  )
            )
        END
    ) AS [Pipeline Health (0–100)],

    /* ============================================================
       Problem Type (Label + Explanation + Recommended Action)
============================================================ */

    CONVERT(NVARCHAR(60),
        CASE
            WHEN ISNULL(f.SubmissionsCreatedMTD, 0) = 0 AND ISNULL(f.SubmissionsActivityMTD, 0) = 0 THEN N'No Activity'
            WHEN ISNULL(f.SubmissionsCreatedMTD, 0) > 0
                 AND ISNULL(f.SubmissionsQuotedMTD, 0) = 0
                 AND ISNULL(f.QuotesStartedMTD, 0) = 0
                 AND ISNULL(f.BindsInMTD, 0) = 0
                THEN N'Intake Not Worked Yet'

            WHEN ISNULL(f.SubmissionsCreatedMTD, 0) >= 10
                 AND (
                        CONVERT(DECIMAL(18,6), f.SubmissionsQuotedMTD)
                        / NULLIF(CONVERT(DECIMAL(18,6), f.SubmissionsCreatedMTD), 0)
                     ) < 0.30
                THEN N'Intake Quality / Intake Triage'

            WHEN ISNULL(f.SubmissionsActivityMTD, 0) >= 10
                 AND (
                        CONVERT(DECIMAL(18,6), f.SubmissionsQuotedMTD)
                        / NULLIF(CONVERT(DECIMAL(18,6), f.SubmissionsActivityMTD), 0)
                     ) < 0.40
                THEN N'Processing Bottleneck (Work→Quote)'

            WHEN ISNULL(f.QuotesStartedMTD, 0) >= 5
                 AND (
                        CONVERT(DECIMAL(18,6), f.QuotesStartedMTD_BoundToDate)
                        / NULLIF(CONVERT(DECIMAL(18,6), f.QuotesStartedMTD), 0)
                     ) < 0.20
                THEN N'Competitiveness / Follow-Up (Quote→Bind)'

            WHEN ISNULL(f.SubmissionsQuotedMTD, 0) >= 5
                 AND (
                        CONVERT(DECIMAL(18,6), f.DeclinesCreatedMTD)
                        / NULLIF(CONVERT(DECIMAL(18,6), f.SubmissionsQuotedMTD), 0)
                     ) >= 0.50
                THEN N'Appetite Mismatch (High Declines)'

            WHEN ISNULL(f.BindsInMTD, 0) >= 5
                 AND (
                        CONVERT(DECIMAL(18,6), (f.BindsInMTD - f.BindsInMTD_FromQuotesStartedMTD))
                        / NULLIF(CONVERT(DECIMAL(18,6), f.BindsInMTD), 0)
                     ) >= 0.70
                THEN N'Backlog-Driven (High Carryover)'

            ELSE N'Healthy / Monitor'
        END
    ) AS [Problem Type Label],

    CONVERT(NVARCHAR(400),
        CASE
            WHEN ISNULL(f.SubmissionsCreatedMTD, 0) = 0 AND ISNULL(f.SubmissionsActivityMTD, 0) = 0
                THEN N'No submissions created or touched in the Rolling 3 Mo window for this agency.'

            WHEN ISNULL(f.SubmissionsCreatedMTD, 0) > 0
                 AND ISNULL(f.SubmissionsQuotedMTD, 0) = 0
                 AND ISNULL(f.QuotesStartedMTD, 0) = 0
                 AND ISNULL(f.BindsInMTD, 0) = 0
                THEN N'New intake exists in the Rolling 3 Mo window but no quotes/binds yet—likely not worked, incomplete, or waiting in queue.'

            WHEN ISNULL(f.SubmissionsCreatedMTD, 0) >= 10
                 AND (
                        CONVERT(DECIMAL(18,6), f.SubmissionsQuotedMTD)
                        / NULLIF(CONVERT(DECIMAL(18,6), f.SubmissionsCreatedMTD), 0)
                     ) < 0.30
                THEN N'High new intake but low submission→quote conversion vs intake in the Rolling 3 Mo window. Focus: submission quality standards, minimum info gate, and appetite alignment.'

            WHEN ISNULL(f.SubmissionsActivityMTD, 0) >= 10
                 AND (
                        CONVERT(DECIMAL(18,6), f.SubmissionsQuotedMTD)
                        / NULLIF(CONVERT(DECIMAL(18,6), f.SubmissionsActivityMTD), 0)
                     ) < 0.40
                THEN N'Many submissions were touched in the Rolling 3 Mo window, but relatively few became quoted. Focus: internal processing/underwriting throughput and turnaround time.'

            WHEN ISNULL(f.QuotesStartedMTD, 0) >= 5
                 AND (
                        CONVERT(DECIMAL(18,6), f.QuotesStartedMTD_BoundToDate)
                        / NULLIF(CONVERT(DECIMAL(18,6), f.QuotesStartedMTD), 0)
                     ) < 0.20
                THEN N'Quotes are being started, but cohort quote→bind is low. Focus: competitiveness (pricing/terms), carrier fit, and follow-up discipline.'

            WHEN ISNULL(f.SubmissionsQuotedMTD, 0) >= 5
                 AND (
                        CONVERT(DECIMAL(18,6), f.DeclinesCreatedMTD)
                        / NULLIF(CONVERT(DECIMAL(18,6), f.SubmissionsQuotedMTD), 0)
                     ) >= 0.50
                THEN N'Decline rate is elevated relative to quoted submissions in the Rolling 3 Mo window. Focus: refine appetite guidance to agency and reduce off-target quoting effort.'

            WHEN ISNULL(f.BindsInMTD, 0) >= 5
                 AND (
                        CONVERT(DECIMAL(18,6), (f.BindsInMTD - f.BindsInMTD_FromQuotesStartedMTD))
                        / NULLIF(CONVERT(DECIMAL(18,6), f.BindsInMTD), 0)
                     ) >= 0.70
                THEN N'Rolling 3 Mo production is primarily coming from prior-period quotes (carryover). Focus: strengthen current cohort conversion to avoid next-period dip.'

            ELSE N'Key funnel indicators look stable in the Rolling 3 Mo window. Continue monitoring for changes in intake, conversion, or declines.'
        END
    ) AS [Problem Type Explanation],

    CONVERT(NVARCHAR(160),
        CASE
            WHEN ISNULL(f.SubmissionsCreatedMTD, 0) = 0 AND ISNULL(f.SubmissionsActivityMTD, 0) = 0
                THEN N'No action needed—monitor monthly for reactivation.'

            WHEN ISNULL(f.SubmissionsCreatedMTD, 0) > 0
                 AND ISNULL(f.SubmissionsQuotedMTD, 0) = 0
                 AND ISNULL(f.QuotesStartedMTD, 0) = 0
                 AND ISNULL(f.BindsInMTD, 0) = 0
                THEN N'Assign owner; enforce first-touch SLA; validate completeness and request missing items same day.'

            WHEN ISNULL(f.SubmissionsCreatedMTD, 0) >= 10
                 AND (
                        CONVERT(DECIMAL(18,6), f.SubmissionsQuotedMTD)
                        / NULLIF(CONVERT(DECIMAL(18,6), f.SubmissionsCreatedMTD), 0)
                     ) < 0.30
                THEN N'Coach agency on minimum submission standards; implement intake gate; share appetite/do-not-send list; schedule producer call.'

            WHEN ISNULL(f.SubmissionsActivityMTD, 0) >= 10
                 AND (
                        CONVERT(DECIMAL(18,6), f.SubmissionsQuotedMTD)
                        / NULLIF(CONVERT(DECIMAL(18,6), f.SubmissionsActivityMTD), 0)
                     ) < 0.40
                THEN N'Rebalance workload; prioritize quoting queue; remove internal blockers; set 24–48h quote-start SLA for this agency.'

            WHEN ISNULL(f.QuotesStartedMTD, 0) >= 5
                 AND (
                        CONVERT(DECIMAL(18,6), f.QuotesStartedMTD_BoundToDate)
                        / NULLIF(CONVERT(DECIMAL(18,6), f.QuotesStartedMTD), 0)
                     ) < 0.20
                THEN N'Review top losses; adjust market/pricing strategy; tighten follow-up cadence; require producer status updates on open quotes.'

            WHEN ISNULL(f.SubmissionsQuotedMTD, 0) >= 5
                 AND (
                        CONVERT(DECIMAL(18,6), f.DeclinesCreatedMTD)
                        / NULLIF(CONVERT(DECIMAL(18,6), f.SubmissionsQuotedMTD), 0)
                     ) >= 0.50
                THEN N'Run appetite reset: train producer team; add pre-qual questions; decline earlier; reduce UW time on off-appetite accounts.'

            WHEN ISNULL(f.BindsInMTD, 0) >= 5
                 AND (
                        CONVERT(DECIMAL(18,6), (f.BindsInMTD - f.BindsInMTD_FromQuotesStartedMTD))
                        / NULLIF(CONVERT(DECIMAL(18,6), f.BindsInMTD), 0)
                     ) >= 0.70
                THEN N'Push current cohort: daily close-out list; prioritize quotes started in the Rolling 3 Mo window; target renewals/NB pending decisions; prevent next-period cliff.'

            ELSE N'Maintain service level; expand relationship; identify upsell/cross-sell opportunities and replicate what is working.'
        END
    ) AS [Primary Recommended Action]

FROM FinalAgg f
ORDER BY
    [MVS (Overall)] DESC,
    f.TotalBoundPremiumMTD DESC,
    f.SubmissionsCreatedMTD DESC,
    f.AgencyName;
