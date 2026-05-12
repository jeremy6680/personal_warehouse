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

---

## ADR-012 — Spotify ingestion via custom Python script (not Airbyte)

**Date:** 2025
**Status:** Active

**Context:** Spotify data (saved albums, liked tracks, followed artists) was identified as a
richer replacement/supplement for the MusicBuddy CSV. Two ingestion options were evaluated:
Airbyte (local instance only, no hosted deployment) and a custom Python script.

**Decision:** Custom Python script (`scripts/spotify_to_bq.py`) using Spotipy + `google-cloud-bigquery`,
scheduled via local Airflow.

**Rationale:**

- Airbyte is only available locally — no Hetzner/Coolify deployment — so scheduled syncs
  would require the developer's machine to be running. The Python script has the same
  constraint but is lighter, requires no running service, and is trivially scheduled via cron
  or an Airflow DAG
- Consistent with the existing "Custom scripts" ingestion pattern already documented in `CLAUDE.md`
  (alongside `bq load` and `scripts/bq_load.sh`)
- Spotipy is the de facto Python wrapper for the Spotify Web API; well-maintained and documented
- Writing the script directly is a stronger portfolio artefact than configuring a UI connector
- If Airbyte gains a hosted deployment in the future, migration is straightforward: swap the
  script for the Airbyte connector and update the `source()` declaration — the staging models
  are unaffected

**Trade-offs:** OAuth2 token management must be handled in the script (refresh + local cache).
The machine must be running at sync time (same constraint as local Airbyte).

---

## ADR-013 — Spotify raw tables land in `raw_personal` (existing dataset)

**Date:** 2025
**Status:** Active

**Context:** BigQuery project `personal-warehouse-495013` has two datasets: `personal_warehouse`
(dbt-managed views and tables) and `raw_personal` (raw source tables loaded from CSV exports).
A decision was needed on where to land Spotify raw data.

**Decision:** Spotify raw tables (`spotify_saved_albums`, `spotify_saved_tracks`,
`spotify_followed_artists`) are written into the existing `raw_personal` dataset.

**Rationale:**

- `raw_personal` already holds all raw source data regardless of ingestion method (bq load,
  scripts, future Airbyte) — it is the raw layer of the warehouse, not a "CSV-only" dataset
- Adding a separate `raw_spotify` dataset would fragment the raw layer without benefit at
  this project scale
- dbt staging models for Spotify will declare `raw_personal` as their source database/schema,
  consistent with all existing `source()` declarations in `_csv__sources.yml`
- Avoids cross-dataset join complexity in staging

**Trade-offs:** All raw tables share the same dataset — table naming must be explicit
(`spotify_*` prefix) to avoid collisions with existing CSV-backed tables (`bookbuddy`,
`letterboxd`, etc.).

---

## ADR-014 — `int_music__unified`: MusicBuddy + Spotify union with genre enrichment via followed artists

**Date:** 2025
**Status:** Active

**Context:** Adding Spotify as a second music source required unifying it with the existing
MusicBuddy CSV in the intermediate layer. The naming pattern for multi-source intermediate models
in this project is `__unified` (see `int_books__unified`, `int_movies__unified`).

**Decision:** Replace `int_music__collection` (single-source) with `int_music__unified`
(multi-source three-case union). Genre enrichment for Spotify albums resolved by joining
`stg_spotify__followed_artists` on the primary artist Spotify ID (`JSON_VALUE(artist_ids, '$[0]')`).

**Rationale:**

- Consistent naming convention with the other two domains
- `album.genres` is almost always `[]` in the Spotify API — genres are stored on Artist objects,
  not Album objects. Joining `followed_artists` on `artist_ids[0]` recovers genre data for albums
  by followed artists without requiring a separate API call
- Single-pass title+artist matching (no two-pass ISBN fallback needed — music has no equivalent)
- Surrogate key for Spotify-only rows generated from `album_name + artists` — consistent with the
  other source-only cases in the unified models

**Matching strategy:**

- Single pass: `lower(trim(artist))` + `lower(trim(title))`
- Three-case output: `matched`, `musicbuddy_only`, `spotify_only`
- For multi-artist Spotify albums, the full `artists` string is used as the match key — may miss
  matches where MusicBuddy stores only the primary artist name

