# UC-05 Reissue a Card

| | |
|---|---|
| **ID** | UC-05 |
| **Level of detail** | Fully dressed |
| **Goal level** | User goal |
| **Scope** | The Bank card management system (mobile app and backend services) |
| **Primary actor** | Customer |
| **Supporting actors** | Card processing center, Card production and delivery service, Notification service |
| **State transition** | T8: `PERM_BLOCKED` → `CLOSED` for the old card ([card lifecycle](../../03-state-model/card-lifecycle.md)) |

Related: [Glossary](../../01-context/glossary.md) · [UC-04](UC-04-perm-block.md) · [Sequence diagram SD-UC-05](../../04-architecture/sequences/SD-UC-05-reissue-saga.md) · [API](../../../api/card-api.openapi.yaml) · [Events](../../../events/card-events.asyncapi.yaml)

## Brief Description

The customer orders a replacement for a permanently blocked card and chooses how to receive it: courier delivery or pickup at a branch. The replacement is a new card with a new number. Issuing it involves the processing center and the card production and delivery service, so the system runs the reissue as an orchestrated saga with compensating actions. The customer gets an immediate confirmation that the request is accepted and follows its progress in the app.

## Stakeholders and Interests

| Stakeholder | Interest |
|---|---|
| Customer | Order a new card in a few taps, choose a convenient way to receive it, and know at every moment what is happening with the order |
| The Bank (operations) | No orphaned cards in the processing center and no delivery orders for cards that were never issued; every failure is either compensated automatically or visible to support |
| The Bank (security) | The old card is never reactivated; the new card has a new number, expiry date and CVV |
| Customer support | See the reissue request with its current step and the reason for any failure |
| Recurring payments and other consumers | Learn about the new card through an event to update their data (out of scope for this case) |

## Preconditions

1. The customer is logged in to the mobile app.
2. The card belongs to the customer and has status `PERM_BLOCKED`.
3. There is no active reissue request for this card.

## Trigger

The customer taps **Reissue** on the card screen, or on the confirmation screen right after a permanent block ([UC-04](UC-04-perm-block.md), [UC-07](UC-07-fraud-confirm.md)).

## Minimal Guarantees

- The old card stays `PERM_BLOCKED` until the reissue completes; transactions on it are declined throughout.
- Every saga step and every compensation is recorded in the reissue request with its result and timestamp.
- If the saga fails, all completed steps before the pivot step are compensated, or the request is flagged for manual handling. A reissue request never stays in an intermediate state silently.

## Success Guarantees

- A new card is issued in the processing center and a production and delivery order has been placed.
- The old card status is `CLOSED`; transition T8 is recorded; the reissue request links the old and the new card.
- The reissue request status is `COMPLETED`.
- `CardReissued` event is published; the customer has been notified and sees delivery tracking in the app.

## Reissue Saga

The saga is orchestrated by the card service. Its state is persisted in the reissue request, so the saga resumes from the last completed step after a restart.

| Step | Action | Participant | Compensation | Reissue request status after the step |
|---|---|---|---|---|
| S1 | Issue a new card number | Card processing center | Cancel the new card in the processing center | `NEW_CARD_ISSUED` |
| S2 | Place a production and delivery order | Card production and delivery service | Cancel the order | `DELIVERY_ORDERED` |
| **S3 (pivot)** | Close the old card and link it to the new one (T8) | Card processing center, Card service | — (not compensated, only retried) | `OLD_CARD_CLOSED` |
| S4 | Publish `CardReissued`, notify the customer | Message broker, Notification service | — (only retried) | `COMPLETED` |

S3 is the **pivot step**: before it, a failure is handled by compensating the completed steps (backward recovery); from S3 onwards, the saga can only move forward, and failures are handled by retrying (forward recovery).

