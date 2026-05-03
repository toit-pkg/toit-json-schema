// Copyright (C) 2025 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

/**
A simple regular expression engine.
*/

class Regex:
  token/Token

  constructor .token:

  match str/string -> bool:
    for i := 0; i <= str.size; i++:
      if (token.match str i: true):
        return true
    return false

skip-char_ str/string pos/int -> int:
  pos++
  while pos < str.size and str[pos] == null: pos++
  return pos

abstract class Token:
  abstract match str/string pos/int [match-rest] -> bool

class Individual extends Token:
  c/int

  constructor .c:

  match str/string pos/int [match-rest] -> bool:
    if pos >= str.size:
      return false
    if str[pos] == c:
      return match-rest.call (skip-char_ str pos)
    return false

class CharAny extends Token:
  match str/string pos/int [match-rest] -> bool:
    if pos >= str.size:
      return false
    // TODO(florian): we could exclude new-lines here.
    return match-rest.call (skip-char_ str pos)

class CharClass extends Token:
  is-negated/bool
  individuals/List
  ranges/List

  constructor --.is-negated --.individuals --.ranges:

  match str/string pos/int [match-rest] -> bool:
    if pos >= str.size:
      return false

    individuals.do: | c/int |
      if str[pos] == c:
        if is-negated:
          return false
        return match-rest.call (skip-char_ str pos)

    for i := 0; i < ranges.size; i += 2:
      c := str[pos]
      if ranges[i] <= c <= ranges[i + 1]:
        if is-negated:
          return false
        return match-rest.call (skip-char_ str pos)

    if is-negated:
      return match-rest.call (skip-char_ str pos)
    return false

class Multi extends Token:
  token/Token
  min/int
  max/int?
  // Since we don't allow captures, there isn't really a difference between eager
  // and lazy. However, it could affect the performance of evaluation, so we keep
  // it as a parameter.
  is-eager/bool

  constructor .token --.min --.max --.is-eager:

  match str/string pos/int [match-rest] -> bool:
    return match_ str pos --matched-count=0 match-rest

  match_ str/string pos/int --matched-count/int [match-rest] -> bool:
    if matched-count < min:
      return token.match str pos:
        match_ str it --matched-count=(matched-count + 1) match-rest

    if max and matched-count >= max:
      return match-rest.call pos

    if not is-eager:
      // Try to match the rest first.
      if match-rest.call pos:
        return true

    sub-match := token.match str pos:
      // Avoid unnecessary or infinite loops.
      if it == pos:
        match-rest.call pos
      else:
        match_ str it --matched-count=(matched-count + 1) match-rest
    if sub-match:
      return true

    if not is-eager:
      // We already tried the direct rest-match above.
      return false

    // Try to match the rest.
    return match-rest.call pos

class BeginningEnd extends Token:
  is-beginning/bool

  constructor --.is-beginning:

  match str/string pos/int [match-rest] -> bool:
    if is-beginning:
      if pos == 0:
        return match-rest.call pos
      return false
    else:
      if pos == str.size:
        return match-rest.call pos
      return false

class Alternatives extends Token:
  tokens/List

  constructor .tokens:

  match str/string pos/int [match-rest] -> bool:
    tokens.do: | token/Token |
      sub-match := token.match str pos match-rest
      if sub-match: return true
    return false

class Sequence extends Token:
  tokens/List

  constructor .tokens:

  match str/string pos/int [match-rest] -> bool:
    return match_ str pos --index=0 match-rest

  match_ str/string pos/int --index/int [match-rest] -> bool:
    if index >= tokens.size:
      return match-rest.call pos
    token/Token := tokens[index]
    return token.match str pos:
      match_ str it --index=(index + 1) match-rest

class Empty extends Token:
  match str/string pos/int [match-rest] -> bool:
    return match-rest.call pos

parse str/string -> Regex:
  parser := Parser_ str
  token := parser.parse-alternative --delimiter=null
  return Regex token

