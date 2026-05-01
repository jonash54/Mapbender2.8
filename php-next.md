# PHP 8 — next session

## Status as of 2026-05-01 (commit `ac6ae05`)

Mapbender 2.8 runs cleanly on the Docker stack with PHP 8.3.30. Verified
against ~80 endpoints across `http/`, `owsproxy/`, `cors_proxy/`,
`http_auth/`, and the geoportal-RLP subtree:
- `php -l` is clean across all first-party files (excludes
  `http/extensions/`, `http/fpdf/`, `http/classes/phpmailer*`).
- `log/php_errors.log` is empty under exercise of every endpoint that has a
  reasonable no-arg/anonymous path and every admin GUI plus the
  authenticated metadata/print/proxy flows.
- The two remaining warnings — `pg_query: ERROR: relation "gazetteer" /
  "mb_metadata" does not exist` — are baseline DB schema gaps in the fresh
  install, not code bugs.

## Quick start the next session

```bash
cd /Users/jonas/Desktop/mach/Mapbender2.8
PHP_VERSION=8.3 docker compose up -d web
# Reset password for root user (the DB-loaded value is empty after fresh init):
HASH=$(docker exec mapbender28-web-1 php -r 'echo password_hash("root", PASSWORD_BCRYPT);')
docker exec mapbender28-db-1 psql -U mapbender -d mapbender \
  -c "UPDATE mb_user SET password='$HASH', is_active='t' WHERE mb_user_name='root';"
# Browse: http://localhost:8080/mapbender/   (root / root)
```

Watch the live PHP log on the host: `tail -f log/php_errors.log`.

## What is intentionally NOT covered yet

These all need a populated DB or a deployment-specific config to actually
exercise. Static lint is clean on every one of them; remaining bugs would
be runtime-/data-dependent.

1. **WMS/WFS upload + capabilities ingest.** The form path (`mod_loadwms.php`
   POST, `mod_addWMS_server.php`, `mod_editWMS_Metadata.php`) returns 200 on
   the empty-body smoke test but I never round-tripped a real Capabilities
   document into the DB. Pick a public WMS (e.g.
   `https://sgx.geodatenzentrum.de/wms_topplus_open?REQUEST=GetCapabilities&SERVICE=WMS&VERSION=1.1.1`)
   and walk through the GUI: load → save → call `mod_callMetadata` for that
   record. Expected hot spots: `class_wms.php` parsing, the
   `wfs_search_table`/`wms_search_table` materialised views (currently
   missing — see #6), and `class_iso19139::fillISO19139`.

2. **WMC save → load → render round-trip.** `mod_savewmc_server.php` returns
   the application's own "could not detect AJAX id" error, which is the
   client-side contract — needs a real WMC JSON payload and the ad-hoc
   AJAX envelope. Verify `mod_loadwmc_server.php?command=getCommands` then
   `getXML`/`saveAsTemplate`.

3. **Print PDF generation.** `print/mod_printPDF.php` and
   `mod_printPDF_pdf.php` answer 200 with a 26-byte error JSON because no
   `conf=` print template exists. Drop `print_*.conf` into
   `http/print/conf/` and re-issue with `conf=portrait_a4.conf` (or
   whichever template you ship). The `class.pdf.php` shim for
   `set_magic_quotes_runtime` is in place; if Imagick is needed for
   `class_weldMaps2PNG_rotate.php`, the Dockerfile's `pecl install imagick`
   step is best-effort and may need the `--with-libgomp` workaround on
   ARM hosts.

4. **KML / GeoJSON upload + edit.** `mod_inputkml.php`, `mb_loadkml.php` and
   the digitize widget pipeline (`http/plugins/mb_digitize_widget.php`)
   were never round-tripped against a real file. Try uploading
   `mapserver/data/test.kml` or any small KML through the digitize tab in
   the `gui_digitize` GUI.

5. **OGC API Features path.** `http_auth/http/index.php` has the
   `case 'ogcapifeatures':` branch; only the no-arg root was hit. With a
   real `wfsId` and an `ogcapifeatures` `SERVICETYPE`, exercise
   `mod_featuretypeISOMetadata.php` and the OAF subroutines in
   `http/classes/class_wfs_2_0_factory.php`.

6. **Materialised search views (`*_search_table`, `mb_metadata`,
   `gazetteer`, `search_application_view`).** The fresh install does not
   create them. Either:
   - run `resources/db/update.sh` against the running container's DB to
     pull in the materialised view DDL, or
   - paste the relevant `CREATE MATERIALIZED VIEW` statements from
     `resources/db/*.sql` and `REFRESH MATERIALIZED VIEW` once.
   Until that's done the catalogue search returns empty results and the
   `pg_query: relation "x" does not exist` warnings keep firing.

7. **Vendored libraries with known PHP 8 patterns I deliberately left
   alone.**
   - `http/extensions/dompdf/*` — auto-vivification patterns similar to
     what we fixed in first-party code. Best path is `composer require
     dompdf/dompdf:^3` rather than patching the vendored copy.
   - `http/classes/phpmailer-1.72/` (alongside the modern 6.0.2). The
     1.72 copy is referenced by some old admin pages; either delete it
     and migrate the callers to 6.0.2, or vendor 5.x as a transitional
     copy.
   - `http/fpdf/fpdi.php` — only the `each()` call site was patched.

8. **Deprecated string-builtins called with null.** Still present in the
   tree but only fire when the caller passes null:
   `utf8_encode/utf8_decode` (deprecated 8.2 — `class_administration.php`,
   `class_wfs.php`); a handful of `strtolower/preg_match` sites uncovered
   by `grep -rn 'strtolower\|preg_match' http/classes | grep -v '?? '`.
   Not fatal, but a periodic `?? ''` sweep would silence them.

9. **`owsproxy_api/`** has no Apache alias yet. To exercise it, add
   `Alias /owsproxy_api /var/www/mapbender/owsproxy_api/http` to
   `docker/apache-mapbender.conf` and restart, then probe the index
   (currently never lint-failed because it consists of only one short
   `index.php`).

## Observations for the next pass

- The fix script at `/tmp/fix_php8.py` (and dedup at `/tmp/dedup_php8.py`)
  are still on disk. They handle two pitfalls already learned:
  - the LHS regex needs `=(?!=)` to avoid matching comparisons, and
  - the "already-guarded" pre-seed regex must capture the bracketed key
    completely (use a balanced/lazy match for the key inside `isset(...)`).
- Login to the docker stack: the install script leaves `mb_user_password`
  empty; bcrypt-hash any password and write it into the `password`
  column to authenticate.
- `core/globalSettings.php` does `session_name()` + `session_start()` near
  the top, so any file that includes it must do so *before* emitting any
  output. There were three offenders this round; check any new geoportal-
  style files for the same pattern (raw `<html>` before the `<?php`
  block).

## Anti-goals

Do not re-run the bulk auto-vivification fix script across the tree
again. It already left some duplicate guards in `mod_callMetadata.php`
that the dedup pass cleaned up; running the original regex would
re-introduce them.

Do not refactor `class.pdf.php`, `class.ezpdf.php`, or `fpdf/fpdi.php`
beyond the targeted fixes — they are fossilised vendor code and replacing
the libraries (`dompdf` 3.x, FPDI 2.x) is the right move, not patching.
