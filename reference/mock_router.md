# Build a mock HTTP router (an `httr2` mock hook)

A factory returning a `function(req)` suitable for
`options(httr2_mock = ...)`. The router walks `routes` in order and
returns the first match. A route's matcher is its `match` field if
present, else its `pattern` field (the back-compat name the existing
connector tables use). The matcher is **either**:

- a `scalar<character>` – matched as a substring of `req$url`
  (`grepl(match, req$url, fixed = TRUE)`); the URL-pattern style used by
  coinbase, alpaca, binance, and kucoin; **or**

- a `function(req) -> logical` – an arbitrary predicate that may read
  the URL, method, AND body, for body-routed APIs (Hyperliquid; see
  [`body_routes()`](https://dereckscompany.github.io/connectcore/reference/body_routes.md)).

## Usage

``` r
mock_router(routes, response_builder = mock_response)
```

## Arguments

- routes:

  (list) a list of routes. Each route is a
  `list(match = <scalar<character> | function>, fixture = <function | value>, method = <scalar<character> | NULL>)`.
  A route may name its matcher `pattern` instead of `match` (the
  connectors' existing tables do). (Lists of routes, e.g. from
  [`body_routes()`](https://dereckscompany.github.io/connectcore/reference/body_routes.md),
  can be spliced in with [`c()`](https://rdrr.io/r/base/c.html).)

- response_builder:

  (function) builds a response from resolved fixture data. Default
  [`mock_response()`](https://dereckscompany.github.io/connectcore/reference/mock_response.md).

## Value

(function) the dispatcher `function(req)` for `options(httr2_mock = )`.

## Details

A route also carries an optional `method`: if set, the route matches
only when `req$method` equals it (so the same URL can map to different
fixtures by verb). The matched route's `fixture` is resolved – called if
it is a function, else used as-is – and passed to `response_builder` (an
`httr2_response` is returned unchanged, the pass-through path). Because
a fixture is invoked per request, a counter in its closure expresses
**stateful** routes (e.g. paginate: page 1 then an empty page). An
unmatched request raises "Unmocked request".
