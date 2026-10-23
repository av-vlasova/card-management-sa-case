-- =============================================================================
-- Card Service database schema
-- PostgreSQL 16
--
-- Part of the card management case study. See db/erd.md for the diagram and
-- docs/03-state-model/card-lifecycle.md for the state model these tables
-- enforce.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Enumerations
-- -----------------------------------------------------------------------------

CREATE TYPE card_status AS ENUM (
    'ACTIVE', 'TEMP_BLOCKED', 'FRAUD_BLOCKED', 'PERM_BLOCKED', 'CLOSED'
);

CREATE TYPE block_reason AS ENUM (
    'CUSTOMER_REQUEST', 'FRAUD_SUSPECTED', 'LOST', 'STOLEN', 'FRAUD_CONFIRMED'
);

CREATE TYPE payment_system AS ENUM ('VISA', 'MASTERCARD', 'MIR');

CREATE TYPE initiator_type AS ENUM ('CUSTOMER', 'ANTI_FRAUD', 'SYSTEM');

CREATE TYPE request_channel AS ENUM ('MOBILE_APP', 'CONTACT_CENTER');

CREATE TYPE step_up_method AS ENUM ('BIOMETRICS', 'OTP');

CREATE TYPE operation_type AS ENUM ('TEMP_BLOCK', 'PERMANENT_BLOCK');

CREATE TYPE operation_status AS ENUM ('PENDING', 'DONE', 'FAILED');

CREATE TYPE fraud_case_status AS ENUM (
    'OPEN', 'CONFIRMED_BY_CUSTOMER', 'REJECTED_BY_CUSTOMER'
);

CREATE TYPE reissue_status AS ENUM (
    'CREATED', 'NEW_CARD_ISSUED', 'DELIVERY_ORDERED', 'OLD_CARD_CLOSED',
    'COMPLETED', 'COMPENSATING', 'FAILED', 'MANUAL_HANDLING'
);

CREATE TYPE delivery_method AS ENUM ('COURIER', 'BRANCH');

CREATE TYPE saga_step AS ENUM ('S1', 'S2', 'S3', 'S4');

CREATE TYPE saga_action AS ENUM ('EXECUTE', 'COMPENSATE');

CREATE TYPE saga_step_result AS ENUM ('SUCCESS', 'FAILURE', 'TIMEOUT');


-- -----------------------------------------------------------------------------
-- card
-- The current state of a card. The full card number (PAN) is never stored
-- here; it lives only in the processing center.
-- -----------------------------------------------------------------------------

CREATE TABLE card (
    id                  uuid            PRIMARY KEY,
    customer_id         uuid            NOT NULL,
    account_id          uuid            NOT NULL,
    processing_ref      text            NOT NULL UNIQUE,  -- card ID in the processing center
    pan_last4           char(4)         NOT NULL CHECK (pan_last4 ~ '^\d{4}$'),
    name                text,
    payment_system      payment_system  NOT NULL,
    expiry_month        smallint        NOT NULL CHECK (expiry_month BETWEEN 1 AND 12),
    expiry_year         smallint        NOT NULL CHECK (expiry_year BETWEEN 2000 AND 2099),
    status              card_status     NOT NULL DEFAULT 'ACTIVE',
    block_reason        block_reason,
    version             integer         NOT NULL DEFAULT 1,  -- optimistic locking
    created_at          timestamptz     NOT NULL DEFAULT now(),
    updated_at          timestamptz     NOT NULL DEFAULT now(),
    closed_at           timestamptz,

    -- Allowed block reasons per status (card-lifecycle.md, "Block Reason")
    CONSTRAINT card_status_reason_chk CHECK (
        (status = 'ACTIVE'        AND block_reason IS NULL) OR
        (status = 'TEMP_BLOCKED'  AND block_reason = 'CUSTOMER_REQUEST') OR
        (status = 'FRAUD_BLOCKED' AND block_reason = 'FRAUD_SUSPECTED') OR
        (status IN ('PERM_BLOCKED', 'CLOSED')
                                  AND block_reason IN ('LOST', 'STOLEN', 'FRAUD_CONFIRMED'))
    ),
    CONSTRAINT card_closed_at_chk CHECK ((status = 'CLOSED') = (closed_at IS NOT NULL))
);

