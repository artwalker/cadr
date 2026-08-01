#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readdirSync, readFileSync } from "node:fs";
import { Session } from "node:inspector";
import { arch, hostname, platform } from "node:os";
import { pathToFileURL } from "node:url";
import path from "node:path";

const quick = process.argv.includes("--quick");
const entryCounts = quick ? [0, 50, 200] : [0, 50, 200, 1000, 5000];
const samples = quick ? 1 : 5;
const warmups = quick ? 0 : 1;
let continuousEvents = 1024;
if (quick) continuousEvents = 12;
const width = 100;
const height = 40;

const baselineDirectory = process.argv.find(
	(argument, index) => index > 1 && argument !== "--quick",
);
if (!baselineDirectory) {
	throw new Error("usage: goal11-pi-baseline-bench.mjs BASELINE_WORKTREE [--quick]");
}
if (!globalThis.gc) {
	throw new Error("run with node --expose-gc");
}

const revision = execFileSync("git", ["-C", baselineDirectory, "rev-parse", "HEAD"], {
	encoding: "utf8",
}).trim();
if (revision !== "74caa2649f10ed71b4378ce69f5d9fbfd2466ca5") {
	throw new Error(`expected baseline 74caa2649, got ${revision}`);
}
const trackedStatus = execFileSync(
	"git",
	["-C", baselineDirectory, "status", "--porcelain", "--untracked-files=no"],
	{ encoding: "utf8" },
).trim();
if (trackedStatus) throw new Error("fixed baseline has tracked worktree changes");
const installedDependencyTree = execFileSync(
	"npm",
	["ls", "--all", "--json", "--ignore-scripts"],
	{ cwd: baselineDirectory, encoding: "utf8" },
);

function directorySha256(relativeDirectory) {
	const root = path.join(baselineDirectory, relativeDirectory);
	const files = [];
	const visit = (directory, prefix = "") => {
		for (const entry of readdirSync(directory, { withFileTypes: true })) {
			const relativePath = path.posix.join(prefix, entry.name);
			const absolutePath = path.join(directory, entry.name);
			if (entry.isDirectory()) visit(absolutePath, relativePath);
			else if (entry.isFile()) files.push([relativePath, absolutePath]);
		}
	};
	visit(root);
	const digest = createHash("sha256");
	for (const [relativePath, absolutePath] of files.sort(([left], [right]) => left.localeCompare(right))) {
		digest.update(relativePath);
		digest.update("\0");
		digest.update(readFileSync(absolutePath));
		digest.update("\0");
	}
	return digest.digest("hex");
}

const moduleUrl = (relativePath) =>
	pathToFileURL(path.join(baselineDirectory, relativePath)).href;

const { Container, Editor } = await import(moduleUrl("packages/tui/dist/index.js"));
const { TuiAltScreen } = await import(moduleUrl("packages/tui/dist/TuiAltScreen.js"));
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
	inputHandler;
	resizeHandler;
	kittyProtocolActive = false;

	write(data) {
		this.writtenBytes += data.length;
	}

	start(onInput, onResize) {
		this.inputHandler = onInput;
		this.resizeHandler = onResize;
	}

	stop() {
		this.inputHandler = undefined;
		this.resizeHandler = undefined;
	}

	emitInput(data) {
		if (!this.inputHandler) throw new Error("benchmark terminal is not started");
		this.inputHandler(data);
	}

	async drainInput() {}
	showCursor() {}
	hideCursor() {}
	setTitle() {}
	clearScreen() {}
	moveCursor() {}
	moveBy() {}
	clearLine() {}
	clearFromCursor() {}
	setProgress() {}
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
			assistantMessage(
				`Entry ${index} keeps markdown, \`inline code\`, and a wrapped paragraph stable across frames.`,
			),
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

function clearScheduledRender(ui) {
	if (ui.renderTimer) clearTimeout(ui.renderTimer);
	ui.renderTimer = undefined;
	ui.renderRequested = false;
}

function renderAltFixture(fixture) {
	clearScheduledRender(fixture.ui);
	fixture.ui.doRender();
	clearScheduledRender(fixture.ui);
}

function sgrMouseInput(button, x, y) {
	return `\x1b[<${button};${x};${y}M`;
}

function continuousEventInput(index) {
	if (index % 3 === 0) {
		return sgrMouseInput(32, index % 2 === 0 ? 20 : 70, index % 2 === 0 ? 8 : 30);
	}
	return sgrMouseInput(index % 3 === 1 ? 64 : 65, 50, 20);
}

