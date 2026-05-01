/* ==========================================================
   Business by City – Policy Detail (YTD, Bound Only)
   - Policy Status logic from KPI1 (bind_dt / trans_finalize_dt)
   - LOB from adm_co_class_types.class_type_name
   - Product Name from adm_co_products.product_name
   - Risk City/State/Zip from bms_quote_insured_mst
   - Written Premium > 0 (cast-safe)
   ========================================================== */

;WITH YTDWindow AS
(
    SELECT
        DATEFROMPARTS(YEAR(GETDATE()), 1, 1) AS StartDt,
        DATEADD(DAY, 1, CAST(GETDATE() AS date)) AS EndDt
)

SELECT
    /* 1 */
    qt.policy_number AS [Policy Number],

    /* 2 */
    ISNULL(LTRIM(RTRIM(ct.class_type_name)), N'') AS [LOB],

    /* 3 */
    ISNULL(LTRIM(RTRIM(p.product_name)), N'') AS [Product Name],

    /* 4 */
    CASE
        WHEN qt.bind_dt IS NULL THEN 'Not Bound'
        WHEN qt.bind_dt IS NOT NULL
             AND qt.trans_finalize_dt IS NULL
             THEN 'Bound – Not Finalized'
        WHEN qt.bind_dt IS NOT NULL
             AND qt.trans_finalize_dt IS NOT NULL
             THEN 'Policy Finalized'
        ELSE 'Unknown'
    END AS [Policy Status],

    /* 5 */
    ISNULL((
        SELECT TOP 1 LTRIM(RTRIM(agx.agency_code))
        FROM adm_co_agencies agx WITH (NOLOCK)
        WHERE agx.agency_id = COALESCE(
                  qt.original_producer_id,
                  (SELECT TOP 1 sb.original_producer_id
                   FROM bms_submission_mst sb WITH (NOLOCK)
                   WHERE sb.submission_id = qt.submission_id)
              )
    ), N'') AS [Agency Id],

    /* 6 */
    ISNULL((
        SELECT TOP 1 LTRIM(RTRIM(agy.agency_name))
        FROM adm_co_agencies agy WITH (NOLOCK)
        WHERE agy.agency_id = COALESCE(
                  qt.original_producer_id,
                  (SELECT TOP 1 sb.original_producer_id
                   FROM bms_submission_mst sb WITH (NOLOCK)
                   WHERE sb.submission_id = qt.submission_id)
              )
    ), N'') AS [Agency Name],

    /* 7–9 */
    ISNULL(LTRIM(RTRIM(ins.adr_phy_city)),        N'') AS [Risk City],
    ISNULL(LTRIM(RTRIM(ins.adr_phy_state_code)), N'') AS [Risk State],
    ISNULL(LTRIM(RTRIM(ins.adr_phy_zip)),        N'') AS [Risk Zip],

    /* 10 */
    ISNULL(tt.lkp_desc, N'') AS [Transaction Type],

    /* 11 */
    ISNULL(CONVERT(NVARCHAR(50), op.sub_total_premium), N'') AS [Written Premium]

FROM bms_options_mst          op
JOIN bms_quote_mst            qt   ON qt.quote_id  = op.quote_id
JOIN bms_quote_insured_mst    ins  ON ins.quote_id = qt.quote_id

LEFT JOIN adm_co_products      p   WITH (NOLOCK)
       ON p.product_id     = op.product_id
LEFT JOIN adm_co_class_types   ct  WITH (NOLOCK)
       ON ct.class_type_id = p.class_type_id
LEFT JOIN adm_bm_lkp_transaction_types tt
       ON tt.lkp_id = qt.lkp_transaction_type_id

CROSS JOIN YTDWindow yw

WHERE qt.flg_active = 1
  AND op.flg_active = 1

  /* Bound / finalized only */
  AND ISNULL(LTRIM(RTRIM(qt.policy_number)), N'') <> N''

  /* Written Premium must be > 0 (cast-safe) */
  AND TRY_CONVERT(
        DECIMAL(18,2),
        REPLACE(REPLACE(CONVERT(NVARCHAR(MAX), op.sub_total_premium), ',', ''), '$','')
      ) > 0

  /* Must tie to at least one active building */
  AND EXISTS (
        SELECT 1
        FROM dbo.bms_locations    l  WITH (NOLOCK)
        JOIN dbo.bms_building_mst b  WITH (NOLOCK)
              ON b.location_id = l.location_id
             AND b.flg_active  = 1
        WHERE l.business_id = op.business_id
      )

  /* Valid transaction types */
  AND (
        tt.lkp_desc IN (
            'New Business','Renewal','Renewals',
            'Endorsement','Endorsements',
            'Cancellation','Cancellations'
        )
        OR tt.lkp_desc LIKE 'Cancel%'
      )
  AND (tt.lkp_desc IS NULL OR tt.lkp_desc NOT LIKE 'Notice of Cancellation%')

  /* YTD window */
  AND qt.created_dt >= yw.StartDt
  AND qt.created_dt <  yw.EndDt

ORDER BY
    ins.adr_phy_state_code,
    ins.adr_phy_city,
    qt.policy_number;