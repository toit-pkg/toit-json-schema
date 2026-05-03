// Copyright (C) 2025 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import json-pointer show *

import .regex_ as regex
import .schema
import .store_
import .validation
import .uri

/**
Actions are the building blocks of JSON Schema validation.

An $Action is either an $Applicator or an $Assertion.
An $Applicator validates a JSON value against one or more subschemas.
  Examples of applicators are $Properties, $Items, AllOf ($X-Of), $Ref.
An $Assertion validates a JSON value against some criteria that does not involve subschemas.
  Examples of assertions are $Type, $Enum, $Const, $StringLength.
*/

/**
The base class for all actions.
*/
abstract class Action:
  static ORDER-EARLY ::= 20
  static ORDER-DEFAULT ::= 50
  static ORDER-LATE ::= 70

  /**
  The order/precedence of the action.

  An action with a lower order is executed before an action with a higher order.

  Typically, actions that are fast to execute should be executed first, so that their failure
    short-circuits the validation.

  Applicators should never run after ORDER-LATE, as the $UnevaluatedProperties and $UnevaluatedItems applicators
    are run at that level and need to know whether subschemas have evaluated properties/items.
  */
  abstract order -> int

  /**
  Validates the given JSON value $o against this action.

  The $context provides global information about the validation process, such
    as whether annotations are needed, or how to resolve dynamic references (the
    $ValidationContext.store).

  The $location is the instantiated schema (a schema that has been resolved
    and has a dynamic location in the schema tree).

  The $instance-pointer points to the location of $o.
  */
  abstract validate o/any -> SubResult
      --context/ValidationContext
      --location/InstantiatedSchema
      --instance-pointer/JsonPointer

  abstract accept visitor/ActionVisitor -> any

interface ActionVisitor:
  visit-Ref ref/Ref -> any
  visit-X-Of x-of/X-Of -> any
  visit-Not not_/Not -> any
  visit-IfThenElse if-then-else/IfThenElse -> any
  visit-DependentSchemas dependent-schemas/DependentSchemas -> any
  visit-Properties properties/Properties -> any
  visit-PropertyNames property-names/PropertyNames -> any
  visit-Contains contains/Contains -> any
  visit-Type type/Type -> any
  visit-Enum enum_/Enum -> any
  visit-Const const/Const -> any
  visit-NumComparison num-comparison/NumComparison -> any
  visit-StringLength string-length/StringLength -> any
  visit-ArrayLength array-length/ArrayLength -> any
  visit-UniqueItems unique-items/UniqueItems -> any
  visit-Required required/Required -> any
  visit-ObjectSize object-size/ObjectSize -> any
  visit-Items items/Items -> any
  visit-Pattern pattern/Pattern -> any
  visit-DependentRequired dependent-required/DependentRequired -> any
  visit-UnevaluatedProperties unevaluated-properties/UnevaluatedProperties -> any
  visit-UnevaluatedItems unevaluated-items/UnevaluatedItems -> any
  visit-Annotation annotation/Annotation -> any
  visit-Format format/Format -> any
  visit-Discriminator discriminator/Discriminator -> any


/**
The base class for all applicator actions.

Applicators validate a JSON value against one or more subschemas.
*/
abstract class Applicator extends Action:
  order -> int:
    return Action.ORDER-DEFAULT

abstract class AnnotationsApplicator extends Applicator:
  order -> int:
    return Action.ORDER-LATE

  abstract validate o/any -> SubResult
      --context/ValidationContext
      --location/InstantiatedSchema
      --instance-pointer/JsonPointer
      --annotations/Map?

/**
The base class for all assertion actions.

Assertions validate a JSON value against some criteria that does not involve subschemas.
*/
abstract class Assertion extends Action:
  order -> int:
    return Action.ORDER-EARLY

/**
A simple assertion that validates any JSON value, but where the
  validation logic only needs access to the value itself.

Examples: $Type, $Enum, $Const.
*/
abstract class SimpleAssertion extends Assertion:
  abstract validate o/any [fail] -> none

  validate o/any -> SubResult
      --context/ValidationContext
      --location/InstantiatedSchema
      --instance-pointer/JsonPointer
  :
    result := SubResult location instance-pointer
    validate o: | keyword/string error-message/string |
      result.fail keyword error-message
    return result

/**
A simple assertion (only needing the actual value) that only applies
  to string values.

Examples: $StringLength, $Pattern.
*/
abstract class SimpleStringAssertion extends Assertion:
  abstract validate str/string [fail] -> none

  validate o/any -> SubResult
      --context/ValidationContext
      --location/InstantiatedSchema
      --instance-pointer/JsonPointer
  :
    result := SubResult location instance-pointer
    if o is not string: return result
    validate (o as string): | keyword/string error-message/string |
      result.fail keyword error-message
    return result

