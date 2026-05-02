# PHP 8 — next session

## Status as of 2026-05-02 (commit `ac57c55`)

Mapbender 2.8 has been re-validated against **PHP 8.3.30** (the default
build arg is now `8.3` in `docker-compose.yml`; the prior round had
silently fallen back to PHP 7.4).

What we proved:
- All 711 first-party PHP files pass `php -l` under PHP 8.3.
- After hitting ~280 endpoints under an authenticated session, the PHP
  error log has **zero first-party deprecation entries** and **zero
  PHP-8-introduced fatals**. Only 2 fatals remain and both are
  intentional `Exception("Could not create WMC from DB/XML")` thrown by
  `WmcFactory` when the probe URL supplies no payload — pre-existing
  application behaviour, fires the same way under PHP 7.

What we did NOT prove (this is the gap before "and works"):
- No browser session was loaded — the OpenLayers UI, drag/zoom/edit was
  never touched.
- No POST / multipart round-trip — items #1–#5 below are still pending.
- DB is fresh & empty; the materialised search views (#6) don't exist.
- Vendored libs (dompdf, phpmailer-1.72, fpdf/fpdi) were left alone, so
  print PDF / mail / FPDI flows are unverified under PHP 8.

## Quick start the next session

```bash
cd /Users/jonas/Desktop/mach/Mapbender2.8
docker compose up -d web                                  # now defaults to PHP 8.3
# Reset password for root user (DB-loaded value is empty after fresh init):
HASH=$(docker exec mapbender28-web-1 php -r 'echo password_hash("root", PASSWORD_BCRYPT);')
docker exec mapbender28-db-1 psql -U mapbender -d mapbender \
  -c "UPDATE mb_user SET password='$HASH', is_active='t' WHERE mb_user_name='root';"
# Browse: http://localhost:8080/mapbender/   (root / root)
```

For a regression diff against the old engine:
```bash
PHP_VERSION=7.4 docker compose build --build-arg PHP_VERSION=7.4 web
```

Watch the live PHP log on the host: `tail -f log/php_errors.log`.

## What is intentionally NOT covered yet

These all need a real user at a browser plus, in some cases, populated
DB or deployment-specific config. Static lint is clean and the
no-arg/anonymous probes pass; remaining bugs would be runtime- or
data-dependent.

1. **WMS/WFS upload + capabilities ingest.** The form path
   (`mod_loadwms.php` POST, `mod_addWMS_server.php`,
   `mod_editWMS_Metadata.php`) returns 200 on the empty-body smoke test
   but no real Capabilities document was ever round-tripped into the DB.
   Pick a public WMS (e.g.
   `https://sgx.geodatenzentrum.de/wms_topplus_open?REQUEST=GetCapabilities&SERVICE=WMS&VERSION=1.1.1`)
   and walk through the GUI: load → save → call `mod_callMetadata` for
   that record. Expected hot spots: `class_wms.php` parsing, the
   `wfs_search_table`/`wms_search_table` materialised views (currently
   missing — see #6), and `class_iso19139::fillISO19139`.

2. **WMC save → load → render round-trip.** `mod_savewmc_server.php`
   returns the application's own "could not detect AJAX id" error, which
   is the client-side contract — needs a real WMC JSON payload and the
   ad-hoc AJAX envelope. Verify `mod_loadwmc_server.php?command=getCommands`
   then `getXML`/`saveAsTemplate`. The two remaining "Could not create
   WMC from DB/XML" Fatals in the log come from this path being probed
   without input.

3. **Print PDF generation.** `print/mod_printPDF.php` and
   `mod_printPDF_pdf.php` answer 200 with a 26-byte error JSON because
   no `conf=` print template exists. Drop `print_*.conf` into
   `http/print/conf/` and re-issue with `conf=portrait_a4.conf` (or
   whichever template you ship). The `class.pdf.php` shim for
   `set_magic_quotes_runtime` is in place; if Imagick is needed for
   `class_weldMaps2PNG_rotate.php`, the Dockerfile's `pecl install
   imagick` step is best-effort and may need the `--with-libgomp`
   workaround on ARM hosts.

4. **KML / GeoJSON upload + edit.** `mod_inputkml.php`, `mb_loadkml.php`
   and the digitize widget pipeline (`http/plugins/mb_digitize_widget.php`)
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
   - `http/extensions/JSON.php` — already converted to bracket-offset
     syntax in this round (was a hard parse error in 8.0+); the rest of
     the file works.

8. **`owsproxy_api/`** — Apache alias is now wired
   (`/owsproxy_api → /var/www/mapbender/owsproxy_api/http`) and the
   index responds 401 with the Digest challenge. Authenticated flow
   (probe with valid `PHP_AUTH_DIGEST` headers) still untested.

## What changed in this round

- `docker-compose.yml` default `PHP_VERSION` flipped from `7.4` to
  `8.3`, so `docker compose up --build` actually tests the target
  engine.
- 90 first-party files patched (commit `ac57c55`):
  - `utf8_encode/utf8_decode` → `mb_convert_encoding` (~25 files,
    paren-balanced + comment- and JS-aware).
  - `Gml_2/3_Factory` LSP signatures fixed; positional callers in
    `mod_linkedDataProxy.php` updated.
  - `count(non-array)` TypeErrors guarded (10 sites).
  - Auto-vivification (`$x->y = ...` on null) pre-initialised with
    `new stdClass()` (8 sites).
  - JSON.php curly-brace string offsets converted (would have been a
    hard parse error in 8.0+).
  - Bareword constants and `DateTime(NULL)` fixed; undefined-constant
    references guarded with `defined()` (CHARSET, LOG_JS,
    LOG_LEVEL_LIST, API_KEY, CKAN_GROUP_*).
  - `<?php` tag added to `mod_searchCSW_form.php`; `globalSettings.php`
    bootstrap added to `dyn_js.php` and `mod_admin.php` so `mb_log`
    property defaults can resolve.
  - Dynamic property declarations on `weldMaps2Image` and `syncCkan`.
  - `?? ''` added to ~60 string-builtin call sites that fired PHP 8.1+
    "Passing null to ..." deprecations.
  - Constructor-arg fixes for `mod_metadataWrite` (now passes the
    required 27th `searchMetadata` arg) and `mod_gazLayerObj_conf`
    (passes user_id to `wfs_conf::getallwfs()`).
  - Local `conf/{ckan,atomFeedClient,gazetteerSQL}.conf` created from
    `-dist` templates and gitignored.
- Apache `RedirectMatch` tightened so `/owsproxy/<sid>/<wms>/` rewriting
  no longer hijacks `/owsproxy_api/` paths (commit `70ae75f`).

## Anti-goals (still in force)

Do not re-run the bulk auto-vivification fix script across the tree
again. It already left some duplicate guards in `mod_callMetadata.php`
that the dedup pass cleaned up; running the original regex would
re-introduce them.

Do not refactor `class.pdf.php`, `class.ezpdf.php`, or `fpdf/fpdi.php`
beyond the targeted fixes — they are fossilised vendor code and
replacing the libraries (`dompdf` 3.x, FPDI 2.x) is the right move, not
patching.

Do not blanket-add `?? ''` across the tree. The current sweep was
driven by actually-firing log entries; speculative wraps can mask real
bugs and will diverge from the install's actual data shapes.
