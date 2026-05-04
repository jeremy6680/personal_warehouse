# CLAUDE.md — dbt Project Guidelines

This file provides context and instructions for Claude when working on dbt projects.
It covers conventions, architecture decisions, workflow rules, and code standards.

> **Principle:** A dbt project's purpose is to move data from _source-conformed_ to
> _business-conformed_. Every structural decision in this file serves that goal.
> Consistency is non-negotiable — when in doubt, follow these conventions rather than
> inventing new ones. Deviation is always documented in `DECISIONS.md`.

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

When writing SQL, **default to standard SQL** that works across adapters unless the project
explicitly targets a single warehouse. Flag adapter-specific syntax with a comment.

---

## Repository Structure

```
project/
├── analyses/                   # Ad-hoc SQL analyses (not materialized)
├── data/                       # Raw CSV files loaded externally (bq load, scripts, Airbyte)
│                               # dbt does NOT manage these — BigQuery/Postgres is the source of truth
├── dbt_packages/               # Installed dbt packages (git-ignored)
├── logs/                       # dbt logs (git-ignored)
├── macros/                     # Reusable Jinja macros
│   └── tests/                  # Custom generic test macros
├── models/
│   ├── overview.md             # Custom docs site overview ({% docs __overview__ %})
│   ├── staging/                # Source-conformed atoms — one model per source table
│   │   ├── <source_system_a>/  # Subfolder per source system (e.g. api_sports/, stripe/)
│   │   │   ├── base/           # Base models (only when joins are needed to stage a concept)
│   │   │   ├── _<source>__docs.md      # Long-form docs blocks for this source's models
│   │   │   ├── _<source>__sources.yml
│   │   │   ├── _<source>__models.yml
│   │   │   └── stg_<source>__<entities>.sql
│   │   └── <source_system_b>/
│   ├── intermediate/           # Business-conformed molecules — joins and transformations
│   │   └── <business_domain>/  # Subfolder per business domain (e.g. finance/, rugby/)
│   │       ├── _int_<domain>__docs.md  # Long-form docs blocks for this domain's models
│   │       ├── _int_<domain>__models.yml
│   │       └── int_<entities>_<verb>.sql
│   ├── mart/                   # Business-ready entities for end users
│   │   └── <business_domain>/  # Subfolder per department or area of concern
│   │       ├── _<domain>__docs.md      # Long-form docs blocks for this domain's models
│   │       ├── _<domain>__models.yml
│   │       └── <entity>.sql    # Plain entity name — no prefix (e.g. orders.sql, fixtures.sql)
│   └── utilities/              # General-purpose helper models (date spines, etc.)
├── seeds/                      # Small, static, manually-maintained reference CSVs (dbt-managed)
├── snapshots/                  # SCD Type 2 snapshots
├── target/                     # Compiled artifacts (git-ignored)
├── tests/                      # Singular (one-off) data tests
├── .sqlfluff                   # SQL linting configuration
├── dbt_project.yml             # Project configuration (includes default materializations per layer)
├── packages.yml                # dbt package dependencies
├── profiles.yml                # Connection profiles (NOT committed — use env vars)
├── CLAUDE.md                   # This file
├── CONTEXT.md                  # Project overview and goals
├── DECISIONS.md                # Architecture and technical decisions log
├── NEXT_STEPS.md               # Current priorities and next tasks
└── STRUCTURE.md                # Folder/file structure explained
```

> **Why subfolders?**
> Subfolders aren't just for organisation — they are a first-class selection mechanism.
> `dbt build --select staging.stripe+` rebuilds all Stripe-dependent models in one command.
> Always create a subfolder when adding a new source system or business domain.

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
- Declared in `_<source>__sources.yml` and referenced via `source()` in staging models
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

