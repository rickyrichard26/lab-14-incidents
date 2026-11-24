# Runbook: CheckoutFastBurn / CheckoutSlowBurn

**SLO:** 99.5 % of checkouts succeed over 30 days. Error budget: 0.5 % = 216 minutes of "fully down".
**Burn rate** = checkout error ratio / 0.005.

| Alert | Condition | Severity | Meaning |
|---|---|---|---|
| CheckoutFastBurn | burn > 14.4 over 1h **and** 5m | page | 2 % of the monthly budget gone per hour: act now |
| CheckoutSlowBurn | burn > 6 over 6h **and** 30m | ticket | 5 % of the budget gone in 6 hours: look today |

## First 5 minutes
1. Which service returns the errors? `sum by (job, route, status) (rate(http_requests_total{status=~"5.."}[5m]))`
2. Is it one card type or all? `sum by (card) (count_over_time({service="payments"} | json | status >= 500 [10m]))`
3. What is the error message? `{service="payments"} | json | level="ERROR" | msg != "request"`
4. Did something change? Check the last deploy of payments (`version` field in the logs).

## Mitigation
- A recent payments deploy is the usual cause: roll back with `docker compose up -d payments` (back to 1.0.0).
- Payments down (TargetDown firing)? Start it: `docker compose start payments`.

## After
Check that the 5m burn rate goes back to 0, then write a short blameless note.
