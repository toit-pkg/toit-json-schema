// Copyright (C) 2025 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import json-pointer show *

import .action
import .build-context
import .schema
import .uri

JSON-SCHEMA-2020-12-URI ::= "https://json-schema.org/draft/2020-12/schema"
OPENAPI-3_1-URI ::= "https://spec.openapis.org/oas/3.1/dialect/base"

// Cached entries for dialects, so we don't need to download the Schema.
DIALECTS_ ::= {
  // Map from vocabulary URI to whether it is required.
  JSON-SCHEMA-2020-12-URI: {
    VocabularyCore.URI: true,
    VocabularyApplicator.URI: true,
    VocabularyUnevaluated.URI: true,
    VocabularyValidation.URI: true,
    VocabularyMetaData.URI: true,
    VocabularyFormatAnnotation.URI: true,
    VocabularyContent.URI: true,
  },
  OPENAPI-3_1-URI: {
    VocabularyCore.URI: true,
    VocabularyApplicator.URI: true,
    VocabularyUnevaluated.URI: true,
    VocabularyValidation.URI: true,
    VocabularyMetaData.URI: true,
    VocabularyFormatAnnotation.URI: true,
    VocabularyContent.URI: true,
    VocabularyOpenApi.URI: true,
  },
}

KNOWN-VOCABULARIES_ ::= {
  VocabularyCore.URI: VocabularyCore,
  VocabularyApplicator.URI: VocabularyApplicator,
  VocabularyValidation.URI: VocabularyValidation,
  VocabularyUnevaluated.URI: VocabularyUnevaluated,
  VocabularyMetaData.URI: VocabularyMetaData,
  VocabularyFormatAnnotation.URI: VocabularyFormatAnnotation,
  VocabularyContent.URI: VocabularyContent,
  VocabularyOpenApi.URI: VocabularyOpenApi,
}

interface Vocabulary:
  uri -> string
  keywords -> List
  add-actions --schema/Schema --context/BuildContext --json-pointer/JsonPointer -> bool

class VocabularyCore implements Vocabulary:
  static URI ::= "https://json-schema.org/draft/2020-12/vocab/core"

  static KEYWORDS ::= [
    "\$schema",
    "\$vocabulary",
    "\$id",
    "\$anchor",
    "\$dynamicAnchor",
    "\$ref",
    "\$dynamicRef",
    "\$defs",
    "\$comment",
  ]

  uri -> string:
    return URI

  keywords -> List:
    return KEYWORDS

  add-actions --schema/Schema --context/BuildContext --json-pointer/JsonPointer -> none:
    json := schema.json-value
    json.get "\$anchor" --if-present=: | anchor-id/string |
      normalized-fragment := UriReference.normalize-fragment anchor-id
      anchor-uri := schema.schema-resource.uri.with-fragment normalized-fragment
      context.store.add anchor-uri.to-string schema

    json.get "\$dynamicAnchor" --if-present=: | anchor-id/string |
      normalized-fragment := UriReference.normalize-fragment anchor-id
      anchor-uri := schema.schema-resource.uri.with-fragment normalized-fragment
      context.store.add --dynamic anchor-uri.to-string schema --fragment=normalized-fragment

    json.get "\$ref" --if-present=: | ref/string |
      target-uri := schema.uri-reference ref
      applicator := Ref --target-uri=target-uri --is-dynamic=false
      context.refs.add applicator
      schema.add-applicator applicator

    json.get "\$dynamicRef" --if-present=: | ref/string |
      target-uri := schema.uri-reference ref
      applicator := Ref --target-uri=target-uri --is-dynamic
      context.refs.add applicator
      schema.add-applicator applicator

    json.get "\$defs" --if-present=: | defs/Map |
      schema-defs := defs.map: | key/string value/any |
        sub-pointer := json-pointer["\$defs"][key]
        // Building the schema will automatically add its json-pointer to the store.
        Schema.parse_ value --parent=schema --context=context --json-pointer=sub-pointer

int-value_ n/num? -> int?:
  if not n: return null
  if n is int: return n as int
  if n is float: return n.to-int
  unreachable

