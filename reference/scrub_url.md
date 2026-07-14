# Redact query-string credentials from a URL

Returns `url` with the *value* of every query parameter whose name
contains a sensitive token (case-insensitively) replaced by
`<redacted>`, so a URL stored on a condition or written to a log never
leaks a signature, API key, or token. The path and the non-sensitive
parameters (symbol, limit, ...) are preserved for debugging. Matching is
deliberately conservative: a substring match on the key over-redacts a
borderline name rather than risk leaking a secret.

## Usage

``` r
scrub_url(
  url,
  sensitive_params = c("key", "secret", "sign", "signature", "sig", "token", "pass",
    "passphrase", "apikey", "api_key", "access", "nonce")
)
```

## Arguments

- url:

  (scalar\<character\> \| NULL) a URL, possibly carrying a query string.
  `NULL` returns `NULL`.

- sensitive_params:

  (vector\<character, 1..\>) parameter-name tokens whose values are
  redacted (matched as a case-insensitive substring of the key).

## Value

(scalar\<character\> \| NULL) the URL with sensitive query values
redacted.

## See also

[connectcore_conditions](https://dereckscompany.github.io/connectcore/reference/connectcore_conditions.md)
