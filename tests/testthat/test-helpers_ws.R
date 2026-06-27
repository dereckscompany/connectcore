# Connection-free WebSocket helpers.

test_that("ws_backoff_delay stays within [1, cap + 1] across many draws", {
  delays <- vapply(1:200, function(i) ws_backoff_delay(3L, cap_seconds = 10), numeric(1))
  expect_true(all(delays >= 1))
  expect_true(all(delays <= 11)) # cap + jitter floor
})

test_that("ws_backoff_delay grows with the attempt number but is capped", {
  # attempt 1 spans [1, 2]; a high attempt is bounded by the cap, not 2^attempt.
  early <- vapply(1:200, function(i) ws_backoff_delay(1L, cap_seconds = 60), numeric(1))
  expect_true(all(early <= 2))
  late <- vapply(1:200, function(i) ws_backoff_delay(20L, cap_seconds = 30), numeric(1))
  expect_true(all(late <= 31))
})

test_that("ws_backoff_delay enforces its contract", {
  expect_error(ws_backoff_delay("three"))
  expect_error(ws_backoff_delay(3L, cap_seconds = -1))
})

test_that("ws_file_sink returns a handler that appends frames plus a newline", {
  path <- withr::local_tempfile()
  con <- file(path, open = "a")
  on.exit(close(con), add = TRUE)
  sink <- ws_file_sink(con)
  expect_type(sink, "closure")
  sink('{"a":1}')
  sink('{"b":2}')
  flush(con)
  lines <- readLines(path)
  expect_identical(lines, c('{"a":1}', '{"b":2}'))
})

test_that("ws_file_sink enforces its contract", {
  expect_error(ws_file_sink("not-a-connection"))
})