class VocabularyApplicator implements Vocabulary:
  static URI ::= "https://json-schema.org/draft/2020-12/vocab/applicator"

  static KEYWORDS ::= [
    "allOf",
    "anyOf",
    "oneOf",
    "not",
    "if",
    "then",
    "else",
    "dependentSchemas",
    "prefixItems",
    "items",
    "contains",
    "properties",
    "patternProperties",
    "additionalProperties",
    "propertyNames",
  ]

  uri -> string:
    return URI

  keywords -> List:
    return KEYWORDS

  map-schemas_ --list/List --parent/Schema? --context/BuildContext --json-pointer/JsonPointer -> List:
    result := List list.size: | i/int |
      sub-schema-json/any := list[i]
      // Building the schema will automatically add its json-pointer to the store.
      Schema.parse_ sub-schema-json --parent=parent --context=context --json-pointer=json-pointer[i]
    return result

  map-schemas_ --object/Map --parent/Schema? --context/BuildContext --json-pointer/JsonPointer -> Map:
    return object.map: | key/string sub-schema-json/any |
      // Building the schema will automatically add its json-pointer to the store.
      Schema.parse_ sub-schema-json --parent=parent --context=context --json-pointer=json-pointer[key]

  add-actions --schema/Schema --context/BuildContext --json-pointer/JsonPointer -> none:
    json := schema.json-value

    ["allOf", "anyOf", "oneOf"].do: | keyword/string |
      json.get keyword --if-present=: | entries/List |
        subschemas := map-schemas_
            --list=entries
            --parent=schema
            --context=context
            --json-pointer=json-pointer[keyword]
        kind/int := ?
        if keyword == "allOf": kind = X-Of.ALL-OF
        else if keyword == "anyOf": kind = X-Of.ANY-OF
        else if keyword == "oneOf": kind = X-Of.ONE-OF
        else: throw "unreachable"
        schema.add-applicator (X-Of --kind=kind subschemas)

    json.get "not" --if-present=: | not-entry/any |
      // Building the schema will automatically add its json-pointer to the store.
      subschema := Schema.parse_ not-entry --parent=schema --context=context --json-pointer=json-pointer["not"]
      schema.add-applicator (Not subschema)

    condition-subschema/Schema? := json.get "if" --if-present=: | if-entry/any |
      // Building the schema will automatically add its json-pointer to the store.
      Schema.parse_ if-entry --parent=schema --context=context --json-pointer=json-pointer["if"]

    // We build the then subschema even if there is no 'if', in case
    // the subschema is referenced.
    then-subschema/Schema? := json.get "then" --if-present=: | then-entry/any |
      // Building the schema will automatically add its json-pointer to the store.
      Schema.parse_ then-entry --parent=schema --context=context --json-pointer=json-pointer["then"]

    // We build the 'else' subschema even if there is no 'if', in case
    // the subschema is referenced.
    else-subschema/Schema? := json.get "else" --if-present=: | else-entry/any |
      // Building the schema will automatically add its json-pointer to the store.
      Schema.parse_ else-entry --parent=schema --context=context --json-pointer=json-pointer["else"]

    if condition-subschema:
      schema.add-applicator (IfThenElse condition-subschema then-subschema else-subschema)

    json.get "dependentSchemas" --if-present=: | dependent-schemas/Map |
      subschemas := map-schemas_
          --object=dependent-schemas
          --parent=schema
          --context=context
          --json-pointer=json-pointer["dependentSchemas"]
      schema.add-applicator (DependentSchemas subschemas)

    prefix-items := json.get "prefixItems" --if-present=: | prefix-items/List |
      subschemas := map-schemas_
          --list=prefix-items
          --parent=schema
          --context=context
          --json-pointer=json-pointer["prefixItems"]

    items := json.get "items" --if-present=: | items/any |
      // Building the schema will automatically add its json-pointer to the store.
      subschema := Schema.parse_ items
          --parent=schema
          --context=context
          --json-pointer=json-pointer["items"]

    if prefix-items or items:
      schema.add-applicator (Items --prefix-items=prefix-items --items=items)

    json.get "contains" --if-present=: | contains/any |
      supports-min-max := schema.schema-resource.vocabularies.contains VocabularyValidation.URI
      min-contains := supports-min-max ? int-value_ (json.get "minContains") : null
      max-contains := supports-min-max ? int-value_ (json.get "maxContains") : null

      // Building the schema will automatically add its json-pointer to the store.
      subschema := Schema.parse_ contains
          --parent=schema
          --context=context
          --json-pointer=json-pointer["contains"]
      schema.add-applicator (Contains subschema --min-contains=min-contains --max-contains=max-contains)

    properties := json.get "properties" --if-present=: | properties/Map |
      subschemas := map-schemas_
          --object=properties
          --parent=schema
          --context=context
          --json-pointer=json-pointer["properties"]

    additional-properties := json.get "additionalProperties" --if-present=: | additional-properties/any |
      // Building the schema will automatically add its json-pointer to the store.
      subschema := Schema.parse_ additional-properties
          --parent=schema
          --context=context
          --json-pointer=json-pointer["additionalProperties"]

    pattern-properties := json.get "patternProperties" --if-present=: | pattern-properties/Map |
      subschemas := map-schemas_
          --object=pattern-properties
          --parent=schema
          --context=context
          --json-pointer=json-pointer["patternProperties"]

    if properties or additional-properties or pattern-properties:
      applicator := Properties
          --properties=properties
          --patterns=pattern-properties
          --additional=additional-properties
      schema.add-applicator applicator

    json.get "propertyNames" --if-present=: | property-names/any |
      // Building the schema will automatically add its json-pointer to the store.
      subschema := Schema.parse_ property-names
          --parent=schema
          --context=context
          --json-pointer=json-pointer["propertyNames"]
      schema.add-applicator (PropertyNames subschema)