**Reissue request statuses:** `CREATED` → `NEW_CARD_ISSUED` → `DELIVERY_ORDERED` → `OLD_CARD_CLOSED` → `COMPLETED`; on failure: `COMPENSATING` → `FAILED`, or `MANUAL_HANDLING` if a compensation cannot be completed.

## Main Success Scenario

*Synchronous part: the customer places the order.*

1. The customer taps **Reissue** on the card screen.
2. The app requests the available delivery options for the customer.
3. The system returns the delivery options: courier delivery to the registered address (with available dates and time slots) and pickup at a branch (list of branches).
4. The customer selects a delivery option and a date or branch.
5. The app shows a summary: masked number of the old card, the fact that the new card will have a new number, the delivery option, and the estimated delivery date. The customer confirms.
6. The app sends a reissue request with the delivery details and a new idempotency key.
7. The system checks that the card belongs to the customer, its status is `PERM_BLOCKED` and there is no active reissue request for it.
8. The system creates a reissue request with status `CREATED`, publishes a `CardReissueRequested` event and returns "request accepted" with the request ID.
9. The app shows the reissue request with its progress.

*Asynchronous part: the system runs the saga.*

10. **S1.** The system asks the processing center to issue a new card number for the customer's account. The processing center returns the new card ID. The system saves it in the reissue request.
11. **S2.** The system places a production and delivery order with the card production and delivery service, passing the new card ID and the delivery details. The service returns the order ID and the estimated delivery date.
12. **S3.** The system asks the processing center to close the old card, receives confirmation, sets the old card status to `CLOSED` and records transition T8.
13. **S4.** The system sets the reissue request status to `COMPLETED` and publishes a `CardReissued` event with the old and new card IDs.
14. The notification service sends the customer a push notification: the new card has been ordered, with the delivery date.
15. The app shows the new card in the card list ([UC-01](UC-01-card-list.md)) with delivery tracking; the old card moves to the closed cards section.

## Extensions

**3a. Courier delivery is not available at the customer's address:**
- 3a1. The system returns only the branch pickup option. The app explains why. The use case continues at step 4.

**3b. There are no available courier slots in the next 14 days:**
- 3b1. The app offers branch pickup. The use case continues at step 4.

**5a. The customer cancels before confirming:**
- 5a1. Nothing is sent. The use case ends.

**6a. No network connection or no response (timeout):**
- 6a1. The app retries with the same idempotency key. If the first request was already processed, the system returns the existing reissue request. The use case continues at step 9.

**7a. The card is `ACTIVE` or `TEMP_BLOCKED`:**
- 7a1. The system rejects the request: only a permanently blocked card can be reissued. The app offers to block it permanently first ([UC-04](UC-04-perm-block.md)). The use case ends.

**7b. The card is `FRAUD_BLOCKED`:**
- 7b1. The system rejects the request. The app redirects the customer to [UC-07](UC-07-fraud-confirm.md). The use case ends.

**7c. The card is `CLOSED`:**
- 7c1. The system rejects the request: the card has already been reissued. The app shows the new card. The use case ends.

**7d. An active reissue request already exists for this card:**
- 7d1. The system returns the existing reissue request instead of creating a new one. The use case continues at step 9.

**10a. The processing center is unavailable or does not respond (S1):**
- 10a1. The system retries S1 with exponential backoff using the same request ID, so the processing center does not issue two cards.
- 10a2. If S1 still fails after the retry window, nothing needs to be compensated. The system sets the request status to `FAILED` and publishes a `CardReissueFailed` event.
- 10a3. The customer receives a notification that the card could not be reissued and can try again. The old card stays `PERM_BLOCKED`. The use case ends in failure.

**11a. The delivery service rejects the order (for example, the address cannot be served or the branch is temporarily closed):**
- 11a1. The system sets the request status to `COMPENSATING` and cancels the new card in the processing center (compensation of S1).
- 11a2. The system sets the request status to `FAILED` and publishes a `CardReissueFailed` event.
- 11a3. The customer receives a notification with the reason and an offer to reissue with a different delivery option. The old card stays `PERM_BLOCKED`. The use case ends in failure.

