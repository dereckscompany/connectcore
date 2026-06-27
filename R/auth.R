# File: R/auth.R
# Request-signing helpers. A connector authenticates by overriding RestClient's
# private `.sign(req, keys, ctx)` and delegating to one of these. v1 ships the
# HMAC-query scheme (Binance-style); HMAC-header (KuCoin), JWT (Coinbase), and
# EVM-wallet (Hyperliquid) helpers plug in the same way and are added as their
# connectors are migrated onto connectcore.

#' Sign a request with HMAC-query authentication
#'
#' Authenticates by appending a `timestamp` and an HMAC-SHA256 `signature` of the
#' (URL-encoded) query string, plus an API-key header — the scheme used by Binance
#' and compatible exchanges. The parameter/header names are configurable so one
#' implementation serves any exchange using this scheme. Call it from a
#' connector's `.sign()` override, e.g.
#' `.sign = function(req, keys, ctx) hmac_query_sign(req, keys, ctx$get_timestamp_ms)`.
#'
#' @param req (class<httr2_request>) the request to sign.
#' @param keys (list) credentials with `api_key` and `api_secret`.
#' @param get_timestamp_ms (function | NULL) a zero-argument function returning
#'   epoch milliseconds; `NULL` (default) uses the local UTC clock.
#' @param api_key_header (scalar<character>) header carrying the public API key.
#'   Default `"X-MBX-APIKEY"`.
#' @param signature_param (scalar<character>) query parameter for the signature.
#'   Default `"signature"`.
#' @param timestamp_param (scalar<character>) query parameter for the timestamp.
#'   Default `"timestamp"`.
#' @return (class<httr2_request>) the signed request.
#' @importFrom digest hmac
#' @importFrom httr2 req_url_query req_headers url_parse
#' @importFrom lubridate now
#' @importFrom rlang `:=`
#' @export
hmac_query_sign <- function(
  req,
  keys,
  get_timestamp_ms = NULL,
  api_key_header = "X-MBX-APIKEY",
  signature_param = "signature",
  timestamp_param = "timestamp"
) {
  assert_args_hmac_query_sign(api_key_header, signature_param, timestamp_param)
  if (is.null(get_timestamp_ms)) {
    get_timestamp_ms <- function() floor(as.numeric(lubridate::now("UTC")) * 1000)
  }
  timestamp <- format(get_timestamp_ms(), scientific = FALSE)
  req <- httr2::req_url_query(req, !!timestamp_param := timestamp)

  # Sign the exact URL-encoded query string the server will receive.
  parsed_url <- httr2::url_parse(req$url)
  query_string <- ""
  if (length(parsed_url$query) > 0L) {
    encoded <- vapply(parsed_url$query, function(v) utils::URLencode(v, reserved = TRUE), character(1L))
    query_string <- paste0(names(parsed_url$query), "=", encoded, collapse = "&")
  }
  signature <- digest::hmac(key = keys$api_secret, object = query_string, algo = "sha256", serialize = FALSE)

  req <- httr2::req_url_query(req, !!signature_param := signature)
  req <- httr2::req_headers(req, !!api_key_header := keys$api_key)
  return(req)
}