**Trade-offs:** `int_music__collection` is now an orphan model (no downstream `ref()`). It still
compiles correctly but is no longer used — can be deleted manually from BigQuery and the repo.

---

## ADR-015 — Scheduling via macOS launchd instead of Airflow

**Date:** 2025
**Status:** Active

**Context:** The Spotify ingestion script needs to run daily at 09:30 Europe/Paris. Airflow was
the planned orchestrator (documented in CLAUDE.md stack). A DAG was written (`dags/spotify_ingest.py`)
and Airflow was installed locally, but persistent SIGSEGV errors on macOS prevented tasks from executing.
The issue is a well-known macOS limitation: Airflow's process forking is unsafe with certain native
libraries, and the environment (pyenv + conda + venv) amplified the instability.

**Decision:** Use macOS `launchd` as the scheduler for local execution. The Airflow DAG is kept in
`dags/` as a portfolio artefact and future reference. Airflow remains the intended orchestrator if
the pipeline is ever moved to a Linux environment (e.g., Hetzner VM).

**Rationale:**

- Airflow native on macOS causes persistent SIGSEGV errors that survive standard workarounds
  (`no_proxy=*`, `OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES`, `execute_tasks_new_python_interpreter=True`)
- `launchd` is the native macOS job scheduler — zero overhead, no background services, no dependencies
- The scheduling requirement is simple (one script, once a day) — Airflow is overkill for local use
- Airflow is still the right tool for a Linux/production environment; the DAG remains valid and
  can be deployed without modification when the time comes

**Trade-offs:** `launchd` has no UI, no task history, no retry logic. For a personal daily script
running in ~30s this is acceptable. Logs are written to a file for manual inspection.

---

## ADR-016 — Evidence.dev + Netlify as the visualisation layer

**Date:** 2026-05-05
**Status:** Active

**Context:** The project needed a dashboard/visualisation layer to make mart tables accessible
to non-SQL audiences and to serve as a portfolio artefact. Options evaluated:

- **Looker Studio** — free, native BigQuery connector, but limited design control and no
  interactive table filtering beyond basic controls
- **Metabase (self-hosted on Hetzner/Coolify)** — richer UI, SQL-native, but resource-heavy
  on the shared Hetzner instance and requires a persistent running service
- **Evidence.dev + Netlify** — static site generator that runs SQL queries at build time;
  outputs a plain HTML/JS site with no server required at runtime

**Decision:** Use Evidence.dev as the dashboard framework, deployed as a static site on Netlify
(free tier). The Evidence project lives in a dedicated GitHub repo, connected to Netlify for
automatic deployments on push. Daily refresh is triggered by a Netlify build hook called at
the end of the existing launchd pipeline (after `dbt build`).

**Rationale:**

- **Zero runtime cost:** Evidence generates a static site — no container, no server, no RAM
  usage between rebuilds. Completely free on Netlify's free tier.
- **Full interactivity:** Evidence's `<DataTable>` component supports sortable columns,
  full-text search, pagination, and `<Dropdown>`/`<TextInput>` filter components — suitable
  for displaying full collections (e.g., 100+ albums with genre/rating filters), not just
  aggregate charts.
- **Portfolio quality:** The Evidence stack (SQL + Markdown → static site) is a credible,
  modern analytics engineering portfolio artefact — it demonstrates the full pipeline from
  raw ingestion to a production-deployed dashboard.
- **Tight dbt integration:** Evidence queries run directly against BigQuery mart tables via
  the native BigQuery connector. No intermediate export or transformation needed — the mart
  layer is the API.
- **Automated refresh:** The existing launchd plist ends with a `dbt build`; appending a
  `curl` call to the Netlify build hook completes the pipeline: Spotify ingest → dbt build
  → Evidence rebuild → dashboard updated. No new scheduler or service required.

**Architecture:**

```
macOS launchd (09:30 daily)
  → scripts/spotify_to_bq.py   (Spotify → BigQuery raw_personal)
  → dbt build --select tag:spotify+  (dbt transforms → mart tables)
  → curl Netlify build hook    (triggers Evidence rebuild)
      → Evidence queries BigQuery mart tables
      → Netlify deploys static site
```

