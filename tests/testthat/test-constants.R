# Exported constants.

test_that("WS_EVENTS exposes the guaranteed core event names", {
  expect_type(WS_EVENTS, "list")
  expect_identical(WS_EVENTS$OPEN, "open")
  expect_identical(WS_EVENTS$MESSAGE, "message")
  expect_identical(WS_EVENTS$CLOSE, "close")
  expect_identical(WS_EVENTS$ERROR, "error")
  expect_identical(WS_EVENTS$RECONNECTING, "reconnecting")
  expect_identical(WS_EVENTS$RECONNECTED, "reconnected")
  expect_identical(WS_EVENTS$GIVEUP, "giveup")
  expect_identical(WS_EVENTS$STALE, "stale")
})