/**
A simple assertion (only needing the actual value) that only applies
  to numeric values.

Examples: $NumComparison (representing minimum, maximum, exclusiveMinimum, exclusiveMaximum).
*/
abstract class SimpleNumAssertion extends Assertion:
  abstract validate n/num [fail] -> none

  validate o/any -> SubResult
      --context/ValidationContext
      --location/InstantiatedSchema
      --instance-pointer/JsonPointer
  :
    result := SubResult location instance-pointer
    if o is not num: return result
    validate (o as num): | keyword/string error-message/string |
      result.fail keyword error-message
    return result

/**
A simple assertion (only needing the actual value) that only applies
  to object values (maps).

Examples: $Required.
*/
abstract class SimpleObjectAssertion extends Assertion:
  abstract validate o/Map [fail] -> none

  validate o/any -> SubResult
      --context/ValidationContext
      --location/InstantiatedSchema
      --instance-pointer/JsonPointer
  :
    result := SubResult location instance-pointer
    if o is not Map: return result
    validate (o as Map): | keyword/string error-message/string |
      result.fail keyword error-message
    return result

/**
A simple assertion (only needing the actual value) that only applies
  to array values (lists).

Examples: $ArrayLength, $UniqueItems.
*/
abstract class SimpleListAssertion extends Assertion:
  abstract validate o/List [fail] -> none

  validate o/any -> SubResult
      --context/ValidationContext
      --location/InstantiatedSchema
      --instance-pointer/JsonPointer
  :
    result := SubResult location instance-pointer
    if o is not List: return result
    validate (o as List): | keyword/string error-message/string |
      result.fail keyword error-message
    return result

/**
A reference to another schema.

References can be static or dynamic. In the latter case, the reference
  is resolved at validation time based on dynamic anchors in the instance.
*/
class Ref extends Applicator:
  target-uri/UriReference
  resolved_/Schema? := null
  is-dynamic/bool := ?
  dynamic-fragment/string? := null

  constructor --.target-uri --.is-dynamic:

  set-target schema/Schema --dynamic-fragment/string?:
    if is-dynamic and dynamic-fragment:
      this.dynamic-fragment = dynamic-fragment
    else:
      // If a dynamic reference resolves to a non-dynamic anchor, then it
      // behaves like a normal ref.
      is-dynamic = false
    resolved_ = schema

  target -> Schema?:
    return resolved_

  find-dynamic-schema_ --location/InstantiatedSchema --store/Store -> Schema:
    location.do-schema-resources --reversed: | resource/SchemaResource_ |
      dynamic-target-uri := resource.uri.with-fragment dynamic-fragment
      dynamic-target := dynamic-target-uri.to-string
      dynamic-target-schema := store.get dynamic-target
      if not dynamic-target-schema:
        continue.do-schema-resources
      if not store.get-dynamic-fragment dynamic-target:
        // Wasn't actually a dynamic target.
        continue.do-schema-resources
      return dynamic-target-schema
    // We know that there is a dynamic anchor in the same resource.
    // Otherwise we would have changed the dynamic reference to a static one.
    throw "Dynamic reference withouth a dynamic target: $target-uri"

  validate o/any -> SubResult
      --context/ValidationContext
      --location/InstantiatedSchema
      --instance-pointer/JsonPointer
  :
    resolved/Schema? := is-dynamic
        ? find-dynamic-schema_ --location=location --store=context.store
        : resolved_

    if resolved == null:
      throw "Unresolved reference: $target-uri"

    return location["\$ref", resolved].validate o --context=context --instance-pointer=instance-pointer

  accept visitor/ActionVisitor -> any:
    return visitor.visit-Ref this

  stringify -> string:
    return "Ref: $target-uri"