**Why Netlify over GitHub Actions + GitHub Pages:**

- Netlify manages secrets (BigQuery credentials) natively as environment variables — no
  GitHub Actions secrets configuration or workflow YAML needed
- Netlify's build environment is better suited for Node.js projects (Evidence is npm-based)
- Build hooks are a single `curl` call — simpler than triggering a GitHub Actions workflow
- Netlify provides a clean public URL suitable for a portfolio link

**Trade-offs:**

- Evidence queries run at build time, not at request time — data is as fresh as the last
  build (daily). Acceptable for a personal media collection that updates once a day.
- Evidence's templating (SQL + Markdown) has a learning curve but is well-documented.
- Netlify free tier has build minute limits (300 min/month) — a typical Evidence build
  takes under 2 minutes, so the daily rebuild uses ~60 min/month, well within limits.

---

## ADR-017 — New domains: manga and anime

**Date:** 2026
**Status:** Active

**Context:** The collection contains manga (in BookBuddy, category `Manga`) and anime
(in MovieBuddy, items with `content_type = 'TV Shows'` and `Animation` in their genres).
Both domains have characteristics distinct enough from books and films to warrant
separate domain treatment.

**Decision:**

- **Manga** are extracted from `stg_csv__bookbuddy` via a `category = 'Manga'` filter in
  the intermediate layer. A new `int_manga__unified` model isolates them. The corresponding
  mart is `mrt_manga__collection`.
- **Anime** are extracted from `stg_csv__moviebuddy` (and `stg_trakt__*` when available)
  via a `content_type = 'TV Shows' AND 'Animation' IN genres` filter. A new
  `int_anime__unified` model isolates them. The corresponding mart is `mrt_anime__collection`.
- Manga are **removed** from `int_books__unified` and anime are **removed** from
  `int_movies__unified` to prevent domain mixing.

**Rationale:**

- Manga and novels are consumed and analysed differently (authorship patterns,
  serialisation, volume counts).
- Anime and Western films have different metadata structures and consumption patterns.
- Seeds must be extended: `seeds/manga/author_countries.csv` and
  `seeds/anime/director_countries.csv`.

**Trade-offs:** Two new domains add two new staging → intermediate → mart branches to
maintain. Accepted — the domain separation is cleaner and more scalable long-term.

---

## ADR-018 — New sources: Trakt (films, anime, series) and Bandcamp (music)

**Date:** 2026
**Status:** Active

**Context:** Two new sources will enrich the warehouse:

- **Trakt**: film, series and anime tracker. Has a public REST API + CSV exports.
- **Bandcamp**: music platform. No public user API. No official personal export is
  available for collection/wishlist data as of 2026.

**Decision:**

### Trakt

- Ingestion via the **Trakt API v2** (free tier, 1000 req/h rate limit) via a Python
  script `scripts/trakt_to_bq.py` — same pattern as `spotify_to_bq.py`.
- Relevant endpoints: `GET /users/{username}/watched/movies`,
  `GET /users/{username}/watched/shows`, `GET /users/{username}/ratings/movies`,
  `GET /users/{username}/ratings/shows`.
- Raw tables in `raw_personal`: `trakt_watched_movies`, `trakt_watched_shows`,
  `trakt_ratings`.
- Staging: `models/staging/trakt/stg_trakt__watched_movies.sql`,
  `stg_trakt__watched_shows.sql`, `stg_trakt__ratings.sql`.

### Bandcamp

- **No public user API** available (collection, wishlist data not exposed via API).
- Official CSV export does not exist — the "Settings > Data Export" option mentioned
  in previous notes is incorrect (no such feature exists on bandcamp.com as of 2026).
- **Chosen approach:** Python script `scripts/bandcamp_to_bq.py` calling Bandcamp's
  **internal (undocumented) web API**, reverse-engineered and documented by
  Michael Herger at https://github.com/michaelherger/Bandcamp-API.
- Auth: session cookie (`Cookie: identity=...`) extracted from a browser session.
  Relevant endpoints: `POST /api/fancollection/1/collection_items` and
  `POST /api/fancollection/1/wishlist_items` with `fan_id`.
- Output: full-refresh write to `raw_personal.bandcamp_collection` and
  `raw_personal.bandcamp_wishlist` (same pattern as `spotify_to_bq.py`).
