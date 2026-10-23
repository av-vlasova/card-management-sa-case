-- =============================================================================
-- Analytical and operational queries over the Card Service schema
-- PostgreSQL 16
--
-- Each query answers a question a product owner, the anti-fraud team or
-- support might ask. Schema: db/schema.sql.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Q1. Cards blocked by anti-fraud in the last 7 days that are still waiting
--     for the customer's response (UC-06, UC-07).
--     Who: customer support, for outbound calls.
-- -----------------------------------------------------------------------------

SELECT
    c.id                                        AS card_id,
    c.customer_id,
    '•••• ' || c.pan_last4                      AS masked_pan,
    fc.opened_at,
    round(extract(epoch FROM now() - fc.opened_at) / 3600, 1)
                                                AS hours_waiting,
    count(t.id)                                 AS suspicious_tx,
    sum(t.amount)                               AS suspicious_amount
FROM card c
JOIN fraud_case fc            ON fc.card_id = c.id AND fc.status = 'OPEN'
JOIN fraud_case_transaction t ON t.fraud_case_id = fc.id
WHERE c.status = 'FRAUD_BLOCKED'
  AND fc.opened_at >= now() - interval '7 days'
GROUP BY c.id, c.customer_id, c.pan_last4, fc.opened_at
ORDER BY hours_waiting DESC;


-- -----------------------------------------------------------------------------
-- Q2. Anti-fraud false positive rate by week: share of resolved fraud cases
--     where the customer answered "It was me" (UC-07, BR-07-5).
--     Who: anti-fraud team.
-- -----------------------------------------------------------------------------

SELECT
    date_trunc('week', resolved_at)::date       AS week,
    count(*)                                    AS resolved_cases,
    count(*) FILTER (WHERE status = 'CONFIRMED_BY_CUSTOMER')
                                                AS false_positives,
    count(*) FILTER (WHERE status = 'REJECTED_BY_CUSTOMER')
                                                AS confirmed_fraud,
    round(100.0 * count(*) FILTER (WHERE status = 'CONFIRMED_BY_CUSTOMER')
          / count(*), 1)                        AS false_positive_pct
FROM fraud_case
WHERE status <> 'OPEN'
  AND resolved_at >= now() - interval '8 weeks'
GROUP BY week
ORDER BY week;


-- -----------------------------------------------------------------------------
-- Q3. How quickly customers respond to an anti-fraud block: median and 90th
--     percentile, split by answer and channel (UC-07).
--     Who: product owner. A long response time means cards stay blocked.
-- -----------------------------------------------------------------------------

SELECT
    status                                      AS answer,
    resolution_channel                          AS channel,
    count(*)                                    AS cases,
    date_trunc('minute', justify_interval(
        percentile_cont(0.5) WITHIN GROUP (ORDER BY resolved_at - opened_at)
    ))                                          AS median_response,
    date_trunc('minute', justify_interval(
        percentile_cont(0.9) WITHIN GROUP (ORDER BY resolved_at - opened_at)
    ))                                          AS p90_response
FROM fraud_case
WHERE status <> 'OPEN'
GROUP BY status, resolution_channel
ORDER BY status, channel;


-- -----------------------------------------------------------------------------
-- Q4. What happens after a temporary block: for every T1 transition, find
--     the next transition of the same card (UC-02 → UC-03 or UC-04).
--     Who: product owner. Shows whether customers find their cards.
-- -----------------------------------------------------------------------------

WITH transitions AS (
    SELECT
        card_id,
        transition_id,
        created_at,
        lead(transition_id) OVER w              AS next_transition,
        lead(created_at)    OVER w              AS next_at
    FROM card_status_history
    WINDOW w AS (PARTITION BY card_id ORDER BY created_at, id)
)
SELECT
    CASE next_transition
        WHEN 'T2' THEN 'Unblocked by customer (UC-03)'
        WHEN 'T7' THEN 'Blocked permanently (UC-04)'
        ELSE           'Still temporarily blocked'
    END                                         AS outcome,
    count(*)                                    AS temp_blocks,
    round(100.0 * count(*) / sum(count(*)) OVER (), 1)
                                                AS pct,
    date_trunc('minute', justify_interval(avg(next_at - created_at)))
                                                AS avg_time_to_outcome
FROM transitions
WHERE transition_id = 'T1'
GROUP BY outcome
ORDER BY temp_blocks DESC;


-- -----------------------------------------------------------------------------
-- Q5. Permanent blocks by reason and month, with the share of cards that
--     have already been reissued (UC-04, UC-05).
--     Who: product owner, operations (card production volume).
-- -----------------------------------------------------------------------------

