# File: R/utils_time.R
# Epoch <-> POSIXct conversions. APIs deliver time as epoch ms/ns/s; connectors
# return POSIXct (UTC). Doubles are kept (not integers) because epoch-ms exceeds
# the 32-bit integer range.

#' Convert an epoch value to POSIXct (UTC)
#'
#' @param value (numeric) epoch time.
#' @param unit (scalar<character in c("ms", "ns", "s")>) the input unit:
#'   milliseconds (default), nanoseconds, or seconds.
#' @return (class<POSIXct>) the time in UTC.
#' @importFrom lubridate as_datetime
#' @export
epoch_to_datetime <- function(value, unit = c("ms", "ns", "s")) {
  unit <- match.arg(unit)
  assert_args_epoch_to_datetime(value)
  seconds <- switch(unit, ms = value / 1000, ns = value / 1e9, s = value)
  return(lubridate::as_datetime(seconds, tz = "UTC"))
}

#' Convert POSIXct to an epoch value
#'
#' @param datetime (class<POSIXct>) the time to convert.
#' @param unit (scalar<character in c("ms", "ns", "s")>) the output unit:
#'   milliseconds (default), nanoseconds, or seconds.
#' @return (numeric) the epoch value in `unit` (a double; ms/ns exceed int range).
#' @export
datetime_to_epoch <- function(datetime, unit = c("ms", "ns", "s")) {
  unit <- match.arg(unit)
  assert_args_datetime_to_epoch(datetime)
  seconds <- as.numeric(datetime)
  return(switch(unit, ms = seconds * 1000, ns = seconds * 1e9, s = seconds))
}

#' Convert epoch milliseconds to POSIXct (UTC)
#'
#' Convenience for the common case; shape-preserving so an all-`NA` input still
#' yields a POSIXct vector (suitable for [coerce_cols()] on a column).
#'
#' @param ms (numeric) epoch milliseconds (may contain `NA`).
#' @return (class<POSIXct>) the times in UTC.
#' @importFrom lubridate as_datetime
#' @export
ms_to_datetime <- function(ms) {
  return(lubridate::as_datetime(as.numeric(ms) / 1000, tz = "UTC"))
}

#' Convert POSIXct to epoch milliseconds
#'
#' @param datetime (class<POSIXct>) the time(s) to convert.
#' @return (numeric) epoch milliseconds (a double).
#' @export
datetime_to_ms <- function(datetime) {
  assert_args_datetime_to_ms(datetime)
  return(as.numeric(datetime) * 1000)
}
