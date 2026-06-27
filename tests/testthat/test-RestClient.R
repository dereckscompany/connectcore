# RestClient: abstract REST base (no network exercised here).

test_that("a public client constructs with defaults", {
  rc <- RestClient$new(base_url = "https://api.test")
  expect_s3_class(rc, "RestClient")
  expect_false(rc$is_async)
  expect_identical(rc$time_source, "local")
})

test_that("async and server-time options are reflected in the active bindings", {
  rc <- RestClient$new(
    base_url = "https://api.test",
    async = TRUE,
    time_source = "server",
    time_endpoint = "/api/v3/time"
  )
  expect_true(rc$is_async)
  expect_identical(rc$time_source, "server")
})

test_that("active bindings are read-only", {
  rc <- RestClient$new(base_url = "https://api.test")
  expect_error(rc$is_async <- TRUE)
  expect_error(rc$time_source <- "server")
})

test_that("time_source = 'server' without an endpoint aborts", {
  expect_error(
    RestClient$new(base_url = "https://api.test", time_source = "server"),
    "time_endpoint"
  )
})

test_that("the default .sign and .parse_envelope seams are no-auth / JSON", {
  rc <- RestClient$new(base_url = "https://api.test")
  # the base applies no auth: .sign returns the request unchanged
  req <- httr2::request("https://api.test")
  expect_identical(rc$.__enclos_env__$private$.sign(req, NULL, list()), req)
})

test_that("initialize enforces its contract", {
  expect_error(RestClient$new(base_url = 123))
  expect_error(RestClient$new(base_url = "https://x", async = "yes"))
  expect_error(RestClient$new(base_url = "https://x", time_source = "satellite"))
  expect_error(RestClient$new(base_url = "https://x", body_format = "xml"))
  expect_error(RestClient$new(base_url = "https://x", max_tries = 0))
})

test_that("body_format = 'raw' is an accepted instance default", {
  rc <- RestClient$new(base_url = "https://api.test", body_format = "raw")
  expect_s3_class(rc, "RestClient")
})

# A test subclass that echoes the assembled request back (no network): it swaps in
# an echoing envelope parser and exposes the private funnel so a test can inspect
# the request build_request() produced.
EchoClient <- R6::R6Class(
  "EchoClient",
  inherit = RestClient,
  public = list(
    call = function(...) {
      return(private$.request(...))
    }
  ),
  private = list(
    .parse_envelope = function(resp) {
      return(resp)
    }
  )
)

new_echo <- function(base_url = "https://default.test", body_format = "json") {
  rc <- EchoClient$new(base_url = base_url, body_format = body_format)
  # Replace the perform fn with identity so .request returns the built request.
  rc$.__enclos_env__$private$.perform <- function(req) req
  return(rc)
}

test_that(".request uses the instance base_url by default", {
  rc <- new_echo(base_url = "https://default.test")
  req <- rc$call(endpoint = "/v1/ping")
  expect_match(req$url, "^https://default\\.test/v1/ping")
})

test_that(".request base_url overrides the instance base for a single call", {
  rc <- new_echo(base_url = "https://default.test")
  # one call to the alternate host (dual-host venues, e.g. coinbase)
  req <- rc$call(endpoint = "/products", base_url = "https://other.test")
  expect_match(req$url, "^https://other\\.test/products")
  # the instance default is untouched: the next call goes back to the default host
  req2 <- rc$call(endpoint = "/v1/ping")
  expect_match(req2$url, "^https://default\\.test/v1/ping")
})

test_that(".request can override body_format to raw for a single call", {
  rc <- new_echo(base_url = "https://default.test", body_format = "json")
  exact <- '{"b":null,"a":1}'
  req <- rc$call(
    endpoint = "/orders",
    method = "POST",
    body = exact,
    body_format = "raw"
  )
  expect_identical(req$body$data, exact) # verbatim, despite the json instance default
})
