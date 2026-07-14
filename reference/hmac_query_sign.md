# Sign a request with HMAC-query authentication

Authenticates by appending a `timestamp` and an HMAC-SHA256 `signature`
of the (URL-encoded) query string, plus an API-key header — a common
scheme across signed REST APIs. The parameter/header names are
configurable so one implementation serves any service using this scheme.
Call it from a connector's `.sign()` override, e.g.
`.sign = function(req, keys, ctx) hmac_query_sign(req, keys, ctx$get_timestamp_ms)`.

## Usage

``` r
hmac_query_sign(
  req,
  keys,
  get_timestamp_ms = NULL,
  api_key_header = "X-API-KEY",
  signature_param = "signature",
  timestamp_param = "timestamp"
)
```

## Arguments

- req:

  (class\<httr2_request\>) the request to sign.

- keys:

  (list) credentials with `api_key` and `api_secret`.

- get_timestamp_ms:

  (function \| NULL) a zero-argument function returning epoch
  milliseconds; `NULL` (default) uses the local UTC clock.

- api_key_header:

  (scalar\<character\>) header carrying the public API key. Default
  `"X-API-KEY"`.

- signature_param:

  (scalar\<character\>) query parameter for the signature. Default
  `"signature"`.

- timestamp_param:

  (scalar\<character\>) query parameter for the timestamp. Default
  `"timestamp"`.

## Value

(class\<httr2_request\>) the signed request.
