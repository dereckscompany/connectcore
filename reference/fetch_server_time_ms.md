# Fetch a server's time in epoch milliseconds

A lightweight synchronous GET against a server-time endpoint, returning
epoch milliseconds. Used when signing against the server clock instead
of the local one (to avoid drift). The `field` is the JSON key holding
the time.

## Usage

``` r
fetch_server_time_ms(base_url, time_endpoint, field = "serverTime")
```

## Arguments

- base_url:

  (scalar\<character\>) the API base URL.

- time_endpoint:

  (scalar\<character\>) the path of the time endpoint.

- field:

  (scalar\<character\>) the response JSON key holding epoch ms. Default
  `"serverTime"`.

## Value

(scalar\<numeric\>) server time in epoch milliseconds.
