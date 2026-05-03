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
  classes/Map ::= {:}  // From UriReference to toit-gen.Class.
  mixins/Map ::= {:}  // From UriReference to toit-gen.Class (kind=MIXIN).
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

  use-class url/UriReference name/string -> toit-gen.Class:
    if classes.contains url:
      return classes[url]

    return use-unique_ --url=url name

  operator [] url/UriReference -> toit-gen.Class?:
    return classes.get url

class CollectRefTargetsVisitor implements ActionVisitor:
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

  visit-Not not_/Not -> none: return

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

  visit-PropertyNames property-names/PropertyNames -> none: return

  visit-Contains contains/Contains -> none: return

  visit-Type type/Type -> none: return

  visit-Enum enum_/Enum -> none: return

  visit-Const const/Const -> none: return

  visit-NumComparison num-comparison/NumComparison -> none: return

  visit-StringLength string-length/StringLength -> none: return

  visit-ArrayLength array-length/ArrayLength -> none: return

  visit-UniqueItems unique-items/UniqueItems -> none: return

  visit-Required required/Required -> none: return

  visit-ObjectSize object-size/ObjectSize -> none: return

  visit-Items items/Items -> none:
    if items.prefix-items and not items.prefix-items.is-empty:
      items.prefix-items.do: | schema/Schema |
        visit schema
    visit items.items

  visit-Pattern pattern/Pattern -> none: return

  visit-DependentRequired dependent-required/DependentRequired -> none: return

  visit-UnevaluatedProperties unevaluated-properties/UnevaluatedProperties -> none:
    visit unevaluated-properties.subschema

  visit-UnevaluatedItems unevaluated-items/UnevaluatedItems -> none:
    visit unevaluated-items.subschema

  visit-Annotation annotation/Annotation -> none: return

  visit-Format format/Format -> none: return

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
class NameVisitor implements ActionVisitor:
  current-class-name/string? := null
  class-manager/ClassManager

  constructor .class-manager:

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
    current-class-name = (class-manager.use-class url name).preferred-name
    schema.actions.do: | action/Action |
      action.accept this
    current-class-name = old-name

  visit-Ref ref/Ref -> none:
    // Do nothing.

  visit-X-Of x-of/X-Of -> none:
    x-of.subschemas.do: | schema/Schema |
      visit schema --nested-name=""

  visit-Not not_/Not -> none:
    // Do nothing.

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

  visit-PropertyNames _/PropertyNames -> none: return

  visit-Contains _/Contains -> none: return

  visit-Type _/Type -> none: return

  visit-Enum _/Enum -> none: return

  visit-Const _/Const -> none: return

  visit-NumComparison _/NumComparison -> none: return

  visit-StringLength _/StringLength -> none: return

  visit-ArrayLength _/ArrayLength -> none: return

  visit-UniqueItems _/UniqueItems -> none: return

  visit-Required _/Required -> none: return

  visit-ObjectSize _/ObjectSize -> none: return

  visit-Items items/Items -> none:
    if items.items:
      visit items.items --nested-name="Element"

  visit-Pattern _/Pattern -> none: return

  visit-DependentRequired _/DependentRequired -> none: return

  visit-UnevaluatedProperties _/UnevaluatedProperties -> none: return

  visit-UnevaluatedItems _/UnevaluatedItems -> none: return

  visit-Annotation _/Annotation -> none: return

  visit-Format _/Format -> none: return

  visit-Discriminator _/Discriminator -> none: return

class QualifiedType_:
  uri/UriReference?  // The JSON-Schema URL of the type, or null if Core.
  clazz/toit-gen.Class

  constructor .clazz --.uri=null:

