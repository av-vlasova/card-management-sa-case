# UC-03 Unblock a Temporarily Blocked Card

| | |
|---|---|
| **ID** | UC-03 |
| **Level of detail** | Brief |
| **Goal level** | User goal |
| **Scope** | The Bank card management system (mobile app and backend services) |
| **Primary actor** | Customer |
| **Supporting actors** | Card processing center, Notification service |
| **State transition** | T2: `TEMP_BLOCKED` → `ACTIVE` ([card lifecycle](../../03-state-model/card-lifecycle.md)) |

Related: [Glossary](../../01-context/glossary.md) · [UC-02](UC-02-temp-block.md) · [API](../../../api/card-api.openapi.yaml) · [Events](../../../events/card-events.asyncapi.yaml)

## Brief Description

The customer unblocks a card they previously blocked temporarily, for example after finding it. Because unblocking removes protection, the customer must pass step-up authentication (OTP or biometrics) before the card is reactivated.

## Preconditions

1. The customer is logged in to the mobile app.
2. The card belongs to the customer and has status `TEMP_BLOCKED`.

## Success Guarantees

- The card status is `ACTIVE`, `block_reason` is cleared.
- The processing center allows transactions on the card again.
- Transition T2 is recorded in the status history.
- A `CardUnblocked` event is published, and the customer receives a push notification.

## Main Success Scenario

1. The customer taps **Unblock** on the card screen.
2. The app requests step-up authentication: biometrics if enabled on the device, otherwise an OTP.
3. The customer passes authentication.
4. The app sends an unblock request with a new idempotency key and the authentication confirmation.
5. The system validates the authentication confirmation, checks that the card belongs to the customer and its status is `TEMP_BLOCKED`.
6. The system sends an unblock command to the processing center and receives confirmation.
7. The system sets the card status to `ACTIVE`, clears `block_reason`, records transition T2 and publishes a `CardUnblocked` event.
8. The app shows the card as active; the customer receives a push notification.

## Extensions

**3a. The customer enters a wrong OTP:**
- 3a1. The app shows an error and lets the customer try again.
- 3a2. After 3 failed attempts, unblocking this card is locked for 30 minutes and the customer receives a security notification. The use case ends.

**3b. Biometrics fail or are cancelled:**
- 3b1. The app falls back to OTP. The use case continues at step 3.

**5a. The card is already `ACTIVE`:**
- 5a1. The system returns success without changing the status or publishing an event (idempotency). The use case continues at step 8.

**5b. The card is `FRAUD_BLOCKED`:**
- 5b1. The system rejects the request: this block can only be lifted by responding to the suspicious transaction.
- 5b2. The app redirects the customer to [UC-07](UC-07-fraud-confirm.md). The use case ends.

**5c. The card is `PERM_BLOCKED` or `CLOSED`:**
- 5c1. The system rejects the request: the block is irreversible. The app suggests reissuing the card ([UC-05](UC-05-reissue.md)). The use case ends.

**5d. The authentication confirmation is invalid or expired:**
- 5d1. The system rejects the request. The app returns the customer to step 2.

**6a. The processing center is unavailable or rejects the command:**
- 6a1. The card status stays `TEMP_BLOCKED`. The system does **not** retry in the background.
- 6a2. The app shows an error and offers to try again later. The use case ends in failure.

## Business Rules

| ID | Rule |
|---|---|
| BR-03-1 | Unblocking always requires step-up authentication (OTP or biometrics), unlike blocking ([BR-02-1](UC-02-temp-block.md#business-rules)). |
| BR-03-2 | Unblocking is not retried in the background when the processing center is unavailable. A card must never become active again without the customer seeing it happen at that moment. Blocking, in contrast, is retried, because a delayed block is safer than no block. |
| BR-03-3 | After 3 failed OTP attempts, unblocking the card is locked for 30 minutes. |

## Traceability

| Artifact | Reference |
|---|---|
| State transition | T2 in [card-lifecycle.md](../../03-state-model/card-lifecycle.md) |
| API | `POST /cards/{cardId}/unblock` in [card-api.openapi.yaml](../../../api/card-api.openapi.yaml) |
| Events | `CardUnblocked` in [card-events.asyncapi.yaml](../../../events/card-events.asyncapi.yaml) |