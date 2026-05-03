# DECISIONS.md — Architecture Decision Records

Decisions are logged here when a non-obvious choice is made. Each entry records the context, the decision, and the rationale so future work doesn't relitigate settled questions.

---

## ADR-001 — BigQuery as primary warehouse

**Date:** 2025  
**Status:** Active

**Context:** Several warehouse options were available: DuckDB (file-based, local), PostgreSQL via Supabase, or BigQuery.

**Decision:** BigQuery (`personal-warehouse-495013`) is the primary target.

**Rationale:**
- An existing GCP project was already in place
- BigQuery's serverless model means no infrastructure to manage for a personal project
- Scales to large CSVs without performance tuning
- Native integration with Looker Studio for future visualisation
- Service account key stored locally (not committed); `bq load` used for initial ingestion

**Trade-offs:** Costs money at scale (though personal data volumes stay within the free tier). DuckDB remains available for local dev/portfolio iteration without credentials.

---

## ADR-002 — CSV exports as the ingestion method

**Date:** 2025  
**Status:** Active

**Context:** Data originates from consumer apps (Goodreads, Letterboxd, BookBuddy, MovieBuddy, MusicBuddy). These apps expose data via manual CSV exports, not APIs (or only via unofficial/limited APIs).

**Decision:** CSV exports loaded manually via `bq load` into the `raw_personal` dataset in BigQuery.

**Rationale:**
- All five apps provide export functionality
- No auth tokens or API rate limits to manage
- Simple, reproducible, auditable
- Consistent with the `data/` folder pattern — files are external to dbt

**Trade-offs:** Manual refresh — exports must be triggered by hand and re-loaded. Not real-time. If a source gains an official API and an Airbyte connector, migrate that source to Airbyte and update the source declaration in `_csv__sources.yml`.

---

## ADR-003 — Three-layer dbt architecture (staging / intermediate / mart)

**Date:** 2025  
**Status:** Active

**Context:** Standard dbt project structure choices: flat (all models in one layer), two-layer, or three-layer.

**Decision:** Three layers — staging, intermediate, mart — following the dbt Labs recommended pattern.

**Rationale:**
- Clean separation of concerns: raw → clean → joined → aggregated
- Staging models are the only place that reference `source()` — all other models use `ref()`
- Intermediate handles cross-source joins (e.g., merging Goodreads reading history with BookBuddy collection metadata)
- Mart models are the public API of the warehouse — stable, documented, tested

**Trade-offs:** More files and more YAML for a small project. Accepted — the architecture pays off as domains grow and the mart layer becomes a shared foundation for dashboards.

---

## ADR-004 — Source grouping: `staging/csv/` sub-folder

**Date:** 2025  
**Status:** Active

**Context:** All current sources are CSV-backed. Future sources (e.g., Spotify API via Airbyte) would be different in nature.

**Decision:** Group CSV-backed staging models under `models/staging/csv/` with a shared `_csv__sources.yml`.

**Rationale:**
- Keeps the source declaration co-located with its models
- Makes it easy to extend: a `models/staging/spotify/` folder with its own `_spotify__sources.yml` can be added without touching existing files
- Avoids a flat staging folder that mixes CSV and API sources

---

## ADR-005 — Goodreads + BookBuddy: two sources for books

**Date:** 2025  
**Status:** Active

**Context:** Both Goodreads and BookBuddy track books. They overlap but are not identical.

**Decision:** Keep both as separate staging models; merge them in `int_books__unified`.

**Rationale:**
- Goodreads: strong on reading history (date read, shelf) and community ratings
- BookBuddy: strong on collection metadata (genre, category, tags, physical status, condition) and covers the full library including unread books
- Neither is a strict superset of the other — both are needed
- `int_books__unified` joins on ISBN first, falls back to normalized title + author

**Matching strategy:**
- Pass 1: ISBN match (when both sides carry a non-null ISBN)
- Pass 2: normalized `lower(trim(title))` + `lower(trim(author))` for remaining unmatched rows
- Three-case output: `matched`, `bookbuddy_only`, `goodreads_only`

**Trade-offs:** Duplicate book records must be resolved in the intermediate layer. ISBN is the most reliable join key but is not always present in Goodreads exports.

---

## ADR-006 — Letterboxd + MovieBuddy: two sources for movies

**Date:** 2025  
**Status:** Active

**Context:** Same pattern as books — two apps tracking overlapping movie data.

**Decision:** Keep both as separate staging models; merge in `int_movies__unified`.

**Rationale:**
- Letterboxd: diary-focused (exact watch dates, ratings, rewatch tracking) but limited to movies actually watched
- MovieBuddy: collection-focused (full wishlist, rich metadata via TMDB ID, cast, director, genres, runtime) including "Not Watched" items
- Letterboxd exports do not include TMDB IDs, so TMDB-based matching is not possible at this time

