# JSON -> data.table coercion toolkit.

test_that("to_snake_case handles camelCase, acronyms, and already-snake input", {
  expect_identical(to_snake_case("camelCase"), "camel_case")
  expect_identical(to_snake_case("openTime"), "open_time")
  expect_identical(to_snake_case("HTTPStatus"), "http_status")
  expect_identical(to_snake_case("already_snake"), "already_snake")
  expect_identical(to_snake_case(c("aB", "cD")), c("a_b", "c_d"))
})

test_that("coalesce_null returns x unless NULL", {
  expect_identical(coalesce_null(5), 5)
  expect_identical(coalesce_null(NULL, "fallback"), "fallback")
  expect_true(is.na(coalesce_null(NULL)))
})

test_that("num_or_na parses strings and maps empty/NULL to NA_real_", {
  expect_identical(num_or_na("3.5"), 3.5)
  expect_identical(num_or_na(42L), 42)
  expect_identical(num_or_na(NULL), NA_real_)
  expect_identical(num_or_na(list()), NA_real_)
  expect_identical(num_or_na("not-a-number"), NA_real_)
})

test_that("chr_or_na and lgl_or_na coerce or yield typed NA", {
  expect_identical(chr_or_na(10), "10")
  expect_identical(chr_or_na(NULL), NA_character_)
  expect_true(lgl_or_na("TRUE"))
  expect_identical(lgl_or_na(NULL), NA)
})

test_that("nth_num and nth_chr index positional arrays safely", {
  arr <- list("100", "1.5", "2.5")
  expect_identical(nth_num(arr, 2L), 1.5)
  expect_identical(nth_chr(arr, 1L), "100")
  expect_identical(nth_num(arr, 9L), NA_real_)
  expect_identical(nth_chr(NULL, 1L), NA_character_)
})

test_that("as_dt_row makes a one-row data.table with snake_case names and NA for NULL", {
  dt <- as_dt_row(list(openTime = 1, closePrice = NULL, symbol = "BTC"))
  expect_s3_class(dt, "data.table")
  expect_identical(nrow(dt), 1L)
  expect_identical(names(dt), c("open_time", "close_price", "symbol"))
  expect_true(is.na(dt$close_price))
})

test_that("as_dt_row wraps nested values into a single list-cell", {
  dt <- as_dt_row(list(id = 1, fills = list(list(a = 1), list(b = 2))))
  expect_identical(nrow(dt), 1L)
  expect_true(is.list(dt$fills))
})

test_that("as_dt_row and as_dt_list return empty tables for NULL/empty", {
  expect_identical(nrow(as_dt_row(NULL)), 0L)
  expect_identical(nrow(as_dt_row(list())), 0L)
  expect_identical(nrow(as_dt_list(NULL)), 0L)
})

test_that("as_dt_list row-binds heterogeneous records with fill", {
  dt <- as_dt_list(list(list(a = 1, b = 2), list(a = 3)))
  expect_identical(nrow(dt), 2L)
  expect_true(is.na(dt$b[2]))
})

test_that("coerce_cols mutates named columns in place and skips missing ones", {
  dt <- data.table::data.table(a = c("1", "2"), b = c("x", "y"))
  out <- coerce_cols(dt, c("a", "absent"), as.numeric)
  expect_identical(dt$a, c(1, 2)) # mutated by reference
  expect_true(is.numeric(out$a))
  expect_identical(dt$b, c("x", "y")) # untouched
})

test_that("coerce_cols enforces its contract", {
  expect_error(coerce_cols(list(a = 1), "a", as.numeric))
  dt <- data.table::data.table(a = 1)
  expect_error(coerce_cols(dt, "a", "not-a-function"))
})

test_that("collapse_string_array_fields joins arrays with ';' and NA-fills empties", {
  rec <- collapse_string_array_fields(
    list(codes = list("A", "B", "C"), empty = list(), name = "x"),
    c("codes", "empty")
  )
  expect_identical(rec$codes, "A;B;C")
  expect_identical(rec$empty, NA_character_)
  expect_identical(rec$name, "x") # untouched
})

test_that("collapse_string_array_fields warns when a value already contains ';'", {
  expect_warning(
    collapse_string_array_fields(list(codes = list("A;B")), "codes"),
    ";"
  )
})
