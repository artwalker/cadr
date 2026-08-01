#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import path from "node:path";

const entryCounts = [0, 50, 200, 1000, 5000];
const samples = 5;
const warmups = 1;
const width = 100;
const height = 40;

const baselineDirectory = process.argv[2];
if (!baselineDirectory) {
	throw new Error("usage: goal11-pi-baseline-bench.mjs BASELINE_WORKTREE");
}

const revision = execFileSync("git", ["-C", baselineDirectory, "rev-parse", "HEAD"], {
	encoding: "utf8",
}).trim();
if (revision !== "74caa2649f10ed71b4378ce69f5d9fbfd2466ca5") {
	throw new Error(`expected baseline 74caa2649, got ${revision}`);
}

const moduleUrl = (relativePath) =>
	pathToFileURL(path.join(baselineDirectory, relativePath)).href;

const { Container, Editor } = await import(moduleUrl("packages/tui/dist/index.js"));
const { TuiMainScreen } = await import(moduleUrl("packages/tui/dist/TuiMainScreen.js"));
const { AssistantMessageComponent } = await import(
	moduleUrl("packages/coding-agent/dist/modes/interactive/components/assistant-message.js")
);
const { BashExecutionComponent } = await import(
	moduleUrl("packages/coding-agent/dist/modes/interactive/components/bash-execution.js")
);
const { ToolExecutionComponent } = await import(
	moduleUrl("packages/coding-agent/dist/modes/interactive/components/tool-execution.js")
);
const { UserMessageComponent } = await import(
	moduleUrl("packages/coding-agent/dist/modes/interactive/components/user-message.js")
);
const { getEditorTheme, initTheme } = await import(
	moduleUrl("packages/coding-agent/dist/modes/interactive/theme/theme.js")
);

initTheme("dark", false);

class BenchmarkTerminal {
	columns = width;
	rows = height;
	writtenBytes = 0;

	write(data) {
		this.writtenBytes += Buffer.byteLength(data);
	}

	start() {}
	stop() {}
	showCursor() {}
	hideCursor() {}
	setTitle() {}
	clearScreen() {}
	moveCursor() {}
	queryTerminalColor() {}
}

const assistantMessage = (text) => ({
	role: "assistant",
	content: [{ type: "text", text }],
	api: "faux",
	provider: "faux",
	model: "faux-bench",
	usage: {
		input: 0,
		output: 0,
		cacheRead: 0,
		cacheWrite: 0,
		totalTokens: 0,
		cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
	},
	stopReason: "stop",
	timestamp: 0,
});

function makeEntry(index, ui) {
	const kind = index % 5;
	if (kind === 0) {
		return new UserMessageComponent(
			`Request ${index}: explain **cache behavior** for 中文输入 and emoji 🚀 without changing output.`,
		);
	}
	if (kind === 1) {
		return new AssistantMessageComponent(
			assistantMessage(`Entry ${index} keeps markdown, \`inline code\`, and wrapping intact.`),
		);
	}
	if (kind === 4) {
		return new AssistantMessageComponent(
			assistantMessage(
				`![image placeholder ${index}](attachment://fixture.png) CJK 宽度与 emoji 🧪 占位。`,
			),
		);
	}

	if (kind === 2) {
		const read = new ToolExecutionComponent(
			"read",
			`read-benchmark-${index}`,
			{ path: `docs/example-${index}.md`, offset: 1, limit: 4 },
			{},
			undefined,
			ui,
			baselineDirectory,
		);
		read.updateResult(
			{ content: [{ type: "text", text: "alpha\nbeta\ngamma\ndelta" }], isError: false },
			false,
		);
		return read;
	}

	const bash = new BashExecutionComponent("printf 'one\\ntwo\\nthree\\n'", ui);
	bash.appendOutput("one\ntwo\nthree");
	bash.setComplete(0, false);
	bash.setExpanded(true);
	return bash;
}

function makeFixture(count, streaming = false) {
	const terminal = new BenchmarkTerminal();
	const ui = new TuiMainScreen(terminal);
	const chat = new Container();
	for (let index = 0; index < count; index += 1) {
		chat.addChild(makeEntry(index, ui));
	}
	const stream = streaming
		? new AssistantMessageComponent(assistantMessage("stream"))
		: undefined;
	if (stream) chat.addChild(stream);
	const editor = new Editor(ui, getEditorTheme());
	ui.addChild(chat);
	ui.addChild(editor);
	ui.doRender();
	return { chat, editor, stream, terminal, ui };
}