- **Purpose:** Create the source-conformed **atoms** — clean and reliable building blocks from raw source data. One model per source table.
- **Materialization:** `view` by default (declared globally in `dbt_project.yml` — see below). Switch to `table` only if the source is slow or external.
- **Folder structure:** Subfolders by **source system** (e.g., `staging/api_sports/`, `staging/garmin/`, `staging/stripe/`).
  - ✅ Subfolders by source system
  - ❌ Subfolders by loader (Airbyte, Fivetran…) — too broad
  - ❌ Subfolders by business domain — this causes overlap and conflicting definitions at the atomic level
- **File prefix:** `stg_`
- **Naming:** `stg_<source>__<entities>.sql` — **plural entity name** (e.g., `stg_api_sports__fixtures.sql`, `stg_stripe__payments.sql`)
  - The double underscore `__` visually separates the source system from the entity name. This avoids ambiguity (is `google_analytics_campaigns` from the `google` source or the `google_analytics` source?).
- **Rules:**
  - Single source per model — no joins between tables (see base models below for the exception)
  - Rename columns to `snake_case`
  - Cast types (strings to `DATE`, `TIMESTAMP`, `INTEGER`, etc.)
  - Handle obvious nulls and trim whitespace
  - Basic computations that will always be needed (e.g. cents to dollars) — apply the DRY principle here
  - Deduplicate if the source contains duplicates:
    - BigQuery / DuckDB: use `QUALIFY ROW_NUMBER() OVER (...) = 1`
    - PostgreSQL: use a subquery with `ROW_NUMBER()`
  - Add `_loaded_at` metadata column when available from the source
  - ❌ No joins (with the base model exception below)
  - ❌ No aggregations — do not change the grain in staging
  - ❌ No business logic — this layer is purely about making raw data usable

#### Base models (staging sub-layer)

Used only when a join is strictly necessary to produce a clean staging concept. Place them in `staging/<source>/base/`.

Common valid use cases:
- **Separate delete tables:** The source system stores deletes in a separate table; join it to mark or filter deleted records.
- **Unioning identical schemas:** Multiple identical source schemas (e.g., multi-region Shopify stores) that must be unioned before staging.

Base model rules:
- File prefix: `base_`
- Naming: `base_<source>__<entities>.sql`
- Same transformation rules as staging (rename, cast, no aggregations)
- The staging model then joins the base models — source macros only appear in base models in this case

### Intermediate Layer (`models/intermediate/`)

- **Purpose:** Build the **molecules** — purpose-built transformation steps that bring staging atoms together into enriched concepts ready for the mart layer.
- **Materialization:** Ephemeral by default (no warehouse artifact — interpolated into downstream models). Alternative: `view` in a custom schema with restricted permissions, for easier troubleshooting as the project grows.
- **Folder structure:** Subfolders by **business domain** (e.g., `intermediate/finance/`, `intermediate/rugby/`).
  - This is where we shift from source-conformed to business-conformed groupings.
- **File prefix:** `int_`
- **Naming:** `int_<entities>_<verb>.sql` — use a descriptive **verb** to communicate the transformation (e.g., `int_payments_pivoted_to_orders.sql`, `int_fixtures_enriched_with_teams.sql`)
  - No double underscore at this layer unless the model still operates at source-system level (in which case `int_<source>__<entities>_<verb>.sql`)
- **Rules:**
  - Always built on top of staging models — never reference raw sources directly
  - Common purposes: structural simplification (bringing 4–6 concepts together), re-graining (fan out or collapse), isolating complex operations (window functions, complex joins)
  - Keep models focused: one logical transformation per model
  - Aim for a narrowing DAG — multiple inputs are expected, multiple outputs from the same model are a red flag
  - Document every join condition and its business rationale in the docs block
  - ❌ Do not expose intermediate models to end users — they are internal building blocks

### Mart Layer (`models/mart/`)

