# SD-UC-06-07 Anti-Fraud Block and Customer Response

Sequence diagrams for [UC-06](../../02-requirements/use-cases/UC-06-fraud-block.md) and [UC-07](../../02-requirements/use-cases/UC-07-fraud-confirm.md). The two use cases form one flow: the anti-fraud system blocks the card, and the customer later confirms or rejects the suspicious transaction. Containers are described in [containers.md](../containers.md).

## 1. UC-06 Anti-Fraud Block

```mermaid
sequenceDiagram
    autonumber
    participant AF as Anti-Fraud System
    participant K as Kafka
    participant CS as Card Service
    participant DB as Card DB
    participant PC as Processing Center
    participant NS as Notification Service
    actor C as Customer

    AF->>K: SuspiciousTransactionDetected
    K->>CS: Deliver event (at least once)

    alt Malformed event or unknown card (ext. 1a)
        CS->>K: Move to dead-letter queue
    else Event ID already processed (ext. 2a)
        CS->>K: Acknowledge, no changes
    else New event
        CS->>DB: Load card status
        alt Card is ACTIVE
            CS->>PC: Block card
            alt Processing center confirms
                PC-->>CS: Blocked
                rect rgb(235, 245, 255)
                    note over CS,DB: One DB transaction (UC step 5-6)
                    CS->>DB: status FRAUD_BLOCKED, reason FRAUD_SUSPECTED
                    CS->>DB: Insert status history T3
                    CS->>DB: Open fraud case with transaction
                    CS->>DB: Mark event ID processed
                    CS->>DB: Insert CardBlocked into outbox
                end
                CS->>K: Acknowledge event
            else Processing center unavailable (ext. 4a)
                PC--xCS: Timeout
                note over CS,K: Event is not acknowledged and is redelivered
            end
        else Card is FRAUD_BLOCKED (ext. 3a)
            CS->>DB: Add transaction to open fraud case, mark event processed
            CS->>K: Acknowledge event
        else Card is TEMP_BLOCKED, PERM_BLOCKED or CLOSED (ext. 3b)
            CS->>DB: Log ignored event, mark event processed
            CS->>K: Acknowledge event
        end
    end

    K->>NS: CardBlocked (reason FRAUD_SUSPECTED)
    NS-->>C: Push and SMS with transaction details
```

## 2. UC-07 Customer Response

```mermaid
sequenceDiagram
    autonumber
    actor C as Customer
    participant App as Mobile App
    participant AS as Auth Service
    participant CS as Card Service
    participant DB as Card DB
    participant PC as Processing Center
    participant K as Kafka

    C->>App: Open notification
    App->>CS: GET /fraud-cases/{caseId}
    CS-->>App: Transactions, case version
    App-->>C: Did you make these transactions?

    alt It was me
        C->>App: Yes, it was me
        App->>AS: Request step-up (biometrics or OTP)
        AS-->>C: OTP via SMS (if no biometrics)
        C->>App: Enter OTP
        App->>AS: Verify OTP
        AS-->>App: Step-up token (card, action, 5 min)
        App->>CS: POST /fraud-cases/{caseId}/resolution<br/>CONFIRMED, case version, step-up token
        CS->>AS: Validate step-up token
        AS-->>CS: Valid
        CS->>DB: Check case is open and version matches
        alt Case changed (ext. 8b)
            CS-->>App: 409 FRAUD_CASE_CHANGED
            App-->>C: Show updated transactions
        else Case unchanged
            CS->>PC: Unblock card
            alt Processing center confirms
                PC-->>CS: Unblocked
                rect rgb(235, 245, 255)
                    note over CS,DB: One DB transaction (UC step 10-11)
                    CS->>DB: status ACTIVE, clear reason, history T4
                    CS->>DB: Close case CONFIRMED_BY_CUSTOMER
                    CS->>DB: Outbox CardUnblocked, FraudCaseResolved
                end
                CS-->>App: 200 OK, card ACTIVE
                App-->>C: Card active, repeat the transaction if needed
            else Processing center unavailable (ext. 9a)
                CS-->>App: 503, card stays FRAUD_BLOCKED, no background retry
            end
        end
    else Not me (ext. 4a)
        C->>App: No, it wasn't me, confirm permanent block
        App->>CS: POST /fraud-cases/{caseId}/resolution<br/>REJECTED, case version
        note over CS: No step-up token required (BR-07-2)
        CS->>PC: Block card permanently (UC-04 from step 6)
        PC-->>CS: Blocked
        rect rgb(235, 245, 255)
            note over CS,DB: One DB transaction
            CS->>DB: status PERM_BLOCKED, reason FRAUD_CONFIRMED, history T5
            CS->>DB: Close case REJECTED_BY_CUSTOMER
            CS->>DB: Outbox CardBlocked, FraudCaseResolved
        end
        CS-->>App: 200 OK, card PERM_BLOCKED
        App-->>C: Offer reissue (UC-05)
    end

    CS->>K: Outbox relay publishes events
    note over K: FraudCaseResolved is consumed by the Anti-Fraud System,<br/>card events by the Notification Service
```

## Notes

- **Case version** protects against the race in UC-07, ext. 8b: the customer's answer is accepted only for the exact set of transactions they saw.
- **Step-up token** is short-lived and bound to the customer, the card and the action, so it cannot be reused to unblock another card or for another action.
- **FraudCaseResolved** is published for both answers, giving the anti-fraud system feedback on false positives and confirmed fraud.