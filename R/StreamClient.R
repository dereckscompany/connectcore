# File: R/StreamClient.R
# Generic event-driven WebSocket client base for data-source connectors.

#' StreamClient: Event-Driven WebSocket Base for Connectors
#'
#' A Node.js-style event-driven base for long-lived WebSocket streams (exchange
#' market data, AIS vessel tracking, any push feed). You register handlers with
#' `$on(event, handler)` — exactly like `ws.on("message", ...)` in JavaScript —
#' and the library calls them as messages arrive on R's event loop (the `later`
#' package, which, like Node, is built on libuv). Concrete connectors subclass
#' it and override two seams — `.dispatch()` (how a raw frame becomes events) and
#' `.resubscribe()` (what to re-send after a (re)connect) — getting all of the
#' reconnect / keepalive / watchdog machinery for free.
#'
#' ### Why no `async` flag (unlike a REST client)
#' A REST call has a single result, so it can return a value (sync) or a promise
#' (async). A socket is an endless push stream with no single result, so the only
#' sensible shape is a callback. Streams are therefore always event-driven; the
#' one thing R needs that Node gives for free is a way to keep the process alive
#' and pump the loop — that is `$run()`.
#'
#' ### Events
#' The set is **open** — `$on(event, ...)` accepts any string, and a subclass'
#' `.dispatch()` may `emit` its own (e.g. one event per message type). The base
#' emits a standard core:
#' - `"open"` — the socket connected (payload: the open event).
#' - `"message"` — the default `.dispatch()` emits this for every frame, carrying
#'   the message as a **character string** (binary frames are decoded with
#'   [rawToChar()] first, so a handler always gets text).
#' - `"close"` / `"error"` — the socket closed / errored (payload: the event).
#' - `"reconnecting"` — about to retry (payload: `list(attempt, delay)`).
#' - `"reconnected"` — a reconnect (not the first connect) succeeded.
#' - `"giveup"` — `max_reconnects` exhausted; the `$run()` loop will exit.
#' - `"stale"` — the silence watchdog fired (no frame within `stale_timeout`).
#'
#' ### Connection management (handled for you)
#' - **Auto-reconnect** with full-jitter exponential backoff, so a reconnect
#'   storm cannot trip a connection rate limit.
#' - **Silence watchdog** — if `stale_timeout` is set and no frame arrives within
#'   it, the socket is force-closed and reopened (a dead connection that never
#'   fired `onClose`).
#' - **Proactive reconnect** — if `proactive_reconnect` is set, reconnect that
#'   many seconds after opening (e.g. to beat a server's 24-hour forced cutoff).
#' - **Re-subscribe** after every (re)connect via the `.resubscribe()` hook.
#' - **Keepalive** keeps one task on the `later` queue so a host-driven
#'   `while (!later::loop_empty())` loop never exits early between frames.
#'
#' @examples
#' \dontrun{
#' # A minimal recorder: subclass and override .dispatch to classify, or just use
#' # the default "message" event and append the raw text to a file.
#' ws <- StreamClient$new("wss://example.org/stream", stale_timeout = 120)
#' ws$on("open", function(e) ws$send('{"subscribe":"all"}'))
#' ws$on("message", function(msg) cat(msg, "\n"))
#' ws$run() # keeps the process alive and pumps the event loop
#' }
#'
#' @importFrom R6 R6Class
#' @export
StreamClient <- R6::R6Class(
  "StreamClient",
  public = list(
    #' @description
    #' Initialise a StreamClient
    #'
    #' @param url (scalar<character>) the WebSocket URL (`ws://` or `wss://`).
    #' @param auto_reconnect (scalar<logical>) reconnect automatically (with
    #'   backoff) when the socket drops. Default `TRUE`.
    #' @param max_reconnects (scalar<numeric>) give up after this many
    #'   consecutive failed reconnects (emit `"giveup"`, then `$run()` exits so a
    #'   supervisor can restart). `Inf` (default) retries forever — the right choice
    #'   for an unattended recorder.
    #' @param backoff_cap (scalar<numeric in ]0, Inf[>) maximum backoff delay in
    #'   seconds before the jitter floor. Default `60`.
    #' @param proactive_reconnect (scalar<numeric in ]0, Inf[> | NULL) reconnect
    #'   proactively this many seconds after opening (e.g. `82800` = 23h to beat a
    #'   24h cutoff). `NULL` (default) disables it.
    #' @param stale_timeout (scalar<numeric in ]0, Inf[> | NULL) force a reconnect
    #'   if no frame arrives within this many seconds (silence watchdog). `NULL`
    #'   (default) disables it.
    #' @param keepalive (scalar<numeric in ]0, Inf[>) interval in seconds of the
    #'   internal keepalive tick (also the watchdog's check granularity). Default
    #'   `30`.
    #' @return (class<StreamClient>) invisibly, self.
    initialize = function(
      url,
      auto_reconnect = TRUE,
      max_reconnects = Inf,
      backoff_cap = 60,
      proactive_reconnect = NULL,
      stale_timeout = NULL,
      keepalive = 30
    ) {
      assert_args_StreamClient__initialize(
        url,
        auto_reconnect,
        max_reconnects,
        backoff_cap,
        proactive_reconnect,
        stale_timeout,
        keepalive
      )
      private$.url <- url
      private$.auto_reconnect <- isTRUE(auto_reconnect)
      private$.max_reconnects <- max_reconnects
      private$.backoff_cap <- backoff_cap
      private$.proactive_reconnect <- proactive_reconnect
      private$.stale_timeout <- stale_timeout
      private$.keepalive <- keepalive
      private$.handlers <- list()
      return(invisible(assert_return_StreamClient__initialize(self)))
    },

    #' @description
    #' Register an Event Handler (Node-style `ws.on`)
    #'
    #' The event set is open: register handlers for the standard events (see the
    #' class description) or for any name a subclass' `.dispatch()` emits.
    #' @param event (scalar<character>) the event name.
    #' @param handler (function) called when the event fires, with that event's
    #'   payload.
    #' @return (class<StreamClient>) invisibly, self (chainable).
    on = function(event, handler) {
      assert_args_StreamClient__on(event, handler)
      private$.handlers[[event]] <- c(private$.handlers[[event]], handler)
      return(invisible(assert_return_StreamClient__on(self)))
    },

    #' @description
    #' Open the Connection
    #'
    #' Wires the socket callbacks and starts connecting, then returns immediately
    #' (non-blocking) — handlers only fire once something pumps `later`. Idempotent:
    #' a no-op if already connecting or open. Use `$run()` to drive the loop
    #' yourself, or call `$connect()` when the client lives inside a host that
    #' already runs a `later` loop.
    #' @return (class<StreamClient>) invisibly, self.
    connect = function() {
      if (private$.is_connecting_or_open()) {
        return(invisible(self))
      }
      private$.running <- TRUE
      private$.schedule_keepalive()
      private$.open_socket()
      return(invisible(assert_return_StreamClient__connect(self)))
    },

    #' @description
    #' Send a Raw Message
    #' @param message (scalar<character>) a string to send on the socket (typically
    #'   a JSON control/subscribe frame).
    #' @return (class<StreamClient>) invisibly, self.
    send = function(message) {
      assert_args_StreamClient__send(message)
      if (!private$.is_open()) {
        rlang::abort("Cannot send: socket is not open.")
      }
      private$.ws$send(message)
      return(invisible(assert_return_StreamClient__send(self)))
    },

    #' @description
    #' Run the Event Loop (keep the process alive)
    #'
    #' Connects if needed, then blocks and pumps R's `later` event loop so handlers
    #' keep firing. Runs until `$close()` is called or reconnects are exhausted.
    #' Teardown is clean and guaranteed — a normal close, an interrupt (Ctrl-C), or
    #' an error all close the socket and cancel timers via `on.exit()`. An interrupt
    #' returns quietly; any other error still propagates after cleanup.
    #' @param timeout (scalar<numeric in ]0, Inf[>) seconds each `later::run_now()`
    #'   tick waits for work before looping (keeps CPU near zero between messages).
    #'   Default `0.1`.
    #' @return (class<StreamClient>) invisibly, self.
    run = function(timeout = 0.1) {
      assert_args_StreamClient__run(timeout)
      if (!private$.is_connecting_or_open()) {
        self$connect()
      }
      on.exit(self$close(), add = TRUE)
      tryCatch(
        while (isTRUE(private$.running)) {
          later::run_now(timeout)
        },
        interrupt = function(cnd) {
          return(invisible(NULL))
        }
      )
      return(invisible(assert_return_StreamClient__run(self)))
    },

    #' @description
    #' Close the Connection
    #'
    #' Stops auto-reconnect, cancels timers, and closes the socket. After this,
    #' `$run()` returns.
    #' @return (class<StreamClient>) invisibly, self.
    close = function() {
      private$.running <- FALSE
      private$.cancel_keepalive()
      private$.cancel_timers()
      if (!is.null(private$.ws)) {
        try(private$.ws$close(), silent = TRUE)
      }
      return(invisible(assert_return_StreamClient__close(self)))
    },

    #' @description
    #' Is the Socket Open?
    #' @return (scalar<logical>) `TRUE` if the socket is open.
    is_open = function() {
      return(assert_return_StreamClient__is_open(private$.is_open()))
    }
  ),
  private = list(
    .url = NULL,
    .auto_reconnect = TRUE,
    .max_reconnects = Inf,
    .backoff_cap = 60,
    .proactive_reconnect = NULL,
    .stale_timeout = NULL,
    .keepalive = 30,
    .ws = NULL,
    .handlers = NULL,
    .running = FALSE,
    .reconnect_attempts = 0L,
    .last_activity = 0,
    .reconnect_timer = NULL,
    .proactive_timer = NULL,
    .keepalive_timer = NULL,
    .proactive_closing = FALSE,

    # ---- Overridable seams (subclasses customise these) ----

    # Turn one raw frame into events. The default emits "message" with the text;
    # override to classify (ack / heartbeat / error / per-channel demux) and emit
    # the relevant named events. Kept parse-free by default so the hot path never
    # deserialises a message it does not need to.
    .dispatch = function(raw) {
      private$.emit("message", raw)
      return(invisible(NULL))
    },

    # Re-send whatever subscription state the connection needs, called after every
    # (re)connect. The default is a no-op; override to replay subscriptions (build
    # the frames with `self$send()`).
    .resubscribe = function() {
      return(invisible(NULL))
    },

    # ---- Connection ----

    .open_socket = function() {
      ws <- websocket::WebSocket$new(private$.url, autoConnect = FALSE)
      ws$onOpen(function(event) {
        was_reconnect <- private$.reconnect_attempts > 0L
        private$.reconnect_attempts <- 0L
        private$.last_activity <- as.numeric(Sys.time())
        private$.resubscribe()
        private$.schedule_proactive_reconnect()
        private$.emit("open", event)
        if (was_reconnect) {
          private$.emit("reconnected", event)
        }
        return(invisible(NULL))
      })
      ws$onMessage(function(event) {
        private$.last_activity <- as.numeric(Sys.time())
        msg <- event$data
        if (is.raw(msg)) {
          msg <- rawToChar(msg) # binary frame carrying JSON/text
        }
        private$.dispatch(msg)
        return(invisible(NULL))
      })
      ws$onClose(function(event) {
        private$.cancel_timers()
        private$.emit("close", event)
        if (isTRUE(private$.running)) {
          if (isTRUE(private$.proactive_closing)) {
            private$.proactive_closing <- FALSE
            private$.open_socket() # planned refresh: reconnect now, no backoff
          } else if (private$.auto_reconnect) {
            private$.schedule_reconnect()
          }
        }
        return(invisible(NULL))
      })
      ws$onError(function(event) {
        private$.emit("error", event)
        if (isTRUE(private$.running) && private$.auto_reconnect && !private$.is_connecting_or_open()) {
          private$.schedule_reconnect()
        }
        return(invisible(NULL))
      })
      private$.ws <- ws
      ws$connect()
      return(invisible(NULL))
    },

    .is_open = function() {
      return(!is.null(private$.ws) && identical(private$.ws$readyState(), 1L))
    },

    .is_connecting_or_open = function() {
      return(!is.null(private$.ws) && private$.ws$readyState() %in% c(0L, 1L))
    },

    # ---- Emit ----

    .emit = function(event, payload) {
      for (h in private$.handlers[[event]]) {
        private$.safe_call(h, payload)
      }
      return(invisible(NULL))
    },

    # A throwing handler warns but never kills the loop.
    .safe_call = function(handler, payload) {
      tryCatch(
        handler(payload),
        error = function(e) rlang::warn(sprintf("WebSocket handler error: %s", conditionMessage(e)))
      )
      return(invisible(NULL))
    },

    # ---- Reconnection ----

    .schedule_reconnect = function() {
      if (private$.reconnect_pending()) {
        return(invisible(NULL))
      }
      private$.reconnect_attempts <- private$.reconnect_attempts + 1L
      if (private$.reconnect_attempts > private$.max_reconnects) {
        private$.emit("giveup", list(attempts = private$.reconnect_attempts - 1L))
        private$.running <- FALSE
        private$.cancel_keepalive()
        return(invisible(NULL))
      }
      delay <- ws_backoff_delay(private$.reconnect_attempts, private$.backoff_cap)
      private$.emit("reconnecting", list(attempt = private$.reconnect_attempts, delay = delay))
      private$.reconnect_timer <- later::later(
        function() {
          private$.reconnect_timer <- NULL
          if (isTRUE(private$.running)) {
            private$.open_socket()
          }
          return(invisible(NULL))
        },
        delay
      )
      return(invisible(NULL))
    },

    .reconnect_pending = function() {
      return(is.function(private$.reconnect_timer))
    },

    .schedule_proactive_reconnect = function() {
      if (is.null(private$.proactive_reconnect)) {
        return(invisible(NULL))
      }
      private$.proactive_timer <- later::later(
        function() {
          if (isTRUE(private$.running) && !is.null(private$.ws)) {
            private$.proactive_closing <- TRUE # tell onClose this is a planned refresh
            try(private$.ws$close(), silent = TRUE)
          }
          return(invisible(NULL))
        },
        private$.proactive_reconnect
      )
      return(invisible(NULL))
    },

    .cancel_timers = function() {
      # later::later() returns a function that cancels the callback when called.
      for (t in list(private$.reconnect_timer, private$.proactive_timer)) {
        if (is.function(t)) {
          try(t(), silent = TRUE)
        }
      }
      private$.reconnect_timer <- NULL
      private$.proactive_timer <- NULL
      return(invisible(NULL))
    },

    # ---- Keepalive + silence watchdog ----

    # Keep one task on the `later` queue for the whole active lifetime so a caller
    # driving the loop with `while (!later::loop_empty())` never sees an empty queue
    # and exits early. The same tick doubles as the silence watchdog.
    .schedule_keepalive = function() {
      private$.keepalive_timer <- later::later(
        function() {
          if (isTRUE(private$.running)) {
            private$.check_stale()
            private$.schedule_keepalive()
          }
          return(invisible(NULL))
        },
        private$.keepalive
      )
      return(invisible(NULL))
    },

    .check_stale = function() {
      if (is.null(private$.stale_timeout) || !private$.is_open()) {
        return(invisible(NULL))
      }
      silent_for <- as.numeric(Sys.time()) - private$.last_activity
      if (silent_for > private$.stale_timeout && !private$.reconnect_pending()) {
        private$.emit("stale", list(silent_for = silent_for))
        if (!is.null(private$.ws)) {
          try(private$.ws$close(), silent = TRUE) # onClose schedules the reconnect
        }
      }
      return(invisible(NULL))
    },

    .cancel_keepalive = function() {
      if (is.function(private$.keepalive_timer)) {
        try(private$.keepalive_timer(), silent = TRUE)
      }
      private$.keepalive_timer <- NULL
      return(invisible(NULL))
    }
  )
)
