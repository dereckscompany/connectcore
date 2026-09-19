# connectcore 0.5.4

**The README now follows the fleet's canonical shape: a plain-English lead, a fixed section order ending in Documentation, Citation and Licence.** Owner ruling 20 (2026-09-18) fixed one README shape for every package in the fleet; connectcore is reshaped into it without changing any existing wording. The lead paragraph's first sentence is now bold and unlabelled, the design-lessons section is renamed to Design philosophy with its bullets untouched, Installation keeps `renv::install()` as the primary path with `remotes::install_github()` as a commented fallback in the same code fence, and the README gains a Documentation section (the pkgdown site and the vignette ladder) and a Citation section built from `DESCRIPTION`. Quick start, Asynchronous usage and Error handling are the fleet's three optional canonical sections, and connectcore's README carries no standalone content for any of them today: the extension examples already fill Quick start's role, the sync/async split is already covered under Design philosophy, and there is no caller-facing error-handling walkthrough in the README to move, so all three are left out of this pass rather than filled with invented examples.

* `README.Rmd` reordered into the canonical shape: `## What we learned` renamed to `## Design philosophy` (content unchanged), `## Installation` gained a commented `remotes::install_github()` fallback in the same fence, a new `## Documentation` section names the pkgdown site, the `connectcore` vignette and `NEWS.md`, and a new `## Citation` section is built from `DESCRIPTION`'s `Authors@R`, `Title`, `Version` and repository URL. No R code, chunk options, `eval` flags or fixtures changed.
* `README.md` regenerated via `scripts/BUILD.sh readme`.
* `DESCRIPTION`: version bumped 0.5.3 -> 0.5.4.

# connectcore 0.5.3

**A prose sweep dropped a labelled documentation convention connectcore was the last package still carrying, and switched ten American spellings to British ones.** The README's "In plain terms:" lead paragraph was added deliberately nine weeks ago under the two-level documentation convention (commit 1be0696); every other connector's README has since converged on an unlabelled plain-English lead followed by "## Technical overview", so this brings connectcore in line with the rest of the fleet. NEWS.md's own 0.5.1 entry carried the matching "In plain English:" label, removed the same way. In both cases the sentence that followed the label is kept exactly as written; only the label itself is gone. Separately, a handful of words in the roxygen documentation, the README, the NEWS history, a CI workflow comment and in-body code comments were spelled the American way ("pre-serialized", "serialization", "color") or used the American section heading ("License"); these now read "pre-serialised", "serialisation", "colour" and "Licence", matching the rest of the fleet. No identifiers, argument names, URLs, or file names changed.

* 2 scaffolding labels removed: `README.Rmd` ("In plain terms:") and `NEWS.md` ("In plain English:").
* 10 spelling changes: `pre-serialized` -> `pre-serialised` (5 occurrences, in `R/RestClient.R`, `R/helpers_request.R` x2, `README.Rmd`, `NEWS.md`), `serialization` -> `serialisation` (3 occurrences, in `R/helpers_request.R` x2, `NEWS.md`), `color` -> `colour` (1 occurrence, in `.github/workflows/test-coverage.yaml`), and the `README.Rmd` "License" heading -> "Licence".
* Files touched: `DESCRIPTION`, `NEWS.md`, `R/RestClient.R`, `R/helpers_request.R`, `README.Rmd`, `README.md` (regenerated), `man/RestClient.Rd`, `man/build_request.Rd` (regenerated) and `.github/workflows/test-coverage.yaml` — 9 files.
* Remaining American-looking spellings in scope are deliberate exclusions, not misses: R6 `initialize`/`super$initialize()` method identifiers, the `serialize = FALSE` argument name in `R/auth.R`, the `fig.align = "center"` knitr chunk-option value, and quoted vendor fields, test fixtures, URLs and file names are not prose; the `artifacts` hits in `scripts/BUILD.sh` and `scripts/CLEANUP.sh` are template-managed (cookiecutter, pinned in `.cruft.json`) and are never edited inside a package.

# connectcore 0.5.2

**NEWS.md was missing its entire entry for the released v0.4.0 tag, because a three-way stacked-PR merge had folded that release's changes into the text of the following 0.5.0 entry.** The v0.4.0 tag shipped typed transport conditions, typed WebSocket lifecycle events, and a durable pkgdown build policy as one cascade-merged release, but the NEWS heading for that version was never written, so all three changes read as if they had shipped under 0.5.0 alongside the unrelated retry work. This reconstructs the missing 0.4.0 section from the three merged pull requests (#9, #10, #11) and leaves only the retry change under 0.5.0.

