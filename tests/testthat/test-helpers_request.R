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

test_that("build_request sends a raw body byte-verbatim (no prune, pretty-print, re-encode)", {
  # A null field is present and a list is compact — exactly the cases req_body_json
  # would mangle (drop the null, pretty-print). The raw path must touch nothing.
  exact <- '{"b":null,"a":1,"nested":[1,2,3]}'
  req <- build_request(
    base_url = "https://api.test",
    endpoint = "/o",
    method = "POST",
    body = exact,
    body_format = "raw",
    .perform = echo_perform,
    parse_envelope = echo_parse
  )
  expect_identical(req$body$data, exact) # byte-for-byte, no NULL-pruning / pretty-print
  expect_identical(req$body$content_type, "application/json") # default content type
})

test_that("build_request raw body honours a custom content type", {
  req <- build_request(
    base_url = "https://api.test",
    endpoint = "/o",
    method = "POST",
    body = "a=1&b=2",
    body_format = "raw",
    raw_content_type = "application/x-www-form-urlencoded",
    .perform = echo_perform,
    parse_envelope = echo_parse
  )
  expect_identical(req$body$data, "a=1&b=2")
  expect_identical(req$body$content_type, "application/x-www-form-urlencoded")
})

test_that("a sign hook reads the exact raw body bytes (body-signing venues)", {
  exact <- '{"price":"100.5","reduceOnly":false}'
  # The sign seam runs AFTER the body is set, so it can read req$body$data and
  # sign those exact bytes — emulating kucoin/hyperliquid body signing.
  body_signer <- function(req, keys, ctx) {
    seen <- req$body$data
    sig <- digest::hmac(keys$secret, seen, algo = "sha256")
    return(httr2::req_headers(req, Signature = sig, SignedBytes = seen))
  }
  req <- build_request(
    base_url = "https://api.test",
    endpoint = "/orders",
    method = "POST",
    body = exact,
    body_format = "raw",
    keys = list(secret = "s3cr3t"),
    sign = body_signer,
    .perform = echo_perform,
    parse_envelope = echo_parse
  )
  expect_identical(req$headers$SignedBytes, exact) # the signer saw the exact body
  expect_identical(
    req$headers$Signature,
    digest::hmac("s3cr3t", exact, algo = "sha256")
  )
})

test_that("build_request accepts a raw-vector body verbatim", {
  bytes <- charToRaw('{"k":"v"}')
  req <- build_request(
    base_url = "https://api.test",
    endpoint = "/o",
    method = "POST",
    body = bytes,
    body_format = "raw",
    .perform = echo_perform,
    parse_envelope = echo_parse
  )
  expect_identical(req$body$data, bytes)
})

