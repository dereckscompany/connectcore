# Shared HTTP-mock test harness. The whole point of mocking at httr2's native
# `httr2_mock` seam (rather than vcr) is that the SAME router intercepts both the
# synchronous req_perform() AND the asynchronous req_perform_promise(); the async
# proof below is the load-bearing test.

# Run a promise to completion on the local event loop and return its value.
drain <- function(promise) {
  result <- NULL
  resolved <- FALSE
  promises::then(promise, function(value) {
    result <<- value
    resolved <<- TRUE
    return(invisible(NULL))
  })
  while (!resolved && !later::loop_empty()) {
    later::run_now()
  }
  return(result)
}

# ---- mock_response ----

test_that("mock_response JSON-encodes a list body", {
  resp <- mock_response(list(symbol = "BTC", price = 100))
  expect_s3_class(resp, "httr2_response")
  expect_identical(httr2::resp_status(resp), 200L)
  expect_identical(httr2::resp_body_json(resp)$symbol, "BTC")
})

test_that("mock_response uses a single character body VERBATIM", {
  raw_json <- '{"captured": true, "n": 3}'
  resp <- mock_response(raw_json)
  expect_identical(httr2::resp_body_string(resp), raw_json)
})

test_that("mock_response returns an httr2_response unchanged (pass-through)", {
  built <- httr2::response(status_code = 204L, body = raw(0))
  expect_identical(mock_response(built), built)
})

test_that("mock_response honours status and headers", {
  resp <- mock_response(list(err = "bad"), status = 500L, headers = list("content-type" = "application/json"))
  expect_identical(httr2::resp_status(resp), 500L)
})

# ---- mock_router: URL-pattern routing (coinbase/alpaca/binance/kucoin) ----

url_routes <- list(
  list(match = "/products/BTC-USD/candles", fixture = function() list(candles = 1:3), method = NULL),
  list(match = "/products", fixture = function() list(products = "all"), method = NULL)
)

test_that("mock_router dispatches by URL substring, in order", {
  router <- mock_router(url_routes)
  resp <- router(httr2::request("https://api.exchange.coinbase.com/products/BTC-USD/candles"))
  expect_identical(httr2::resp_body_json(resp)$candles, list(1L, 2L, 3L))
  # the broader /products pattern matches when the candles one does not
  resp2 <- router(httr2::request("https://api.exchange.coinbase.com/products"))
  expect_identical(httr2::resp_body_json(resp2)$products, "all")
})

test_that("mock_router raises 'Unmocked request' with method and url", {
  router <- mock_router(url_routes)
  req <- httr2::req_method(httr2::request("https://api.test/unknown"), "GET")
  expect_error(
    router(req),
    "Unmocked request: GET https://api.test/unknown"
  )
})

test_that("mock_router routes by the method discriminator", {
  routes <- list(
    list(match = "/orders", fixture = function() list(action = "create"), method = "POST"),
    list(match = "/orders", fixture = function() list(action = "list"), method = "GET")
  )
  router <- mock_router(routes)
  post <- httr2::req_method(httr2::request("https://api.test/orders"), "POST")
  get <- httr2::req_method(httr2::request("https://api.test/orders"), "GET")
  expect_identical(httr2::resp_body_json(router(post))$action, "create")
  expect_identical(httr2::resp_body_json(router(get))$action, "list")
})

test_that("mock_router passes a fixture-built httr2_response through (204 no-content)", {
  no_content <- httr2::response(status_code = 204L, body = raw(0))
  routes <- list(list(match = "/margin_setting", fixture = function() no_content, method = "POST"))
  router <- mock_router(routes)
  resp <- router(httr2::req_method(httr2::request("https://api.test/margin_setting"), "POST"))
  expect_identical(httr2::resp_status(resp), 204L)
})

test_that("mock_router accepts a non-function fixture used as-is", {
  routes <- list(list(match = "/static", fixture = list(value = 1), method = NULL))
  router <- mock_router(routes)
  resp <- router(httr2::request("https://api.test/static"))
  expect_identical(httr2::resp_body_json(resp)$value, 1L)
})

# ---- mock_router: STATEFUL fixtures (kucoin pagination) ----