**11b. The delivery service does not respond (S2 outcome unknown):**
- 11b1. The system retries S2 with the same request ID, which the delivery service uses as an idempotency key, so no duplicate order is created.
- 11b2. If S2 still has no definite result after the retry window, the system queries the order status by request ID. If the order exists, the use case continues at step 12. If it does not, the saga is compensated as in 11a.

**11a1a. The compensation of S1 fails (the processing center cannot cancel the new card), also applies to 11b2:**
- 11a1a1. The system retries the compensation with backoff.
- 11a1a2. If it still fails, the system sets the request status to `MANUAL_HANDLING` and alerts the support team. The customer is told the request is being processed by support. The use case ends in failure.

**12a. The processing center does not confirm the closing of the old card (S3):**
- 12a1. The saga is past the pivot step, so nothing is compensated. The system retries S3 until it succeeds.
- 12a2. If S3 has not succeeded within 1 hour, the system alerts the support team, but keeps retrying. The old card is still `PERM_BLOCKED` in the meantime, so no risk arises. The new card's production continues.

**13a. The event broker is unavailable:**
- 13a1. The event is stored together with the status change and published later (transactional outbox). The use case continues at step 14.

**14a. The push notification cannot be delivered:**
- 14a1. The notification service sends an SMS instead. The use case outcome is not affected.

**\*a. The card service restarts at any point during the saga:**
- \*a1. On startup, the orchestrator loads all reissue requests in intermediate statuses and resumes each from its last completed step.

## Business Rules

| ID | Rule |
|---|---|
| BR-05-1 | Only a card with status `PERM_BLOCKED` can be reissued. |
| BR-05-2 | A card can have at most one active reissue request (in any status other than `COMPLETED` or `FAILED`). |
| BR-05-3 | A reissued card is a new card with a new number, expiry date and CVV, linked to the same account. |
| BR-05-4 | The old card is closed only after the new card has been issued and its delivery ordered (T8 guard). |
| BR-05-5 | Saga steps before the pivot step S3 are compensated on failure; S3 and later steps are only retried. |
| BR-05-6 | Every call to an external participant carries the reissue request ID as an idempotency key, so a retried step never creates a duplicate card or order. |
| BR-05-7 | The new card is delivered only to the customer's registered address or a branch. Changing the address is out of scope. |

## Non-Functional Requirements

Detailed in [nfr.md](../nfr.md). Key ones for this use case:

- Response time for steps 6–8 (request accepted): no more than 2 seconds at the 95th percentile, independent of the availability of the processing center and the delivery service.
- The saga reaches `COMPLETED` within 5 minutes in 99% of cases when all participants are available.
- No reissue request stays in an intermediate status for more than 24 hours without an alert to the support team.

## Technology and Data Variations

- **3.** Courier slots and branch availability are provided by the card production and delivery service; the card service only passes them through.
- **14.** If push notifications are disabled, the notification is sent by SMS.

## Out of Scope

Reissue fees and tariffs, activation of the new card on receipt, migrating recurring payments to the new card (consumers subscribe to `CardReissued`), cancelling a reissue request by the customer, changing the delivery address.

## Traceability

| Artifact | Reference |
|---|---|
| State transition | T8 in [card-lifecycle.md](../../03-state-model/card-lifecycle.md) |
| API | `GET /cards/{cardId}/reissue-options`, `POST /cards/{cardId}/reissue`, `GET /reissue-requests/{requestId}` in [card-api.openapi.yaml](../../../api/card-api.openapi.yaml) |
| Events | Published: `CardReissueRequested`, `CardReissued`, `CardReissueFailed` in [card-events.asyncapi.yaml](../../../events/card-events.asyncapi.yaml) |
| Sequence diagram | [SD-UC-05-reissue-saga.md](../../04-architecture/sequences/SD-UC-05-reissue-saga.md) |