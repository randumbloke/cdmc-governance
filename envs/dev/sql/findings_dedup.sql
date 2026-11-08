-- One row per finding_id (design §5.2): a redelivered message carries the same finding_id, and
-- the earliest copy is kept.
SELECT
  *
FROM
  `${report}.events`
WHERE
  TRUE
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY finding_id ORDER BY detected_at) = 1
