# Build a mock `httr2` response from fixture data

The single response constructor every mocked route resolves to. It
accepts fixture data in three shapes, mirroring how connectors capture
fixtures:

- an already-built `httr2_response` is returned **unchanged** (the
  pass-through path – e.g. a 204 no-content or a hand-built error
  response);

- a single character string is used **verbatim** as the body (the
  real-captured-JSON path – a fixture file read in as one string);

- anything else is JSON-encoded with
  [`jsonlite::toJSON()`](https://jeroen.r-universe.dev/jsonlite/reference/fromJSON.html)
  (`auto_unbox = TRUE, null = "null", digits = NA`), matching the live
  wire.

## Usage

``` r
mock_response(
  body = NULL,
  status = 200L,
  headers = list(`content-type` = "application/json")
)
```

## Arguments

- body:

  (any) the response body: an `httr2_response` (returned as-is), a
  `scalar<character>` (used verbatim), or a list/value (JSON-encoded).

- status:

  (scalar\<count in \[100, 599\]\>) the HTTP status code. Default `200`.

- headers:

  (list) the response headers. Default
  `list("content-type" = "application/json")`.

## Value

(class\<httr2_response\>) the mock response.
