# Business Requirements

What the business needs from the card management features, independent of how they are implemented. Each requirement is traced to a business goal from the [vision](../01-context/vision.md) and to the use cases that implement it.

Related: [README](../../README.md) · [Vision](../01-context/vision.md) · [NFR](nfr.md) · [User stories](user-stories.md) · [Glossary](../01-context/glossary.md)

## Stakeholders

| Stakeholder | Role | Main interest |
|---|---|---|
| Customers | Users of the mobile app | Protect their money quickly, get a working card back |
| Product owner, cards | Owns the card features in the app | Adoption, customer satisfaction, contact center load |
| Security and anti-fraud team | Owns the anti-fraud system and rules | Fraud losses, false positive rate, feedback from customers |
| Contact center | Handles customer calls | Fewer calls, the same view of the card status as the customer |
| Card operations | Card production and delivery | Predictable reissue volume, no orphaned cards or orders |
| Compliance and audit | Regulatory and internal control | Traceability of every action, protection of card data |
| Card management development team | Builds and runs the system | Clear requirements, reliable integrations |

## Business Requirements

| ID | Requirement | Goal | Use cases |
|---|---|---|---|
| REQ-01 | The customer must be able to see all their cards, the status of each one and the actions available for it in the mobile app. | G-1 | UC-01 |
| REQ-02 | The customer must be able to block a card temporarily at any time, without calling the bank, and undo the block later. | G-1, G-2 | UC-02, UC-03 |
| REQ-03 | A block must take effect in the processing center before the customer is told the card is blocked. | G-1 | UC-02, UC-04 |
| REQ-04 | Removing a block must require additional confirmation by the customer, so that a person holding the customer's phone cannot reactivate the card. | — (security) | UC-03, UC-07 |
| REQ-05 | The customer must be able to block a lost or stolen card permanently and must be clearly warned that this cannot be undone. | G-1, G-5 | UC-04 |
| REQ-06 | The customer must be able to order a replacement for a permanently blocked card in the app and choose courier delivery or branch pickup. | G-5 | UC-05 |
| REQ-07 | The customer must be able to follow the progress of a reissue in the app and must be notified if it fails. | G-5, G-6 | UC-05 |
| REQ-08 | When the anti-fraud system reports a suspicious transaction, the card must be blocked automatically and the customer notified immediately, with the details of the transaction. | G-3 | UC-06 |
| REQ-09 | The customer must be able to review the suspicious transactions in the app and either confirm them, which unblocks the card, or report them as fraud, which blocks the card permanently and leads to a reissue. | G-3, G-4 | UC-07 |
| REQ-10 | Every customer answer about a suspicious transaction must be passed back to the anti-fraud system. | G-4 | UC-07 |
| REQ-11 | Every change of card status must be recorded with who made it, through which channel and when, and must be available to the contact center and audit. | — (compliance) | All |
| REQ-12 | The customer must receive a notification about every change of a card's status. | G-1, G-2 | UC-02 … UC-07 |
| REQ-13 | Operations that could not be completed automatically must be handed over to the support team; no request may stay unresolved without anyone knowing. | G-6 | UC-02, UC-05, UC-06 |

## Constraints

| ID | Constraint | Source |
|---|---|---|
| CON-01 | The full card number must never be stored, shown or logged by the card management system. | PCI DSS, The Bank security policy |
| CON-02 | The processing center holds the authoritative card status used to authorize transactions; the card management system cannot authorize or decline transactions itself. | Architecture of The Bank |
| CON-03 | The decision whether a transaction is suspicious belongs to the anti-fraud system. | Responsibility split between teams |
| CON-04 | Card production and delivery are performed by an external partner through its API. | Contract with the partner |
| CON-05 | Integration with the anti-fraud system is asynchronous, via Kafka. | Integration standard of The Bank |

## Assumptions

| ID | Assumption |
|---|---|
| AS-01 | The customer is already logged in to the mobile app; login and session management are provided by the Auth Service. |
| AS-02 | The customer's phone number for OTP and the delivery address are up to date. |
| AS-03 | The processing center and the delivery partner support idempotent requests by a request ID. |
| AS-04 | Reissue is free of charge for the customer in this release. |

## Dependencies

| ID | Dependency | Needed for |
|---|---|---|
| DEP-01 | Processing center API for block, unblock, issue and close | UC-02 … UC-07 |
| DEP-02 | `SuspiciousTransactionDetected` events from the anti-fraud system | UC-06 |
| DEP-03 | Delivery partner API for options, orders and cancellations | UC-05 |
| DEP-04 | Auth Service support for step-up tokens bound to an action | UC-03, UC-07 |

## Out of Scope

Card issuance and activation, spending limits, block history in the app, blocking by a contact center agent, migrating recurring payments to the new card, disputing transactions (chargeback), reissue fees, changing the delivery address.