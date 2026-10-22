# SD-UC-02 Temporarily Block a Card

Sequence diagram for [UC-02](../../02-requirements/use-cases/UC-02-temp-block.md). Arrow numbers are the diagram's own; "UC step" and "ext." in notes refer to the use case. Containers are described in [containers.md](../containers.md).

## Main Scenario and Key Extensions

```mermaid
sequenceDiagram
    autonumber
    actor C as Customer
    participant App as Mobile App
    participant GW as API Gateway
    participant CS as Card Service
    participant DB as Card DB
    participant PC as Processing Center
    participant K as Kafka
    participant NS as Notification Service

    C->>App: Tap Block temporarily
    App-->>C: Confirmation dialog
    C->>App: Confirm
    App->>GW: POST /cards/{cardId}/block<br/>Idempotency-Key
    GW->>CS: Forward request with customer ID

    CS->>DB: Find stored result by idempotency key
    alt Key already processed (ext. 4b)
        DB-->>CS: Stored response
        CS-->>App: Same response as the first request
    else New key
        CS->>DB: Load card, check owner and status
        alt Card is ACTIVE
            CS->>PC: Block card (operation ID)
            alt Processing center confirms (UC steps 6-7)
                PC-->>CS: Blocked
                rect rgb(235, 245, 255)
                    note over CS,DB: One DB transaction (UC step 8-9)
                    CS->>DB: status TEMP_BLOCKED, reason CUSTOMER_REQUEST
                    CS->>DB: Insert status history T1
                    CS->>DB: Insert CardBlocked into outbox
                    CS->>DB: Save response by idempotency key
                end
                CS-->>App: 200 OK, card status TEMP_BLOCKED
                App-->>C: Card shown as blocked
            else Timeout or unavailable (ext. 6a)
                PC--xCS: No response within 3 s
                CS->>DB: Create operation PENDING, card stays ACTIVE
                CS-->>App: 202 Accepted, operation ID
                App-->>C: Blocking in progress
                loop Until operation is DONE or FAILED
                    App->>GW: GET /operations/{operationId}
                    GW->>CS: Forward
                    CS-->>App: Operation status
                end
                note over CS,PC: Background retries with backoff,<br/>on success continue as in step 8
            end
        else Card is TEMP_BLOCKED (ext. 5b)
            CS-->>App: 200 OK, status unchanged, no event
        else Card is FRAUD_BLOCKED (ext. 5c)
            CS-->>App: 409 CARD_FRAUD_BLOCKED
            App-->>C: Show suspicious transaction (UC-07)
        else Card is PERM_BLOCKED or CLOSED (ext. 5d)
            CS-->>App: 409 CARD_STATUS_FINAL
        else Card not found or not owned (ext. 5a)
            CS-->>App: 404 CARD_NOT_FOUND
        end
    end

    note over CS,K: Outbox relay, asynchronous (UC step 9, ext. 9a)
    CS->>K: Publish CardBlocked
    K->>NS: CardBlocked
    NS-->>C: Push notification (UC step 12)
```

## Notes

- **Status check and update** are protected by optimistic locking on the card version. If the status changed between reading and writing (ext. 5e), the Card Service re-reads the card and re-evaluates the request.
- **Processing center call** carries the operation ID, so a background retry never creates a second block operation on the processing side.
- **Outbox relay** is a separate process inside the Card Service that reads unpublished outbox records and publishes them to Kafka. Publishing does not block the customer's response.