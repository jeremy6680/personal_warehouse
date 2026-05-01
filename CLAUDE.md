# CLAUDE.md — dbt Project Guidelines

This file provides context and instructions for Claude when working on dbt projects.
It covers conventions, architecture decisions, workflow rules, and code standards.

---

## Project Context

This is a **dbt Core** project following a **three-layer architecture** (staging / intermediate / mart).
The destination warehouse is **BigQuery** or **PostgreSQL (Supabase)** depending on the project.
For local development and portfolio projects, the mart layer may also run on **DuckDB**.
The project is part of the **Web2Data** portfolio, bridging web development expertise with analytics engineering.

---

## Stack

| Concern | Tool |
|---|---|
| Transformation | dbt Core |
| Warehouse (analytics) | BigQuery |
| Warehouse (operational / smaller projects) | PostgreSQL via Supabase |
| Query engine (local / portfolio) | DuckDB |
| Ingestion (primary) | Airbyte |
| Ingestion (fallback) | Fivetran |
| Orchestration | Apache Airflow |
| Language | SQL + Python (dbt macros, tests, scripts) |
| Version control | Git + BitBucket |
| Package manager | pip + `requirements.txt` |

---

## Adapter Notes

### BigQuery
- Use `{{ project_id }}.{{ dataset }}.{{ table }}` fully-qualified references when needed
- Partitioning and clustering are relevant for large mart tables — add `partition_by` and `cluster_by` in `config()` blocks when appropriate
- Use `TIMESTAMP` (not `DATETIME`) for UTC timestamps in BigQuery
- `QUALIFY` is supported natively in BigQuery — use it for deduplication

### PostgreSQL (Supabase)
- Use `merge` incremental strategy
- `QUALIFY` is **not** available — use a subquery with `ROW_NUMBER()` for deduplication

### DuckDB (local / portfolio)
- Use `delete+insert` incremental strategy
- `QUALIFY` is supported — preferred for deduplication
- No credentials needed — path-based connection in `profiles.yml`

When writing SQL, **default to standard SQL** that works across adapters unless the project explicitly targets a single warehouse. Flag adapter-specific syntax with a comment.

---

## Repository Structure

```
project/
├── analyses/               # Ad-hoc SQL analyses (not materialized)
├── data/                   # Raw CSV files loaded externally (bq load, scripts, Airbyte)
│                           # dbt does NOT manage these — BigQuery/Postgres is the source of truth
├── dbt_packages/           # Installed dbt packages (git-ignored)
├── logs/                   # dbt logs (git-ignored)
├── macros/                 # Reusable Jinja macros
│   └── tests/              # Custom generic test macros
├── models/
│   ├── staging/            # Raw source data, cleaned and typed — one model per source table
│   │   └── _staging__sources.yml
│   ├── intermediate/       # Cross-source joins and inter-domain transformations
│   │   └── _intermediate__models.yml
│   └── mart/               # Business-ready, self-service models (aggregated and enriched)
│       └── _mart__models.yml
├── seeds/                  # Small, static, manually-maintained reference CSVs (dbt-managed)
├── snapshots/              # SCD Type 2 snapshots
├── target/                 # Compiled artifacts (git-ignored)
├── tests/                  # Singular (one-off) data tests
├── .sqlfluff               # SQL linting configuration
├── dbt_project.yml         # Project configuration
├── packages.yml            # dbt package dependencies
├── profiles.yml            # Connection profiles (NOT committed — use env vars)
├── CLAUDE.md               # This file
├── CONTEXT.md              # Project overview and goals
├── DECISIONS.md            # Architecture and technical decisions log
├── NEXT_STEPS.md           # Current priorities and next tasks
└── STRUCTURE.md            # Folder/file structure explained
```

---

## `data/` vs `seeds/` — Critical Distinction

These two folders serve very different purposes. Never confuse them.

### `seeds/` — dbt-managed static reference data
- dbt loads these CSVs automatically with `dbt seed`
- For **small, static, manually-maintained** tables only
- Examples: country codes, category labels, league name mappings, hardcoded thresholds
- dbt is responsible for loading and versioning this data
- Appropriate when: the data rarely changes, fits in a spreadsheet, and a data engineer would never ETL it

