// Copyright (C) 2025 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import encoding.url as encoding-url

normalize-percent-encoding_ str/string -> string:
  return encoding-url.encode (encoding-url.decode str)

/**
A URI reference.

Either a URI or a relative URI.

Relative URIs don't have a scheme, but may have an authority, path, query, and fragment.
*/
class UriReference:
  scheme/string?
  authority/string?
  path/string
  query/string?
  fragment/string?

  constructor
      --.scheme
      --.authority
      --.path
      --.query
      --.fragment:

  static parse str/string -> UriReference:
    sharp-index := str.index-of "#"
    fragment := ?
    if sharp-index == -1:
      fragment = null
    else:
      fragment = str[sharp-index + 1..]
      str = str[..sharp-index]

    query-index := str.index-of "?"
    query := ?
    if query-index == -1:
      query = null
    else:
      query = str[query-index + 1..]
      str = str[..query-index]

    // Try to find a scheme.
    scheme/string? := null

    for i := 0; i < str.size; i++:
      c := str[i]
      if c == ':':
        scheme = str[..i]
        str = str[i + 1..]
        break
      if not 'a' <= c <= 'z' and not 'A' <= c <= 'Z' and not '0' <= c <= '9' and c != '+' and c != '-' and c != '.':
        break

    // The authority must start with two slashes.
    authority/string? := null
    if str.size >= 2 and str[0] == '/' and str[1] == '/':
      for i := 2; i < str.size; i++:
        c := str[i]
        if c == '/' or c == '\\' or c == '?' or c == '#':
          authority = str[2..i]
          str = str[i..]
          break

    // The path is everything that's left.
    path := str

    return UriReference --scheme=scheme --authority=authority --path=str --query=query --fragment=fragment

  operator == other/any:
    if other is not UriReference: return false
    return scheme == other.scheme and
        authority == other.authority and
        path == other.path and
        query == other.query and
        fragment == other.fragment

  hash-code -> int:
    result := 0
    if scheme: result = 31 * result + scheme.hash-code
    if authority: result = 29 * result + authority.hash-code
    result = 37 * result + path.hash-code
    if query: result = 47 * result + query.hash-code
    if fragment: result = 97 * result + fragment.hash-code
    return result

  compare-to other/UriReference -> int:
    return compare-to other --if-equal=: 0

  compare-to other/UriReference [--if-equal] -> int:
    if scheme != other.scheme:
      if scheme == null: return -1
      if other.scheme == null: return 1
      return scheme.compare-to other.scheme
    if authority != other.authority:
      if authority == null: return -1
      if other.authority == null: return 1
      return authority.compare-to other.authority
    return path.compare-to other.path --if-equal=:
      if query != other.query:
        if query == null: return -1
        if other.query == null: return 1
        return query.compare-to other.query
      if fragment != other.fragment:
        if fragment == null: return -1
        if other.fragment == null: return 1
        return fragment.compare-to other.fragment
      return if-equal.call

  to-string -> string:
    result := ""
    if scheme != null: result = "$scheme:"
    if authority != null: result = "$result//$authority"
    result = "$result$path"
    if query != null: result = "$result?$query"
    if fragment != null: result = "$result#$fragment"
    return result

  stringify -> string:
    return to-string

  is-absolute -> bool:
    return scheme != null and fragment == null

  has-absolute-base -> bool:
    return scheme != null

  // https://datatracker.ietf.org/doc/html/rfc3986#section-5.2.4
  static remove-dot-segments_ path/string -> string:
    if not path.contains ".":
      return path

    // We add one char to avoid range checks.
    buffer := ByteArray (path.size + 2)
    buffer.replace 0 path

    source-pos := 0
    target-pos := 0
    making-progress := true
    while buffer[source-pos] != 0:
      // Skip leading "../" and "./"
      if buffer[source-pos] == '.' and buffer[source-pos + 1] == '.' and buffer[source-pos + 2] == '/':
        source-pos += 3
        continue

      if buffer[source-pos] == '.' and buffer[source-pos + 1] == '/':
        source-pos += 2
        continue

      // Replace leading "/./" and "/." (where . is a complete path segment) with "/".
      if buffer[source-pos] == '/' and
          buffer[source-pos + 1] == '.' and
          (buffer[source-pos + 2] == '/' or buffer[source-pos + 2] == 0):
        source-pos += 2
        buffer[source-pos] = '/'
        continue

      // If the input begins with a prefix "/../" or "/.." (where .. is a complete path segment),
      // drop the first segment in the output.
      if buffer[source-pos] == '/' and
          buffer[source-pos + 1] == '.' and
          buffer[source-pos + 2] == '.' and
          (buffer[source-pos + 3] == '/' or buffer[source-pos + 3] == 0):
        source-pos += 3
        while target-pos > 0 and buffer[target-pos] != '/':
          target-pos--
        continue

      // If the input is just "." or ".." then remove it.
      if buffer[source-pos] == '.' and buffer[source-pos + 1] == 0:
        source-pos++
        continue
      if buffer[source-pos] == '.' and buffer[source-pos + 1] == '.' and buffer[source-pos + 2] == 0:
        source-pos += 2
        continue

      // Copy the next path segment from input to output.
      // Start by copying the initial '/' (if any), and then loop.
      buffer[target-pos++] = buffer[source-pos++]
      while buffer[source-pos] != 0 and buffer[source-pos] != '/':
        buffer[target-pos++] = buffer[source-pos++]

    return buffer[0..target-pos].to-string

  // https://datatracker.ietf.org/doc/html/rfc3986#section-5.2.3
  static merge_ --base/UriReference --relative-path/string -> string:
    if base.authority and base.path == "":
      return "/$relative-path"

    base-path := base.path
    last-slash := base-path.index-of --last "/"
    if last-slash == -1:
      return relative-path
    return "$base-path[..last-slash]/$relative-path"

  // https://datatracker.ietf.org/doc/html/rfc3986#section-5.2.2
  resolve --base/UriReference -> UriReference:
    result-scheme/string? := null
    result-authority/string? := null
    result-path/string := ""
    result-query/string? := null
    result-fragment/string? := null

    result-fragment = fragment
    if scheme:
      result-scheme = scheme
      result-authority = authority
      result-path = remove-dot-segments_ path
      result-query = query
    else:
      result-scheme = base.scheme
      if authority:
        result-authority = authority
        result-path = remove-dot-segments_ path
        result-query = query
      else:
        result-authority = base.authority
        if path == "":
          result-path = base.path
          if query:
            result-query = query
          else:
            result-query = base.query
        else:
          result-query = query
          if path[0] == '/':
            result-path = remove-dot-segments_ path
          else:
            result-path = merge_ --base=base --relative-path=path
            result-path = remove-dot-segments_ result-path
    return UriReference
        --scheme=result-scheme
        --authority=result-authority
        --path=result-path
        --query=result-query
        --fragment=result-fragment

  // Note that we don't use the usual `with --scheme --authority ...` pattern, as we need
  // to be able to unset values.

  with-scheme scheme/string? -> UriReference:
    return UriReference --scheme=scheme --authority=authority --path=path --query=query --fragment=fragment

  with-authority authority/string? -> UriReference:
    return UriReference --scheme=scheme --authority=authority --path=path --query=query --fragment=fragment

  with-path path/string -> UriReference:
    return UriReference --scheme=scheme --authority=authority --path=path --query=query --fragment=fragment

  with-query query/string? -> UriReference:
    return UriReference --scheme=scheme --authority=authority --path=path --query=query --fragment=fragment

  with-fragment fragment/string? -> UriReference:
    return UriReference --scheme=scheme --authority=authority --path=path --query=query --fragment=fragment


  static normalize-scheme scheme/string? -> string?:
    if not scheme: return null
    return scheme.to-ascii-lower

  static normalize-authority authority/string? -> string?:
    if not authority: return null
    return (Authority.parse authority).normalize.to-string

  static normalize-path path/string -> string:
    // TODO(florian): have a normalize-percent-encoding-path that handles '/'.
    if path == "": return ""
    segments := path.split "/"
    segments.map --in-place: normalize-percent-encoding_ it
    return segments.join "/"

  static normalize-query query/string? -> string?:
    if not query: return null
    return normalize-percent-encoding_ query

  static normalize-fragment fragment/string? -> string?:
    if not fragment: return null
    // TODO(florian): have a normalize-percent-encoding-fragment that allows $, /, ...
    return normalize-percent-encoding_ fragment

  normalize -> UriReference:
    return UriReference
        --scheme=normalize-scheme scheme
        --authority=normalize-authority authority
        --path=normalize-path path
        --query=normalize-query query
        --fragment=normalize-fragment fragment