- **Purpose:** The **cells** — business-defined entities ready for consumption. Wide, denormalized, entity-grained.
- **Materialization:** `table` (always — mart models are for dashboards and direct querying). Evolve to `incremental` only when the table takes too long to build and slows down runs.
- **Folder structure:** Subfolders by **business department or area of concern** (e.g., `mart/finance/`, `mart/marketing/`, `mart/rugby/`).
- **File naming:** Plain entity name — **no prefix** (e.g., `orders.sql`, `customers.sql`, `fixtures.sql`).
  - ✅ `orders.sql` — clear, entity-grained
  - ❌ `finance_orders.sql` and `marketing_orders.sql` — anti-pattern, creates competing definitions of the same concept. If truly different business concepts exist (e.g. `tax_revenue` vs `revenue`), give them distinct names.
  - ❌ `orders_per_day.sql` — time-based rollups belong in metrics, not mart tables
- **Rules:**
  - Wide and denormalized — in modern warehousing, storage is cheap; compute is expensive. Pack in all relevant data about the entity at its grain.
  - Always built on top of intermediate (or staging for simple, single-source cases)
  - Window functions, rolling averages, KPIs, and aggregations belong here
  - Avoid more than 4–5 joins in a single mart — if needed, add intermediate models for clarity
  - Must have full column-level documentation (in YAML + docs blocks)
  - Must have at least `not_null` + `unique` tests on primary keys
  - No raw source references — only `ref()` calls
  - For BigQuery mart tables: consider `partition_by` and `cluster_by` for tables expected to grow large
  - A mart can reference another mart (e.g., `customers.sql` referencing `orders.sql`), but use this with care to avoid circular dependencies

#### `models/utilities/`

A special folder outside the three layers for general-purpose helper models (not data to model, but tools for modeling):
- Date spines generated with `dbt_utils.date_spine()`
- Any other macro-generated utility models

---

## Default Materializations in `dbt_project.yml`

Declare default materializations per layer in `dbt_project.yml` to avoid repeating `config()` blocks in every model file:

```yaml
# dbt_project.yml

models:
  <project_name>:
    staging:
      +materialized: view
    intermediate:
      +materialized: ephemeral
    mart:
      +materialized: table
```

Individual models can override these defaults with a `{{ config() }}` block when needed.

---

## Documentation Strategy

Documentation is a first-class concern in this project. The goal is for every model
and column to be self-explanatory — for both humans discovering the data and AI assistants
working on the codebase. dbt generates a browsable documentation site (`dbt docs serve`)
from these descriptions, and the quality of that site reflects directly on the project.

Good documentation serves two distinct audiences:
- **End users** (analysts, stakeholders) discovering and querying data
- **Contributors** (engineers, AI) building and maintaining transformations

### Two mechanisms: inline descriptions vs. docs blocks

| Mechanism | When to use | Format |
|---|---|---|
| Inline `description:` in YAML | Short descriptions — 1 to 3 sentences, no formatting needed | Plain string in `.yml` |
| Docs blocks (`{% docs %}`) | Long-form — business context, data quality notes, column value tables, lineage narrative | Markdown in `.md` file |

**Default to docs blocks for any model description.** Short inline descriptions are acceptable for
simple columns, but model-level descriptions should almost always live in a docs block.

### Docs blocks — syntax and placement

A docs block is declared in a `.md` file and referenced from YAML with `{{ doc("block_name") }}`.

**Declaration:**

```markdown
{% docs block_name %}

Your markdown content here. Supports **bold**, tables, lists, links, code blocks, etc.

{% enddocs %}
```

**Reference in YAML:**

```yaml
- name: stg_api_sports__fixtures
  description: '{{ doc("stg_api_sports__fixtures") }}'
```