class SchemaType implements ActionVisitor:
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
    schema.actions.do: | action/Action |
      action.accept this

  url -> UriReference:
    return schema.absolute-location

  single-type -> string?:
    if ref: return (SchemaType ref.target).single-type
    if not type: return null
    accepted-types := type.types
    if accepted-types.size != 1: return null
    return accepted-types.first

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
    type-string := single-type
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
    if one-of or all-of or any-of or properties:
      return QualifiedType_ class-manager[url] --uri=url
    return QualifiedType_ class-manager.any-class

  is-primitive -> bool:
    type-string := single-type
    if not type-string: return false
    return type-string == "null" or
        type-string == "boolean" or
        type-string == "number" or
        type-string == "string" or
        type-string == "integer"

  is-object -> bool:
    type-string := single-type
    if not type-string: return false
    return type-string == "object"

  convert-from-json expr/toit-gen.Expression -> toit-gen.Expression
      --class-manager/ClassManager
      [--gen-ref]
      :
    if single-type == "array" and items and items.items:
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
    if single-type == "array" and items and items.items:
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

  visit-Ref action/Ref -> none:
    ref = action

  visit-X-Of x-of/X-Of -> none:
    if x-of.kind == X-Of.ALL-OF: all-of = x-of
    else if x-of.kind == X-Of.ANY-OF: any-of = x-of
    else if x-of.kind == X-Of.ONE-OF: one-of = x-of
    else: unreachable

  visit-AllOf action/X-Of -> none:
    all-of = action

  visit-AnyOf action/X-Of -> none:
    any-of = action

  visit-OneOf action/X-Of -> none:
    one-of = action

  visit-Not _/Not -> none: return
  visit-IfThenElse _/IfThenElse -> none: return
  visit-DependentSchemas _/DependentSchemas -> none: return

  visit-Properties action/Properties -> none:
    properties = action

  visit-PropertyNames _/PropertyNames -> none: return
  visit-Contains _/Contains -> none: return

  visit-Type action/Type -> none:
    type = action

  visit-Enum _/Enum -> none: return
  visit-Const _/Const -> none: return
  visit-NumComparison _/NumComparison -> none: return
  visit-StringLength _/StringLength -> none: return
  visit-ArrayLength _/ArrayLength -> none: return
  visit-UniqueItems _/UniqueItems -> none: return

  visit-Required action/Required -> none:
    required = action

  visit-ObjectSize _/ObjectSize -> none: return

  visit-Items action/Items -> none:
    items = action

  visit-Pattern _/Pattern -> none: return
  visit-DependentRequired _/DependentRequired -> none: return
  visit-UnevaluatedProperties _/UnevaluatedProperties -> none: return
  visit-UnevaluatedItems _/UnevaluatedItems -> none: return
  visit-Annotation action/Annotation -> none:
    if action.keyword == "description" and
        action.value is string:
      description-annotation = action

  visit-Format _/Format -> none: return
  visit-Discriminator action/Discriminator -> none:
    discriminator = action

