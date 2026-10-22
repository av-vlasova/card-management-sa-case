# SD-UC-05 Reissue a Card (Saga)

Sequence diagrams for [UC-05](../../02-requirements/use-cases/UC-05-reissue.md). The reissue is split into two diagrams: the customer placing the order (synchronous) and the saga run by the Card Service (asynchronous). Containers are described in [containers.md](../containers.md).

## 1. Placing the Reissue Request

```mermaid
sequenceDiagram
    autonumber
    actor C as Customer
    participant App as Mobile App
    participant CS as Card Service
    participant DB as Card DB
    participant DS as Delivery Service

    C->>App: Tap Reissue
    App->>CS: GET /cards/{cardId}/reissue-options
    CS->>DS: Get delivery options for customer address
    DS-->>CS: Courier slots, branches
    CS-->>App: Delivery options
    C->>App: Select option, confirm summary
    App->>CS: POST /cards/{cardId}/reissue<br/>Idempotency-Key
    CS->>DB: Load card, check status PERM_BLOCKED

    alt Active reissue request exists (ext. 7d)
        DB-->>CS: Existing request
        CS-->>App: 200 OK, existing request
    else No active request
        rect rgb(235, 245, 255)
            note over CS,DB: One DB transaction (UC step 8)
            CS->>DB: Insert reissue request CREATED
            CS->>DB: Insert CardReissueRequested into outbox
        end
        CS-->>App: 202 Accepted, request ID
    end

    App-->>C: Request progress screen
    note over CS: Saga starts asynchronously
```

## 2. Reissue Saga

```mermaid
sequenceDiagram
    autonumber
    participant CS as Card Service<br/>(orchestrator)
    participant DB as Card DB
    participant PC as Processing Center
    participant DS as Delivery Service
    participant K as Kafka

    note over CS,K: Every step result is saved in the reissue request before the next step starts

    CS->>PC: S1 Issue new card (request ID as idempotency key)
    alt S1 succeeds
        PC-->>CS: New card ID
        CS->>DB: Request NEW_CARD_ISSUED, save new card ID
    else S1 fails after retries (ext. 10a)
        CS->>DB: Request FAILED, outbox CardReissueFailed
        note over CS: Nothing to compensate, saga ends
    end

    CS->>DS: S2 Place delivery order (request ID as idempotency key)
    alt S2 succeeds
        DS-->>CS: Order ID, delivery date
        CS->>DB: Request DELIVERY_ORDERED
    else S2 rejected (ext. 11a)
        DS-->>CS: Rejected with reason
        CS->>DB: Request COMPENSATING
        CS->>PC: Compensate S1, cancel new card
        alt Compensation succeeds
            PC-->>CS: Cancelled
            CS->>DB: Request FAILED, outbox CardReissueFailed
        else Compensation fails after retries (ext. 11a1a)
            CS->>DB: Request MANUAL_HANDLING
            note over CS: Alert support team
        end
    else S2 outcome unknown (ext. 11b)
        DS--xCS: Timeout
        CS->>DS: Retry with same request ID, then query order status
        note over CS,DS: Order exists: continue to S3.<br/>Order missing: compensate as on rejection.
    end

    note over CS,PC: Pivot step. From here the saga only moves forward.

    loop Retry until success (ext. 12a)
        CS->>PC: S3 Close old card
        PC-->>CS: Closed
    end
    rect rgb(235, 245, 255)
        note over CS,DB: One DB transaction
        CS->>DB: Old card status CLOSED, history T8
        CS->>DB: Link old card to new card
        CS->>DB: Request OLD_CARD_CLOSED
    end

    rect rgb(235, 245, 255)
        note over CS,DB: One DB transaction (S4)
        CS->>DB: Request COMPLETED
        CS->>DB: Insert CardReissued into outbox
    end
    CS->>K: Outbox relay publishes CardReissued
    note over K: Notification Service notifies the customer,<br/>other consumers update their data
```

## Notes

- **Saga state is persisted** before and after every external call. After a restart, the orchestrator loads all requests in intermediate statuses and resumes each from its last completed step (UC-05, ext. \*a).
- **Every external call is idempotent** thanks to the reissue request ID, so a resumed or retried step never issues a second card or places a second order.
- **Compensations are also idempotent and retried.** If a compensation cannot be completed, the request goes to `MANUAL_HANDLING` instead of being left in an intermediate state.