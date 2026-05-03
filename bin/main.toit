// Copyright (C) 2025 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import cli
import encoding.json
import host.file
import json-schema
import json-schema.gen as schema-gen

main args/List:
  command := cli.Command "gen-toit"
      --help="Generate Toit code from a JSON schema"
      --options=[
        cli.Option "out" --short-name="o"
            --help="Output directory for the generated Toit code"
            --type="directory"
            --required
      ]
      --rest=[
        cli.Option "schema"
          --help="Path to the JSON schema file"
          --type="file"
          --required
      ]
      --run=:: | invocation/cli.Invocation |
        gen invocation
  command.run args

gen invocation/cli.Invocation:
  schema-path := invocation["schema"]
  output-dir := invocation["out"]

  contents := file.read-contents schema-path
  decoded := json.decode contents
  schema := json-schema.build decoded

  print "Generating Toit code from schema '$schema-path' into directory '$output-dir'"

  generator := schema-gen.Gen output-dir
  generator.gen [schema]
