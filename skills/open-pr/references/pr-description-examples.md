# PR description examples — one per type

Five bodies in the shape `pr-description-writing.md` defines, for a fictional invoicing app. Read the one matching the type Step A picked; the shape is the target, not the length. Visuals are shown as `[placeholders]`; in a real body each is an uploaded asset URL.

---

## Tiny

**Title:** `Finance Team On Staging Billing`

```markdown
Adds the two finance reviewers to the Billing app on staging so they can test the quarter-end export.

Part of PROJ-410
```

Lede and ticket. Nothing else — no *How it works*, no collapsibles, not even the monitoring one.

---

## Bug fix

**Title:** `Paid Invoices No Longer Get Overdue Reminders`

```markdown
Clients who paid an invoice by bank transfer were still getting "your invoice is overdue" emails for it, sometimes three in a row. Since Tuesday, 41 clients received one. Reminders now check the invoice's live payment status, so a paid invoice never sends one.

Resolves PROJ-388

## What was wrong

The reminder job read `invoice.status`, which is set to `paid` when a card payment clears. Bank transfers are matched by a separate reconciliation job that writes `invoice.paid_at` but, until this change, never updated `status`. So a transfer-paid invoice stayed `sent` forever and the reminder job kept picking it up.

## The fix

`Invoice#paid?` is now the single answer and reads both fields (`status == "paid" || paid_at.present?`). The reminder job, the dashboard badge and the CSV export all call it instead of comparing `status` themselves. The reconciliation job also sets `status = "paid"` going forward, so new rows are consistent either way; a one-off migration backfills the 212 historical rows where `paid_at` was set and `status` was not.

The fix lives on the model rather than in the reminder job because the dashboard had the same bug — a transfer-paid invoice showed an "Unpaid" badge — and the export would have had it next.

## Worth knowing

- The 41 clients who already received a wrong reminder are listed in the ticket. Sending them a correction email is a product decision and is not done here.
- Card refunds set `status = "refunded"` and leave `paid_at` set, so `paid?` returns true for a refunded invoice. That was already the dashboard's behaviour and is unchanged; PROJ-402 tracks a proper refund state.

<details><summary><strong>In this PR</strong></summary>

- Add `Invoice#paid?` reading `status` and `paid_at`; use it in `InvoiceReminderJob`, the dashboard badge and `InvoiceExport`
- Set `status = "paid"` from `ReconciliationJob` when a transfer matches
- Add a migration backfilling `status` where `paid_at` is set
- Add specs for transfer-paid, card-paid, refunded and unpaid invoices against the reminder job

</details>

<details><summary><strong>Verification</strong></summary>

- 318 model and job specs pass, including new cases for transfer-paid, card-paid, refunded and unpaid invoices against the reminder job.
- The backfill migration was run against a staging copy of production: 212 rows updated, 0 rows where `status` was `paid` without `paid_at`.

</details>

<details><summary><strong>Post-deploy monitoring</strong></summary>

**Where to look.** The `InvoiceReminderJob` row in Sidekiq and the `reminders_sent` metric.

**Healthy.** `reminders_sent` drops by roughly 40 per day (the wrong ones) and `reminder_complaints` in support stops growing.

**Failure signal.** Any reminder logged for an invoice with `paid_at` set. Query: `SELECT id FROM reminders r JOIN invoices i ON i.id = r.invoice_id WHERE i.paid_at IS NOT NULL AND r.sent_at > '<deploy time>'`.

**Rollback.** Revert the commit. The migration is additive (sets `status` on rows that already had `paid_at`) and does not need reversing.

</details>
```

---

## Change to existing behavior

**Title:** `Invoice Due Dates Default To Net 30`

```markdown
New invoices now default to a due date 30 days after the issue date instead of 14. The 14-day default came from the original prototype and no client contract uses it; every one of the 60 active clients is on net 30 or longer, so users were changing the date on almost every invoice. The field is still editable.

