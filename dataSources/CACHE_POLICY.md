# Cache policy

This site is currently published from GitHub Pages. GitHub Pages does not let this repository define per-file HTTP cache headers in a way that is reliably applied in production.

The `_headers` file in this folder is therefore a target policy for a future host or CDN that supports custom response headers.

## Current strategy

- HTML entry pages should stay fresh and be revalidated.
- Heavy static media should be cached for a long time once URLs are versioned.
- If a media file changes and keeps the same name, cache duration should stay moderate.

## Recommended headers

For HTML entry pages:

```http
Cache-Control: no-cache
```

For static media without URL versioning:

```http
Cache-Control: public, max-age=2592000
```

For static media with URL versioning or file renaming on each content change:

```http
Cache-Control: public, max-age=31536000, immutable
```

## Versioning rule

When a media file changes, rename it.

Examples:

- `openStreetViewcarte.v20260801.jpg`
- `fond1.v20260801.webm`
- `corneille2.v20260801.webm`

This avoids stale browser caches on GitHub Pages and makes future long-lived caching safe on a CDN or another host.

## Files concerned in this project

- `index.html`
- `mobile.html`
- `diaporama/index.html`
- `openStreetViewcarte.jpg`
- `data/*`
- `background/*`
- `song/*`