/**
An applicator representing all-of, any-of, and one-of.
*/
class X-Of extends Applicator:
  static ALL-OF ::= 0
  static ANY-OF ::= 1
  static ONE-OF ::= 2

  kind/int
  subschemas/List
  // An x-of keyword can be disabled if there is an OpenAPI discriminator. In that
  // case the discriminator does the work of the x-of keyword.
  is-disabled/bool := false

  constructor --.kind .subschemas:

  validate o/any -> SubResult
      --context/ValidationContext
      --location/InstantiatedSchema
      --instance-pointer/JsonPointer
  :
    result := SubResult location instance-pointer
    if is-disabled:
      return result

    if kind == ALL-OF:
      all-of-location := location["allOf"]
      for i := 0; i < subschemas.size; i++:
        subschema := subschemas[i]
        subresult := all-of-location["$i", subschema].validate o
            --context=context
            --instance-pointer=instance-pointer
        result.merge subresult
        if not subresult.is-valid and not context.needs-all-errors:
          break
      if not result.is-valid:
        result.fail "allOf" "Expected all subschemas to match."
      return result
    else:
      success-count := 0
      keyword := kind == ANY-OF ? "anyOf" : "oneOf"
      x-of-location := location[keyword]
      for i := 0; i < subschemas.size; i++:
        subschema := subschemas[i]
        subresult := x-of-location["$i", subschema].validate o
            --context=context
            --instance-pointer=instance-pointer
        if subresult.is-valid:
          success-count++
          result.merge subresult
          if not context.needs-annotations and kind == ANY-OF:
            break
          if not context.needs-all-errors and kind == ONE-OF and success-count > 1:
            break
      if kind == ONE-OF:
        if success-count != 1:
          result.fail keyword "Expected exactly one subschema to match."
      else if kind == ANY-OF:
        if success-count == 0:
          result.fail keyword "Expected at least one subschema to match."
      else:
        unreachable
      return result

  accept visitor/ActionVisitor -> any:
    return visitor.visit-X-Of this

  stringify -> string:
    if kind == X-Of.ALL-OF:
      return "AllOf: $subschemas"
    else if kind == X-Of.ANY-OF:
      return "AnyOf: $subschemas"
    else:
      return "OneOf: $subschemas"

class Not extends Applicator:
  subschema/Schema

  constructor .subschema/Schema:

  validate o/any -> SubResult
      --context/ValidationContext
      --location/InstantiatedSchema
      --instance-pointer/JsonPointer
  :
    result := SubResult location instance-pointer
    subresult := location["not", subschema].validate o
        --context=context
        --instance-pointer=instance-pointer
    if subresult.is-valid:
      result.fail "not" "Expected subschema to fail."
    return result

  accept visitor/ActionVisitor -> any:
    return visitor.visit-Not this

  stringify -> string:
    return "Not $subschema"

class IfThenElse extends Applicator:
  condition-subschema/Schema
  then-subschema/Schema?
  else-subschema/Schema?

  constructor .condition-subschema/Schema .then-subschema/Schema? .else-subschema/Schema?:

  validate o/any -> SubResult
      --context/ValidationContext
      --location/InstantiatedSchema
      --instance-pointer/JsonPointer
  :
    result := SubResult location instance-pointer
    condition-result := location["if", condition-subschema].validate o
        --context=context
        --instance-pointer=instance-pointer
    if condition-result.is-valid:
      result.merge condition-result
      if then-subschema:
        then-result := location["then", then-subschema].validate o
            --context=context
            --instance-pointer=instance-pointer
        if not then-result.is-valid:
          return then-result
        else:
          result.merge then-result
          return result
    else:
      if else-subschema:
        else-result := location["else", else-subschema].validate o
            --context=context
            --instance-pointer=instance-pointer
        if not else-result.is-valid:
          return else-result
        else:
          result.merge else-result
          return result
    return result

  accept visitor/ActionVisitor -> any:
    return visitor.visit-IfThenElse this

  stringify -> string:
    return "if ($condition-subschema) then $(then-subschema) else $(else-subschema)"


/**
Applicator for dependent schemas.

A schema is dependent on properties of the object that is validated.
*/
class DependentSchemas extends Applicator:
  subschemas/Map

  constructor .subschemas/Map:

  validate o/any -> SubResult
      --context/ValidationContext
      --location/InstantiatedSchema
      --instance-pointer/JsonPointer
  :
    result := SubResult location instance-pointer
    if o is not Map: return result
    map := o as Map
    dependent-location := location["dependentSchemas"]
    subschemas.do: | key/string subschema/Schema |
      map.get key --if-present=: | value/any |
        subresult := dependent-location[key, subschema].validate o
            --context=context
            --instance-pointer=instance-pointer
        result.merge subresult
        if not subresult.is-valid:
          result.fail "dependentSchemas" "Dependent schema '$key' failed."
          if not context.needs-all-errors:
            return result
    return result

  accept visitor/ActionVisitor -> any:
    return visitor.visit-DependentSchemas this

  stringify -> string:
    return "DependentSchemas: $subschemas"

