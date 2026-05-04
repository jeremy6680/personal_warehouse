#!/usr/bin/env python3
"""
Fetches Spotify data (saved albums, saved tracks, followed artists) via the Spotify
Web API and writes them to BigQuery raw_personal as full-refresh loads.

Usage:
    python scripts/spotify_to_bq.py [--dry-run] [--table TABLE]

Options:
    --dry-run          Fetch data but skip BigQuery writes (safe to run anytime)
    --table TABLE      Sync a single table: saved_albums | saved_tracks | followed_artists

Environment variables (see .env.example):
    SPOTIFY_CLIENT_ID
    SPOTIFY_CLIENT_SECRET
    SPOTIFY_REDIRECT_URI
    GOOGLE_APPLICATION_CREDENTIALS   Path to GCP service account JSON
    BQ_PROJECT                       Default: personal-warehouse-495013
    BQ_DATASET                       Default: raw_personal
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).parent.parent / ".env")

import spotipy
from spotipy.oauth2 import SpotifyOAuth
from google.cloud import bigquery

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

BQ_PROJECT = os.getenv("BQ_PROJECT", "personal-warehouse-495013")
BQ_DATASET = os.getenv("BQ_DATASET", "raw_personal")

# Token cache lives at project root (one level up from scripts/); git-ignored.
_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CACHE_PATH = os.path.join(_SCRIPT_DIR, "..", ".spotify_cache")

SCOPES = "user-library-read user-follow-read"


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------

def get_spotify_client() -> spotipy.Spotify:
    """Build a Spotipy client. Handles OAuth2 token refresh via cache file."""
    for var in ("SPOTIFY_CLIENT_ID", "SPOTIFY_CLIENT_SECRET", "SPOTIFY_REDIRECT_URI"):
        if not os.getenv(var):
            sys.exit(f"[error] Missing required env var: {var}")

    auth_manager = SpotifyOAuth(
        client_id=os.environ["SPOTIFY_CLIENT_ID"],
        client_secret=os.environ["SPOTIFY_CLIENT_SECRET"],
        redirect_uri=os.environ["SPOTIFY_REDIRECT_URI"],
        scope=SCOPES,
        cache_path=CACHE_PATH,
    )
    return spotipy.Spotify(auth_manager=auth_manager)


# ---------------------------------------------------------------------------
# Fetchers
# ---------------------------------------------------------------------------

def _now_utc() -> str:
    return datetime.now(timezone.utc).isoformat()


def fetch_saved_albums(sp: spotipy.Spotify) -> list[dict]:
    """
    Fetch all user-saved albums (offset pagination, 50 per page).

    Note: album.genres is almost always empty in the Spotify API — genres are
    stored on Artist objects, not Album objects. The column is kept for
    completeness but will typically be '[]'. Enrich via followed_artists if needed.
    """
    rows = []
    limit = 50
    offset = 0
    extracted_at = _now_utc()

    while True:
        batch = sp.current_user_saved_albums(limit=limit, offset=offset)
        for item in batch["items"]:
            album = item["album"]
            rows.append({
                "album_id": album["id"],
                "name": album["name"],
                "artists": ", ".join(a["name"] for a in album["artists"]),
                "artist_ids": json.dumps([a["id"] for a in album["artists"]]),
                "release_date": album.get("release_date"),
                "release_date_precision": album.get("release_date_precision"),
                # Typically empty — see docstring above
                "genres": json.dumps(album.get("genres", [])),
                "total_tracks": album["total_tracks"],
                "added_at": item["added_at"],
                "_extracted_at": extracted_at,
            })
        if not batch["next"]:
            break
        offset += limit

    return rows


def fetch_saved_tracks(sp: spotipy.Spotify) -> list[dict]:
    """
    Fetch all user-saved tracks (offset pagination) and enrich with audio features.

    Audio features (/audio-features) were deprecated by Spotify in November 2024
    for new developer applications. The enrichment step is attempted but silently
    skipped if the endpoint returns no data — all feature columns will be NULL.
    """
    rows = []
    track_ids = []
    limit = 50
    offset = 0
    extracted_at = _now_utc()

    while True:
        batch = sp.current_user_saved_tracks(limit=limit, offset=offset)
        for item in batch["items"]:
            track = item["track"]
            if track is None or track.get("id") is None:
                # Local files have no Spotify ID — skip
                continue
            rows.append({
                "track_id": track["id"],
                "name": track["name"],
                "artists": ", ".join(a["name"] for a in track["artists"]),
                "artist_ids": json.dumps([a["id"] for a in track["artists"]]),
                "album_id": track["album"]["id"],
                "album_name": track["album"]["name"],
                "duration_ms": track["duration_ms"],
                "explicit": track.get("explicit", False),
                "popularity": track.get("popularity"),
                "added_at": item["added_at"],
                # Audio features — filled in below; NULL if endpoint unavailable
                "danceability": None,
                "energy": None,
                "valence": None,
                "tempo": None,
                "acousticness": None,
                "instrumentalness": None,
                "liveness": None,
                "speechiness": None,
                "_extracted_at": extracted_at,
            })
            track_ids.append(track["id"])
        if not batch["next"]:
            break
        offset += limit

    # Enrich with audio features in batches of 100
    features_map: dict[str, dict] = {}
    try:
        for i in range(0, len(track_ids), 100):
            batch_features = sp.audio_features(track_ids[i : i + 100])
            for f in batch_features or []:
                if f:
                    features_map[f["id"]] = f
    except Exception as exc:
        # Endpoint may be unavailable — proceed without features
        print(f"  [warn] Audio features unavailable ({exc}); feature columns will be NULL.")

    for row in rows:
        f = features_map.get(row["track_id"])
        if f:
            row.update({
                "danceability": f.get("danceability"),
                "energy": f.get("energy"),
                "valence": f.get("valence"),
                "tempo": f.get("tempo"),
                "acousticness": f.get("acousticness"),
                "instrumentalness": f.get("instrumentalness"),
                "liveness": f.get("liveness"),
                "speechiness": f.get("speechiness"),
            })

    return rows


def fetch_followed_artists(sp: spotipy.Spotify) -> list[dict]:
    """
    Fetch all followed artists (cursor-based pagination, 50 per page).

    Genres are reliable on Artist objects — unlike albums.
    """
    rows = []
    after = None
    limit = 50
    extracted_at = _now_utc()

    while True:
        batch = sp.current_user_followed_artists(limit=limit, after=after)
        artists_page = batch["artists"]
        for artist in artists_page["items"]:
            rows.append({
                "artist_id": artist["id"],
                "name": artist["name"],
                "genres": json.dumps(artist.get("genres", [])),
                "popularity": artist.get("popularity"),
                "followers": (artist.get("followers") or {}).get("total"),
                "_extracted_at": extracted_at,
            })
        cursors = artists_page.get("cursors") or {}
        if not cursors.get("after"):
            break
        after = cursors["after"]

    return rows


# ---------------------------------------------------------------------------
# BigQuery writer
# ---------------------------------------------------------------------------

def write_to_bq(
    client: bigquery.Client,
    table_id: str,
    rows: list[dict],
    dry_run: bool = False,
) -> None:
    if dry_run:
        print(f"  [dry-run] Would write {len(rows)} rows to {table_id}")
        return

    job_config = bigquery.LoadJobConfig(
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        autodetect=True,
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
    )
    job = client.load_table_from_json(rows, table_id, job_config=job_config)
    job.result()
    print(f"  ✓ {len(rows)} rows written to {table_id}")


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------

TABLES: dict[str, callable] = {
    "saved_albums": fetch_saved_albums,
    "saved_tracks": fetch_saved_tracks,
    "followed_artists": fetch_followed_artists,
}


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Sync Spotify library data to BigQuery raw_personal."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Fetch data but skip BigQuery writes.",
    )
    parser.add_argument(
        "--table",
        choices=list(TABLES.keys()),
        help="Sync a single table only.",
    )
    args = parser.parse_args()

    sp = get_spotify_client()
    bq_client = bigquery.Client(project=BQ_PROJECT)

    tables_to_run = (
        {args.table: TABLES[args.table]} if args.table else TABLES
    )

    for table_name, fetch_fn in tables_to_run.items():
        bq_table = f"{BQ_PROJECT}.{BQ_DATASET}.spotify_{table_name}"
        print(f"Fetching spotify_{table_name}...")
        rows = fetch_fn(sp)
        print(f"  → {len(rows)} rows fetched")
        write_to_bq(bq_client, bq_table, rows, dry_run=args.dry_run)

    print("\nDone. Run 'dbt build --select tag:spotify' to rebuild staging models.")


if __name__ == "__main__":
    main()
