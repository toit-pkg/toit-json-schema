// Copyright (C) 2025 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import json-pointer show *
import .schema

class Result:
  /**
  When this result is converted to JSON with the structure equal to $STRUCTURE-FLAG,
    then the returned object contains a single field "valid" with the value of $is-valid.
  */
  static STRUCTURE-FLAG ::= 0
  /**
  When this result is converted to JSON with the structure equal to $STRUCTURE-BASIC,
    then the returned object contains the following fields:
  - "valid": A boolean indicating whether the validation was successful.
  - "annotations"/"errors": A list of annotations or errors, depending on $is-valid.

  See $Detail.to-json for the structure of the annotations and errors.
  */
  static STRUCTURE-BASIC ::= 1

  // The result of the root schema.
  schema-result_/SubResult

  constructor.private_ .schema-result_:

  annotations-for instance-pointer/JsonPointer -> List:
    return schema-result_.annotations.get instance-pointer --if-absent=: []

  /** Whether the validation was successful. */
  is-valid -> bool:
    return schema-result_.is-valid

  /** A list of details of type $Detail. */
  details -> List:
    if not schema-result_.is-valid:
      return schema-result_.errors.copy or []
    if not schema-result_.annotations: return []

    annotations := []
    schema-result_.annotations.do --values: | value/List |
      annotations.add-all value
    return annotations

  /**
  Returns this result as a JSON object.

  Dependening on the $structure-kind, the returned object has different fields.

  If $structure-kind is equal to $STRUCTURE-FLAG, then the returned object consists
    of a map with a single field:
  - "valid": A boolean indicating whether the validation was successful.

  If $structure-kind is equal to $STRUCTURE-BASIC, then the returned object consists
    of a map with the following fields:
  - "valid": A boolean indicating whether the validation was successful.
  - "annotations": A list of annotations. This field is only present if the validation
    was successful. See $Detail.to-json for the structure of the annotations.
  - "errors": A list of map from instance pointers to lists of errors. This field is
    only present if the validation was not successful. See $Detail.to-json for the
    structure of the errors.
  */
  to-json --structure-kind/int=STRUCTURE-BASIC -> Map:
    if structure-kind != STRUCTURE-FLAG and structure-kind != STRUCTURE-BASIC:
      throw "INVALID_ARGUMENT"

    if structure-kind == STRUCTURE-FLAG:
      return {"valid": is-valid}

    json-details := details.map: | detail/Detail |
      detail.to-json

    return {
      "valid": is-valid,
      is-valid ? "annotations" : "errors": json-details
    }

class SubResult:
  location/InstantiatedSchema?
  instance-pointer/JsonPointer
  is-valid/bool := true
  annotations/Map? := null
  errors/List? := null

  constructor .location .instance-pointer:

  /**
  Merges the $sub result into this one.
  Reuses the $sub result's fields if possible. This means that the $sub result
    can not be used after this method is called.

  If the given $sub is not valid, marks this instance as not valid.

  Only merges annotations if the $sub is valid.
  */
  merge sub/SubResult -> none:
    if not sub.is-valid:
      is-valid = false

    if sub.errors:
      assert: not sub.is-valid
      if not errors:
        errors = sub.errors
      else:
        errors.add-all sub.errors

    if sub.is-valid and sub.annotations:
      if not annotations:
        annotations = sub.annotations
      else:
        sub.annotations.do: | key/string sub-entries/List |
          this-entry := annotations.get key
          if not this-entry:
            annotations[key] = sub-entries
          else:
            this-entry.add-all sub-entries

  fail-false -> none:
    is-valid = false
    error := Detail.false-error
        --instance-pointer=instance-pointer
        --location=location
    errors = [error]

  fail -> none
      keyword/string
      value/any
      --instance-pointer=instance-pointer
  :
    is-valid = false
    if not errors:
      errors = []
    error := Detail.error
        --keyword=keyword
        --instance-pointer=instance-pointer
        --location=location
        value
    errors.add error

  annotate -> none
      keyword/string
      value/any
  :
    if not annotations:
      annotations = {:}
    annotation-key := instance-pointer.to-string
    entries := annotations.get annotation-key --init=:[]
    annotation := Detail.annotation
        --keyword=keyword
        --instance-pointer=instance-pointer
        --location=location
        value
    entries.add annotation

/**
An annotation or error.
*/
class Detail:
  is-error/bool
  keyword/string?
  instance-pointer/JsonPointer
  location/InstantiatedSchema
  value/any

  constructor.annotation --.keyword --.instance-pointer --.location .value:
    is-error = false

  constructor.error --.keyword --.instance-pointer --.location .value:
    is-error = true

  constructor.false-error --.instance-pointer --.location:
    is-error = true
    keyword = null
    value = "This instance is disallowed by a boolean 'false' schema."

  /**
  Converts this detail to JSON.

  The returned object contains the following fields:
  - `keywordLocation`: the relative location, as JSON pointer, of the keyword that
    produced the detail.
  - `absoluteKeywordLocation`: the absolute, dereferenced location of the keyword
    that produced the detail. This location is constructed using the canonical
    URL of the schema resource with a JSON pointer fragment.
  - `instanceLocation`: the location, as JSON pointer, of the JSON value within the
    instance that produced the detail.
  */
  to-json:
    result := {:}
    keyword-location := keyword ? [keyword] : []
    current/InstantiatedSchema? := location
    while current:
      keyword-location.add current.segment
      current = current.parent
    i := 0
    j := keyword-location.size - 1
    while i < j:
      t := keyword-location[i]
      keyword-location[i++] = keyword-location[j]
      keyword-location[j--] = t

    result["keywordLocation"] = keyword-location.join "/"
    absolute-location := location.schema.absolute-location.to-string
    if keyword: absolute-location += "/$keyword"
    result["absoluteKeywordLocation"] = absolute-location
    result["instanceLocation"] = instance-pointer.to-string
    json-value := value
    if json-value is Set: json-value = json-value.to-list
    if is-error:
      result["error"] = json-value
    else:
      result["annotation"] = json-value
    return result

