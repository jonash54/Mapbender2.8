# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Mapbender 2.8 — a PHP/JavaScript geoportal/web-mapping framework (OGC WMS/WFS/WMC client + admin) backed by PostgreSQL/PostGIS. This is the legacy "Mapbender2" line (not Mapbender3/Symfony). Version constant `MB_VERSION_NUMBER = "2.8trunk"` is set in `core/system.php`.

There is no build system, no package manager, and no automated test suite. Development is "edit PHP/JS in place, reload in browser."

## Setup / Common operations

- **Install / DB bootstrap:** `cd resources/db && ./install.sh <HOST> <PORT> <DBNAME> <DBTEMPLATE> <DBUSER>` (creates the Mapbender PostgreSQL/PostGIS database and compiles `.mo` translation files). Windows equivalent: `install.bat`.
- **Update an existing install:** `resources/db/update.sh` (or `update.bat`).
- **Config:** copy `conf/mapbender.conf-dist` → `conf/mapbender.conf` (the install script does this) and edit DB credentials. Many other features use `conf/*.conf-dist` → `conf/*.conf` overrides — never edit the `-dist` files in place.
- **Web root:** Apache must alias `/mapbender` → `http/`. Entry point is `http/index.php`; the application UI lives under `http/frames/`.
- **Setup check:** move `tools/mapbender_setup.php` into `http/tools/` and visit `http://localhost/mapbender/tools/mapbender_setup.php` — it verifies DB connection, PostGIS, and PHP extensions. Remove it when done (it leaks system info).
- **i18n:** enable via `define("USE_I18N", true)` and `define("LANGUAGE", "de")` in `mapbender.conf`. To rebuild a locale: `msgfmt resources/locale/<lang>/LC_MESSAGES/Mapbender.po -o resources/locale/<lang>/LC_MESSAGES/Mapbender.mo`.
- **Permissions:** `log/` and `http/print/tmp/` must be writable by the web-server user/group.
- **Default login after install:** `root` / `root` — change immediately.

## Architecture

The codebase follows a pre-framework PHP layout: top-level directories are roles, not modules.

- `core/` — bootstrap. `system.php` is included by every entry point; it loads `conf/mapbender.conf`, defines version/log/EPSG constants, and sets `MODULE_SEARCH_PATHS` (the JS module resolution list, including `OpenLayers-2.9.1`). `globalSettings.php`, `i18n.php`, `epsg.php`, `httpRequestSecurity.php` are also pulled in here.
- `conf/` — runtime configuration. Each feature ships a `*.conf-dist` template; the live file (without `-dist`) is what gets read.
- `http/` — the public document root.
  - `http/index.php`, `http/frames/` — top-level portal/frameset/login pages.
  - `http/php/` — server-side endpoints. Naming convention: `mod_*.php` are AJAX/RPC endpoints called by JS modules; `mb_*.php` are Mapbender-internal services (session validation, WMC load/save, KML/GeoJSON conversion, etc.). Each endpoint includes `core/system.php` and talks to the DB via `lib/database-pgsql.php`.
  - `http/javascripts/` — client modules. Some files are `.php` but emit JavaScript (server-side templating of JS) — e.g. `core.php`, `map.php`, `gui.php`. The dynamic-JS endpoints are referenced in `MODULES_NOT_RELYING_ON_GLOBALS` in `core/system.php` when they don't depend on the legacy global-state model.
  - `http/classes/` — domain classes (`class_*.php`), one class per file, manually `require_once`d. Heavy areas: OGC services (`class_wms*`, `class_wfs*`, `class_csw*`, `class_wmc*`), geometry/format (`class_gml*`, `class_kml*`, `class_geojson*`, `class_georss*`), metadata (`class_iso19139.php`, `class_metadata*`), logging (`class_mb_exception.php`, `class_mb_log.php`, `class_mb_notice.php`, `class_mb_warning.php`), and image composition (`class_weldMaps2*`, `class_weldOverview2*`, `class_weldLegend2PNG.php`).
  - `http/extensions/` — vendored third-party JS/PHP libs (OpenLayers 2.x, jQuery 1.x + many UI versions, DataTables, dompdf, fpdf, leaflet, proj4js, raphael, JSON-Schema, etc.). Multiple parallel versions are intentional — different modules pin different ones; do **not** consolidate without checking every reference.
  - `http/widgets/`, `http/plugins/`, `http/include/`, `http/print/`, `http/sld/`, `http/geoportal/`, `http/html/`, `http/css/`, `http/img/` — UI assets and feature subsystems.
  - `http/tmp/` — runtime scratch (PDFs, welded images, KML uploads).
- `lib/` — shared helpers shared between `http/` and proxies. Notably `database-pgsql.php` (the DB layer), `class_Mapbender.php`, `class_Mapbender_session.php`, `class_GetApi.php`, `class_OgcFilter.php`, `spatial_security.php`, plus a pile of UI JS (`button*.js`, `wizard*.js`, `customTree*.js`).
- `owsproxy/`, `owsproxy_api/`, `cors_proxy/`, `http_auth/` — separate web-aliased entry points (each contains its own `http/` subtree). The OWS proxy mediates outbound OGC requests for access control/logging; configured in Apache via `Alias /owsproxy ...` and a `RedirectMatch` rule (see `Install.txt`).
- `mapserver/` — example MapServer mapfile (`spatial_security.map`) plus GML test fixtures.
- `resources/db/` — SQL dumps and shell scripts for install/update. Reference data, default GUIs (`gui_*.sql`), admin metadata, and materialized-view definitions live here.
- `resources/locale/<lang>/LC_MESSAGES/Mapbender.po|.mo` — gettext translations.
- `tools/` — assorted maintenance scripts (including `mapbender_setup.php`); not web-served by default.
- `log/` — runtime log target.

### Data flow at a glance

Browser → `http/frames/index.php` (GUI shell) → loads JS modules from `http/javascripts/` (some statically, some templated through `*.php`) → JS modules POST to `http/php/mod_*.php` / `mb_*.php` → endpoints use classes from `http/classes/` and `lib/` and read/write PostgreSQL via `lib/database-pgsql.php`. OGC traffic to remote services is funneled through `owsproxy/` for access control.

### Conventions to be aware of

- Code style is procedural PHP 5-era with global state (`$_SESSION`, globals). `core/system.php` lists the modules that opted out of that pattern in `MODULES_NOT_RELYING_ON_GLOBALS`.
- Class files are named `class_<name>.php` and contain a single class; loading is manual `require_once`, not autoloaded.
- Several files have `~` backup siblings (`class_cache.php~`, `class_iso19139.php~`, `class_wfs_factory.php~`) — these are stale editor backups, not active code.
- `*-dist` files in `conf/` and `resources/` are templates; modify the non-`-dist` copy.
- Multiple jQuery and OpenLayers versions coexist intentionally (see `http/extensions/`); pick the version a given module already uses rather than upgrading globally.
