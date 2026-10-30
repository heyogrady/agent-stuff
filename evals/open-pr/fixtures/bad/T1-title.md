Invoices can now repeat on a schedule. A client on a monthly retainer gets the same invoice on the first of each month without anyone creating it.

Resolves [PROJ-41](https://linear.app/acme/issue/PROJ-41)

## What you can do now

1. Open an invoice and choose **Repeat**.
2. Pick monthly or weekly, and a start date.
3. The invoice goes out on that schedule until you pause it.

## How it works

A daily job finds schedules due today and copies their invoice. Pausing skips runs rather than shifting them, so the dates stay predictable.

<details><summary><strong>In this PR</strong></summary>

- Add `InvoiceSchedule` and the daily `RepeatInvoicesJob`
- Add the Repeat menu to the invoice page

</details>

<details><summary><strong>Verification</strong></summary>

- 38 new specs pass, including a paused schedule and a month with 28 days.

</details>
