# lab14-incidents (Variant A)

ShopLab: two services (shop, payments), a traffic generator, Prometheus, Alertmanager, Loki, Alloy and Grafana.

## Start
```
docker compose up -d --build
docker compose ps                 # 9 services Up
docker compose logs -f webhook    # notifications
```
Prometheus http://localhost:9090, Alertmanager http://localhost:9093, Grafana http://localhost:3000

## Release
```
PAYMENTS_VERSION=1.1.0 docker compose up -d payments   # deploy
docker compose up -d payments                          # roll back to 1.0.0
```

## Files
- `monitoring/rules.yml`, `monitoring/alertmanager.yml`: final rules and routing
- `dashboards/shoplab.json`: Grafana dashboard as code
- `runbooks/`: one per alert
- `REPORT.md`, `POSTMORTEM.md`: the report and the postmortem
