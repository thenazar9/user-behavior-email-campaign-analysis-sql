WITH account_table AS (   -- account information (account count, verification, unsubscribed)
  SELECT
    s.date,
    sp.country,
    send_interval,
    is_verified,
    is_unsubscribed,
    COUNT(DISTINCT a.id) AS account_cnt,
    0 AS sent_msg,
    0 AS open_msg,
    0 AS visit_msg
  FROM
    `DA.account` a
    JOIN `DA.account_session` acs
    ON a.id = acs.account_id
    JOIN `DA.session` s
    ON s.ga_session_id = acs.ga_session_id
    JOIN `DA.session_params` sp
    ON sp.ga_session_id = s.ga_session_id
  GROUP BY
    s.date,
    sp.country,
    send_interval,
    is_verified,
    is_unsubscribed
),
email_metrics_table AS(    -- email metrics information (sent, opened, clicked)
  SELECT
    DATE_ADD(s.date, INTERVAL es.sent_date DAY) AS date,
    sp.country,
    send_interval,
    is_verified,
    is_unsubscribed,
    0 AS account_cnt,
    COUNT(DISTINCT es.id_message) AS sent_msg,
    COUNT(DISTINCT eo.id_message) AS open_msg,
    COUNT(DISTINCT ev.id_message) AS visit_msg
  FROM
    `DA.email_sent` es
    JOIN `DA.account` a
    ON a.id = es.id_account
    JOIN `DA.account_session` acs
    ON acs.account_id = a.id
    JOIN `DA.session` s
    ON acs.ga_session_id = s.ga_session_id
    JOIN `DA.session_params` sp
    ON sp.ga_session_id = s.ga_session_id
    LEFT JOIN `DA.email_open` eo
    ON es.id_message = eo.id_message
    LEFT JOIN `DA.email_visit` ev
    ON es.id_message = ev.id_message
  GROUP BY
    DATE_ADD(s.date, INTERVAL es.sent_date DAY),
    sp.country,
    send_interval,
    is_verified,
    is_unsubscribed
),
account_union_email_metrics AS (   -- combine account and email data
  SELECT *
  FROM account_table
  UNION ALL
  SELECT *
  FROM email_metrics_table
),
sum_account_union_email_metrics AS(   -- aggregate combined data by date and country
  SELECT
    date,
    country,
    send_interval,
    is_verified,
    is_unsubscribed,
    SUM(account_cnt) AS account_cnt,
    SUM(sent_msg) AS sent_msg,
    SUM(open_msg) AS open_msg,
    SUM(visit_msg) AS visit_msg
  FROM account_union_email_metrics
  GROUP BY date,
    country,
    send_interval,
    is_verified,
    is_unsubscribed
),
account_union_email_metrics_with_total AS(   -- calculate total accounts and sent messages by country
  SELECT
    *,
    SUM(account_cnt) OVER(PARTITION BY country) AS total_country_account_cnt,
    SUM(sent_msg) OVER(PARTITION BY country) AS total_country_sent_cnt
  FROM sum_account_union_email_metrics
),
account_union_email_metrics_with_total_and_rank AS(   -- rank countries by total accounts and sent messages
  SELECT
    *,
    DENSE_RANK() OVER(ORDER BY total_country_account_cnt DESC) AS rank_total_country_account_cnt,
    DENSE_RANK() OVER(ORDER BY total_country_sent_cnt DESC) AS rank_total_country_sent_cnt
  FROM account_union_email_metrics_with_total
)
-- final selection of data filtered by top-10 countries
SELECT *
FROM account_union_email_metrics_with_total_and_rank
WHERE rank_total_country_account_cnt <= 10 OR rank_total_country_sent_cnt <= 10
ORDER BY date, country;
