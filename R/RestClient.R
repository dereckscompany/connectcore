# File: R/RestClient.R
# Generic abstract REST client base for data-source connectors.

#' RestClient: Abstract REST Client Base for Connectors
#'
#' Shared infrastructure for REST connectors: credential storage, sync/async
#' execution, a configurable signing scheme and error-envelope parser, and a
#' single `private$.request()` funnel every endpoint method delegates to. A
#' connector subclasses it and supplies the venue specifics — base URL, a `sign`
#' strategy (e.g. [hmac_query_signer()]), an envelope `parse` function, and the
#' body encoding — then adds typed endpoint methods.
#'
#' ### Sync vs Async
#' `async = FALSE` (default) returns results directly; `async = TRUE` returns
#' [promises::promise]s resolving to the same values. The whole class is mode-
#' transparent — the only branch is inside [then_or_now()].
#'
#' ### Timestamp source
#' `time_source = "local"` (default) signs against the local UTC clock;
#' `"server"` fetches the venue's server time (`time_endpoint`) before each
#' signed request to avoid clock drift, at the cost of one extra round trip.
#'
#' @examples
#' \dontrun{
#' # A connector subclasses RestClient and injects its venue strategy:
#' BinanceBase <- R6::R6Class("BinanceBase", inherit = connectcore::RestClient,
#'   public = list(initialize = function(keys = get_api_keys(), base_url = get_base_url(),
#'                                        async = FALSE, time_source = c("local", "server")) {
#'     super$initialize(keys = keys, base_url = base_url, async = async,
#'       time_source = match.arg(time_source), time_endpoint = "/api/v3/time",
#'       sign = connectcore::hmac_query_signer(), body_format = "query")
#'   }))
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
    #' @param keys (list | NULL) API credentials forwarded to `sign`. `NULL` for a
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
    #' @param sign (function | NULL) the request signer `function(req, keys, ctx)`.
    #'   `NULL` (default) means no signing.
    #' @param parse_envelope (function) `function(resp)` turning a response into
    #'   data and raising on error. Default [parse_json_response()].
    #' @param body_format (scalar<character in c("json", "query", "none")>) request
    #'   body encoding. Default `"json"`.
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
      sign = NULL,
      parse_envelope = parse_json_response,
      body_format = c("json", "query", "none"),
      user_agent = "dereckscompany/connectcore",
      max_tries = 1L,
      throttle_rate = NULL
    ) {
      time_source <- match.arg(time_source)
      body_format <- match.arg(body_format)
      assert_args_RestClient__initialize(
        keys, base_url, async, time_source, time_endpoint, time_field,
        sign, parse_envelope, body_format, user_agent, max_tries, throttle_rate
      )
      private$.keys <- keys
      private$.base_url <- base_url
      private$.is_async <- isTRUE(async)
      private$.time_source <- time_source
      private$.sign <- sign
      private$.parse_envelope <- parse_envelope
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
    .sign = NULL,
    .parse_envelope = NULL,
    .body_format = "json",
    .user_agent = "dereckscompany/connectcore",
    .max_tries = 1L,
    .throttle_rate = NULL,

    # The single request method every endpoint method delegates to. Injects the
    # instance's URL, credentials, signer, envelope parser, perform fn, and
    # retry/throttle config into the shared build_request() funnel.
    .request = function(
      endpoint,
      method = "GET",
      query = list(),
      body = NULL,
      auth = TRUE,
      .parser = identity,
      timeout = 30
    ) {
      return(build_request(
        base_url = private$.base_url,
        endpoint = endpoint,
        method = method,
        query = query,
        body = body,
        keys = if (auth) private$.keys else NULL,
        sign = private$.sign,
        parse_envelope = private$.parse_envelope,
        body_format = private$.body_format,
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