CREATE INDEX card_customer_idx ON card (customer_id);
CREATE INDEX card_status_idx   ON card (status) WHERE status <> 'ACTIVE';

COMMENT ON TABLE  card IS 'Current card state. One row per card; a reissued card is a new row.';
COMMENT ON COLUMN card.version IS 'Incremented on every update; used for optimistic locking (UC-02 ext. 5e).';


-- -----------------------------------------------------------------------------
-- card_status_history
-- Append-only log of every status transition (T1-T8). Used for audit,
-- customer support and analytics.
-- -----------------------------------------------------------------------------

CREATE TABLE card_status_history (
    id                  bigint          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    card_id             uuid            NOT NULL REFERENCES card (id),
    transition_id       char(2)         NOT NULL CHECK (transition_id IN ('T1','T2','T3','T4','T5','T6','T7','T8')),
    from_status         card_status     NOT NULL,
    to_status           card_status     NOT NULL,
    block_reason        block_reason,
    initiator_type      initiator_type  NOT NULL,
    channel             request_channel,         -- set when the initiator is a customer
    step_up_method      step_up_method,          -- set for T2 and T4
    correlation_id      uuid,                    -- idempotency key, anti-fraud event ID or reissue request ID
    created_at          timestamptz     NOT NULL DEFAULT now(),

    -- Allowed transitions (card-lifecycle.md, "Transitions")
    CONSTRAINT history_transition_chk CHECK (
        (transition_id = 'T1' AND from_status = 'ACTIVE'        AND to_status = 'TEMP_BLOCKED') OR
        (transition_id = 'T2' AND from_status = 'TEMP_BLOCKED'  AND to_status = 'ACTIVE') OR
        (transition_id = 'T3' AND from_status = 'ACTIVE'        AND to_status = 'FRAUD_BLOCKED') OR
        (transition_id = 'T4' AND from_status = 'FRAUD_BLOCKED' AND to_status = 'ACTIVE') OR
        (transition_id = 'T5' AND from_status = 'FRAUD_BLOCKED' AND to_status = 'PERM_BLOCKED') OR
        (transition_id = 'T6' AND from_status = 'ACTIVE'        AND to_status = 'PERM_BLOCKED') OR
        (transition_id = 'T7' AND from_status = 'TEMP_BLOCKED'  AND to_status = 'PERM_BLOCKED') OR
        (transition_id = 'T8' AND from_status = 'PERM_BLOCKED'  AND to_status = 'CLOSED')
    ),
    CONSTRAINT history_step_up_chk CHECK (
        transition_id NOT IN ('T2', 'T4') OR step_up_method IS NOT NULL
    )
);

CREATE INDEX history_card_time_idx ON card_status_history (card_id, created_at);
CREATE INDEX history_time_idx      ON card_status_history (created_at);

-- History is append-only: updates and deletes are rejected.
CREATE FUNCTION forbid_history_change() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'card_status_history is append-only';
END;
$$;

CREATE TRIGGER history_append_only
    BEFORE UPDATE OR DELETE ON card_status_history
    FOR EACH ROW EXECUTE FUNCTION forbid_history_change();


-- -----------------------------------------------------------------------------
-- card_operation
-- Block operations that could not be confirmed by the processing center in
-- time and are retried in the background (UC-02 ext. 6a, UC-04 ext. 8a).
-- -----------------------------------------------------------------------------

CREATE TABLE card_operation (
    id                  uuid             PRIMARY KEY,
    card_id             uuid             NOT NULL REFERENCES card (id),
    type                operation_type   NOT NULL,
    status              operation_status NOT NULL DEFAULT 'PENDING',
    requested_reason    block_reason     NOT NULL,
    attempts            integer          NOT NULL DEFAULT 0,
    next_attempt_at     timestamptz,
    last_error          text,
    created_at          timestamptz      NOT NULL DEFAULT now(),
    completed_at        timestamptz,

    CONSTRAINT operation_completed_chk CHECK ((status = 'PENDING') = (completed_at IS NULL))
);

