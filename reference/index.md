# Package index

## Transport clients

The abstract REST base and the concrete event-driven WebSocket base that
connector packages extend.

- [`RestClient`](https://dereckscompany.github.io/connectcore/reference/RestClient.md)
  : RestClient: Abstract REST Client Base for Connectors
- [`StreamClient`](https://dereckscompany.github.io/connectcore/reference/StreamClient.md)
  : StreamClient: Event-Driven WebSocket Base for Connectors
- [`build_request()`](https://dereckscompany.github.io/connectcore/reference/build_request.md)
  : Build and perform a REST request (the single funnel)

## Authentication and signing

Request signing, credential loading, and nonces.

- [`hmac_query_sign()`](https://dereckscompany.github.io/connectcore/reference/hmac_query_sign.md)
  : Sign a request with HMAC-query authentication
- [`load_keys()`](https://dereckscompany.github.io/connectcore/reference/load_keys.md)
  : Load API credentials from environment variables
- [`next_nonce()`](https://dereckscompany.github.io/connectcore/reference/next_nonce.md)
  : Next monotonic nonce (epoch milliseconds, strictly increasing)

## Typed conditions

Classed transport errors every connector inherits and subclasses, plus
the credential-scrubbing helper. See the taxonomy and the connector
recipe.

- [`connectcore_conditions`](https://dereckscompany.github.io/connectcore/reference/connectcore_conditions.md)
  : Typed transport conditions and the connector recipe
- [`abort_api_error()`](https://dereckscompany.github.io/connectcore/reference/abort_api_error.md)
  : Raise a typed HTTP API error
- [`abort_response_error()`](https://dereckscompany.github.io/connectcore/reference/abort_response_error.md)
  : Raise a typed response-parse error
- [`abort_stream_error()`](https://dereckscompany.github.io/connectcore/reference/abort_stream_error.md)
  : Raise a typed stream error
- [`scrub_url()`](https://dereckscompany.github.io/connectcore/reference/scrub_url.md)
  : Redact query-string credentials from a URL

## Time conversion

Epoch and POSIXct conversions and server-time helpers.

- [`epoch_to_datetime()`](https://dereckscompany.github.io/connectcore/reference/epoch_to_datetime.md)
  : Convert an epoch value to POSIXct (UTC)
- [`datetime_to_epoch()`](https://dereckscompany.github.io/connectcore/reference/datetime_to_epoch.md)
  : Convert POSIXct to an epoch value
- [`ms_to_datetime()`](https://dereckscompany.github.io/connectcore/reference/ms_to_datetime.md)
  : Convert epoch milliseconds to POSIXct (UTC)
- [`datetime_to_ms()`](https://dereckscompany.github.io/connectcore/reference/datetime_to_ms.md)
  : Convert POSIXct to epoch milliseconds
- [`fetch_server_time_ms()`](https://dereckscompany.github.io/connectcore/reference/fetch_server_time_ms.md)
  : Fetch a server's time in epoch milliseconds
- [`then_or_now()`](https://dereckscompany.github.io/connectcore/reference/then_or_now.md)
  : Apply a continuation to a value or a promise

## Response parsing

JSON to data.table coercion and name conversion.

- [`as_dt_row()`](https://dereckscompany.github.io/connectcore/reference/as_dt_row.md)
  : Convert a named list to a one-row data.table
- [`as_dt_list()`](https://dereckscompany.github.io/connectcore/reference/as_dt_list.md)
  : Row-bind a list of records into a data.table
- [`to_snake_case()`](https://dereckscompany.github.io/connectcore/reference/to_snake_case.md)
  : Convert camelCase names to snake_case
- [`coerce_cols()`](https://dereckscompany.github.io/connectcore/reference/coerce_cols.md)
  : Coerce columns of a data.table in place
- [`collapse_string_array_fields()`](https://dereckscompany.github.io/connectcore/reference/collapse_string_array_fields.md)
  : Collapse plain-string array fields to semicolon-joined scalars
- [`parse_json_response()`](https://dereckscompany.github.io/connectcore/reference/parse_json_response.md)
  : Default response parser: JSON body, error on non-2xx

## Accessors and coercion

Null-safe scalar accessors and type coercion.

- [`nth_chr()`](https://dereckscompany.github.io/connectcore/reference/nth_chr.md)
  : The nth element of a positional array as character (or NA)
- [`nth_num()`](https://dereckscompany.github.io/connectcore/reference/nth_num.md)
  : The nth element of a positional array as numeric (or NA)
- [`chr_or_na()`](https://dereckscompany.github.io/connectcore/reference/chr_or_na.md)
  : Coerce a scalar to character, or NA
- [`num_or_na()`](https://dereckscompany.github.io/connectcore/reference/num_or_na.md)
  : Coerce a scalar to numeric, or NA
- [`lgl_or_na()`](https://dereckscompany.github.io/connectcore/reference/lgl_or_na.md)
  : Coerce a scalar to logical, or NA
- [`coalesce_null()`](https://dereckscompany.github.io/connectcore/reference/coalesce_null.md)
  : First non-NULL value

## Environment and configuration

Environment-backed configuration lookups.

- [`env_or()`](https://dereckscompany.github.io/connectcore/reference/env_or.md)
  : Read an environment variable with a default
- [`url_getter()`](https://dereckscompany.github.io/connectcore/reference/url_getter.md)
  : Make a base-URL getter backed by an environment variable

## WebSocket helpers

Backoff, event constants, typed lifecycle events, and a file sink for
stream recorders.

- [`ws_backoff_delay()`](https://dereckscompany.github.io/connectcore/reference/ws_backoff_delay.md)
  : Full-jitter exponential reconnect backoff (seconds)
- [`ws_file_sink()`](https://dereckscompany.github.io/connectcore/reference/ws_file_sink.md)
  : A message handler that appends each frame to a connection
- [`ws_event()`](https://dereckscompany.github.io/connectcore/reference/ws_event.md)
  : Construct a typed WebSocket lifecycle event
- [`WS_EVENTS`](https://dereckscompany.github.io/connectcore/reference/WS_EVENTS.md)
  : WebSocket Events
- [`WS_EVENT_TYPES`](https://dereckscompany.github.io/connectcore/reference/WS_EVENT_TYPES.md)
  : WebSocket Lifecycle Event Types

## Test harness

A shared HTTP-mock toolkit over httr2’s native mock hook, for testing
and documenting a connector against canned fixtures (sync and async).

- [`mock_response()`](https://dereckscompany.github.io/connectcore/reference/mock_response.md)
  :

  Build a mock `httr2` response from fixture data

- [`mock_router()`](https://dereckscompany.github.io/connectcore/reference/mock_router.md)
  :

  Build a mock HTTP router (an `httr2` mock hook)

- [`body_routes()`](https://dereckscompany.github.io/connectcore/reference/body_routes.md)
  : Build body-discriminated routes from a named case table

- [`req_body_json()`](https://dereckscompany.github.io/connectcore/reference/req_body_json.md)
  : Parse a request's JSON body

- [`with_mock_api()`](https://dereckscompany.github.io/connectcore/reference/with_mock_api.md)
  : Run code with a mock router installed

- [`local_mock_api()`](https://dereckscompany.github.io/connectcore/reference/local_mock_api.md)
  : Install a mock router for the rest of the current scope

- [`load_fixtures()`](https://dereckscompany.github.io/connectcore/reference/load_fixtures.md)
  : Load JSON fixtures from a directory
