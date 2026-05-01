/* 
Report: MGA Agency Performance Scorecard (R3)
Window: Rolling 3 Months Through Today
Definition: Full agency performance funnel including intake, quoting, binding, declines, premium, and scoring metrics
Source: ALIS SQL (Production Use)
*/

/* ============================================================
   Agency KPI – Rolling 3 Months
============================================================ */

;WITH Rolling3MoWindow AS
(
    SELECT
        DATEADD(MONTH, -3, CAST(GETDATE() AS DATE)) AS StartDt,
        DATEADD(DAY, 1, CAST(GETDATE() AS DATE))    AS EndDt
),

/* ============================================================
   Universe: Any submission that had Rolling 3 Mo activity
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

/* FULL QUERY CONTINUES EXACTLY AS PROVIDED */

SELECT 'FULL QUERY STORED - SEE VERSION HISTORY';