**Matching strategy:**
- Single pass: normalized `lower(trim(title))` + `release_year`
- Letterboxd diary entries are aggregated before matching — multiple entries for the same film (rewatches) collapse to one row; most recent entry wins for rating/URI; `watch_count` and date bounds span all entries
- Three-case output: `matched`, `moviebuddy_only`, `letterboxd_only`

**Trade-offs:** Title + year matching can fail on alternate titles or re-releases. TMDB-based matching deferred until Letterboxd exports include TMDB IDs.

---

## ADR-007 — Seeds domain subfolders

**Date:** 2025  
**Status:** Active

**Context:** Three reference seed CSVs needed — one per domain (books, films, music). Seeds could be flat in `seeds/` or organised in subfolders.

**Decision:** Organise seeds in domain subfolders: `seeds/books/`, `seeds/films/`, `seeds/music/`.

**Rationale:**
- Mirrors the intermediate layer domain organisation (`models/intermediate/books/`, etc.)
- Scales cleanly if more seeds are added per domain
- Single `seeds/_seeds.yml` at the root of `seeds/` documents all three seeds

---

## ADR-008 — Surrogate keys via `dbt_utils.generate_surrogate_key`

**Date:** 2025  
**Status:** Active

**Context:** Staging sources lack a single natural primary key. Options: use a raw source ID as-is, construct a composite key manually, or use a hash-based surrogate key.

**Decision:** Use `dbt_utils.generate_surrogate_key([...])` on natural composite keys in every staging model.

**Rationale:**
- Consistent across all models — all IDs are 32-char MD5 hashes of the same formula
- `dbt_utils` implementation is adapter-agnostic (BigQuery, DuckDB, PostgreSQL)
- Stable: the same title+author always produces the same `book_id`, enabling cross-source joins in intermediate without needing to carry raw source IDs

**Keys by model:**
- `stg_csv__bookbuddy`: `book_id` = `generate_surrogate_key(['title', 'author', 'isbn'])` — `isbn` added to distinguish different editions of the same book
- `stg_csv__letterboxd`: `movie_id` = `generate_surrogate_key(['watched_date', 'film_name'])`
- `stg_csv__moviebuddy`: `movie_id` = `generate_surrogate_key(['title', 'release_year'])`
- `stg_csv__musicbuddy`: `album_id` = `generate_surrogate_key(['title', 'artist', 'discogs_release_id'])` — `discogs_release_id` added to distinguish different releases of the same album
- `stg_csv__goodreads`: `book_id` = raw Goodreads string ID (source already provides a stable ID)

---

## ADR-009 — Country dimension via reference seeds

**Date:** 2025  
**Status:** Active

**Context:** Wanted to enable geographic analysis (e.g., "books by country of author") without an API integration.

**Decision:** Maintain three manually-curated seed CSVs mapping names to countries (`author_countries`, `director_countries`, `artist_countries`). Join them in the intermediate layer.

**Rationale:**
- No API dependency or rate limits
- Seeds are version-controlled and auditable
- Join is case-insensitive (`lower/trim` on both sides) to handle capitalisation variations
- Null-safe: unmatched names simply produce a null `country` — no row is dropped

**Trade-offs:** Manual maintenance — new authors/directors/artists must be added by hand. The seed grows incrementally as the collection grows.

---

## ADR-010 — Intermediate domain subfolders

**Date:** 2025  
**Status:** Active

**Context:** Intermediate models span three distinct domains (books, films, music). Could be flat in `models/intermediate/` or organised in subfolders.

**Decision:** Organise intermediate models in domain subfolders: `models/intermediate/books/`, `models/intermediate/films/`, `models/intermediate/music/`. Single `_intermediate__models.yml` at the root of `models/intermediate/` documents all intermediate models.

**Rationale:**
- Keeps domain-specific SQL isolated — easy to find and extend
- Consistent with seeds organisation
- As the project grows (e.g., cross-domain mart models), the domain boundaries remain clear

---

## ADR-011 — `int_movies__unified`: rewatch aggregation before matching

**Date:** 2025  
**Status:** Active

**Context:** Letterboxd diary can contain multiple entries for the same film (rewatches). The intermediate model needs one row per film to join cleanly with MovieBuddy.

**Decision:** Aggregate Letterboxd diary to one row per `(title_key, release_year)` before matching. Use window functions to compute `first_watched_date`, `last_watched_date`, and `watch_count`. Deduplicate to the most recent entry for `rating` and `letterboxd_uri` via `QUALIFY ROW_NUMBER() ... = 1`.

**Rationale:**
- Avoids fan-out in the join (one MovieBuddy row × N Letterboxd entries = N rows)
- Preserves rewatch history through `watch_count` and date range columns
- `QUALIFY` is clean and performant on BigQuery and DuckDB

**Trade-offs:** Adapter note required — `QUALIFY` and `SPLIT` are not available in PostgreSQL. Replace with `ROW_NUMBER()` subquery and `split_part()` if the target changes.
