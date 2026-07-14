# Raise a typed response-parse error

Signals a condition classed `c("connectcore_response_error",`
`"connectcore_error")` for a response that reached the client but is
malformed or missing an expected field (e.g. a server-time endpoint
whose payload lacks its time key). Carries the offending `field`, the
request `url` (credentials redacted), and a truncated `body` snippet.
The `message` is passed through verbatim, so an existing string stays
byte-identical. See
[connectcore_conditions](https://dereckscompany.github.io/connectcore/reference/connectcore_conditions.md)
for the taxonomy.

## Usage

``` r
abort_response_error(
  message,
  field = NULL,
  url = NULL,
  body = NULL,
  max_body = 2048L
)
```

## Arguments

- message:

  (scalar\<character\>) the condition message (passed through verbatim).

- field:

  (scalar\<character\> \| NULL) the missing / malformed field name, if
  known. Default `NULL`.

- url:

  (scalar\<character\> \| NULL) the request URL; query-string
  credentials are redacted with
  [`scrub_url()`](https://dereckscompany.github.io/connectcore/reference/scrub_url.md)
  before storing on the `url` field. Default `NULL`.

- body:

  (scalar\<character\> \| NULL) the response body text; stored truncated
  to `max_body` characters on the `body_snippet` field (named
  `body_snippet`, not `body`, because
  [`rlang::abort()`](https://rlang.r-lib.org/reference/abort.html)
  reserves `body`). Default `NULL`.

- max_body:

  (scalar\<count in \[1, Inf\[\>) truncate the stored body snippet to
  this many characters. Default `2048`.

## Value

(class\<connectcore_error\>) never returns normally; signals the classed
condition described above.

## See also

[connectcore_conditions](https://dereckscompany.github.io/connectcore/reference/connectcore_conditions.md)
