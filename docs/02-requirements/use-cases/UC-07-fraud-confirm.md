# UC-07 Confirm or Reject a Suspicious Transaction

| | |
|---|---|
| **ID** | UC-07 |
| **Level of detail** | Fully dressed |
| **Goal level** | User goal |
| **Scope** | The Bank card management system (mobile app and backend services) |
| **Primary actor** | Customer |
| **Supporting actors** | Card processing center, Anti-fraud system, Notification service |
| **State transitions** | T4: `FRAUD_BLOCKED` → `ACTIVE` ("It was me"), T5: `FRAUD_BLOCKED` → `PERM_BLOCKED` ("Not me") ([card lifecycle](../../03-state-model/card-lifecycle.md)) |

Related: [Glossary](../../01-context/glossary.md) · [UC-06](UC-06-fraud-block.md) · [UC-04](UC-04-permanent-block.md) · [UC-05](UC-05-reissue.md) · [Sequence diagram SD-UC-06-07](../../04-architecture/sequences/SD-UC-06-07-fraud.md) · [API](../../../api/card-api.openapi.yaml) · [Events](../../../events/card-events.asyncapi.yaml)

## Brief Description

After the anti-fraud system has blocked a card ([UC-06](UC-06-fraud-block.md)), the customer reviews the suspicious transaction in the app and answers whether they made it. If the customer confirms the transaction ("It was me"), the card is unblocked. If the customer does not recognize it ("Not me"), the card is blocked permanently and the customer is offered a reissue.

## Stakeholders and Interests

| Stakeholder | Interest |
|---|---|
| Customer | Get the card working again quickly if it was a false alarm; be protected and get a new card if it was fraud |
| The Bank (security) | A fraudster who has the customer's phone must not be able to unblock the card; a compromised card must never return to `ACTIVE` |
| Anti-fraud team | Receive the customer's answer as feedback to improve detection and reduce false positives |
| Customer support | See the full history: what was flagged, what the customer answered, when and how |
| Compliance and audit | Every decision is recorded with the authentication method used |

## Preconditions

1. The customer is logged in to the mobile app.
2. The card belongs to the customer and has status `FRAUD_BLOCKED`.
3. There is an open fraud case for the card containing one or more suspicious transactions.

## Trigger

The customer taps the push notification about the anti-fraud block, or taps **Review transaction** on the card screen ([UC-01](UC-01-card-list.md), extension 3c).

## Minimal Guarantees

- The card never leaves `FRAUD_BLOCKED` unless the customer has given an explicit answer.
- The card never returns to `ACTIVE` without successful step-up authentication.
- The customer's answer, the authentication method and the result are recorded in the fraud case, whether or not the status change succeeds.

## Success Guarantees

**If the customer confirmed the transactions ("It was me"):**
- The card status is `ACTIVE`, `block_reason` is cleared; transition T4 is recorded.
- The fraud case is closed with resolution `CONFIRMED_BY_CUSTOMER`.
- `CardUnblocked` and `FraudCaseResolved` events are published.

**If the customer did not recognize a transaction ("Not me"):**
- The card status is `PERM_BLOCKED`, `block_reason` is `FRAUD_CONFIRMED`; transition T5 is recorded.
- The fraud case is closed with resolution `REJECTED_BY_CUSTOMER`.
- `CardBlocked` and `FraudCaseResolved` events are published.
- The customer has been offered a reissue ([UC-05](UC-05-reissue.md)).

## Main Success Scenario

The main scenario covers the "It was me" answer; the "Not me" answer is described in extension 4a.

1. The customer opens the fraud case from the notification or the card screen.
2. The system returns the open fraud case: masked card, list of suspicious transactions (amount, currency, merchant, country, date and time).
3. The app shows the transactions and asks: **Did you make these transactions?** with two actions, **Yes, it was me** and **No, it wasn't me**.
4. The customer taps **Yes, it was me**.
5. The app requests step-up authentication: biometrics if enabled on the device, otherwise an OTP.
6. The customer passes authentication.
7. The app sends the resolution `CONFIRMED` with the authentication confirmation and a new idempotency key.
8. The system validates the authentication confirmation and checks that the fraud case is still open and contains exactly the transactions shown to the customer.
9. The system sends an unblock command to the processing center and receives confirmation.
10. The system sets the card status to `ACTIVE`, clears `block_reason`, records transition T4 and closes the fraud case with resolution `CONFIRMED_BY_CUSTOMER`.
11. The system publishes `CardUnblocked` and `FraudCaseResolved` events.
12. The app shows the card as active and informs the customer that the transaction may need to be repeated, since the original one was declined.
13. The notification service sends the customer a push notification about the unblock.

## Extensions

**1a. The customer opens the notification while logged out:**
- 1a1. The app asks the customer to log in, then opens the fraud case. The use case continues at step 2.

**2a. The fraud case is already closed (for example, the customer has already answered via the contact center):**
- 2a1. The app shows the current card status and the result of the fraud case. The use case ends.