### `data/` — externally-loaded source CSVs
- dbt does **nothing** with files in this folder
- Loaded externally via `bq load`, a Python script, Airbyte, or another pipeline
- The warehouse (BigQuery or Postgres) becomes the source of truth
- Declared in `_staging__sources.yml` and referenced via `source()` in staging models
- Appropriate when: the CSV comes from an external system, may be large, or could be replaced by an API in the future

**Rule of thumb:** if a data engineer would ever ETL it, it belongs in `data/` (or directly in the warehouse), not in `seeds/`.

---

## Ingestion

Data arrives in the warehouse via:

- **Airbyte** (primary) — self-hosted on Hetzner via Coolify; covers most connectors (APIs, databases, files)
- **Fivetran** (fallback) — used when a connector is unavailable in Airbyte, or when a client mandates it
- **Custom scripts** — for APIs without an Airbyte connector (e.g., API-Sports via a Python pipeline)
- **`bq load` / `psql COPY`** — for loading files from `data/` into the warehouse

All ingested data lands in a **raw schema** (e.g., `raw` or `airbyte_raw`) and is referenced in staging via `source()` declarations. dbt never touches raw data directly — it only reads from it.

---

## Three-Layer Architecture

### Staging Layer (`models/staging/`)

- **Purpose:** Recover raw source data and clean it. One staging model per source table.
- **Materialization:** `view` by default (or `table` if the source is slow or external)
- **File prefix:** `stg_`
- **Naming:** `stg_<source>__<entity>.sql` (e.g., `stg_api_sports__fixtures.sql`)
- **Rules:**
  - Single source per model — no joins between tables
  - Rename columns to `snake_case`
  - Cast types (strings to `DATE`, `TIMESTAMP`, `INTEGER`, etc.)
  - Handle obvious nulls and trim whitespace
  - Deduplicate if the source contains duplicates
    - BigQuery / DuckDB: use `QUALIFY ROW_NUMBER() OVER (...) = 1`
    - PostgreSQL: use a subquery with `ROW_NUMBER()`
  - Add `_loaded_at` metadata column when available from the source
  - No business logic — this layer is purely about making raw data usable

### Intermediate Layer (`models/intermediate/`)

- **Purpose:** Cross-source transformations — joins between tables from different sources or domains.
- **Materialization:** `view` by default (use `table` or `incremental` only if performance requires)
- **File prefix:** `int_`
- **Naming:** `int_<domain>__<description>.sql` (e.g., `int_rugby__fixtures_with_teams.sql`)
- **Rules:**
  - Always built on top of staging models — never reference raw sources directly
  - This is where inter-source joins happen (e.g., joining fixtures with team metadata from a different source)
  - Light aggregations are acceptable but not the primary goal
  - Keep models focused: one logical join/enrichment per intermediate model
  - Document every join condition and its business rationale in the `.yml` description

### Mart Layer (`models/mart/`)

- **Purpose:** Final, self-service models ready for consumption — cleaned, aggregated, and enriched.
- **Materialization:** `table` (always — mart models are for dashboards and direct querying)
- **File prefix:** `mrt_`
- **Naming:** `mrt_<domain>__<entity>.sql` (e.g., `mrt_rugby__fixture_results.sql`)
- **Target warehouse:** BigQuery or PostgreSQL in production; DuckDB for local/portfolio projects
- **Rules:**
  - Always built on top of intermediate (or staging for simple, single-source cases)
  - Window functions, rolling averages, KPIs, and aggregations belong here
  - Must have full column-level documentation in the `.yml` file
  - Must have at least `not_null` + `unique` tests on primary keys
  - No raw source references — only `ref()` calls
  - For BigQuery mart tables: consider `partition_by` and `cluster_by` for tables expected to grow large

---

## Naming Conventions

