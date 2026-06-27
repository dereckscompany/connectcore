
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
#> [1]  1  2  5  3 23
```

## License

MIT