**Naming rules for docs block identifiers:**
- Only alphanumeric characters (`A–Z`, `a–z`, `0–9`) and underscores `_`
- Must not start with a digit
- Must be **unique across the entire project** — dbt does not namespace docs blocks by folder
- Convention: `<layer_prefix>_<source_or_domain>__<model_or_concept>`
  - Model block: `stg_api_sports__fixtures`, `int_rugby__fixtures_enriched_with_teams`, `mart_rugby__fixtures`
  - Shared column block: `col_fixture_id`, `col_loaded_at`, `col_fixture_status`

**File naming convention for docs files:**

| Layer | Location | File name |
|---|---|---|
| Project overview | `models/` | `overview.md` |
| Staging | `models/staging/<source>/` | `_<source>__docs.md` |
| Intermediate | `models/intermediate/<domain>/` | `_int_<domain>__docs.md` |
| Mart | `models/mart/<domain>/` | `_<domain>__docs.md` |

### Project overview page (`models/overview.md`)

Every project **must** define a custom `__overview__` docs block. This is the landing page
of the generated docs site — the first thing any reader (human or AI) sees.

```markdown
{% docs __overview__ %}

# <Project Name>

## What this project does

<2–3 sentences: what data this project transforms, for whom, and why.>

## Data sources

| Source | Description | Ingestion | Update frequency |
|---|---|---|---|
| `api_sports` | Rugby fixtures, teams, standings from API-Sports | Airbyte | Hourly |
| `garmin` | Activity and performance data from Garmin Connect | Custom script | Daily |

## Layers

| Layer | Prefix | Purpose |
|---|---|---|
| Staging | `stg_` | Clean and type raw source data — one model per source table |
| Intermediate | `int_` | Join and transform staged models into business-ready building blocks |
| Mart | _(none)_ | Final, wide, entity-grained tables for dashboards and self-service |

## Key contacts

- **Owner:** <name or team>
- **Stack:** dbt Core + <warehouse> + <ingestion tool>
- **Repo:** <BitBucket URL>

## Style guide and conventions

See `CLAUDE.md` at the root of this repository.

{% enddocs %}
```

### Example docs block file — `_api_sports__docs.md`

```markdown
{% docs stg_api_sports__fixtures %}

Cleaned and typed rugby fixture records sourced from the API-Sports endpoint.

**Source table:** `airbyte_raw.fixtures` — loaded hourly via Airbyte.

**Transformations applied:**
- All columns renamed to `snake_case`
- `fixture_date` cast from string to `TIMESTAMP` (UTC)
- Deduplication applied using `QUALIFY ROW_NUMBER() OVER (PARTITION BY fixture_id ORDER BY fixture_at DESC) = 1`
- Null scores (`home_score`, `away_score`) are preserved — they indicate a match not yet played

**Grain:** One row per fixture.

**Known data quality issues:**
- Postponed matches (`status = 'PST'`) may reappear with a new `fixture_id` after rescheduling.
  Always filter by `fixture_status = 'FT'` when working with completed-match data.

{% enddocs %}


{% docs col_fixture_id %}

Unique identifier for the fixture, sourced directly from the API-Sports API.
Stable across loads — the same fixture always has the same ID.

{% enddocs %}


{% docs col_fixture_status %}

Short status code indicating the current state of the match.

| Value | Meaning |
|---|---|
| `FT` | Full time — match completed |
| `NS` | Not started |
| `LIVE` | In progress |
| `PST` | Postponed |
| `CANC` | Cancelled |

{% enddocs %}


{% docs col_loaded_at %}

Timestamp at which this record was loaded into the raw schema by Airbyte.
Used as the high-watermark column for incremental loads.

{% enddocs %}
```

> **Reusing column docs blocks across models:**
> Shared columns (e.g., `fixture_id`, `_loaded_at`) should reference a single shared docs block
> rather than repeating the same description in every YAML file.
> Define shared column blocks once in the most relevant source's `_*__docs.md` file
> and reference them from any model that contains that column.

### Mart docs block template — `_rugby__docs.md`

Every mart model docs block must follow this four-section structure.
It is designed to be readable by non-technical stakeholders as well as
engineers and AI assistants encountering the model for the first time.