/**
An applicator for properties of an object.
*/
class Properties extends Applicator:
  properties/Map?
  additional/Schema?
  patterns/Map?
  cached-regexs_/Map?

  constructor --.properties --.additional --.patterns:
    if patterns:
      cached := {:}
      patterns.do: | pattern/string _ |
        cached[pattern] = regex.parse pattern
      cached-regexs_ = cached
    else:
      cached-regexs_ = null


  validate o/any -> SubResult
      --context/ValidationContext
      --location/InstantiatedSchema
      --instance-pointer/JsonPointer
  :
    result := SubResult location instance-pointer
    if o is not Map: return result
    map := o as Map
    evaluated-properties := {}
    evaluated-matched-properties := {}
    evaluated-additional-properties := {}

    properties-location := location["properties"]
    patterns-location := location["patternProperties"]

    failed-properties := []
    failed-patterns := []
    failed-additional := []
    map.do: | key/string value/any |
      sub-pointer := instance-pointer[key]
      is-additional := true
      if properties and properties.contains key:
        evaluated-properties.add key
        is-additional = false
        subschema/Schema := properties[key]
        sub-is-valid := ?
        if subschema.json-value == false:
          sub-is-valid = false
        else:
          subresult := properties-location[key, properties[key]].validate value
              --context=context
              --instance-pointer=sub-pointer
          result.merge subresult
          sub-is-valid = subresult.is-valid
        if not sub-is-valid:
          failed-properties.add key
          if not context.needs-all-errors:
            result.fail "properties" "Property '$key' failed." --instance-pointer=sub-pointer
            return result

      if patterns:
        patterns.do: | pattern/string schema/Schema |
          regex := cached-regexs_[pattern]
          if regex.match key:
            evaluated-matched-properties.add key
            is-additional = false
            sub-is-valid := ?
            if schema.json-value == false:
              sub-is-valid = false
            else:
              subresult := patterns-location[pattern, schema].validate value
                  --context=context
                  --instance-pointer=sub-pointer
              result.merge subresult
              sub-is-valid = subresult.is-valid
            if not sub-is-valid:
              failed-patterns.add key
              if not context.needs-all-errors:
                result.fail "patternProperties"
                    "Pattern for '$key' failed."
                    --instance-pointer=sub-pointer
                return result

      if is-additional and additional:
        evaluated-additional-properties.add key
        sub-is-valid := ?
        if additional.json-value == false:
          sub-is-valid = false
        else:
          subresult := location["additionalProperties", additional].validate value
              --context=context
              --instance-pointer=sub-pointer
          result.merge subresult
          sub-is-valid = subresult.is-valid
        if not sub-is-valid:
          failed-additional.add key
          if not context.needs-all-errors:
            result.fail "additionalProperties"
                "Additional for '$key' failed."
                --instance-pointer=sub-pointer
            return result

    if context.needs-annotations:
      if not evaluated-properties.is-empty:
        result.annotate "properties" evaluated-properties
      if not evaluated-matched-properties.is-empty:
        result.annotate "patternProperties" evaluated-matched-properties
      if not evaluated-additional-properties.is-empty:
        result.annotate "additionalProperties" evaluated-additional-properties

    if not failed-properties.is-empty:
      result.fail "properties" failed-properties
    if not failed-patterns.is-empty:
      result.fail "patternProperties" failed-patterns
    if not failed-additional.is-empty:
      result.fail "additionalProperties" failed-additional
    return result

  accept visitor/ActionVisitor -> any:
    return visitor.visit-Properties this

  stringify -> string:
    return "Properties: $properties, Additional: $additional, Patterns: $patterns"

/**
Checks the names of properties in an object.
*/
class PropertyNames extends Applicator:
  subschema/Schema

  constructor .subschema/Schema:

  validate o/any -> SubResult
      --context/ValidationContext
      --location/InstantiatedSchema
      --instance-pointer/JsonPointer
  :
    result := SubResult location instance-pointer
    if o is not Map: return result
    map := o as Map
    sublocation := location["propertyNames", subschema]
    map.do: | key/string _ |
      subresult := sublocation.validate key
          --context=context
          // I don't think there is a way to point to the key of a property with a json pointer.
          --instance-pointer=instance-pointer
      if not subresult.is-valid:
        result.fail "propertyNames" "Property name '$key' failed."
        return result
      result.merge subresult
    return result

  accept visitor/ActionVisitor -> any:
    return visitor.visit-PropertyNames this

  stringify -> string:
    return "PropertyNames: $subschema"

/**
Check that an array contains items matching a subschema.
*/
class Contains extends Applicator:
  subschema/Schema
  min-contains/int?
  max-contains/int?

  constructor .subschema/Schema --.min-contains --.max-contains:

  validate o/any -> SubResult
      --context/ValidationContext
      --location/InstantiatedSchema
      --instance-pointer/JsonPointer
  :
    result := SubResult location instance-pointer
    if o is not List: return result
    list := o as List
    success-count := 0
    contained-indexes := []
    sublocation := location["contains", subschema]
    for i := 0; i < list.size; i++:
      item := list[i]
      subresult := sublocation.validate item
          --context=context
          --instance-pointer=instance-pointer[i]
      if subresult.is-valid:
        contained-indexes.add i
        success-count++
        result.merge subresult
    if min-contains:
      if success-count < min-contains:
        result.fail "minContains" "Expected at least $min-contains items to match."
        return result
    else if success-count == 0:
      result.fail "contains" "Expected at least one item to match."
      return result
    if max-contains and success-count > max-contains:
      result.fail "maxContains" "Expected at most $max-contains items to match."
      return result
    annotation-value := contained-indexes == list.size ? true : contained-indexes
    if context.needs-annotations:
      result.annotate "contains" annotation-value
    return result

  accept visitor/ActionVisitor -> any:
    return visitor.visit-Contains this

  stringify -> string:
    return "Contains: $subschema, min: $min-contains, max: $max-contains"

