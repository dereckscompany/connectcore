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
