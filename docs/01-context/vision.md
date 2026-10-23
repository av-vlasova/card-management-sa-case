# Vision

Why the card management features exist, who they are for and how success is measured.

Related: [README](../../README.md) · [Business requirements](../02-requirements/business-requirements.md) · [Context diagram](context-diagram.md) · [Glossary](glossary.md)

## Problem

When a card is lost, stolen or used by someone else, every minute counts. Today, a customer of The Bank who needs to block a card has to call the hotline: wait in a queue, pass identification, explain the situation. Meanwhile, transactions on the card can still go through.

The same happens in the other direction. When the anti-fraud system blocks a card because of a suspicious transaction, the customer often learns about it only when their next payment is declined. To get the card working again, they have to call the bank, even if the "suspicious" transaction was their own.

| Who is affected | How |
|---|---|
| Customers | Money at risk while they wait for the hotline; declined payments and no clear way to unblock after a false anti-fraud alert |
| The Bank | Fraud losses; contact center load (card blocking is one of the most frequent reasons to call); customer churn after bad experiences |
| Anti-fraud team | No fast feedback on whether an alert was correct, which makes tuning the rules slow |

## Vision Statement

> **For** customers of The Bank **who** need to protect their money when a card is lost, stolen or compromised, **the card management features** of the mobile app **let them** block, unblock and replace a card and respond to anti-fraud alerts in a few taps, at any time, without calling the bank. **Unlike** blocking through the hotline, **the app** applies a block in seconds and shows the customer exactly what is happening with their card.

## Target Users

| User | Situation | What they need |
|---|---|---|
| Customer who can't find their card | Probably left it somewhere, not sure it's lost | A quick, reversible block, and an easy way to undo it |
| Customer whose card is lost or stolen | Sure the card is gone | A permanent block and a replacement card without visiting a branch |
| Customer who received an anti-fraud alert | Card suddenly blocked, may be in a shop or travelling | To see what triggered the block and get the card working again, or confirm fraud and get a new card |

## Business Goals and Success Metrics

| ID | Goal | Metric | Target (6 months after launch) | How it is measured |
|---|---|---|---|---|
| G-1 | Customers block cards themselves | Share of card blocks made in the app (vs. contact center) | ≥ 80% | `card_status_history.channel` for T1, T6, T7 |
| G-2 | Reduce contact center load | Calls with the reason "block / unblock card" | −50% vs. the 3 months before launch | Contact center reporting |
| G-3 | Shorten the time a card stays blocked after a false anti-fraud alert | Median time from anti-fraud block to the customer's response | ≤ 2 h | [Q3](../../db/queries.sql) |
| G-4 | Give the anti-fraud team feedback | Share of fraud cases resolved by the customer | ≥ 90% within 7 days | `fraud_case.status`, [Q1](../../db/queries.sql) |
| G-5 | Replace lost cards without branch visits | Share of permanently blocked cards reissued through the app | ≥ 70% | [Q5](../../db/queries.sql) |
| G-6 | Keep the experience reliable | Share of reissue requests completed without manual handling | ≥ 97% | [Q6](../../db/queries.sql) |

## Scope

**In scope:** viewing cards and statuses, temporary block and unblock, permanent block for a lost or stolen card, reissue with courier delivery or branch pickup, anti-fraud block and the customer's response to it. Details: [README, Scope](../../README.md#scope).

**Out of scope for this release:** card issuance and activation, spending limits, block history in the app, blocking by a contact center agent, migrating recurring payments to the new card, disputing transactions (chargeback), reissue fees.

## Principles

1. **Blocking is fast; unblocking is safe.** Protective actions never require extra confirmation. Actions that remove protection always do.
2. **What the customer sees is true.** The app never shows a card as blocked before the processing center has confirmed it.
3. **Nothing is lost silently.** Every failed or delayed operation is either retried automatically or handed over to people, and the customer is told what is happening.