class Type extends SimpleAssertion:
  types/List

  constructor .types/List:

  validate o/any [fail] -> none:
    types.do: | type-string |
      if type-string == "null" and o == null: return
      if type-string == "boolean" and o is bool: return
      if type-string == "object" and o is Map: return
      if type-string == "array" and o is List: return
      if type-string == "number" and o is num: return
      if type-string == "string" and o is string: return
      if type-string == "integer":
        if o is int: return
        if o is float:
          f := o as float
          if f.is-finite:
            // Floats with absolute value >= 2^53 cannot represent a fractional
            // part, so they are always integers. Below 2^53 we can safely call
            // to-int without risking an OUT_OF_RANGE exception.
            if f.abs >= 9007199254740992.0: return
            if f.to-int.to-float == f: return
    fail.call "type" "Value type not one of $types"

  accept visitor/ActionVisitor -> any:
    return visitor.visit-Type this

  stringify -> string:
    return "Type: $types"

structural-equals_ a/any b/any -> bool:
  if a is num and a == b: return true
  if a is bool and a == b: return true
  if a is string and a == b: return true
  if a == null and b == null: return true

  if a is Map and b is Map:
    a-map := a as Map
    b-map := b as Map
    if a-map.size != b-map.size: return false
    a-map.do: | key/string a-value/any |
      b-value := b-map.get key
      if not structural-equals_ a-value b-value: return false
    return true

  if a is List and b is List:
    a-list := a as List
    b-list := b as List
    if a-list.size != b-list.size: return false
    for i := 0; i < a.size; i++:
      a-value := a-list[i]
      b-value := b-list[i]
      if not structural-equals_ a-value b-value: return false
    return true

  return false

class Enum extends SimpleAssertion:
  values/List

  constructor .values/List:

  validate o/any [fail] -> none:
    values.do: | value |
      if structural-equals_ o value: return
    fail.call "enum" "Value not one of $values"

  accept visitor/ActionVisitor -> any:
    return visitor.visit-Enum this

  stringify -> string:
    return "Enum: $values"

class Const extends SimpleAssertion:
  value/any

  constructor .value/any:

  validate o/any [fail] -> none:
    if not structural-equals_ o value:
      fail.call "const" "Value not equal to $value"

  accept visitor/ActionVisitor -> any:
    return visitor.visit-Const this

  stringify -> string:
    return "Const: $value"

class NumComparison extends SimpleNumAssertion:
  static MULTIPLE-OF ::= 0
  static MAXIMUM ::= 1
  static EXCLUSIVE-MAXIMUM ::= 2
  static MINIMUM ::= 3
  static EXCLUSIVE-MINIMUM ::= 4

  kind/int
  n/num

  constructor .n/num --.kind:

  validate o/num [fail] -> none:
    if kind == MULTIPLE-OF:
      if o % n != 0.0:
        fail.call "multipleOf" "Value $o not a multiple of $n"
    else if kind == MAXIMUM:
      if o > n:
        fail.call "maximum" "Value $o greater than $n"
    else if kind == EXCLUSIVE-MAXIMUM:
      if o >= n:
        fail.call "exclusiveMaximum" "Value $o greater than or equal to $n"
    else if kind == MINIMUM:
      if o < n:
        fail.call "minimum" "Value $o less than $n"
    else if kind == EXCLUSIVE-MINIMUM:
      if o <= n:
        fail.call "exclusiveMinimum" "Value $o less than or equal to $n"

  accept visitor/ActionVisitor -> any:
    return visitor.visit-NumComparison this

  stringify -> string:
    kind-str/string := ?
    if kind == MULTIPLE-OF:
      kind-str = "multipleOf"
    else if kind == MAXIMUM:
      kind-str = "maximum"
    else if kind == EXCLUSIVE-MAXIMUM:
      kind-str = "exclusiveMaximum"
    else if kind == MINIMUM:
      kind-str = "minimum"
    else if kind == EXCLUSIVE-MINIMUM:
      kind-str = "exclusiveMinimum"
    else:
      unreachable
    return "NumComparison: $kind-str, $n"