class Gen:
  out-path/string
  done/Set ::= {}
  schema-to-clazz/Map ::= {:}
  class-manager/ClassManager ::= ClassManager
  // Schemas that need a mixin generated (because they appear in an allOf).
  needs-mixin_/Set ::= {}  // Of UriReference.
  // Maps oneOf variant schema URLs to their parent oneOf schema URL.
  one-of-parent_/Map ::= {:}  // From UriReference to UriReference.
  // Maps oneOf schema URLs to their discriminator property name.
  one-of-discriminator_/Map ::= {:}  // From UriReference to string.
  // Maps oneOf schema URLs to discriminator value → variant URL.
  one-of-mapping_/Map ::= {:}  // From UriReference to Map<string, UriReference>.
  // Maps schema URLs to Schema objects (populated during gen).
  schema-by-url_/Map ::= {:}  // From UriReference to Schema.
  // TODO(florian): make this a map from uri to library when we
  // support multiple libraries.
  out-gen/LibraryGen? := null

  constructor .out-path:

  gen-type type/SchemaType -> QualifiedType_:
    result := type.type class-manager

    if done.contains type.url:
      return result
    done.add type.url

    if type.ref:
      gen-type (SchemaType type.ref.target)
      return result

    if type.type and type.type.types != ["object"]:
      return result

    if type.is-map:
      return result

    library-gen := library-gen-for-url_ type.url
    library-gen.gen-class type
    return result

  gen schemas/List --in-memory/bool=false -> Map?:
    if schemas.is-empty:
      throw "UNIMPLEMENTED"

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

    name-visitor := NameVisitor class-manager
    reffed.do: | schema/Schema |
      name-visitor.visit schema --if-no-name=: "Root"

    // At this point the namer has assigned names to all schemas.
    // The 'type-names' map represents the actual type name we use for
    // each schema. Differences arise when a schema has a '$ref', or
    // if a schema represents a primitive type.

    // Analyze schemas for allOf/oneOf patterns.
    reffed.do: | schema/Schema |
      type := SchemaType schema
      // Mark schemas that appear in allOf as needing mixin generation.
      if type.all-of:
        type.all-of.subschemas.do: | sub/Schema |
          sub-type := SchemaType sub
          if sub-type.ref:
            needs-mixin_.add sub-type.ref.target.absolute-location
          else if not sub-type.is-primitive:
            needs-mixin_.add sub.absolute-location
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
              sub-type := SchemaType sub
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
            sub-type := SchemaType sub
            if sub-type.ref:
              target-url := sub-type.ref.target.absolute-location
              target-class := class-manager[target-url]
              if target-class:
                mapping[target-class.preferred-name] = target-url
                one-of-parent_[target-url] = parent-url
          one-of-mapping_[parent-url] = mapping

    program := toit-gen.Program

    // TODO(florian): split into multiple libraries.
    library := toit-gen.Library out-path
    program.libraries.add library
    out-gen = LibraryGen library --program-gen=this

    reffed.do: | schema/Schema |
      type := SchemaType schema
      gen-type type

    file-map := program.gen --in-memory
    if in-memory: return file-map
    file-map.do: | path/string code/string |
      print "path: $path"
      print code
      print "=============================="
      print
    return null

  library-gen-for-url_ uri/UriReference -> LibraryGen:
    // For now, all generated classes go into the same library.
    return out-gen

