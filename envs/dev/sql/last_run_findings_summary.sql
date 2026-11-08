-- Latest finding per asset and check, with pass and fail ratios by domain and control
-- (design §5.2).
WITH latest AS (
  SELECT
    *
  FROM
    `${report}.findings_dedup`
  WHERE
    TRUE
  QUALIFY
    ROW_NUMBER() OVER (
      PARTITION BY asset, `check`
      ORDER BY evaluation.evaluated_at DESC, detected_at DESC
    ) = 1
)
SELECT
  latest.*,
  SAFE_DIVIDE(
    COUNTIF(evaluation.status = 'PASS') OVER (PARTITION BY domain, control),
    COUNT(*) OVER (PARTITION BY domain, control)
  ) AS domain_control_pass_ratio,
  SAFE_DIVIDE(
    COUNTIF(evaluation.status = 'FAIL') OVER (PARTITION BY domain, control),
    COUNT(*) OVER (PARTITION BY domain, control)
  ) AS domain_control_fail_ratio
FROM
  latest