class StringLength extends SimpleStringAssertion:
  min/int?
  max/int?

  constructor --.min --.max:

  validate str/string [fail] -> none:
    rune-size := str.size --runes
    if min and rune-size < min:
      fail.call "minLength" "String length $rune-size less than $min"
    if max and rune-size > max:
      fail.call "maxLength" "String length $rune-size greater than $max"

  accept visitor/ActionVisitor -> any:
    return visitor.visit-StringLength this

  stringify -> string:
    return "StringLength: min=$min, max=$max"

class ArrayLength extends SimpleListAssertion:
  min/int?
  max/int?

  constructor --.min --.max:

  validate o/List [fail] -> none:
    if min and o.size < min:
      fail.call "minItems" "Array length $o.size less than $min"
    if max and o.size > max:
      fail.call "maxItems" "Array length $o.size greater than $max"

  accept visitor/ActionVisitor -> any:
    return visitor.visit-ArrayLength this

  stringify -> string:
    return "ArrayLength: min=$min, max=$max"

class UniqueItems extends SimpleListAssertion:
  constructor:

  validate list/List [fail] -> none:
    // For simplicity do an O(n^2) algorithm.
    for i := 0; i < list.size; i++:
      for j := i + 1; j < list.size; j++:
        if structural-equals_ list[i] list[j]:
          fail.call "uniqueItems" "Array contains duplicate items."
          return

  accept visitor/ActionVisitor -> any:
    return visitor.visit-UniqueItems this

  stringify -> string:
    return "UniqueItems"

class Required extends SimpleObjectAssertion:
  properties/List

  constructor .properties/List:

  validate map/Map [fail] -> none:
    missing := []
    properties.do: | property |
      if not map.contains property:
        missing.add property
    if missing.size == 1:
      fail.call "required" "Required property '$missing.first' missing."
    else if missing.size > 1:
      fail.call "required" "Required properties $((missing.map: "'$it'").join ", ") missing."

  accept visitor/ActionVisitor -> any:
    return visitor.visit-Required this

  stringify -> string:
    return "Required: $properties"

class ObjectSize extends SimpleObjectAssertion:
  min/int?
  max/int?

  constructor --.min --.max:

  validate map/Map [fail] -> none:
    if min and map.size < min:
      fail.call "minProperties" "Object size $map.size less than $min"
    if max and map.size > max:
      fail.call "maxProperties" "Object size $map.size greater than $max"

  accept visitor/ActionVisitor -> any:
    return visitor.visit-ObjectSize this

  stringify -> string:
    return "ObjectSize: min=$min, max=$max"

/**
Checks that the items of a list satisfy the $items schema.
*/
class Items extends Applicator:
  prefix-items/List?
  items/Schema?

  constructor --.prefix-items --.items:

  validate o/any -> SubResult
      --context/ValidationContext
      --location/InstantiatedSchema
      --instance-pointer/JsonPointer
  :
    result := SubResult location instance-pointer
    if o is not List: return result
    list := o as List
    items-location/InstantiatedSchema? := items ? location["items", items] : null
    prefix-location := location["prefixItems"]
    failed-items := []
    failed-prefix-items := []
    for i := 0; i < list.size; i++:
      sub-pointer := instance-pointer[i]
      if prefix-items and i < prefix-items.size:
        prefix-schema/Schema := prefix-items[i]
        subresult := prefix-location["$i", prefix-items[i]].validate list[i]
            --context=context
            --instance-pointer=sub-pointer
        result.merge subresult
        if not subresult.is-valid:
          failed-prefix-items.add i
          if not context.needs-all-errors:
            result.fail "prefixItems" "Prefix item $i failed." --instance-pointer=sub-pointer
            return result
      else if items:
        sub-is-valid := ?
        if items.json-value == false:
          sub-is-valid = false
        else:
          subresult := items-location["$i", items].validate list[i]
              --context=context
              --instance-pointer=sub-pointer
          result.merge subresult
          sub-is-valid = subresult.is-valid
        if not sub-is-valid:
          failed-items.add i
          if not context.needs-all-errors:
            result.fail "items" "Item $i failed." --instance-pointer=sub-pointer
            return result

    if not failed-prefix-items.is-empty:
      result.fail "prefixItems" failed-prefix-items
    if not failed-items.is-empty:
      result.fail "items" failed-items
    if context.needs-annotations:
      if prefix-items:
        annotation-value := prefix-items.size < list.size ? prefix-items.size : true
        result.annotate "prefixItems" annotation-value
      if items:
        result.annotate "items" true
    return result

  accept visitor/ActionVisitor -> any:
    return visitor.visit-Items this

  stringify -> string:
    return "Items: prefixItems=$prefix-items, items=$items"

class Pattern extends SimpleStringAssertion:
  pattern/string
  regex_/regex.Regex

  constructor .pattern:
    regex_ = regex.parse pattern

  validate str/string [fail] -> none:
    if not regex_.match str:
      fail.call "pattern" "String '$str' does not match pattern '$pattern'"

  accept visitor/ActionVisitor -> any:
    return visitor.visit-Pattern this

  stringify -> string:
    return "Pattern: $pattern"