-- At most one pending operation per card
CREATE UNIQUE INDEX operation_one_pending_per_card
    ON card_operation (card_id) WHERE status = 'PENDING';

-- Retry scheduler picks due operations
CREATE INDEX operation_due_idx
    ON card_operation (next_attempt_at) WHERE status = 'PENDING';


-- -----------------------------------------------------------------------------
-- fraud_case and fraud_case_transaction
-- A fraud case groups all suspicious transactions on a card while it is
-- FRAUD_BLOCKED (BR-07-3).
-- -----------------------------------------------------------------------------

CREATE TABLE fraud_case (
    id                  uuid              PRIMARY KEY,
    card_id             uuid              NOT NULL REFERENCES card (id),
    status              fraud_case_status NOT NULL DEFAULT 'OPEN',
    version             integer           NOT NULL DEFAULT 1,  -- incremented when a transaction is added (BR-07-4)
    resolution_channel  request_channel,
    step_up_method      step_up_method,                         -- set when confirmed by the customer
    opened_at           timestamptz       NOT NULL DEFAULT now(),
    resolved_at         timestamptz,

    CONSTRAINT fraud_case_resolved_chk CHECK (
        (status = 'OPEN') = (resolved_at IS NULL AND resolution_channel IS NULL)
    ),
    CONSTRAINT fraud_case_step_up_chk CHECK (
        status <> 'CONFIRMED_BY_CUSTOMER' OR step_up_method IS NOT NULL
    )
);

-- At most one open fraud case per card
CREATE UNIQUE INDEX fraud_case_one_open_per_card
    ON fraud_case (card_id) WHERE status = 'OPEN';

CREATE INDEX fraud_case_opened_idx ON fraud_case (opened_at);

CREATE TABLE fraud_case_transaction (
    id                  uuid            PRIMARY KEY,           -- transaction ID from the anti-fraud system
    fraud_case_id       uuid            NOT NULL REFERENCES fraud_case (id),
    source_event_id     uuid            NOT NULL UNIQUE,       -- SuspiciousTransactionDetected eventId
    amount              numeric(18, 2)  NOT NULL CHECK (amount > 0),
    currency            char(3)         NOT NULL,
    merchant            text            NOT NULL,
    mcc                 char(4),
    country             char(2),
    risk_score          numeric(4, 3)   CHECK (risk_score BETWEEN 0 AND 1),
    occurred_at         timestamptz     NOT NULL,
    added_at            timestamptz     NOT NULL DEFAULT now()
);

CREATE INDEX fraud_tx_case_idx ON fraud_case_transaction (fraud_case_id);


-- -----------------------------------------------------------------------------
-- reissue_request and reissue_saga_step
-- The reissue request is also the persisted state of the reissue saga
-- (UC-05). The step log records every execution and compensation attempt.
--
-- The new card row in `card` is created in the same transaction as closing
-- the old card (S3, the pivot step). Until then only the processing center's
-- reference is stored, so a card cancelled by compensation never appears in
-- the customer's card list.
-- -----------------------------------------------------------------------------

CREATE TABLE reissue_request (
    id                      uuid            PRIMARY KEY,
    old_card_id             uuid            NOT NULL REFERENCES card (id),
    new_card_processing_ref text            UNIQUE,                       -- set after S1
    new_card_id             uuid            UNIQUE REFERENCES card (id),  -- set at S3, see below
    status                  reissue_status  NOT NULL DEFAULT 'CREATED',
    delivery_method         delivery_method NOT NULL,
    courier_slot_id         uuid,
    branch_id               text,
    delivery_order_id       text,                                         -- set after S2
    estimated_delivery_date date,
    failed_step             saga_step,
    failure_reason          text,
    created_at              timestamptz     NOT NULL DEFAULT now(),
    updated_at              timestamptz     NOT NULL DEFAULT now(),
    completed_at            timestamptz,

    CONSTRAINT reissue_delivery_chk CHECK (
        (delivery_method = 'COURIER' AND courier_slot_id IS NOT NULL AND branch_id IS NULL) OR
        (delivery_method = 'BRANCH'  AND branch_id IS NOT NULL AND courier_slot_id IS NULL)
    ),
    CONSTRAINT reissue_new_card_ref_chk CHECK (
        status IN ('CREATED', 'FAILED', 'COMPENSATING', 'MANUAL_HANDLING') OR new_card_processing_ref IS NOT NULL
    ),
    CONSTRAINT reissue_new_card_chk CHECK (
        (status IN ('OLD_CARD_CLOSED', 'COMPLETED')) = (new_card_id IS NOT NULL)
    ),
    CONSTRAINT reissue_delivery_order_chk CHECK (
        status NOT IN ('DELIVERY_ORDERED', 'OLD_CARD_CLOSED', 'COMPLETED') OR delivery_order_id IS NOT NULL
    ),
    CONSTRAINT reissue_failed_chk CHECK (
        status NOT IN ('FAILED', 'MANUAL_HANDLING') OR failed_step IS NOT NULL
    ),
    CONSTRAINT reissue_cards_differ_chk CHECK (new_card_id IS NULL OR new_card_id <> old_card_id)
);

