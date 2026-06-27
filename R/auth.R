# File: R/auth.R
# Request-signing strategies. A signer is a `function(req, keys, ctx)` returning a
# signed httr2 request; pass one to build_request()/RestClient as `sign`. v1 ships
# the HMAC-query scheme (Binance-style); HMAC-header (KuCoin), JWT (Coinbase), and
# EVM-wallet (Hyperliquid) schemes plug in the same way and are added as their
# connectors are migrated onto connectcore.

#' Make an HMAC-query request signer
#'
#' Returns a signer that authenticates by appending a `timestamp` and an
#' HMAC-SHA256 `signature` of the (URL-encoded) query string to the request, plus
#' an API-key header — the scheme used by Binance and compatible exchanges. The
#' parameter/header names are configurable so the one implementation serves any
#' exchange using this scheme.
#'
#' The returned signer reads a timestamp source from `ctx$get_timestamp_ms` (a
#' zero-argument function returning epoch milliseconds) so the caller can sign
#' against the server clock; it falls back to the local UTC clock.
#'
#' @param api_key_header (scalar<character>) header carrying the public API key.
#'   Default `"X-MBX-APIKEY"`.
#' @param signature_param (scalar<character>) query parameter for the signature.
#'   Default `"signature"`.
#' @param timestamp_param (scalar<character>) query parameter for the timestamp.
#'   Default `"timestamp"`.
#' @return (function) a signer `function(req, keys, ctx)`.
#' @importFrom digest hmac
#' @importFrom httr2 req_url_query req_headers url_parse
#' @importFrom rlang `:=` `!!`
#' @export
hmac_query_signer <- function(
  api_key_header = "X-MBX-APIKEY",
  signature_param = "signature",
  timestamp_param = "timestamp"
) {
  assert_args_hmac_query_signer(api_key_header, signature_param, timestamp_param)
  signer <- function(req, keys, ctx) {
    get_ts <- ctx$get_timestamp_ms
    if (is.null(get_ts)) {
      get_ts <- function() floor(as.numeric(lubridate::now("UTC")) * 1000)
    }
    timestamp <- format(get_ts(), scientific = FALSE)
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
  return(assert_return_hmac_query_signer(signer))
}
