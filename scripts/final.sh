#!/usr/bin/env bash
# Final Challenge: reproduces the night. Takes about 22 minutes. Run it from the repo root.
set -e
log() { echo "$(date -u +%FT%TZ) $*" | tee -a events.log; }

log "START deploy payments 1.1.0"
PAYMENTS_VERSION=1.1.0 docker compose up -d payments
sleep 900                                  # 15 minutes of errors
log "OUTAGE docker compose stop payments"
docker compose stop payments
sleep 120                                  # 2 minutes down
log "RECOVER docker compose start payments (still 1.1.0)"
docker compose start payments
sleep 300                                  # 5 minutes
log "ROLLBACK payments 1.0.0"
docker compose up -d payments
log "DONE (wait 2-3 more minutes, then collect the evidence)"