```markdown
{% docs mart_rugby__fixtures %}

# Description and Motivation

Final fixture results table for completed rugby matches, built for
self-service analysis and dashboards.

Answers questions like: which team won, what was the score, and how many
total points were scored in a given fixture? Filtered to finished matches
only (`fixture_status = 'FT'`). Derived from `int_fixtures_enriched_with_teams`,
which joins fixture data with home and away team details.

**Grain:** One row per completed fixture.
**Upstream model:** `int_fixtures_enriched_with_teams`

**Typical use cases:**
- Win/loss records by team, league, or season
- Points scored trends over time
- Head-to-head analysis between two teams

# Known Limitations

- Postponed matches (`PST`) may later reappear with a **new fixture ID**
  after rescheduling. This means a single real-world fixture can appear
  as two rows across time if the raw source was loaded both before and
  after rescheduling. Always filter on `fixture_status = 'FT'` and be
  aware of this when computing historical counts.
- `home_score` and `away_score` are `NULL` for non-finished matches —
  this model filters them out, but any upstream join to this table
  should not assume scores are always populated.
- Does not include matches in progress (`LIVE`). For live data, query
  `stg_api_sports__fixtures` directly.

# Business Stakeholder

Jeremy Marchandeau — jeremy@web2data.org
Primary consumer of this model for RugbyDraft analytics and portfolio demos.

# Technical Stakeholder

Jeremy Marchandeau — jeremy@web2data.org
Built and maintains this model. Contact for questions about join logic,
deduplication strategy, or upstream data quality.

{% enddocs %}
```

**Why this structure?**
The four sections serve distinct purposes:
- **Description and Motivation** — gives any reader (analyst, stakeholder, AI) instant context on what the model is for and why it exists
- **Known Limitations** — prevents silent misuse; documents edge cases that no test can catch
- **Business Stakeholder** — identifies who has the most domain knowledge about the data
- **Technical Stakeholder** — identifies who to contact for implementation questions

> In a solo/portfolio project, both stakeholders are typically the same person.
> In a team context, they will often differ — a finance analyst vs. the engineer who built the model.
> Always fill in both fields even when they're identical: it keeps the template consistent
> and makes the docs immediately useful when the project changes hands.

---

## Naming Conventions

### SQL files
- All filenames are lowercase with underscores
- **Staging:** `stg_<source>__<entities>.sql` — plural, double underscore separator
- **Base (sub-staging):** `base_<source>__<entities>.sql` — plural
- **Intermediate:** `int_<entities>_<verb>.sql` — descriptive verb
- **Mart:** `<entity>.sql` — plain plural entity name, no prefix
- **Utilities:** descriptive name (e.g., `all_dates.sql`)

### Columns
- `snake_case` everywhere
- Primary keys: `<entity>_id` (e.g., `fixture_id`, `activity_id`)
- Foreign keys: `<referenced_entity>_id`
- Boolean columns: prefix with `is_`, `has_`, `did_`
- Date columns: suffix with `_at` (timestamp) or `_date` (date only)
- Monetary columns: suffix with `_amount` and always note the currency in the description

### YAML files
- Sources file per source system: `_<source>__sources.yml`
- Models file per layer subfolder: `_<source>__models.yml` (staging) or `_<domain>__models.yml` (intermediate, mart)
- Use `description` for every model and every column — no exceptions