### SQL files
- All filenames are lowercase with underscores
- **Staging:** `stg_<source>__<entity>.sql`
- **Intermediate:** `int_<domain>__<description>.sql`
- **Mart:** `mrt_<domain>__<entity>.sql`
- Double underscore `__` separates the source/domain from the entity name
- Examples:
  - `stg_garmin__activities.sql`
  - `stg_api_sports__fixtures.sql`
  - `int_rugby__fixtures_with_teams.sql`
  - `int_running__activities_with_segments.sql`
  - `mrt_rugby__fixture_results.sql`
  - `mrt_running__training_summary.sql`

### Columns
- `snake_case` everywhere
- Primary keys: `<entity>_id` (e.g., `fixture_id`, `activity_id`)
- Foreign keys: `<referenced_entity>_id`
- Boolean columns: prefix with `is_`, `has_`, `did_`
- Date columns: suffix with `_at` (timestamp) or `_date` (date only)
- Monetary columns: suffix with `_amount` and always note the currency in the description

### YAML files
- Sources file per layer: `_staging__sources.yml`
- Models file per layer (or grouped by domain): `_intermediate__models.yml`, `_mart__models.yml`
- Use `description` for every model and every column — no exceptions

### Macros
- Descriptive verb-noun names: `generate_surrogate_key`, `test_is_valid_email`
- Custom generic tests: prefix with `test_`

---

## SQL Style Guide

Follow these conventions in all `.sql` model files.

### Staging example

```sql
-- ============================================================
-- Model: stg_api_sports__fixtures
-- Layer: Staging
-- Description: Raw rugby fixtures from API-Sports, cleaned and typed.
--              Renames columns to snake_case, casts dates, deduplicates.
-- Source: api_sports.fixtures
-- Adapter note: QUALIFY used — works on BigQuery and DuckDB.
--               For PostgreSQL, replace with ROW_NUMBER() subquery.
-- ============================================================

WITH

source AS (
    SELECT * FROM {{ source('api_sports', 'fixtures') }}
),

renamed AS (
    SELECT
        fixture_id,
        league_id,
        season_year,
        -- Cast string date to proper UTC timestamp
        CAST(fixture_date AS TIMESTAMP)    AS fixture_at,
        home_team_id,
        away_team_id,
        home_score,
        away_score,
        status_short                       AS fixture_status,
        _loaded_at
    FROM source
),

deduplicated AS (
    SELECT *
    FROM renamed
    QUALIFY ROW_NUMBER() OVER (PARTITION BY fixture_id ORDER BY fixture_at DESC) = 1
)

SELECT * FROM deduplicated
```

### Intermediate example

```sql
-- ============================================================
-- Model: int_rugby__fixtures_with_teams
-- Layer: Intermediate
-- Description: Joins cleaned fixtures with home and away team details.
--              Combines stg_api_sports__fixtures and stg_api_sports__teams.
-- Dependencies: stg_api_sports__fixtures, stg_api_sports__teams
-- ============================================================

WITH

fixtures AS (
    SELECT * FROM {{ ref('stg_api_sports__fixtures') }}
),

teams AS (
    SELECT * FROM {{ ref('stg_api_sports__teams') }}
),

home_teams AS (
    SELECT
        team_id,
        team_name   AS home_team_name,
        team_logo   AS home_team_logo
    FROM teams
),

away_teams AS (
    SELECT
        team_id,
        team_name   AS away_team_name,
        team_logo   AS away_team_logo
    FROM teams
),

joined AS (
    SELECT
        f.fixture_id,
        f.league_id,
        f.season_year,
        f.fixture_at,
        f.fixture_status,
        f.home_team_id,
        ht.home_team_name,
        ht.home_team_logo,
        f.away_team_id,
        at.away_team_name,
        at.away_team_logo,
        f.home_score,
        f.away_score
    FROM fixtures        AS f
    LEFT JOIN home_teams AS ht ON f.home_team_id = ht.team_id
    LEFT JOIN away_teams AS at ON f.away_team_id = at.team_id
)

SELECT * FROM joined
```

### Mart example

