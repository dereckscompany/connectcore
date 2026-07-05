# StreamClient: event-driven WebSocket base (no live socket exercised here).

test_that("a fresh client constructs and is not open", {
  ws <- StreamClient$new("wss://example.test/stream", stale_timeout = 120)
  expect_s3_class(ws, "StreamClient")
  expect_false(ws$is_open())
})

test_that("on() registers handlers and is chainable", {
  ws <- StreamClient$new("wss://example.test/stream")
  result <- ws$on("message", function(msg) NULL)
  expect_identical(result, ws) # returns self
  # multiple handlers for one event are allowed
  ws$on("message", function(msg) NULL)
  expect_s3_class(ws, "StreamClient")
})

test_that("send() aborts when the socket is not open", {
  ws <- StreamClient$new("wss://example.test/stream")
  expect_error(ws$send('{"subscribe":"all"}'), "not open")
})

test_that("is_open() reads an OPEN socket even when readyState carries attributes", {
  # The `websocket` package returns readyState() as an ATTRIBUTED integer (a named
  # `OPEN = 1L`), so an `identical(., 1L)` open-check silently reports "not open" and
  # wedges every send() / .resubscribe(). is_open() must compare by value. Inject a
  # fake socket to exercise the check without a live connection.
  ws <- StreamClient$new("wss://example.test/stream")
  ws$.__enclos_env__$private$.ws <- list(readyState = function() c(OPEN = 1L))
  expect_true(ws$is_open())
  ws$.__enclos_env__$private$.ws <- list(readyState = function() c(CONNECTING = 0L))
  expect_false(ws$is_open())
})

test_that("initialize enforces its contract", {
  expect_error(StreamClient$new(url = 123))
  expect_error(StreamClient$new("wss://x", auto_reconnect = "yes"))
  expect_error(StreamClient$new("wss://x", backoff_cap = -5))
  expect_error(StreamClient$new("wss://x", keepalive = 0))
})

test_that("on() and send() enforce their contracts", {
  ws <- StreamClient$new("wss://example.test/stream")
  expect_error(ws$on(event = 123, handler = function(x) NULL))
  expect_error(ws$on("message", handler = "not-a-function"))
  expect_error(ws$send(123))
})

test_that("max_reconnects = Inf is accepted (unattended-recorder default)", {
  expect_s3_class(StreamClient$new("wss://x", max_reconnects = Inf), "StreamClient")
  expect_s3_class(StreamClient$new("wss://x", max_reconnects = 5), "StreamClient")
})