class LibraryGen:
  library/toit-gen.Library
  program-gen/Gen
  core-import/toit-gen.Import

  constructor .library --.program-gen/Gen:
    core-import = toit-gen.Import ["core"]
    library.imports.add core-import

  class-manager -> ClassManager:
    return program-gen.class-manager

  /**
  Generates fields for the given $type's properties on $target.

  The $target is either a class or a mixin.
  Returns the list of generated fields.
  */
  gen-fields_ type/SchemaType --target/toit-gen.Class -> List:
    fields := []
    if not type.properties or not type.properties.properties: return fields
    type.properties.properties.do: | prop-name/string schema/Schema |
      prop-type := SchemaType schema
      field-qualified-type := program-gen.gen-type prop-type
      field-type-import := gen-import_ field-qualified-type
      field-type-ref/toit-gen.Ref := ?
      if field-type-import:
        field-type-ref = toit-gen.ImportedRef field-type-import field-qualified-type.clazz
      else:
        field-type-ref = toit-gen.Ref field-qualified-type.clazz

      is-required := false
      if type.required:
        is-required = type.required.properties.contains prop-name
      initial := default-value-for-type_ prop-type
      field := toit-gen.VarDefinition.field prop-name
          --type=field-type-ref
          --is-nullable=not is-required
          --initial=initial
          --is-final=false
      if prop-type.description-annotation:
        field.toitdoc = [prop-type.description-annotation.value]
      target.fields.add field
      fields.add field
    return fields

  /**
  Generates constructor body statements that initialize $fields from
    a `data/Map` parameter.
  */
  gen-constructor-body_ type/SchemaType --fields/List --data-arg/toit-gen.VarDefinition --body/toit-gen.Sequence -> none:
    if not type.properties or not type.properties.properties: return
    field-index := 0
    type.properties.properties.do: | prop-name/string schema/Schema |
      prop-type := SchemaType schema
      field := fields[field-index++]
      index := toit-gen.Index (toit-gen.Ref data-arg) (toit-gen.Literal prop-name)
      converted := prop-type.convert-from-json index
          --class-manager=class-manager
          --gen-ref=: | type/SchemaType |
            qualified := program-gen.gen-type type
            imp := gen-import_ qualified
            if imp:
              toit-gen.ImportedRef imp qualified.clazz
            else:
              toit-gen.Ref qualified.clazz
      body.assign field converted

  /**
  Generates to-json map entries for the given $type's properties.
  */
  gen-to-json-entries_ type/SchemaType --fields/List --keys/List --values/List -> none:
    if not type.properties or not type.properties.properties: return
    field-index := 0
    type.properties.properties.do: | prop-name/string schema/Schema |
      prop-type := SchemaType schema
      field-ref := toit-gen.Ref fields[field-index++]
      converted := prop-type.convert-to-json field-ref
      keys.add (toit-gen.Literal prop-name)
      values.add converted

  gen-class type/SchemaType -> none:
    // Check if this is a oneOf base schema.
    if program-gen.one-of-mapping_.contains type.url:
      gen-one-of-base_ type
      return

    qualified-clazz := type.type class-manager
    clazz := qualified-clazz.clazz
    if type.description-annotation:
      clazz.toitdoc = [type.description-annotation.value]

    // If this schema is a oneOf variant, extend the parent base class.
    parent-url := program-gen.one-of-parent_.get type.url
    if parent-url:
      parent-class := class-manager[parent-url]
      if parent-class:
        clazz.super-class = toit-gen.Ref parent-class

    needs-mixin := program-gen.needs-mixin_.contains type.url
    mixin-clazz/toit-gen.Class? := null

    if needs-mixin:
      // Generate the mixin with fields.
      mixin-name := "$(clazz.preferred-name)Mixin"
      mixin-clazz = toit-gen.Class mixin-name --kind=toit-gen.Class.MIXIN
      class-manager.mixins[type.url] = mixin-clazz
      gen-fields_ type --target=mixin-clazz
      library.classes.add mixin-clazz

      // The class extends Object with the mixin.
      object-class := toit-gen.Class.core "Object"
      clazz.super-class = toit-gen.Ref object-class
      clazz.mixins.add (toit-gen.Ref mixin-clazz)

    // Handle allOf: set up inheritance and mixins from $ref subschemas,
    // and collect inline property subschemas for field merging.
    all-of-inline-types := []  // SchemaTypes from inline allOf subschemas.
    // Types from allOf $ref targets, for collecting parent fields in to-json.
    all-of-ref-types := []  // SchemaTypes of resolved $ref targets.
    has-super := false
    if type.all-of:
      type.all-of.subschemas.do: | sub/Schema |
        sub-type := SchemaType sub
        if sub-type.ref:
          // A $ref subschema → inheritance or mixin.
          ref-target-type := SchemaType sub-type.ref.target
          program-gen.gen-type ref-target-type
          target-url := sub-type.ref.target.absolute-location
          target-class := class-manager[target-url]
          all-of-ref-types.add ref-target-type
          if not has-super:
            // First $ref → superclass.
            clazz.super-class = toit-gen.Ref target-class
            has-super = true
          else:
            // Additional $refs → mixin.
            target-mixin := class-manager.mixins.get target-url
            if target-mixin:
              clazz.mixins.add (toit-gen.Ref target-mixin)
        else if sub-type.properties and sub-type.properties.properties:
          // Inline property subschema → merge fields.
          all-of-inline-types.add sub-type

    // Generate fields on the class itself (or use mixin fields for constructor).
    fields/List := ?
    if needs-mixin:
      // Fields are on the mixin; the class references them.
      fields = mixin-clazz.fields.copy
    else:
      fields = gen-fields_ type --target=clazz
    // Also add fields from inline allOf subschemas.
    all-of-inline-types.do: | sub-type/SchemaType |
      fields.add-all (gen-fields_ sub-type --target=clazz)

    // Generate from-json constructor.
    data-arg := toit-gen.VarDefinition.parameter "data"
        --type=toit-gen.ImportedRef core-import class-manager.map-class
    constructor-body := toit-gen.Sequence
    is-one-of-variant := program-gen.one-of-parent_.contains type.url
    if has-super:
      // Call super.from-json first (required before accessing instance members).
      constructor-body.add
          toit-gen.Statement (toit-gen.Call toit-gen.Super "from-json" --arguments=[toit-gen.Ref data-arg])
    else if is-one-of-variant:
      // OneOf variant: call super.from-sub_ (the abstract base's private constructor).
      constructor-body.add
          toit-gen.Statement (toit-gen.Call toit-gen.Super "from-sub_")
    gen-constructor-body_ type --fields=fields --data-arg=data-arg --body=constructor-body
    // Also init fields from inline allOf subschemas.
    all-of-inline-types.do: | sub-type/SchemaType |
      inline-fields := clazz.fields.filter:
        sub-type.properties.properties.contains it.preferred-name
      gen-constructor-body_ sub-type
          --fields=inline-fields
          --data-arg=data-arg
          --body=constructor-body
    constr := toit-gen.Function.constr --name="from-json" --parameters=[data-arg] constructor-body
    clazz.members.add constr

    // Generate to-json method.
    // For allOf, include all fields (parent mixin fields are accessible)
    // in a single map literal.
    to-json-body := toit-gen.Sequence
    map-keys := []
    map-values := []
    // First add parent fields from allOf $refs (accessible via mixin).
    all-of-ref-types.do: | ref-type/SchemaType |
      ref-url := ref-type.url
      ref-mixin := class-manager.mixins.get ref-url
      if ref-mixin:
        gen-to-json-entries_ ref-type --fields=ref-mixin.fields --keys=map-keys --values=map-values
    // Then own fields.
    gen-to-json-entries_ type --fields=fields --keys=map-keys --values=map-values
    all-of-inline-types.do: | sub-type/SchemaType |
      inline-fields := clazz.fields.filter:
        sub-type.properties.properties.contains it.preferred-name
      gen-to-json-entries_ sub-type --fields=inline-fields --keys=map-keys --values=map-values
    map-literal := toit-gen.MapLiteral map-keys map-values
    to-json-body.ret map-literal
    to-json-map-ref := toit-gen.ImportedRef core-import class-manager.map-class
    to-json-method := toit-gen.Function "to-json"
        --parameters=[]
        --return-type=to-json-map-ref
        to-json-body
    clazz.members.add to-json-method

    library.classes.add clazz

  /**
  Returns a default value expression for the given $type.

  Mixin fields cannot use late-init (`:= ?`), so all fields use
    type-appropriate defaults instead.
  */
  static default-value-for-type_ type/SchemaType -> toit-gen.Expression:
    single := type.single-type
    if single == "string": return toit-gen.Literal ""
    if single == "integer" or single == "number": return toit-gen.Literal 0
    if single == "boolean": return toit-gen.Literal false
    return toit-gen.Literal null

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
    disc-prop := program-gen.one-of-discriminator_.get type.url
    mapping := program-gen.one-of-mapping_[type.url]
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
      mapping.do: | _/string variant-url/UriReference |
        variant-class := class-manager[variant-url]
        if not variant-class: continue.do
        // Find a distinguishing required field for this variant.
        variant-type := find-variant-type_ variant-url
        if not variant-type: continue.do
        distinguishing-field := find-distinguishing-field_ variant-type mapping
        if not distinguishing-field: continue.do
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
    schema := program-gen.schema-by-url_.get variant-url
    if not schema: return null
    return SchemaType schema

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
    if not uri: return core-import
    // For now, all generated classes go into the same library.
    return null

