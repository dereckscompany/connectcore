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

# ---- Typed lifecycle events ($on_event) ----

test_that("on_event registers a handler and is chainable", {
  ws <- StreamClient$new("wss://x")
  result <- ws$on_event(function(e) NULL)
  expect_identical(result, ws) # returns self
})

test_that("on_event enforces its contract", {
  ws <- StreamClient$new("wss://x")
  expect_error(ws$on_event(handler = "not-a-function"))
})

test_that("with no on_event handler, .emit_event is a no-op (hot path stays free)", {
  ws <- StreamClient$new("wss://x")
  # No handler registered -> returns invisibly without materialising a ws_event.
  expect_null(ws$.__enclos_env__$private$.emit_event("message", list(data = "x")))
})

test_that(".emit_event delivers a typed event to on_event handlers", {
  ws <- StreamClient$new("wss://x")
  got <- list()
  ws$on_event(function(e) got[[length(got) + 1L]] <<- e)
  ws$.__enclos_env__$private$.emit_event("message", list(data = "hello"))
  expect_length(got, 1L)
  expect_identical(got[[1]]$event_type, "message")
  expect_identical(got[[1]]$data, "hello")
})

test_that("a throwing on_event handler warns but does not propagate", {
  ws <- StreamClient$new("wss://x")
  ws$on_event(function(e) stop("boom"))
  expect_warning(
    ws$.__enclos_env__$private$.emit_event("open", list(reconnect = FALSE)),
    "WebSocket handler error"
  )
})

# A fake websocket that records the lifecycle callbacks StreamClient wires, so a
# test can fire them with synthetic events and observe the typed lifecycle stream
# without a live socket. `.h` exposes the captured callbacks to the test.
make_fake_ws <- function(state = 1L) {
  h <- new.env()
  return(list(
    onOpen = function(cb) h$open <- cb,
    onMessage = function(cb) h$message <- cb,
    onClose = function(cb) h$close <- cb,
    onError = function(cb) h$error <- cb,
    connect = function() invisible(NULL),
    send = function(msg) invisible(NULL),
    close = function() invisible(NULL),
    readyState = function() state,
    .h = h
  ))
}
# `...` swallows the real generator's `autoConnect =` argument.
fake_ws_generator <- list(new = function(url, ...) make_fake_ws())

# Connect a StreamClient against a fresh fake socket, returning both the client
# and a capture list its $on_event() appends to.
connect_fake <- function(...) {
  ws <- StreamClient$new("wss://x", ...)
  got <- new.env()
  got$events <- list()
  ws$on_event(function(e) got$events[[length(got$events) + 1L]] <- e)
  ws$connect()
  return(list(ws = ws, got = got, fake = ws$.__enclos_env__$private$.ws))
}

collect_types <- function(events) {
  return(vapply(events, function(e) e$event_type, character(1)))
}

test_that("open fires a typed 'open' event (reconnect flag = FALSE on first connect)", {
  local_mocked_bindings(WebSocket = fake_ws_generator, .package = "websocket")
  h <- connect_fake(auto_reconnect = FALSE)
  on.exit(h$ws$close(), add = TRUE)
  h$fake$.h$open(list())
  open_ev <- Filter(function(e) e$event_type == "open", h$got$events)[[1]]
  expect_false(open_ev$reconnect)
})

test_that("close fires a typed 'close' event carrying code and reason", {
  local_mocked_bindings(WebSocket = fake_ws_generator, .package = "websocket")
  h <- connect_fake(auto_reconnect = FALSE)
  on.exit(h$ws$close(), add = TRUE)
  h$fake$.h$close(list(code = 1006, reason = "gone"))
  close_ev <- Filter(function(e) e$event_type == "close", h$got$events)[[1]]
  expect_identical(close_ev$code, 1006L)
  expect_identical(close_ev$reason, "gone")
})

test_that("a close with no code/reason yields NA fields (not an error)", {
  local_mocked_bindings(WebSocket = fake_ws_generator, .package = "websocket")
  h <- connect_fake(auto_reconnect = FALSE)
  on.exit(h$ws$close(), add = TRUE)
  h$fake$.h$close(list()) # no code / reason on the event
  close_ev <- Filter(function(e) e$event_type == "close", h$got$events)[[1]]
  expect_identical(close_ev$code, NA_integer_)
  expect_identical(close_ev$reason, NA_character_)
})

test_that("an error fires a typed 'error' event carrying the socket error", {
  local_mocked_bindings(WebSocket = fake_ws_generator, .package = "websocket")
  h <- connect_fake(auto_reconnect = FALSE)
  on.exit(h$ws$close(), add = TRUE)
  h$fake$.h$error(list(message = "socket boom"))
  err_ev <- Filter(function(e) e$event_type == "error", h$got$events)[[1]]
  expect_identical(err_ev$error$message, "socket boom")
})

test_that("a message frame fires a typed 'message' event carrying the text", {
  local_mocked_bindings(WebSocket = fake_ws_generator, .package = "websocket")
  h <- connect_fake(auto_reconnect = FALSE)
  on.exit(h$ws$close(), add = TRUE)
  h$fake$.h$message(list(data = "{\"a\":1}"))
  msg_ev <- Filter(function(e) e$event_type == "message", h$got$events)[[1]]
  expect_identical(msg_ev$data, "{\"a\":1}")
})

test_that("a reconnect fires a typed 'reconnect' event with attempt and delay", {
  local_mocked_bindings(WebSocket = fake_ws_generator, .package = "websocket")
  h <- connect_fake(auto_reconnect = TRUE)
  on.exit(h$ws$close(), add = TRUE) # cancels the scheduled reconnect timer
  # A close while running + auto_reconnect schedules a reconnect, which emits it.
  h$fake$.h$close(list(code = 1006, reason = "x"))
  rc_ev <- Filter(function(e) e$event_type == "reconnect", h$got$events)[[1]]
  expect_identical(rc_ev$attempt, 1L)
  expect_true(rc_ev$delay >= 1)
})

test_that("the raw $on() callbacks fire unchanged alongside $on_event (additive)", {
  local_mocked_bindings(WebSocket = fake_ws_generator, .package = "websocket")
  ws <- StreamClient$new("wss://x", auto_reconnect = FALSE)
  on.exit(ws$close(), add = TRUE)
  raw_msgs <- character()
  ws$on("message", function(msg) raw_msgs <<- c(raw_msgs, msg))
  typed <- new.env()
  typed$events <- list()
  ws$on_event(function(e) typed$events[[length(typed$events) + 1L]] <- e)
  ws$connect()
  ws$.__enclos_env__$private$.ws$.h$message(list(data = "RAW"))
  expect_identical(raw_msgs, "RAW") # the raw callback still got the string
  expect_true(any(collect_types(typed$events) == "message")) # and the typed stream fired
})