```sql
-- ============================================================
-- Model: mrt_rugby__fixture_results
-- Layer: Mart
-- Description: Final fixture results table ready for self-service use.
--              Includes team names, scores, result labels and season context.
-- Dependencies: int_rugby__fixtures_with_teams
-- ============================================================

{{ config(
    materialized='table',
    -- BigQuery only: uncomment to enable partitioning and clustering
    -- partition_by={"field": "fixture_at", "data_type": "timestamp", "granularity": "day"},
    -- cluster_by=["league_id", "season_year"]
) }}

WITH

fixtures AS (
    SELECT * FROM {{ ref('int_rugby__fixtures_with_teams') }}
),

enriched AS (
    SELECT
        fixture_id,
        league_id,
        season_year,
        fixture_at,
        fixture_status,
        home_team_id,
        home_team_name,
        away_team_id,
        away_team_name,
        home_score,
        away_score,
        -- Derive result label from scores
        CASE
            WHEN home_score > away_score  THEN 'home_win'
            WHEN home_score < away_score  THEN 'away_win'
            WHEN home_score = away_score  THEN 'draw'
            ELSE                               'unknown'
        END                                AS result,
        -- Total points scored in the match
        COALESCE(home_score, 0)
            + COALESCE(away_score, 0)      AS total_points
    FROM fixtures
    WHERE fixture_status = 'FT'            -- Only include finished matches
)

SELECT * FROM enriched
```

### General SQL rules
- CTEs over subqueries — always
- One CTE per logical transformation step
- Trailing commas on column lists
- Uppercase SQL keywords (`SELECT`, `FROM`, `WHERE`, `JOIN`, `CASE`, `WHEN`, `THEN`, `END`, etc.)
- Lowercase function names (`count()`, `coalesce()`, `date_trunc()`, `row_number()`)
- Align `AS` aliases when there are 3+ columns in a block
- Always end the model with `SELECT * FROM <final_cte>`
- Add a header comment block on every model (layer, description, dependencies, adapter notes if relevant)

---

## YAML / Documentation Standards

Every model must have a `.yml` entry. Examples by layer:

### Staging YAML

```yaml
version: 2

sources:
  - name: api_sports
    description: Raw data from the API-Sports rugby endpoint, loaded via Airbyte.
    schema: airbyte_raw           # Adjust to the raw schema name in your warehouse
    tables:
      - name: fixtures
        description: Raw fixture records as loaded from the API.

models:
  - name: stg_api_sports__fixtures
    description: >
      Cleaned and deduplicated rugby fixtures from API-Sports.
      Casts date strings to TIMESTAMP, renames columns to snake_case.
    config:
      materialized: view
      tags: ["staging", "rugby"]
    columns:
      - name: fixture_id
        description: Unique identifier for the fixture (sourced from API-Sports).
        tests:
          - unique
          - not_null
      - name: fixture_at
        description: Kickoff timestamp in UTC.
        tests:
          - not_null
      - name: fixture_status
        description: Short status code for the match (e.g., FT, NS, CANC).
        tests:
          - accepted_values:
              values: ["FT", "NS", "CANC", "PST", "LIVE"]
```

### Intermediate YAML

```yaml
models:
  - name: int_rugby__fixtures_with_teams
    description: >
      Enriches fixtures with home and away team names and logos.
      Joins stg_api_sports__fixtures with stg_api_sports__teams (twice — home and away).
    config:
      materialized: view
      tags: ["intermediate", "rugby"]
    columns:
      - name: fixture_id
        description: Unique fixture identifier, carried over from staging.
        tests:
          - unique
          - not_null
      - name: home_team_name
        description: Full name of the home team.
      - name: away_team_name
        description: Full name of the away team.
```

### Mart YAML

```yaml
models:
  - name: mrt_rugby__fixture_results
    description: >
      Final fixture results table ready for dashboards and self-service analysis.
      Includes team names, scores, result label (home_win / away_win / draw), and total points.
      Filtered to finished matches only (status = FT).
    config:
      materialized: table
      tags: ["mart", "rugby"]
    columns:
      - name: fixture_id
        description: Unique fixture identifier.
        tests:
          - unique
          - not_null
      - name: result
        description: Match outcome from the home team perspective.
        tests:
          - accepted_values:
              values: ["home_win", "away_win", "draw", "unknown"]
      - name: total_points
        description: Sum of home and away scores. Null scores are treated as 0.
```

