# Glossary

Terms, statuses and abbreviations used across this case. All documents refer to these definitions.

## Actors

| Term | Definition |
|---|---|
| **Customer** | An individual who holds a card issued by The Bank and uses the mobile app. In this case, the customer is always the cardholder. |
| **Anti-fraud system** | An external system that analyzes card transactions in real time and reports suspicious ones. Owned by a separate team. The Bank's card management only consumes its events. |
| **Card processing center** | An external system that authorizes card transactions. It holds its own copy of the card status and declines transactions on blocked cards. |

## Business Terms

| Term | Definition |
|---|---|
| **Card** | A payment card issued by The Bank and linked to a customer account. Identified internally by `card_id` shown to the customer only in masked form. |
| **Temporary block** | A reversible block initiated by the customer. Transactions are declined until the customer unblocks the card. See [UC-02](../02-requirements/use-cases/UC-02-temp-block.md). |
| **Unblock** | Restoring a temporarily blocked card to the active status. Requires additional confirmation. See [UC-03](../02-requirements/use-cases/UC-03-unblock.md). |
| **Permanent block** | An irreversible block for a lost, stolen or compromised card. The card can only be replaced, never reactivated. See [UC-04](../02-requirements/use-cases/UC-04-perm-block.md). |
| **Anti-fraud block** | A block applied automatically when the anti-fraud system reports a suspicious transaction. Can only be lifted by the customer's response to that transaction. See [UC-06](../02-requirements/use-cases/UC-06-fraud-block.md). |
| **Suspicious transaction** | A transaction flagged by the anti-fraud system as possibly not made by the cardholder. |
| **Transaction confirmation** | The customer's answer to a suspicious transaction: "It was me" (the block is lifted) or "It was not me" (the card is permanently blocked). See [UC-07](../02-requirements/use-cases/UC-07-fraud-confirm.md). |
| **Reissue** | Issuing a replacement card for a permanently blocked one. The replacement is a new card with a new number. The old card is closed. See [UC-05](../02-requirements/use-cases/UC-05-reissue.md). |
| **Reissue request** | A record of the customer's reissue order. Contains information about the old card, the delivery method, the current saga step and, once issued, the new card. |
| **Delivery method** | How the customer receives the replacement card. Possible options: courier delivery or pickup at a branch. |

## Card Statuses

Full transition rules: [card-lifecycle.md](../03-state-model/card-lifecycle.md).

| Status | Meaning | Reversible |
|---|---|---|
| `ACTIVE` | Card is operational | — |
| `TEMP_BLOCKED` | Blocked by the customer | Yes, by the customer (UC-03) |
| `FRAUD_BLOCKED` | Blocked by the anti-fraud system, waiting for the customer's response | Yes, only via transaction confirmation (UC-07) |
| `PERM_BLOCKED` | Blocked permanently | No |
| `CLOSED` | Replaced by a reissued card. Terminal status | No |

## Block Reasons

Stored in the `block_reason` attribute, separately from the status.

| Value | Meaning | Used with status |
|---|---|---|
| `CUSTOMER_REQUEST` | Customer blocked the card temporarily | `TEMP_BLOCKED` |
| `FRAUD_SUSPECTED` | Anti-fraud system reported a suspicious transaction | `FRAUD_BLOCKED` |
| `LOST` | Customer reported the card as lost | `PERM_BLOCKED`, `CLOSED` |
| `STOLEN` | Customer reported the card as stolen | `PERM_BLOCKED`, `CLOSED` |
| `FRAUD_CONFIRMED` | Customer did not recognize a suspicious transaction | `PERM_BLOCKED`, `CLOSED` |

## Technical Terms

| Term | Definition |
|---|---|
| **Idempotency** | The property of an operation that produces the same result no matter how many times it is repeated. Blocking an already blocked card returns success without changing anything. |
| **Idempotency key** | A unique identifier (UUID) sent by the mobile app with each state-changing request in the `Idempotency-Key` header. A repeated request with the same key returns the stored result of the first one instead of being executed again. |
| **Saga** | A sequence of local transactions across several services, where each step has a compensating action. |
| **Orchestrator** | The component that runs a saga, calls each step, tracks progress and triggers compensations on failure. In this case, the reissue saga is orchestrated by the card service. |
| **Compensating action** | An action that semantically undoes a completed saga step. |
| **Event** | An asynchronous message published to Kafka when something has happened, e.g. `CardBlocked`. Contracts: [card-events.asyncapi.yaml](../../events/card-events.asyncapi.yaml). |
| **Status history** | An append-only log of every card status change. Includes transition ID, old and new status, reason, initiator and timestamp. Used for audit and customer support. |
| **Masked PAN** | The card number with all digits hidden except the last four. The only form in which a card number is shown in the app, API responses and logs. |
| **OTP** | One-time password sent by SMS or push notification to confirm a sensitive action. |
| **Step-up authentication** | Additional confirmation (OTP or biometrics) required on top of the app login before a sensitive action, such as unblocking a card. |

## Abbreviations

| Abbreviation | Meaning |
|---|---|
| API | Application Programming Interface |
| C4 | Context, Containers, Components, Code: a model for architecture diagrams |
| ERD | Entity-Relationship Diagram |
| NFR | Non-Functional Requirement |
| OTP | One-Time Password |
| PAN | Primary Account Number (card number) |
| SD | Sequence Diagram |
| UC | Use Case |