/**
An assertion for dependent required properties.

For each key in $properties, if that key is present in the object,
  then all properties in the associated list must also be present.
*/
class DependentRequired extends SimpleObjectAssertion:
  properties/Map

  constructor .properties/Map:

  validate map/Map [fail] -> none:
    missing := []
    properties.do: | key/string required/List |
      if map.contains key:
        required.do: | property |
          if not map.contains property:
            missing.add property

    if missing.size == 1:
      fail.call "dependentRequired" "Required property '$missing.first' missing."
    else if missing.size > 1:
      fail.call "dependentRequired" "Required properties $((missing.map: "'$it'").join ", ") missing."

  accept visitor/ActionVisitor -> any:
    return visitor.visit-DependentRequired this

  stringify -> string:
    return "DependentRequired: $properties"

/**
An applicator for unevaluated properties of an object.

Checks that all properties that have not been evaluated by other
  keywords (properties, patternProperties, additionalProperties,
  unevaluatedProperties) satisfy the given subschema.
*/
class UnevaluatedProperties extends AnnotationsApplicator:
  static EVALUATED-ANNOTATION-KEYS_ ::= [
    "properties",
    "patternProperties",
    "additionalProperties",
    "unevaluatedProperties",
  ]
  subschema/Schema

  constructor .subschema/Schema:

  validate o/any -> SubResult
      --context/ValidationContext
      --location/InstantiatedSchema
      --instance-pointer/JsonPointer
  :
    unreachable

  validate o/any -> SubResult
      --context/ValidationContext
      --location/InstantiatedSchema
      --instance-pointer/JsonPointer
      --annotations/Map?
  :
    result := SubResult location instance-pointer
    if o is not Map: return result

    evaluated := {}
    if annotations:
      object-annotations := annotations.get instance-pointer.to-string
      if object-annotations:
        object-annotations.do: | annotation/Detail |
          if annotation.is-error: continue.do
          if EVALUATED-ANNOTATION-KEYS_.contains annotation.keyword:
            evaluated.add-all annotation.value

    new-evaluated := {}
    map := o as Map
    unevaluated-location := location["unevaluatedProperties", subschema]
    failed-unevaluated := []
    map.do: | key/string value/any |
      if not evaluated.contains key:
        new-evaluated.add key
        sub-pointer := instance-pointer[key]
        sub-is-valid := ?
        if subschema.json-value == false:
          sub-is-valid = false
        else:
          subresult := unevaluated-location.validate value
              --context=context
              --instance-pointer=sub-pointer
          result.merge subresult
          sub-is-valid = subresult.is-valid
        if not sub-is-valid:
          failed-unevaluated.add key
          if not context.needs-all-errors:
            result.fail "unevaluatedProperties"
                "Unevaluated property '$key' failed."
                --instance-pointer=sub-pointer
            return result
    if context.needs-annotations:
      result.annotate "unevaluatedProperties" new-evaluated
    if not failed-unevaluated.is-empty:
      result.fail "unevaluatedProperties" failed-unevaluated
    return result

  accept visitor/ActionVisitor -> any:
    return visitor.visit-UnevaluatedProperties this

  stringify -> string:
    return "UnevaluatedProperties: $subschema"

/**
An applicator for unevaluated items of an array.

Checks that all items that have not been evaluated by other
  keywords (items, prefixItems, contains, unevaluatedItems) satisfy the given subschema.
*/
class UnevaluatedItems extends AnnotationsApplicator:
  subschema/Schema

  constructor .subschema/Schema:

  validate o/any -> SubResult
      --context/ValidationContext
      --location/InstantiatedSchema
      --instance-pointer/JsonPointer
  :
    unreachable

  validate o/any -> SubResult
      --context/ValidationContext
      --location/InstantiatedSchema
      --instance-pointer/JsonPointer
      --annotations/Map?
  :
    result := SubResult location instance-pointer
    if o is not List: return result
    list := o as List
    first-unevaluated := 0
    evaluated-with-contains := {}
    if annotations:
      list-annotations/List? := annotations.get instance-pointer.to-string
      if list-annotations:
        list-annotations.do: | annotation/Detail |
          if annotation.is-error: continue.do
          if annotation.keyword == "items" or annotation.keyword == "unevaluatedItems":
            // Means that all items have been evaluated.
            return result
          if annotation.keyword == "contains":
            value := annotation.value
            if value == true:
              // Was applied to all items.
              return result
            assert: value is List
            evaluated-with-contains.add-all (value as List)
          if annotation.keyword == "prefixItems":
            value := annotation.value
            if value == true:
              // Was applied to all items.
              return result
            assert: value is int
            prefix-count := value as int
            if prefix-count >= list.size:
              // Was applied to all items.
              return result
            first-unevaluated = prefix-count
          else if annotation.keyword == "contains":

    sublocation := location["unevaluatedItems", subschema]
    needs-annotation := false
    failed-unevaluated := []
    for i := first-unevaluated; i < list.size; i++:
      if evaluated-with-contains.contains i:
        continue
      needs-annotation = true
      item := list[i]
      sub-pointer := instance-pointer[i]
      sub-is-valid := ?
      if subschema.json-value == false:
        sub-is-valid = false
      else:
        subresult := sublocation.validate item
            --context=context
            --instance-pointer=sub-pointer
        result.merge subresult
        sub-is-valid = subresult.is-valid
      if not sub-is-valid:
        failed-unevaluated.add i
        if not context.needs-all-errors:
          result.fail "unevaluatedItems"
              "Unevaluated item at position '$i' failed."
              --instance-pointer=sub-pointer
          return result
    if not failed-unevaluated.is-empty:
      result.fail "unevaluatedItems" failed-unevaluated
    if needs-annotation:
      result.annotate "unevaluatedItems" true
    return result

  accept visitor/ActionVisitor -> any:
    return visitor.visit-UnevaluatedItems this

  stringify -> string:
    return "UnevaluatedItems: $subschema"

