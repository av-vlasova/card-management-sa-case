# Bank Card Management in a Mobile App

A system analyst case study covering requirements, a state model, integrations, API and data model for card management features (blocking, unblocking, reissue, response to anti-fraud alerts) in the mobile app of a fictional bank, **The Bank**.

## Problem and Goal

A customer who has lost their card or has spotted a suspicious transaction needs to protect their money within seconds, without calling the bank. The bank needs blocking to be applied reliably and irreversible actions to never happen by accident.

**The goal** is to let customers do the following procedures in the app:
- temporarily block and unblock a card;
- permanently block a lost or stolen card and order a replacement;
- respond quickly when the anti-fraud system automatically blocks their card.

## Scope

### Actors

| Actor | Type | Role |
|---|---|---|
| Customer | User | Mobile app user and cardholder |
| Anti-fraud system | External system | Initiates blocking when a suspicious transaction is detected |
| Card processing center | External system | Enforces card status during transaction authorization |

### Use Cases (core)

| ID | Name | Initiator | Level of detail |
|---|---|---|---|
| [UC-01](docs/02-requirements/use-cases/UC-01-card-list.md) | View cards | Customer | Brief |
| [UC-02](docs/02-requirements/use-cases/UC-02-temp-block.md) | Temporarily block a card | Customer | **Fully dressed** |
| [UC-03](docs/02-requirements/use-cases/UC-03-unblock.md) | Unblock a card | Customer | Brief |
| [UC-04](docs/02-requirements/use-cases/UC-04-permanent-block.md) | Permanently block a lost or stolen card | Customer | Brief |
| [UC-05](docs/02-requirements/use-cases/UC-05-reissue.md) | Reissue a card | Customer | **Fully dressed** |
| [UC-06](docs/02-requirements/use-cases/UC-06-fraud-block.md) | Block a card on an anti-fraud alert | Anti-fraud system | Brief |
| [UC-07](docs/02-requirements/use-cases/UC-07-fraud-confirm.md) | Confirm or reject a suspicious transaction | Customer | **Fully dressed** |

### Out of Scope

Card issuance and activation, spending limits, block history, blocking by a contact center agent, migrating recurring payments, closing a card without reissue.


## Card State Model

```mermaid
stateDiagram-v2

    state "Active<br/>ACTIVE" as ACTIVE
    state "Temporarily blocked<br/>TEMP_BLOCKED" as TEMP_BLOCKED
    state "Blocked by anti-fraud<br/>FRAUD_BLOCKED" as FRAUD_BLOCKED
    state "Permanently blocked<br/>PERM_BLOCKED" as PERM_BLOCKED
    state "Closed<br/>CLOSED" as CLOSED

    [*] --> ACTIVE : issue and activation (out of scope)

    ACTIVE --> TEMP_BLOCKED : T1 · UC-02
    TEMP_BLOCKED --> ACTIVE : T2 · UC-03

    ACTIVE --> FRAUD_BLOCKED : T3 · UC-06
    FRAUD_BLOCKED --> ACTIVE : T4 · UC-07 "It was me"
    FRAUD_BLOCKED --> PERM_BLOCKED : T5 · UC-07 "It was not me" → UC-04

    ACTIVE --> PERM_BLOCKED : T6 · UC-04
    TEMP_BLOCKED --> PERM_BLOCKED : T7 · UC-04

    PERM_BLOCKED --> CLOSED : T8 · UC-05 (new card issued)
    CLOSED --> [*]
```

Full transition table, guard conditions and forbidden transitions: [card-lifecycle.md](docs/03-state-model/card-lifecycle.md).

## Repository Structure

```
card-management-sa-case/
├── README.md                         ← you are here
├── docs/
│   ├── 01-context/
│   │   ├── vision.md                 ← problem, goals, success metrics
│   │   ├── glossary.md               ← terms and statuses
│   │   └── context-diagram.md        ← C4 Level 1: system and environment
│   ├── 02-requirements/
│   │   ├── business-requirements.md
│   │   ├── nfr.md                    ← performance, security, audit
│   │   ├── user-stories.md           ← stories with acceptance criteria
│   │   └── use-cases/
│   │       ├── UC-01-card-list.md
│   │       ├── UC-02-temp-block.md
│   │       ├── UC-03-unblock.md
│   │       ├── UC-04-permanent-block.md
│   │       ├── UC-05-reissue.md
│   │       ├── UC-06-fraud-block.md
│   │       └── UC-07-fraud-confirm.md
│   ├── 03-state-model/
│   │   └── card-lifecycle.md         ← state diagram and transition table
│   ├── 04-architecture/
│   │   ├── containers.md             ← C4 Level 2: services
│   │   └── sequences/
│   │       ├── SD-UC-02-temp-block.md
│   │       ├── SD-UC-05-reissue-saga.md
│   │       └── SD-UC-06-07-fraud.md
├── api/
│   └── card-api.openapi.yaml         ← REST API for the mobile app
├── events/
│   └── card-events.asyncapi.yaml     ← event contracts (Kafka)
└── db/
    ├── erd.md                        ← ERD in Mermaid
    ├── schema.sql                    ← DDL, PostgreSQL
    └── queries.sql                   ← analytical queries
```

## Skills Demonstrated

| Skill | Where to look |
|---|---|
| Requirements elicitation and specification | `business-requirements.md`, `user-stories.md`, `use-cases/` |
| Non-functional requirements | `nfr.md` |
| State modeling | `card-lifecycle.md` |
| Architecture and integrations (C4, sequence diagrams) | `04-architecture/` |
| Distributed transactions (saga, compensations, idempotency) | `SD-UC-05-reissue-saga.md` |
| REST API design (OpenAPI) | `api/card-api.openapi.yaml` |
| Asynchronous messaging (AsyncAPI, Kafka) | `events/card-events.asyncapi.yaml` |
| Data modeling and SQL (PostgreSQL) | `db/` |

**Notations and tools:** UML (use case, state, sequence), C4, Mermaid, PlantUML, OpenAPI 3.0, AsyncAPI 2.6, Gherkin, PostgreSQL.

## About me

**Alina Vlasova**, System Analyst <br> Telegram: `@drunkenwhal3r` · Email: `avzhorina@gmail.com` · [CV](...)