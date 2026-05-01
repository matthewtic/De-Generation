/* ============================================================ 
   Agency Retention Rate YoY
   - Renewals only
   - Cohort by quote_dt / created_dt
   - Retention = Bound / Started
   - 2020–2026 window
   - Output formatted for Power BI (tall format)
   ============================================================ */

;WITH RenewalBase AS
(
    SELECT
        TRY_CONVERT(
            INT,
            NULLIF(LTRIM(RTRIM(CONVERT(NVARCHAR(50), sb.original_producer_id))), N'')
        ) AS AgencyID,

        qt.quote_id,
        YEAR(TRY_CONVERT(DATE, COALESCE(qt.quote_dt, qt.created_dt))) AS CohortYear,
        CASE WHEN qt.bind_dt IS NOT NULL THEN 1 ELSE 0 END AS IsBound
    FROM dbo.bms_submission_mst sb WITH (NOLOCK)
    JOIN dbo.bms_quote_mst qt WITH (NOLOCK)
         ON qt.submission_id = sb.submission_id
        AND ISNULL(qt.flg_active, 1) = 1
        AND ISNULL(qt.purge_status, 0) = 0
    LEFT JOIN dbo.adm_bm_lkp_transaction_types tt WITH (NOLOCK)
         ON tt.lkp_id = qt.lkp_transaction_type_id
    WHERE
          ISNULL(sb.flg_active, 1) = 1
      AND ISNULL(sb.purge_status, 0) = 0

      AND TRY_CONVERT(
              INT,
              NULLIF(LTRIM(RTRIM(CONVERT(NVARCHAR(50), sb.original_producer_id))), N'')
          ) IS NOT NULL

      AND ISNULL(tt.lkp_desc, '') IN ('Renewal', 'Renewals')

      AND TRY_CONVERT(DATE, COALESCE(qt.quote_dt, qt.created_dt))
              >= CONVERT(DATE, '2020-01-01')
      AND TRY_CONVERT(DATE, COALESCE(qt.quote_dt, qt.created_dt))
              <  CONVERT(DATE, '2027-01-01')
)
, RenewalAgg AS
(
    SELECT
        AgencyID,
        CohortYear,
        COUNT(DISTINCT quote_id)                                     AS RenewalQuotesStarted,
        COUNT(DISTINCT CASE WHEN IsBound = 1 THEN quote_id END)      AS RenewalQuotesBoundToDate
    FROM RenewalBase
    WHERE CohortYear BETWEEN 2020 AND 2026
    GROUP BY
        AgencyID,
        CohortYear
)

SELECT
    CONVERT(NVARCHAR(50),  ag.agency_code)                           AS [Agency Code],
    CONVERT(NVARCHAR(150), ag.agency_name)                           AS [Agency Name],
    ra.CohortYear                                                    AS [Cohort Year],
    ra.RenewalQuotesStarted                                          AS [Renewals Started],
    ra.RenewalQuotesBoundToDate                                      AS [Renewals Bound],
    CASE
        WHEN ra.RenewalQuotesStarted = 0 THEN NULL
        ELSE ROUND(100.0 * ra.RenewalQuotesBoundToDate
                         / NULLIF(ra.RenewalQuotesStarted, 0), 2)
    END                                                              AS [Renewal Retention %]
FROM RenewalAgg ra
JOIN dbo.adm_co_agencies ag WITH (NOLOCK)
     ON ag.agency_id = ra.AgencyID
WHERE
    ISNULL(ag.flg_active, 1) = 1
    AND ag.agency_code NOT IN ('AGT001', 'AGT002')
ORDER BY
    TRY_CONVERT(
        INT,
        NULLIF(REPLACE(ag.agency_code, 'AGT', ''), '')
    ),
    ag.agency_code,
    ra.CohortYear;