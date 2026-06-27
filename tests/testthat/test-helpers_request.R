# HTTP request funnel, parser, nonce.

test_that("then_or_now applies fn directly when synchronous", {
  expect_identical(then_or_now(5, function(x) x * 2), 10)
  expect_identical(then_or_now("a", toupper), "A")
})

test_that("then_or_now returns a promise when async", {
  p <- then_or_now(promises::promise_resolve(5), function(x) x * 2, is_async = TRUE)
  expect_true(promises::is.promise(p))
})

test_that("then_or_now enforces its contract", {
  expect_error(then_or_now(5, "not-a-function"))
  expect_error(then_or_now(5, identity, is_async = "yes"))
})

test_that("parse_json_response returns the parsed body on 2xx", {
  resp <- httr2::response(
    status_code = 200,
    headers = list("content-type" = "application/json"),
    body = charToRaw('{"a":1,"b":[2,3]}')
  )
  out <- parse_json_response(resp)
  expect_identical(out$a, 1L)
  expect_identical(out$b, list(2L, 3L)) # simplifyVector = FALSE keeps lists
})

test_that("parse_json_response aborts on a non-2xx status", {
  resp <- httr2::response(
    status_code = 404,
    headers = list("content-type" = "application/json"),
    body = charToRaw('{"msg":"nope"}')
  )
  expect_error(parse_json_response(resp), "HTTP error 404")
})

test_that("next_nonce is strictly increasing across rapid calls", {
  nonces <- vapply(1:50, function(i) next_nonce(), numeric(1))
  expect_true(all(diff(nonces) >= 1))
})

# build_request is exercised without a network by injecting an identity perform
# and parse_envelope, so the returned value is the assembled httr2 request.
echo_perform <- function(req) req
echo_parse <- function(resp) resp

test_that("build_request assembles URL, method, query, and user agent", {
  req <- build_request(
    base_url = "https://api.test",
    endpoint = "/v1/ping",
    method = "GET",
    query = list(symbol = "BTC", limit = NULL), # NULL dropped
    .perform = echo_perform,
    parse_envelope = echo_parse
  )
  expect_s3_class(req, "httr2_request")
  expect_match(req$url, "^https://api\\.test/v1/ping")
  expect_match(req$url, "symbol=BTC")
  expect_false(grepl("limit", req$url)) # NULL query entry dropped
  expect_identical(req$method, "GET")
})

test_that("build_request applies the sign hook only with keys", {
  signer <- function(req, keys, ctx) httr2::req_headers(req, Signed = keys$tag)
  signed <- build_request(
    base_url = "https://api.test",
    endpoint = "/o",
    keys = list(tag = "yes"),
    sign = signer,
    .perform = echo_perform,
    parse_envelope = echo_parse
  )
  expect_identical(signed$headers$Signed, "yes")

  unsigned <- build_request(
    base_url = "https://api.test",
    endpoint = "/o",
    keys = NULL,
    sign = signer,
    .perform = echo_perform,
    parse_envelope = echo_parse
  )
  expect_null(unsigned$headers$Signed)
})

test_that("build_request encodes a JSON body, or folds it into the query", {
  as_json <- build_request(
    base_url = "https://api.test",
    endpoint = "/o",
    method = "POST",
    body = list(price = 100),
    body_format = "json",
    .perform = echo_perform,
    parse_envelope = echo_parse
  )
  expect_false(is.null(as_json$body))

  as_query <- build_request(
    base_url = "https://api.test",
    endpoint = "/o",
    method = "POST",
    body = list(price = 100),
    body_format = "query",
    .perform = echo_perform,
    parse_envelope = echo_parse
  )
  expect_match(as_query$url, "price=100")
})

test_that("build_request runs the post-parser over the envelope output", {
  out <- build_request(
    base_url = "https://api.test",
    endpoint = "/o",
    .perform = function(req) "RESP",
    parse_envelope = function(resp) list(value = 21),
    .parser = function(data) data$value * 2
  )
  expect_identical(out, 42)
})

test_that("build_request enforces its contract", {
  expect_error(build_request(base_url = 123, endpoint = "/o"))
  expect_error(build_request(base_url = "https://x", endpoint = "/o", body_format = "xml"))
})
