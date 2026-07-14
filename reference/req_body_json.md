# Parse a request's JSON body

Reads `req$body$data` and parses it as JSON, returning a list. It copes
with every shape httr2 stores a body in: a `raw` vector or a `character`
scalar (set by
[`httr2::req_body_raw()`](https://httr2.r-lib.org/reference/req_body.html),
the byte-verbatim path connectors use to sign the exact body), and an
already-deserialised `list` (set by
[`httr2::req_body_json()`](https://httr2.r-lib.org/reference/req_body.html),
which httr2 serialises only at perform time). Used by body-routed APIs
whose endpoint is encoded in the body rather than the URL (e.g.
Hyperliquid).

## Usage

``` r
req_body_json(req)
```

## Arguments

- req:

  (class\<httr2_request\>) the request whose body to parse.

## Value

(list \| NULL) the parsed body, or `NULL` if the request has no body.