### Docs block files
- `_<source>__docs.md` in staging source subfolders (e.g., `_api_sports__docs.md`)
- `_int_<domain>__docs.md` in intermediate domain subfolders (e.g., `_int_rugby__docs.md`)
- `_<domain>__docs.md` in mart domain subfolders (e.g., `_rugby__docs.md`)
- `overview.md` at `models/overview.md` — project-level overview only

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
-- Layer: Staging | Source: api_sports
-- Description: Raw rugby fixtures from API-Sports, cleaned and typed.
--              Full description: models/staging/api_sports/_api_sports__docs.md
-- Source table: api_sports.fixtures
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
-- Model: int_fixtures_enriched_with_teams
-- Layer: Intermediate | Domain: rugby
-- Description: Enriches fixtures with home and away team details.
--              Full description: models/intermediate/rugby/_int_rugby__docs.md
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
-- Model: fixtures
-- Layer: Mart | Domain: rugby
-- Description: Final fixture results table — completed matches only.
--              Full description: models/mart/rugby/_rugby__docs.md
-- Dependencies: int_fixtures_enriched_with_teams
-- ============================================================

-- Materialization declared globally in dbt_project.yml (table).
-- Uncomment config() below only when overriding defaults (e.g. BigQuery partitioning).
--
-- {{ config(
--     partition_by={"field": "fixture_at", "data_type": "timestamp", "granularity": "day"},
--     cluster_by=["league_id", "season_year"]
-- ) }}

WITH

fixtures AS (
    SELECT * FROM {{ ref('int_fixtures_enriched_with_teams') }}
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
    WHERE fixture_status = 'FT'            -- Only finished matches
)

SELECT * FROM enriched
```

### General SQL rules
- CTEs over subqueries — always
- One CTE per logical transformation step; name CTEs descriptively (the name should convey _what_ the CTE produces)
- Trailing commas on column lists
- Uppercase SQL keywords (`SELECT`, `FROM`, `WHERE`, `JOIN`, `CASE`, `WHEN`, `THEN`, `END`, etc.)
- Lowercase function names (`count()`, `coalesce()`, `date_trunc()`, `row_number()`)
- Align `AS` aliases when there are 3+ columns in a block
- Always end the model with `SELECT * FROM <final_cte>`
- Header comment block on every model — reference the docs block file path rather than duplicating long descriptions inline
- Plural model names in the mart layer read naturally in SQL (`select * from orders`, not `select * from order`)

---

## YAML / Documentation Standards

Every model must have a `.yml` entry. Model descriptions use the two-tier approach:
- **Short (1–3 lines):** write inline as a plain string
- **Long / complex:** use `'{{ doc("block_name") }}'` pointing to a docs block in the co-located `.md` file

### Staging YAML

```yaml
version: 2

sources:
  - name: api_sports
    description: Raw data from the API-Sports rugby endpoint, loaded via Airbyte.
    schema: airbyte_raw           # Adjust to the raw schema name in your warehouse
    tables:
      - name: fixtures
        description: Raw fixture records as loaded from the API, prior to any transformation.

models:
  - name: stg_api_sports__fixtures
    description: '{{ doc("stg_api_sports__fixtures") }}'
    config:
      tags: ["staging", "rugby"]
    columns:
      - name: fixture_id
        description: '{{ doc("col_fixture_id") }}'
        tests:
          - unique
          - not_null
      - name: fixture_at
        description: Kickoff timestamp in UTC, cast from the raw string `fixture_date`.
        tests:
          - not_null
      - name: fixture_status
        description: '{{ doc("col_fixture_status") }}'
        tests:
          - accepted_values:
              values: ["FT", "NS", "CANC", "PST", "LIVE"]
      - name: _loaded_at
        description: '{{ doc("col_loaded_at") }}'
```

### Intermediate YAML

```yaml
models:
  - name: int_fixtures_enriched_with_teams
    description: '{{ doc("int_rugby__fixtures_enriched_with_teams") }}'
    config:
      tags: ["intermediate", "rugby"]
    columns:
      - name: fixture_id
        description: '{{ doc("col_fixture_id") }}'
        tests:
          - unique
          - not_null
      - name: home_team_name
        description: Full name of the home team, joined from `stg_api_sports__teams`.
      - name: away_team_name
        description: Full name of the away team, joined from `stg_api_sports__teams`.