class Parser_:
  pos := 0
  str/string

  constructor .str:

  map-escaped-char_ c/int -> int:
    if c == 'n': return '\n'
    if c == 'r': return '\r'
    if c == 't': return '\t'
    if c == '0': return '\0'
    if c == 'f': return '\f'
    if c == 'v': return '\v'
    if c == 'b': return '\b'
    if c == 'a': return '\a'
    return c

  peek-char_ -> int?:
    if pos >= str.size:
      return null
    return str[pos]

  consume-char_ -> int?:
    if pos >= str.size:
      return null
    result := peek-char_
    pos++
    // Skip surrogate pairs.
    while pos < str.size and str[pos] == null: pos++
    return result

  parse-atom -> Token:
    c := consume-char_
    if c == '.':
      return CharAny
    if c == '\\':
      c = consume-char_
      if not c:
        throw "Expected escaped character"
      return Individual (map-escaped-char_ c)
    if c == '^':
      return BeginningEnd --is-beginning
    if c == '$':
      return BeginningEnd --is-beginning=false
    if c == '[':
      result := parse-char-class
      if consume-char_ != ']':
        throw "Expected ']'"
      return result
    if c == '(':
      result := parse-alternative --delimiter=')'
      if consume-char_ != ')':
        throw "Expected ')'"
      return result
    return Individual c

  parse-lazy_ -> bool:
    if peek-char_ == '?':
      consume-char_
      return true
    return false

  parse-number_ -> int?:
    start := pos
    result := 0
    while true:
      c := peek-char_
      if not '0' <= c <= '9':
        break
      consume-char_
      result = result * 10 + (c - '0')
    return pos == start ? null : result

  parse-char-class -> Token:
    start := pos
    is-negated := false
    individuals := List
    ranges := List
    change-next-to-range := false
    while pos < str.size:
      c := peek-char_
      if c == ']':
        if change-next-to-range:
          individuals.add '-'
        return CharClass --is-negated=is-negated --individuals=individuals --ranges=ranges
      if c == '^' and pos == start:
        consume-char_
        is-negated = true
        continue
      else if c == '-' and not individuals.is-empty and not change-next-to-range:
        change-next-to-range = true
        consume-char_
      else:
        consume-char_
        if c == '\\':
          // TODO(florian): we could recognize some character classes here.
          c = map-escaped-char_ consume-char_
        individuals.add c

        if change-next-to-range:
          change-next-to-range = false
          to := individuals.remove-last
          from := individuals.remove-last
          ranges.add from
          ranges.add to
    throw "Expected ']'"

  parse-multi -> Token:
    token := parse-atom
    while pos < str.size:
      c := peek-char_
      // Handle the modifiers (`+`, `?`, ...)
      if c == '?':
        consume-char_
        token = Multi token --min=0 --max=1 --is-eager=(not parse-lazy_)
      else if c == '*':
        consume-char_
        token = Multi token --min=0 --max=null --is-eager=(not parse_lazy_)
      else if c == '+':
        consume-char_
        token = Multi token --min=1 --max=null --is-eager=(not parse_lazy_)
      else if c == '{':
        consume-char_
        min := parse-number_
        max := min
        if peek-char_ == ',':
          consume-char_
          if peek-char_ != '}':
            max = parse-number_
          else:
            max = null
        if not consume-char_ == '}':
          throw "Expected '}': $str"
        token = Multi token --min=min --max=max --is-eager=(not parse-lazy_)
      else:
        break
    return token

  parse-sequence --delimiter/int? -> Token?:
    tokens := List
    while pos < str.size:
      c := peek-char_
      if c == delimiter:
        break
      // Not super clean, but 'parse-sequence' is always called from 'parse-alternative'.
      if c == '|':
        break
      tokens.add parse-multi

    if tokens.size == 0:
      return Empty
    if tokens.size == 1:
      return tokens[0]
    return Sequence tokens

  parse-alternative --delimiter/int? -> Token?:
    tokens := List
    while pos < str.size:
      tokens.add (parse-sequence --delimiter=delimiter)
      c := peek-char_
      if c == '|':
        consume-char_
        continue
      if c == delimiter:
        break
      if delimiter != null and c == null:
        throw "Expected delimiter: '$delimiter'"
      throw "Expected character: '$c'"

    if tokens.size == 0:
      return Empty
    if tokens.size == 1:
      return tokens[0]
    return Alternatives tokens
