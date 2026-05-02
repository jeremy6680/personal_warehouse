#!/usr/bin/env bash
# Loads all personal_warehouse CSV exports into BigQuery raw_personal dataset.
# Safe to re-run: --replace overwrites existing tables each time.
# Usage: ./scripts/bq_load.sh [--dry-run]
set -euo pipefail

PROJECT="personal-warehouse-495013"
DATASET="raw_personal"
DATA_DIR="$(cd "$(dirname "$0")/.." && pwd)/data"

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "[dry-run] No tables will be loaded."
fi

declare -A SCHEMAS
SCHEMAS["goodreads"]="Book Id:STRING,Title:STRING,Author:STRING,Author l-f:STRING,Additional Authors:STRING,ISBN:STRING,ISBN13:STRING,My Rating:FLOAT,Average Rating:FLOAT,Publisher:STRING,Binding:STRING,Number of Pages:INTEGER,Year Published:INTEGER,Original Publication Year:INTEGER,Date Read:DATE,Date Added:DATE,Bookshelves:STRING,Bookshelves with positions:STRING,Exclusive Shelf:STRING,My Review:STRING,Spoiler:STRING,Private Notes:STRING,Read Count:INTEGER,Owned Copies:INTEGER"
SCHEMAS["bookbuddy"]=""
SCHEMAS["letterboxd"]=""
SCHEMAS["moviebuddy"]=""
SCHEMAS["musicbuddy"]=""

tables=("goodreads" "bookbuddy" "letterboxd" "moviebuddy" "musicbuddy")

for table in "${tables[@]}"; do
    csv_path="${DATA_DIR}/${table}.csv"

    if [[ ! -f "$csv_path" ]]; then
        echo "[SKIP] ${table}.csv not found at ${csv_path}"
        continue
    fi

    destination="${PROJECT}:${DATASET}.${table}"
    echo "Loading ${table} → ${destination} ..."

    if [[ "$DRY_RUN" == true ]]; then
        echo "[dry-run] bq load --source_format=CSV --skip_leading_rows=1 --autodetect --replace ${destination} ${csv_path}"
        continue
    fi

    bq load \
        --source_format=CSV \
        --skip_leading_rows=1 \
        --autodetect \
        --replace \
        "${destination}" \
        "${csv_path}"

    echo "  ✓ ${table} loaded"
done

echo ""
echo "Done. Run 'dbt build' to validate the full pipeline."
