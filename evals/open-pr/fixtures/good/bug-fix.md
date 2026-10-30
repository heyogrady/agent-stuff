Opening an order with an empty coupon code showed an error page. Those orders now open, with no discount line.

Related: Sentry [WEB-4F](https://sentry.example.test/issues/1)

## What was wrong

- **What:** some orders showed an error page instead of the order.
- **Where:** the order page; `app/views/orders/_totals.html.erb:12` raised.
- **Cause:** an empty coupon code counted as a coupon.

## Summary

```diff
-  render DiscountLine(order.coupon)  if order.coupon
+  render DiscountLine(order.coupon)  if order.coupon.present?
```

## Evidence

- **Before:** `bundle exec rspec spec/requests/orders_spec.rb` failed, 2 examples, 1 failure.
- **After:** the same spec passes, 2 examples, 0 failures.

## Merge Danger

**Door:** two-way. One condition in one view; a revert restores the old page.

**Blast Radius:** tiny. Only the totals block on the order page.

## Potential follow-ups

Found while fixing this. None of it is in this PR.

| Urgency | Finding | Where | Why it matters | How sure | Next step |
|---|---|---|---|---|---|
| Do soon | **Receipts may draw the same line** | `app/pdfs/receipt.rb` | A blank coupon could break a receipt. | Suspected | Reproduce, then fix |

<details><summary><strong>In this PR</strong></summary>

- Guard the discount line with `coupon.present?`

</details>
