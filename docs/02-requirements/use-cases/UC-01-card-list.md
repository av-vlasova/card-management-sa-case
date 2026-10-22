# UC-01 View Cards and Their Statuses

| | |
|---|---|
| **ID** | UC-01 |
| **Level of detail** | Brief |
| **Goal level** | User goal |
| **Scope** | The Bank card management system (mobile app and backend services) |
| **Primary actor** | Customer |
| **State transition** | None (read-only) |

Related: [Glossary](../../01-context/glossary.md) · [Card lifecycle](../../03-state-model/card-lifecycle.md) · [API](../../../api/card-api.openapi.yaml)

## Brief Description

The customer opens the **Cards** section of the app and sees all their cards with the current status of each one and the actions available for that status. This is the entry point for all other use cases in this case.

## Preconditions

1. The customer is logged in to the mobile app.

## Main Success Scenario

1. The customer opens the **Cards** section.
2. The app requests the customer's card list.
3. The system returns the customer's cards with, for each card: masked PAN, card name, payment system, expiry date, status, block reason, and the list of actions available for this status.
4. The app shows the cards grouped as follows:
   - **Active and blocked cards** (`ACTIVE`, `TEMP_BLOCKED`, `FRAUD_BLOCKED`, `PERM_BLOCKED`) at the top;
   - **Closed cards** (`CLOSED`) in a collapsed section at the bottom.
5. For each card, the app shows a status label and the available actions (see the table below).

## Extensions

**3a. The customer has no cards:**
- 3a1. The app shows an empty state. The use case ends.

**3b. A block operation for a card is still in progress (see [UC-02](UC-02-temp-block.md), extension 6a):**
- 3b1. The card is returned with its current status (`ACTIVE`) and a reference to the pending operation.
- 3b2. The app shows a "Blocking in progress" label on the card and hides the block actions until the operation completes.

**3c. A card is `FRAUD_BLOCKED`:**
- 3c1. The app shows a banner on the card with the suspicious transaction and a **Review transaction** action ([UC-07](UC-07-fraud-confirm.md)).

**3d. The system is unavailable:**
- 3d1. The app shows the last loaded card list marked as possibly outdated, with all actions disabled, and offers to retry.

## Statuses and Available Actions

The system calculates available actions on the backend so that the app does not duplicate state-model rules.

| Status | Label in the app | Available actions |
|---|---|---|
| `ACTIVE` | — | Block temporarily (UC-02), Block permanently (UC-04) |
| `TEMP_BLOCKED` | Blocked | Unblock (UC-03), Block permanently (UC-04) |
| `FRAUD_BLOCKED` | Blocked for security reasons | Review transaction (UC-07) |
| `PERM_BLOCKED` | Blocked permanently | Reissue (UC-05) |
| `CLOSED` | Closed | — |

## Business Rules

| ID | Rule |
|---|---|
| BR-01-1 | The full card number is never returned to the app or shown in the list, only the masked PAN. |
| BR-01-2 | Closed cards are shown for 12 months after closing, then hidden from the list. |
| BR-01-3 | The list of available actions is calculated by the system from the current card status, not by the app. |

## Traceability

| Artifact | Reference |
|---|---|
| API | `GET /cards` in [card-api.openapi.yaml](../../../api/card-api.openapi.yaml) |
| Statuses | [card-lifecycle.md](../../03-state-model/card-lifecycle.md) |