// Copyright (C) 2025 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import encoding.url as url-encoder
import toit-gen
import toit-gen.namer
import json-pointer show JsonPointer

import .action
import .json-schema
import .schema
import .store_
import .uri

class ClassManager:
  used/Set ::= {}  // Of string.
  // The public toit-gen target for each schema URI. For schemas that are used
  // as allOf $ref parents this is an interface; otherwise it's a regular class.
  classes/Map ::= {:}  // From UriReference to toit-gen.Class.
  // Private impl class for schemas whose public face is an interface.
  impl-classes/Map ::= {:}  // From UriReference to toit-gen.Class.
  // TODO(florian): "any" shouldn't be a core class.
  any-class/toit-gen.Class ::= toit-gen.Class.core "any"
  list-class/toit-gen.Class ::= toit-gen.Class.core "List"
  map-class/toit-gen.Class ::= toit-gen.Class.core "Map"
  bool-class/toit-gen.Class ::= toit-gen.Class.core "bool"
  int-class/toit-gen.Class ::= toit-gen.Class.core "int"
  num-class/toit-gen.Class ::= toit-gen.Class.core "num"
  string-class/toit-gen.Class ::= toit-gen.Class.core "string"
  null-class/toit-gen.Class ::= toit-gen.Class.core "Null"

  constructor --class-seed/Map?={:}:
    if class-seed:
      class-seed.do: | url/UriReference name/string |
        class-name := namer.toit-class-name name
        use-unique_ --url=url class-name

  use-unique_ --url/UriReference name/string -> toit-gen.Class:
    attempt := name
    i := 0
    while used.contains attempt:
      attempt = "$name$(i++)"
    used.add attempt
    clazz := toit-gen.Class attempt --kind=toit-gen.Class.CLASS
    classes[url] = clazz
    return clazz

  use-class url/UriReference name/string --as-interface/bool=false -> toit-gen.Class:
    if classes.contains url:
      return classes[url]

    if as-interface:
      attempt := name
      i := 0
      while used.contains attempt:
        attempt = "$name$(i++)"
      used.add attempt
      itf := toit-gen.Class attempt --kind=toit-gen.Class.INTERFACE
      classes[url] = itf
      // Reserve the private impl class name. Toit treats names ending with
      // "_" as private to the file. Hyphenate the suffix so toit-gen's
      // PascalCase namer recognises "Impl" as a separate word ("AImpl_"
      // instead of "Aimpl_").
      impl-base := "$(attempt)-Impl"
      impl-attempt := "$(impl-base)_"
      j := 0
      while used.contains impl-attempt:
        impl-attempt = "$(impl-base)$(j++)_"
      used.add impl-attempt
      impl := toit-gen.Class impl-attempt --kind=toit-gen.Class.CLASS --is-private
      impl-classes[url] = impl
      return itf

    return use-unique_ --url=url name

  operator [] url/UriReference -> toit-gen.Class?:
    return classes.get url

  /**
  Returns the impl class for $url if the schema's public face is an interface,
    else the public class itself. Generation methods (gen-fields_,
    gen-class) target this class.
  */
  target-class url/UriReference -> toit-gen.Class?:
    return impl-classes.get url --if-absent=: classes.get url

/**
A no-op base class for $ActionVisitor.

Subclasses override only the visit methods they care about.
*/
class BaseActionVisitor implements ActionVisitor:
  visit-Ref _/Ref -> none:
  visit-X-Of _/X-Of -> none:
  visit-Not _/Not -> none:
  visit-IfThenElse _/IfThenElse -> none:
  visit-DependentSchemas _/DependentSchemas -> none:
  visit-Properties _/Properties -> none:
  visit-PropertyNames _/PropertyNames -> none:
  visit-Contains _/Contains -> none:
  visit-Type _/Type -> none:
  visit-Enum _/Enum -> none:
  visit-Const _/Const -> none:
  visit-NumComparison _/NumComparison -> none:
  visit-StringLength _/StringLength -> none:
  visit-ArrayLength _/ArrayLength -> none:
  visit-UniqueItems _/UniqueItems -> none:
  visit-Required _/Required -> none:
  visit-ObjectSize _/ObjectSize -> none:
  visit-Items _/Items -> none:
  visit-Pattern _/Pattern -> none:
  visit-DependentRequired _/DependentRequired -> none:
  visit-UnevaluatedProperties _/UnevaluatedProperties -> none:
  visit-UnevaluatedItems _/UnevaluatedItems -> none:
  visit-Annotation _/Annotation -> none:
  visit-Format _/Format -> none:
  visit-Discriminator _/Discriminator -> none:

