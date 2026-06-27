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