```

### Mart YAML

```yaml
models:
  - name: fixtures
    description: '{{ doc("mart_rugby__fixtures") }}'
    config:
      tags: ["mart", "rugby"]
      meta:
        owner: "web2data"
        expected_update_frequency: "daily"
    columns:
      - name: fixture_id
        description: '{{ doc("col_fixture_id") }}'
        tests:
          - unique
          - not_null
      - name: result
        description: Match outcome from the home team perspective — `home_win`, `away_win`, `draw`, or `unknown`.
        tests:
          - accepted_values:
              values: ["home_win", "away_win", "draw", "unknown"]
      - name: total_points
        description: Sum of home and away scores. Null scores are treated as 0 via `COALESCE`.
```

### YAML rules
- `description` is mandatory on every model and column — no exceptions
- Declare the `schema` on sources to point to the raw ingestion schema (e.g., `airbyte_raw`)
- Primary key columns must always have `unique` + `not_null` tests
- Use `tags` to label both the layer and the domain (e.g., `["mart", "rugby"]`)
- Do **not** declare `materialized` in YAML `config` blocks — use `dbt_project.yml` for layer-level defaults and `{{ config() }}` blocks in SQL files for model-level overrides
- Use `config.meta` for extra context: owner, source URL, expected update frequency
- When a column description is shared across multiple models, always use a docs block — never copy-paste inline text

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
  - Example: `test__mart__fixtures__no_negative_scores.sql`
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

# Run all models downstream of a source system (leverages subfolder structure)
dbt build --select staging.api_sports+
```

---

## Materialization Strategy

| Layer | Default | Declared in |
|---|---|---|
| Staging | `view` | `dbt_project.yml` |
| Intermediate | `ephemeral` (preferred) or `view` in custom schema | `dbt_project.yml` |
| Mart | `table` | `dbt_project.yml` |

**Escalation path for mart models:**
1. Start with `view` — zero storage cost, always fresh
2. Once the view is too slow to query → switch to `table`
3. Once the table is too slow to build (slows down runs) → switch to `incremental`

Avoid rushing to `incremental` — it adds significant complexity. Apply it only where needed.

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
dbt run --select +fixtures

# Run a specific source system's staging layer (leverages subfolder structure)
dbt run --select staging.api_sports+

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
  - package: dbt-labs/codegen
    version: [">=0.12.0", "<0.13.0"]
  - package: calogica/dbt_expectations
    version: [">=0.10.0", "<0.11.0"]
