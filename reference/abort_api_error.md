# Raise a typed HTTP API error

Signals a condition classed `c("connectcore_api_error_<status>",`
`"connectcore_api_error", "connectcore_error")` (on top of rlang's error
classes), carrying the HTTP `status`, the request `url` (query-string
credentials redacted), and a truncated `body_snippet` as structured
fields. The message defaults to the byte-identical
`"HTTP error <status>\n<body>"` the transport base signalled before
typed conditions existed, so nothing that matched on message text
breaks. See
[connectcore_conditions](https://dereckscompany.github.io/connectcore/reference/connectcore_conditions.md)
for the taxonomy and the connector-subclass recipe.

## Usage

``` r
abort_api_error(
  status,
  url = NULL,
  body = NULL,
  message = NULL,
  max_body = 2048L
)
```

## Arguments

- status:

  (scalar\<count in \[100, 599\]\>) the HTTP status code. Also names the
  most specific class, `connectcore_api_error_<status>`.

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

- message:

  (scalar\<character\> \| NULL) the condition message. `NULL` (default)
  derives the byte-identical legacy string from `status` and `body`.

- max_body:

  (scalar\<count in \[1, Inf\[\>) truncate the stored body snippet to
  this many characters. Default `2048`.

## Value

(class\<connectcore_error\>) never returns normally; signals the classed
condition described above.

## See also

[connectcore_conditions](https://dereckscompany.github.io/connectcore/reference/connectcore_conditions.md)