Resolves PROJ-395

## Before / After

| Before | After |
|---|---|
| ![new invoice form, due date 14 days out](…) | ![new invoice form, due date 30 days out](…) |

| | Before | After |
|---|---|---|
| Default due date | issue date + 14 days | issue date + 30 days |
| Per-client override | none | `Client.payment_terms_days`, shown on the client settings page; when set, it wins over the default |
| Existing invoices | — | untouched; the default applies at creation only |
| API `POST /invoices` without `due_date` | 14 days | 30 days, or the client's terms |

**What did not change:** the reminder schedule (still keyed off the actual due date), the overdue calculation, and any invoice already created.

## How it works

`Invoice#default_due_date` is now `issue_date + (client.payment_terms_days || 30)`. The 30 lives in one constant, `Invoice::DEFAULT_TERMS_DAYS`. The client settings form gains one integer field with a 1–365 validation.

**Why a per-client field rather than just changing the constant?** Twelve clients are on net 45 or net 60, so a single default would still be wrong for a fifth of invoices. The field was a three-line addition once the default was reading through the client.

## Worth knowing

- The public API docs still say "defaults to 14 days". Updated in the same PR; the docs site rebuilds on merge.

<details><summary><strong>In this PR</strong></summary>

- Add `Invoice::DEFAULT_TERMS_DAYS = 30` and read it through `client.payment_terms_days` in `Invoice#default_due_date`
- Add `payment_terms_days` to clients (integer, 1–365) and its field on the client settings form
- Update the API docs for `POST /invoices`
- Add specs for the three-way default

</details>

<details><summary><strong>Verification</strong></summary>

- 84 invoice specs pass, including the three-way default (constant, client override, explicit date).
- Created an invoice on staging for a client with terms set to 45: due date landed 45 days out; for a client with no terms, 30.

</details>
```

---

## New feature

**Title:** `Recurring Invoices`

```markdown
You can now set an invoice to repeat — monthly, quarterly or yearly — and the app creates and sends each one on schedule. Before this, retainer clients were invoiced by duplicating last month's invoice by hand, and two were missed in August. A recurring invoice shows its schedule on the invoice page and can be paused or stopped at any time.

Resolves PROJ-301

[video: setting an invoice to repeat monthly, then seeing the next one appear]

## What you can do now

1. **Open any sent invoice and choose "Repeat this invoice".** Pick monthly, quarterly or yearly, and optionally an end date. [screenshot: the repeat dialog]
2. **The invoice page shows the schedule** — "Repeats monthly · next on 1 Nov · 3 sent so far" — with Pause and Stop. [screenshot: schedule banner]
3. **Each new invoice is created and sent automatically** on the schedule date, with the issue and due dates moved forward and the invoice number incremented. It appears in the invoice list like any other. [screenshot: list with the generated invoice]
4. **Pause** keeps the schedule but skips runs until you resume; **Stop** ends it. Either way, invoices already sent are unaffected.

**Background.** A retainer client pays the same amount on the same day each period. The invoice content doesn't change; only the dates and number do. That's the whole feature: copy the template invoice forward on a schedule.

## How it works

Three pieces:

- **`RecurringSchedule`** (new model) — belongs to the template invoice; holds `interval`, `next_run_on`, `ends_on`, `paused_at`. One schedule per invoice.
- **`RecurringInvoiceJob`** — runs daily at 06:00 UTC, finds schedules with `next_run_on <= today` and no `paused_at`, and for each one calls `Invoice#copy_forward(schedule)` then `InvoiceMailer.send_invoice`. Advances `next_run_on` by the interval inside the same transaction.
- **`Invoice#copy_forward`** — duplicates the line items and client, sets `issue_date` to the run date and `due_date` from the client's terms, takes the next invoice number from the existing sequence. The copy is a normal invoice with `recurring_schedule_id` set for traceability.

