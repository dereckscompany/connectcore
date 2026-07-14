# Default response parser: JSON body, error on non-2xx

A generic
[httr2::response](https://httr2.r-lib.org/reference/response.html) -\>
data parser: returns the parsed JSON body, and raises on a non-2xx HTTP
status. Connectors with a business-level error envelope (e.g. a
`code`/`msg` field that signals failure on a 200) supply their own
`parse_envelope` to
[`build_request()`](https://dereckscompany.github.io/connectcore/reference/build_request.md)
instead; this is the sensible default when the HTTP status alone tells
the truth.

## Usage

``` r
parse_json_response(resp)
```

## Arguments

- resp:

  (class\<httr2_response\>) the response to parse.

## Value

(any) the parsed JSON body (lists, with `simplifyVector = FALSE`).
