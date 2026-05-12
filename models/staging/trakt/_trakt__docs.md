{% docs trakt_rating_scale %}

Trakt stores personal ratings as integers from 1 to 10. The ingestion script
preserves that value as `rating_raw` and also writes `rating = rating_raw / 2`
so warehouse models keep the project-wide 0 to 5 personal rating scale.

{% enddocs %}
