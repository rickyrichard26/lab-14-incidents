# Runbook: HighErrorRatio

A service answers more than 2 % of its requests with 5xx for 2 minutes (and has real traffic, more than 0.2 req/s).

1. Which service? The alert label `job` tells you (shop or payments).
2. Which route and status? `sum by (route, status) (rate(http_requests_total{status=~"5.."}[5m]))`
3. Look at the logs: `{service="<job>"} | json | level="ERROR"`
4. shop 502 + payments 500 together: the cause is in payments (shop only passes the error on).
5. Recent deploy? Roll back first, investigate after.

Severity is `ticket`: the page for customer impact comes from CheckoutFastBurn.