**Why a daily job instead of scheduling each invoice individually?** A daily sweep is idempotent and survives a missed run — if the job doesn't fire on the 1st, it sends on the 2nd rather than never. Per-invoice scheduled jobs would need reconciliation for the same cases.

**Why does Pause skip runs rather than shifting them?** A paused monthly invoice that resumes two months later should send for the current month, not send three catch-up invoices. `next_run_on` is recomputed from today on resume.

## Worth knowing

- Quarterly and yearly schedules on the 29th–31st clamp to the last day of shorter months. Monthly does the same. This matches how the existing due-date arithmetic already behaves.
- Editing a template invoice after the schedule exists changes future copies. That's intended, but there's no warning yet; PROJ-322 adds one.
- No proration, no per-run amount changes. A client whose retainer changes gets a new template invoice.

<details><summary><strong>All decisions</strong></summary>

- The schedule is a separate model rather than columns on `invoices`, so a template invoice stays an ordinary invoice and the schedule can be deleted without touching it.
- Generated invoices are sent immediately, not saved as drafts. The feature exists so no one has to remember; a draft would reintroduce the step it removes. A "review before sending" option was considered and left for a client to ask for it.
- The job runs at 06:00 UTC so invoices land in inboxes during European and US-East mornings. The hour is a constant, not a setting.

</details>

<details><summary><strong>In this PR</strong></summary>

- Add `RecurringSchedule` (interval, `next_run_on`, `ends_on`, `paused_at`) with a migration, one per invoice
- Add `RecurringInvoiceJob`, scheduled daily at 06:00 UTC, advancing `next_run_on` in the same transaction as the copy
- Add `Invoice#copy_forward(schedule)` and set `recurring_schedule_id` on the copy
- Add the Repeat dialog, the schedule banner with Pause and Stop, and the resume recompute
- Add 142 specs across the model, the job and the copy

</details>

<details><summary><strong>Verification</strong></summary>

- 142 new specs across the model, the job and the copy: intervals, month-end clamping, pause/resume, end dates, a missed day, and a template invoice that was deleted.
- On staging: created a monthly schedule with `next_run_on` set to today, ran the job, got one new invoice with the right number and dates and one email in the mail preview. Ran the job again: no second invoice.

</details>

<details><summary><strong>Post-deploy monitoring</strong></summary>

**Where to look.** `RecurringInvoiceJob` in Sidekiq; the `invoices.recurring_schedule_id IS NOT NULL` count.

**Healthy.** One job run per day, each generated invoice has a matching sent email, and no schedule has `next_run_on` in the past after a run.

**Failure signals.** A schedule with `next_run_on < today` and `paused_at IS NULL` after 06:30 UTC means the job skipped it. Two invoices with the same `recurring_schedule_id` and the same `issue_date` means a double run.

**Rollback.** Revert and disable the cron entry. Generated invoices are real invoices and stay; schedules stop advancing.

**Window.** The first two scheduled runs.

</details>
```

---

## Large feature

**Title:** `Client Portal`

```markdown
Clients can now sign in to a portal of their own and do the three things they currently email us for: **see every invoice and its status**, **pay an open invoice by card**, and **download a statement** for any date range. Before this, a client asking "what do I still owe you?" got a hand-built PDF two days later. The portal is read-only apart from paying; nothing a client does there changes an invoice's content.

Resolves PROJ-250

[video: a client signing in, paying an invoice, downloading a statement]

## What you can do now

### See your invoices

1. **A client receives a sign-in link by email** — no password. The link is valid for 15 minutes and signs them in for 30 days on that browser. [screenshot: sign-in email]
2. **The invoice list shows every invoice** for their account with status, amount and due date, open ones first. [screenshot: portal invoice list]
3. **Opening an invoice shows the same PDF they were emailed**, plus its payment history.

### Pay by card

