# Performance Monitoring Stack

Docker-based monitoring stack for performance testing.

Intended for:

* k6 load testing
* Azure Container Jobs
* InfluxDB 1.8 metrics storage (InfluxQL)
* Grafana dashboards
* DigitalOcean Droplet deployment

The stack contains:

* InfluxDB 1.8
* Grafana 11.6
* Docker Compose deployment

---

# Architecture

```
Azure Container Job / local k6
        |
        | k6 metrics (write)
        v

DigitalOcean Droplet

  InfluxDB  :8086  <---- k6 writes here
      ^
      | InfluxQL (docker network)
      |
  Grafana   :3000  <---- you look here
```

No reverse proxy — both ports are published directly on the droplet.

---

# Requirements

## DigitalOcean

Recommended droplet:

* Ubuntu 24.04 LTS
* 1 CPU / 2 GB RAM minimum
* public IPv4 address

For larger dashboards:

* 2 CPU / 4 GB RAM

---

## Firewall

DigitalOcean Firewall:

Inbound:

| Port | Purpose  | Who needs it                    |
| ---- | -------- | ------------------------------- |
| 22   | SSH      | you                             |
| 3000 | Grafana  | you (your IP)                   |
| 8086 | InfluxDB | k6 runner / Azure Container Job |

InfluxDB has authentication enabled (see *InfluxDB authentication*), but traffic
runs over plain HTTP. Restrict source IPs wherever you can:

* `3000` — your IP only
* `8086` — only the IP range k6 runs from

---

# Installation

## 1. Connect to the server

```bash
ssh root@SERVER_IP
```

---

## 2. Clone the repository

```bash
git clone <repository-url>

cd perf_monitor
```

Or copy it over directly:

```bash
scp -r ./perf_monitor root@SERVER_IP:/opt/
```

---

## 3. Configuration

Create the environment file:

```bash
cp .env.example .env
```

Edit it:

```bash
nano .env
```

Example:

```env
GRAFANA_ROOT_URL=http://DROPLET_IP:3000

INFLUX_DB=k6
INFLUX_USERNAME=admin
INFLUX_PASSWORD=strong-password

GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=strong-password
```

Important:

* `GRAFANA_ROOT_URL` must contain the real droplet IP, otherwise Grafana breaks
  on redirects and generated links.
* `INFLUX_DB` is the database k6 writes into. It must match the last segment of
  the URL in `--out influxdb=...`.

Note: Compose only reads a file named `.env` — `.env.example` is just a
template. A variable missing from `.env` is substituted as an empty string with
a warning, not an error. Verify the rendered result with:

```bash
docker compose config
```

---

# Running

Make the scripts executable:

```bash
chmod +x *.sh
```

Run the installer:

```bash
./install.sh
```

The script:

* installs Docker
* enables the Docker service
* pulls the images
* creates the containers
* starts the monitoring stack

---

# Verification

Container status:

```bash
docker ps
```

Expected:

```
grafana
influxdb
```

Check that InfluxDB is up:

```bash
curl -i http://SERVER_IP:8086/ping
```

Expect `204 No Content`.

Check that the database exists (`/ping` needs no auth, `/query` does):

```bash
curl -G http://SERVER_IP:8086/query \
  -u admin:your-password \
  --data-urlencode "q=SHOW DATABASES"
```

Without `-u` you get `401 Unauthorized` — that is the expected behaviour.

Logs:

```bash
docker compose logs -f
```

---

# Access GRAFNA

Grafana (login from `.env`):

```
http://DROPLET_IP:3000
```

InfluxDB HTTP API (1.8 has no UI, API only):

```
http://DROPLET_IP:8086
```

---

# Grafana login

Use the values from `.env`:

```
username: admin
password: ********
```

## Create grafana datasource
Data Sources -> Add new datasource -> influxdb

name: influxdb
url: http://influxdb:8086
basic auth: on
database: k6

## Import k6 dashboard
Open dashboards and inport file: grafana\provisioning\dashboards\k6-dashboard.json

---

# InfluxDB configuration

InfluxDB 1.8 uses **databases** and **InfluxQL** — not the organizations,
buckets and Flux of 2.x. The database named by `INFLUX_DB` (default `k6`) is
created on the container's first start.

The Grafana datasource is provisioned automatically from
`grafana/provisioning/datasources/influxdb.yaml` — no API token involved.

---

# k6 configuration

This is the whole point of the stack: getting k6 metrics into InfluxDB.

InfluxDB requires authentication, so k6 must send credentials. Recommended way
(the password stays out of the command line and CI logs):

```bash
export K6_OUT: influxdb
export K6_INFLUXDB_ADDR: http://DROPLET_IP:8086
export K6_INFLUXDB_DB: k6
export K6_INFLUXDB_USERNAME: admin
export K6_INFLUXDB_PASSWORD: ${INFLUXDB_ADMIN_PASSWORD}
k6 run -e K6_INFLUXDB_USERNAME=admin -e K6_INFLUXDB_PASSWORD=your-password -e K6_OUT="influxdb=http://SERVER_IP:8086/k6" main.ts
```

