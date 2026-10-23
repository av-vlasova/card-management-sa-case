# Non-Functional Requirements

Quality attributes of the card management system. Every requirement is measurable and states how it is verified. Use cases refer to these requirements in their "Non-Functional Requirements" sections.

Related: [README](../../README.md) · [Business requirements](business-requirements.md) · [Containers](../04-architecture/containers.md) · [API](../../api/card-api.openapi.yaml)

## Performance

| ID | Requirement | Target | Applies to | Verification |
|---|---|---|---|---|
| NFR-PERF-01 | Response time of state-changing card operations when the processing center is available | ≤ 2 s at the 95th percentile, ≤ 4 s at the 99th | `POST /cards/{cardId}/block`, `/unblock`, `/permanent-block`, `/fraud-cases/{caseId}/resolution` (UC-02, UC-03, UC-04, UC-07) | Load test; production latency metrics per endpoint |
| NFR-PERF-02 | Response time of read operations | ≤ 500 ms at the 95th percentile | `GET /cards`, `GET /cards/{cardId}`, `GET /fraud-cases/{caseId}` (UC-01, UC-07) | Load test; production metrics |
| NFR-PERF-03 | Response time for accepting a reissue request, independent of external systems | ≤ 2 s at the 95th percentile | `POST /cards/{cardId}/reissue` (UC-05) | Load test with the processing center and delivery service stubbed as slow |
| NFR-PERF-04 | Timeout for a call to the processing center before switching to background processing | 3 s | UC-02 ext. 6a, UC-04 ext. 8a | Integration test with a delayed processing stub |
| NFR-PERF-05 | Time from a `SuspiciousTransactionDetected` event to the card being blocked in the processing center | ≤ 10 s at the 95th percentile | UC-06 | Event timestamps vs. status history (`occurredAt` → `card_status_history.created_at`) |
| NFR-PERF-06 | Reissue saga duration when all participants are available | `COMPLETED` within 5 min in ≥ 99% of requests | UC-05 | `reissue_request.completed_at - created_at` ([queries.sql](../../db/queries.sql), Q6) |
| NFR-PERF-07 | Outbox relay lag | ≤ 5 s at the 95th percentile; alert if any event is unpublished for > 1 min | All events | `outbox_event.published_at - created_at`; Q10 as an alert |

## Capacity

| ID | Requirement | Target | Verification |
|---|---|---|---|
| NFR-CAP-01 | Sustained load of state-changing card operations | 50 requests/s | Load test |
| NFR-CAP-02 | Peak load of state-changing card operations (for example, after a mass data breach is reported in the news) | 500 requests/s for 15 min without violating NFR-PERF-01 | Load test with a spike profile |
| NFR-CAP-03 | Anti-fraud event throughput | 200 events/s with consumer lag ≤ 30 s | Load test on the Kafka consumer |

## Availability and Reliability

| ID | Requirement | Target | Verification |
|---|---|---|---|
| NFR-AV-01 | Availability of blocking operations (temporary, permanent, anti-fraud) | 99.95% per month (≈ 22 min of downtime) | Synthetic monitoring, SLO dashboard |
| NFR-AV-02 | Availability of other card operations | 99.9% per month | Synthetic monitoring |
| NFR-AV-03 | A block request accepted by the system is never lost, even if the processing center is unavailable | Retried in the background for 15 min; on failure, the customer and support are notified | Chaos test: processing center down during a block (UC-02 ext. 6a) |
| NFR-AV-04 | An anti-fraud block that cannot be applied is escalated | Support alert if the card is not blocked within 5 min of the event | Chaos test; alert rule (UC-06 ext. 4a) |
| NFR-AV-05 | No reissue request stays in an intermediate status silently | Support alert after 24 h in an intermediate status; alert after 1 h of failed retries of S3 | Q7 as a scheduled alert (UC-05 ext. 12a) |
| NFR-AV-06 | The reissue saga survives a restart of the Card Service | Every request in an intermediate status resumes from its last completed step | Test: kill the service between saga steps |
| NFR-AV-07 | Every state-changing operation is idempotent | Repeating a request with the same `Idempotency-Key` within 24 h returns the stored result and has no side effects | API tests: double submit, retry after timeout |
| NFR-AV-08 | Events are delivered at least once and processed exactly once in effect | Consumers deduplicate by `eventId` | Test: redeliver the same event |
| NFR-AV-09 | Recovery objectives for the Card DB | RPO ≤ 1 min, RTO ≤ 15 min | Disaster recovery drill twice a year |