- `NEWS.md`: added the missing `# connectcore 0.4.0` heading between the 0.5.0 and 0.3.0 entries, moved the typed-conditions, WebSocket lifecycle-event, and pkgdown-build content there in the file's two-level form, and trimmed the 0.5.0 entry down to the retry change it actually shipped.
- Ran `pkgdown::check_pkgdown()` to confirm the site configuration is still sound after the NEWS reshuffle.

# connectcore 0.5.1

**A test fixture used a real captured timestamp instead of a made-up one, and the mock-harness documentation overstated where fixtures come from.** A test for the shared `ms_to_datetime()` helper hard-coded `1729159459033`, which is not an arbitrary number — it is the exact millisecond instant (2024-10-17T10:04:19.033 UTC) that also appears as a capture timestamp in the kucoin package's fixtures, meaning a test value and a real recorded moment were the same number. Separately, the roxygen docs for `mock_response()` and `load_fixtures()`, and a line in the README, described fixtures as "real captured" JSON — every fixture in this fleet is authored synthetic data, never a live capture, and the wording was simply wrong.

- `tests/testthat/test-utils_time.R`: replaced `1729159459033` (and its derived seconds/fractional forms) with `1767571200000` (2026-01-05T00:00:00.000 UTC), a fictional instant on a clean grid, across all four affected `test_that()` blocks.
- `R/mock.R`: reworded the `mock_response()` and `load_fixtures()` roxygen text from "real captured"/"a connector's captured fixtures" to "authored synthetic fixture files (never live captures; fleet rule ratified 2026-07-05)".
- `README.Rmd`: same wording correction in the "Testing your connector" section; regenerated `README.md` via `scripts/BUILD.sh readme`.
- `man/mock_response.Rd`, `man/load_fixtures.Rd`: regenerated via `scripts/BUILD.sh document`.
- `NEWS.md`: added a NOTE under the 0.2.0 entry that introduced `load_fixtures()` and `mock_response()`, pointing at this release for the corrected fixture-provenance wording (the historical entry's own text is left as written).

# connectcore 0.5.0

Request retry is now gated on **idempotency**, so opting into `max_tries > 1` can never make a write resend itself. Before, `build_request()` attached `req_retry` to any method once `max_tries > 1`; a caller who set `max_tries` for convenient backfill resilience would also have silently retried an order `POST` or a cancel `DELETE` on a transient blip — a resend that can double-submit. Retry is fundamentally safe only for an idempotent request, and in live trading the trader layer is the single retry authority (it routes by typed error class and manages cooldowns), so wrapper-level retries belong to research and backfill reads alone.

* **Idempotency-gated retry** — `build_request()` gains an `idempotent` argument (`scalar<logical>`, default `identical(toupper(method), "GET")`) and attaches `req_retry` only when `max_tries > 1` **and** `idempotent` is `TRUE`. By default this is exactly the GET-only carve-out — a non-`GET` verb is performed exactly once regardless of `max_tries`, so an order submission can never be silently resent — enforced in the one shared funnel, so every connector that extends `RestClient` inherits it. The parameter exists for the venue whose reads are POST (the query is encoded in the request body, e.g. Hyperliquid's `/info`): that read path may pass `idempotent = TRUE` to opt into retry, while a write (order submission, cancel) must **never** be marked idempotent. The retry-safety rule is stated in the `build_request()` `@details`.
* **Broadened transient set** — an auto-retried request now treats `408`, `429`, and any `5xx` as transient (previously httr2's default `429`/`503` only), and retries a connection-level failure (`retry_on_failure = TRUE`) — always safe to re-send for an idempotent request. `Retry-After` is honoured by httr2's default backoff. This makes the documented backfill contract ("retry on a timeout, a dropped connection, a 5xx, or a 429") actually true.
* **Backward compatible** — the default `max_tries = 1` still disables retry, and no existing error *message* changes. The only behavioural change lands on callers that already opted into `max_tries > 1` (e.g. `binance_backfill_klines()`, an idempotent GET): its retries now also cover `408`/`5xx`/connection failures, matching its own documentation.

# connectcore 0.4.0

**Three stacked pull requests landed together as this release: every transport failure now signals a typed condition instead of a bare message, a WebSocket client gained the same typed lifecycle surface, and the pkgdown documentation build gained a lockfile policy that will not quietly drop its own build tools.**

Typed conditions on every transport failure, so a caller branches on error type and reads structured fields instead of grepping the message string. When a REST call fails, the transport base used to throw a bare message with the HTTP status buried in the text; a caller who wanted to retry on 429 or re-auth on 401 had to regex the string, and there was no way to catch one failure class without catching all of them. `connectcore` is the base every connector extends, so a condition raised here is inherited fleet-wide — one place to fix.

* **Typed transport conditions** — the default response parser and the other transport abort sites now signal **classed conditions** ordered specific -> general, all sharing the `connectcore_error` root. See [`?connectcore_conditions`](https://dereckscompany.github.io/connectcore/reference/connectcore_conditions.html) for the class taxonomy and the connector-subclass recipe.
    * `abort_api_error(status, url, body, message)` — a non-2xx HTTP response (the default `parse_json_response()` envelope) signals `c("connectcore_api_error_<status>", "connectcore_api_error", "connectcore_error")`, carrying `status` (integer), `url`, and a truncated `body` as structured fields. The per-status class lets `tryCatch(connectcore_api_error_429 = ...)` catch one status; the family class catches every HTTP failure.
    * `abort_response_error(message, field, url, body)` — a response that parsed but is malformed or missing a field (e.g. a server-time payload lacking its key) signals `connectcore_response_error`.
    * `abort_stream_error(message, url)` — a `StreamClient` transport failure (e.g. `$send()` on a closed socket) signals `connectcore_stream_error`.
* **Backward compatible** — every existing error *message* is byte-identical to the bare `rlang::abort()` string it replaced, so tests and downstream greps that matched on message text keep working; the classes and fields are purely additive. Golden tests pin the byte-identity.
* **`scrub_url()`** — a URL stored on a condition (or logged) has the *value* of every credential-named query parameter (signature, apiKey, token, ...) redacted to `<redacted>`, so `e$url` never leaks a secret while preserving the path and benign parameters for debugging. Exported for connectors to reuse.

**Structured WebSocket lifecycle events** — the WebSocket analogue of the typed conditions, for a client whose error surface is asynchronous events rather than catchable throws (refs [dereckscompany/aisstream#3](https://github.com/dereckscompany/aisstream/issues/3)). Where a `StreamClient` used to hand a raw callback payload to each string-keyed `$on(event, ...)` handler, callers can now register a single `$on_event(handler)` that receives a **typed** object for every lifecycle transition, and branch on `event$event_type` reading fields as data.

* **`StreamClient$on_event(handler)`** — registers a handler that receives a typed `ws_event` object on every lifecycle transition: `open`, `message`, `close`, `error`, `reconnect` (see `WS_EVENT_TYPES`). Each event carries a lubridate UTC `timestamp` and per-type fields — `close` carries `code` + `reason`, `reconnect` carries `attempt` + `delay` (backoff seconds), `open` carries `reconnect` (was this a reconnect), `message` carries `data` (the frame text), `error` carries `error` (the socket error event).
* **Additive and zero-cost when unused** — the existing `$on()` callbacks fire exactly as before (verified against the two current consumers, `binance::BinanceWsBase` and `aisstream::AisStream`, which register no `$on_event()` handler and are unaffected), and the typed object — including its timestamp — is materialised only when at least one `$on_event()` handler is registered, so a parse-free recorder hot path stays free by default.
* **`ws_event(event_type, fields)`** and **`WS_EVENT_TYPES`** exported — the constructor a WebSocket connector uses to emit its own structured events (e.g. a parsed error frame), and the `event_type` value set to branch on instead of bare string literals.

**Durable pkgdown documentation build** (closes #5) — the docs workflow was prone to failing because the renv lockfile did not durably track the development tools the site build needs (pkgdown and the packages the vignettes load); a future `renv::snapshot()` under the old settings would silently drop them, reintroducing the htmltools `dyn.load` failure class. This adopts the proven binance recipe: `renv` settings `snapshot.dev: true` and `lockfile.sanitize: true`, `renv` upgraded 1.1.8 -> 1.2.3 (the `snapshot.dev` setting is a 1.2.x feature, so it must be recorded in the lock for CI's `setup-renv` to honour it), and the lockfile regenerated so it tracks the current dev tree. The regeneration adds the genuinely-needed dev dependencies (`roxygen2`, `brew`, `commonmark`, `stringr`) and sanitises 13 stale, unreachable entries (the `ggplot2` / `DT` / widget ecosystem, none of which connectcore, its vignette, or pkgdown use). The pkgdown workflow now builds with `install = TRUE`. Verified locally with `pkgdown::build_site()` completing (CI proof waits on the org's Actions billing).

# connectcore 0.3.0

Centralise the fleet-wide `ms_to_datetime()` measurement-time helper. Connectors parse raw JSON timestamp fields whose R type is not known ahead of time — a field is numeric when populated, character on some venues, and an all-`NA` logical when a batch of records came back empty — so the shared helper must be type-stable, length-preserving, and NA-in -> NA-out. connectcore already shipped an `ms_to_datetime()`, but it was the thin `as_datetime(as.numeric(ms) / 1000)` form: it warned on all-`NA` character input (the documented missing-value path), it was not runtime-typed, and an all-missing batch could collapse to a single `NA` that `data.table::set()` then recycles into a column's existing storage type rather than replacing it with a POSIXct one. This ports kucoin's hardened implementation — the fleet reference — as the single canonical copy, so each wrapper drops its local re-implementation as it converges.

* **`ms_to_datetime(ms)`** now accepts the raw JSON value untyped (`numeric`, `character`, or an all-`NA` logical), always returns a POSIXct/UTC vector whose length matches the input, maps `NULL`/`NA` to `NA`, stays silent on the all-`NA` missing-value path, and still surfaces the usual "NAs introduced by coercion" warning for a genuinely malformed string. The argument and return are runtime-checked with [roxyassert](https://github.com/dereckscompany/roxyassert).

* **Dependency and CI reconciliation** (fleet convergence, no behaviour change): `Config/roxygen2/version` pinned to `7.3.3` alongside `RoxygenNote`; a version floor added to `assert` in Imports and `roxyassert` in Suggests; the `roxyassert` Remote de-pinned to a bare repository entry (exact versions live in `renv.lock` per the ratified bare-Remotes-plus-Imports-floors policy); `withr` promoted from Suggests to Imports (the exported mock-harness activators `with_mock_api()`/`local_mock_api()` import it at run time, so R CMD check rightly required it as a hard dependency); the previously incomplete `renv.lock` now records the `assert`, `data.table`, `lubridate` and `websocket` runtime dependencies it was missing; and R-CMD-check (3-OS matrix) plus test-coverage now run on push and pull request rather than manual dispatch only, so the fleet's "merge on a green gate" rule is enforceable.

# connectcore 0.2.1

Fix a `StreamClient` open-check that silently broke every WebSocket stream. `.is_open()` compared `readyState()` to `1L` with `identical()`, but the `websocket` package returns an ATTRIBUTED integer (a named `OPEN = 1L`), so `identical()` was `FALSE` even when the socket was open. Every `send()` then aborted and `.resubscribe()` threw inside `onOpen` before the `"open"` event fired, so no subscription was ever sent and the stream received nothing (0-byte captures). Now compares by value (`== 1L`). Regression test added.

# connectcore 0.2.0

A shared **HTTP-mock test harness**, exported for connector packages to use in
their tests and vignettes. Every connector had hand-rolled a near-identical
`mock_router` (a response builder, a route table, and a dispatch loop, ~180 lines
each); this extracts that into one reusable toolkit and generalises it to cover
every routing style the connectors use. The harness mocks at httr2's **native**
global hook — `options(httr2_mock = ...)` — which intercepts both the synchronous
`req_perform()` and the asynchronous `req_perform_promise()`, so a connector's sync
and async paths render against the same fixtures with no extra wiring (this is the
reason for the native hook over vcr). No existing behaviour changes — this only
adds new exports. Migrating the connectors onto it is a follow-up per connector.

* **`mock_router(routes, response_builder = mock_response)`** — a factory returning
  the `function(req)` dispatcher. A route's `match` is **either** a string (a
  substring of `req$url` — the URL-pattern style of coinbase, alpaca, binance,
  kucoin) **or** a `function(req) -> logical` predicate that can read the URL,
  method, AND body (the body-routing style of hyperliquid). An optional `method`
  pins a route to a verb; a fixture may be a thunk (invoked **per request**, so a
  closure counter expresses **stateful** pagination) and may return a fully-built
  `httr2_response` (a 204 no-content, an error), which is **passed through**
  unchanged. An unmatched request raises `"Unmocked request: <method> <url>"`.

* **`mock_response(body, status = 200, headers = ...)`** — the response builder:
  returns an `httr2_response` unchanged, uses a single `character` body verbatim
  (the real-captured-JSON path), or JSON-encodes anything else
  (`auto_unbox = TRUE, null = "null", digits = NA`, matching the live wire).

* **`body_routes(url_filter, field_path, cases)`** + **`req_body_json(req)`** — make
  body-routed APIs ergonomic: `req_body_json()` parses `req$body$data` (raw,
  character, or an already-deserialised list) and `body_routes()` builds one
  predicate-route per named case (match when the URL contains `url_filter` and the
  body field at `field_path` equals the case name). Hyperliquid becomes
  `mock_router(c(body_routes("/exchange", c("action", "type"), .exchange_routes), body_routes("/info", "type", .info_routes)))`.

* **`with_mock_api(routes, code)`** / **`local_mock_api(routes, .env)`** — install
  `mock_router(routes)` as the `httr2_mock` option for a scope (via withr) and
  restore it afterwards; what a connector's tests and vignettes call instead of
  hand-setting the option.

* **`load_fixtures(dir, parse = FALSE)`** — read every `*.json` in a directory into
  a named list keyed by file basename; the value is the raw JSON string (pairs with
  `mock_response()`'s verbatim path) or the parsed list (`parse = TRUE`). How a
  connector loads its real captured fixtures into a route table.

  NOTE (added in 0.5.1): the fixtures this release describes are, and always
  were, authored synthetic files, never live captures. The "real captured"
  wording above and in the `mock_response()` entry further up this section is
  stale terminology; see the 0.5.1 entry for the corrected phrasing.

* **`jsonlite`** moves to Imports (the harness JSON-encodes/decodes bodies);
  `withr` (already a Suggest) backs the scoped activators.

# connectcore 0.1.0

Three additive fixes to the shared request funnel (`build_request()`), each a gap
surfaced by migrating the exchange connectors onto connectcore. The funnel was
extracted from a connector that signs the **query string** (not the body) and
talks to a **single host**, so a raw-body path, a per-call host override, and
multi-value query encoding were never exercised. Migrating venues that *do* need
them surfaced all three. Nothing existing changes behaviour — these only add new
capability or fix an encoding that silently regressed. The connector adoptions
themselves are separate follow-up PRs.

* **`body_format = "raw"`** — a new body encoding that sends a pre-serialised
  `character` (or `raw`) body **byte-verbatim** via `httr2::req_body_raw()`: no
  `NULL`-pruning, no pretty-printing, no re-encoding. The caller owns
  serialisation. Required by venues that cryptographically sign the *exact bytes*
  of the request body — kucoin (signs the **compact** JSON body, which
  pretty-printing would corrupt) and hyperliquid (signs the body and needs `null`
  fields **preserved**, which `req_body_json` drops). The `sign` seam runs
  **after** the body is set, so a body-signing `.sign()` can read the exact bytes
  off `req$body$data` and add the signature header. A `raw_content_type` argument
  (default `"application/json"`) sets the `Content-Type`. `"json"` / `"query"` /
  `"none"` are unchanged.

* **Per-request `base_url` override** — `RestClient`'s private `.request()` (and
  `build_request()`) takes an optional `base_url` that overrides the instance base
  for a single call (default `NULL` = instance base). For dual-host venues —
  coinbase routes between its Advanced Trade and Exchange hosts per request.
  `.request()` also accepts a per-call `body_format` (and `raw_content_type`) so a
  single signed endpoint can send a raw body even when the client's default is
  JSON.

* **Multi-value query params (`.multi = "explode"`)** — the query encoder now
  passes `.multi = "explode"` to `httr2::req_url_query()`, so a vector-valued
  entry repeats its key (`ids = c("A", "B")` → `ids=A&ids=B`), the standard REST
  convention. httr2 defaults to `.multi = "error"`, which aborts on any length > 1
  value; that silently regressed coinbase methods passing list-valued params.
  Scalar query values are unaffected.

# connectcore 0.0.1

Initial release. A shared transport base for R data-source connectors. It owns
**transport only** — no domain vocabulary, no domain dependencies — and is meant
to be installed and **extended** by connector packages rather than used on its
own. (The exported helpers and `StreamClient` do work standalone; `RestClient` is
extend-only, its request funnel being private.)

* **`RestClient`** — abstract REST base: synchronous or asynchronous (via
  `promises`), optional retry and client-side throttle, and one private
  `.request()` funnel every endpoint method delegates to. Venue specifics plug in
  by overriding two private seams — `.sign()` (authenticate a request) and
  `.parse_envelope()` (response → data, raise on error). The defaults are no-auth
  and "JSON body, error on non-2xx", so a simple public API works unextended.

* **`StreamClient`** — concrete, event-driven WebSocket base (`$on(event, handler)`,
  Node-style) with full-jitter auto-reconnect, keepalive, a silence watchdog, and
  proactive reconnect. Subclasses override `.dispatch()` (frame → events) and
  `.resubscribe()` (replay subscriptions); a recorder needs no subclass at all.

* **Helpers** — HMAC-query request signing (`hmac_query_sign()`), JSON →
  `data.table` coercion, epoch ↔ `POSIXct` conversion, environment-backed
  credential loading, and WebSocket backoff. Every argument and return is typed and
  runtime-checked with [roxyassert](https://github.com/dereckscompany/roxyassert).