-- At most one active reissue request per card (BR-05-2)
CREATE UNIQUE INDEX reissue_one_active_per_card
    ON reissue_request (old_card_id) WHERE status NOT IN ('COMPLETED', 'FAILED');

-- The saga orchestrator resumes requests in intermediate statuses after a restart
CREATE INDEX reissue_in_progress_idx
    ON reissue_request (updated_at) WHERE status NOT IN ('COMPLETED', 'FAILED');

CREATE TABLE reissue_saga_step (
    id                  bigint           GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    reissue_request_id  uuid             NOT NULL REFERENCES reissue_request (id),
    step                saga_step        NOT NULL,
    action              saga_action      NOT NULL,
    attempt             integer          NOT NULL CHECK (attempt >= 1),
    result              saga_step_result NOT NULL,
    error               text,
    created_at          timestamptz      NOT NULL DEFAULT now(),

    -- Only steps before the pivot (S3) can be compensated (BR-05-5)
    CONSTRAINT saga_compensation_chk CHECK (action = 'EXECUTE' OR step IN ('S1', 'S2'))
);

CREATE INDEX saga_step_request_idx ON reissue_saga_step (reissue_request_id, created_at);


-- -----------------------------------------------------------------------------
-- Integration tables
-- -----------------------------------------------------------------------------

-- Transactional outbox: events are written in the same transaction as the
-- state change and published to Kafka by a separate relay.
CREATE TABLE outbox_event (
    id                  uuid            PRIMARY KEY,           -- eventId in message headers
    topic               text            NOT NULL,
    message_key         text            NOT NULL,              -- cardId or oldCardId
    event_type          text            NOT NULL,
    payload             jsonb           NOT NULL,
    headers             jsonb           NOT NULL,
    created_at          timestamptz     NOT NULL DEFAULT now(),
    published_at        timestamptz
);

CREATE INDEX outbox_unpublished_idx ON outbox_event (created_at) WHERE published_at IS NULL;

-- Idempotent consumer: anti-fraud events already processed (BR-06-4).
CREATE TABLE processed_event (
    event_id            uuid            PRIMARY KEY,
    topic               text            NOT NULL,
    outcome             text            NOT NULL CHECK (outcome IN ('BLOCKED', 'ADDED_TO_CASE', 'IGNORED')),
    processed_at        timestamptz     NOT NULL DEFAULT now()
);

-- Stored API responses by idempotency key, kept for 24 hours.
CREATE TABLE idempotency_key (
    customer_id         uuid            NOT NULL,
    key                 uuid            NOT NULL,
    endpoint            text            NOT NULL,              -- e.g. POST /cards/{cardId}/block
    request_hash        char(64)        NOT NULL,              -- SHA-256 of method, path and body
    response_status     smallint        NOT NULL,
    response_body       jsonb           NOT NULL,
    created_at          timestamptz     NOT NULL DEFAULT now(),
    expires_at          timestamptz     NOT NULL DEFAULT now() + interval '24 hours',

    PRIMARY KEY (customer_id, key)
);

CREATE INDEX idempotency_expires_idx ON idempotency_key (expires_at);