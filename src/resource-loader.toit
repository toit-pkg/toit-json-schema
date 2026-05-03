// Copyright (C) 2025 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import certificate-roots
import http
import encoding.json
import net
import .schemas_.draft-2020-12 as draft-2020-12

/**
Resource loaders.
*/

/**
An interface for the resource loading of JSON schemas.
*/
interface ResourceLoader:
  load url/string -> any

/**
An HTTP based resource loader.

Uses HTTP 'GET' to fetch requested URLs.
*/
class HttpResourceLoader implements ResourceLoader:
  constructor:
    certificate-roots.install-all-trusted-roots

  load url/string -> any:
    cached := draft-2020-12.URL-MAPPING.get url
    if cached: return json.parse cached

    network := net.open
    client/http.Client? := null
    try:
      client = http.Client network
      response := client.get --uri=url
      if response.status-code != 200:
        throw "HTTP error: $response.status-code $response.status-message for $url"
      result := json.decode-stream response.body
      while response.body.read: null
      return result
    finally:
      if client: client.close
      network.close