Rules:
- `description` is mandatory on every model and column — no exceptions
- Declare the `schema` on sources to point to the raw ingestion schema (e.g., `airbyte_raw`)
- Primary key columns must always have `unique` + `not_null` tests
- Use `tags` to label both the layer and the domain (e.g., `["mart", "rugby"]`)
- Use `config.meta` for extra context: owner, source URL, expected update frequency

---

## Testing Strategy

### Generic tests (in `.yml` files)
- `not_null` — on every primary key and all critical foreign keys
- `unique` — on every primary key
- `accepted_values` — on status, type, and enum columns
- `relationships` — when a foreign key references another model's primary key

### Singular tests (in `tests/`)
- Use for business rules that cannot be expressed as generic tests
- Naming: `test__<layer>__<model>__<what_is_tested>.sql`
  - Example: `test__mart__mrt_rugby__fixture_results__no_negative_scores.sql`
- Must return 0 rows to pass (rows returned = test failures)

### Custom generic tests (in `macros/tests/`)
- Use for reusable cross-project validations
- Examples: `test_is_positive`, `test_is_valid_email`, `test_no_future_dates`

### Running tests
```bash
# All tests
dbt test

# Specific model
dbt test --select stg_api_sports__fixtures

# Specific layer by tag
dbt test --select tag:mart

# Run and test together
dbt build --select tag:staging
```

---

## Materialization Strategy

| Layer | Default | Notes |
|---|---|---|
| Staging | `view` | Switch to `table` for slow or external sources |
| Intermediate | `view` | Switch to `table` or `incremental` only if performance requires |
| Mart | `table` | Always — mart models are for direct consumption, never views |

### Incremental models
- Define `unique_key` — always
- Use `is_incremental()` macro to filter new records
- Incremental strategy by adapter:
  - **BigQuery:** `merge` (default) or `insert_overwrite` for partition-based loads
  - **PostgreSQL:** `merge`
  - **DuckDB:** `delete+insert`

```sql
{{ config(
    materialized='incremental',
    unique_key='activity_id',
    on_schema_change='fail'
    -- incremental_strategy='merge'  -- set explicitly per adapter if needed
) }}

SELECT * FROM {{ ref('stg_garmin__activities') }}
{% if is_incremental() %}
WHERE _loaded_at > (SELECT MAX(_loaded_at) FROM {{ this }})
{% endif %}
```

---

## dbt Commands Reference

```bash
# Install packages
dbt deps

# Load seeds (static reference CSVs only — not data/)
dbt seed

# Compile and run all models
dbt run

# Run a specific model and all its upstream dependencies
dbt run --select +mrt_rugby__fixture_results

# Run a specific layer by tag
dbt run --select tag:staging
dbt run --select tag:intermediate
dbt run --select tag:mart

# Run and test in one go
dbt build

# Run and test a specific layer
dbt build --select tag:mart

# Generate and serve documentation
dbt docs generate
dbt docs serve

# Check for issues without running
dbt compile

# Format/lint SQL (requires sqlfluff)
sqlfluff lint models/
sqlfluff fix models/
```

---

## Packages in Use

Defined in `packages.yml`:

```yaml
packages:
  - package: dbt-labs/dbt_utils
    version: [">=1.0.0", "<2.0.0"]
  - package: calogica/dbt_expectations
    version: [">=0.10.0", "<0.11.0"]
```

Install with: `dbt deps`

Commonly used utilities:
- `dbt_utils.generate_surrogate_key()` — composite surrogate keys from multiple columns
- `dbt_utils.star()` — SELECT all columns except a given list
- `dbt_expectations.expect_column_values_to_be_between()` — range validation on numeric columns

---

## Environment & Profiles

`profiles.yml` is **never committed** to version control.
Use environment variables for all credentials.

