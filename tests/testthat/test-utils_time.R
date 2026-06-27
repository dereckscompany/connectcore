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