class CollectRefTargetsVisitor extends BaseActionVisitor:
  ref-targets/Set ::= {}  // Of Schema.
  visited_/Set ::= {}  // Of Schema.

  visit schema/Schema -> none:
    if visited_.contains schema: return
    visited_.add schema
    schema.actions.do: | action/Action |
      action.accept this

  visit-Ref ref/Ref -> none:
    if ref.is-dynamic: throw "UNIMPLEMENTED"
    ref-targets.add ref.target
    visit ref.target

  visit-X-Of x-of/X-Of -> none:
    x-of.subschemas.do: | schema/Schema |
      visit schema

  visit-IfThenElse if-then-else/IfThenElse -> none:
    visit if-then-else.condition-subschema
    visit if-then-else.then-subschema
    visit if-then-else.else-subschema

  visit-DependentSchemas dependent-schemas/DependentSchemas -> none:
    dependent-schemas.subschemas.do: | schema/Schema |
      visit schema

  visit-Properties properties/Properties -> none:
    if properties.properties:
      properties.properties.do: | _ schema/Schema |
        visit schema
    if properties.additional:
      ref-targets.add properties.additional
      visit properties.additional

  visit-Items items/Items -> none:
    if items.prefix-items and not items.prefix-items.is-empty:
      items.prefix-items.do: | schema/Schema |
        visit schema
    visit items.items

  visit-UnevaluatedProperties unevaluated-properties/UnevaluatedProperties -> none:
    visit unevaluated-properties.subschema

  visit-UnevaluatedItems unevaluated-items/UnevaluatedItems -> none:
    visit unevaluated-items.subschema

  visit-Discriminator discriminator/Discriminator -> none:
    if discriminator.resolved-mapping:
      discriminator.resolved-mapping.do --values: | schema/Schema |
        visit schema

/**
A visitor that assigns names to schemas.

Each schema gets a name that could be used as a Toit class name.
Many of these names won't be used, especially the names of
  schemas that represent primitive types.
*/
class NameVisitor extends BaseActionVisitor:
  current-class-name/string? := null
  class-manager/ClassManager
  needs-interface_/Set  // Of UriReference. Schemas to materialise as interfaces.

  constructor .class-manager --needs-interface/Set:
    needs-interface_ = needs-interface

  visit schema/Schema [--if-no-name] -> none:
    // Try to guess the name from the URL.
    url := schema.absolute-location
    fragment := url.fragment
        ? url-encoder.decode url.fragment
        : ""
    segments := (fragment.split "/").filter: it != ""
    name := segments.is-empty
        ? if-no-name.call
        : segments.last
    visit schema --name=name

  visit schema/Schema --nested-name/string -> none:
    url := schema.absolute-location
    name/string := ?
    if nested-name == "":
      if not current-class-name: throw "Unable to name schema at $url"
      name = current-class-name
    else:
      name = current-class-name
          ? "$current-class-name-$nested-name"
          : nested-name
    visit schema --name=name

  visit schema/Schema --name/string -> none:
    url := schema.absolute-location
    old-name := current-class-name
    as-interface := needs-interface_.contains url
    current-class-name = (class-manager.use-class url name --as-interface=as-interface).preferred-name
    schema.actions.do: | action/Action |
      action.accept this
    current-class-name = old-name

  visit-X-Of x-of/X-Of -> none:
    x-of.subschemas.do: | schema/Schema |
      visit schema --nested-name=""

  visit-IfThenElse if-then-else/IfThenElse -> none:
    visit if-then-else.condition-subschema --nested-name=""
    visit if-then-else.then-subschema --nested-name=""
    visit if-then-else.else-subschema --nested-name=""

  visit-DependentSchemas dependent-schemas/DependentSchemas -> none:
    dependent-schemas.subschemas.do: | schema/Schema |
      visit schema --nested-name=""

  visit-Properties properties/Properties -> none:
    if properties.properties:
      properties.properties.do: | prop-name/string schema/Schema |
        visit schema --nested-name=prop-name
    if properties.additional:
      visit properties.additional --nested-name="Value"

  visit-Items items/Items -> none:
    if items.items:
      visit items.items --nested-name="Element"

class QualifiedType_:
  uri/UriReference?  // The JSON-Schema URL of the type, or null if Core.
  clazz/toit-gen.Class

  constructor .clazz --.uri=null:

