# Make a base-URL getter backed by an environment variable

Returns a function `function(url = <env or default>)` — the standard
connector pattern. Calling it with no argument resolves the env var
(falling back to the default); passing `url` overrides.

## Usage

``` r
url_getter(var, default)
```

## Arguments

- var:

  (scalar\<character\>) the environment variable name.

- default:

  (scalar\<character\>) the fallback URL.

## Value

(function) a getter `function(url)`.