function median(values) {
	const sorted = [...values].sort((a, b) => a - b);
	const middle = Math.floor(sorted.length / 2);
	return sorted.length % 2 === 1
		? sorted[middle]
		: (sorted[middle - 1] + sorted[middle]) / 2;
}

function statistics(values) {
	const center = median(values);
	return {
		median_us: center,
		mad_us: median(values.map((value) => Math.abs(value - center))),
		samples_us: values,
	};
}

function repetitions(count, kind) {
	if (kind === "append") return count <= 200 ? 100000 : count <= 1000 ? 30000 : 10000;
	if (count <= 200) return 50;
	if (count <= 1000) return 20;
	return 5;
}

function collect(prepare, count, kind) {
	const operation = prepare();
	const run = () => {
		const countPerSample = repetitions(count, kind);
		globalThis.gc?.();
		const started = process.hrtime.bigint();
		for (let index = 0; index < countPerSample; index += 1) operation();
		const elapsed = Number(process.hrtime.bigint() - started) / 1000;
		return elapsed / countPerSample;
	};
	for (let index = 0; index < warmups; index += 1) run();
	return statistics(Array.from({ length: samples }, run));
}

function regressionExponent(points) {
	const pairs = points
		.filter((point) => point.n > 0 && point.median_us > 0)
		.map((point) => [Math.log(point.n), Math.log(point.median_us)]);
	const meanX = pairs.reduce((total, pair) => total + pair[0], 0) / pairs.length;
	const meanY = pairs.reduce((total, pair) => total + pair[1], 0) / pairs.length;
	const numerator = pairs.reduce(
		(total, pair) => total + (pair[0] - meanX) * (pair[1] - meanY),
		0,
	);
	const denominator = pairs.reduce(
		(total, pair) => total + (pair[0] - meanX) ** 2,
		0,
	);
	return numerator / denominator;
}

function metric(points) {
	const exponent = regressionExponent(points);
	return {
		points,
		scaling: {
			log_log_exponent: exponent,
			classification: exponent < 0.35 ? "constant" : exponent < 1.5 ? "linear" : "quadratic-or-worse",
		},
	};
}

const framePoints = [];
const keyPoints = [];
const streamPoints = [];
const appendPoints = [];

for (const count of entryCounts) {
	process.stderr.write(`goal11 pi baseline: N=${count} frame/key/stream/append\n`);
	framePoints.push({
		n: count,
		...collect(() => {
			const fixture = makeFixture(count);
			return () => fixture.ui.doRender();
		}, count, "frame"),
	});
	keyPoints.push({
		n: count,
		...collect(() => {
			const fixture = makeFixture(count);
			return () => {
				fixture.editor.handleInput("x");
				fixture.ui.doRender();
				fixture.editor.handleInput("\x7f");
			};
		}, count, "key"),
	});
	streamPoints.push({
		n: count,
		...collect(() => {
			const fixture = makeFixture(count, true);
			let toggle = false;
			return () => {
				toggle = !toggle;
				fixture.stream.updateContent(
					assistantMessage(toggle ? "stream delta" : "stream delta next"),
					true,
				);
				fixture.ui.doRender();
			};
		}, count, "stream"),
	});
	appendPoints.push({
		n: count,
		...collect(() => {
			const fixture = makeFixture(count);
			const entry = makeEntry(count, fixture.ui);
			return () => {
				fixture.chat.addChild(entry);
				fixture.chat.children.pop();
			};
		}, count, "append"),
	});
}

const result = {
	schema_version: 1,
	kind: "pi-goal11-structural-baseline",
	provenance: {
		source_revision: revision,
		tui_object_id: execFileSync(
			"git",
			["-C", baselineDirectory, "rev-parse", `${revision}:packages/tui/src/tui.ts`],
			{ encoding: "utf8" },
		).trim(),
		interactive_mode_object_id: execFileSync(
			"git",
			[
				"-C",
				baselineDirectory,
				"rev-parse",
				`${revision}:packages/coding-agent/src/modes/interactive/interactive-mode.ts`,
			],
			{ encoding: "utf8" },
		).trim(),
	},
	parameters: {
		width,
		height,
		entry_counts: entryCounts,
		warmups,
		samples,
		note: "Production TuiMainScreen, Editor, message, read-tool, and bash-tool components; every history entry is a distinct production component and fixture construction is outside timed samples.",
	},
	metrics: {
		frame_render: metric(framePoints),
		key_to_frame: metric(keyPoints),
		stream_delta_to_frame: metric(streamPoints),
		append_entry: metric(appendPoints),
	},
};

process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