## Security

| ID | Requirement | Verification |
|---|---|---|
| NFR-SEC-01 | All API calls require a valid customer access token. The customer ID is taken only from the token. | Security tests; API gateway configuration |
| NFR-SEC-02 | A customer can access only their own cards and fraud cases. Accessing another customer's resource returns `404`, not `403`, so the existence of the resource is not revealed. | Authorization tests (IDOR) for every endpoint with a path ID |
| NFR-SEC-03 | Unblocking a card (UC-03) and confirming a suspicious transaction (UC-07, "It was me") require a step-up token obtained via biometrics or OTP. The token lives ≤ 5 min and is bound to the customer, the card and the action. | API tests with expired, foreign and wrong-action tokens |
| NFR-SEC-04 | After 3 failed OTP attempts, the protected action is locked for 30 min for this card, and the customer receives a security notification. | Functional test |
| NFR-SEC-05 | Blocking actions (UC-02, UC-04, "Not me" in UC-07) never require step-up authentication, so they remain available when the customer cannot pass OTP. | Functional test |
| NFR-SEC-06 | Rate limiting per customer: ≤ 20 state-changing requests per minute; excess requests get `429`. | Gateway configuration test |
| NFR-SEC-07 | Service-to-service traffic uses mTLS; Kafka clients authenticate with certificates. | Infrastructure review |

## Data Protection

| ID | Requirement | Verification |
|---|---|---|
| NFR-DATA-01 | The full card number (PAN), CVV and expiry-plus-PAN combination are never stored, logged, returned by the API or put in events. Only the last four digits are allowed (`•••• 1234`). | Schema review; automated log scanning for PAN patterns (Luhn check); contract tests on API and event payloads |
| NFR-DATA-02 | Personal data in logs is limited to internal IDs (`customerId`, `cardId`). Names, phone numbers and addresses are not logged. | Log scanning |
| NFR-DATA-03 | Data at rest in the Card DB and Kafka is encrypted. | Infrastructure review |
| NFR-DATA-04 | Retention: status history and fraud cases are kept for 5 years after the card is closed; idempotency keys for 24 h; outbox events for 7 days after publishing. | Retention jobs review |

## Audit

| ID | Requirement | Verification |
|---|---|---|
| NFR-AUD-01 | Every card status change is recorded in an append-only history with the transition, initiator, channel, step-up method, correlation ID and timestamp. | Database trigger `history_append_only`; test that updates and deletes fail |
| NFR-AUD-02 | Every resolution of a fraud case records the answer, channel, authentication method and device ID. | Functional test (UC-07) |
| NFR-AUD-03 | The current card status always matches the latest history record. | Q9 in [queries.sql](../../db/queries.sql) as a daily check; any row is an incident |

## Observability

| ID | Requirement | Verification |
|---|---|---|
| NFR-OBS-01 | Every request and event carries a correlation ID (`X-Request-ID`, `correlationId` header) that is propagated to logs, outgoing calls and published events. | Tracing review |
| NFR-OBS-02 | Metrics are exported for: latency and error rate per endpoint, processing center call latency and timeouts, pending operations, consumer lag, outbox lag, saga statuses. | Dashboard review |
| NFR-OBS-03 | Alerts exist for: NFR-AV-04, NFR-AV-05, NFR-PERF-07, messages in the dead-letter queue, error rate > 1% for 5 min. | Alert rules review |

## Usability

| ID | Requirement | Verification |
|---|---|---|
| NFR-UX-01 | A temporary block takes no more than 3 taps from the card screen. | UX review |
| NFR-UX-02 | Irreversible actions (permanent block, "Not me") show a warning and require a separate, non-default confirmation button. | UX review |
| NFR-UX-03 | When an operation is pending (`202`), the app shows "Blocking in progress" and never shows the card as blocked before confirmation. | Functional test (UC-02 ext. 6a) |
| NFR-UX-04 | Card screens meet WCAG 2.1 AA, including screen reader labels for card status. | Accessibility audit |