class SchemaType:
  schema/Schema
  one-of/X-Of? := null
  all-of/X-Of? := null
  any-of/X-Of? := null
  properties/Properties? := null
  required/Required? := null
  items/Items? := null
  ref/Ref? := null
  type/Type? := null
  description-annotation/Annotation? := null
  discriminator/Discriminator? := null

  constructor .schema:
    builder := SchemaTypeBuilder_ this
    schema.actions.do: | action/Action |
      action.accept builder

  url -> UriReference:
    return schema.absolute-location

  single-type -> string?:
    if ref: return (SchemaType ref.target).single-type
    if not type: return null
    accepted-types := type.types
    if accepted-types.size != 1: return null
    return accepted-types.first

  /**
  The schema's effective type for code generation purposes.

  Returns the single type when there is one, or the single non-null type
    when the schema's `type` keyword is `["T","null"]` (treated as nullable T).
  Returns "null" if the schema's only declared type is "null".
  Returns null when the schema declares multiple non-null types or no type.
  */
  effective-type -> string?:
    if ref: return (SchemaType ref.target).effective-type
    if not type: return null
    non-null := type.types.filter: it != "null"
    if non-null.is-empty:
      return type.types.contains "null" ? "null" : null
    if non-null.size == 1: return non-null.first
    return null

  /**
  Whether the schema's `type` keyword permits null.
  */
  is-type-nullable -> bool:
    if ref: return (SchemaType ref.target).is-type-nullable
    if not type: return false
    return type.types.contains "null"

  /**
  Whether the schema's `type` keyword is a union of numeric types (and possibly null).
  */
  is-numeric-union -> bool:
    if ref: return (SchemaType ref.target).is-numeric-union
    if not type: return false
    non-null := type.types.filter: it != "null"
    if non-null.size < 2: return false
    return non-null.every: it == "integer" or it == "number"

  is-map -> bool:
    if ref: return (SchemaType ref.target).is-map
    if not type: return false
    if not properties: return false
    if properties.properties: return false
    return true

  is-typed-map -> bool:
    return is-map and properties.additional != null

  type class-manager/ClassManager -> QualifiedType_:
    if ref:
      on-stack := {}
      current-type := this
      on-stack.add current-type.url
      while current-type.ref:
        current-ref := current-type.ref
        current-type = SchemaType current-ref.target
        if on-stack.contains current-type.url:
          // Circular reference.
          return QualifiedType_ class-manager.any-class
        on-stack.add current-type.url
      return current-type.type class-manager
    type-string := effective-type
    if type-string:
      if type-string == "null":
        return QualifiedType_ class-manager.null-class
      if type-string == "boolean":
        return QualifiedType_ class-manager.bool-class
      if type-string == "object":
        if is-map: return QualifiedType_ class-manager.map-class
        return QualifiedType_ class-manager[url] --uri=url
      if type-string == "array":
        return QualifiedType_ class-manager.list-class
      if type-string == "number":
        return QualifiedType_ class-manager.num-class
      if type-string == "string":
        return QualifiedType_ class-manager.string-class
      if type-string == "integer":
        return QualifiedType_ class-manager.int-class
    if is-numeric-union:
      return QualifiedType_ class-manager.num-class
    if one-of or all-of or any-of or properties:
      return QualifiedType_ class-manager[url] --uri=url
    return QualifiedType_ class-manager.any-class

  is-primitive -> bool:
    type-string := effective-type
    if not type-string: return is-numeric-union
    return type-string == "null" or
        type-string == "boolean" or
        type-string == "number" or
        type-string == "string" or
        type-string == "integer"

  is-object -> bool:
    type-string := effective-type
    if not type-string: return false
    return type-string == "object"

  convert-from-json expr/toit-gen.Expression -> toit-gen.Expression
      --class-manager/ClassManager
      [--gen-ref]
  :
    if effective-type == "array" and items and items.items:
      element-type := SchemaType items.items
      if not element-type.is-primitive:
        it-def := toit-gen.VarDefinition.it
        it-ref := toit-gen.Ref it-def
        element-conversion := element-type.convert-from-json it-ref
            --class-manager=class-manager
            --gen-ref=gen-ref
        block := toit-gen.Block --parameters=[it-def]
            toit-gen.Statement element-conversion
        return toit-gen.Call expr "map" --arguments=[block]
    if not is-object: return expr
    if is-typed-map:
      value-type := SchemaType properties.additional
      value-def := toit-gen.VarDefinition.parameter "v"
      value-ref := toit-gen.Ref value-def
      element-conversion := value-type.convert-from-json value-ref
          --class-manager=class-manager
          --gen-ref=gen-ref
      block := toit-gen.Block --parameters=[toit-gen.VarDefinition.ignored, value-def]
          toit-gen.Statement element-conversion
      map-call := toit-gen.Call expr "map" --arguments=[block]
      return map-call
    if is-map:
      return toit-gen.As expr class-manager.map-class
    self-ref/toit-gen.Ref := gen-ref.call this
    return toit-gen.Call self-ref "from-json"
        --arguments=[expr]

  /**
  Converts an expression to its JSON representation.

  Returns the expression unchanged for primitives, or wraps it in a
    `.to-json` call for objects and typed arrays.
  */
  convert-to-json expr/toit-gen.Expression -> toit-gen.Expression:
    if effective-type == "array" and items and items.items:
      element-type := SchemaType items.items
      if not element-type.is-primitive:
        it-def := toit-gen.VarDefinition.it
        it-ref := toit-gen.Ref it-def
        element-conversion := element-type.convert-to-json it-ref
        block := toit-gen.Block --parameters=[it-def]
            toit-gen.Statement element-conversion
        return toit-gen.Call expr "map" --arguments=[block]
    if ref:
      return (SchemaType ref.target).convert-to-json expr
    if not is-object: return expr
    if is-typed-map:
      value-type := SchemaType properties.additional
      value-def := toit-gen.VarDefinition.parameter "v"
      value-ref := toit-gen.Ref value-def
      element-conversion := value-type.convert-to-json value-ref
      block := toit-gen.Block --parameters=[toit-gen.VarDefinition.ignored, value-def]
          toit-gen.Statement element-conversion
      return toit-gen.Call expr "map" --arguments=[block]
    if is-map: return expr
    return toit-gen.Call expr "to-json"

/**
Populates a $SchemaType's fields by visiting the source schema's actions.
*/
class SchemaTypeBuilder_ extends BaseActionVisitor:
  target/SchemaType

  constructor .target:

  visit-Ref action/Ref -> none:
    target.ref = action

  visit-X-Of x-of/X-Of -> none:
    if x-of.kind == X-Of.ALL-OF: target.all-of = x-of
    else if x-of.kind == X-Of.ANY-OF: target.any-of = x-of
    else if x-of.kind == X-Of.ONE-OF: target.one-of = x-of
    else: unreachable

  visit-Properties action/Properties -> none:
    target.properties = action

  visit-Type action/Type -> none:
    target.type = action

  visit-Required action/Required -> none:
    target.required = action

  visit-Items action/Items -> none:
    target.items = action

  visit-Annotation action/Annotation -> none:
    if action.keyword == "description" and action.value is string:
      target.description-annotation = action

  visit-Discriminator action/Discriminator -> none:
    target.discriminator = action

