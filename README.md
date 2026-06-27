
# connectcore

<!-- badges: start -->

<!-- badges: end -->

A shared transport base for R data-source connectors. It owns
**transport only** — no domain vocabulary, no domain dependencies. You
build a connector by extending two base classes and supplying what is
genuinely source-specific; everything else is inherited.

It is mostly a place to put what building a stack of these connectors
taught us, so the next one starts with the lessons already baked in.

## What we learned

- **One codebase for sync and async — not two.** Route every result
  through a single branch point (`then_or_now()`), write methods
  mode-agnostically, and choose sync or async once at construction.
  `RestClient` is mode-transparent.

- **Keep the request funnel private; expose only typed endpoint
  methods.** Every call flows through one `private$.request()`, so
  signing, the error envelope, retry, and throttle live in one place
  instead of scattered across endpoints. The funnel covers the awkward
  cases too: `body_format = "raw"` sends a pre-serialized body
  **byte-verbatim** (for venues that sign the exact body bytes — no
  `NULL`-pruning or pretty-printing), and `.request(base_url = ...)`
  overrides the host for a single call (for dual-host venues).

- **Only two things are genuinely venue-specific: how you authenticate,
  and how you read an error.** Make exactly those two overridable seams
  — `.sign()` and `.parse_envelope()` — with sane defaults (no-auth,
  error on non-2xx). A simple public API then needs no overrides at all.

- **WebSockets fail silently.** `onClose` does not always fire, so a
  dead socket looks alive. You need a silence watchdog (force-reconnect
  after N seconds quiet), full-jitter backoff (or a reconnect storm
  trips the server’s rate limit), and proactive reconnect (to beat a
  forced cutoff). `StreamClient` does all of this; subclass it only to
  classify frames into your own events.

- **Coerce JSON once, centrally.** Flat `data.table`s, snake_case names,
  no list columns — from a shared toolkit, not hand-rolled per endpoint.

- **Type every argument and return.**
  [roxyassert](https://github.com/dereckscompany/roxyassert) contracts
  fail loudly at the boundary, instead of letting a malformed value
  surface three calls later.

## Installation

This package uses [renv](https://rstudio.github.io/renv/); install it
into the project library:

``` r
renv::install("dereckscompany/connectcore")
```

## Extending the REST base

Subclass `RestClient`, override the two seams (or neither, for a public
API), and add endpoint methods over the private funnel:

``` r
library(connectcore)

MyClient <- R6::R6Class(
  "MyClient",
  inherit = connectcore::RestClient,
  public = list(
    initialize = function(keys = NULL, base_url = "https://api.example.com") {
      super$initialize(keys = keys, base_url = base_url, body_format = "query")
    }
  ),
  private = list(
    # Authenticate by delegating to the shared HMAC-query helper.
    .sign = function(req, keys, ctx) {
      connectcore::hmac_query_sign(req, keys, ctx$get_timestamp_ms)
    }
  )
)

client <- MyClient$new()
client$is_async
#> [1] FALSE
```

## Extending the WebSocket base

A recorder needs no subclass — register a handler and run the loop:

``` r
ws <- StreamClient$new("wss://stream.example.com", stale_timeout = 120)
ws$on("open", function(e) ws$send('{"subscribe": "all"}'))
ws$on("message", function(msg) cat(msg, "\n"))
ws$run() # keeps the process alive and pumps the event loop
```

The reconnect backoff is full-jitter exponential and capped, so a
reconnect storm can never trip a server’s connection rate limit:

``` r
vapply(1:5, function(attempt) ws_backoff_delay(attempt, cap_seconds = 60), numeric(1))
#> [1]  1  1  5  7 23
```

## Testing your connector

httr2 has a native global mock hook — `options(httr2_mock = ...)` — that
intercepts **both** the synchronous `req_perform()` and the asynchronous
`req_perform_promise()`. connectcore ships a small harness over it, so a
connector renders its docs and runs its suite against canned fixtures
with no network, no credentials, and no funds (and the async path is
covered by the very same router).

Define a route table and wrap your code in `with_mock_api()`:

``` r
library(connectcore)

routes <- list(
  list(match = "/time", fixture = function() list(epoch = 1700000000), method = NULL),
  list(match = "/products", fixture = function() list(list(id = "BTC-USD")), method = "GET")
)

with_mock_api(routes, {
  resp <- httr2::req_perform(httr2::request("https://api.example.com/time"))
  httr2::resp_body_json(resp)$epoch
})
#> [1] 1700000000
```

A route’s `match` is **either** a string (matched as a substring of the
request URL — the style coinbase, alpaca, binance, and kucoin use)
**or** a `function(req)` predicate that can read the URL, method, and
body. Body-routed APIs (e.g. Hyperliquid, whose whole REST surface sits
behind `/info` and `/exchange`, keyed by a body field) are built with
`body_routes()`:

``` r
mock_router(c(
  body_routes("/exchange", c("action", "type"), exchange_routes),
  body_routes("/info", "type", info_routes)
))
```

A fixture is invoked **per request**, so a counter in its closure
expresses a stateful route (paginate: page 1, then an empty page); and a
fixture may return a fully-built `httr2_response` (a 204 no-content, an
error), which is passed through unchanged. `mock_response()` builds a
response from a list (JSON-encoded), a verbatim JSON string, or an
existing response; `load_fixtures(dir)` reads a directory of real
captured `*.json` into a named route table; and `local_mock_api()` is
the `withr::local_*` companion for use inside a `test_that()` block.

## License

MIT