class Authority:
  userinfo/string?
  host/string
  port/int?

  constructor
      --.userinfo
      --.host
      --.port:

  static parse str/string -> Authority:
    if str == "":
      return Authority --userinfo=null --host="" --port=null

    at-index := str.index-of "@"
    userinfo/string? := ?
    if at-index == -1:
      userinfo = null
    else:
      userinfo = str[..at-index]
      str = str[at-index + 1..]

    host/string? := ?
    port/int? := ?
    if str.starts-with "[":
      // IPv6 address.
      close-bracket-index := str.index-of "]"
      if close-bracket-index == -1: throw "Invalid authority: missing closing bracket"
      host = str[1..close-bracket-index]
      str = str[close-bracket-index + 1..]
      if str.starts-with ":":
        port = int.parse str[1..]
      else:
        throw "Invalid authority: trailing characters after IPv6 address"
    else:
      // IPv4 address or domain name.
      colon-index := str.index-of ":"
      if colon-index == -1:
        host = str
        port = null
      else:
        host = str[..colon-index]
        port = int.parse str[colon-index + 1..]

    return Authority --userinfo=userinfo --host=host --port=port

  normalize -> Authority:
    return Authority
        --userinfo=normalize-userinfo userinfo
        --host=normalize-host host
        --port=port

  to-string -> string:
    result := ""
    if userinfo: result = "$userinfo@"
    result = "$result$host"
    if port: result = "$result:$port"
    return result

  stringify -> string:
    return to-string

  static normalize-userinfo userinfo/string? -> string?:
    if not userinfo: return null
    return normalize-percent-encoding_ userinfo

  static normalize-host host/string -> string:
    // Replace RFC 4007 IPv6 Zone ID delimiter '%' with '%25' from RFC 6874.
    // If the host is `[<IPv6 addr>%25]` then we assume RFC 4007 and normalize to
    // `[<IPv6 addr>%2525]`.
    // See https://github.com/python-hyper/rfc3986/blob/f3552bf793422c4f64cb46cee20d1b43cc3194cb/src/rfc3986/normalizers.py#L50
    if host.starts-with "[":
      // Assume it's an IPv6 address.
      percent-index := host.index-of "%"
      if percent-index != -1:
        percent25-index := host.index-of "%25"
        if percent25-index == -1 or
            percent-index < percent25-index or
            (percent-index == percent25-index and percent-index == host.size - 4):
          host = "$host[..percent-index]%25$host[percent-index + 1..]"
        // Don't normalize the casing of the Zone ID.
        lowered := host[..percent-index].to-ascii-lower
        rest := host[percent-index..]
        host = "$lowered$rest"
    else:
      host = host.to-ascii-lower
    return normalize-percent-encoding_ host