/**
Read-only lookup of classes generated by $populate.

$lookup-by-uri returns the $toit-gen.Class to use as a type reference for
  the schema at the given URI, or null if the schema is primitive (no class
  is generated for primitives).
*/
class Models:
  uri-to-class_/Map  // From UriReference to toit-gen.Class.

  constructor .uri-to-class_:

  lookup-by-uri uri/UriReference -> toit-gen.Class?:
    return uri-to-class_.get uri

  lookup schema/Schema -> toit-gen.Class?:
    return lookup-by-uri schema.absolute-location

/**
Generates classes for $schemas into $program, routing each class to a
  library chosen by $library-for-uri.

$library-for-uri receives a schema's absolute URI and must return the
  $toit-gen.Library that the generated class should be added to. The library
  must already belong to $program.

Returns a $Models facade for looking up the generated classes by URI.

Cross-library references generate imports automatically. The caller is
  responsible for adding the libraries to $program before calling.
*/
populate program/toit-gen.Program schemas/List --library-for-uri/Lambda -> Models:
  if schemas.is-empty:
    throw "populate requires at least one schema"
  generator := Generator_ program --library-for-uri=library-for-uri
  generator.run schemas
  return Models generator.class-manager.classes

/**
Convenience wrapper around $populate for the single-library case.

Builds a fresh $toit-gen.Program with one $toit-gen.Library at $module,
  calls $populate, and returns the rendered file map (filename → source).
*/
gen schemas/List --module/string="schema.toit" -> Map:
  if schemas.is-empty:
    throw "gen requires at least one schema"
  program := toit-gen.Program
  library := toit-gen.Library module
  program.libraries.add library
  populate program schemas --library-for-uri=:: library
  return program.gen --in-memory

/**
Per-run state for a single $populate invocation. Private impl detail.
*/
class Generator_:
  program/toit-gen.Program
  library-for-uri_/Lambda
  done/Set ::= {}
  class-manager/ClassManager ::= ClassManager
  schema-types_/Map ::= {:}  // From UriReference to SchemaType.
  // Schemas that appear as $ref-target in some allOf list. These get a public
  // interface plus a private impl class.
  needs-interface_/Set ::= {}  // Of UriReference.
  // Maps oneOf variant schema URLs to their parent oneOf schema URL.
  one-of-parent_/Map ::= {:}  // From UriReference to UriReference.
  // Maps oneOf schema URLs to their discriminator property name.
  one-of-discriminator_/Map ::= {:}  // From UriReference to string.
  // Maps oneOf schema URLs to discriminator value → variant URL.
  one-of-mapping_/Map ::= {:}  // From UriReference to Map<string, UriReference>.
  // Maps schema URLs to Schema objects (populated during run).
  schema-by-url_/Map ::= {:}  // From UriReference to Schema.
  // Per-library generation state, keyed by toit-gen.Library identity.
  library-gens_/Map ::= {:}  // From toit-gen.Library to LibraryGen.
  // Maps each generated class URI to the toit-gen.Library it lives in.
  // Used by LibraryGen.gen-import_ to emit cross-library imports.
  library-of-class_/Map ::= {:}  // From UriReference to toit-gen.Library.

  constructor .program --library-for-uri/Lambda:
    library-for-uri_ = library-for-uri

  /**
  Returns a (cached) $SchemaType for $schema.

  Avoids reconstructing $SchemaType objects (each one re-runs the action visitor).
  */
  schema-type schema/Schema -> SchemaType:
    return schema-types_.get schema.absolute-location --init=:
      SchemaType schema

  gen-type type/SchemaType -> QualifiedType_:
    result := type.type class-manager

    if done.contains type.url:
      return result
    done.add type.url

    if type.ref:
      gen-type (schema-type type.ref.target)
      return result

    if type.type and type.type.types != ["object"]:
      return result

    if type.is-map:
      return result

    library-gen := library-gen-for-url_ type.url
    library-gen.gen-class type
    return result

  run schemas/List -> none:
    // TODO(florian): handle dynamic refs.
    // We need to collect all dynamic refs, and all the resource-uris.
    // Then extract the possible target schemas from the store.
    store := (schemas.first as JsonSchema).store_

    ref-visitor := CollectRefTargetsVisitor
    schemas.do: | schema/JsonSchema |
      // Not really a target, but this way we have all
      // transitive schemas we need.
      ref-visitor.ref-targets.add schema.schema
      ref-visitor.visit schema.schema

    reffed := ref-visitor.ref-targets.to-list
    reffed.sort: | a/Schema b/Schema |
      a.absolute-location.to-string.compare-to b.absolute-location.to-string

    // Build URL → Schema lookup.
    reffed.do: | schema/Schema |
      schema-by-url_[schema.absolute-location] = schema

    // Identify schemas referenced as allOf parents — they must be generated
    // as interfaces so descendants can declare type compatibility via
    // `implements`. (Toit only supports single-inheritance for both classes
    // and interfaces, so multi-parent allOf can't fit any inheritance chain.)
    reffed.do: | schema/Schema |
      type := schema-type schema
      if type.all-of:
        type.all-of.subschemas.do: | sub/Schema |
          sub-type := schema-type sub
          if sub-type.ref:
            needs-interface_.add sub-type.ref.target.absolute-location

    name-visitor := NameVisitor class-manager --needs-interface=needs-interface_
    reffed.do: | schema/Schema |
      name-visitor.visit schema --if-no-name=: "Root"

    // At this point the namer has assigned names to all schemas.
    // The 'type-names' map represents the actual type name we use for
    // each schema. Differences arise when a schema has a '$ref', or
    // if a schema represents a primitive type.

    // Analyze schemas for oneOf/anyOf patterns.
    reffed.do: | schema/Schema |
      type := schema-type schema
      // Track oneOf/anyOf: map variants to parent.
      // anyOf is treated identically to oneOf for code generation.
      x-of := type.one-of or type.any-of
      if x-of:
        parent-url := schema.absolute-location
        if type.discriminator:
          disc-prop := type.discriminator.property
          one-of-discriminator_[parent-url] = disc-prop
          mapping := {:}
          if type.discriminator.resolved-mapping:
            type.discriminator.resolved-mapping.do: | value/string target/Schema |
              mapping[value] = target.absolute-location
              one-of-parent_[target.absolute-location] = parent-url
          else:
            // No explicit mapping — derive from variant schema names.
            x-of.subschemas.do: | sub/Schema |
              sub-type := schema-type sub
              if sub-type.ref:
                target-url := sub-type.ref.target.absolute-location
                target-class := class-manager[target-url]
                if target-class:
                  mapping[target-class.preferred-name] = target-url
                  one-of-parent_[target-url] = parent-url
          one-of-mapping_[parent-url] = mapping
        else:
          // No discriminator — register variants for heuristic dispatch.
          mapping := {:}
          x-of.subschemas.do: | sub/Schema |
            sub-type := schema-type sub
            if sub-type.ref:
              target-url := sub-type.ref.target.absolute-location
              target-class := class-manager[target-url]
              if target-class:
                mapping[target-class.preferred-name] = target-url
                one-of-parent_[target-url] = parent-url
          one-of-mapping_[parent-url] = mapping

    reffed.do: | schema/Schema |
      type := schema-type schema
      gen-type type

  library-gen-for-url_ uri/UriReference -> LibraryGen:
    library/toit-gen.Library := library-for-uri_.call uri
    library-of-class_[uri] = library
    return library-gens_.get library --init=:
      LibraryGen library --run=this