### BigQuery profile
```yaml
# ~/.dbt/profiles.yml
my_project:
  target: dev
  outputs:
    dev:
      type: bigquery
      method: oauth                         # or service-account for CI/CD
      project: "{{ env_var('GCP_PROJECT') }}"
      dataset: "{{ env_var('BQ_DATASET') }}"
      threads: 4
      timeout_seconds: 300
    prod:
      type: bigquery
      method: service-account
      project: "{{ env_var('GCP_PROJECT') }}"
      dataset: "{{ env_var('BQ_DATASET_PROD') }}"
      keyfile: "{{ env_var('GCP_KEYFILE_PATH') }}"
      threads: 4
```

### PostgreSQL (Supabase) profile
```yaml
my_project:
  target: dev
  outputs:
    dev:
      type: postgres
      host: "{{ env_var('SUPABASE_HOST') }}"
      user: "{{ env_var('SUPABASE_USER') }}"
      password: "{{ env_var('SUPABASE_PASSWORD') }}"
      dbname: "{{ env_var('SUPABASE_DB') }}"
      port: "{{ env_var('SUPABASE_PORT') | int }}"
      schema: public
      threads: 4
```

### DuckDB profile (local / portfolio)
```yaml
my_project:
  target: dev
  outputs:
    dev:
      type: duckdb
      path: ./dev.duckdb
      threads: 4
```

Expected env vars (adjust per project):
```bash
# BigQuery
GCP_PROJECT=...
BQ_DATASET=...
BQ_DATASET_PROD=...
GCP_KEYFILE_PATH=...

# PostgreSQL
SUPABASE_HOST=...
SUPABASE_USER=...
SUPABASE_PASSWORD=...
SUPABASE_DB=...
SUPABASE_PORT=5432
```

---

## Git Workflow

- **One branch per feature or model group**: `feat/stg-api-sports-fixtures`
- **Commit message format**: `<type>(<scope>): <short description>`
  - Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`
  - Scope = layer name or domain
  - Examples:
    - `feat(staging): add stg_api_sports__fixtures model`
    - `feat(intermediate): add int_rugby__fixtures_with_teams model`
    - `feat(mart): add mrt_rugby__fixture_results model`
    - `test(mart): add unique/not_null tests to mrt_running__training_summary`
    - `docs(staging): document api_sports source columns`
- **Pull Requests** for all merges into `main`
- Never commit: `target/`, `logs/`, `dbt_packages/`, `profiles.yml`, `*.duckdb`

`.gitignore` must include:
```
target/
dbt_packages/
logs/
profiles.yml
*.duckdb
.env
```

---

## Claude Interaction Rules

When working with Claude on this project:

1. **Always provide full file contents** — never partial diffs unless explicitly asked
2. **Specify the exact file path** for every file delivered
3. **Never modify files directly** — always provide copy/paste ready content
4. **Follow naming conventions strictly** — `stg_`, `int_`, `mrt_` prefixes are mandatory, do not invent alternatives
5. **Respect layer boundaries:**
   - Staging only references `source()` — never `ref()`
   - Intermediate only references staging models via `ref()`
   - Mart references intermediate (or staging for simple, single-source cases) via `ref()`
   - Never skip a layer (e.g., no mart model referencing a source directly)
6. **Know where CSV data belongs:**
   - `seeds/` — small, static, manually-maintained reference data; loaded by `dbt seed`
   - `data/` — external CSV sources loaded into the warehouse independently; referenced via `source()`
   - When in doubt, ask before deciding
7. **Be adapter-aware:**
   - Default to standard SQL that works across BigQuery, PostgreSQL, and DuckDB
   - Flag adapter-specific syntax (e.g., `QUALIFY`, partition/cluster config) with a comment
   - Ask which warehouse is the target if it affects the SQL or config
8. **Document everything** — every model, every column, no exceptions
9. **When adding a model**, also provide or update:
   - The corresponding `.yml` entry with descriptions and tests
   - `NEXT_STEPS.md` if the task is complete
   - `DECISIONS.md` if an architectural choice was made
10. **When suggesting a new package or tool**, add it to `DECISIONS.md` with rationale
11. **SQL must follow the style guide** — CTEs, uppercase keywords, header comments
12. **Ask before changing materialization strategy** — it has cost/performance implications
13. **Default target is `dev` (DuckDB)** unless the project context specifies BigQuery or PostgreSQL