test_that("a stateful thunk paginates: page 1 then the empty page (kucoin)", {
  counter <- new.env(parent = emptyenv())
  counter$n <- 0L
  empty_page <- httr2::response(
    status_code = 200L,
    headers = list("content-type" = "application/json"),
    body = charToRaw('{"items": []}')
  )
  routes <- list(
    list(
      match = "/sub-accounts",
      fixture = function() {
        counter$n <- counter$n + 1L
        if (counter$n == 1L) {
          return(list(items = list(list(id = "sub-1"))))
        }
        return(empty_page) # an httr2_response, passed through
      },
      method = NULL
    )
  )
  router <- mock_router(routes)
  req <- httr2::request("https://api.kucoin.com/sub-accounts")
  first <- httr2::resp_body_json(router(req))
  expect_length(first$items, 1L)
  second <- httr2::resp_body_json(router(req))
  expect_length(second$items, 0L)
})

# ---- req_body_json ----

test_that("req_body_json reads a list body (req_body_json request)", {
  req <- httr2::req_body_json(httr2::request("https://api.test/info"), list(type = "meta"))
  expect_identical(req_body_json(req)$type, "meta")
})

test_that("req_body_json reads a character/raw body (req_body_raw request)", {
  exact <- '{"action":{"type":"order"},"nonce":1}'
  req_chr <- httr2::req_body_raw(httr2::request("https://api.test/exchange"), exact, "application/json")
  expect_identical(req_body_json(req_chr)$action$type, "order")
  req_raw <- httr2::req_body_raw(httr2::request("https://api.test/exchange"), charToRaw(exact), "application/json")
  expect_identical(req_body_json(req_raw)$action$type, "order")
})

test_that("req_body_json returns NULL for a bodyless request", {
  expect_null(req_body_json(httr2::request("https://api.test/info")))
})

# ---- body_routes + mock_router: body routing (hyperliquid) ----

info_routes <- list(meta = function() list(universe = "perps"), l2Book = function() list(levels = 2))
exchange_routes <- list(order = function() list(status = "ok"), cancel = function() list(status = "cancelled"))

hl_router <- mock_router(c(
  body_routes("/exchange", c("action", "type"), exchange_routes),
  body_routes("/info", "type", info_routes)
))

test_that("body_routes dispatches /info reads by body$type (hyperliquid)", {
  req <- httr2::req_body_json(httr2::request("https://api.hyperliquid.xyz/info"), list(type = "meta"))
  expect_identical(httr2::resp_body_json(hl_router(req))$universe, "perps")
  req2 <- httr2::req_body_json(httr2::request("https://api.hyperliquid.xyz/info"), list(type = "l2Book"))
  expect_identical(httr2::resp_body_json(hl_router(req2))$levels, 2L)
})

test_that("body_routes dispatches /exchange writes by body$action$type (hyperliquid)", {
  exact <- jsonlite::toJSON(list(action = list(type = "order"), nonce = 1), auto_unbox = TRUE)
  req <- httr2::req_body_raw(
    httr2::request("https://api.hyperliquid.xyz/exchange"),
    as.character(exact),
    "application/json"
  )
  expect_identical(httr2::resp_body_json(hl_router(req))$status, "ok")
})

test_that("body_routes raises 'Unmocked request' for an unknown body type", {
  req <- httr2::req_body_json(httr2::request("https://api.hyperliquid.xyz/info"), list(type = "nope"))
  expect_error(hl_router(req), "Unmocked request")
})

# ---- with_mock_api / local_mock_api: the SYNC + ASYNC proof ----

test_that("with_mock_api intercepts a SYNCHRONOUS req_perform()", {
  routes <- list(list(match = "/time", fixture = function() list(epoch = 1700000000), method = NULL))
  body <- with_mock_api(routes, {
    resp <- httr2::req_perform(httr2::request("https://api.test/time"))
    httr2::resp_body_json(resp)
  })
  expect_identical(body$epoch, 1700000000L)
})