- The cookie must be refreshed manually when it expires (typically every few weeks).
  Add `BANDCAMP_IDENTITY_COOKIE` and `BANDCAMP_FAN_ID` to `.env.example`.

**Note on ToS:** Bandcamp's Terms of Service prohibit scraping for commercial use.
This project is strictly personal, non-commercial, and non-redistributed.
The internal API is the same one Bandcamp's own frontend calls — no credentials
other than the user's own session are used. Risk accepted for a personal portfolio project.

**Rationale:**

- No official export exists — the internal API is the only viable programmatic option.
- Consistent with the existing ingestion patterns: Python scripts write directly to BigQuery.
- More automatable than a manual browser workflow.

**Trade-offs:**

- The internal API is undocumented and can break without notice if Bandcamp changes
  its frontend.
- Session cookie requires periodic manual refresh (no OAuth flow available).
- Pagination uses an `older_than_token` mechanism whose structure is partially
  undocumented — requires careful implementation.

---

## ADR-019 — Rating priority: Trakt > Letterboxd > MovieBuddy

**Date:** 2026
**Status:** Active

**Context:** With Trakt added as a third source, up to three sources can provide a rating
for the same film or series. A clear priority rule is needed.

**Decision:** In `int_movies__unified` and `int_anime__unified`, the resolved rating is:

```sql
COALESCE(trakt_rating, letterboxd_rating, moviebuddy_rating) AS rating
```

**Rationale:**

- Trakt is used as the primary, up-to-date tracker — its rating is the most recent
  and intentional.
- Letterboxd is a watch diary — its rating is valid but may be older.
- MovieBuddy is a catalogue/wishlist — its rating is often absent for unwatched items.

**Trade-offs:** A Trakt rating will override a Letterboxd rating even if the latter
is more recent. Acceptable for this personal project.

---

## ADR-020 — Music deduplication: MusicBuddy + Spotify + Bandcamp

**Date:** 2026
**Status:** Active

**Context:** Three music sources can contain the same album:

- **MusicBuddy**: physical collection (CD) and Discogs wishlist.
- **Spotify**: saved albums (digital).
- **Bandcamp**: purchased digital albums and wishlist. Wishlist items are included
  because adding an album to the wishlist means it has been listened to and liked.

**Decision:** Deduplication is handled in `int_music__unified` via
`lower(trim(title)) + lower(trim(artist))` matching:

- If an album appears in multiple sources, a single row is kept with a `media_format`
  field (e.g. `'cd, digital'`) listing all detected formats.
- Metadata priority: MusicBuddy (richer via Discogs) > Bandcamp > Spotify.
- Rating priority: most recent non-null rating regardless of source.

**Trade-offs:** Title + artist matching can produce false positives on same-name albums
by different artists. Adding a Discogs ID or ISRC identifier would improve precision —
deferred until duplicate issues are observed in practice.

---

## ADR-021 — Media format (`media_format`) per domain

**Date:** 2026
**Status:** Active

**Context:** For music especially, the same album can exist in multiple formats
(CD, vinyl, digital). The format origin of each item must be tracked.

**Decision:**

**Music:**
| Source | Assigned format |
|---|---|
| MusicBuddy | `cd` |
| Spotify | `digital` |
| Bandcamp collection/wishlist | `digital` |
| `vinyls.csv` (future manual upload) | `vinyl` |

If an album appears in multiple sources → `media_format` = concatenated formats,
e.g. `'cd, digital'`.

**Books:** Not applicable for now (all physical in current collection). Can be extended
later with `ebook` / `print` / `audiobook` formats.

**Films / Anime:** Not applicable (streaming context only).

**Implementation:** `media_format` column added in `int_music__unified` and exposed in
`mrt_music__collection`. The future seed `seeds/music/vinyls.csv` will be joined in
the intermediate layer as soon as it exists — its absence is a no-op.

---

## ADR-022 — Genre normalisation via mapping seed

**Date:** 2026
**Status:** Active

**Context:** Genre values vary across sources:

- Films: `Comedy` vs `Comédie`, `Sci-Fi` vs `Science Fiction`
- Books: `Biography` vs `Biography & Autobiography`
- Music: parasitic genres such as `& Country` (Discogs export artefacts)

