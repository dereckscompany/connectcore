# HMAC-query request signing.

test_that("hmac_query_sign signs the exact URL-encoded query string", {
  fixed_ts <- function() 1700000000000
  req <- httr2::req_url_query(httr2::request("https://api.test/order"), symbol = "BTCUSDT")
  signed <- hmac_query_sign(req, list(api_key = "KEY", api_secret = "SECRET"), get_timestamp_ms = fixed_ts)

  q <- httr2::url_parse(signed$url)$query
  expect_identical(q$timestamp, "1700000000000")
  # signature is HMAC-SHA256 of "symbol=BTCUSDT&timestamp=1700000000000"
  expected <- digest::hmac(
    key = "SECRET",
    object = "symbol=BTCUSDT&timestamp=1700000000000",
    algo = "sha256",
    serialize = FALSE
  )
  expect_identical(q$signature, expected)
})

test_that("hmac_query_sign sets the api-key header", {
  signed <- hmac_query_sign(
    httr2::request("https://api.test/order"),
    list(api_key = "KEY", api_secret = "SECRET"),
    get_timestamp_ms = function() 1700000000000
  )
  expect_identical(signed$headers$`X-MBX-APIKEY`, "KEY")
})

test_that("hmac_query_sign honours configurable param/header names", {
  signed <- hmac_query_sign(
    httr2::request("https://api.test/order"),
    list(api_key = "KEY", api_secret = "SECRET"),
    get_timestamp_ms = function() 1700000000000,
    api_key_header = "KC-API-KEY",
    signature_param = "sign",
    timestamp_param = "nonce"
  )
  q <- httr2::url_parse(signed$url)$query
  expect_false(is.null(q$nonce))
  expect_false(is.null(q$sign))
  expect_identical(signed$headers$`KC-API-KEY`, "KEY")
})

test_that("hmac_query_sign returns an httr2 request and enforces its contract", {
  expect_s3_class(
    hmac_query_sign(httr2::request("https://x"), list(api_key = "k", api_secret = "s")),
    "httr2_request"
  )
  expect_error(hmac_query_sign("not-a-request", list(api_key = "k", api_secret = "s")))
})
