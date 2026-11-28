-- Hindu Wisdom analytics: example Athena queries.
-- Run in the Athena console with workgroup "gitaquotes" and database "gitaquotes_analytics".
-- Always filter on dt (the event date, YYYY-MM-DD): it limits how much data is scanned, and so the cost.

-- 1. Daily active installs (phones that opened the app at least once that day)
SELECT dt, count(DISTINCT install_id) AS active_installs
FROM events
WHERE dt >= date_format(current_date - interval '30' day, '%Y-%m-%d') AND name = 'app_open'
GROUP BY dt ORDER BY dt;

-- 2. How people arrive: app icon vs each widget size
SELECT coalesce(source, 'app_icon') AS arrived_from, count(*) AS opens
FROM events
WHERE dt >= date_format(current_date - interval '30' day, '%Y-%m-%d')
  AND (name = 'widget_tap' OR (name = 'app_open'))
GROUP BY 1 ORDER BY opens DESC;

-- 3. Most-read verses, and how often each one's explanation is opened
SELECT v.verse_id, v.views, coalesce(x.explanations, 0) AS explanations,
       round(100.0 * coalesce(x.explanations, 0) / v.views, 1) AS explain_rate_pct
FROM (SELECT verse_id, count(*) AS views FROM events
      WHERE dt >= date_format(current_date - interval '30' day, '%Y-%m-%d') AND name = 'verse_view'
      GROUP BY verse_id) v
LEFT JOIN (SELECT verse_id, count(*) AS explanations FROM events
           WHERE dt >= date_format(current_date - interval '30' day, '%Y-%m-%d') AND name = 'explanation_open'
           GROUP BY verse_id) x ON v.verse_id = x.verse_id
ORDER BY v.views DESC LIMIT 25;

-- 4. Most-shared verses
SELECT verse_id, props['what'] AS what, count(*) AS shares
FROM events
WHERE dt >= date_format(current_date - interval '30' day, '%Y-%m-%d') AND name = 'share_tap'
GROUP BY 1, 2 ORDER BY shares DESC LIMIT 25;

-- 5. New installs per day (first day each install ID was seen)
SELECT first_day, count(*) AS new_installs
FROM (SELECT install_id, min(dt) AS first_day FROM events GROUP BY install_id)
GROUP BY first_day ORDER BY first_day;

-- 6. Day-7 retention: of installs first seen on a day, how many opened the app 7 days later
WITH first_seen AS (SELECT install_id, min(dt) AS first_day FROM events GROUP BY install_id)
SELECT f.first_day, count(*) AS installs,
       count(DISTINCT CASE WHEN e.dt = date_format(date(f.first_day) + interval '7' day, '%Y-%m-%d')
                           THEN e.install_id END) AS active_day_7
FROM first_seen f LEFT JOIN events e ON e.install_id = f.install_id AND e.name = 'app_open'
GROUP BY f.first_day ORDER BY f.first_day;

-- 7. Sanskrit: how many installs turn it on
SELECT props['on'] AS turned_on, count(DISTINCT install_id) AS installs
FROM events
WHERE dt >= date_format(current_date - interval '30' day, '%Y-%m-%d') AND name = 'sanskrit_toggle'
GROUP BY 1;

-- 8. App versions in use
SELECT app_version, count(DISTINCT install_id) AS installs
FROM events
WHERE dt >= date_format(current_date - interval '7' day, '%Y-%m-%d')
GROUP BY 1 ORDER BY installs DESC;

-- 9. Crashes and hangs from MetricKit, grouped by where they happened in the app
SELECT name, props['build'] AS build, props['app_frame'] AS app_frame,
       props['exception_type'] AS exception_type, props['signal'] AS signal,
       count(*) AS reports, count(DISTINCT install_id) AS installs_affected
FROM events
WHERE dt >= date_format(current_date - interval '30' day, '%Y-%m-%d') AND name IN ('crash', 'hang')
GROUP BY 1, 2, 3, 4, 5 ORDER BY reports DESC;
