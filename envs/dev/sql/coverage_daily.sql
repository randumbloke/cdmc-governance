-- Assets evaluated by the sweep / assets in scope, per control and day (design §5.2). Assets in
-- scope is the larger of the day's and the previous day's data_assets counts, so a sweep that
-- fails part-way cannot shrink its own denominator. NOT_EVALUATED does not count as covered.
WITH in_scope_by_day AS (
  SELECT
    snapshot_date,
    COUNT(DISTINCT asset) AS assets
  FROM
    `${report}.data_assets`
  GROUP BY
    snapshot_date
),
scope AS (
  SELECT
    snapshot_date,
    GREATEST(assets, IFNULL(LAG(assets) OVER (ORDER BY snapshot_date), 0)) AS assets_in_scope
  FROM
    in_scope_by_day
),
evaluated AS (
  SELECT
    DATE(detected_at, '${time_zone}') AS day,
    control,
    COUNT(DISTINCT asset) AS assets_evaluated
  FROM
    `${report}.findings_dedup`
  WHERE
    evaluation.trigger = 'SWEEP'
    AND evaluation.status != 'NOT_EVALUATED'
  GROUP BY
    day,
    control
)
SELECT
  evaluated.day,
  evaluated.control,
  evaluated.assets_evaluated,
  scope.assets_in_scope,
  SAFE_DIVIDE(evaluated.assets_evaluated, scope.assets_in_scope) AS coverage
FROM
  evaluated
LEFT JOIN
  scope
ON
  scope.snapshot_date = evaluated.day
