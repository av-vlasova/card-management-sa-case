# User Stories

User stories for the card management features, with acceptance criteria in Gherkin. Each story is traced to a use case and a business requirement. Use cases describe the full behavior, including every extension; stories split that behavior into increments a team can deliver and test.

Related: [README](../../README.md) · [Business requirements](business-requirements.md) · [NFR](nfr.md) · [Use cases](use-cases/)

## Story Map

| ID | Story | Use case | Requirement | Priority |
|---|---|---|---|---|
| [US-01](#us-01-see-my-cards-and-their-statuses) | See my cards and their statuses | UC-01 | REQ-01 | Must |
| [US-02](#us-02-block-a-card-temporarily) | Block a card temporarily | UC-02 | REQ-02, REQ-03 | Must |
| [US-03](#us-03-see-that-blocking-is-in-progress) | See that blocking is in progress | UC-02 | REQ-03, REQ-13 | Must |
| [US-04](#us-04-unblock-a-card) | Unblock a card | UC-03 | REQ-02, REQ-04 | Must |
| [US-05](#us-05-block-a-lost-or-stolen-card-permanently) | Block a lost or stolen card permanently | UC-04 | REQ-05 | Must |
| [US-06](#us-06-order-a-replacement-card) | Order a replacement card | UC-05 | REQ-06 | Must |
| [US-07](#us-07-follow-the-reissue) | Follow the reissue | UC-05 | REQ-07 | Should |
| [US-08](#us-08-get-notified-when-anti-fraud-blocks-my-card) | Get notified when anti-fraud blocks my card | UC-06 | REQ-08 | Must |
| [US-09](#us-09-confirm-a-suspicious-transaction-as-mine) | Confirm a suspicious transaction as mine | UC-07 | REQ-04, REQ-09 | Must |
| [US-10](#us-10-report-a-suspicious-transaction-as-fraud) | Report a suspicious transaction as fraud | UC-07 | REQ-09 | Must |
| [US-11](#us-11-send-customer-answers-to-the-anti-fraud-system) | Send customer answers to the anti-fraud system | UC-07 | REQ-10 | Should |

## US-01 See my cards and their statuses

**As a** customer,
**I want** to see all my cards with their statuses,
**so that** I know which cards I can pay with and what I can do with each one.

```gherkin
Feature: Card list

  Scenario: Cards are shown with their status and available actions
    Given I have an active card ending in 4417
    And I have a temporarily blocked card ending in 0238
    When I open the Cards section
    Then I see the card ending in 4417 with the actions "Block temporarily" and "Block permanently"
    And I see the card ending in 0238 labelled "Blocked" with the actions "Unblock" and "Block permanently"

  Scenario: Card numbers are always masked
    When I open the Cards section
    Then every card number is shown as "•••• " followed by its last four digits

  Scenario: Closed cards are shown separately
    Given I have a card that was closed 2 months ago
    And I have a card that was closed 13 months ago
    When I open the Cards section
    Then I see the card closed 2 months ago in the collapsed "Closed cards" section
    And I do not see the card closed 13 months ago
```

## US-02 Block a card temporarily

**As a** customer who can't find my card,
**I want** to block it in a couple of taps,
**so that** nobody can pay with it while I look for it.

```gherkin
Feature: Temporary block

  Background:
    Given I have an active card ending in 4417

  Scenario: Successful temporary block
    When I tap "Block temporarily" on the card
    And I confirm the block
    Then the card is shown as "Blocked"
    And transactions on the card are declined
    And I receive a push notification that the card is blocked

  Scenario: No additional confirmation is required to block
    When I tap "Block temporarily" on the card
    Then I am asked only to confirm the action
    And I am not asked for a one-time password or biometrics

  Scenario: Repeated block request does not cause an error
    Given the card is already temporarily blocked
    When the app sends the block request again
    Then the response is successful
    And the card stays "Blocked"
    And I do not receive a second notification

  Scenario: A card blocked by anti-fraud cannot be blocked temporarily
    Given the card is blocked by the anti-fraud system
    When I try to block the card temporarily
    Then I see the suspicious transaction and the question "Did you make this transaction?"
```

## US-03 See that blocking is in progress

**As a** customer,
**I want** to know when my block has not been applied yet,
**so that** I don't think my card is safe when it isn't.

```gherkin
Feature: Pending block

  Background:
    Given I have an active card ending in 4417
    And the processing center does not respond

  Scenario: Block is accepted and applied later
    When I block the card temporarily
    Then I see "Blocking in progress"
    And the card is not shown as "Blocked"
    When the processing center confirms the block within 15 minutes
    Then the card is shown as "Blocked"
    And I receive a push notification that the card is blocked

  Scenario: Block cannot be applied
    When I block the card temporarily
    And the processing center does not confirm the block within 15 minutes
    Then I receive a notification advising me to call the hotline
    And the support team receives an alert
    And the card stays active
```

## US-04 Unblock a card

**As a** customer who has found my card,
**I want** to unblock it in the app,
**so that** I can pay with it again.

```gherkin
Feature: Unblock

  Background:
    Given I have a temporarily blocked card ending in 4417

  Scenario: Successful unblock with biometrics
    Given biometrics are enabled on my device
    When I tap "Unblock" on the card
    And I confirm with biometrics
    Then the card is shown as active
    And I receive a push notification that the card is unblocked

  Scenario: Unblock with a one-time password
    Given biometrics are not enabled on my device
    When I tap "Unblock" on the card
    Then I receive a one-time password by SMS
    When I enter the correct password
    Then the card is shown as active

  Scenario: Too many wrong passwords
    When I tap "Unblock" on the card
    And I enter a wrong one-time password 3 times
    Then unblocking this card is locked for 30 minutes
    And I receive a security notification
    And the card stays blocked

  Scenario: Unblock is not retried in the background
    Given the processing center is unavailable
    When I unblock the card with a valid confirmation
    Then I see an error asking me to try again later
    And the card stays blocked
    And the card does not become active later without my action

  Scenario Outline: Cards that cannot be unblocked here
    Given my card is <status>
    When I try to unblock the card
    Then I see <result>

    Examples:
      | status                            | result                                         |
      | blocked by the anti-fraud system  | the suspicious transaction to review           |
      | permanently blocked               | an offer to reissue the card                   |
```

## US-05 Block a lost or stolen card permanently

**As a** customer whose card is lost or stolen,
**I want** to block it permanently,
**so that** it can never be used again and I can get a new one.

```gherkin
Feature: Permanent block

  Scenario Outline: Successful permanent block
    Given I have a <status> card ending in 4417
    When I tap "Block permanently" on the card
    And I choose the reason "<reason>"
    And I confirm that I understand the block cannot be undone
    Then the card is shown as "Blocked permanently"
    And I am offered to reissue the card

    Examples:
      | status               | reason |
      | active               | Lost   |
      | active               | Stolen |
      | temporarily blocked  | Lost   |

  Scenario: The warning cannot be skipped
    Given I have an active card ending in 4417
    When I tap "Block permanently" and choose a reason
    Then I see a warning that the card will have to be reissued
    And the confirm button is not the default button

  Scenario: No one-time password is required
    Given I have an active card ending in 4417
    When I block the card permanently
    Then I am not asked for a one-time password or biometrics

  Scenario: A permanent block cannot be undone
    Given my card is permanently blocked
    When I open the card
    Then the "Unblock" action is not available
```

## US-06 Order a replacement card

**As a** customer with a permanently blocked card,
**I want** to order a new card in the app,
**so that** I don't have to visit a branch.

```gherkin
Feature: Reissue

  Background:
    Given my card ending in 4417 is permanently blocked

  Scenario: Order with courier delivery
    When I tap "Reissue" on the card
    And I choose courier delivery on an available date and time slot
    And I confirm the order
    Then I immediately see that my request is accepted
    And I see that the new card will have a new number

  Scenario: Courier delivery is not available at my address
    Given courier delivery is not available at my registered address
    When I tap "Reissue" on the card
    Then I can only choose pickup at a branch
    And I see why courier delivery is not available

  Scenario: Only one reissue at a time
    Given I have already ordered a replacement for this card
    When I tap "Reissue" on the card again
    Then I see my existing request
    And no second request is created

  Scenario: An active card cannot be reissued
    Given my card ending in 0238 is active
    Then the "Reissue" action is not available on that card
```

## US-07 Follow the reissue

**As a** customer who ordered a new card,
**I want** to see what is happening with my order,
**so that** I know when to expect the card.

```gherkin
Feature: Reissue progress

  Background:
    Given I have ordered a replacement for my card ending in 4417

  Scenario: Reissue completed
    When the new card is issued and its delivery is ordered
    Then I receive a push notification with the delivery date
    And I see the new card in my card list with delivery tracking
    And the old card is moved to "Closed cards"

  Scenario: Reissue failed and was rolled back
    When the delivery partner rejects the order
    Then I receive a notification with the reason
    And I am offered to reissue the card with another delivery option
    And the old card stays "Blocked permanently"
    And no new card appears in my card list

  Scenario: Reissue needs manual handling
    When the reissue cannot be completed or rolled back automatically
    Then I see that my request is being processed by support
    And the support team receives an alert
```

## US-08 Get notified when anti-fraud blocks my card

**As a** customer,
**I want** to be told immediately and in detail when my card is blocked for security reasons,
**so that** I don't find out from a declined payment.

```gherkin
Feature: Anti-fraud block

  Background:
    Given I have an active card ending in 0238

  Scenario: Card is blocked after a suspicious transaction
    When the anti-fraud system reports a suspicious transaction of 18,990.00 RUB at "ELECTRO-WORLD ONLINE"
    Then the card is blocked
    And I receive a push notification and an SMS with the amount and the merchant
    And the card is shown as "Blocked for security reasons" with the action "Review transaction"

  Scenario: Second suspicious transaction on a blocked card
    Given the card is blocked by the anti-fraud system
    When the anti-fraud system reports another suspicious transaction on the card
    Then the transaction is added to the same review
    And I receive a notification about it

  Scenario: The same alert is delivered twice
    When the same suspicious transaction event is delivered twice
    Then the card is blocked once
    And I receive one notification

  Scenario: The card stays blocked until I answer
    Given the card has been blocked by the anti-fraud system for 3 days
    And I have not answered
    Then the card is still blocked
```

## US-09 Confirm a suspicious transaction as mine

**As a** customer whose card was blocked by mistake,
**I want** to confirm that the transaction was mine,
**so that** I can use my card again right away.

```gherkin
Feature: Confirm suspicious transaction

  Background:
    Given my card ending in 0238 is blocked by the anti-fraud system
    And the review shows one transaction of 18,990.00 RUB at "ELECTRO-WORLD ONLINE"

  Scenario: Successful confirmation
    When I answer "Yes, it was me"
    And I confirm with biometrics
    Then the card is shown as active
    And I am told I may need to repeat the payment

  Scenario: Confirmation requires biometrics or a one-time password
    When I answer "Yes, it was me"
    Then I am asked for biometrics or a one-time password
    And the card is not unblocked until I pass the check

  Scenario: A new transaction appears while I am reviewing
    Given I have opened the review
    And the anti-fraud system adds another suspicious transaction
    When I answer "Yes, it was me" and confirm with biometrics
    Then I see the updated list of transactions
    And I am asked to answer again
    And the card stays blocked

  Scenario: I recognize only some of the transactions
    Given the review shows two transactions
    And I recognize only one of them
    Then I must answer "No, it wasn't me"
```

## US-10 Report a suspicious transaction as fraud

**As a** customer whose card was used by someone else,
**I want** to report the transaction as fraud,
**so that** my card is blocked for good and I get a new one.

```gherkin
Feature: Report fraud

  Background:
    Given my card ending in 0238 is blocked by the anti-fraud system

  Scenario: Successful fraud report
    When I answer "No, it wasn't me"
    And I confirm that the card will be blocked permanently
    Then the card is shown as "Blocked permanently"
    And I am offered to reissue the card
    And I am told that disputing the transaction is handled by the contact center

  Scenario: Reporting fraud does not require a one-time password
    When I answer "No, it wasn't me"
    Then I am not asked for a one-time password or biometrics

  Scenario: Fraud can be reported while confirmation is locked
    Given I have entered a wrong one-time password 3 times while confirming the transaction
    When I answer "No, it wasn't me"
    Then the card is blocked permanently
```

## US-11 Send customer answers to the anti-fraud system

**As an** anti-fraud analyst,
**I want** to receive every customer's answer about a suspicious transaction,
**so that** I can measure false positives and improve the rules.

```gherkin
Feature: Fraud case feedback

  Scenario Outline: Every answer is published
    Given a fraud case for a card with one suspicious transaction
    When the customer answers "<answer>" in the <channel>
    Then a FraudCaseResolved event is published with resolution "<resolution>" and channel "<channel_code>"
    And the event lists the transaction IDs from the case

    Examples:
      | answer             | channel        | resolution            | channel_code   |
      | Yes, it was me     | mobile app     | CONFIRMED_BY_CUSTOMER | MOBILE_APP     |
      | No, it wasn't me   | mobile app     | REJECTED_BY_CUSTOMER  | MOBILE_APP     |
      | Yes, it was me     | contact center | CONFIRMED_BY_CUSTOMER | CONTACT_CENTER |

  Scenario: The event is not lost if Kafka is unavailable
    Given Kafka is unavailable
    When the customer answers "Yes, it was me"
    Then the customer sees the result without delay
    And the FraudCaseResolved event is published once Kafka is available again
```