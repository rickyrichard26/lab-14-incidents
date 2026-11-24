# Postmortem: payments 1.1.0 release and outage

*Blameless: this explains how the system allowed the incident, not who caused it.*

## Summary
TODO three sentences: what was deployed, what broke for customers, how it was fixed.

## Impact
- Failed checkouts: TODO (PromQL: `sum(increase(http_requests_total{job="shop",route="/api/checkout",status="502"}[30m]))` evaluated at the end of the rollback)
- Total checkouts in the same window: TODO
- Duration: TODO minutes (from first error to rollback)
- Error ratio over the incident: TODO %. Budget used = ratio x duration = TODO minutes of the 216-minute (99.5 %, 30 days) budget = TODO %.

## Timeline (UTC)
| Time | Event | Evidence |
|---|---|---|
| TODO | Deploy payments 1.1.0 | events.log |
| TODO | First error | LogQL: `{service="payments"} | json | level="ERROR" | msg != "request"` |
| TODO | First alert | `docker compose logs -t webhook` |
| TODO | First useful alert (HighErrorRatio / CheckoutFastBurn) | webhook log, `ALERTS` in Prometheus |
| TODO | Outage: payments stopped, TargetDown | webhook /pager line, `up{job="payments"}` |
| TODO | Payments restarted | `changes(process_start_time_seconds{job="payments"}[1h])` |
| TODO | Rollback to 1.0.0 | events.log |
| TODO | Resolved | webhook RESOLVED lines, 5m error ratio back to 0 |

## Detection
TODO which alert told you first, which alerts were noise, how long after the first error.

## Root cause
TODO payments 1.1.0 fails for card=unionpay ("currency KZT not supported by the new unionpay client"); shop turns the 500 into 502. Add the queries that prove it (count by card, the ERROR message). Also: 1.1.0 logs the full card_number.

## What went well
- TODO

## What went badly
- TODO

## Action items
| # | Action | Owner | Type |
|---|---|---|---|
| 1 | TODO canary release of payments (5 % of traffic first) | me | prevent |
| 2 | TODO test for every card type before release | me | prevent |
| 3 | TODO page on CheckoutFastBurn with a shorter detection path | me | detect |
| 4 | TODO redact card numbers in logs | me | prevent |
| 5 | TODO one-command rollback documented in the runbook | me | mitigate |
