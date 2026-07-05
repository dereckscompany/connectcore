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
  assert_args_epoch_to_datetime(value, unit)
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
  assert_args_datetime_to_epoch(datetime, unit)
  seconds <- as.numeric(datetime)
  return(switch(unit, ms = seconds * 1000, ns = seconds * 1e9, s = seconds))
}

#' Convert epoch milliseconds to POSIXct (UTC)
#'
#' The fleet-wide convenience for the common measurement-time case: connectors
#' feed it a raw JSON timestamp field whose R type is not known ahead of time
#' (numeric, character, or an all-`NA` logical when every record was empty). It
#' is length-preserving and NA-in -> NA-out, so an all-`NA` input still yields a
#' POSIXct vector of the same length (suitable for [coerce_cols()] on a column
#' documented as POSIXct — a scalar `NA` would be recycled into the column's
#' existing storage type rather than replacing it with a POSIXct one).
#'
#' @param ms (any | NULL) epoch millisecond timestamp(s); the raw JSON value,
#'   whose R type is unconstrained (numeric, character, or an all-`NA` logical).
#' @return (class<POSIXct>) a POSIXct vector in UTC (length matching `ms`), `NA`
#'   where `ms` is `NULL`/`NA`.
#' @importFrom lubridate as_datetime
#' @export
ms_to_datetime <- function(ms) {
  assert_args_ms_to_datetime(ms)
  # Default to the length-1 `NA_POSIXct_`, which is the `NULL` contract. Don't
  # short-circuit on `all(is.na(ms))`: the length-1 `NA_POSIXct_` would be
  # recycled by `data.table::set()` into the existing column's storage type
  # rather than replacing the column with a POSIXct one. The numeric/character
  # branches below always return a vector matching input length so columns
  # documented as POSIXct actually land as POSIXct, even when every upstream
  # value is missing.
  result <- lubridate::NA_POSIXct_
  if (is.null(ms)) {
    result <- lubridate::NA_POSIXct_
  } else if (is.numeric(ms)) {
    result <- lubridate::as_datetime(ms / 1000, tz = "UTC")
  } else {
    # Character (or other) path. Only feed real (non-NA) values to
    # `as.numeric()` so the documented NA-in -> NA-out contract is silent, while
    # a genuinely malformed string (e.g. `"not-a-number"`) still triggers the
    # usual "NAs introduced by coercion" warning; a blanket `suppressWarnings()`
    # would silence real bugs too.
    seconds <- rep(NA_real_, length(ms))
    not_na <- !is.na(ms)
    if (any(not_na)) {
      seconds[not_na] <- as.numeric(ms[not_na])
    }
    result <- lubridate::as_datetime(seconds / 1000, tz = "UTC")
  }
  return(assert_return_ms_to_datetime(result))
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
