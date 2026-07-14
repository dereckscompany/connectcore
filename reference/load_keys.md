# Load API credentials from environment variables

Reads a named set of credential fields from env vars into a list (the
shape a signer expects, e.g. `list(api_key = ..., api_secret = ...)`).
Warns (rather than aborts) if any field is empty, since public endpoints
work without keys.

## Usage

``` r
load_keys(spec, warn = TRUE)
```

## Arguments

- spec:

  (list) a named list mapping each credential field to its env var name,
  e.g.
  `list(api_key = "MYAPP_API_KEY", api_secret = "MYAPP_API_SECRET")`.

- warn:

  (scalar\<logical\>) warn when a field resolves empty. Default `TRUE`.

## Value

(list) a named list of the resolved credential values.