class VocabularyUnevaluated implements Vocabulary:
  static URI ::= "https://json-schema.org/draft/2020-12/vocab/unevaluated"
  static KEYWORDS ::= [
    "unevaluatedItems",
    "unevaluatedProperties",
  ]

  uri -> string:
    return URI

  keywords -> List:
    return KEYWORDS

  add-actions --schema/Schema --context/BuildContext --json-pointer/JsonPointer -> none:
    json := schema.json-value

    json.get "unevaluatedItems" --if-present=: | unevaluated-items/any |
      // Building the schema will automatically add its json-pointer to the store.
      subschema := Schema.parse_ unevaluated-items
          --parent=schema
          --context=context
          --json-pointer=json-pointer["unevaluatedItems"]
      schema.add-applicator (UnevaluatedItems subschema)

    json.get "unevaluatedProperties" --if-present=: | unevaluated-properties/any |
      // Building the schema will automatically add its json-pointer to the store.
      subschema := Schema.parse_ unevaluated-properties
          --parent=schema
          --context=context
          --json-pointer=json-pointer["unevaluatedProperties"]
      schema.add-applicator (UnevaluatedProperties subschema)

class VocabularyValidation implements Vocabulary:
  static URI ::= "https://json-schema.org/draft/2020-12/vocab/validation"

  static KEYWORDS ::= [
    "type",
    "enum",
    "const",
    "minContains",
    "maxContains",
    "multipleOf",
    "maximum",
    "exclusiveMaximum",
    "minimum",
    "exclusiveMinimum",
    "required",
    "minLength",
    "maxLength",
    "maxItems",
    "minItems",
    "uniqueItems",
    "minProperties",
    "maxProperties",
    "pattern",
    "dependentRequired",
  ]

  uri -> string:
    return URI

  keywords -> List:
    return KEYWORDS

  add-actions --schema/Schema --context/BuildContext --json-pointer/JsonPointer -> none:
    json := schema.json-value

    json.get "type" --if-present=: | type/any |
      if type is string: type = [type]
      schema.add-assertion (Type type)

    json.get "enum" --if-present=: | enum-values/any |
      schema.add-assertion (Enum enum-values)

    json.get "const" --if-present=: | value/any |
      schema.add-assertion (Const value)

    ["multipleOf", "maximum", "exclusiveMaximum", "minimum", "exclusiveMinimum"].do: | keyword/string |
      json.get keyword --if-present=: | value |
        if value is not num:
          throw "Invalid value for '$keyword' keyword: $value"
        n := value as num
        kind/int := ?
        if keyword == "multipleOf": kind = NumComparison.MULTIPLE-OF
        else if keyword == "maximum": kind = NumComparison.MAXIMUM
        else if keyword == "exclusiveMaximum": kind = NumComparison.EXCLUSIVE-MAXIMUM
        else if keyword == "minimum": kind = NumComparison.MINIMUM
        else if keyword == "exclusiveMinimum": kind = NumComparison.EXCLUSIVE-MINIMUM
        else: throw "unreachable"
        schema.add-assertion (NumComparison --kind=kind n)

    json.get "required" --if-present=: | required-properties/List |
      schema.add-assertion (Required required-properties)

    min-length := int-value_ (json.get "minLength")
    max-length := int-value_ (json.get "maxLength")
    if min-length or max-length:
      schema.add-assertion (StringLength --min=min-length --max=max-length)

    min-items := int-value_ (json.get "minItems")
    max-items := int-value_ (json.get "maxItems")
    if min-items or max-items:
      schema.add-assertion (ArrayLength --min=min-items --max=max-items)

    json.get "uniqueItems" --if-present=: | val/bool |
      if val: schema.add-assertion UniqueItems

    min-properties := int-value_ (json.get "minProperties")
    max-properties := int-value_ (json.get "maxProperties")
    if min-properties or max-properties:
      schema.add-assertion (ObjectSize --min=min-properties --max=max-properties)

    json.get "pattern" --if-present=: | pattern/string |
      schema.add-assertion (Pattern pattern)

    json.get "dependentRequired" --if-present=: | dependent-required/Map |
      schema.add-assertion (DependentRequired dependent-required)

