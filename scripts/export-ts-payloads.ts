import { spawnSync } from "node:child_process";
import fs from "node:fs";
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
		"Pass --reference <checkout> for earendil-works/pi commit 71efc6f0c1909874ec8c944637a9ae7fc0e2d508",
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
const tsx = path.resolve("node_modules/.bin/tsx");

fs.copyFileSync(runnerTemplate, runnerPath);
try {
	const result = spawnSync(tsx, [runnerPath, outputDirectory], {
		cwd: referenceDirectory,
		encoding: "utf8",
		stdio: "inherit",
	});
	if (result.error) {
		throw result.error;
	}
	if (result.status !== 0) {
		throw new Error(`Reference payload export exited ${result.status}`);
	}
} finally {
	fs.rmSync(runnerPath, { force: true });
}
