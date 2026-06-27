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

* **`body_format = "raw"`** — a new body encoding that sends a pre-serialized
  `character` (or `raw`) body **byte-verbatim** via `httr2::req_body_raw()`: no
  `NULL`-pruning, no pretty-printing, no re-encoding. The caller owns
  serialization. Required by venues that cryptographically sign the *exact bytes*
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
