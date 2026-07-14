# RestClient: Abstract REST Client Base for Connectors

RestClient: Abstract REST Client Base for Connectors

RestClient: Abstract REST Client Base for Connectors

## Details

Shared infrastructure for REST connectors: credential storage,
sync/async execution, and a single `private$.request()` funnel every
endpoint method delegates to. Venue specifics plug in by **overriding
two private seams** — `.sign()` (how to authenticate a request) and
`.parse_envelope()` (how to turn a response into data and detect errors)
— exactly as
[StreamClient](https://dereckscompany.github.io/connectcore/reference/StreamClient.md)
subclasses override `.dispatch()`. The defaults are no-auth and "JSON
body, error on non-2xx", so the base works as-is for a simple public
API.

### Sync vs Async

`async = FALSE` (default) returns results directly; `async = TRUE`
returns
[promises::promise](https://rstudio.github.io/promises/reference/promise.html)s
resolving to the same values. The whole class is mode- transparent — the
only branch is inside
[`then_or_now()`](https://dereckscompany.github.io/connectcore/reference/then_or_now.md).

### Timestamp source

`time_source = "local"` (default) signs against the local UTC clock;
`"server"` fetches the venue's server time (`time_endpoint`) before each
signed request to avoid clock drift, at the cost of one extra round
trip. The source is exposed to `.sign()` via `ctx$get_timestamp_ms`.

## Active bindings

- `is_async`:

  (scalar\<logical\>) read-only async-mode flag.

- `time_source`:

  (scalar\<character\>) read-only signing clock source.

## Methods

### Public methods

- [`RestClient$new()`](#method-RestClient-new)

- [`RestClient$clone()`](#method-RestClient-clone)

------------------------------------------------------------------------

### Method `new()`

Initialise a RestClient

#### Usage

    RestClient$new(
      keys = NULL,
      base_url,
      async = FALSE,
      time_source = c("local", "server"),
      time_endpoint = NULL,
      time_field = "serverTime",
      body_format = c("json", "query", "none", "raw"),
      user_agent = "dereckscompany/connectcore",
      max_tries = 1L,
      throttle_rate = NULL
    )

#### Arguments

- `keys`:

  (list \| NULL) API credentials passed to `.sign()`. `NULL` for a
  public-only client.

- `base_url`:

  (scalar\<character\>) the API base URL.

- `async`:

  (scalar\<logical\>) if `TRUE`, methods return promises. Default
  `FALSE`.

- `time_source`:

  (scalar\<character in c("local", "server")\>) clock used for signing.
  Default `"local"`.

- `time_endpoint`:

  (scalar\<character\> \| NULL) path of the server-time endpoint,
  required when `time_source = "server"`. Default `NULL`.

- `time_field`:

  (scalar\<character\>) JSON field holding epoch ms in the server-time
  response. Default `"serverTime"`.

- `body_format`:

  (scalar\<character in c("json", "query", "none", "raw")\>) default
  request-body encoding for every call; `"raw"` sends a pre-serialized
  body byte-verbatim (for venues that sign the exact body bytes). A
  single `.request()` may override it. Default `"json"`.

- `user_agent`:

  (scalar\<character\>) the `User-Agent` header. Default
  `"dereckscompany/connectcore"`.

- `max_tries`:

  (scalar\<count in \[1, Inf\[\>) retry up to this many times on a
  transient failure. Default `1` (no retry).

- `throttle_rate`:

  (scalar\<numeric in \]0, Inf\[\> \| NULL) client-side rate cap in
  requests/second. Default `NULL` (no throttle).

#### Returns

(class\<RestClient\>) invisibly, self.

------------------------------------------------------------------------

### Method `clone()`

The objects of this class are cloneable with this method.

#### Usage

    RestClient$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.

## Examples

``` r
if (FALSE) { # \dontrun{
# A connector subclasses RestClient and overrides .sign to authenticate,
# delegating to a shared signing helper:
MyClient <- R6::R6Class("MyClient", inherit = connectcore::RestClient,
  public = list(initialize = function(keys = NULL, base_url = "https://api.example.com",
                                       async = FALSE, time_source = c("local", "server")) {
    super$initialize(keys = keys, base_url = base_url, async = async,
      time_source = match.arg(time_source), time_endpoint = "/v1/time",
      body_format = "query")
  }),
  private = list(
    .sign = function(req, keys, ctx) connectcore::hmac_query_sign(req, keys, ctx$get_timestamp_ms)
  ))
} # }
```