const continuousTrace = Array.from({ length: continuousEvents }, (_, index) =>
	continuousEventInput(index),
);
const eventTraceSha256 = createHash("sha256").update(continuousTrace.join("\n")).digest("hex");
const eventTraceCounts = continuousTrace.reduce(
	(counts, _event, index) => {
		counts[index % 3 === 0 ? "drag" : index % 3 === 1 ? "wheel_up" : "wheel_down"] += 1;
		return counts;
	},
	{ drag: 0, wheel_up: 0, wheel_down: 0 },
);

function makeAltFixture(count) {
	const terminal = new BenchmarkTerminal();
	const ui = new TuiAltScreen(terminal);
	const chat = new Container();
	for (let index = 0; index < count; index += 1) {
		chat.addChild(makeEntry(index, ui));
	}
	const editor = new Editor(ui, getEditorTheme());
	ui.addChild(chat);
	ui.addChild(editor);
	ui.start();
	renderAltFixture({ ui });
	ui.scrollToTop();
	ui.scrollBy(Math.floor(Math.max(0, ui.contentLineCount - height) / 2));
	renderAltFixture({ ui });
	terminal.emitInput(sgrMouseInput(0, 10, 10));
	renderAltFixture({ ui });
	return { chat, editor, terminal, ui };
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

function interactiveStatistics(timeValues, heapValues) {
	return {
		...statistics(timeValues),
		median_retained_heap_delta_bytes: median(heapValues),
		samples_retained_heap_delta_bytes: heapValues,
	};
}

function repetitions(count, kind) {
	if (kind === "append") return count <= 200 ? 100000 : count <= 1000 ? 30000 : 10000;
	if (kind === "interactive") return count <= 200 ? 10 : count <= 1000 ? 3 : 1;
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

function collectInteractive(prepare, count) {
	const countPerSample = repetitions(count, "interactive");
	const run = () => {
		const fixture = prepare();
		globalThis.gc();
		const heapBefore = process.memoryUsage().heapUsed;
		const started = process.hrtime.bigint();
		for (let index = 0; index < countPerSample; index += 1) {
			fixture.operation(index);
		}
		const elapsed = Number(process.hrtime.bigint() - started) / 1000;
		const heapAfter = process.memoryUsage().heapUsed;
		fixture.dispose();
		return {
			time: elapsed / countPerSample,
			heap: Math.max(0, heapAfter - heapBefore) / countPerSample,
		};
	};
	for (let index = 0; index < warmups; index += 1) run();
	const results = Array.from({ length: samples }, run);
	return interactiveStatistics(
		results.map((result) => result.time),
		results.map((result) => result.heap),
	);
}

function percentile(values, fraction) {
	const sorted = [...values].sort((a, b) => a - b);
	return sorted[Math.max(0, Math.min(sorted.length - 1, Math.ceil(fraction * sorted.length) - 1))];
}

const drainRequestedRender = () => new Promise((resolve) => process.nextTick(resolve));

async function continuousAltInputRun() {
	const fixture = makeAltFixture(5000);
	const samplesUs = [];
	const samplesHeapDeltaBytes = [];
	globalThis.gc();
	const heapBefore = process.memoryUsage().heapUsed;
	let heapHighWater = heapBefore;
	const initialViewportTop = fixture.ui.viewportTop;
	let renderedFrameCount = 0;
	for (const input of continuousTrace) {
		const eventHeapBefore = process.memoryUsage().heapUsed;
		const started = process.hrtime.bigint();
		fixture.terminal.emitInput(input);
		renderAltFixture(fixture);
		renderedFrameCount += 1;
		samplesUs.push(Number(process.hrtime.bigint() - started) / 1000);
		const eventHeapAfter = process.memoryUsage().heapUsed;
		samplesHeapDeltaBytes.push(Math.max(0, eventHeapAfter - eventHeapBefore));
		heapHighWater = Math.max(heapHighWater, eventHeapAfter);
		await drainRequestedRender();
	}
	const heapAfter = process.memoryUsage().heapUsed;
	const finalViewportTop = fixture.ui.viewportTop;
	const finalSelectionActive = fixture.ui.selectionAnchor !== undefined;
	fixture.ui.stop();
	return {
		event_count: samplesUs.length,
		median_us: median(samplesUs),
		p95_us: percentile(samplesUs, 0.95),
		p99_us: percentile(samplesUs, 0.99),
		max_us: Math.max(...samplesUs),
		median_retained_heap_delta_bytes: median(samplesHeapDeltaBytes),
		retained_heap_delta_bytes_per_event:
			Math.max(0, heapAfter - heapBefore) / continuousEvents,
		retained_heap_high_water_delta_bytes_per_event:
			Math.max(0, heapHighWater - heapBefore) / continuousEvents,
		event_trace_sha256: eventTraceSha256,
		event_trace_counts: eventTraceCounts,
		terminal_sink: "count-only",
		gc_mode: "runtime-default",
		renderer_mode: "synchronous-requested-frame",
		scheduler_mode: "production-request-immediate-flush",
		rendered_frame_count: renderedFrameCount,
		initial_viewport_top: initialViewportTop,
		final_viewport_top: finalViewportTop,
		final_selection_active: finalSelectionActive,
		samples_us: samplesUs,
		samples_retained_heap_delta_bytes: samplesHeapDeltaBytes,
	};
}

async function continuousAltInput() {
	const runs = [];
	for (let index = 0; index < samples; index += 1) {
		runs.push(await continuousAltInputRun());
	}
	const aggregate = {};
	for (const field of ["median", "p95", "p99"]) {
		const values = runs.map((run) => run[`${field}_us`]);
		aggregate[`${field}_us`] = median(values);
		aggregate[`${field}_run_mad_us`] = median(
			values.map((value) => Math.abs(value - aggregate[`${field}_us`])),
		);
	}
	return {
		...aggregate,
		event_count: continuousEvents,
		max_us: Math.max(...runs.map((run) => run.max_us)),
		median_retained_heap_delta_bytes: median(
			runs.map((run) => run.median_retained_heap_delta_bytes),
		),
		retained_heap_delta_bytes_per_event: median(
			runs.map((run) => run.retained_heap_delta_bytes_per_event),
		),
		retained_heap_high_water_delta_bytes_per_event: median(
			runs.map((run) => run.retained_heap_high_water_delta_bytes_per_event),
		),
		event_trace_sha256: eventTraceSha256,
		event_trace_counts: eventTraceCounts,
		terminal_sink: "count-only",
		gc_mode: "runtime-default",
		renderer_mode: "synchronous-requested-frame",
		scheduler_mode: "production-request-immediate-flush",
		rendered_frame_count: continuousEvents,
		final_selection_active: runs.every((run) => run.final_selection_active),
		runs,
	};
}

function inspectorPost(session, method, parameters = {}) {
	return new Promise((resolve, reject) => {
		session.post(method, parameters, (error, result) => {
			if (error) reject(error);
			else resolve(result);
		});
	});
}

function sampledProfileBytes(node) {
	return node.selfSize + node.children.reduce(
		(total, child) => total + sampledProfileBytes(child),
		0,
	);
}

async function continuousSampledAllocation() {
	const session = new Session();
	const fixture = makeAltFixture(5000);
	const allocationTrace = continuousTrace.slice(0, Math.min(96, continuousTrace.length));
	session.connect();
	try {
		globalThis.gc();
		await inspectorPost(session, "HeapProfiler.enable");
		await inspectorPost(session, "HeapProfiler.startSampling", {
			samplingInterval: 32768,
			includeObjectsCollectedByMajorGC: true,
			includeObjectsCollectedByMinorGC: true,
		});
		for (const input of allocationTrace) {
			fixture.terminal.emitInput(input);
			renderAltFixture(fixture);
			await drainRequestedRender();
		}
		const { profile } = await inspectorPost(session, "HeapProfiler.stopSampling");
		return {
			bytesPerEvent: sampledProfileBytes(profile.head) / allocationTrace.length,
			eventCount: allocationTrace.length,
		};
	} finally {
		fixture.ui.stop();
		session.disconnect();
	}
}

async function sampledInteractiveAllocation(kind) {
	const session = new Session();
	const fixture = makeAltFixture(5000);
	const eventCount = 32;
	session.connect();
	try {
		globalThis.gc();
		await inspectorPost(session, "HeapProfiler.enable");
		await inspectorPost(session, "HeapProfiler.startSampling", {
			samplingInterval: 32768,
			includeObjectsCollectedByMajorGC: true,
			includeObjectsCollectedByMinorGC: true,
		});
		for (let index = 0; index < eventCount; index += 1) {
			const input =
				kind === "mouse"
					? sgrMouseInput(32, index % 2 === 0 ? 20 : 70, index % 2 === 0 ? 8 : 30)
					: sgrMouseInput(index % 2 === 0 ? 64 : 65, 50, 20);
			fixture.terminal.emitInput(input);
			renderAltFixture(fixture);
			await drainRequestedRender();
		}
		const { profile } = await inspectorPost(session, "HeapProfiler.stopSampling");
		return {
			bytesPerEvent: sampledProfileBytes(profile.head) / eventCount,
			eventCount,
		};
	} finally {
		fixture.ui.stop();
		session.disconnect();
	}
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
const mousePoints = [];
const wheelPoints = [];
const appendPoints = [];

for (const count of entryCounts) {
	process.stderr.write(`goal11 pi baseline: N=${count} frame/key/stream/mouse/wheel/append\n`);
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
	mousePoints.push({
		n: count,
		...collectInteractive(() => {
			const fixture = makeAltFixture(count);
			let eventIndex = 0;
			return {
				operation: () => {
					eventIndex += 1;
					fixture.terminal.emitInput(
						sgrMouseInput(32, eventIndex % 2 === 1 ? 20 : 70, eventIndex % 2 === 1 ? 8 : 30),
					);
					renderAltFixture(fixture);
				},
				dispose: () => fixture.ui.stop(),
			};
		}, count),
	});
	wheelPoints.push({
		n: count,
		...collectInteractive(() => {
			const fixture = makeAltFixture(count);
			let eventIndex = 0;
			return {
				operation: () => {
					eventIndex += 1;
					fixture.terminal.emitInput(sgrMouseInput(eventIndex % 2 === 1 ? 64 : 65, 50, 20));
					renderAltFixture(fixture);
				},
				dispose: () => fixture.ui.stop(),
			};
		}, count),
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

process.stderr.write(`goal11 pi baseline: N=5000 continuous ${continuousEvents} events\n`);
await drainRequestedRender();
const continuousInput = await continuousAltInput();
const continuousAllocation = await continuousSampledAllocation();
continuousInput.sampled_allocated_bytes_per_event = continuousAllocation.bytesPerEvent;
continuousInput.allocation_sample_event_count = continuousAllocation.eventCount;
continuousInput.allocation_sampling_interval_bytes = 32768;
for (const [kind, points] of [
	["mouse", mousePoints],
	["wheel", wheelPoints],
]) {
	const point = points.find((candidate) => candidate.n === 5000);
	if (point) {
		const allocation = await sampledInteractiveAllocation(kind);
		point.sampled_allocated_bytes_per_event = allocation.bytesPerEvent;
		point.allocation_sample_event_count = allocation.eventCount;
		point.allocation_sampling_interval_bytes = 32768;
	}
}

const result = {
	schema_version: 2,
	kind: "pi-goal11-structural-baseline",
	provenance: {
		source_revision: revision,
		tracked_worktree_clean: true,
		package_lock_object_id: execFileSync(
			"git",
			["-C", baselineDirectory, "rev-parse", `${revision}:package-lock.json`],
			{ encoding: "utf8" },
		).trim(),
		installed_dependency_tree_sha256: createHash("sha256")
			.update(installedDependencyTree)
			.digest("hex"),
		loaded_dist_tree_sha256: {
			tui: directorySha256("packages/tui/dist"),
			ai: directorySha256("packages/ai/dist"),
			agent: directorySha256("packages/agent/dist"),
			coding_agent: directorySha256("packages/coding-agent/dist"),
		},
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
		alt_screen_object_id: execFileSync(
			"git",
			["-C", baselineDirectory, "rev-parse", `${revision}:packages/tui/src/TuiAltScreen.ts`],
			{ encoding: "utf8" },
		).trim(),
	},
	parameters: {
		width,
		height,
		entry_counts: entryCounts,
		warmups,
		samples,
		continuous_events: continuousEvents,
		paired_fresh_fixture_per_run: true,
		note: "Production TuiMainScreen/TuiAltScreen, raw SGR input listener, production render request, Editor, message, read-tool, and bash-tool components. Mouse/wheel timing immediately flushes each requested frame in both runtimes with a count-only sink, excluding only the 16ms wait. V8 heap deltas are retained-heap proxies, not allocation counts or runtime-identical byte values.",
	},
	machine: {
		arch: arch(),
		hostname: hostname(),
		node_version: process.version,
		platform: platform(),
	},
	metrics: {
		frame_render: metric(framePoints),
		key_to_frame: metric(keyPoints),
		stream_delta_to_frame: metric(streamPoints),
		mouse_drag_to_frame: metric(mousePoints),
		wheel_to_frame: metric(wheelPoints),
		append_entry: metric(appendPoints),
	},
	continuous_alt_input: continuousInput,
};

process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
