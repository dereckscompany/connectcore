# File: R/RestClient.R
# Generic abstract REST client base for data-source connectors.

#' RestClient: Abstract REST Client Base for Connectors
#'
#' Shared infrastructure for REST connectors: credential storage, sync/async
#' execution, and a single `private$.request()` funnel every endpoint method
#' delegates to. Venue specifics plug in by **overriding two private seams** —
#' `.sign()` (how to authenticate a request) and `.parse_envelope()` (how to turn
#' a response into data and detect errors) — exactly as [StreamClient] subclasses
#' override `.dispatch()`. The defaults are no-auth and "JSON body, error on
#' non-2xx", so the base works as-is for a simple public API.
#'
#' ### Sync vs Async
#' `async = FALSE` (default) returns results directly; `async = TRUE` returns
#' [promises::promise]s resolving to the same values. The whole class is mode-
#' transparent — the only branch is inside [then_or_now()].
#'
#' ### Timestamp source
#' `time_source = "local"` (default) signs against the local UTC clock;
#' `"server"` fetches the venue's server time (`time_endpoint`) before each
#' signed request to avoid clock drift, at the cost of one extra round trip. The
#' source is exposed to `.sign()` via `ctx$get_timestamp_ms`.
#'
#' @examples
#' \dontrun{
#' # A connector subclasses RestClient and overrides .sign to authenticate,
#' # delegating to a shared signing helper:
#' MyClient <- R6::R6Class("MyClient", inherit = connectcore::RestClient,
#'   public = list(initialize = function(keys = NULL, base_url = "https://api.example.com",
#'                                        async = FALSE, time_source = c("local", "server")) {
#'     super$initialize(keys = keys, base_url = base_url, async = async,
#'       time_source = match.arg(time_source), time_endpoint = "/v1/time",
#'       body_format = "query")
#'   }),
#'   private = list(
#'     .sign = function(req, keys, ctx) connectcore::hmac_query_sign(req, keys, ctx$get_timestamp_ms)
#'   ))
#' }
#'
#' @importFrom R6 R6Class
#' @importFrom httr2 req_perform req_perform_promise
#' @export
RestClient <- R6::R6Class(
  "RestClient",
  public = list(
    #' @description
    #' Initialise a RestClient
    #'
    #' @param keys (list | NULL) API credentials passed to `.sign()`. `NULL` for a
    #'   public-only client.
    #' @param base_url (scalar<character>) the API base URL.
    #' @param async (scalar<logical>) if `TRUE`, methods return promises. Default
    #'   `FALSE`.
    #' @param time_source (scalar<character in c("local", "server")>) clock used for
    #'   signing. Default `"local"`.
    #' @param time_endpoint (scalar<character> | NULL) path of the server-time
    #'   endpoint, required when `time_source = "server"`. Default `NULL`.
    #' @param time_field (scalar<character>) JSON field holding epoch ms in the
    #'   server-time response. Default `"serverTime"`.
    #' @param body_format (scalar<character in c("json", "query", "none", "raw")>)
    #'   default request-body encoding for every call; `"raw"` sends a
    #'   pre-serialized body byte-verbatim (for venues that sign the exact body
    #'   bytes). A single `.request()` may override it. Default `"json"`.
    #' @param user_agent (scalar<character>) the `User-Agent` header. Default
    #'   `"dereckscompany/connectcore"`.
    #' @param max_tries (scalar<count in [1, Inf[>) retry up to this many times on a
    #'   transient failure. Default `1` (no retry).
    #' @param throttle_rate (scalar<numeric in ]0, Inf[> | NULL) client-side rate
    #'   cap in requests/second. Default `NULL` (no throttle).
    #' @return (class<RestClient>) invisibly, self.
    initialize = function(
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
    ) {
      time_source <- match.arg(time_source)
      body_format <- match.arg(body_format)
      assert_args_RestClient__initialize(
        keys,
        base_url,
        async,
        time_source,
        time_endpoint,
        time_field,
        body_format,
        user_agent,
        max_tries,
        throttle_rate
      )
      private$.keys <- keys
      private$.base_url <- base_url
      private$.is_async <- isTRUE(async)
      private$.time_source <- time_source
      private$.body_format <- body_format
      private$.user_agent <- user_agent
      private$.max_tries <- as.integer(max_tries)
      private$.throttle_rate <- throttle_rate

      if (time_source == "server") {
        if (is.null(time_endpoint)) {
          rlang::abort("time_source = 'server' requires a time_endpoint.")
        }
        url <- base_url
        ep <- time_endpoint
        fld <- time_field
        private$.get_timestamp_ms <- function() fetch_server_time_ms(url, ep, fld)
      } else {
        private$.get_timestamp_ms <- function() floor(as.numeric(lubridate::now("UTC")) * 1000)
      }

      private$.perform <- if (private$.is_async) httr2::req_perform_promise else httr2::req_perform
      return(invisible(assert_return_RestClient__initialize(self)))
    }
  ),
  active = list(
    #' @field is_async (scalar<logical>) read-only async-mode flag.
    is_async = function() {
      return(private$.is_async)
    },
    #' @field time_source (scalar<character>) read-only signing clock source.
    time_source = function() {
      return(private$.time_source)
    }
  ),
  private = list(
    .keys = NULL,
    .base_url = NULL,
    .perform = NULL,
    .is_async = FALSE,
    .time_source = "local",
    .get_timestamp_ms = NULL,
    .body_format = "json",
    .user_agent = "dereckscompany/connectcore",
    .max_tries = 1L,
    .throttle_rate = NULL,

    # ---- Overridable seams (subclasses customise these) ----

    # Authenticate a request. The default applies no auth (public client); a venue
    # overrides it and delegates to a signing helper (e.g. hmac_query_sign()). It
    # receives the instance's credentials and a context list whose
    # `get_timestamp_ms` is the configured (local or server) clock source.
    .sign = function(req, keys, ctx) {
      return(req)
    },

    # Turn a response into data and raise on error. The default is JSON + non-2xx;
    # a venue with a business-level error envelope (e.g. a `code`/`msg` field that
    # signals failure on a 200) overrides it.
    .parse_envelope = function(resp) {
      return(parse_json_response(resp))
    },

    # The single request method every endpoint method delegates to. Injects the
    # instance's URL, credentials, the overridable sign/parse seams, perform fn,
    # and retry/throttle config into the shared build_request() funnel.
    #
    # `base_url` overrides the instance URL for this one call (dual-host venues);
    # `body_format` overrides the instance default (e.g. a single signed endpoint
    # that sends a "raw" body the rest of the client does not).
    .request = function(
      endpoint,
      method = "GET",
      query = list(),
      body = NULL,
      auth = TRUE,
      .parser = identity,
      timeout = 30,
      base_url = NULL,
      body_format = NULL,
      raw_content_type = "application/json"
    ) {
      return(build_request(
        base_url = if (is.null(base_url)) private$.base_url else base_url,
        endpoint = endpoint,
        method = method,
        query = query,
        body = body,
        keys = if (auth) private$.keys else NULL,
        sign = private$.sign,
        parse_envelope = private$.parse_envelope,
        body_format = if (is.null(body_format)) private$.body_format else body_format,
        raw_content_type = raw_content_type,
        .perform = private$.perform,
        .parser = .parser,
        is_async = private$.is_async,
        timeout = timeout,
        user_agent = private$.user_agent,
        max_tries = private$.max_tries,
        throttle_rate = private$.throttle_rate,
        ctx = list(get_timestamp_ms = private$.get_timestamp_ms)
      ))
    }
  )
)