/**
An annotation that adds information to the validation result
  without causing validation to fail.
*/
class Annotation extends Assertion:
  keyword/string
  value/any

  constructor .keyword .value:

  validate o/any -> SubResult
      --context/ValidationContext
      --location/InstantiatedSchema
      --instance-pointer/JsonPointer
  :
    result_ := SubResult location instance-pointer
    if context.needs-annotations:
      result_.annotate keyword value
    return result_

  accept visitor/ActionVisitor -> any:
    return visitor.visit-Annotation this

  stringify -> string:
    return "Annotation: $keyword = $value"

/**
An assertion for the format of a string.

For example, "email", "uri", "date-time", etc.
*/
class Format extends Assertion:
  format/string

  constructor .format/string:

  validate o/any -> SubResult
      --context/ValidationContext
      --location/InstantiatedSchema
      --instance-pointer/JsonPointer
  :
    result := SubResult location instance-pointer
    if context.needs-annotations:
      result.annotate "format" format
    // TODO(florian): Implement validation and give a way for users to add their own formats.
    return result

  accept visitor/ActionVisitor -> any:
    return visitor.visit-Format this

  stringify -> string:
    return "Format: $format"

/**
An applicator for OpenAPI discriminators.

The discriminator property is used to aid in the validation of
  polymorphic types. It contains a mapping from discriminator values
  to schema references. During validation, the value of the discriminator
  property is used to select the appropriate schema for validation.
*/
class Discriminator extends Applicator:
  property/string
  mapping/Map?  // From string to UriReference.
  resolved-mapping/Map? := null  // From string to Schema.
  kind/int := -1  // An X-Of kind.
  all-of-hierarchy-parents/Map? := null

  constructor .property .mapping:

  validate o/any -> SubResult
      --context/ValidationContext
      --location/InstantiatedSchema
      --instance-pointer/JsonPointer
      --required-hierarchy-schema/Schema? = null
  :
    result := SubResult location instance-pointer
    if o is not Map: return result

    if kind == X-Of.ALL-OF and not required-hierarchy-schema:
      // All-of discriminators are called as part of the validate in
      // Schemas, where the schema is set.
      // Otherwise, we skip them.
      return result

    map := o as Map
    discriminator-value := map.get property
    if discriminator-value is not string:
      result.fail "discriminator" "Discriminator property '$property' not a string."
      return result

    target-schema/Schema? := resolved-mapping.get discriminator-value
    if not target-schema:
      result.fail "discriminator" "Discriminator value '$discriminator-value' not in mapping."
      return result

    subresult := location["discriminator", target-schema].validate o
        --context=context
        --instance-pointer=instance-pointer
    result.merge subresult

    if required-hierarchy-schema:
      required-url := required-hierarchy-schema.absolute-location
      // Check that the required-hierarchy-schema is a parent of the target-schema.
      current/UriReference? := target-schema.absolute-location
      while current != required-url:
        current = (all-of-hierarchy-parents.get current)
        if not current:
          result.fail "discriminator" "Discriminator value '$discriminator-value' not expected class"
          return result

    if kind == X-Of.ONE-OF and not subresult.is-valid:
      result.fail "discrimator" "Discriminator with 'oneOf' kind failed."
      return result
    return result

  accept visitor/ActionVisitor -> any:
    return visitor.visit-Discriminator this

  stringify -> string:
    return "Discriminator: property=$property, mapping=$mapping"
