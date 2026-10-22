# UC-02 Temporarily Block a Card

| | |
|---|---|
| **ID** | UC-02 |
| **Level of detail** | Fully dressed |
| **Goal level** | User goal |
| **Scope** | The Bank card management system (mobile app and backend services) |
| **Primary actor** | Customer |
| **Supporting actors** | Card processing center, Notification service |
| **State transition** | T1: `ACTIVE` → `TEMP_BLOCKED` ([card lifecycle](../../03-state-model/card-lifecycle.md)) |

Related: [Glossary](../../01-context/glossary.md) · [Sequence diagram SD-UC-02](../../04-architecture/sequences/SD-UC-02-temp-block.md) · [API](../../../api/card-api.openapi.yaml) · [Events](../../../events/card-events.asyncapi.yaml)

## Brief Description

The customer temporarily blocks their card in the mobile app, for example when they can't find it but expect it to turn up. Transactions on the card are declined until the customer unblocks it ([UC-03](UC-03-unblock.md)).

## Stakeholders and Interests

| Stakeholder | Interest |
|---|---|
| Customer | Block the card in a few taps and be certain that no transaction will go through after that |
| The Bank (security) | The block is applied in the processing center, not only displayed in the app; fraud losses are minimized |
| Customer support | The status shown in the app matches the real status; every block can be traced in the history |
| Compliance and audit | Every status change is recorded with the initiator and time; card numbers never appear in logs |

## Preconditions

1. The customer is logged in to the mobile app.
2. The card belongs to the customer.

## Trigger

The customer taps **Block temporarily** on the card screen.

## Minimal Guarantees

Guaranteed whether the use case succeeds or fails:

- The app never shows the card as blocked unless the processing center has confirmed the block.
- Every block attempt is logged with the result, initiator and timestamp.
- The card number appears only in masked form in logs and responses.

## Success Guarantees

- The card status is `TEMP_BLOCKED`, `block_reason` is `CUSTOMER_REQUEST`.
- The processing center declines all transactions on the card.
- The status change (T1) is recorded in the status history.
- A `CardBlocked` event is published.
- The customer has seen the new status in the app and received a push notification.

## Main Success Scenario

1. The customer opens the card screen and taps **Block temporarily**.
2. The app shows a confirmation dialog explaining that transactions will be declined until the card is unblocked.
3. The customer confirms.
4. The app sends a block request with a new idempotency key.
5. The system checks that the card belongs to the customer and its status is `ACTIVE`.
6. The system sends a block command to the processing center.
7. The processing center confirms the block.
8. The system sets the card status to `TEMP_BLOCKED` with `block_reason = CUSTOMER_REQUEST` and records transition T1 in the status history.
9. The system publishes a `CardBlocked` event.
10. The system returns a success response to the app.
11. The app shows the card as blocked and offers the **Unblock** action.
12. The notification service sends the customer a push notification about the block.

## Extensions

**2a. The customer cancels the confirmation dialog:**
- 2a1. The app closes the dialog; nothing is sent. The use case ends.

**4a. No network connection:**
- 4a1. The app shows a connection error and offers to retry. Nothing is sent.
- 4a2. On retry, the app reuses the same idempotency key. The use case resumes at step 4.

**4b. The app does not receive a response (timeout) and the customer retries:**
- 4b1. The app sends the request again with the same idempotency key.
- 4b2. If the first request has already been processed, the system returns its stored result without executing the block again. The use case resumes at step 11.

**5a. The card does not belong to the customer or does not exist:**
- 5a1. The system rejects the request as "card not found", without revealing whether the card exists.
- 5a2. The app shows a generic error. The use case ends.

**5b. The card is already `TEMP_BLOCKED`:**
- 5b1. The system returns success without changing the status or publishing an event (idempotency).
- 5b2. The use case resumes at step 11.

**5c. The card is `FRAUD_BLOCKED`:**
- 5c1. The system rejects the request: the card is already blocked by the anti-fraud system.
- 5c2. The app shows the suspicious transaction and offers to respond to it ([UC-07](UC-07-fraud-confirm.md)). The use case ends.

**5d. The card is `PERM_BLOCKED` or `CLOSED`:**
- 5d1. The system rejects the request: the card can no longer be blocked or unblocked.
- 5d2. The app refreshes the card screen. The use case ends.

**5e. The card status changes during processing (for example, an anti-fraud block arrives at the same moment):**
- 5e1. The system detects the conflict when saving the status and re-reads the card.
- 5e2. The system re-evaluates the request against the new status: extension 5b, 5c or 5d applies.

**6a. The processing center is unavailable or does not respond within the timeout:**
- 6a1. The system registers the block operation with status `PENDING`; the card status stays `ACTIVE`.
- 6a2. The system returns an "operation accepted" response with the operation ID.
- 6a3. The app shows "Blocking in progress" and polls the operation status.
- 6a4. The system retries the block command with exponential backoff.
  - 6a4a. A retry succeeds: the use case resumes at step 8; the app shows the result on the next poll or when the customer reopens the card screen.
  - 6a4b. All retries fail within the retry window: the system marks the operation `FAILED`, sends the customer a push notification advising them to call the hotline, and alerts the support team. The card status stays `ACTIVE`. The use case ends in failure.

**7a. The processing center rejects the command (for example, the card is unknown to it):**
- 7a1. The system leaves the card status unchanged, logs an incident and alerts the support team.
- 7a2. The app shows an error advising the customer to call the hotline. The use case ends in failure.

**9a. The event cannot be published at the moment (message broker unavailable):**
- 9a1. The event is stored together with the status change and published once the broker is available (transactional outbox). The customer response is not affected. The use case continues at step 10.

**12a. The push notification cannot be delivered:**
- 12a1. The notification service retries according to its own policy. The use case outcome is not affected.

## Business Rules

| ID | Rule |
|---|---|
| BR-02-1 | Blocking requires no additional confirmation (OTP or biometrics) beyond the confirmation dialog: blocking protects the customer, so it must be as fast as possible. Unblocking does require it ([UC-03](UC-03-unblock.md)). |
| BR-02-2 | The card is considered blocked only after the processing center has confirmed the block. |
| BR-02-3 | A temporary block does not expire automatically; only the customer can lift it. |
| BR-02-4 | A temporary block cannot replace an anti-fraud block or a permanent block. |

## Non-Functional Requirements

Detailed in [nfr.md](../nfr.md). Key ones for this use case:

- Response time from step 4 to step 10: no more than 2 seconds at the 95th percentile when the processing center is available.
- Processing center call timeout: 3 seconds; retry window for pending blocks: 15 minutes.
- Idempotency keys are stored for at least 24 hours.

## Technology and Data Variations

- **4.** The request is sent from the iOS or Android app; the backend behavior is identical.
- **12.** If push notifications are disabled on the device, the notification is sent by SMS.

## Traceability

| Artifact | Reference |
|---|---|
| State transition | T1 in [card-lifecycle.md](../../03-state-model/card-lifecycle.md) |
| API | `POST /cards/{cardId}/block`, `GET /operations/{operationId}` in [card-api.openapi.yaml](../../../api/card-api.openapi.yaml) |
| Events | `CardBlocked` in [card-events.asyncapi.yaml](../../../events/card-events.asyncapi.yaml) |
| Sequence diagram | [SD-UC-02-temp-block.md](../../04-architecture/sequences/SD-UC-02-temp-block.md) |
| Decisions | [ADR-001](../../05-decisions/ADR-001-block-reason-as-attribute.md) |