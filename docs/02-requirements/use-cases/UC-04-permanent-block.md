# UC-04 Permanently Block a Lost or Stolen Card

| | |
|---|---|
| **ID** | UC-04 |
| **Level of detail** | Brief |
| **Goal level** | User goal |
| **Scope** | The Bank card management system (mobile app and backend services) |
| **Primary actor** | Customer |
| **Supporting actors** | Card processing center, Notification service |
| **State transitions** | T6: `ACTIVE` → `PERM_BLOCKED`, T7: `TEMP_BLOCKED` → `PERM_BLOCKED`, T5: `FRAUD_BLOCKED` → `PERM_BLOCKED` when invoked from UC-07 ([card lifecycle](../../03-state-model/card-lifecycle.md)) |

Related: [Glossary](../../01-context/glossary.md) · [UC-05](UC-05-reissue.md) · [API](../../../api/card-api.openapi.yaml) · [Events](../../../events/card-events.asyncapi.yaml)

## Brief Description

The customer permanently blocks a card that has been lost or stolen. The block is irreversible: the card can never be used again and can only be replaced by a reissued one ([UC-05](UC-05-reissue.md)). Because of this, the app asks the customer to choose a reason and explicitly confirm the action.

## Preconditions

1. The customer is logged in to the mobile app.
2. The card belongs to the customer and has status `ACTIVE` or `TEMP_BLOCKED`.

## Success Guarantees

- The card status is `PERM_BLOCKED`, `block_reason` is `LOST`, `STOLEN` or `FRAUD_CONFIRMED`.
- The processing center declines all transactions on the card.
- The transition is recorded in the status history.
- A `CardBlocked` event is published, and the customer receives a push notification.

## Main Success Scenario

1. The customer taps **Block permanently** on the card screen.
2. The app asks for the reason: **Lost** or **Stolen**.
3. The customer selects a reason.
4. The app shows a warning that the action is irreversible and the card will have to be reissued, and asks for explicit confirmation (a separate **Block permanently** button, not the default one).
5. The customer confirms.
6. The app sends a permanent block request with the reason and a new idempotency key.
7. The system checks that the card belongs to the customer and its status allows a permanent block.
8. The system sends a block command to the processing center and receives confirmation.
9. The system sets the card status to `PERM_BLOCKED` with the selected `block_reason`, records the transition and publishes a `CardBlocked` event.
10. The app shows the card as permanently blocked and offers to reissue it ([UC-05](UC-05-reissue.md)).

## Extensions

**2a / 5a. The customer cancels at any step before step 6:**
- Nothing is sent; the card status does not change. The use case ends.

**7a. The card is `PERM_BLOCKED` or `CLOSED`:**
- 7a1. The system rejects the request. A retry with the same idempotency key returns the stored result of the first request instead. The use case ends.

**7b. The card is `FRAUD_BLOCKED` and the request does not come from UC-07:**
- 7b1. The system rejects the request. The app redirects the customer to [UC-07](UC-07-fraud-confirm.md), where they can answer "Not me". The use case ends.

**8a. The processing center is unavailable or does not respond:**
- 8a1. Handled as in [UC-02, extension 6a](UC-02-temp-block.md#extensions): the operation is registered as `PENDING` and retried in the background; the app shows "Blocking in progress".

## Variations

**Invoked from UC-07.** When the customer answers "Not me" to a suspicious transaction, UC-07 invokes this use case starting at step 6 with `block_reason = FRAUD_CONFIRMED`. Steps 2–5 are skipped: the customer has already made the decision in UC-07.

## Business Rules

| ID | Rule |
|---|---|
| BR-04-1 | A permanent block is irreversible. No actor, including customer support, can return the card to `ACTIVE`. |
| BR-04-2 | A permanent block does not require OTP: the customer's phone may be lost together with the card, and the block must remain available. Protection against accidental use is provided by the reason selection and explicit confirmation. |
| BR-04-3 | The reason is mandatory. `FRAUD_CONFIRMED` can only be set through UC-07. |

## Traceability

| Artifact | Reference |
|---|---|
| State transitions | T5, T6, T7 in [card-lifecycle.md](../../03-state-model/card-lifecycle.md) |
| API | `POST /cards/{cardId}/permanent-block` in [card-api.openapi.yaml](../../../api/card-api.openapi.yaml) |
| Events | `CardBlocked` in [card-events.asyncapi.yaml](../../../events/card-events.asyncapi.yaml) |
| Decisions | [ADR-001](../../05-decisions/ADR-001-block-reason-as-attribute.md) |