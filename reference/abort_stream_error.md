# Raise a typed stream error

Signals a condition classed `c("connectcore_stream_error",`
`"connectcore_error")` for a
[StreamClient](https://dereckscompany.github.io/connectcore/reference/StreamClient.md)
transport failure (e.g. calling `$send()` while the socket is closed).
Carries the socket `url` (credentials redacted) when available. The
`message` is passed through verbatim, so an existing string stays
byte-identical. See
[connectcore_conditions](https://dereckscompany.github.io/connectcore/reference/connectcore_conditions.md)
for the taxonomy.

## Usage

``` r
abort_stream_error(message, url = NULL)
```

## Arguments

- message:

  (scalar\<character\>) the condition message (passed through verbatim).

- url:

  (scalar\<character\> \| NULL) the socket URL; query-string credentials
  are redacted with
  [`scrub_url()`](https://dereckscompany.github.io/connectcore/reference/scrub_url.md)
  before storing. Default `NULL`.

## Value

(class\<connectcore_error\>) never returns normally; signals the classed
condition described above.

## See also

[connectcore_conditions](https://dereckscompany.github.io/connectcore/reference/connectcore_conditions.md)
