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

**Decision:** Keep both as separate staging models; merge them in the intermediate layer.

**Rationale:**
- Goodreads: strong on reading history (date read, shelf) and community ratings
- BookBuddy: strong on collection metadata (genre, category, tags, physical status, condition) and covers the full library including unread books
- Neither is a strict superset of the other — both are needed
- Intermediate model (`int_books__collection_with_history`) will join on ISBN or title+author as the merge key

**Trade-offs:** Duplicate book records must be resolved in the intermediate layer. ISBN is the most reliable join key but is not always present in Goodreads exports.

---

## ADR-006 — Letterboxd + MovieBuddy: two sources for movies

**Date:** 2025  
**Status:** Active

**Context:** Same pattern as books — two apps tracking overlapping movie data.

**Decision:** Keep both as separate staging models; merge in intermediate.

**Rationale:**
- Letterboxd: diary-focused (exact watch dates, ratings) but limited to movies actually watched
- MovieBuddy: collection-focused (full wishlist, rich metadata via TMDB ID, cast, director, genres, runtime) including "Not Watched" items
- Join key: TMDB ID (present in MovieBuddy) or title + year matching via Letterboxd URI
