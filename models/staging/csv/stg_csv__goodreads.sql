select
    cast(`Book Id` as string) as book_id,
    trim(`Title`) as title,
    trim(`Author`) as author,
    safe_cast(trim(cast(`Year Published` as string)) as int64) as year_published,
    trim(`Publisher`) as publisher,
    nullif(
        regexp_replace(`ISBN`, r'^="?|"$', ''),
        ''
    ) as isbn,
    safe_cast(trim(cast(`My Rating` as string)) as int64) as my_rating
from {{ source('csv', 'goodreads') }}