1. **An open invoice has a Pay button.** It opens the card form; the amount is fixed to the invoice total. [screenshot: pay form]
2. **On success the invoice flips to Paid on the spot** and a receipt email goes out. Our side sees it as a card payment like any other. [screenshot: paid confirmation]
3. **A declined card shows the bank's reason** and leaves the invoice open. Nothing is retried automatically.

### Download a statement

1. **Pick a date range** (defaults to the current quarter) and choose Download. [screenshot: statement form]
2. **The statement lists every invoice and payment in the range** with a running balance, as a PDF named `statement-<client>-<from>-<to>.pdf`. Generation takes under two seconds for the largest client (1,400 rows).

**What is the same as before.** Invoices are still created, edited and sent from the staff app only. The portal cannot edit an invoice, dispute it, or change the client's details. Card payments made in the portal use the same Stripe account and the same `Payment` records as staff-entered card payments.

## How it fits together

| Layer | Sign-in | Invoices & statements | Payments |
|---|---|---|---|
| Routes | `/portal/sign_in`, `/portal/session` | `/portal/invoices`, `/portal/statements` | `/portal/invoices/:id/payment` |
| Controllers (`app/controllers/portal/`) | `SessionsController` — issues and redeems magic links | `InvoicesController`, `StatementsController` — read-only, scoped to `current_client` | `PaymentsController` — creates a Stripe PaymentIntent, confirms on webhook |
| Models | `ClientSession` (token, expiry, browser) | existing `Invoice`, `Payment`; new `Statement` (PDF builder, no table) | existing `Payment` |
| Views | `layouts/portal.html.erb` — separate layout, no staff nav | | |

Two boundaries hold it together:

- **One way in.** Every portal controller inherits from `Portal::BaseController`, whose `current_client` comes only from a `ClientSession`. There is no path from a staff session into the portal, and no portal controller reads `params[:client_id]`.
- **One write.** The portal never writes to `invoices`. The only write is `Payment` creation, and that happens in the Stripe webhook handler that staff card payments already use.

### Sign-in

A magic link is a `ClientSession` row with a random 32-byte token, `expires_at` 15 minutes out, and `redeemed_at` nil. Redeeming it sets `redeemed_at`, issues a signed cookie holding the session id, and extends `expires_at` to 30 days. A second click on the same link is refused. Sessions are revoked by deleting the row; the client settings page in the staff app lists active sessions with a Revoke button.

**Why magic links rather than passwords?** Clients sign in a few times a year. A password they will forget and reset each time is a worse experience than a link, and it removes password storage from the portal's threat model.

### Payments

The Pay button creates a Stripe PaymentIntent for the invoice total with `metadata.invoice_id`, and the card form uses Stripe Elements so card data never touches our servers. The invoice is marked paid only when the `payment_intent.succeeded` webhook arrives — the same handler staff payments use — so a client closing the tab mid-flow can't leave a half-recorded payment. The Pay button is disabled while an intent for that invoice is less than 10 minutes old, to stop double payments from a double click.

### Statements

`Statement.new(client, from, to)` loads invoices and payments in the range in two queries, merges them by date, and renders through the existing Prawn PDF layer. There is no table; a statement is generated on every request. At 1,400 rows it renders in 1.8 s; the largest real client has 610.

### Privacy

The portal shows a client only their own rows: every query goes through `current_client.invoices` or `current_client.payments`, and a request spec asserts that a signed-in client requesting another client's invoice id gets a 404, not a 403 (so ids can't be enumerated). Magic-link emails contain the link and nothing about the account.

## Worth knowing

- Partial payments are not supported; the amount is the invoice total. PROJ-260 covers it, and needs a decision on how partial payments show on statements.
- The portal is English-only. The staff app's locale switching is not wired in.
- Rate limiting on `/portal/sign_in` is 5 requests per email per hour, enforced in the controller. There is no global limit yet; PROJ-261.

<details><summary><strong>All decisions</strong></summary>

