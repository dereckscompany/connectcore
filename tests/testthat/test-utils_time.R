# Epoch <-> POSIXct conversions.

test_that("epoch_to_datetime converts each unit to the same UTC instant", {
  ms <- epoch_to_datetime(1700000000000, "ms")
  s <- epoch_to_datetime(1700000000, "s")
  ns <- epoch_to_datetime(1700000000000000000, "ns")
  expect_s3_class(ms, "POSIXct")
  expect_identical(as.numeric(ms), 1700000000)
  expect_identical(as.numeric(s), 1700000000)
  expect_identical(as.numeric(ns), 1700000000)
  expect_identical(attr(ms, "tzone"), "UTC")
})

test_that("epoch_to_datetime defaults to milliseconds", {
  expect_identical(
    as.numeric(epoch_to_datetime(1700000000000)),
    as.numeric(epoch_to_datetime(1700000000000, "ms"))
  )
})

test_that("datetime_to_epoch is the inverse of epoch_to_datetime", {
  dt <- epoch_to_datetime(1700000000000, "ms")
  expect_identical(datetime_to_epoch(dt, "ms"), 1700000000000)
  expect_identical(datetime_to_epoch(dt, "s"), 1700000000)
  expect_identical(datetime_to_epoch(dt, "ns"), 1700000000000000000)
})

test_that("ms_to_datetime / datetime_to_ms round-trip and preserve NA", {
  dt <- ms_to_datetime(c(1700000000000, NA))
  expect_s3_class(dt, "POSIXct")
  expect_true(is.na(dt[2]))
  expect_identical(datetime_to_ms(dt[1]), 1700000000000)
})

test_that("time conversions enforce their contracts", {
  expect_error(epoch_to_datetime(1, "decades"))
  expect_error(datetime_to_epoch("not-a-time", "ms"))
  expect_error(datetime_to_ms("not-a-time"))
})

# ms_to_datetime is the fleet-wide, type-stable measurement-time helper: raw
# JSON timestamps arrive as numeric, character, or an all-NA logical, and the
# contract is length-preserving, NA-in -> NA-out, POSIXct/UTC out.

test_that("ms_to_datetime converts a numeric vector to POSIXct (UTC)", {
  # 1729159459033 ms = 2024-10-17T10:04:19.033 UTC
  out <- ms_to_datetime(c(1729159459033, 1700000000000))
  expect_s3_class(out, "POSIXct")
  expect_identical(attr(out, "tzone"), "UTC")
  expect_length(out, 2L)
  expect_equal(as.numeric(out), c(1729159459.033, 1700000000), tolerance = 1e-3)
})

test_that("ms_to_datetime accepts numeric-as-character timestamps", {
  out <- ms_to_datetime(c("1729159459033", "1700000000000"))
  expect_s3_class(out, "POSIXct")
  expect_equal(as.numeric(out), c(1729159459.033, 1700000000), tolerance = 1e-3)
})

test_that("ms_to_datetime returns a same-length all-NA POSIXct for all-NA input", {
  # A logical all-NA vector is what an all-empty batch of records yields; the
  # result must be POSIXct (not logical) of the SAME length so a data.table
  # column documented as POSIXct actually lands as POSIXct.
  out <- ms_to_datetime(c(NA, NA, NA))
  expect_s3_class(out, "POSIXct")
  expect_length(out, 3L)
  expect_true(all(is.na(out)))
})

test_that("ms_to_datetime preserves NA positions within a mixed vector", {
  out <- ms_to_datetime(c(1700000000000, NA, 1729159459033))
  expect_s3_class(out, "POSIXct")
  expect_length(out, 3L)
  expect_false(is.na(out[1]))
  expect_true(is.na(out[2]))
  expect_false(is.na(out[3]))
})

test_that("ms_to_datetime returns an empty POSIXct for empty input", {
  out <- ms_to_datetime(numeric(0))
  expect_s3_class(out, "POSIXct")
  expect_length(out, 0L)
})

test_that("ms_to_datetime returns a scalar NA POSIXct for NULL/NA", {
  expect_s3_class(ms_to_datetime(NULL), "POSIXct")
  expect_true(is.na(ms_to_datetime(NULL)))
  expect_length(ms_to_datetime(NULL), 1L)
  expect_true(is.na(ms_to_datetime(NA)))
})

test_that("ms_to_datetime handles fractional and edge millisecond values", {
  out <- ms_to_datetime(c(0, 1729159459033.5))
  expect_s3_class(out, "POSIXct")
  expect_equal(as.numeric(out), c(0, 1729159459.0335), tolerance = 1e-3)
})

test_that("ms_to_datetime is silent on all-NA character input", {
  # `as.numeric(NA_character_)` emits "NAs introduced by coercion", but the
  # NA -> NA path is the documented contract and must not warn.
  expect_warning(ms_to_datetime(c(NA_character_, NA_character_)), NA)
  out <- ms_to_datetime(c(NA_character_, NA_character_))
  expect_s3_class(out, "POSIXct")
  expect_length(out, 2L)
  expect_true(all(is.na(out)))
})

test_that("ms_to_datetime still warns on genuinely malformed character input", {
  # Counter-regression: a blanket `suppressWarnings()` would silence real bugs.
  expect_warning(
    ms_to_datetime(c("not-a-number", NA_character_)),
    "NAs introduced by coercion"
  )
})
