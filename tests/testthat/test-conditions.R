# Typed transport conditions (see ?connectcore_conditions). The classes and
# structured fields are additive; the message strings stay byte-identical to the
# pre-typed-conditions `rlang::abort()` calls (golden tests below pin that).

# ---- Class taxonomy: specific -> family -> root ----

test_that("abort_api_error signals the specific, family, and root classes", {
  err <- tryCatch(
    abort_api_error(status = 429, url = "https://api.test/x", body = "slow down"),
    error = function(e) e
  )
  expect_s3_class(err, "connectcore_api_error_429")
  expect_s3_class(err, "connectcore_api_error")
  expect_s3_class(err, "connectcore_error")
  expect_s3_class(err, "rlang_error")
  expect_s3_class(err, "error")
})

test_that("a status-specific handler catches its status but not another", {
  caught <- tryCatch(
    abort_api_error(status = 429, body = "x"),
    connectcore_api_error_429 = function(e) "got-429",
    connectcore_api_error = function(e) "got-family"
  )
  expect_identical(caught, "got-429")

  # A 500 is NOT caught by the _429 handler; the family handler catches it.
  caught2 <- tryCatch(
    abort_api_error(status = 500, body = "x"),
    connectcore_api_error_429 = function(e) "got-429",
    connectcore_api_error = function(e) "got-family"
  )
  expect_identical(caught2, "got-family")
})

test_that("the family class catches every HTTP status", {
  for (st in c(400L, 401L, 404L, 429L, 500L, 503L)) {
    caught <- tryCatch(
      abort_api_error(status = st, body = "x"),
      connectcore_api_error = function(e) e$status
    )
    expect_identical(caught, st)
  }
})

test_that("the connectcore_error root catches api, response, and stream errors alike", {
  expect_identical(
    tryCatch(abort_api_error(status = 500), connectcore_error = function(e) "root"),
    "root"
  )
  expect_identical(
    tryCatch(abort_response_error("boom"), connectcore_error = function(e) "root"),
    "root"
  )
  expect_identical(
    tryCatch(abort_stream_error("boom"), connectcore_error = function(e) "root"),
    "root"
  )
})

# ---- Structured fields (read them, don't grep the message) ----

test_that("api-error fields are present and typed", {
  err <- tryCatch(
    abort_api_error(status = 404, url = "https://x/y", body = "the-body"),
    error = function(e) e
  )
  expect_identical(err$status, 404L) # integer, read not grepped
  expect_type(err$status, "integer")
  expect_identical(err$url, "https://x/y")
  # Stored under `body_snippet`, NOT `body` (rlang::abort reserves `body`).
  # Use [[ ]] for exact matching: `$body` would partial-match `body_snippet`.
  expect_identical(err[["body_snippet"]], "the-body")
  expect_null(err[["body"]])
})

test_that("api-error truncates an over-long body snippet", {
  big <- strrep("a", 5000L)
  err <- tryCatch(abort_api_error(status = 500, body = big, max_body = 100L), error = function(e) e)
  expect_true(nchar(err$body_snippet) < 200L)
  expect_match(err$body_snippet, "<truncated>$")
})

test_that("response-error carries its field and class", {
  err <- tryCatch(abort_response_error("bad", field = "serverTime"), error = function(e) e)
  expect_s3_class(err, "connectcore_response_error")
  expect_s3_class(err, "connectcore_error")
  expect_identical(err$field, "serverTime")
})

test_that("stream-error carries a scrubbed url and class", {
  err <- tryCatch(abort_stream_error("closed", url = "wss://h/s?token=SECRET"), error = function(e) e)
  expect_s3_class(err, "connectcore_stream_error")
  expect_match(err$url, "token=<redacted>")
  expect_false(grepl("SECRET", err$url))
})

# ---- Credential scrubbing (pinned) ----

test_that("api-error scrubs query-string credentials in the stored url", {
  err <- tryCatch(
    abort_api_error(
      status = 401,
      url = "https://api.test/o?symbol=BTC&signature=DEADBEEF&apiKey=SEKRET&timestamp=123"
    ),
    error = function(e) e
  )
  expect_match(err$url, "symbol=BTC", fixed = TRUE) # non-sensitive preserved
  expect_match(err$url, "signature=<redacted>", fixed = TRUE) # secret redacted
  expect_match(err$url, "apiKey=<redacted>", fixed = TRUE)
  expect_false(grepl("DEADBEEF", err$url, fixed = TRUE))
  expect_false(grepl("SEKRET", err$url, fixed = TRUE))
})

test_that("scrub_url redacts sensitive values and preserves the rest", {
  expect_identical(
    scrub_url("https://h/p?key=AAA&limit=100&secret=BBB"),
    "https://h/p?key=<redacted>&limit=100&secret=<redacted>"
  )
  expect_null(scrub_url(NULL))
  expect_identical(scrub_url("https://h/p"), "https://h/p") # no query, unchanged
  # A bare flag parameter (no `=`) is left intact.
  expect_identical(scrub_url("https://h/p?verbose&key=Z"), "https://h/p?verbose&key=<redacted>")
})

test_that("scrub_url matching is case-insensitive", {
  expect_identical(scrub_url("https://h/p?APIKEY=Z"), "https://h/p?APIKEY=<redacted>")
  expect_identical(scrub_url("https://h/p?Signature=Z"), "https://h/p?Signature=<redacted>")
})

# ---- Message byte-identity vs the pre-typed-conditions strings (golden) ----
# These pin that adding classes changed not one byte of the message a caller
# might grep. If one fails, the backward-compatibility contract broke.

test_that("parse_json_response message is byte-identical to the legacy string", {
  resp <- httr2::response(
    status_code = 404,
    headers = list("content-type" = "application/json"),
    body = charToRaw('{"msg":"nope"}')
  )
  err <- tryCatch(parse_json_response(resp), error = function(e) e)
  expect_identical(conditionMessage(err), "HTTP error 404\n{\"msg\":\"nope\"}")
  expect_s3_class(err, "connectcore_api_error_404") # typed, additively
})

test_that("parse_json_response still aborts with the documented pattern", {
  resp <- httr2::response(status_code = 500, headers = list(), body = charToRaw("oops"))
  expect_error(parse_json_response(resp), "HTTP error 500")
})

test_that("abort_response_error preserves the server-time message verbatim (golden)", {
  msg <- sprintf("Failed to fetch server time: response has no '%s' field.", "serverTime")
  err <- tryCatch(abort_response_error(msg, field = "serverTime"), error = function(e) e)
  expect_identical(
    conditionMessage(err),
    "Failed to fetch server time: response has no 'serverTime' field."
  )
})

test_that("StreamClient$send raises a typed stream error with the legacy message (golden)", {
  ws <- StreamClient$new("wss://example.test/stream")
  err <- tryCatch(ws$send('{"x":1}'), error = function(e) e)
  expect_s3_class(err, "connectcore_stream_error")
  expect_identical(conditionMessage(err), "Cannot send: socket is not open.")
})