class LibraryGen:
  library/toit-gen.Library
  run_/Generator_
  core-import/toit-gen.Import
  // Imports from this library to other libraries within the same program,
  // keyed by target Library identity.
  cross-library-imports_/Map ::= {:}  // From toit-gen.Library to toit-gen.Import.

  constructor .library --run/Generator_:
    run_ = run
    core-import = toit-gen.Import ["core"]
    library.imports.add core-import

  class-manager -> ClassManager:
    return run_.class-manager

  /**
  Generates fields for $source-type's properties on $target.

  Skips property names already in $declared (e.g. inherited from a super-class
    chain or contributed by an earlier source on this class). Adds newly-declared
    names to $declared.

  Returns triples [prop-name/string, prop-type/SchemaType, field/VarDefinition]
    for each newly-declared field, in property iteration order. Skipped
    properties simply do not appear in the result.
  */
  gen-fields_ source-type/SchemaType --target/toit-gen.Class --declared/Set -> List:
    triples := []
    if not source-type.properties or not source-type.properties.properties: return triples
    source-type.properties.properties.do: | prop-name/string schema/Schema |
      if declared.contains prop-name: continue.do
      prop-type := run_.schema-type schema
      field-qualified-type := run_.gen-type prop-type
      field-type-import := gen-import_ field-qualified-type
      field-type-ref/toit-gen.Ref := ?
      if field-type-import:
        field-type-ref = toit-gen.ImportedRef field-type-import field-qualified-type.clazz
      else:
        field-type-ref = toit-gen.Ref field-qualified-type.clazz

      is-required := source-type.required != null
          and source-type.required.properties.contains prop-name
      initial/toit-gen.Expression := is-required
          ? toit-gen.LateInitialized
          : toit-gen.Literal null
      field := toit-gen.VarDefinition.field prop-name
          --type=field-type-ref
          --is-nullable=not is-required
          --initial=initial
          --is-final=false
      if prop-type.description-annotation:
        field.toitdoc = [prop-type.description-annotation.value]
      target.fields.add field
      triples.add [prop-name, prop-type, field]
      declared.add prop-name
    return triples

  /**
  Generates constructor body statements that initialize $triples from
    a `data/Map` parameter.
  */
  gen-constructor-body_ triples/List --data-arg/toit-gen.VarDefinition --body/toit-gen.Sequence -> none:
    triples.do: | triple/List |
      prop-name/string := triple[0]
      prop-type/SchemaType := triple[1]
      field := triple[2]
      index := toit-gen.Index (toit-gen.Ref data-arg) (toit-gen.Literal prop-name)
      converted := prop-type.convert-from-json index
          --class-manager=class-manager
          --gen-ref=: | t/SchemaType |
            qualified := run_.gen-type t
            imp := gen-import_ qualified
            if imp:
              toit-gen.ImportedRef imp qualified.clazz
            else:
              toit-gen.Ref qualified.clazz
      body.assign field converted

  /**
  Appends to-json map entries for $triples (one entry per triple).
  */
  gen-to-json-entries_ triples/List --keys/List --values/List -> none:
    triples.do: | triple/List |
      prop-name/string := triple[0]
      prop-type/SchemaType := triple[1]
      field := triple[2]
      field-ref := toit-gen.Ref field
      converted := prop-type.convert-to-json field-ref
      keys.add (toit-gen.Literal prop-name)
      values.add converted

  gen-class type/SchemaType -> none:
    // Check if this is a oneOf base schema.
    if run_.one-of-mapping_.contains type.url:
      gen-one-of-base_ type
      return

    // The public face: an interface for schemas referenced as allOf parents,
    // a regular class otherwise. The impl class is the same when the public
    // face is a class; for interfaces, it's the private impl class.
    public-clazz := class-manager[type.url]
    impl-clazz := class-manager.target-class type.url
    is-interface := public-clazz != impl-clazz

    if type.description-annotation:
      public-clazz.toitdoc = [type.description-annotation.value]

    // OneOf variants extend the abstract oneOf base — keep that single
    // super-class line. Note: oneOf bases never appear as allOf parents in
    // practice (they're abstract), so this doesn't conflict with the
    // interface-based allOf design.
    one-of-parent-url := run_.one-of-parent_.get type.url
    if one-of-parent-url:
      parent-class := class-manager[one-of-parent-url]
      if parent-class:
        impl-clazz.super-class = toit-gen.Ref parent-class

    // Collect direct allOf $ref parents in declaration order. The first one
    // becomes the `extends` parent for the public interface (its members
    // propagate without redeclaration); the rest go in `implements` (those
    // members must be redeclared in the interface body).
    direct-parent-interfaces := []
    first-parent-type/SchemaType? := null
    if type.all-of:
      type.all-of.subschemas.do: | sub/Schema |
        sub-type := run_.schema-type sub
        if not sub-type.ref: continue.do
        ref-target := sub-type.ref.target
        ref-target-type := run_.schema-type ref-target
        run_.gen-type ref-target-type
        parent-itf := class-manager[ref-target.absolute-location]
        if parent-itf and parent-itf.kind == toit-gen.Class.INTERFACE:
          direct-parent-interfaces.add parent-itf
          if not first-parent-type: first-parent-type = ref-target-type

    if is-interface:
      // First parent → extends (single-inheritance, members propagate).
      // Remaining parents → implements (require redeclaration).
      if not direct-parent-interfaces.is-empty:
        public-clazz.super-class = toit-gen.Ref direct-parent-interfaces.first
        for i := 1; i < direct-parent-interfaces.size; i++:
          public-clazz.interfaces.add (toit-gen.Ref direct-parent-interfaces[i])
      impl-clazz.interfaces.add (toit-gen.Ref public-clazz)
    else:
      // Leaf class: list direct parent interfaces. Transitive compatibility
      // comes from the parent interfaces' own extends/implements chain.
      direct-parent-interfaces.do: | itf/toit-gen.Class |
        impl-clazz.interfaces.add (toit-gen.Ref itf)

    // Collect all property sources transitively. Order: own → allOf $ref
    // parents (recursive) → inline allOf subschemas (recursive). Dedup by
    // property name (first wins).
    declared/Set := {}
    triples := []
    collect-fields-recursive_ type --target=impl-clazz --declared=declared --triples=triples

    // Generate from-json constructor on the impl class.
    data-arg := toit-gen.VarDefinition.parameter "data"
        --type=toit-gen.ImportedRef core-import class-manager.map-class
    constructor-body := toit-gen.Sequence
    if one-of-parent-url:
      // OneOf variant: call super.from-sub_ (the abstract base's private constructor).
      constructor-body.add
          toit-gen.Statement (toit-gen.Call toit-gen.Super "from-sub_")
    gen-constructor-body_ triples --data-arg=data-arg --body=constructor-body
    constr := toit-gen.Function.constr --name="from-json" --parameters=[data-arg] constructor-body
    impl-clazz.members.add constr

    // Generate to-json on the impl class.
    to-json-body := toit-gen.Sequence
    map-keys := []
    map-values := []
    gen-to-json-entries_ triples --keys=map-keys --values=map-values
    map-literal := toit-gen.MapLiteral map-keys map-values
    to-json-body.ret map-literal
    to-json-map-ref := toit-gen.ImportedRef core-import class-manager.map-class
    to-json-method := toit-gen.Function "to-json"
        --parameters=[]
        --return-type=to-json-map-ref
        to-json-body
    impl-clazz.members.add to-json-method

    if is-interface:
      // Members inherited from the extends parent's chain don't need to be
      // redeclared on this interface; only members from `implements` parents
      // and own/inline must be declared.
      inherited-via-extends/Set := {}
      if first-parent-type:
        collect-property-names-recursive_ first-parent-type --result=inherited-via-extends
      gen-interface-members_ public-clazz
          --triples=triples
          --impl=impl-clazz
          --skip=inherited-via-extends
      library.classes.add public-clazz
    library.classes.add impl-clazz

  /**
  Walks $type's allOf chain transitively, generating fields on $target for
    every property encountered (deduped by name). $declared is updated with
    the names of newly-declared fields, and $triples receives the
    `[prop-name, SchemaType, field]` entries in declaration order.

  Order: $type's own properties first, then each allOf \$ref parent (recursing
    into the parent's own allOf chain), then each inline allOf subschema
    (also recursing).
  */
  collect-fields-recursive_ type/SchemaType
      --target/toit-gen.Class
      --declared/Set
      --triples/List
      -> none:
    triples.add-all (gen-fields_ type --target=target --declared=declared)
    if not type.all-of: return
    type.all-of.subschemas.do: | sub/Schema |
      sub-type := run_.schema-type sub
      if sub-type.ref:
        ref-target-type := run_.schema-type sub-type.ref.target
        collect-fields-recursive_ ref-target-type --target=target --declared=declared --triples=triples
      else if sub-type.properties and sub-type.properties.properties:
        collect-fields-recursive_ sub-type --target=target --declared=declared --triples=triples

  /**
  Walks $type's allOf chain transitively and adds every property name it
    encounters to $result. Used to compute the set of members an interface
    inherits via `extends` (so the interface body can skip redeclaring them).
  */
  collect-property-names-recursive_ type/SchemaType --result/Set -> none:
    if type.properties and type.properties.properties:
      type.properties.properties.do: | name/string _ |
        result.add name
    if not type.all-of: return
    type.all-of.subschemas.do: | sub/Schema |
      sub-type := run_.schema-type sub
      if sub-type.ref:
        collect-property-names-recursive_ (run_.schema-type sub-type.ref.target) --result=result
      else if sub-type.properties:
        collect-property-names-recursive_ sub-type --result=result

  /**
  Populates an interface declaration with abstract getter signatures (one per
    property in $triples whose name is not in $skip) and a factory
    `constructor.from-json` that returns a fresh $impl instance.

  $skip holds names inherited via the interface's `extends` parent — those
    don't need to be redeclared.

  Toit interfaces accept method signatures (no body, no `abstract` keyword)
    plus factory constructors with bodies; the patched toit-gen renders these
    correctly when the enclosing class has `kind == INTERFACE`.
  */
  gen-interface-members_ itf/toit-gen.Class --triples/List --impl/toit-gen.Class --skip/Set -> none:
    triples.do: | triple/List |
      prop-name/string := triple[0]
      if skip.contains prop-name: continue.do
      field/toit-gen.VarDefinition := triple[2]
      // Reuse the impl field's type ref for the getter return type.
      getter := toit-gen.Function prop-name
          --parameters=[]
          --return-type=field.type
          --is-abstract
          null
      itf.members.add getter
    // Factory: constructor.from-json data/Map -> Itf  (return Impl_.from-json data)
    data-arg := toit-gen.VarDefinition.parameter "data"
        --type=toit-gen.ImportedRef core-import class-manager.map-class
    factory-body := toit-gen.Sequence
    factory-body.ret
        toit-gen.Call (toit-gen.Ref impl) "from-json" --arguments=[toit-gen.Ref data-arg]
    factory := toit-gen.Function.constr --name="from-json" --parameters=[data-arg] factory-body
    itf.members.add factory

  /**
  Generates an abstract base class for a oneOf schema with discriminator.

  Creates a factory `constructor.from-json` that dispatches to the
    appropriate variant based on the discriminator property value.
  */
  gen-one-of-base_ type/SchemaType -> none:
    qualified-clazz := type.type class-manager
    clazz := qualified-clazz.clazz
    clazz.is-abstract = true
    if type.description-annotation:
      clazz.toitdoc = [type.description-annotation.value]

    // Private constructor for subclasses.
    from-sub := toit-gen.Function.constr --name="from-sub_" --parameters=[]
    clazz.members.add from-sub

    // Abstract to-json method.
    to-json-map-ref := toit-gen.ImportedRef core-import class-manager.map-class
    abstract-to-json := toit-gen.Function "to-json"
        --parameters=[]
        --return-type=to-json-map-ref
        --is-abstract
    clazz.members.add abstract-to-json

    // Factory constructor.from-json that dispatches to variants.
    disc-prop := run_.one-of-discriminator_.get type.url
    mapping := run_.one-of-mapping_[type.url]
    data-arg := toit-gen.VarDefinition.parameter "data"
        --type=toit-gen.ImportedRef core-import class-manager.map-class
    factory-body := toit-gen.Sequence

    if disc-prop:
      // Discriminator-based dispatch.
      disc-var := factory-body.define "type"
          toit-gen.Index (toit-gen.Ref data-arg) (toit-gen.Literal disc-prop)
      mapping.do: | disc-value/string variant-url/UriReference |
        variant-class := class-manager[variant-url]
        if variant-class:
          condition := toit-gen.Binary
              (toit-gen.Ref disc-var)
              "=="
              (toit-gen.Literal disc-value)
          then-body := toit-gen.Sequence
          then-body.ret
              toit-gen.Call (toit-gen.Ref variant-class) "from-json" --arguments=[toit-gen.Ref data-arg]
          factory-body.iff condition then-body
      factory-body.add
          toit-gen.Throw
              toit-gen.StringInterpolation ["Unknown $disc-prop: ", toit-gen.Ref disc-var, ""]
    else:
      // Heuristic dispatch: check for required/unique fields.
      // Discriminator-less oneOf is supported only when each variant is
      // statically distinguishable. We fail at codegen otherwise rather than
      // emit dispatch that's wrong on edge cases at runtime.
      check-heuristic-decidable_ type mapping
      mapping.do: | _/string variant-url/UriReference |
        variant-class := class-manager[variant-url]
        if not variant-class: continue.do
        variant-type := find-variant-type_ variant-url
        if not variant-type: continue.do
        distinguishing-field := find-distinguishing-field_ variant-type mapping
        // check-heuristic-decidable_ has already verified this is non-null.
        condition := toit-gen.Call (toit-gen.Ref data-arg) "contains"
            --arguments=[toit-gen.Literal distinguishing-field]
        then-body := toit-gen.Sequence
        then-body.ret
            toit-gen.Call (toit-gen.Ref variant-class) "from-json" --arguments=[toit-gen.Ref data-arg]
        factory-body.iff condition then-body
      factory-body.add
          toit-gen.Throw (toit-gen.Literal "No matching variant")
    factory := toit-gen.Function.constr --name="from-json" --parameters=[data-arg] factory-body
    clazz.members.add factory

    library.classes.add clazz

  /**
  Finds the SchemaType for a variant URL.
  */
  find-variant-type_ variant-url/UriReference -> SchemaType?:
    schema := run_.schema-by-url_.get variant-url
    if not schema: return null
    return run_.schema-type schema

  /**
  Validates that a discriminator-less oneOf is statically decidable.

  Throws at codegen if:
  - Any variant lacks a distinguishing field (so dispatch would silently drop
    the variant at runtime).
  - One variant's required-property set is a strict subset of another's
    (so an input matching the larger variant would also satisfy the smaller
    variant's `contains` heuristic, making dispatch order-dependent).

  Both conditions are user-fixable: add a discriminator on $base-type.
  */
  check-heuristic-decidable_ base-type/SchemaType mapping/Map -> none:
    variant-types/List := []
    mapping.do: | _/string variant-url/UriReference |
      variant-type := find-variant-type_ variant-url
      if variant-type: variant-types.add variant-type

    // Strict-subset detection across required sets.
    variant-types.do: | a/SchemaType |
      a-required := required-set_ a
      if a-required.is-empty: continue.do
      variant-types.do: | b/SchemaType |
        if identical a b: continue.do
        b-required := required-set_ b
        if b-required.size <= a-required.size: continue.do
        if is-subset_ a-required b-required:
          throw "Discriminator-less oneOf at $(base-type.url) is ambiguous: variant $(a.url)'s required set is a subset of $(b.url)'s. Add a discriminator."

    // Each variant must have a distinguishing field.
    variant-types.do: | v/SchemaType |
      distinguishing := find-distinguishing-field_ v mapping
      if not distinguishing:
        throw "Discriminator-less oneOf at $(base-type.url) cannot statically distinguish variant $(v.url). Add a discriminator."

  static required-set_ type/SchemaType -> Set:
    if not type.required: return {}
    result := {}
    type.required.properties.do: result.add it
    return result

  static is-subset_ a/Set b/Set -> bool:
    a.do: if not b.contains it: return false
    return true

  /**
  Finds a field name that distinguishes this variant from others.

  Returns the name of a required field that is unique to this variant,
    or the first property name if no required fields exist.
  */
  find-distinguishing-field_ variant-type/SchemaType mapping/Map -> string?:
    if not variant-type.properties or not variant-type.properties.properties:
      return null
    // Collect all property names from other variants.
    other-props := {}
    mapping.do: | _/string other-url/UriReference |
      if other-url != variant-type.url:
        other-type := find-variant-type_ other-url
        if other-type and other-type.properties and other-type.properties.properties:
          other-type.properties.properties.do: | name/string _ |
            other-props.add name
    // Find a required field unique to this variant.
    if variant-type.required:
      variant-type.required.properties.do: | name/string |
        if not other-props.contains name: return name
    // Fall back to any unique property.
    variant-type.properties.properties.do: | name/string _ |
      if not other-props.contains name: return name
    // No distinguishing field found.
    return null

  gen-import_ qualified/QualifiedType_ -> toit-gen.Import?:
    uri := qualified.uri
    if not uri:
      // `any` is a builtin keyword; it can't be imported from core.
      if qualified.clazz == class-manager.any-class: return null
      return core-import
    target-library/toit-gen.Library? := run_.library-of-class_.get uri
    if not target-library or target-library == library: return null
    return cross-library-imports_.get target-library --init=:
      // Build path segments for the target library. Toit imports use dotted
      // module paths; we strip a leading "src/" and any ".toit" suffix.
      path := target-library.path
      if path.starts-with "src/": path = path[4..]
      if path.ends-with ".toit": path = path[..path.size - 5]
      segments := path.split "/"
      imp := toit-gen.Import segments
      library.imports.add imp
      imp

