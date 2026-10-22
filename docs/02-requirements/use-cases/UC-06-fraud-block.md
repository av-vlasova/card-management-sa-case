# UC-06 Block a Card on an Anti-Fraud Alert

| | |
|---|---|
| **ID** | UC-06 |
| **Level of detail** | Brief |
| **Goal level** | User goal (of the anti-fraud system, on behalf of The Bank) |
| **Scope** | The Bank card management system (backend services) |
| **Primary actor** | Anti-fraud system |
| **Supporting actors** | Card processing center, Notification service, Customer (informed) |
| **State transition** | T3: `ACTIVE` → `FRAUD_BLOCKED` ([card lifecycle](../../03-state-model/card-lifecycle.md)) |

Related: [Glossary](../../01-context/glossary.md) · [UC-07](UC-07-fraud-confirm.md) · [Sequence diagram SD-UC-06-07](../../04-architecture/sequences/SD-UC-06-07-fraud.md) · [Events](../../../events/card-events.asyncapi.yaml)

## Brief Description

The anti-fraud system detects a suspicious transaction and publishes an event. The card management system consumes the event, blocks the card and asks the customer to confirm or reject the transaction ([UC-07](UC-07-fraud-confirm.md)). This use case has no user interface: it is triggered asynchronously, and the customer only receives a notification.

## Trigger

A `SuspiciousTransactionDetected` event is published by the anti-fraud system.

## Preconditions

1. The card is known to the card management system.

## Success Guarantees

- The card status is `FRAUD_BLOCKED`, `block_reason` is `FRAUD_SUSPECTED`.
- The processing center declines all transactions on the card.
- A fraud case linking the card and the suspicious transaction is open and awaits the customer's response.
- Transition T3 is recorded with the anti-fraud system as the initiator.
- A `CardBlocked` event is published, and the customer is notified by push and SMS.

## Main Success Scenario

1. The system receives a `SuspiciousTransactionDetected` event containing the event ID, card ID, transaction details (amount, merchant, time) and risk score.
2. The system checks that this event ID has not been processed before.
3. The system checks that the card status is `ACTIVE`.
4. The system sends a block command to the processing center and receives confirmation.
5. The system sets the card status to `FRAUD_BLOCKED` with `block_reason = FRAUD_SUSPECTED`, records transition T3 and opens a fraud case for the suspicious transaction.
6. The system publishes a `CardBlocked` event.
7. The notification service sends the customer a push notification and an SMS: the card has been blocked for security reasons, with the transaction amount, merchant and a link to review it in the app.
8. The system acknowledges the event.

## Extensions

**1a. The event is malformed or refers to an unknown card:**
- 1a1. The system moves the event to the dead-letter queue and alerts the support team. The use case ends.

**2a. The event has already been processed (duplicate delivery):**
- 2a1. The system acknowledges the event without any changes. The use case ends.

**3a. The card is already `FRAUD_BLOCKED` (another suspicious transaction):**
- 3a1. The system adds the transaction to the open fraud case without changing the status, and notifies the customer. The use case continues at step 8.

**3b. The card is `TEMP_BLOCKED`, `PERM_BLOCKED` or `CLOSED`:**
- 3b1. The system ignores the event, logs it and acknowledges it: no transactions are possible on the card anyway. The use case ends.

**4a. The processing center is unavailable:**
- 4a1. The system does not acknowledge the event; it is redelivered and processed again with backoff.
- 4a2. If the block is not applied within 5 minutes, the system alerts the support team for manual handling.

**7a. The customer cannot be notified (push and SMS both fail):**
- 7a1. The card stays `FRAUD_BLOCKED`. The case is handed over to the contact center for an outbound call.

## Business Rules

| ID | Rule |
|---|---|
| BR-06-1 | The decision whether a transaction is suspicious belongs to the anti-fraud system. The card management system does not re-evaluate it and blocks the card on every valid event. |
| BR-06-2 | An anti-fraud block takes priority over a temporary block: it cannot be replaced by `TEMP_BLOCKED` or lifted via [UC-03](UC-03-unblock.md). |
| BR-06-3 | The card stays `FRAUD_BLOCKED` until the customer responds in [UC-07](UC-07-fraud-confirm.md) or via the contact center. There is no automatic unblock by timeout. |
| BR-06-4 | Events are processed idempotently by event ID; each event is processed at least once. |

## Traceability

| Artifact | Reference |
|---|---|
| State transition | T3 in [card-lifecycle.md](../../03-state-model/card-lifecycle.md) |
| Events | Consumed: `SuspiciousTransactionDetected`; published: `CardBlocked` in [card-events.asyncapi.yaml](../../../events/card-events.asyncapi.yaml) |
| Sequence diagram | [SD-UC-06-07-fraud.md](../../04-architecture/sequences/SD-UC-06-07-fraud.md) |