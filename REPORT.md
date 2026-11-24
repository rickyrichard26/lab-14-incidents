# REPORT: Lab 14 (Variant A)

Name: Richard (Ricky Richard Takahindangen), Student ID: 78831

Variant A: Tasks 1 to 5 and the Final Challenge. Screenshots are in `screenshots/`.


## Part 0. Setup (ShopLab stack)

Run all commands in the Ubuntu terminal inside the lab14-incidents folder. Open the web pages in the browser inside the same VM.


### 0.1 Check Docker and Docker Compose

```bash
docker --version
docker compose version
```

If "docker compose" is not found on Ubuntu: sudo apt install -y docker-compose-v2. The VM needs about 4 GB RAM for 9 containers.


![docker --version and docker compose version](screenshots/s0-1.png)


### 0.2 Unpack the project

```bash
cd ~
unzip ~/Downloads/lab14-incidents.zip
cd lab14-incidents
find . -type f | sort
```

The zip contains the starter stack from the assignment plus final configs in solutions/.


![file list of lab14-incidents](screenshots/s0-2.png)


### 0.3 Start the stack

```bash
docker compose up -d --build
docker compose ps
```

Expected: 9 services, all Up (shop, payments, traffic, prometheus, alertmanager, webhook, loki, alloy, grafana). The first build needs internet and a few minutes.


![docker compose ps showing 9 services Up](screenshots/s0-3.png)


### 0.4 Write down the start time (UTC)

```bash
echo "$(date -u +%FT%TZ) stack started, payments 1.0.0, starter config" | tee -a events.log
```

Keep adding a line to events.log for every deploy, rollback and config change. You need these times for Task 2, Task 3 and the postmortem.


![events.log first line](screenshots/s0-4.png)


### 0.5 Check Prometheus targets

Open http://localhost:9090/targets: shop and payments must be UP.


![Prometheus Targets page, shop and payments UP](screenshots/s0-5.png)


### 0.6 Check logs in Grafana

Open http://localhost:3000, Explore, choose Loki, run {service="shop"}. You should see JSON log lines.


![Grafana Explore with Loki logs of shop](screenshots/s0-6.png)


### 0.7 Watch the webhook

```bash
docker compose logs -f webhook
```

This is where alert notifications appear (leave it in a second terminal). Stop with Ctrl+C.


![webhook output with starter ErrorsDetected notifications](screenshots/s0-7.png)


## Task 1. "Search is slow"