**Decision:** Create a seed `seeds/shared/genre_mapping.csv` (columns: `domain`,
`raw_genre`, `normalized_genre`) mapping each raw value to a normalised French label.

Parasitic genres (empty strings, `& Country`, etc.) are mapped to `null` and filtered out.

Normalisation is applied in the **intermediate layer**:

- `int_books__unified` for books
- `int_movies__unified` + `int_anime__unified` for films and anime
- `int_music__unified` for music
- `int_manga__unified` for manga

**Rationale:**

- Centralises normalisation logic in a single auditable file.
- Easily extensible: adding a row to the CSV is sufficient.
- No logic in staging (respects layer boundaries).

**Trade-offs:** Manual maintenance of the mapping. Unknown genres pass through unchanged
and trigger a `dbt_expectations.expect_column_values_to_be_in_set` test alert.

---

## ADR-023 — Author name normalisation via mapping seed

**Date:** 2026
**Status:** Active

**Context:** Author name variants exist across sources — e.g. `Hubert Selby` vs
`Hubert Selby Jr.`.

**Decision:** Create a seed `seeds/shared/author_name_mapping.csv` (columns:
`raw_name`, `canonical_name`) mapping variants to a canonical name.
Normalisation is applied in `int_books__unified` before cross-source matching.

**Rationale:**

- Prevents duplicate author entries in the mart layer.
- Manually maintainable and easily extensible.

**Trade-offs:** Requires periodic review of the seed as new authors are added.

---

## ADR-024 — Manual ratings via CSV seed (`manual_ratings.csv`)

**Date:** 2026
**Status:** Active

**Context:** Some items have no rating from any source but deserve a personal rating.
Two options evaluated:

1. CSV seed `manual_ratings.csv` → fallback join in the intermediate layer.
2. Frontend interface (Supabase form or custom app writing to BigQuery).

**Decision:** Option 1 — seed `seeds/shared/manual_ratings.csv` with columns:
`domain` (`books` | `movies` | `music` | `manga` | `anime` | `series`), `title`,
`author_or_director_or_artist`, `rating` (0–5), `rated_at` (ISO date).

In each intermediate model, the manual rating is used as a last-resort fallback:

```sql
COALESCE(source_rating, manual_rating) AS rating
```

**Rationale:**

- Simple, Git-versioned, auditable, and consistent with the "seeds for static reference"
  pattern already established in this project.
- No external dependency (no Supabase, no interface to maintain).
- Upgradable: if the list grows, migrate to a Supabase table with a lightweight interface —
  the intermediate models only need their `ref()` updated.

**Trade-offs:** Manual CSV editing (no GUI). Acceptable for a personal project with
a low volume of manual ratings.

---

## ADR-025 — Remove read/unread status from books

**Date:** 2026
**Status:** Active

**Context:** The `status = 'Read'` / `status = 'Unread'` distinction in
`mrt_books__collection` was used to filter read books. In practice, all books in the
collection are read (unread books are not entered).

**Decision:** Remove the `status` column from `mrt_books__collection` and from
`mrt_books__reading_history`. The `WHERE status = 'Read'` filter in
`mrt_books__reading_history` is dropped — all items are treated as read.

**Rationale:**

- Simplifies the mart layer and the dashboard.
- More accurately reflects the actual collection.

**Trade-offs:** If unread books are added in the future, the field must be
reintroduced. The decision is fully reversible.

---

## ADR-026 — French labels for genres, countries and content types in the warehouse

**Date:** 2026
**Status:** Active

**Context:** Genres, countries and content types appeared in the marts in English
(from CSV exports and the Spotify API). The dashboard is fully in French — the
inconsistency was visible in filters and charts.

**Decision:** French translation is applied in the **intermediate layer** via mapping
seeds (`genre_mapping.csv` for genres, and a new seed `seeds/shared/country_name_fr.csv`
for country names). Mart models expose French values directly.

**Rationale:**

- Single source of truth for all translations (seeds).
- The dashboard requires no client-side translation logic.

**Trade-offs:** Mapping seeds must be exhaustive. Unmapped values pass through in
English and trigger a `dbt_expectations.expect_column_values_to_be_in_set` test alert.
