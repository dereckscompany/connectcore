# Build body-discriminated routes from a named case table

The ergonomic constructor for body-routed APIs (e.g. Hyperliquid, whose
whole REST surface sits behind two POST paths, each dispatched by a
field in the JSON body). Given a URL filter, a body field path, and a
**named** list of fixtures keyed by that field's value, it returns one
predicate-route per case: each matches when `req$url` contains
`url_filter` AND the body field at `field_path` equals that case's name.

## Usage

``` r
body_routes(url_filter, field_path, cases)
```

## Arguments

- url_filter:

  (scalar\<character\>) a substring the request URL must contain.

- field_path:

  (character) the path of names to the discriminating body field (e.g.
  `c("action", "type")` for `body$action$type`).

- cases:

  (list) a **named** list of fixtures keyed by the body field's value;
  each value is a fixture (a function, a built `httr2_response`, or
  data).

## Value

(list) a list of routes, one per `names(cases)`, each a
`list(match = <predicate>, fixture = <value>, method = NULL)`.

## Details

For example, Hyperliquid's `/info` reads (keyed by `body$type`) and
`/exchange` writes (keyed by `body$action$type`) become:

    mock_router(c(
      body_routes("/exchange", c("action", "type"), exchange_routes),
      body_routes("/info", "type", info_routes)
    ))
