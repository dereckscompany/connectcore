# Build and perform a REST request (the single funnel)

Constructs an
[httr2::request](https://httr2.r-lib.org/reference/request.html),
optionally signs it, performs it (sync or async), parses the response
envelope, and applies a post-parser. Every REST call a connector makes
flows through here. Venue specifics are injected: `sign` (how to
authenticate), `parse_envelope` (how to turn a response into data and
detect errors), and `body_format` (how a request body is encoded).

## Usage

``` r
build_request(
  base_url,
  endpoint,
  method = "GET",
  query = list(),
  body = NULL,
  keys = NULL,
  sign = NULL,
  parse_envelope = parse_json_response,
  body_format = c("json", "query", "none", "raw"),
  raw_content_type = "application/json",
  .perform = httr2::req_perform,
  .parser = identity,
  is_async = FALSE,
  timeout = 30,
  user_agent = "dereckscompany/connectcore",
  max_tries = 1L,
  throttle_rate = NULL,
  ctx = list()
)
```

## Arguments

- base_url:

  (scalar\<character\>) the API base URL.

- endpoint:

  (scalar\<character\>) the path appended to `base_url`.

- method:

  (scalar\<character\>) the HTTP method. Default `"GET"`.

- query:

  (list) query parameters; `NULL` entries are dropped. A vector-valued
  entry repeats its key (`.multi = "explode"`), e.g. `ids = c("A", "B")`
  becomes `ids=A&ids=B`.

- body:

  (list \| scalar\<character\> \| raw \| NULL) request body. For
  `body_format = "raw"` it is a pre-serialized scalar `character` (or
  `raw`) sent verbatim; otherwise a `list` whose `NULL` entries are
  dropped. Default `NULL`.

- keys:

  (list \| NULL) credentials passed to `sign`; `NULL` skips signing.

- sign:

  (function \| NULL) `function(req, keys, ctx)` returning a signed
  request. `NULL` (default) means no signing.

- parse_envelope:

  (function) `function(resp)` turning a response into data, raising on
  error. Default
  [`parse_json_response()`](https://dereckscompany.github.io/connectcore/reference/parse_json_response.md).

- body_format:

  (scalar\<character in c("json", "query", "none", "raw")\>) how `body`
  is encoded: a pretty-printed JSON body (`NULL` fields pruned), merged
  into the query string (some signed APIs), ignored, or — for `"raw"` —
  sent byte-verbatim via
  [`httr2::req_body_raw()`](https://httr2.r-lib.org/reference/req_body.html)
  with no pruning, pretty-printing, or re-encoding (the caller owns
  serialization; required by venues that sign the exact body bytes).
  Default `"json"`.

- raw_content_type:

  (scalar\<character\>) the `Content-Type` for a `"raw"` body. Ignored
  unless `body_format = "raw"`. Default `"application/json"`.

- .perform:

  (function) the httr2 perform function
  ([httr2::req_perform](https://httr2.r-lib.org/reference/req_perform.html)
  or
  [httr2::req_perform_promise](https://httr2.r-lib.org/reference/req_perform_promise.html)).
  Default
  [httr2::req_perform](https://httr2.r-lib.org/reference/req_perform.html).

- .parser:

  (function) post-processor applied to the parsed data. Default
  [base::identity](https://rdrr.io/r/base/identity.html).

- is_async:

  (scalar\<logical\>) whether `.perform` returns a promise. Default
  `FALSE`.

- timeout:

  (scalar\<numeric in \]0, Inf\[\>) request timeout in seconds. Default
  `30`.

- user_agent:

  (scalar\<character\>) the `User-Agent` header. Default
  `"dereckscompany/connectcore"`.

- max_tries:

  (scalar\<count in \[1, Inf\[\>) retry up to this many times with
  backoff on a transient failure. `1` (default) disables retry.

- throttle_rate:

  (scalar\<numeric in \]0, Inf\[\> \| NULL) client-side rate cap in
  requests per second. `NULL` (default) disables throttling.

- ctx:

  (list) extra context forwarded to `sign` (e.g. a timestamp source).
  Default [`list()`](https://rdrr.io/r/base/list.html).

## Value

(any) the post-processed data, or a promise resolving to it.

## Details

Unlike the per-venue copies this generalises, it also adds optional
`req_retry` and `req_throttle` — retry/backoff and client-side rate
limiting that no individual connector currently has.

Signing runs **after** the body is set, so a venue that signs the exact
body bytes (`body_format = "raw"`) can read them off `req$body$data`
inside `sign` and add the signature header before the request is
performed.