```

Install with: `dbt deps`

### Key utilities

**`dbt_utils`**
- `dbt_utils.generate_surrogate_key()` — composite surrogate keys from multiple columns
- `dbt_utils.star()` — SELECT all columns except a given list
- `dbt_utils.date_spine()` — generate a date dimension for the utilities folder

**`codegen`** _(use early, use often)_
- Automates the boilerplate for staging models and YAML files
- Staging models follow highly repetitive patterns — once you understand how to write them by hand, use codegen to generate them at scale
- Key commands:
  ```bash
  # Generate source YAML for a schema
  dbt run-operation generate_source --args '{"schema_name": "airbyte_raw", "database_name": "my_db"}'

  # Generate a staging model SQL from a source table
  dbt run-operation generate_base_model --args '{"source_name": "api_sports", "table_name": "fixtures"}'

  # Generate model YAML documentation
  dbt run-operation generate_model_yaml --args '{"model_names": ["stg_api_sports__fixtures"]}'
  ```

**`dbt_expectations`**
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
    - `feat(intermediate): add int_fixtures_enriched_with_teams model`
    - `feat(mart): add rugby/fixtures mart model`
    - `docs(staging): add docs blocks for api_sports source`
    - `docs(project): add custom __overview__ docs block`
    - `test(mart): add unique/not_null tests to rugby/fixtures`
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
4. **Follow naming conventions strictly:**
   - Staging: `stg_<source>__<entities>.sql` (double underscore, plural, in source-system subfolder)
   - Base: `base_<source>__<entities>.sql` (in `base/` subfolder under the source system)
   - Intermediate: `int_<entities>_<verb>.sql` (in business-domain subfolder)
   - Mart: `<entity>.sql` (plain plural entity name, in business-domain subfolder — **no prefix**)
   - Do not invent alternative naming patterns
5. **Respect layer boundaries:**
   - Staging only references `source()` — never `ref()` (except when staging model joins base models)
   - Base models only reference `source()` — they are the only `source()` consumers when used
   - Intermediate only references staging (or other intermediate) models via `ref()`
   - Mart references intermediate (or staging for simple, single-source cases) via `ref()`
   - Never skip a layer (e.g., no mart model referencing a source directly)
   - Never expose intermediate models as end-user artifacts
6. **Respect subfolder conventions:**
   - Staging subfolders = source system names (e.g., `staging/api_sports/`)
   - Intermediate and mart subfolders = business domain names (e.g., `mart/rugby/`)
7. **Know where CSV data belongs:**
   - `seeds/` — small, static, manually-maintained reference data; loaded by `dbt seed`
   - `data/` — external CSV sources loaded into the warehouse independently; referenced via `source()`
   - When in doubt, ask before deciding
8. **Be adapter-aware:**
   - Default to standard SQL that works across BigQuery, PostgreSQL, and DuckDB
   - Flag adapter-specific syntax (e.g., `QUALIFY`, partition/cluster config) with a comment
   - Ask which warehouse is the target if it affects the SQL or config
9. **Document everything — rigorously. Documentation is not optional:**
   - Every model and every column must have a `description` — no exceptions
   - Apply the two-tier rule: short descriptions inline, everything else in a docs block
   - When adding any model, always create or update the corresponding `_*__docs.md` file
   - Shared columns (e.g., `fixture_id`, `_loaded_at`) must use shared docs blocks — never copy-paste descriptions across YAML files
   - The `models/overview.md` file must be kept up to date as new sources and domains are added
   - When in doubt about description length, err on the side of writing a docs block
   - **Mart docs blocks must follow the four-section template** (Description and Motivation / Known Limitations / Business Stakeholder / Technical Stakeholder) — do not write free-form descriptions for mart models
10. **When adding a model**, also provide or update:
    - The SQL file
    - The `.yml` entry with descriptions (using `{{ doc() }}` where appropriate) and tests
    - The `_*__docs.md` file with the appropriate docs block:
      - Staging / intermediate: free-form markdown with grain, transformations, and data quality notes
      - **Mart: strictly follow the four-section template** (Description and Motivation, Known Limitations, Business Stakeholder, Technical Stakeholder)
    - `NEXT_STEPS.md` if the task is complete
    - `DECISIONS.md` if an architectural choice was made
11. **When adding a new source system**, also provide:
    - `models/staging/<source>/_<source>__docs.md` with a docs block per model and any complex columns
    - Updated `models/overview.md` to include the new source in the sources table
12. **When suggesting a new package or tool**, add it to `DECISIONS.md` with rationale
13. **SQL must follow the style guide** — CTEs, uppercase keywords, header comment referencing the docs file path
14. **Ask before changing materialization strategy** — it has cost/performance implications
15. **Default target is `dev` (DuckDB)** unless the project context specifies BigQuery or PostgreSQL
16. **Do not declare materialization in YAML `config` blocks** — use `dbt_project.yml` layer defaults; only override in the SQL model's `{{ config() }}` block when genuinely needed
17. **Use `codegen`** to generate staging boilerplate when adding a new source system — do not write repetitive YAML and model SQL by hand once the pattern is established
18. **Docs block names must be unique project-wide** — always use the `<layer_prefix>_<source_or_domain>__<model_or_concept>` convention; never reuse a name across different contexts
