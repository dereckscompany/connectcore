# Load JSON fixtures from a directory

Reads every `*.json` file in `dir` and returns a **named** list keyed by
each file's basename without the extension (`btc_book.json` -\>
`btc_book`). Each value is the raw JSON string (`parse = FALSE`, the
verbatim path that pairs with
[`mock_response()`](https://dereckscompany.github.io/connectcore/reference/mock_response.md)'s
string-body case) or the parsed list (`parse = TRUE`, via
[`jsonlite::fromJSON()`](https://jeroen.r-universe.dev/jsonlite/reference/fromJSON.html)
with `simplifyVector = FALSE`). This is how a connector loads its real
captured fixtures into a route table.

## Usage

``` r
load_fixtures(dir, parse = FALSE)
```

## Arguments

- dir:

  (scalar\<character\>) a directory holding `*.json` fixture files.

- parse:

  (scalar\<logical\>) if `TRUE`, parse each file to a list; if `FALSE`
  (default), keep the raw JSON string.

## Value

(list) a named list of fixtures (strings or parsed lists), one per
`*.json` file; empty if `dir` holds none.