Keep payments on 1.0.0. Wait at least 10 minutes after the start so the graphs have data. Use Prometheus (http://localhost:9090/graph, Graph tab, 15m) for PromQL and Grafana Explore (Loki) for LogQL.


### 1.1 p50 per route

```promql
histogram_quantile(0.5, sum by (route, le) (rate(http_request_duration_seconds_bucket{job="shop"}[5m])))
```

Expected: /api/search about 0.04 s. The median hides the problem.


![p50 graph per route](screenshots/s1-1.png)


### 1.2 p95 per route

```promql
histogram_quantile(0.95, sum by (route, le) (rate(http_request_duration_seconds_bucket{job="shop"}[5m])))
```

Expected: /api/search p95 close to 1 s, because about 8 % of searches are slow (more than the 5 % the p95 looks at).


![p95 graph per route](screenshots/s1-2.png)


### 1.3 Average per route

```promql
sum by (route) (rate(http_request_duration_seconds_sum{job="shop"}[5m]))
/ sum by (route) (rate(http_request_duration_seconds_count{job="shop"}[5m]))
```

Expected: about 0.1 to 0.13 s for /api/search, which looks harmless.


![average latency graph per route](screenshots/s1-3.png)


### 1.4 Share of searches slower than 0.5 s

```promql
1 - (
  sum(rate(http_request_duration_seconds_bucket{job="shop",route="/api/search",le="0.5"}[5m]))
  / sum(rate(http_request_duration_seconds_count{job="shop",route="/api/search"}[5m]))
)
```

Expected: about 0.08 (8 %).


![share of slow searches (about 8 %)](screenshots/s1-4.png)


### 1.5 Slow searches in the logs

```logql
{service="shop"} | json | path="/api/search" and duration_ms > 500
```

Run in Grafana Explore (Loki).


![LogQL list of slow searches](screenshots/s1-5.png)


### 1.6 Duration and query text

```logql
{service="shop"} | json | path="/api/search" and duration_ms > 500 | line_format "{{.duration_ms}}ms q={{.query}}"
```

Pattern: every slow search has a long query, six words, more than 20 characters (the code path in /api/search is a black box for now; you only describe the pattern).


![slow searches with duration and query text](screenshots/s1-6.png)


### 1.7 Bonus: prove the pattern with LogQL metrics

```logql
sum by (long) (count_over_time({service="shop"} | json | path="/api/search" | label_format long=`{{ if gt (len .query) 20 }}yes{{ else }}no{{ end }}` [5m]))

avg by (long) (avg_over_time({service="shop"} | json | path="/api/search" | label_format long=`{{ if gt (len .query) 20 }}yes{{ else }}no{{ end }}` | unwrap duration_ms [5m]))
```

Expected: long=yes averages about 1100 ms, long=no about 40 ms. Run the two queries one after the other.


![count and average duration split by long=yes/no](screenshots/s1-7.png)


### Explain


**Why does the average look fine while some users wait more than a second?**

About 8 % of searches (the ones with six words, a query longer than 20 characters) take about one second longer, and the other 92 % take about 40 ms. The average mixes both groups, so it stays near 0.1 s and looks harmless. The p50 only describes the typical user. The p95 sits inside the slow group, because the slow group is bigger than 5 % of the requests, so it shows about 1 s. Averages hide the tail; percentiles from histograms show it. (Replace with your numbers: p50 = ___, p95 = ___, average = ___, slow share = ___ %.)


**Why do you need both metrics and logs to answer "why"?**

Metrics are cheap aggregates: they tell me where (route /api/search), when and how big (p95 about 1 s, 8 % of requests), but they cannot hold per-request details like the query text because every value would become a new time series. Logs keep one line per request with duration_ms and query, so I can see what the slow requests have in common. Metrics find the problem, logs explain it.


## Task 3 (before). The noisy alert with the starter config

Do this part second (right after Task 1), while the starter rules.yml and alertmanager.yml are still active. It takes 30 minutes. The "after" part is later in this report, in Task 3 (after).


### 3.1 Start the measurement

```bash
echo "$(date -u +%FT%TZ) BEFORE-run start: payments 1.0.0, starter config" | tee -a events.log
```

Payments is already on 1.0.0. Wait 15 minutes from this moment.


![events.log line for the start](screenshots/s3-1.png)


### 3.2 Count notifications after 15 min on 1.0.0

```bash
docker compose logs --since 15m webhook | grep -c FIRING
docker compose logs --since 15m webhook | tail -15
```

Write the number in the table below. They are all ErrorsDetected, even though nothing is really wrong.


![count and sample of notifications on 1.0.0](screenshots/s3-2.png)


### 3.3 Deploy payments 1.1.0

```bash
PAYMENTS_VERSION=1.1.0 docker compose up -d payments
echo "$(date -u +%FT%TZ) BEFORE-run: deploy payments 1.1.0" | tee -a events.log
```

Wait 15 minutes. Use this time for Task 4 (it needs failing checkouts).


![deploy command and events.log](screenshots/s3-3.png)


### 3.4 Count notifications after 15 min on 1.1.0

```bash
docker compose logs --since 15m webhook | grep -c FIRING
docker compose logs --since 15m webhook | tail -15
```


![count and sample of notifications on 1.1.0](screenshots/s3-4.png)


### 3.5 Roll back before the next run

```bash
docker compose up -d payments
echo "$(date -u +%FT%TZ) BEFORE-run: rollback to 1.0.0" | tee -a events.log
```

Which of the notifications needed a human? The real incident is checkout failing because payments returns 500 (ErrorsDetected for /api/pay and for /api/checkout, 2 alerts about the same problem). The /api/search 500s (about 0.5 % random errors) never needed a human.


![rollback command](screenshots/s3-5.png)


## Task 2. An SLO for checkout and a burn-rate alert

Do these steps after the "before" measurement of Task 3. The final rules are in solutions/rules.yml.


### 2.1 Error budget in minutes

```bash
python3 -c "print(30*24*60, 'minutes in 30 days'); print(30*24*60*0.005, 'minutes of full outage allowed (0.5 %)')"
```

30 days = 43,200 minutes, 0.5 % of it = 216 minutes. Write this in the report.


![error budget calculation = 216 minutes](screenshots/s2-1.png)


### 2.2 Install the final rules

```bash
sed -i "s/YOUR-GITHUB-USER/rickyrichard26/" solutions/rules.yml
cp solutions/rules.yml monitoring/rules.yml
docker run --rm -v "$PWD/monitoring:/m" --entrypoint promtool prom/prometheus:v3.16.0 check rules /m/rules.yml
curl -X POST localhost:9090/-/reload
echo "$(date -u +%FT%TZ) final rules installed" | tee -a events.log
```

Use cp (not sed -i or an editor) on files inside monitoring/: they are mounted into the containers as single files, and cp keeps the file the container sees. promtool must say SUCCESS with the number of rules.


![promtool check rules: SUCCESS](screenshots/s2-2.png)


### 2.3 Show the recording rules and alerts

In Prometheus open Status, Rules. You should see 4 recording rules (checkout:error_ratio:rate5m, 30m, 1h, 6h) and the alerts CheckoutFastBurn (page) and CheckoutSlowBurn (ticket), each with two windows, a summary and a runbook_url. Also show the file: cat monitoring/rules.yml


![Prometheus Status, Rules page](screenshots/s2-3.png)


### 2.4 Runbook

```bash
cat runbooks/checkout-slo.md
```


![runbook checkout-slo.md](screenshots/s2-4.png)


### 2.5 Reset Prometheus history (recommended)

```bash
docker compose up -d --force-recreate prometheus
```

The BEFORE-run errors would still sit in the 1h and 6h windows and distort the burn rate. This wipes the Prometheus data (it has no volume) and loads the new rules. Then wait 15 minutes with payments on 1.0.0: this is also the first half of Task 3 (after).


![recreate command](screenshots/s2-5.png)


### 2.6 Deploy payments 1.1.0 and leave it 50 to 55 minutes

```bash
PAYMENTS_VERSION=1.1.0 docker compose up -d payments
echo "$(date -u +%FT%TZ) AFTER-run: deploy payments 1.1.0" | tee -a events.log
```

The 5m error ratio jumps to about 10 % at once (unionpay is 1 card in 10), which is a burn rate of about 20. The 1h window needs about 40 minutes to climb above 7.2 % (14.4 x 0.5 %), so the fast burn alert is NOT immediate.


![deploy command and events.log](screenshots/s2-6.png)


### 2.7 Burn rate over time

```promql
checkout:error_ratio:rate5m / 0.005
checkout:error_ratio:rate1h / 0.005
checkout:error_ratio:rate6h / 0.005
```

Take a graph at about +5, +20 and +45 minutes (Graph tab, 1h range). Run the three lines as separate queries or with the + Add query button.


![burn rates at about +5, +20 and +45 min](screenshots/s2-7.png)


### 2.8 Which alert fired, when, and the burn rate then

```promql
ALERTS{alertname=~"Checkout.*"}
checkout:error_ratio:rate1h / 0.005
```

Also: docker compose logs -t webhook | grep Checkout. The /pager line gives the time of the notification. Read the burn rate from the graph at that time. Expected: CheckoutFastBurn fires about 40 to 50 minutes after the deploy. CheckoutSlowBurn needs the 6h window above 3 %, which takes about 2 hours at 10 % errors, so it is not expected within this run.


![ALERTS in Prometheus and webhook /pager line](screenshots/s2-8.png)


### Explain


**Why alert on the burn rate instead of "error ratio > 0.5 %"?**

The SLO allows 0.5 % errors on average over 30 days, so a short blip above 0.5 % is normal and uses almost no budget; alerting on it would page for nothing. The burn rate says how fast the budget is being used: 14.4x for one hour burns 2 % of the monthly budget (14.4 / 720), 6x for six hours burns 5 %. So the alert is proportional to the danger, and the severity (page or ticket) follows from how fast the budget goes.


**Why two windows per alert?**

The long window (1h or 6h) proves the problem is big enough to matter and not just a spike. The short window (5m or 30m) proves it is still happening now, so the alert resolves quickly after the fix instead of staying red for an hour. Both must be true.


**Why did (or didn't) the fast-burn alert fire soon after the deploy, although the error ratio jumped at once?**

It did not fire at once. The 5m ratio jumped to about 10 % immediately (burn rate about 20), but the 1h window is an average of the last hour, mostly good traffic at first. With about 10 % errors it takes roughly 40 minutes before the 1h ratio passes 7.2 % (14.4 x 0.5 %). Only then are both windows above 14.4x. (Replace with your measured values: deploy at ___, alert at ___, burn rate then ___.) This is the price of the long window: fewer false pages, slower detection of a medium-size problem.


## Task 3 (after). Fixed alerting and the comparison table

Same 30 minutes again, now with the fixed rules (HighErrorRatio replaces ErrorsDetected) and the fixed alertmanager.yml. The 1.1.0 part is the same deploy as in Task 2 (step 2.6).


### 3.6 Show the new alert

```bash
cat monitoring/rules.yml | sed -n "/service-errors/,\$p"
```

HighErrorRatio: a ratio (more than 2 % 5xx), a minimum of traffic (more than 0.2 req/s), for: 2m, per job, a summary with the number and a runbook_url. cat runbooks/high-error-ratio.md too.


![HighErrorRatio rule](screenshots/s3-6.png)


### 3.7 Install the fixed Alertmanager config

```bash
cp solutions/alertmanager.yml monitoring/alertmanager.yml
docker run --rm -v "$PWD/monitoring:/m" --entrypoint amtool prom/alertmanager:v0.35.0 check-config /m/alertmanager.yml
curl -X POST localhost:9093/-/reload
echo "$(date -u +%FT%TZ) fixed alertmanager.yml installed" | tee -a events.log
```

group_by [alertname, job], group_wait 30s, group_interval 5m, repeat_interval 4h, page alerts go to /pager and the rest to /tickets. amtool must say SUCCESS. Do this before step 2.5 so the 15 minutes on 1.0.0 already use the new config.


![amtool check-config result](screenshots/s3-7.png)


### 3.8 Count after 15 min on 1.0.0

```bash
docker compose logs --since 15m webhook | grep -c FIRING
```

Taken at the end of the 15 minutes before the 1.1.0 deploy (see step 2.5). Expected: 0.


![count on 1.0.0 with the new config](screenshots/s3-8.png)


### 3.9 Count after 15 min on 1.1.0

```bash
docker compose logs --since 15m webhook | grep -c FIRING
docker compose logs --since 15m webhook | grep FIRING
```

Taken 15 minutes after the deploy in step 2.6 (not at the end of the 50 minutes). Expect HighErrorRatio for payments and for shop, each once.


![count and notifications on 1.1.0 with the new config](screenshots/s3-9.png)


### 3.10 Before / after table

Fill in the numbers from your steps 3.2, 3.4, 3.8 and 3.9.

|  | Starter config | Fixed config |
|---|---|---|
| 15 min on 1.0.0: FIRING notifications | ___ | ___ |
| 15 min on 1.1.0: FIRING notifications | ___ | ___ |
| Total | ___ | ___ |
| Notifications that needed a human | ___ | ___ |
| Repeats of the same problem | every minute | at most every 4 h (1 h for pages) |


### Explain


**What is alert fatigue and why is it dangerous?**

Alert fatigue is when people get so many alerts that are not important that they stop reading them, mute the channel or answer slowly. It is dangerous because the one alert that matters is lost in the noise, so real incidents are detected late (or by customers).


**What makes an alert actionable?**

It signals real or imminent user impact, needs a human now (not something that fixes itself), says in the summary what is wrong with a number, is routed to the right place by severity, fires rarely, and has a runbook_url with the first steps. If the person who receives it cannot do anything, it should not exist.


**Why does a single 500 on /api/search not deserve a page?**

The app returns random 500s on about 0.5 % of searches. One error is normal background noise, retrying works, no customer is blocked and nobody can act on it. It is already covered by the SLO and by HighErrorRatio, which only fires for a sustained ratio.


## Task 4. Follow one checkout across two services

Needs payments 1.1.0 running (failing checkouts exist). Do it while 1.1.0 is deployed, for example during step 3.3 or 2.6. Use Grafana Explore, Loki.


### 4.1 Find a failing checkout in the shop logs

```logql
{service="shop"} | json | status=502
```

Click one line and copy its request_id (a 16-character hex value).


![shop logs with status 502, request_id visible](screenshots/s4-1.png)


### 4.2 All lines of that request from both services

```logql
{service=~"shop|payments"} |= "PASTE-THE-REQUEST-ID-HERE"
```

Replace the placeholder with the copied ID. Expected: 3 lines: the shop request line (502), the payments ERROR line (currency KZT not supported) and the payments request line (500).


![three lines of one request from shop and payments](screenshots/s4-2.png)


### 4.3 Make your own request with a chosen ID

```bash
curl -si -X POST localhost:8000/api/checkout -H 'X-Request-ID: lab-richard-1' \
  -H 'Content-Type: application/json' \
  -d '{"card":"unionpay","amount":1000,"card_number":"4000000000000000"}'
```

Expected: HTTP 502 and the header X-Request-ID: lab-richard-1.


![curl response with 502 and X-Request-ID](screenshots/s4-3.png)


### 4.4 Find your own request in Loki

```logql
{service=~"shop|payments"} |= "lab-richard-1"
```

Wait 10 seconds for the logs to arrive.


![your own request in both services](screenshots/s4-4.png)


### 4.5 Show where the ID is passed on

```bash
grep -n "X-Request-ID" app/app.py
```

Two lines matter: in before_request (g.request_id = request.headers.get("X-Request-ID") or uuid4) and in checkout() (the header "X-Request-ID": g.request_id sent to payments, marked "pass it on!").


![grep output with the X-Request-ID lines](screenshots/s4-5.png)


### Explain


**What would break if the line that passes the ID on were missing?**

payments would not receive X-Request-ID, so before_request would create its own random ID. The shop line and the payments lines would have different request_ids and could not be connected: I could not tell which payments error belongs to which customer checkout.


**Why is service a Loki label but request_id is not?**

Loki indexes only labels, so labels must have few values. service has a handful of values (shop, payments, ...), but request_id is unique for every request. That would create millions of streams and a huge index, which makes Loki slow and expensive. request_id is found at query time with a line filter (|= "id") or | json instead.


**How does a request_id turn logs from two services into one story? What would a trace add?**

Every service logs the same ID, so one search returns all lines of that request in time order across services. A trace adds the structure and timing: the tree of spans (shop checkout calls payments pay), how long each hop took and where the time or the error is, without searching by hand.


## Task 5. The dashboard, as code

The dashboard is already in dashboards/shoplab.json and is provisioned by Grafana automatically. Open it while the incident is running (payments 1.1.0), so the panels show data.


### 5.1 Check the JSON file

```bash
python3 -m json.tool dashboards/shoplab.json > /dev/null && echo "valid JSON"
grep -E '"title"|"unit"' dashboards/shoplab.json
```

Panels: request rate (reqps), 5xx ratio by service (percentunit), p95 per route (s), checkout burn rate with threshold lines at 6 and 14.4, logs panel with errors from both services. All y axes start at 0.


![JSON valid and the panel titles and units](screenshots/s5-1.png)


### 5.2 Open the dashboard

Grafana (http://localhost:3000), Dashboards, folder lab14, ShopLab — RED. Take a screenshot of the whole dashboard during the incident. If a panel looks wrong, you can fix it in the UI and export it again (Share, Export, Export as JSON, save into dashboards/shoplab.json).


![ShopLab RED dashboard during the incident](screenshots/s5-2.png)


### 5.3 Show the burn-rate panel

Zoom on "Checkout error budget: burn rate" with the threshold lines at 6 and 14.4.


![burn rate panel with threshold lines](screenshots/s5-3.png)


### 5.4 Prove it loads by itself

```bash
docker compose down && docker compose up -d
sleep 60
docker compose ps
```

Do this at the end of Task 2/3 (it deletes Prometheus and Loki data). Then open Grafana again: the dashboard must be there without any manual import.


![dashboard present after down and up](screenshots/s5-4.png)


### 5.5 Keep it in git

```bash
git add dashboards/shoplab.json
git status --short
```

Commit it with the rest at the end.


![git status with dashboards/shoplab.json](screenshots/s5-5.png)


### Explain


**Why keep dashboards in git instead of only in Grafana?**

Git gives history, review and rollback, and the same dashboard can be recreated anywhere (docker compose down and up brings it back). A dashboard that exists only in the Grafana database is lost with the container, changes silently and cannot be reviewed.


**Who is each row of your dashboard for?**

The top row (rate, 5xx ratio, p95: the RED method) is for the on-call engineer and the service owner: are users being served right now? The bottom row is for the SRE and the engineer: the burn rate panel shows if the SLO and the error budget are at risk, and the logs panel is for the engineer who then looks for the cause.


## Final Challenge. Reproduce the night and write the postmortem

Start from a clean stack so the numbers are not mixed with earlier runs. Do the earlier tasks (and their screenshots) first. The whole run takes about 22 minutes plus 10 minutes of normal traffic before it.


### F.1 Clean start

```bash
docker compose down
docker compose up -d --build
sleep 600
docker compose ps
rm -f events.log
```

Wait 10 minutes of normal traffic (payments 1.0.0). The final rules and Alertmanager config must be the ones in monitoring/ now.


![docker compose ps after the clean start](screenshots/sF-1.png)


### F.2 Run the incident

```bash
./scripts/final.sh
```

Deploys 1.1.0, waits 15 minutes, stops payments for 2 minutes, starts it, waits 5 minutes, rolls back. It writes every step with a UTC time into events.log. Keep the terminal open (or use tmux/screen).


![final.sh output with the times](screenshots/sF-2.png)


### F.3 Collect the times

```bash
cat events.log
docker compose logs -t webhook | grep -E "FIRING|RESOLVED"
```

Wait 2 to 3 minutes after the rollback so RESOLVED lines appear.


![events.log and the webhook log with timestamps](screenshots/sF-3.png)


### F.4 Impact: failed checkouts

```promql
sum(increase(http_requests_total{job="shop",route="/api/checkout",status="502"}[30m]))
sum(increase(http_requests_total{job="shop",route="/api/checkout"}[30m]))
```

Evaluate right after the rollback (use a range that covers the whole incident; adjust [30m] to the real duration). Budget used = error ratio x duration in minutes, compared with 216 minutes.


![increase of failed and total checkouts](screenshots/sF-4.png)


### F.5 Alerts in Prometheus

```promql
ALERTS
ALERTS{alertname=~"Checkout.*"}
up{job="payments"}
```

Graph with a range that covers the incident. Note which alerts fired and when, and which did not.


![ALERTS graph during the incident](screenshots/sF-5.png)


### F.6 Logs: root cause and card numbers

```logql
{service="payments"} | json | level="ERROR" | msg != "request"
sum by (card) (count_over_time({service="payments"} | json | status >= 500 [30m]))
```

Expected: the message "currency KZT not supported by the new unionpay client" and all failures for card=unionpay.


![error message and failures by card](screenshots/sF-6.png)


### F.7 The restart

```promql
changes(process_start_time_seconds{job="payments"}[1h])
```

Shows the restart after the 2-minute outage (and the redeploys).


![changes(process_start_time_seconds) result](screenshots/sF-7.png)


### F.8 Write POSTMORTEM.md

```bash
nano POSTMORTEM.md
```

A template is already in the repo. Replace every TODO with your times, numbers and queries. Keep it blameless. At least 4 action items with owner and type (prevent, detect, mitigate).


![POSTMORTEM.md finished (first lines)](screenshots/sF-8.png)


## Submission and cleanup


### G.1 Put the screenshots into the repo

```bash
ls screenshots | head
git status --short
```

REPORT.md refers to screenshots/<id>.png (for example screenshots/s1-1.png). Use the ids shown in the red boxes of this Word file.


![screenshots folder and git status](screenshots/sG-1.png)


### G.2 Check for secrets and commit

```bash
git init -b main
git status
git add .
git commit -m "Lab 14: incidents, alerts, SLOs and logs (Variant A)"
```

No .env and no secrets must appear in git status.


![git status and commit](screenshots/sG-2.png)


### G.3 Push to the public repository

```bash
git remote add origin https://github.com/rickyrichard26/lab14-incidents.git
git push -u origin main
```

Create the empty public repository lab14-incidents on GitHub first (without README).


![git push result](screenshots/sG-3.png)


### G.4 Stop the stack

```bash
docker compose down
docker image rm shoplab-app:1
```


![docker compose down and image removed](screenshots/sG-4.png)