SELECT
    date_trunc('month', h.created_at)::date     AS month,
    h.block_reason,
    count(*)                                    AS perm_blocks,
    count(rr.id)                                AS reissued,
    round(100.0 * count(rr.id) / count(*), 1)   AS reissued_pct
FROM card_status_history h
LEFT JOIN reissue_request rr
       ON rr.old_card_id = h.card_id AND rr.status = 'COMPLETED'
WHERE h.to_status = 'PERM_BLOCKED'
GROUP BY month, h.block_reason
ORDER BY month, perm_blocks DESC;


-- -----------------------------------------------------------------------------
-- Q6. Reissue saga health for the last 30 days: outcome per final status,
--     and for failures, the step and reason (UC-05).
--     Who: card management team.
-- -----------------------------------------------------------------------------

SELECT
    status,
    failed_step,
    failure_reason,
    count(*)                                    AS requests,
    round(100.0 * count(*) / sum(count(*)) OVER (), 1)
                                                AS pct,
    date_trunc('second', avg(coalesce(completed_at, updated_at) - created_at))
                                                AS avg_duration
FROM reissue_request
WHERE created_at >= now() - interval '30 days'
GROUP BY status, failed_step, failure_reason
ORDER BY requests DESC;


-- -----------------------------------------------------------------------------
-- Q7. Stuck reissue requests: in an intermediate status for more than
--     24 hours (NFR for UC-05), with the last saga step attempted.
--     Who: support team alert.
-- -----------------------------------------------------------------------------

SELECT
    rr.id                                       AS reissue_request_id,
    rr.old_card_id,
    rr.status,
    rr.updated_at,
    date_trunc('minute', now() - rr.updated_at) AS stuck_for,
    last_step.step                              AS last_step,
    last_step.action                            AS last_action,
    last_step.result                            AS last_result,
    last_step.attempt                           AS attempts
FROM reissue_request rr
LEFT JOIN LATERAL (
    SELECT s.step, s.action, s.result, s.attempt
    FROM reissue_saga_step s
    WHERE s.reissue_request_id = rr.id
    ORDER BY s.created_at DESC, s.id DESC
    LIMIT 1
) last_step ON true
WHERE rr.status NOT IN ('COMPLETED', 'FAILED')
  AND rr.updated_at < now() - interval '24 hours'
ORDER BY rr.updated_at;


-- -----------------------------------------------------------------------------
-- Q8. Customers who blocked a card temporarily 3 or more times in the last
--     30 days. A signal for UX research (do they use blocking as a
--     "spending pause"?) or for a contact from support.
-- -----------------------------------------------------------------------------

SELECT
    c.customer_id,
    count(*)                                    AS temp_blocks,
    count(DISTINCT c.id)                        AS cards,
    min(h.created_at)                           AS first_block,
    max(h.created_at)                           AS last_block
FROM card_status_history h
JOIN card c ON c.id = h.card_id
WHERE h.transition_id = 'T1'
  AND h.created_at >= now() - interval '30 days'
GROUP BY c.customer_id
HAVING count(*) >= 3
ORDER BY temp_blocks DESC;


-- -----------------------------------------------------------------------------
-- Q9. Data consistency check: the current card status must match the
--     to_status of its latest history record. Any row returned is a bug.
--     Who: card management team, run as a scheduled check.
-- -----------------------------------------------------------------------------

WITH last_transition AS (
    SELECT DISTINCT ON (card_id)
        card_id, to_status, transition_id, created_at
    FROM card_status_history
    ORDER BY card_id, created_at DESC, id DESC
)
SELECT
    c.id                                        AS card_id,
    c.status                                    AS current_status,
    lt.to_status                                AS status_in_history,
    lt.transition_id,
    lt.created_at
FROM card c
LEFT JOIN last_transition lt ON lt.card_id = c.id
WHERE c.status IS DISTINCT FROM coalesce(lt.to_status, 'ACTIVE');


-- -----------------------------------------------------------------------------
-- Q10. Outbox lag: events not yet published to Kafka, by type, with the age
--      of the oldest one. A growing lag means the relay or Kafka is down
--      (UC-02 ext. 9a).
--      Who: monitoring.
-- -----------------------------------------------------------------------------

SELECT
    topic,
    event_type,
    count(*)                                    AS unpublished,
    date_trunc('second', now() - min(created_at)) AS oldest_age
FROM outbox_event
WHERE published_at IS NULL
GROUP BY topic, event_type
HAVING now() - min(created_at) > interval '1 minute'
ORDER BY oldest_age DESC;