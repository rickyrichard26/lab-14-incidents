# Runbook: TargetDown

Prometheus cannot scrape a service for 30 seconds.

1. `docker compose ps`: is the container Up?
2. `docker compose logs --tail 50 <service>`
3. `docker compose start <service>` (or `docker compose up -d <service>`)
4. While payments is down, checkout answers 502 ("payments unreachable") for every customer.