class VocabularyFormatAnnotation implements Vocabulary:
  static URI ::= "https://json-schema.org/draft/2020-12/vocab/format-annotation"

  static KEYWORDS ::= [
    "format",
  ]

  uri -> string:
    return URI

  keywords -> List:
    return KEYWORDS

  add-actions --schema/Schema --context/BuildContext --json-pointer/JsonPointer -> none:
    json := schema.json-value

    json.get "format" --if-present=: | format/string |
      schema.add-assertion (Format format)

abstract class VocabularyAnnotationBase implements Vocabulary:
  abstract uri -> string
  abstract keywords -> List

  add-actions --schema/Schema --context/BuildContext --json-pointer/JsonPointer -> none:
    json := schema.json-value

    keywords.do: | keyword/string |
      // We assume that the values have the correct type.
      // The meta-schema can be used to validate the schema, so we don't need to do this
      // here.
      json.get keyword --if-present=: | value |
        schema.add-assertion (Annotation keyword value)

class VocabularyMetaData extends VocabularyAnnotationBase:
  static URI ::= "https://json-schema.org/draft/2020-12/vocab/meta-data"

  static KEYWORDS ::= [
    "title",
    "description",
    "default",
    "deprecated",
    "readOnly",
    "writeOnly",
    "examples",
  ]

  uri -> string:
    return URI

  keywords -> List:
    return KEYWORDS

class VocabularyContent extends VocabularyAnnotationBase:
  static URI ::= "https://json-schema.org/draft/2020-12/vocab/content"

  static KEYWORDS ::= [
    "contentSchema",
    "contentMediaType",
    "contentEncoding",
  ]

  uri -> string:
    return URI

  keywords -> List:
    return KEYWORDS