test_that("build_request explodes a vector-valued query param (key repeated)", {
  req <- build_request(
    base_url = "https://api.test",
    endpoint = "/products",
    query = list(ids = c("A", "B")),
    .perform = echo_perform,
    parse_envelope = echo_parse
  )
  expect_s3_class(req, "httr2_request")
  expect_match(req$url, "ids=A&ids=B") # repeated key, not an error
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

# ---- Retry: the hard GET-only carve-out -------------------------------------

test_that("retry attaches on idempotency, not the verb (default GET-only, overridable)", {
  # GET default: idempotent -> retry attached.
  get_req <- build_request(
    base_url = "https://api.test",
    endpoint = "/p",
    method = "GET",
    max_tries = 3L,
    .perform = echo_perform,
    parse_envelope = echo_parse
  )
  expect_equal(get_req$policies$retry_max_tries, 3)

  # POST default: non-idempotent -> never a retry policy, whatever max_tries says.
  post_req <- build_request(
    base_url = "https://api.test",
    endpoint = "/orders",
    method = "POST",
    max_tries = 3L,
    .perform = echo_perform,
    parse_envelope = echo_parse
  )
  expect_null(post_req$policies$retry_max_tries)

  delete_req <- build_request(
    base_url = "https://api.test",
    endpoint = "/orders/1",
    method = "DELETE",
    max_tries = 3L,
    .perform = echo_perform,
    parse_envelope = echo_parse
  )
  expect_null(delete_req$policies$retry_max_tries)

  # A read-only POST explicitly marked idempotent -> retry attached (the
  # hyperliquid /info case: query encoded in the body).
  idem_post <- build_request(
    base_url = "https://api.test",
    endpoint = "/info",
    method = "POST",
    max_tries = 3L,
    idempotent = TRUE,
    .perform = echo_perform,
    parse_envelope = echo_parse
  )
  expect_equal(idem_post$policies$retry_max_tries, 3)

  # A GET explicitly marked non-idempotent -> no retry policy.
  non_idem_get <- build_request(
    base_url = "https://api.test",
    endpoint = "/p",
    method = "GET",
    max_tries = 3L,
    idempotent = FALSE,
    .perform = echo_perform,
    parse_envelope = echo_parse
  )
  expect_null(non_idem_get$policies$retry_max_tries)
})

# httr2's `req_perform()` short-circuits its retry loop whenever the `httr2_mock`
# option is set, so `local_mocked_responses()` returns the first response without
# ever retrying. To exercise the real retry loop we mock the per-attempt fetch
# (`httr2:::req_perform1`) instead, letting `req_perform()` re-drive it against
# the policy `build_request()` assembled; `sys_sleep` is stubbed so the jittered
# backoff does not slow the suite.
test_that("a POST is performed exactly once even with max_tries > 1 (no double-submit)", {
  n <- 0L
  testthat::local_mocked_bindings(
    sys_sleep = function(seconds, ...) invisible(),
    req_perform1 = function(req, req_prep, path, handle, resend_count) {
      n <<- n + 1L
      return(httr2::response(status_code = 500L, body = charToRaw("boom")))
    },
    .package = "httr2"
  )
  expect_error(
    build_request(
      base_url = "https://api.test",
      endpoint = "/orders",
      method = "POST",
      max_tries = 5L
    ),
    "HTTP error 500"
  )
  expect_identical(n, 1L) # a non-idempotent verb is never silently resent
})

test_that("a transient 500 on a GET is retried and then succeeds (max_tries = 3)", {
  n <- 0L
  testthat::local_mocked_bindings(
    sys_sleep = function(seconds, ...) invisible(),
    req_perform1 = function(req, req_prep, path, handle, resend_count) {
      n <<- n + 1L
      if (n == 1L) {
        return(httr2::response(status_code = 500L, body = charToRaw("transient")))
      }
      return(httr2::response(
        status_code = 200L,
        headers = list("content-type" = "application/json"),
        body = charToRaw('{"ok":true}')
      ))
    },
    .package = "httr2"
  )
  out <- build_request(
    base_url = "https://api.test",
    endpoint = "/v1/ping",
    method = "GET",
    max_tries = 3L
  )
  expect_true(out$ok)
  expect_identical(n, 2L) # retried once on the 500, then succeeded
})

# ---- The request deadline: a stub server that never responds -------------------
#
# Issue #19 (2026-09-28 incident): a documented 10-second per-request timeout
# did not stop a venue call from hanging for 600 seconds. `req_timeout()` is
# reliable on the synchronous branch (plain curl); on the asynchronous branch
# (`req_perform_promise()`) it is not, because of a suspected unit-mismatch bug
# in httr2 1.2.2's own pool poller (milliseconds fed into a seconds-denominated
# `later_fd()` wait -- see the file-header comment above `.perform_async_with_deadline()`
# in R/helpers_request.R, and NEWS, for the full mechanism) -- confirmed below
# against a real socket, never a mock, because httr2's mock seam never
# exercises curl's own timeout machinery at all.
#
# NOTE: every test below that touches `build_request()` or httr2 directly
# exercises the INSTALLED copy of this package (`library(connectcore)` inside
# a fresh `callr` subprocess loads whatever is in `.libPaths()`, not this
# source tree) -- after editing R/ code, reinstall (`R CMD INSTALL
# --no-multiarch .`) before re-running this file, or these tests silently
# exercise stale code.
#
# Every request against the stub server below runs in its OWN fresh subprocess
# (`run_against_stub()`). This is not incidental test hygiene: httr2's async
# branch shares ONE curl multi-handle for the whole R session, and an
# abandoned (never-settled) promise from an earlier test leaves that shared
# handle in a state that made the identical request against a brand-new,
# confirmed-listening stub server intermittently raise a spurious "Could not
# connect" within ~200ms when run later in the SAME session -- discovered
# while developing this suite. A fresh subprocess per test sidesteps that
# entirely; the subprocess's own `timeout` argument is also a second,
# independent safety net against a genuine regression hanging the suite.

testthat::skip_if_not_installed("callr")

# Is `port` in LISTEN state, per the OS itself (not an application-level
# signal)? Used to confirm the stub server below is actually bound and ready
# to accept BEFORE a test connects to it, without consuming the server's
# single accept() the way a connect-then-close probe would, and without
# guessing at R subprocess startup timing the way a fixed sleep would. `lsof`
# is near-universal on macOS/Linux dev and CI images; where it is genuinely
# absent, `.stub_server_is_listening()` falls back to a short fixed sleep
# (less robust, but no worse than this suite's behaviour before this check
# existed).
.stub_server_is_listening <- function(port) {
  if (nzchar(Sys.which("lsof"))) {
    out <- tryCatch(
      system2("lsof", c(sprintf("-iTCP:%d", port), "-sTCP:LISTEN", "-t"), stdout = TRUE, stderr = FALSE),
      error = function(e) character(0),
      warning = function(w) character(0)
    )
    return(length(out) > 0 && nzchar(out[1]))
  }
  Sys.sleep(0.5)
  return(TRUE)
}

# A minimal TCP stub server, run in a background process. It accepts exactly
# ONE connection (socketConnection(server = TRUE) performs the accept() at
# open time), then either:
#  - "silent": never reads or writes anything (holds the connection open),
#  - "late": sleeps `delay` seconds, then writes one minimal valid HTTP/1.1
#    response and closes, or
#  - "responsive": answers immediately with a minimal valid HTTP/1.1 response.
.start_stub_server <- function(mode = c("silent", "late", "responsive"), delay = 0) {
  mode <- match.arg(mode)
  port <- sample(20000:40000, 1)
  proc <- callr::r_bg(
    func = function(port, mode, delay) {
      con <- socketConnection(host = "0.0.0.0", port = port, server = TRUE, blocking = TRUE, open = "r+b")
      if (mode %in% c("late", "responsive")) {
        Sys.sleep(delay)
        body <- "{}"
        resp <- paste0(
          "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ",
          nchar(body),
          "\r\nConnection: close\r\n\r\n",
          body
        )
        tryCatch(
          {
            writeChar(resp, con, eos = NULL)
            flush(con)
          },
          error = function(e) NULL
        )
      } else {
        Sys.sleep(60) # "silent": accept the connection, never say a word
      }
      return(close(con))
    },
    args = list(port = port, mode = mode, delay = delay),
    user_profile = FALSE, # skip this project's renv/.Rprofile -- the stub needs only base R
    stdout = "|",
    stderr = "|"
  )
  ready_deadline <- lubridate::now("UTC") + lubridate::dseconds(5)
  ready <- FALSE
  while (!ready && lubridate::now("UTC") < ready_deadline) {
    if (.stub_server_is_listening(port)) {
      ready <- TRUE
    } else {
      Sys.sleep(0.02)
    }
  }
  if (!ready) {
    try(proc$kill(), silent = TRUE)
    stop("stub server did not report ready within 5s")
  }
  return(list(port = port, proc = proc))
}

# Start a stub server and arrange for it to be killed when the calling test
# (or its enclosing context) exits, following the package's withr::local_*
# convention for test-scoped resources.
local_stub_server <- function(mode = c("silent", "late"), delay = 0, env = parent.frame()) {
  srv <- .start_stub_server(mode = mode, delay = delay)
  withr::defer(try(srv$proc$kill(), silent = TRUE), envir = env)
  return(srv$port)
}

# Run `fn(...)` in a fresh subprocess against one or more stub servers (see the
# file-header note on why isolation matters here); `...` is forwarded to `fn`
# by name (almost always just `port = <port>`, occasionally more than one
# port). `timeout_secs` bounds the subprocess itself, independent of whatever
# wall-clock bound `fn` applies internally.
run_against_stub <- function(fn, ..., timeout_secs = 15) {
  return(tryCatch(
    callr::r(fn, args = list(...), timeout = timeout_secs, libpath = .libPaths(), user_profile = FALSE),
    error = function(e) list(outcome = "subprocess_timeout", message = conditionMessage(e))
  ))
}

test_that("FINDING: req_timeout() fires reliably on the sync branch against a stub that never responds", {
  port <- local_stub_server(mode = "silent")
  res <- run_against_stub(
    function(port) {
      library(httr2)
      library(lubridate)
      started <- lubridate::now("UTC")
      err <- tryCatch(
        httr2::req_perform(httr2::req_timeout(httr2::request(sprintf("http://127.0.0.1:%d/", port)), 1)),
        error = function(e) e
      )
      return(list(
        is_timeout = inherits(err, "httr2_failure") && inherits(err[["parent"]], "curl_error_operation_timedout"),
        elapsed = lubridate::time_length(lubridate::interval(started, lubridate::now("UTC")), "seconds")
      ))
    },
    port = port
  )
  expect_true(isTRUE(res$is_timeout))
  expect_lt(res$elapsed, 5) # fires close to the 1s timeout, nowhere near 600s
})

test_that("FINDING: req_timeout() does NOT fire on the async branch against a stub that never responds", {
  # This pins the production bug issue #19 is about: against a REAL socket
  # that accepts the TCP connection and never writes a byte, the promise
  # never settles at all -- timeout or no.
  port <- local_stub_server(mode = "silent")
  res <- run_against_stub(
    function(port) {
      library(httr2)
      library(promises)
      library(later)
      library(lubridate)
      req <- httr2::req_timeout(httr2::request(sprintf("http://127.0.0.1:%d/", port)), 1)
      done <- FALSE
      promises::then(
        httr2::req_perform_promise(req),
        onFulfilled = function(v) done <<- TRUE,
        onRejected = function(e) done <<- TRUE
      )
      deadline <- lubridate::now("UTC") + lubridate::dseconds(5)
      while (!done && lubridate::now("UTC") < deadline) {
        later::run_now(timeoutSecs = 0.05)
      }
      return(list(settled = done))
    },
    port = port
  )
  expect_false(isTRUE(res$settled)) # never settled in 5s past a 1s timeout
})

test_that("sync: a stalled request raises connectcore_request_deadline, not the raw curl error", {
  port <- local_stub_server(mode = "silent")
  res <- run_against_stub(
    function(port) {
      library(connectcore)
      err <- tryCatch(
        build_request(
          base_url = sprintf("http://127.0.0.1:%d", port),
          endpoint = "/v1/orders",
          method = "GET",
          timeout = 1,
          .perform = httr2::req_perform
        ),
        error = function(e) e
      )
      return(list(
        classes = class(err),
        method = err$method,
        host = err$host,
        path = err$path,
        elapsed = err$elapsed
      ))
    },
    port = port
  )
  expect_true("connectcore_request_deadline" %in% res$classes)
  expect_true("connectcore_error" %in% res$classes)
  expect_identical(res$method, "GET")
  expect_identical(res$host, "127.0.0.1")
  expect_identical(res$path, "/v1/orders")
  expect_true(res$elapsed > 0 && res$elapsed < 5)
})

test_that("async: a stalled request raises connectcore_request_deadline via the outer deadline guard", {
  port <- local_stub_server(mode = "silent")
  res <- run_against_stub(
    function(port) {
      library(connectcore)
      library(promises)
      library(later)
      library(lubridate)
      out <- build_request(
        base_url = sprintf("http://127.0.0.1:%d", port),
        endpoint = "/v1/orders",
        method = "GET",
        timeout = 1,
        deadline_margin = 0.5,
        .perform = httr2::req_perform_promise,
        is_async = TRUE
      )
      done <- FALSE
      ok <- NA
      err <- NULL
      promises::then(
        out,
        onFulfilled = function(v) {
          done <<- TRUE
          return(ok <<- TRUE)
        },
        onRejected = function(e) {
          done <<- TRUE
          ok <<- FALSE
          return(err <<- e)
        }
      )
      deadline <- lubridate::now("UTC") + lubridate::dseconds(5)
      while (!done && lubridate::now("UTC") < deadline) {
        later::run_now(timeoutSecs = 0.05)
      }
      return(list(
        done = done,
        ok = ok,
        classes = class(err),
        method = err$method,
        host = err$host,
        path = err$path,
        elapsed = err$elapsed
      ))
    },
    port = port
  )
  expect_true(res$done)
  expect_false(isTRUE(res$ok))
  expect_true("connectcore_request_deadline" %in% res$classes)
  expect_true("connectcore_error" %in% res$classes)
  expect_identical(res$method, "GET")
  expect_identical(res$host, "127.0.0.1")
  expect_identical(res$path, "/v1/orders")
  # Fires at ~ timeout + deadline_margin (1.5s), not at 600s and not never.
  expect_true(res$elapsed > 1 && res$elapsed < 4)
})

test_that("the deadline condition never carries the query string (credential-safe)", {
  port <- local_stub_server(mode = "silent")
  res <- run_against_stub(
    function(port) {
      library(connectcore)
      err <- tryCatch(
        build_request(
          base_url = sprintf("http://127.0.0.1:%d", port),
          endpoint = "/v1/orders",
          method = "GET",
          query = list(signature = "TOP-SECRET-SIG", symbol = "BTC"),
          timeout = 1,
          .perform = httr2::req_perform
        ),
        error = function(e) e
      )
      return(list(
        classes = class(err),
        path = err$path,
        message = conditionMessage(err)
      ))
    },
    port = port
  )
  expect_true("connectcore_request_deadline" %in% res$classes)
  expect_identical(res$path, "/v1/orders") # no "?", no query at all
  expect_false(grepl("signature", res$path, fixed = TRUE))
  expect_false(grepl("TOP-SECRET-SIG", res$path, fixed = TRUE))
  expect_false(grepl("TOP-SECRET-SIG", res$message, fixed = TRUE))
  expect_false(grepl("?", res$path, fixed = TRUE))
})

test_that("async: a real socket's late 200 never reaches the caller (integration; proof below is socket-free)", {
  # This is an integration-level check only: over a real socket, a late 200
  # never surfacing is also what plain unguarded req_perform_promise() would
  # show once ITS OWN httr2-level timeout eventually fires (whenever that is)
  # -- it cannot, by itself, tell our deadline/cancel mechanism apart from
  # that. The test below this one isolates OUR mechanism specifically with a
  # fully deterministic, socket-free mock that always SUCCEEDS, never errors,
  # so there is no other explanation available for the parser never running.
  port <- local_stub_server(mode = "late", delay = 3)
  res <- run_against_stub(
    function(port) {
      library(connectcore)
      library(promises)
      library(later)
      library(lubridate)
      n_parsed <- 0L
      out <- build_request(
        base_url = sprintf("http://127.0.0.1:%d", port),
        endpoint = "/v1/orders",
        method = "GET",
        timeout = 1,
        deadline_margin = 0.5,
        .perform = httr2::req_perform_promise,
        is_async = TRUE,
        .parser = function(x) {
          n_parsed <<- n_parsed + 1L
          return(x)
        }
      )
      done <- FALSE
      ok <- NA
      err <- NULL
      promises::then(
        out,
        onFulfilled = function(v) {
          done <<- TRUE
          return(ok <<- TRUE)
        },
        onRejected = function(e) {
          done <<- TRUE
          ok <<- FALSE
          return(err <<- e)
        }
      )
      first_deadline <- lubridate::now("UTC") + lubridate::dseconds(2) # well before the 3s late response
      while (!done && lubridate::now("UTC") < first_deadline) {
        later::run_now(timeoutSecs = 0.05)
      }
      # Keep pumping well past when the late response actually arrives, and
      # confirm the parser is never invoked -- the real request promise's
      # eventual fulfilment is abandoned, not delivered.
      extra_deadline <- lubridate::now("UTC") + lubridate::dseconds(4)
      while (lubridate::now("UTC") < extra_deadline) {
        later::run_now(timeoutSecs = 0.05)
      }
      return(list(done = done, ok = ok, classes = class(err), n_parsed = n_parsed))
    },
    port = port
  )
  expect_true(res$done)
  expect_false(isTRUE(res$ok))
  expect_true("connectcore_request_deadline" %in% res$classes)
  expect_identical(res$n_parsed, 0L)
})

test_that("async: a response that SUCCEEDS after the deadline is discarded, not delivered (socket-free proof)", {
  # No socket, no curl, no network at all: `.perform` is a mock whose promise
  # ALWAYS fulfils (never errors) via its own later() timer fired well after
  # our deadline. Nothing but build_request()'s own race + discard can explain
  # the parser never running here -- unlike the real-socket test above, there
  # is no competing explanation (an independent httr2/curl timeout) available.
  n_parsed <- 0L
  late_resolved <- FALSE
  mock_perform <- function(req, pool = NULL) {
    return(promises::promise(function(resolve, reject) {
      return(later::later(
        function() {
          late_resolved <<- TRUE
          return(resolve("late-success"))
        },
        delay = 1 # well after the 0.3s deadline below
      ))
    }))
  }
  out <- build_request(
    base_url = "http://example.test",
    endpoint = "/v1/orders",
    method = "GET",
    timeout = 0.2,
    deadline_margin = 0.1, # our deadline fires at ~0.3s
    .perform = mock_perform,
    is_async = TRUE,
    parse_envelope = identity,
    .parser = function(x) {
      n_parsed <<- n_parsed + 1L
      return(x)
    }
  )
  done <- FALSE
  ok <- NA
  err <- NULL
  promises::then(
    out,
    onFulfilled = function(v) {
      done <<- TRUE
      return(ok <<- TRUE)
    },
    onRejected = function(e) {
      done <<- TRUE
      ok <<- FALSE
      return(err <<- e)
    }
  )
  first_deadline <- lubridate::now("UTC") + lubridate::dseconds(2) # well before the mock's 1s success
  while (!done && lubridate::now("UTC") < first_deadline) {
    later::run_now(timeoutSecs = 0.02)
  }
  expect_true(done)
  expect_false(isTRUE(ok))
  expect_s3_class(err, "connectcore_request_deadline")

  # Keep pumping past the mock's own 1s success, and confirm it never reaches
  # the parser even though it DID eventually fire (proving this is a discard,
  # not a race the mock just happened to lose on its own).
  extra_deadline <- lubridate::now("UTC") + lubridate::dseconds(2)
  while (lubridate::now("UTC") < extra_deadline) {
    later::run_now(timeoutSecs = 0.02)
  }
  expect_true(late_resolved)
  expect_identical(n_parsed, 0L)
})

test_that("FINDING 1 regression: one deadline does not poison later async requests in the same process", {
  # Before the fix, build_request()'s async branch used httr2's shared DEFAULT
  # curl pool; an abandoned handle left there parked that pool's poller for a
  # suspected ~timeout*1000 seconds (httr2 1.2.2 ms/s bug -- see NEWS), so a
  # SECOND, wholly unrelated async request on the SAME pool also never settled
  # in any reasonable window, even against a server that answers immediately.
  # This proves the fix: every async request gets its own pool, and the
  # abandoned handle is actively cancelled on deadline, so nothing after it is
  # affected.
  stalled_port <- local_stub_server(mode = "silent")
  fast_port <- local_stub_server(mode = "responsive", delay = 0)
  res <- run_against_stub(
    function(stalled_port, fast_port) {
      library(connectcore)
      library(promises)
      library(later)
      library(lubridate)

      await_one <- function(promise, timeout_secs) {
        done <- FALSE
        ok <- NA
        promises::then(
          promise,
          onFulfilled = function(v) {
            done <<- TRUE
            return(ok <<- TRUE)
          },
          onRejected = function(e) {
            done <<- TRUE
            ok <<- FALSE
            return(invisible(NULL))
          }
        )
        deadline <- lubridate::now("UTC") + lubridate::dseconds(timeout_secs)
        while (!done && lubridate::now("UTC") < deadline) {
          later::run_now(timeoutSecs = 0.02)
        }
        return(list(done = done, ok = ok))
      }

      # Step 1: a request against the silent stub deadlines (~0.3s).
      stalled <- build_request(
        base_url = sprintf("http://127.0.0.1:%d", stalled_port),
        endpoint = "/v1/orders",
        method = "GET",
        timeout = 0.2,
        deadline_margin = 0.1,
        .perform = httr2::req_perform_promise,
        is_async = TRUE
      )
      first <- await_one(stalled, timeout_secs = 3)

      # Step 2: a SECOND, unrelated request to a FAST, responsive host, issued
      # immediately after. If the fix works, this settles in well under 1s;
      # on the pre-fix code this never settled within 10s (reproduced).
      started_second <- lubridate::now("UTC")
      fast <- build_request(
        base_url = sprintf("http://127.0.0.1:%d", fast_port),
        endpoint = "/v1/orders",
        method = "GET",
        .perform = httr2::req_perform_promise,
        is_async = TRUE,
        parse_envelope = identity
      )
      second <- await_one(fast, timeout_secs = 5)
      second_elapsed <- lubridate::time_length(lubridate::interval(started_second, lubridate::now("UTC")), "seconds")

      return(list(
        first_done = first$done,
        first_ok = first$ok,
        second_done = second$done,
        second_ok = second$ok,
        second_elapsed = second_elapsed
      ))
    },
    stalled_port = stalled_port,
    fast_port = fast_port,
    timeout_secs = 20
  )
  expect_true(res$first_done)
  expect_false(isTRUE(res$first_ok)) # the silent stub's request deadlined
  expect_true(res$second_done)
  expect_true(isTRUE(res$second_ok))
  expect_lt(res$second_elapsed, 1) # well under a second, not poisoned by the first
})

test_that("sync: a late response (after the deadline) still raises the deadline, not a stale success", {
  port <- local_stub_server(mode = "late", delay = 3)
  res <- run_against_stub(
    function(port) {
      library(connectcore)
      err <- tryCatch(
        build_request(
          base_url = sprintf("http://127.0.0.1:%d", port),
          endpoint = "/v1/orders",
          method = "GET",
          timeout = 1,
          .perform = httr2::req_perform
        ),
        error = function(e) e
      )
      return(list(classes = class(err)))
    },
    port = port
  )
  expect_true("connectcore_request_deadline" %in% res$classes)
})
