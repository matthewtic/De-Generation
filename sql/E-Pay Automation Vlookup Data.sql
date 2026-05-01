/* ============================================================
   E-Pay Automation Vlookup Data
   - Simple lookup dataset for E-Pay automation
   - Provides Submission → Agency → Insured mapping
   ============================================================ */

SELECT
    CONVERT(NVARCHAR(50), sb.submission_code) AS [Submission Number],
    CONVERT(NVARCHAR(150), ag.agency_name)    AS [Agency Name],
    CONVERT(NVARCHAR(200), qi.insured_name)   AS [Insured Name]
FROM dbo.bms_submission_mst sb
LEFT JOIN dbo.adm_co_agencies ag
    ON ag.agency_id = sb.original_producer_id
   AND ISNULL(ag.flg_active, 1) = 1
LEFT JOIN dbo.bms_quote_mst qt
    ON qt.submission_id = sb.submission_id
   AND ISNULL(qt.flg_active, 1) = 1
   AND ISNULL(qt.purge_status, 0) = 0
LEFT JOIN dbo.bms_quote_insured_mst qi
    ON qi.quote_id = qt.quote_id
WHERE
      ISNULL(sb.flg_active, 1) = 1
  AND ISNULL(sb.purge_status, 0) = 0
ORDER BY sb.submission_code, ag.agency_name, qi.insured_name;