Quick variant for a manual run — credentials in the URL:

```bash
k6 run --out influxdb=http://admin:your-password@SERVER_IP:8086/k6 main.ts
```

The last URL segment (`/k6`) is the **database name** and must match `INFLUX_DB`
in `.env`. If it does not match, k6 writes into a non-existent database and you
see nothing in Grafana — with no error message.

Watch the config precedence: k6 merges defaults → JSON → env → URL. If you set
credentials in both places, **the URL wins**.

## The `service` tag

The dashboard filters by the `service` tag. For the per-service panels to work,
k6 has to send it:

```js
export const options = {
  tags: {
    service: 'checkout-api',
  },
};
```

Or per request:

```js
http.get(url, { tags: { service: 'checkout-api' } });
```

Without this tag only the "Overview" panels will have data.

## Confirming the data arrived

After the test finishes:

```bash
curl -G http://SERVER_IP:8086/query \
  -u admin:your-password \
  --data-urlencode "db=k6" \
  --data-urlencode "q=SHOW MEASUREMENTS"
```

You should see `vus`, `http_reqs`, `http_req_duration`, `http_req_failed`, ...

---

# Azure Container Job

Store as secrets / environment variables:

```
K6_OUT                = influxdb=http://SERVER_IP:8086/k6
K6_INFLUXDB_USERNAME  = admin
K6_INFLUXDB_PASSWORD  = <secret>
```

```
Azure Container Job
        |
        | k6 metrics
        v

http://SERVER_IP:8086/k6
```

Note: Azure Container Jobs have variable outbound IPs, so pinning the firewall
to a single source address will not work. Either allow the relevant Azure range
on `8086`, or accept that InfluxDB authentication is the only control in front
of the write endpoint.

---

# Updating the stack

After an image change:

```bash
./update.sh
```

It runs:

* docker pull
* container restart
* removal of old images

---

# Backup

Run:

```bash
./backup.sh
```

Creates:

```
backups/

influx-data-v1-YYYY-MM-DD-HHMM.tar.gz
grafana-data-YYYY-MM-DD-HHMM.tar.gz
```

Contains:

* InfluxDB data
* Grafana configuration

---

# InfluxDB authentication

Authentication is **enabled** (`INFLUXDB_HTTP_AUTH_ENABLED: "true"`).

The admin user is created from `INFLUX_USERNAME` / `INFLUX_PASSWORD` during the
**first** initialization of the data volume. The Grafana datasource sends the
credentials automatically (it reads them from `.env`), so nothing to change
there.

## Careful: enabling auth on an existing volume

The admin user is only created during initial setup, when the volume is empty.
If you enable auth on a droplet where InfluxDB has already been running, the
user may not exist and every write starts returning `401`.

Check:

```bash
docker exec -it influxdb influx -execute "SHOW USERS"
```

If the list is empty, create the admin manually — InfluxDB 1.x allows this one
command without login precisely while no user exists yet:

```bash
docker exec -it influxdb influx -execute \
  "CREATE USER admin WITH PASSWORD 'your-password' WITH ALL PRIVILEGES"
```

On a clean droplet none of this applies — the volume is empty and the admin is
created automatically.

## Limitations

Traffic is still plain HTTP, so the password crosses the network in the clear.
Auth stops casual scanning and accidental writes, but not eavesdropping. If k6
runs from Azure over the public internet and that matters to you, put TLS
termination in front of InfluxDB.

Keep the firewall rules — auth supplements them, it does not replace them.

---

# k6 monitoring

The `k6 Performance Test` dashboard is provisioned automatically from
`grafana/provisioning/dashboards/` — find it in the `k6` folder in Grafana.

It contains:

* VU count
* throughput (req/s), overall and per service
* error rate
* p95 / p99 latency per service

---

# Maintenance

Disk space:

```bash
df -h
```

Docker usage:

```bash
docker system df
```

Logs:

```bash
docker compose logs --tail=100
```

---

# Lifecycle

For short-lived tests:

1. Create a droplet
2. Run install.sh
3. Run the performance tests
4. Export dashboards / data
5. Destroy the droplet

For long-term use:

* add a domain
* enable HTTPS
* set a retention policy in InfluxDB
* schedule regular backups

---

# Project goal

This stack provides a simple, repeatable environment for:

* performance testing
* load testing
* API monitoring
* FE performance monitoring
* k6 result analysis

Without depending on a local machine.

## Hints

cat >> ~/.bashrc <<'EOF'
# Land in the project directory on interactive login
if [[ $- == *i* ]] && [ -d /opt/perf_monitor ]; then
    cd /opt/perf_monitor
fi
EOF
