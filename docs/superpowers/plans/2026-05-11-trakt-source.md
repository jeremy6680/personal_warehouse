# Trakt Source Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Trakt API ingestion, staging models, and unified movie/anime intermediates.

**Architecture:** Trakt raw API data lands in `raw_personal` via a full-refresh Python script. dbt staging models type and normalize the raw rows, then intermediate models merge Trakt with MovieBuddy and Letterboxd on `lower(trim(title)) + release_year`.

**Tech Stack:** Python `requests`, `google-cloud-bigquery`, dbt BigQuery SQL.

---

### Task 1: Ingestion

**Files:**
- Create: `scripts/trakt_to_bq.py`
- Modify: `.env.example`
- Modify: `requirements.txt`

- [ ] Verify `dbt compile --select stg_trakt__watched_movies int_anime__unified` reports missing nodes.
- [ ] Add `scripts/trakt_to_bq.py` with `--dry-run` and `--table` support.
- [ ] Add `TRAKT_API_KEY` and `TRAKT_USERNAME` to `.env.example`.
- [ ] Add `requests` to `requirements.txt`.

### Task 2: Staging

**Files:**
- Create: `models/staging/trakt/stg_trakt__watched_movies.sql`
- Create: `models/staging/trakt/stg_trakt__watched_shows.sql`
- Create: `models/staging/trakt/stg_trakt__ratings.sql`
- Create: `models/staging/trakt/_trakt__sources.yml`
- Create: `models/staging/trakt/_trakt__docs.md`

- [ ] Add source declarations for `raw_personal.trakt_*`.
- [ ] Normalize Trakt rating from raw `1..10` to warehouse `0.5..5`.
- [ ] Add primary key, not-null, and rating range tests.

### Task 3: Intermediate and Mart

**Files:**
- Modify: `models/intermediate/films/int_movies__unified.sql`
- Create: `models/intermediate/anime/int_anime__unified.sql`
- Modify: `models/intermediate/_intermediate__models.yml`
- Modify: `models/mart/films/mrt_movies__collection.sql`
- Modify: `models/mart/_mart__models.yml`
- Modify: `tests/assert_genre_mapping_coverage.sql`

- [ ] Update movies to merge Trakt, Letterboxd, and MovieBuddy.
- [ ] Resolve rating priority as `Trakt > Letterboxd > MovieBuddy > manual`.
- [ ] Add `source` combinations for movies.
- [ ] Add anime unified from Trakt shows plus MovieBuddy animated TV shows.
- [ ] Compile and run targeted dbt tests.
