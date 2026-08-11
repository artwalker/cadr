import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

function option(name: string): string | undefined {
	const index = process.argv.indexOf(name);
	return index === -1 ? undefined : process.argv[index + 1];
}

const referenceDirectory = path.resolve(
	option("--reference") ?? process.env.CADR_TS_REFERENCE ?? "",
);
const outputDirectory = path.resolve(
	option("--output") ?? "test/fixtures/requests",
);
const explicitCatalogDirectory = option("--catalog");

if (
	!referenceDirectory ||
	!fs.existsSync(
		path.join(
			referenceDirectory,
			"packages/ai/src/api/anthropic-messages.ts",
		),
	)
) {
	throw new Error(
		"Pass --reference <checkout> for earendil-works/pi commit 53fa77ccd8a279eb87e92294ef3687b03ff80112",
	);
}
if (!fs.existsSync(path.join(referenceDirectory, "node_modules"))) {
	throw new Error(
		"The reference checkout has no node_modules; run npm install --ignore-scripts there first",
	);
}

const runnerTemplate = path.resolve(
	"scripts/export-ts-payloads.runner.ts.txt",
);
const runnerPath = path.join(
	referenceDirectory,
	"scripts/.cadr-export-ts-payloads.ts",
);
const tsx = path.join(referenceDirectory, "node_modules/.bin/tsx");
const temporaryCatalogDirectory = explicitCatalogDirectory
	? undefined
	: fs.mkdtempSync(path.join(os.tmpdir(), "cadr-ts-models-"));
const catalogDirectory = path.resolve(
	explicitCatalogDirectory ?? temporaryCatalogDirectory!,
);

fs.copyFileSync(runnerTemplate, runnerPath);
try {
	if (temporaryCatalogDirectory !== undefined) {
		const generator = spawnSync(
			process.execPath,
			[
				"packages/ai/scripts/generate-models.ts",
				"--strict",
				"--json-only",
				"--json-output",
				catalogDirectory,
			],
			{
				cwd: referenceDirectory,
				encoding: "utf8",
				stdio: "inherit",
			},
		);
		if (generator.error) {
			throw generator.error;
		}
		if (generator.status !== 0) {
			throw new Error(`Reference catalog generation exited ${generator.status}`);
		}
	}
	const result = spawnSync(
		tsx,
		[runnerPath, outputDirectory, catalogDirectory],
		{
		cwd: referenceDirectory,
		encoding: "utf8",
		stdio: "inherit",
		},
	);
	if (result.error) {
		throw result.error;
	}
	if (result.status !== 0) {
		throw new Error(`Reference payload export exited ${result.status}`);
	}
} finally {
	fs.rmSync(runnerPath, { force: true });
	if (temporaryCatalogDirectory !== undefined) {
		fs.rmSync(temporaryCatalogDirectory, {
			force: true,
			recursive: true,
		});
	}
}