**3a. The customer leaves without answering:**
- 3a1. The card stays `FRAUD_BLOCKED` ([BR-06-3](UC-06-fraud-block.md#business-rules)). The banner on the card screen remains. The use case ends.

**4a. The customer taps "No, it wasn't me":**
- 4a1. The app warns that the card will be blocked permanently and will have to be reissued, and asks for confirmation.
- 4a2. The customer confirms. No step-up authentication is required (see BR-07-2).
- 4a3. The app sends the resolution `REJECTED` with a new idempotency key.
- 4a4. The system checks that the fraud case is still open and invokes [UC-04](UC-04-permanent-block.md) from step 6 with `block_reason = FRAUD_CONFIRMED` (transition T5).
- 4a5. The system closes the fraud case with resolution `REJECTED_BY_CUSTOMER` and publishes a `FraudCaseResolved` event.
- 4a6. The app shows the card as permanently blocked and offers to reissue it ([UC-05](UC-05-reissue.md)). It also informs the customer that disputing the transaction is handled by the contact center (out of scope). The use case ends.

**4a4a. The processing center is unavailable during the permanent block:**
- 4a4a1. Handled as in [UC-02, extension 6a](UC-02-temp-block.md#extensions): the block is registered as `PENDING` and retried in the background. The card stays `FRAUD_BLOCKED` in the meantime, so transactions are still declined.

**4b. The fraud case contains several transactions and the customer recognizes only some of them:**
- 4b1. The customer answers "No, it wasn't me": a single unrecognized transaction is enough to treat the card as compromised. The use case continues at 4a1.

**6a. The customer enters a wrong OTP:**
- 6a1. The app shows an error and lets the customer try again.
- 6a2. After 3 failed attempts, confirming this fraud case is locked for 30 minutes, the card stays `FRAUD_BLOCKED`, and the customer receives a security notification. The "Not me" answer stays available. The use case ends.

**6b. Biometrics fail or are cancelled:**
- 6b1. The app falls back to OTP. The use case continues at step 6.

**7a. No network connection or no response (timeout):**
- 7a1. The app offers to retry and resends the request with the same idempotency key.
- 7a2. If the first request has already been processed, the system returns its stored result. The use case continues at step 12 (or 4a6 for "Not me").

**8a. The authentication confirmation is invalid or expired:**
- 8a1. The system rejects the request. The app returns the customer to step 5.

**8b. A new suspicious transaction was added to the fraud case after it was shown to the customer:**
- 8b1. The system rejects the resolution because the case has changed.
- 8b2. The app reloads the fraud case and shows the updated list. The use case continues at step 3.

**8c. The fraud case is already closed (answer given in another channel at the same time):**
- 8c1. The system rejects the resolution and returns the current card status. The use case continues at 2a1.

**9a. The processing center is unavailable or rejects the unblock command:**
- 9a1. The card stays `FRAUD_BLOCKED`, the fraud case stays open. The system does **not** retry in the background ([BR-03-2](UC-03-unblock.md#business-rules)).
- 9a2. The app shows an error and offers to try again later. The use case ends in failure.

**11a. The event broker is unavailable:**
- 11a1. Events are stored together with the status change and published later (transactional outbox). The customer response is not affected.

## Business Rules

| ID | Rule |
|---|---|
| BR-07-1 | "It was me" requires step-up authentication (OTP or biometrics). Being logged in to the app is not enough: the fraudster may have access to the customer's phone. |
| BR-07-2 | "Not me" does not require step-up authentication: it only makes the card more secure, so it must be available even if the customer cannot pass OTP. |
| BR-07-3 | One fraud case covers all suspicious transactions on the card that occurred while it was `FRAUD_BLOCKED`. The customer answers for the whole case, not for each transaction separately. |
| BR-07-4 | The answer applies to the exact set of transactions shown to the customer. If the set has changed, the answer is rejected and the customer must review again. |
| BR-07-5 | The customer's answer is always sent back to the anti-fraud system as feedback (`FraudCaseResolved`), regardless of the outcome. |

## Non-Functional Requirements

Detailed in [nfr.md](../nfr.md). Key ones for this use case:

- Response time from step 7 to the response at step 12: no more than 2 seconds at the 95th percentile when the processing center is available.
- The fraud case is shown with masked card number only; merchant and amount are shown in full.
- Every resolution is stored in the audit log with the authentication method (biometrics or OTP), device ID and timestamp.

## Technology and Data Variations

- **5.** Biometrics: Face ID / Touch ID on iOS, BiometricPrompt on Android. OTP: push to the bank app on a trusted device or SMS.
- **1.** The fraud case can also be opened from an SMS link, which opens the app via a deep link.

## Traceability

| Artifact | Reference |
|---|---|
| State transitions | T4, T5 in [card-lifecycle.md](../../03-state-model/card-lifecycle.md) |
| API | `GET /fraud-cases/{caseId}`, `POST /fraud-cases/{caseId}/resolution` in [card-api.openapi.yaml](../../../api/card-api.openapi.yaml) |
| Events | Published: `CardUnblocked`, `CardBlocked`, `FraudCaseResolved` in [card-events.asyncapi.yaml](../../../events/card-events.asyncapi.yaml) |
| Sequence diagram | [SD-UC-06-07-fraud.md](../../04-architecture/sequences/SD-UC-06-07-fraud.md) |
| Related use cases | [UC-06](UC-06-fraud-block.md) (precedes), [UC-04](UC-04-permanent-block.md) (invoked), [UC-05](UC-05-reissue.md) (offered) |