test_that("with_mock_api intercepts an ASYNCHRONOUS req_perform_promise()", {
  # This is the whole reason for mocking at httr2's native seam: the SAME router
  # serves the async transport, so a connector's async path renders against the
  # same fixtures with no extra wiring.
  routes <- list(list(match = "/time", fixture = function() list(epoch = 1700000000), method = NULL))
  body <- with_mock_api(routes, {
    promise <- httr2::req_perform_promise(httr2::request("https://api.test/time"))
    resp <- drain(promise)
    httr2::resp_body_json(resp)
  })
  expect_identical(body$epoch, 1700000000L)
})

test_that("with_mock_api restores the previous httr2_mock option afterwards", {
  options(httr2_mock = NULL)
  with_mock_api(list(list(match = "/x", fixture = function() list(), method = NULL)), {
    expect_true(is.function(getOption("httr2_mock")))
  })
  expect_null(getOption("httr2_mock"))
})

test_that("local_mock_api installs the router for the rest of the scope", {
  options(httr2_mock = NULL)
  local({
    local_mock_api(list(list(match = "/ping", fixture = function() list(ok = TRUE), method = NULL)))
    resp <- httr2::req_perform(httr2::request("https://api.test/ping"))
    expect_true(httr2::resp_body_json(resp)$ok)
  })
  # the scope has exited: the option is restored
  expect_null(getOption("httr2_mock"))
})

# ---- load_fixtures ----

test_that("load_fixtures reads *.json keyed by basename, as raw strings or parsed", {
  dir <- withr::local_tempdir()
  writeLines('{"symbol": "BTC", "price": 100}', file.path(dir, "btc_ticker.json"))
  writeLines('{"symbol": "ETH"}', file.path(dir, "eth_ticker.json"))

  raw <- load_fixtures(dir, parse = FALSE)
  expect_setequal(names(raw), c("btc_ticker", "eth_ticker"))
  expect_type(raw$btc_ticker, "character")

  parsed <- load_fixtures(dir, parse = TRUE)
  expect_identical(parsed$btc_ticker$symbol, "BTC")
  expect_identical(parsed$btc_ticker$price, 100L)
})

test_that("load_fixtures returns an empty list for a directory with no JSON", {
  dir <- withr::local_tempdir()
  expect_length(load_fixtures(dir), 0L)
})

test_that("a load_fixtures string pairs with mock_response's verbatim path", {
  dir <- withr::local_tempdir()
  writeLines('{"captured": "verbatim"}', file.path(dir, "capture.json"))
  fixtures <- load_fixtures(dir, parse = FALSE)
  routes <- list(list(match = "/capture", fixture = fixtures$capture, method = NULL))
  router <- mock_router(routes)
  resp <- router(httr2::request("https://api.test/capture"))
  expect_identical(httr2::resp_body_json(resp)$captured, "verbatim")
})

# ---- contract enforcement ----

test_that("the harness enforces its roxyassert contracts", {
  expect_error(mock_response(list(), status = "200")) # status not a count
  expect_error(mock_router("not-a-list")) # routes must be a list
  expect_error(body_routes(1, "type", list())) # url_filter must be character
  expect_error(load_fixtures(123)) # dir must be character
})

# ---- back-compat: the connectors' existing tables key the URL field `pattern` ----

test_that("mock_router accepts `pattern` as the URL field (back-compat)", {
  # The five connectors' route tables all name the URL string `pattern`, not
  # `match`; the harness must route them unchanged.
  routes <- list(
    list(pattern = "/products/BTC-USD", fixture = function() list(id = "BTC-USD")),
    list(pattern = "/products", fixture = function() list(products = "all"))
  )
  router <- mock_router(routes)
  expect_identical(
    httr2::resp_body_json(router(httr2::request("https://api.test/products/BTC-USD")))$id,
    "BTC-USD"
  )
  expect_identical(
    httr2::resp_body_json(router(httr2::request("https://api.test/products")))$products,
    "all"
  )
})

test_that("mock_router prefers `match` over `pattern` when both are present", {
  routes <- list(list(match = "/win", pattern = "/lose", fixture = function() list(field = "matched")))
  router <- mock_router(routes)
  expect_identical(httr2::resp_body_json(router(httr2::request("https://api.test/win")))$field, "matched")
  expect_error(router(httr2::request("https://api.test/lose")), "Unmocked request")
})
