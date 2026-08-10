// Goal 18 Part K: dump the fixed baseline's seven coding-tool
// definitions (name, description, TypeBox parameter schema) exactly as
// constructed, so the gate can lock Cadr's model-visible tool contract
// against mechanically derived expectations instead of a hand-written
// table.
import { createBashToolDefinition } from "../src/core/tools/bash.ts";
import { createEditToolDefinition } from "../src/core/tools/edit.ts";
import { createFindToolDefinition } from "../src/core/tools/find.ts";
import { createGrepToolDefinition } from "../src/core/tools/grep.ts";
import { createLsToolDefinition } from "../src/core/tools/ls.ts";
import { createReadToolDefinition } from "../src/core/tools/read.ts";
import { createWriteToolDefinition } from "../src/core/tools/write.ts";

const cwd = "/tmp";
const definitions = [
	createReadToolDefinition(cwd),
	createBashToolDefinition(cwd),
	createEditToolDefinition(cwd),
	createWriteToolDefinition(cwd),
	createGrepToolDefinition(cwd),
	createFindToolDefinition(cwd),
	createLsToolDefinition(cwd),
];

process.stdout.write(
	JSON.stringify(
		{
			schemaVersion: 1,
			baselineCommit: process.argv[2] ?? "",
			tools: definitions.map((definition) => ({
				name: definition.name,
				description: definition.description,
				parameters: definition.parameters,
				promptSnippet:
					(definition as { promptSnippet?: string }).promptSnippet ?? null,
			})),
		},
		null,
		1,
	) + "\n",
);