- Sessions are rows, not JWTs, so revocation is a delete and the staff app can list them. The cost is one query per portal request.
- The portal has its own layout and stylesheet rather than reusing the staff app's, so a staff redesign can't accidentally change what clients see. The shared pieces are the PDF layer and the models.
- Statements are generated per request rather than cached. The largest client renders in under two seconds; caching would need invalidation on every payment and is not worth it at this size.
- The `payment_intent.succeeded` handler was extended rather than duplicated: it now looks up the invoice by `metadata.invoice_id` when present and falls back to the existing staff-payment path when not.
- Clients are not told when a session is revoked. They see the sign-in page on their next visit.

</details>

<details><summary><strong>In this PR</strong></summary>

**Sign-in**
- Add `ClientSession` (token, `expires_at`, `redeemed_at`, browser) with `Portal::SessionsController` issuing and redeeming magic links
- Add the active-sessions list and Revoke button to the staff client settings page

**Invoices and statements**
- Add `Portal::BaseController` with `current_client` from the session cookie only
- Add `Portal::InvoicesController` and `Portal::StatementsController`, read-only, scoped through `current_client`
- Add `Statement` (PDF builder over the existing Prawn layer, no table)

**Payments**
- Add `Portal::PaymentsController` creating a Stripe PaymentIntent with `metadata.invoice_id`
- Extend the `payment_intent.succeeded` webhook handler to resolve the invoice from metadata
- Disable the Pay button while an intent under 10 minutes old exists

**Layout, rate limiting, tests**
- Add `layouts/portal.html.erb` and its stylesheet
- Rate-limit `/portal/sign_in` to 5 per email per hour
- Add 226 specs across sessions, controllers, payments and statements

</details>

<details><summary><strong>Verification</strong></summary>

- 226 new specs: 41 for sessions (expiry, single redemption, revocation, cookie tampering), 88 for the read-only controllers including cross-client isolation, 52 for payments against Stripe's test webhooks, 45 for statements including an empty range and a client with no invoices.
- On staging with Stripe test mode: signed in as a test client, paid a £120 invoice with the 4242 test card, saw it flip to Paid, received the receipt, downloaded a statement showing the payment. Paid with the "declined" test card: invoice stayed open with the decline reason shown.
- A staff session cannot reach any `/portal/*` route (redirects to portal sign-in), and a portal session cannot reach any staff route.

Staging walk, step by step:

| Step | Result |
|---|---|
| Sign-in link requested for `test-client@example.test` | email in mail preview, link redeemed in 4 s |
| Same link clicked again | "This link has already been used" |
| Pay invoice INV-1042, card 4242 | PaymentIntent `pi_3P…`, webhook received, invoice `paid` at 14:02:11 |
| Pay invoice INV-1043, card 0002 (decline) | "Your card was declined", invoice still `sent` |
| Statement 2026-07-01 to 2026-09-30 | 14 rows, closing balance £0.00, 0.6 s |
| Request `/portal/invoices/9001` (another client's) | 404 |

</details>

<details><summary><strong>Post-deploy monitoring</strong></summary>

**Where to look.** `portal_sign_ins`, `portal_payments`, `portal_statements` counters; Stripe dashboard filtered to `metadata.source = portal`; the Rails error tracker for `Portal::*` controllers.

**Healthy.** Sign-in links redeemed within minutes of being sent; every `portal_payments` increment has a matching `payment_intent.succeeded` webhook; no `Portal::*` exceptions.

**Failure signals.** A PaymentIntent succeeded in Stripe with no matching `Payment` row after five minutes means the webhook path broke. A spike in sign-in requests for one email means the rate limit is not holding. Any 200 on a cross-client invoice request is a data exposure and should be treated as an incident.

**Rollback.** Remove the `/portal` routes. Sessions and payments already made are ordinary rows and stay valid.

**Window.** The first ten client sign-ins, and the first real card payment.

</details>
```