/**
Vocabulary for OpenAPI.

The OpenAPI specification is geared towards their OpenAPI specifications and
  is relatively vague on how to correctly implement the vocabulary outside
  the context of OpenAPI. Specifically, OpenAPI uses the term "parent", which
  is neither defined in the OpenAPI specification, nor the JSON Schema.
  It is also not giving any guidance on corner cases that could arrive
  when using the discriminator keyword.

The OpenAPI vocabulary is relatively invasive. It required changes to the
  following parts of this library:
- The X-Of applicator: Can now be disabled, since the discriminator "shadows"
  the functionality.
- Schemas: Due to the implicit 'all-of' targets, it's necessary to guard
  schemas that are in an 'allOf' chain so that there isn't any infinite
  recursion.
*/
class VocabularyOpenApi implements Vocabulary:
  static URI ::= "https://spec.openapis.org/oas/3.1/dialect/base"

  static KEYWORDS ::= [
    "discriminator",
    "xml",
    "externalDocs",
    "example",  // Deprecated but still supported.
  ]

  uri -> string:
    return URI

  keywords -> List:
    return KEYWORDS

  add-actions --schema/Schema --context/BuildContext --json-pointer/JsonPointer -> none:
    json := schema.json-value

    // The 'discriminator' keyword is handled by the X-Of applicator.
    [ "xml", "externalDocs", "example" ].do: | keyword/string |
      json.get keyword --if-present=: | value/any |
        schema.add-assertion (Annotation keyword value)

    json.get "discriminator" --if-present=: | discriminator-json/any |
      property-name := discriminator-json.get "propertyName" --if-absent=:
        throw "Missing 'propertyName' in 'discriminator' keyword."
      mapping := discriminator-json.get "mapping"
      uri-ref-mapping/Map? := null
      if mapping:
        uri-ref-mapping = mapping.map: | _ ref/string |
          schema.uri-reference ref
      discriminator := Discriminator property-name uri-ref-mapping
      context.discriminators.add [discriminator, schema]
      schema.add-applicator discriminator

  static flatten_ schema/Schema tree/Map --seen/Set --result/List -> none:
    absolute-location := schema.absolute-location
    if seen.contains absolute-location:
      throw "Recursive all-of loop"
    seen.add absolute-location
    parents := tree.get absolute-location
    if not parents: return
    parents.do: | parent/Schema |
      flatten_ parent tree --seen=seen --result=result
      result.add parent

  /**
  Computes the all-of hierarchy.

  We consider a schema to be a "parent" of another schema, if it is the
    target of a 'ref' inside an 'allOf' keyword.

  Returns a map from schema URI to a list of schemas that have the schema
    as a parent.
  */
  static compute-all-of-hierarchy_ context/BuildContext -> Map:
    seen := {}  // Set of schema URIs that have already been seen.
    // The tree is a map from schema URI to a list of schemas.
    // Any entry in the value means that the key is the target of an 'allOf' keyword.
    // Only considers 'refs' in the all-of keywords.
    tree := {:}
    context.store.do: | uri/string schema/Schema |
      // Schemas may exist under multiple URIs in the store.
      // Make sure we look at each one only once.
      if seen.contains schema.absolute-location: continue.do
      seen.add schema.absolute-location

      schema.actions.do: | action/Action |
        if action is X-Of:
          x-of := action as X-Of
          if x-of.kind == X-Of.ALL-OF:
            x-of.subschemas.do: | subschema/Schema |
              subactions := subschema.actions
              if subschema.actions.size != 1:
                continue.do
              subaction := subactions.first
              if subaction is not Ref or (subaction as Ref).is-dynamic:
                continue.do
              ref := subaction as Ref
              target-uri := ref.target.absolute-location
              (tree.get target-uri --init=:[]).add schema

    return tree

  /**
  Resolves the discriminators.

  Builds the map from identifier to schema for the discriminators.
  All references must be resolved before calling this method.
  */
  static resolve-discriminators --context/BuildContext -> none:
    all-of-hierarchy := compute-all-of-hierarchy_ context

    all-of-hierarchy-parents := {:}
    all-of-hierarchy.do: | parent-url/UriReference children/List |
      children.do: | child/Schema |
        all-of-hierarchy-parents[child.absolute-location] = parent-url

    one-of-schemas := {:}  // From schema-uri to list of options.
    all-of-schemas := {:}  // From schema-UriReference to Discriminator.

    context.discriminators.do: | entry/List |
      discriminator/Discriminator := entry[0]
      schema/Schema := entry[1]

      discriminator.all-of-hierarchy-parents = all-of-hierarchy-parents

      // See if the schema contains an `anyOf` or `oneOf` keyword.
      x-of/X-Of? := null
      for i := 0; i < schema.actions.size; i++:
        action := schema.actions[i]
        if action is X-Of:
          potential-x-of := action as X-Of
          if potential-x-of.kind == X-Of.ANY-OF or potential-x-of.kind == X-Of.ONE-OF:
            x-of = potential-x-of
            break

      // Map from uri to schema.
      implicit-targets/List := ?
      if x-of:
        // This discriminator will do the job of the x-of.
        x-of.is-disabled = true

        implicit-targets = x-of.subschemas.map: | subschema/Schema |
          // Find the 'ref' in the subschema.
          target/Schema? := null
          actions := subschema.actions
          for i := 0; i < actions.size; i++:
            action/Action := actions[i]
            if action is Ref:
              ref := action as Ref
              if ref.is-dynamic:
                throw "Invalid discriminator schema with 'anyOf' or 'oneOf' keyword. Only non-dynamic references are allowed."
              target = ref.target
              if not target:
                throw "Unresolved target for ref that is used in discriminator."
              break
          target
      else:
        // The schema containing this discriminator doesn't have any
        // x-of keyword. This means we need to use all "parents" (having
        // this schema as `allOf`)
        // The specification isn't really clear on how to find parents. We
        // just find schemas that have the discriminator-keyword as transitive
        // 'allOf'.
        // See https://github.com/OAI/OpenAPI-Specification/issues/3591.
        implicit-targets = []
        flatten_ schema all-of-hierarchy --seen={} --result=implicit-targets
        schema.all-of-discriminator = discriminator
        implicit-targets.do: | child/Schema |
            child.all-of-discriminator = discriminator

      inverted-mapping := {:}
      if discriminator.mapping:
        discriminator.mapping.do: | key/any value/UriReference |
          inverted-mapping[value] = key

      resolved-mapping := {:}

      implicit-targets.do: | schema/Schema |
        explicit-mapping/string? := inverted-mapping.get schema.absolute-location
        if explicit-mapping:
          resolved-mapping[explicit-mapping] = schema
        else:
          // Find the implicit name of the schema.
          segments := schema.json-pointer.segments
          i := segments.size - 1
          while i > 0:
            // The OpenAPI spec isn't really clear on how to find the name, but
            // the following approach works with the examples they give.
            // In practice we probably only remove one 'allOf'.
            if segments[i] != "allOf":
              break
            i--
          resolved-mapping[segments[i]] = schema

      discriminator.kind = x-of ? x-of.kind : X-Of.ALL-OF
      discriminator.resolved-mapping = resolved-mapping
