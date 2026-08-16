import { Container, Markdown, SelectList, SettingsList, Text } from "@earendil-works/pi-tui";
import {
	chmodSync,
	mkdirSync,
	mkdtempSync,
	readFileSync,
	symlinkSync,
	unlinkSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { FirstTimeSetupComponent } from "../src/modes/interactive/components/first-time-setup.ts";
import { LoginDialogComponent } from "../src/modes/interactive/components/login-dialog.ts";
import { ModelSelectorComponent } from "../src/modes/interactive/components/model-selector.ts";
import { OAuthSelectorComponent } from "../src/modes/interactive/components/oauth-selector.ts";
import { CompactionSummaryMessageComponent } from "../src/modes/interactive/components/compaction-summary-message.ts";
import { BranchSummaryMessageComponent } from "../src/modes/interactive/components/branch-summary-message.ts";
import { CustomEntryComponent } from "../src/modes/interactive/components/custom-entry.ts";
import { CustomMessageComponent } from "../src/modes/interactive/components/custom-message.ts";
import { ExtensionInputComponent } from "../src/modes/interactive/components/extension-input.ts";
import { ExtensionSelectorComponent } from "../src/modes/interactive/components/extension-selector.ts";
import { ScopedModelsSelectorComponent } from "../src/modes/interactive/components/scoped-models-selector.ts";
import { SkillInvocationMessageComponent } from "../src/modes/interactive/components/skill-invocation-message.ts";
import { AssistantMessageComponent } from "../src/modes/interactive/components/assistant-message.ts";
import { initTheme, theme } from "../src/modes/interactive/theme/theme.ts";
import { createEventBus } from "../src/core/event-bus.ts";
import { formatMissingSessionCwdPrompt, MissingSessionCwdError } from "../src/core/session-cwd.ts";
import { printTimings, resetTimings, time } from "../src/core/timings.ts";
import { listModels } from "../src/cli/list-models.ts";
import { InteractiveMode } from "../src/modes/interactive/interactive-mode.ts";
import { EarendilAnnouncementComponent } from "../src/modes/interactive/components/earendil-announcement.ts";
import { restoreModelFromSession } from "../src/core/model-resolver.ts";
import { getChangelogPath, getSelfUpdateUnavailableInstruction } from "../src/config.ts";
import { InteractiveThemeController } from "../src/modes/interactive/theme/theme-controller.ts";
import { runPrintMode } from "../src/modes/print-mode.ts";
import { showLlamaUi } from "../src/extensions/llama/ui.ts";
import { handleConfigCommand, handlePackageCommand } from "../src/package-manager-cli.ts";
import { printAuthCommandHelp } from "../src/cli/auth-command.ts";
import { createGrepToolDefinition } from "../src/core/tools/grep.ts";
import { showDeprecationWarnings } from "../src/migrations.ts";
import { runMigrations } from "../src/migrations.ts";
import { warnDeprecation } from "../src/utils/deprecation.ts";
import { processFileArguments } from "../src/cli/file-processor.ts";
import { ExtensionRunner } from "../src/core/extensions/runner.ts";
import { DefaultResourceLoader } from "../src/core/resource-loader.ts";
import { createRequire } from "node:module";
import { parseChangelog } from "../src/utils/changelog.ts";
import { ensureTool } from "../src/utils/tools-manager.ts";
import llamaExtension from "../src/extensions/llama/index.ts";
import { formatNoModelsAvailableMessage } from "../src/core/auth-guidance.ts";
import { editInExternalEditor } from "../src/modes/interactive/external-editor.ts";
import { SessionImportFileNotFoundError } from "../src/core/agent-session-runtime.ts";

initTheme("dark", false);

const tui = {
	requestRender() {},
};

const model = {
	id: "model-one",
	name: "Model One",
	provider: "provider-one",
	reasoning: true,
	input: ["text"],
	cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
	contextWindow: 1000,
	maxTokens: 100,
};

const setup = new FirstTimeSetupComponent({
	detectedTheme: "dark",
	onThemePreview() {},
	onSubmit() {},
	onCancel() {},
});
setup.handleInput("\r");

const modelRuntime = {
	getAvailableSnapshot: () => [model],
	getAvailable: async () => [],
	getModel: () => model,
	getError: () => undefined,
	refresh: async () => ({ errors: new Map(), aborted: false }),
};
const modelSelector = new ModelSelectorComponent(
	tui,
	model,
	{ setDefaultModelAndProvider() {} },
	modelRuntime,
	[{ model, thinkingLevel: "high" }],
	() => {},
	() => {},
);
(modelSelector as any).errorMessage = "catalog failure";
(modelSelector as any).updateList();

const originalPlatform = Object.getOwnPropertyDescriptor(process, "platform");
Object.defineProperty(process, "platform", { value: "darwin" });
const login = new LoginDialogComponent(tui, "provider", () => {});
login.showDeviceCode({ verificationUri: "https://example.invalid/device", userCode: "CODE" });
login.showManualInput("Paste code");
login.showInfo("Information", [], true);
login.showPrompt("Paste the authorization code", "code-from-browser");
login.showInfo("Complete", [{ label: "Docs", url: "https://example.invalid/docs" }], true);
login.showDetails([
	"You can also use an AWS profile, IAM keys, or role-based credentials.",
	"See:",
	"  providers.md",
]);
if (originalPlatform) Object.defineProperty(process, "platform", originalPlatform);

new OAuthSelectorComponent("login", [], () => {}, () => {});
new OAuthSelectorComponent("logout", [], () => {}, () => {});
const filteredOAuth = new OAuthSelectorComponent(
	"login",
	[{ id: "provider", name: "Provider", authType: "oauth" }],
	() => {},
	() => {},
);
filteredOAuth.handleInput("z");
new OAuthSelectorComponent(
	"login",
	[
		{ id: "mismatch", name: "Mismatch", authType: "api_key", status: { type: "oauth" } },
		{ id: "env", name: "Env", authType: "oauth", status: { type: "oauth", source: "KIMI_API_KEY" } },
	],
	() => {},
	() => {},
);

const compaction = new CompactionSummaryMessageComponent({
	role: "compactionSummary",
	summary: "summary",
	tokensBefore: 1234,
	firstKeptEntryId: "entry",
	timestamp: 0,
});
compaction.setExpanded(true);
const branch = new BranchSummaryMessageComponent({
	role: "branchSummary",
	summary: "summary",
	timestamp: 0,
});
branch.setExpanded(true);

new CustomEntryComponent(
	{
		type: "custom",
		id: "entry",
		parentId: null,
		timestamp: "2026-01-01T00:00:00.000Z",
		customType: "broken",
		data: {},
	},
	() => {
		throw new Error("failure");
	},
);
new CustomMessageComponent({
	role: "custom",
	customType: "notice",
	content: "content",
	display: true,
	timestamp: 0,
});

const countdownTui = { requestRender() {} };
const extensionInput = new ExtensionInputComponent("Input", undefined, () => {}, () => {}, {
	tui: countdownTui,
	timeout: 2,
});
extensionInput.dispose();
const extensionSelector = new ExtensionSelectorComponent("Select", ["one"], () => {}, () => {}, {
	tui: countdownTui,
	timeout: 2,
});
extensionSelector.dispose();

new ScopedModelsSelectorComponent(
	{ allModels: [model], enabledModelIds: null },
	{ onChange() {}, onPersist() {}, onCancel() {} },
);
const skill = new SkillInvocationMessageComponent({ name: "skill", content: "body" });
skill.setExpanded(true);
new AssistantMessageComponent({
	role: "assistant",
	content: [],
	api: "responses",
	provider: "provider",
	model: "model",
	usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
	stopReason: "error",
	timestamp: 0,
});
new AssistantMessageComponent({
	role: "assistant",
	content: [],
	api: "responses",
	provider: "provider",
	model: "model",
	usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
	stopReason: "length",
	timestamp: 0,
});
formatNoModelsAvailableMessage();
await editInExternalEditor({ command: "true", content: "draft" });

const noMatchList = new SelectList(
	[{ value: "one", label: "One" }],
	1,
	{
		selectedPrefix: (value) => value,
		selectedText: (value) => value,
		description: (value) => value,
		scrollInfo: (value) => value,
		noMatch: (value) => value,
	},
);
noMatchList.setFilter("missing");
noMatchList.render(80);
const selectList = new SelectList(
	Array.from({ length: 6 }, (_, index) => ({ value: `${index}`, label: `${index}` })),
	2,
	{
		selectedPrefix: (value) => value,
		selectedText: (value) => value,
		description: (value) => value,
		scrollInfo: (value) => value,
		noMatch: (value) => value,
	},
);
selectList.setSelectedIndex(5);
selectList.render(80);
selectList.setSelectedIndex(0);
selectList.render(80);
(selectList as any).renderItem(
	{ value: "selected", label: "Selected" },
	true,
	80,
	undefined,
	40,
);
new SettingsList(
	[],
	5,
	{
		label: (value) => value,
		value: (value) => value,
		description: (value) => value,
		cursor: ">",
		hint: (value) => value,
	},
	() => {},
	() => {},
).render(80);
new Markdown("> quote", 0, 0, {
	heading: (value) => value,
	link: (value) => value,
	linkUrl: (value) => value,
	code: (value) => value,
	codeBlock: (value) => value,
	codeBlockBorder: (value) => value,
	quote: (value) => value,
	quoteBorder: (value) => value,
	hr: (value) => value,
	listBullet: (value) => value,
	bold: (value) => value,
	italic: (value) => value,
	strikethrough: (value) => value,
	underline: (value) => value,
}).render(80);

formatMissingSessionCwdPrompt({ sessionCwd: "/missing", fallbackCwd: "/current" });
const eventBus = createEventBus();
eventBus.on("event", () => {
	throw new Error("handler");
});
eventBus.emit("event", { type: "event" });
await new Promise((resolve) => setTimeout(resolve, 0));

resetTimings();
time("start");
time("finish");
printTimings();

await listModels(
	{
		getAvailable: async () => [model],
		getError: () => undefined,
	},
	"missing",
);
getSelfUpdateUnavailableInstruction("@earendil-works/pi-coding-agent");
await restoreModelFromSession("provider-one", "model-one", undefined, true, {
	getModel: () => model,
	hasConfiguredAuth: () => true,
	getAvailableSnapshot: () => [model],
});
await restoreModelFromSession("missing", "missing", model, true, {
	getModel: () => undefined,
	hasConfiguredAuth: () => false,
	getAvailableSnapshot: () => [model],
});
await restoreModelFromSession("missing", "missing", undefined, true, {
	getModel: () => undefined,
	hasConfiguredAuth: () => false,
	getAvailableSnapshot: () => [model],
});
await restoreModelFromSession("provider-one", "model-one", undefined, true, {
	getModel: () => model,
	hasConfiguredAuth: () => false,
	getAvailableSnapshot: () => [model],
});

const controller = new InteractiveThemeController(
	{
		onTerminalColorSchemeChange() {},
		setTerminalColorSchemeNotifications() {},
		invalidate() {},
		requestRender() {},
	},
	{
		getSettingsManager: () => ({ getThemeSetting: () => "dark" }) as any,
		showError: () => {},
		onChanged: () => {},
	},
);
controller.setThemeName("missing-goal17-theme", true);

await showLlamaUi(
	{
		ui: {
			custom: async (factory) => {
				await new Promise<void>((resolve) => {
					let view: any;
					view = factory(
						{ requestRender() {} },
						theme,
						{ matches: () => false },
						() => {
							view.render(80);
							resolve();
						},
					);
					view.render(80);
				});
			},
			notify() {},
		},
	},
	async (ui) => {
		const modelChoice = ui.showModels("http://127.0.0.1:8080", [{
			id: "owner/model",
			status: { value: "loaded", args: [] },
			meta: { n_ctx: 8192 },
		}]);
		(ui as any).content.render(80);
		(ui as any).inputHandler.onCancel();
		await modelChoice;

		const searchChoice = ui.searchModels(async () => [{ id: "owner/model", downloads: 1234 }]);
		const search = (ui as any).inputTarget;
		search.results = Array.from({ length: 12 }, (_, index) => ({
			id: `owner/model-${index}`,
			downloads: 1234 + index,
		}));
		search.filteredResults = search.results;
		search.updateResults();
		(ui as any).content.render(80);
		search.close(undefined);
		await searchChoice;

		const progress = ui.progress({ title: "Download", model: "owner/model", message: "downloading", ratio: 0.5 });
		ui.updateProgress({ title: "Download", model: "owner/model", message: "downloading", ratio: 0.5 });
		(ui as any).content.render(80);
		(ui as any).progressResolver();
		await progress;
	},
);

let llamaCommand: any;
llamaExtension({
	registerProvider() {},
	registerCommand(name: string, command: any) {
		if (name === "llama") llamaCommand = command;
	},
} as any);
const llamaFetch = globalThis.fetch;
globalThis.fetch = async (input) => {
	const url = String(input);
	if (url === "http://llama.test/models") {
		return new Response(JSON.stringify({ data: [] }), { status: 200 });
	}
	if (url === "https://huggingface.co/api/models/owner/model?blobs=true") {
		return new Response(JSON.stringify({ error: "fixture details failure" }), { status: 500 });
	}
	throw new Error(`unexpected llama construction request: ${url}`);
};
const waitForLlamaState = async (predicate: () => boolean): Promise<void> => {
	for (let index = 0; index < 100; index++) {
		if (predicate()) return;
		await new Promise((resolve) => setImmediate(resolve));
	}
	throw new Error("llama construction state did not settle");
};
await llamaCommand.handler("", {
	mode: "tui",
		modelRegistry: {
			getProviderAuth: async () => ({
				auth: { baseUrl: "http://llama.test/v1" },
				env: { LLAMA_BASE_URL: "http://llama.test" },
			}),
			refresh: async () => ({ aborted: false, errors: new Map() }),
		},
	ui: {
		notify() {},
		custom: async (factory: any) => new Promise<void>((resolve, reject) => {
			const view = factory(
				{ requestRender() {} },
				theme,
				{ matches: () => false },
				resolve,
			);
			void (async () => {
				await waitForLlamaState(() => (view as any).inputHandler?.constructor.name === "SelectList");
				const modelList = (view as any).inputHandler;
				const download = modelList.items.find((item: any) => item.label === "Download model…");
				modelList.onSelect(download);
				await waitForLlamaState(() => (view as any).inputTarget?.constructor.name === "HuggingFaceSearch");
				const search = (view as any).inputTarget;
				search.close("owner/model");
				await waitForLlamaState(() =>
					(view as any).inputHandler?.constructor.name === "SelectList" &&
					(view as any).inputHandler !== modelList,
				);
				(view as any).inputHandler.onCancel();
			})().catch(reject);
		}),
	},
});
globalThis.fetch = llamaFetch;

await runPrintMode(
	{
		session: {
			sessionManager: { getHeader: () => undefined },
			bindExtensions: async ({ onError }) => {
				onError({ extensionPath: "/tmp/ext.ts", error: "failure" });
			},
			subscribe: () => () => {},
			state: {
				messages: [{ role: "assistant", content: [], stopReason: "aborted", timestamp: 0 }],
			},
		},
		setRebindSession() {},
		dispose: async () => {},
	},
	{ mode: "text" },
);

await handleConfigCommand(["config", "--invalid"]);
process.exitCode = 0;
await handlePackageCommand(["update", "--self", "--extensions"]);
process.exitCode = 0;
await handlePackageCommand(["update", "--models"]);
process.exitCode = 0;

printAuthCommandHelp();
createGrepToolDefinition("/tmp").renderResult(
	{
		content: [{ type: "text", text: "long line" }],
		details: { linesTruncated: true },
	},
	{ expanded: false },
	theme,
	{ showImages: false },
);

const migrationPromise = showDeprecationWarnings(["legacy extension directory"]);
process.stdin.emit("data", Buffer.from("x"));
await migrationPromise;
warnDeprecation("render drive");

const invalidChangelog = mkdtempSync(join(tmpdir(), "pi-visible-invalid-changelog-"));
parseChangelog(invalidChangelog);

const packageProject = mkdtempSync(join(tmpdir(), "pi-visible-packages-"));
const packageAgent = join(packageProject, "agent");
mkdirSync(packageAgent, { recursive: true });
mkdirSync(join(packageAgent, "npm", "node_modules", "plain-package"), { recursive: true });
writeFileSync(
	join(packageAgent, "npm", "node_modules", "plain-package", "package.json"),
	JSON.stringify({ name: "plain-package", version: "1.0.0" }),
);
writeFileSync(
	join(packageAgent, "settings.json"),
	JSON.stringify({
		packages: [
			"npm:plain-package",
			{ source: "npm:filtered-package", extensions: ["extensions/index.ts"] },
		],
	}),
);
const previousAgentDir = process.env.PI_CODING_AGENT_DIR;
const previousCwd = process.cwd();
const packageOffline = process.env.PI_OFFLINE;
delete process.env.PI_OFFLINE;
process.env.PI_CODING_AGENT_DIR = packageAgent;
process.chdir(packageProject);
await handlePackageCommand(["list", "--no-approve"]);
await handleConfigCommand(["config", "bogus"]);
const packageSettingsPath = join(packageAgent, "settings.json");
const packageSettingsBefore = readFileSync(packageSettingsPath, "utf-8");
writeFileSync(packageSettingsPath, JSON.stringify({ packages: [] }));
await handlePackageCommand(["list", "--no-approve"]);
writeFileSync(packageSettingsPath, packageSettingsBefore);
const projectExtension = join(packageProject, "ext-local");
mkdirSync(projectExtension, { recursive: true });
writeFileSync(
	join(projectExtension, "package.json"),
	JSON.stringify({ name: "ext-local", version: "1.0.0" }),
);
mkdirSync(join(packageProject, ".pi"), { recursive: true });
writeFileSync(
	join(packageProject, ".pi", "settings.json"),
	JSON.stringify({ packages: ["./ext-local"] }),
);
await handlePackageCommand(["list", "--approve"]);
await handlePackageCommand(["install", "./ext-local", "--no-approve"]);
process.exitCode = 0;
await handlePackageCommand(["remove", "./ext-local", "--no-approve"]);
process.exitCode = 0;
writeFileSync(packageSettingsPath, "{ corrupt json ");
await handlePackageCommand(["list", "--no-approve"]);
process.exitCode = 0;
writeFileSync(packageSettingsPath, packageSettingsBefore);
await handlePackageCommand(["install", "x", "--bogus"]);
process.exitCode = 0;

const originalFetch = globalThis.fetch;
globalThis.fetch = async () => new Response(JSON.stringify({ version: "0.83.0" }), {
	status: 200,
	headers: { "content-type": "application/json" },
});
await handlePackageCommand(["update"]);
process.exitCode = 0;

globalThis.fetch = async () => new Response(JSON.stringify({ version: "99.0.0" }), {
	status: 200,
	headers: { "content-type": "application/json" },
});
await handlePackageCommand(["update", "--self", "--force"]);
process.exitCode = 0;

const originalPlatformForUpdate = Object.getOwnPropertyDescriptor(process, "platform");
Object.defineProperty(process, "platform", { value: "win32", configurable: true });
await handlePackageCommand(["update", "--self", "--force"]);
process.exitCode = 0;
if (originalPlatformForUpdate) Object.defineProperty(process, "platform", originalPlatformForUpdate);

const originalExecPath = process.execPath;
const originalPackageDir = process.env.PI_PACKAGE_DIR;
const fakeNpmDir = mkdtempSync(join(tmpdir(), "pi-visible-npm-"));
const fakeNpm = join(fakeNpmDir, "npm");
writeFileSync(fakeNpm, "#!/bin/sh\nprintf '%s\\n' /proc/sys\n");
chmodSync(fakeNpm, 0o755);
Object.defineProperty(process, "execPath", { value: "/tmp/npm/node", configurable: true });
process.env.PI_PACKAGE_DIR = packageProject;
getSelfUpdateUnavailableInstruction("@earendil-works/pi-coding-agent", [fakeNpm]);
process.env.PI_PACKAGE_DIR = "/proc/sys/kernel";
getSelfUpdateUnavailableInstruction("@earendil-works/pi-coding-agent", [fakeNpm]);
Object.defineProperty(process, "execPath", { value: originalExecPath, configurable: true });
if (originalPackageDir === undefined) delete process.env.PI_PACKAGE_DIR;
else process.env.PI_PACKAGE_DIR = originalPackageDir;

const selfUpdateNpmDir = mkdtempSync(join(tmpdir(), "pi-visible-selfupdate-"));
const selfUpdateNpm = join(selfUpdateNpmDir, "npm");
writeFileSync(
	selfUpdateNpm,
	`#!/bin/sh
case " $* " in
	*" root "*) printf '%s\\n' "${selfUpdateNpmDir}/global/node_modules" ;;
	*) exit "\${VISIBLE_NPM_FAIL:-0}" ;;
esac
`,
);
chmodSync(selfUpdateNpm, 0o755);
const selfUpdateGlobalRoot = join(selfUpdateNpmDir, "global", "node_modules");
const selfUpdatePackageDir = join(selfUpdateGlobalRoot, "@earendil-works", "pi-coding-agent");
mkdirSync(selfUpdatePackageDir, { recursive: true });
writeFileSync(
	packageSettingsPath,
	JSON.stringify({ packages: [], npmCommand: [selfUpdateNpm] }),
);
Object.defineProperty(process, "execPath", { value: join(selfUpdateNpmDir, "npm", "node"), configurable: true });
process.env.PI_PACKAGE_DIR = selfUpdatePackageDir;
globalThis.fetch = async () => new Response(JSON.stringify({ version: "99.0.0" }), {
	status: 200,
	headers: { "content-type": "application/json" },
});
await handlePackageCommand(["update", "--self", "--force"]);
process.exitCode = 0;
process.env.VISIBLE_NPM_FAIL = "1";
await handlePackageCommand(["update", "--self", "--force"]);
process.exitCode = 0;
delete process.env.VISIBLE_NPM_FAIL;
Object.defineProperty(process, "execPath", { value: originalExecPath, configurable: true });
if (originalPackageDir === undefined) delete process.env.PI_PACKAGE_DIR;
else process.env.PI_PACKAGE_DIR = originalPackageDir;
writeFileSync(packageSettingsPath, packageSettingsBefore);

{
	// package-manager-cli.ts:454 — a release feed note prints the bold
	// "Update note" block before the self-update runs.
	writeFileSync(
		packageSettingsPath,
		JSON.stringify({ packages: [], npmCommand: [selfUpdateNpm] }),
	);
	Object.defineProperty(process, "execPath", {
		value: join(selfUpdateNpmDir, "npm", "node"),
		configurable: true,
	});
	process.env.PI_PACKAGE_DIR = selfUpdatePackageDir;
	globalThis.fetch = async () =>
		new Response(
			JSON.stringify({
				version: "99.0.0",
				note: "Read the changelog before updating.",
			}),
			{ status: 200, headers: { "content-type": "application/json" } },
		);
	await handlePackageCommand(["update", "--self", "--force"]);
	process.exitCode = 0;
	Object.defineProperty(process, "execPath", { value: originalExecPath, configurable: true });
	if (originalPackageDir === undefined) delete process.env.PI_PACKAGE_DIR;
	else process.env.PI_PACKAGE_DIR = originalPackageDir;
	writeFileSync(packageSettingsPath, packageSettingsBefore);
}

{
	// package-manager-cli.ts:443-444 — a failing pnpm install method adds
	// the registry-metadata hints after the update error.
	const fakePnpmDir = mkdtempSync(join(tmpdir(), "pi-visible-pnpm-"));
	const fakePnpm = join(fakePnpmDir, "pnpm");
	// `pnpm root -g` must succeed so the method resolves as a managed
	// global pnpm install; the actual update command fails.
	const fakePnpmRoot = join(fakePnpmDir, "global", "5");
	writeFileSync(
		fakePnpm,
		`#!/bin/sh\ncase " $* " in\n *" root "*) printf '%s\\n' "${fakePnpmRoot}" ;;\n *) exit 1 ;;\nesac\n`,
	);
	chmodSync(fakePnpm, 0o755);
	const fakePnpmPackageDir = join(
		fakePnpmRoot,
		".pnpm",
		"@earendil-works+pi-coding-agent@0.83.0",
		"node_modules",
		"@earendil-works",
		"pi-coding-agent",
	);
	mkdirSync(fakePnpmPackageDir, { recursive: true });
	const savedDrivePath = process.env.PATH;
	process.env.PATH = fakePnpmDir + ":" + (savedDrivePath ?? "");
	Object.defineProperty(process, "execPath", {
		value: join(fakePnpmDir, "pnpm", "node"),
		configurable: true,
	});
	process.env.PI_PACKAGE_DIR = fakePnpmPackageDir;
	globalThis.fetch = async () =>
		new Response(JSON.stringify({ version: "99.0.0" }), {
			status: 200,
			headers: { "content-type": "application/json" },
		});
	await handlePackageCommand(["update", "--self", "--force"]);
	process.exitCode = 0;
	if (savedDrivePath === undefined) delete process.env.PATH;
	else process.env.PATH = savedDrivePath;
	Object.defineProperty(process, "execPath", { value: originalExecPath, configurable: true });
	if (originalPackageDir === undefined) delete process.env.PI_PACKAGE_DIR;
	else process.env.PI_PACKAGE_DIR = originalPackageDir;
}

const toolFixture = mkdtempSync(join(tmpdir(), "pi-visible-tool-"));
const archiveRoot = join(toolFixture, "archive");
const toolPath = join(archiveRoot, "fd");
mkdirSync(archiveRoot, { recursive: true });
writeFileSync(toolPath, "#!/bin/sh\nexit 0\n");
chmodSync(toolPath, 0o755);
const archivePath = join(toolFixture, "fd.tar.gz");
const tarResult = spawnSync("/usr/bin/tar", ["czf", archivePath, "-C", archiveRoot, "fd"]);
if (tarResult.status !== 0) throw new Error("failed to create deterministic fd fixture");
const archive = readFileSync(archivePath);
const toolPathDir = join(toolFixture, "path");
mkdirSync(toolPathDir);
symlinkSync("/usr/bin/tar", join(toolPathDir, "tar"));
symlinkSync("/usr/bin/gzip", join(toolPathDir, "gzip"));
const originalPath = process.env.PATH;
process.env.PATH = toolPathDir;
globalThis.fetch = async (input) => String(input).includes("api.github.com")
	? new Response(JSON.stringify({ tag_name: "v1.0.0" }), { status: 200 })
	: new Response(archive, { status: 200 });
await ensureTool("fd");
process.env.PATH = originalPath;
globalThis.fetch = originalFetch;
process.chdir(previousCwd);
if (packageOffline === undefined) delete process.env.PI_OFFLINE;
else process.env.PI_OFFLINE = packageOffline;
if (previousAgentDir === undefined) delete process.env.PI_CODING_AGENT_DIR;
else process.env.PI_CODING_AGENT_DIR = previousAgentDir;

new EarendilAnnouncementComponent();

const statuses: string[] = [];
const warnings: string[] = [];
const errors: string[] = [];
const fakeSettingsManager = new Proxy({
	getCollapseChangelog: () => true,
	setHideThinkingBlock() {},
	getTreeFilterMode: () => "all",
	getBranchSummarySkipPrompt: () => false,
	getEnabledModels: () => undefined,
	getHttpIdleTimeoutMs: () => 0,
	getWarnings: () => ({}),
}, {
	get(target, property) {
		if (property in target) return target[property];
		return () => undefined;
	},
});
let fakeTree: any[] = [];
let fakeLeafId = "leaf";
let fakeEntries: any[] = [{ type: "compaction" }, { type: "compaction" }];
const fakeSessionManager = {
	buildContextEntries: () => [],
	getEntries: () => fakeEntries,
	getSessionName: () => "normalized",
	getTree: () => fakeTree,
	getLeafId: () => fakeLeafId,
	getCwd: () => "/tmp",
	getSessionDir: () => "/tmp",
	getSessionFile: () => undefined,
	usesDefaultSessionDir: () => true,
};
const fakeSession = {
	sessionManager: fakeSessionManager,
	agent: { signal: new AbortController().signal },
	model,
	modelRuntime,
	promptTemplates: [],
	scopedModels: [],
	thinkingLevel: "off",
	autoCompactionEnabled: true,
	steeringMode: "one-at-a-time",
	followUpMode: "one-at-a-time",
	getAvailableThinkingLevels: () => ["off", "high"],
	cycleThinkingLevel: () => undefined,
	cycleModel: async () => undefined,
	setModel: async () => {},
	setSessionName() {},
	clearQueue() {},
	prompt: async () => {},
	followUp: async () => {},
	steer: async () => {},
	getUserMessagesForForking: () => [],
	getSessionStats: () => ({
		sessionFile: undefined,
		sessionId: "session",
		totalMessages: 0,
		userMessages: 0,
		assistantMessages: 0,
		toolCalls: 0,
		toolResults: 0,
		tokens: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
		cost: 0,
	}),
	extensionRunner: new Proxy({
		getCommand: () => undefined,
		getShortcuts: () => new Map(),
		getCommandDiagnostics: () => [],
		getShortcutDiagnostics: () => [],
		getModelRegistry: () => ({}),
	}, {
		get(target, property) {
			if (property in target) return target[property];
			return () => [];
		},
	}),
	settingsManager: fakeSettingsManager,
};
const interactive = Object.create(InteractiveMode.prototype);
const constructedSelectors: any[] = [];
Object.assign(interactive, {
	runtimeHost: {
		session: fakeSession,
		services: { agentDir: "/tmp/cadr-visible-agent" },
		fork: async () => ({ cancelled: false, selectedText: "forked" }),
		switchSession: async () => ({ cancelled: false }),
		newSession: async () => ({ cancelled: false }),
	},
	chatContainer: new Container(),
	loadedResourcesContainer: new Container(),
	statusContainer: new Container(),
	widgetContainerAbove: new Container(),
	widgetContainerBelow: new Container(),
	extensionWidgetsAbove: new Map(),
	extensionWidgetsBelow: new Map(),
	compactionQueuedMessages: [],
	pendingUserInputs: [],
	autocompleteProviderWrappers: [],
	defaultWorkingMessage: "Working...",
	defaultHiddenThinkingLabel: "Thinking...",
	hiddenThinkingLabel: "Thinking...",
	hideThinkingBlock: false,
	startupNoticesShown: false,
	changelogMarkdown: "## [9.9.9]\n\n- change",
	version: "9.9.8",
	showStatus: (value: string) => statuses.push(value),
	showWarning: (value: string) => warnings.push(value),
	showError: (value: string) => errors.push(value),
	rebuildChatFromMessages() {},
	renderSessionEntries() {},
	renderProjectTrustWarningIfNeeded() {},
	updatePendingMessagesDisplay() {},
	updateEditorBorderColor() {},
	maybeWarnAboutAnthropicSubscriptionAuth() {},
	checkDaxnutsEasterEgg() {},
	getMarkdownThemeWithSettings: () => ({
		heading: (value: string) => value,
		link: (value: string) => value,
		linkUrl: (value: string) => value,
		code: (value: string) => value,
		codeBlock: (value: string) => value,
		codeBlockBorder: (value: string) => value,
		quote: (value: string) => value,
		quoteBorder: (value: string) => value,
		hr: (value: string) => value,
		listBullet: (value: string) => value,
		bold: (value: string) => value,
		italic: (value: string) => value,
		strikethrough: (value: string) => value,
		underline: (value: string) => value,
	}),
	footer: { invalidate() {} },
	footerDataProvider: { clearExtensionStatuses() {}, setAvailableProviderCount() {} },
	editor: { addToHistory() {}, setText() {}, getText: () => "", borderColor: "" },
	defaultEditor: { onEscape: undefined, onExtensionShortcut: undefined, setAutocompleteProvider() {} },
	ui: {
		requestRender() {},
		hideOverlay() {},
		setFocus() {},
		getClearOnShrink: () => false,
		terminal: { rows: 32, columns: 100 },
		render: () => [],
	},
	editorContainer: new Container(),
	showSelector(create: (done: () => void) => { component: object }) {
		const result = create(() => {});
		constructedSelectors.push(result.component);
	},
	showExtensionSelector: async () => undefined,
	showExtensionEditor: async () => undefined,
	clearExtensionTerminalInputListeners() {},
	setExtensionFooter() {},
	setExtensionHeader() {},
	clearExtensionWidgets() {},
	setCustomEditorComponent() {},
	setupAutocompleteProvider() {},
	updateTerminalTitle() {},
	setWorkingIndicator() {},
	setHiddenThinkingLabel() {},
	activeStatusIndicator: undefined,
	options: { alt: false },
	keybindings: { getEffectiveConfig: () => ({}) },
	themeController: { getTerminalTheme: () => "dark", getThemeSelection: () => "dark" },
});

const invoke = (name: string, ...args: unknown[]) => InteractiveMode.prototype[name].apply(interactive, args);

invoke("showStartupNoticesIfNeeded");
invoke("addCacheMissNotice", { missedTokens: 25_000, missedCost: 0.12, modelChanged: false, idleMs: 0 });
invoke("addCacheMissNotice", { missedTokens: 25_000, missedCost: 0.12, modelChanged: true, idleMs: 0 });
invoke("addCacheMissNotice", { missedTokens: 25_000, missedCost: 0.12, modelChanged: false, idleMs: 600_000 });
interactive.restoreQueuedMessagesToEditor = () => 2;
invoke("handleDequeue");
invoke("cycleThinkingLevel");
interactive.session.cycleThinkingLevel = () => "high";
invoke("cycleThinkingLevel");
interactive.session.scopedModels = [{ model }];
await invoke("cycleModel", "forward");
interactive.session.scopedModels = [];
await invoke("cycleModel", "forward");
interactive.session.cycleModel = async () => ({ model, thinkingLevel: "high" });
await invoke("cycleModel", "forward");
invoke("toggleThinkingBlockVisibility");
invoke("toggleThinkingBlockVisibility");
invoke("queueCompactionMessage", "queued", "followUp");
invoke("renderInitialMessages");
invoke("setExtensionWidget", "many", Array.from({ length: 11 }, (_, index) => `${index}`));
invoke("showExtensionError", "/tmp/ext.ts", "failure");
invoke("showLoginAuthTypeSelector", []);
invoke("showLoginAuthTypeSelector");
interactive.getLoginProviderOptions = () => [];
invoke("showLoginProviderSelector", "oauth");
invoke("showLoginProviderSelector", "api_key");
invoke("showLoginProviderSelector");
interactive.getLogoutProviderOptions = async () => [];
await invoke("showOAuthSelector", "logout");
delete interactive.getLogoutProviderOptions;
invoke("showUserMessageSelector");
invoke("showTreeSelector");
await invoke("showModelsSelector");

invoke("showLoginAuthTypeSelector", [
	{ id: "provider", name: "Provider", authType: "oauth", method: { name: "OAuth" } },
	{ id: "provider", name: "Provider", authType: "api_key", method: { name: "API key" } },
]);

fakeSession.getUserMessagesForForking = () => [{ entryId: "user-entry", text: "fork point" }];
invoke("showUserMessageSelector");
await (constructedSelectors.at(-1) as any).getMessageList().onSelect("user-entry");

const treeEntry = (id: string, text: string) => ({
	type: "message",
	id,
	parentId: null,
	timestamp: "2026-01-01T00:00:00.000Z",
	message: { role: "user", content: text, timestamp: 0 },
});
fakeTree = [
	{ entry: treeEntry("leaf", "current"), children: [] },
	{ entry: treeEntry("other", "other"), children: [] },
];
fakeLeafId = "leaf";
fakeSession.navigateTree = async () => ({ cancelled: false, aborted: false, editorText: "restored" });
invoke("showTreeSelector");
await (constructedSelectors.at(-1) as any).getTreeList().onSelect("leaf");

interactive.showExtensionSelector = async () => "No summary";
invoke("showTreeSelector");
await (constructedSelectors.at(-1) as any).getTreeList().onSelect("other");

let summaryChoice = 0;
interactive.showExtensionSelector = async () => summaryChoice++ === 0 ? "Summarize with custom prompt" : "No summary";
interactive.showExtensionEditor = async () => undefined;
invoke("showTreeSelector");
await (constructedSelectors.at(-1) as any).getTreeList().onSelect("other");

interactive.showExtensionSelector = async () => "Summarize";
fakeSession.navigateTree = async () => ({ cancelled: false, aborted: true });
invoke("showTreeSelector");
await (constructedSelectors.at(-1) as any).getTreeList().onSelect("other");
fakeSession.navigateTree = async () => ({ cancelled: true, aborted: false });
invoke("showTreeSelector");
await (constructedSelectors.at(-1) as any).getTreeList().onSelect("other");
await (constructedSelectors.at(-1) as any).onCopy(undefined);
await (constructedSelectors.at(-1) as any).onCopy("copied tree entry");

interactive.runtimeHost.switchSession = async () => ({ cancelled: false });
await invoke("handleResumeSession", "/tmp/session.jsonl");
interactive.promptForMissingSessionCwd = async () => undefined;
interactive.runtimeHost.switchSession = async () => {
	throw new MissingSessionCwdError({ sessionCwd: "/missing", fallbackCwd: "/current" });
};
await invoke("handleResumeSession", "/tmp/session.jsonl");
let switchAttempt = 0;
interactive.promptForMissingSessionCwd = async () => "/current";
interactive.runtimeHost.switchSession = async () => {
	if (switchAttempt++ === 0) {
		throw new MissingSessionCwdError({ sessionCwd: "/missing", fallbackCwd: "/current" });
	}
	return { cancelled: false };
};
await invoke("handleResumeSession", "/tmp/session.jsonl");

modelRuntime.listCredentials = async () => [
	{ providerId: "oauth-provider", type: "oauth" },
	{ providerId: "key-provider", type: "api_key" },
];
modelRuntime.getProvider = (providerId: string) => ({ id: providerId, name: providerId });
modelRuntime.logout = async () => {};
interactive.updateAvailableProviderCount = async () => {};
await invoke("showOAuthSelector", "logout");
await (constructedSelectors.findLast((component) => component.constructor.name === "OAuthSelectorComponent") as any)
	.onSelectCallback("oauth-provider", "oauth");
modelRuntime.listCredentials = async () => [
	{ providerId: "key-provider", type: "api_key" },
];
await invoke("showOAuthSelector", "logout");
await (constructedSelectors.findLast((component) => component.constructor.name === "OAuthSelectorComponent") as any)
	.onSelectCallback("key-provider", "api_key");
modelRuntime.listCredentials = async () => [
	{ providerId: "oauth-provider", type: "oauth" },
];
modelRuntime.logout = async () => { throw new Error("logout failure"); };
await invoke("showOAuthSelector", "logout");
await (constructedSelectors.findLast((component) => component.constructor.name === "OAuthSelectorComponent") as any)
	.onSelectCallback("oauth-provider", "oauth");

modelRuntime.getAvailable = async () => [model];
await invoke("completeProviderAuthentication", "provider-one", "Provider One", "oauth", model);
await invoke("completeProviderAuthentication", "provider-one", "Provider One", "api_key", model);
const codexModel = { ...model, api: "openai-codex-responses", provider: "openai-codex", id: "gpt-5.5" };
const unknownModel = { ...model, api: "unknown", provider: "unknown", id: "unknown" };
modelRuntime.getAvailable = async () => [codexModel];
fakeSession.setModel = async () => {};
await invoke("completeProviderAuthentication", "openai-codex", "OpenAI Codex", "oauth", unknownModel);

modelRuntime.getAvailable = async () => [model];
await invoke("showModelsSelector");
(constructedSelectors.findLast((component) => component.constructor.name === "ScopedModelsSelectorComponent") as any)
	.callbacks.onPersist(["provider-one/model-one"]);

invoke("showSettingsSelector");
(constructedSelectors.at(-1) as any).getSettingsList().onChange("http-idle-timeout", "disabled");

invoke("showAmbientAuthDialog", {
	id: "ambient-default",
	name: "Ambient Default",
	authType: "api_key",
});
invoke("handleNameCommand", "");
interactive.sessionManager.getSessionName = () => "trimmed";
invoke("handleNameCommand", "/name requested");
invoke("handleSessionCommand");
invoke("handleHotkeysCommand");

const platformBeforeHotkeys = Object.getOwnPropertyDescriptor(process, "platform");
Object.defineProperty(process, "platform", { value: "win32" });
interactive.session.extensionRunner.getShortcuts = () => new Map([
	["ctrl+k", { description: "extension shortcut", extensionPath: "/tmp/ext.ts" }],
]);
invoke("handleHotkeysCommand");
if (platformBeforeHotkeys) Object.defineProperty(process, "platform", platformBeforeHotkeys);

Object.defineProperty(process, "platform", { value: "win32", configurable: true });
invoke("handleCtrlZ");
if (platformBeforeHotkeys) Object.defineProperty(process, "platform", platformBeforeHotkeys);

delete interactive.maybeWarnAboutAnthropicSubscriptionAuth;
fakeSession.modelRuntime.checkAuth = async () => ({ type: "oauth" });
await invoke("maybeWarnAboutAnthropicSubscriptionAuth", { ...model, provider: "anthropic" });

fakeLeafId = null;
await invoke("handleCloneCommand");
fakeLeafId = "leaf";

const usage = (input: number, cacheRead: number, timestamp: number) => ({
	role: "assistant",
	content: [],
	api: "responses",
	provider: "provider-one",
	model: "model-one",
	usage: {
		input,
		output: 10,
		cacheRead,
		cacheWrite: 0,
		totalTokens: input + cacheRead + 10,
		cost: { input: input / 1_000_000, output: 0, cacheRead: 0, cacheWrite: 0, total: input / 1_000_000 },
	},
	stopReason: "stop",
	timestamp,
});
fakeEntries = [
	{ type: "message", id: "m1", parentId: null, timestamp: "2026-01-01T00:00:00.000Z", message: usage(1000, 3000, 0) },
	{ type: "message", id: "m2", parentId: "m1", timestamp: "2026-01-01T00:10:00.000Z", message: usage(4000, 0, 600_000) },
	{ type: "message", id: "m3", parentId: "m2", timestamp: "2026-01-01T00:20:00.000Z", message: usage(4000, 0, 1_200_000) },
];
fakeSession.getSessionStats = () => ({
	sessionFile: undefined,
	sessionId: "session",
	totalMessages: 3,
	userMessages: 0,
	assistantMessages: 3,
	toolCalls: 0,
	toolResults: 0,
	tokens: { input: 9000, output: 30, cacheRead: 3000, cacheWrite: 0, total: 12_030 },
	cost: 1,
});
invoke("handleSessionCommand");

fakeSession.getLastAssistantText = () => "copy me";
await invoke("handleCopyCommand");

const changelogPath = getChangelogPath();
try { unlinkSync(changelogPath); } catch {}
invoke("handleChangelogCommand");

fakeSession.resourceLoader = {
	getSystemPromptSource: () => undefined,
	getAppendSystemPromptSources: () => [],
	getAgentsFiles: () => ({ agentsFiles: [] }),
	getSkills: () => ({ skills: [], diagnostics: [] }),
	getPrompts: () => ({ prompts: [], diagnostics: [{ type: "warning", message: "prompt conflict" }] }),
	getThemes: () => ({ themes: [], diagnostics: [{ type: "warning", message: "theme conflict" }] }),
	getExtensions: () => ({ extensions: [], errors: [{ path: "/tmp/ext.ts", error: "extension failure" }] }),
};
fakeSession.extensionRunner.getCommandDiagnostics = () => [];
fakeSession.extensionRunner.getShortcutDiagnostics = () => [];
invoke("showLoadedResources", { force: true, showDiagnosticsWhenQuiet: true });
fakeSession.resourceLoader.getSkills = () => ({ skills: [], diagnostics: [{ type: "warning", message: "skill conflict" }] });
invoke("showLoadedResources", { force: true, showDiagnosticsWhenQuiet: true });

fakeSession.extensionRunner.getShortcuts = () => new Map([
	["ctrl+k", { description: "failing shortcut", extensionPath: "/tmp/ext.ts", handler: async () => { throw new Error("shortcut failure"); } }],
]);
invoke("setupExtensionShortcuts", fakeSession.extensionRunner);
interactive.defaultEditor.onExtensionShortcut("\x0b");
await new Promise((resolve) => setTimeout(resolve, 0));

fakeSession.navigateTree = async () => ({ cancelled: false, editorText: "extension navigation" });
fakeSession.bindExtensions = async (options: any) => {
	await options.commandContextActions.fork("other", {});
	await options.commandContextActions.navigateTree("other", {});
};
await invoke("bindCurrentSessionExtensions");

const trustCwd = `${process.env.HOME}/goal17-trust-project`;
mkdirSync(`${trustCwd}/.pi/extensions`, { recursive: true });
writeFileSync(`${trustCwd}/.pi/extensions/extension.ts`, "export default () => {};\n");
fakeSessionManager.getCwd = () => trustCwd;
fakeSettingsManager.isProjectTrusted = () => true;
interactive.autoTrustOnReloadCwd = trustCwd;
interactive.runtimeHost.services.agentDir = "/dev/null";
invoke("maybeSaveImplicitProjectTrustAfterReload");
fakeSessionManager.getCwd = () => "/tmp";
interactive.runtimeHost.services.agentDir = "/tmp/cadr-visible-agent";

const shareFixture = mkdtempSync(join(tmpdir(), "pi-visible-share-"));
const fakeGh = join(shareFixture, "gh");
writeFileSync(
	fakeGh,
	`#!/bin/sh
if [ "$1" = "auth" ]; then
	[ "$GH_VISIBLE_MODE" = "not-logged-in" ] && exit 1
	exit 0
fi
case "$GH_VISIBLE_MODE" in
	failure) printf '%s\\n' 'fixture gist failure' >&2; exit 3 ;;
	empty) exit 0 ;;
	cancel) exec /bin/sleep 10 ;;
esac
`,
);
chmodSync(fakeGh, 0o755);
const sharePath = process.env.PATH;
process.env.PATH = `${shareFixture}:${sharePath ?? ""}`;
fakeSession.exportToHtml = async (path: string) => writeFileSync(path, "fixture html");
process.env.GH_VISIBLE_MODE = "not-logged-in";
await invoke("handleShareCommand");
process.env.GH_VISIBLE_MODE = "failure";
await invoke("handleShareCommand");
process.env.GH_VISIBLE_MODE = "empty";
await invoke("handleShareCommand");
process.env.GH_VISIBLE_MODE = "cancel";
const cancelledShare = invoke("handleShareCommand");
await new Promise((resolve) => setTimeout(resolve, 20));
const shareLoader = (interactive.editorContainer as any).children.at(-1);
shareLoader.handleInput("\x1b");
await cancelledShare;
delete process.env.GH_VISIBLE_MODE;
process.env.PATH = sharePath;

const previousOffline = process.env.PI_OFFLINE;
process.env.PI_OFFLINE = "1";
interactive.init = async () => {};
interactive.checkForPackageUpdates = async () => [];
interactive.checkTmuxKeyboardSetup = async () => undefined;
interactive.getUserInput = async () => { throw new Error("goal17 construction complete"); };
interactive.options = {
	migratedProviders: ["provider-one"],
	initialMessage: "first",
	initialMessages: ["second"],
};
fakeSession.prompt = async () => { throw 42; };
try {
	await invoke("run");
} catch (error) {
	if (!(error instanceof Error) || error.message !== "goal17 construction complete") throw error;
}
if (previousOffline === undefined) delete process.env.PI_OFFLINE;
else process.env.PI_OFFLINE = previousOffline;

interactive.session.modelRuntime.login = async () => {
	throw new Error("login failure");
};
await invoke("showApiKeyLoginDialog", "amazon-bedrock", "Amazon Bedrock");
await invoke("showLoginDialog", "provider", "Provider");
invoke("showAmbientAuthDialog", {
	id: "ambient",
	name: "Ambient",
	authType: "api_key",
	method: { name: "Ambient authentication" },
});
invoke("notifyAuthDialog", login, {
	type: "device_code",
	verificationUri: "https://example.invalid/device",
	userCode: "CODE",
});

interactive.session.isStreaming = true;
await invoke("handleReloadCommand");
interactive.session.isStreaming = false;
interactive.session.isCompacting = true;
await invoke("handleReloadCommand");
interactive.session.isCompacting = false;

interactive.session.exportToHtml = async () => {
	throw new Error("export failure");
};
await invoke("handleExportCommand", "/export");

interactive.ui.terminal = { rows: 32, columns: 100 };
interactive.session.messages = [];
invoke("handleDebugCommand");

interactive.findExactModelMatch = async () => model;
await invoke("handleModelCommand", "provider/model-one");

interactive.compactionQueuedMessages = [{ text: "queued", mode: "followUp" }];
interactive.session.followUp = async () => {
	throw new Error("queue failure");
};
await invoke("flushCompactionQueue", { willRetry: true });

invoke("showSettingsSelector");
invoke("showModelSelector");

interactive.isInitialized = true;
interactive.clearStatusIndicator = () => {};
interactive.showStatusIndicator = () => {};
interactive.checkShutdownRequested = async () => {};
await invoke("handleEvent", { type: "compaction_end", reason: "manual", aborted: true });
await invoke("handleEvent", { type: "compaction_end", reason: "threshold", aborted: true });
await invoke("handleEvent", { type: "auto_retry_end", success: false, attempt: 3 });

interactive.pendingMessagesContainer = new Container();
interactive.pendingBashComponents = [];
interactive.session.extensionRunner.emitUserBash = async () => undefined;
interactive.session.executeBash = async () => {
	throw new Error("bash failure");
};
await invoke("handleBashCommand", "false");

interactive.resetExtensionUI = () => {};
interactive.session.reload = async () => { throw new Error("reload failure"); };
await invoke("handleReloadCommand");
interactive.session.reload = async ({ beforeSessionStart }: { beforeSessionStart: () => void }) => beforeSessionStart();
interactive.session.resourceLoader = { getThemes: () => ({ themes: [] }) };
interactive.keybindings.reload = () => {};
interactive.themeController.applyFromSettings = async () => {};
interactive.themeController.getTerminalTheme = () => "dark";
interactive.defaultEditor.setPaddingX = () => {};
interactive.defaultEditor.setAutocompleteMaxVisible = () => {};
interactive.ui.setShowHardwareCursor = () => {};
interactive.ui.setClearOnShrink = () => {};
interactive.showLoadedResources = () => {};
interactive.maybeSaveImplicitProjectTrustAfterReload = () => true;
interactive.session.modelRuntime.getError = () => "catalog failure";
await invoke("handleReloadCommand");

interactive.session.isBashRunning = true;
invoke("setupEditorSubmitHandler");
await interactive.defaultEditor.onSubmit("!long-running");

interactive.activeStatusIndicator = { kind: "working", setMessage() {}, dispose() {} };
interactive.clearExtensionWidgets = () => {};
invoke("resetExtensionUI");
const extensionUi = invoke("createExtensionUIContext");
extensionUi.setWorkingMessage(undefined);

interactive.showExtensionConfirm = async () => false;
await invoke("promptForMissingSessionCwd", {
	issue: { sessionCwd: "/missing", fallbackCwd: "/current" },
});

interactive.showExtensionConfirm = async () => true;
interactive.runtimeHost.importFromJsonl = async () => ({ cancelled: false });
await invoke("handleImportCommand", "/import /tmp/session.jsonl");
interactive.runtimeHost.importFromJsonl = async () => {
	throw new SessionImportFileNotFoundError("/tmp/session.jsonl");
};
await invoke("handleImportCommand", "/import /tmp/session.jsonl");

if (!statuses.length || !warnings.length && !errors.length) {
	throw new Error("production sink construction did not execute expected interactive paths");
}

// Force render construction on containers whose constructors only register children.
for (const component of [setup, compaction, branch, skill, new Container(), new Text(theme.fg("text", "done"), 0, 0)]) {
	component.render(80);
}

// --- Goal 18 I7 tail: migrations, shortcut conflicts, prompt-file and
// tool-download failure arms, models.json load warning, unreadable @file.

{
	// migrations.ts:144 (success, Global and Project) and :214 (tools→bin).
	const migrationHome = mkdtempSync(join(tmpdir(), "pi-visible-migrations-"));
	const migrationAgent = join(migrationHome, "agent");
	mkdirSync(join(migrationAgent, "commands"), { recursive: true });
	mkdirSync(join(migrationAgent, "tools"), { recursive: true });
	writeFileSync(join(migrationAgent, "tools", "fd"), "managed-binary");
	const migrationProject = join(migrationHome, "project");
	mkdirSync(join(migrationProject, ".pi", "commands"), { recursive: true });
	const savedAgentDir = process.env.PI_CODING_AGENT_DIR;
	process.env.PI_CODING_AGENT_DIR = migrationAgent;
	try {
		runMigrations(migrationProject);
	} finally {
		if (savedAgentDir === undefined) delete process.env.PI_CODING_AGENT_DIR;
		else process.env.PI_CODING_AGENT_DIR = savedAgentDir;
	}

	// migrations.ts:148 — the rename failure arm.  tsx transpiles the
	// baseline to call-time CommonJS lookups, so patching the fs module
	// object reaches the production import.
	// Use a fresh agent directory: the success arm above already renamed
	// commands/ to prompts/, and the migration only fires while prompts/
	// is absent.
	const migrationFailAgent = join(migrationHome, "agent-fail");
	mkdirSync(join(migrationFailAgent, "commands"), { recursive: true });
	const constructionRequire = createRequire(import.meta.url);
	const fsModule = constructionRequire("node:fs") as typeof import("node:fs");
	const realRenameSync = fsModule.renameSync;
	fsModule.renameSync = (() => {
		throw new Error("EACCES: permission denied, rename (construction drive)");
	}) as never;
	process.env.PI_CODING_AGENT_DIR = migrationFailAgent;
	try {
		runMigrations(migrationProject);
	} finally {
		fsModule.renameSync = realRenameSync;
		if (savedAgentDir === undefined) delete process.env.PI_CODING_AGENT_DIR;
		else process.env.PI_CODING_AGENT_DIR = savedAgentDir;
	}
}

{
	// runner.ts:513/521/529 — extension shortcut conflict diagnostics,
	// driven without a UI context so they take the console.warn path.
	const shortcutRunner = new ExtensionRunner(
		[
			{
				shortcuts: new Map([
					["ctrl+x", { extensionPath: "./ext-one" }],
					["ctrl+shift+d", { extensionPath: "./ext-one" }],
					["ctrl+shift+z", { extensionPath: "./ext-one" }],
				]),
			},
			{
				shortcuts: new Map([
					["ctrl+shift+z", { extensionPath: "./ext-two" }],
				]),
			},
		] as never,
		{} as never,
		process.cwd(),
		{} as never,
		{} as never,
	);
	shortcutRunner.getShortcuts({
		"app.interrupt": "ctrl+x",
		"app.session.delete": "ctrl+shift+d",
	} as never);
}

{
	// resource-loader.ts:62 — an existing but unreadable prompt file (a
	// directory) warns and falls back to the literal input.
	const promptHome = mkdtempSync(join(tmpdir(), "pi-visible-prompt-"));
	const promptAgent = join(promptHome, "agent");
	const promptCwd = join(promptHome, "project");
	mkdirSync(promptAgent, { recursive: true });
	mkdirSync(promptCwd, { recursive: true });
	const promptDir = join(promptHome, "prompt-dir");
	mkdirSync(promptDir);
	const promptLoader = new DefaultResourceLoader({
		cwd: promptCwd,
		agentDir: promptAgent,
		noExtensions: true,
		noSkills: true,
		noPromptTemplates: true,
		noThemes: true,
		noContextFiles: true,
		systemPrompt: promptDir,
		appendSystemPrompt: [promptDir],
	});
	await promptLoader.reload();
}

{
	// tools-manager.ts:337 (offline) and :365 (download failure).  The
	// construction environment is offline by default; clear it just for
	// the failure arm and force fetch to reject.
	const toolHome = mkdtempSync(join(tmpdir(), "pi-visible-tools-"));
	mkdirSync(join(toolHome, "bin"), { recursive: true });
	// The download-fixture drive above installed a fixture fd into the
	// agent bin directory; remove it so getToolPath misses and both
	// failure arms run.
	try {
		unlinkSync(join(process.env.PI_CODING_AGENT_DIR ?? join(process.env.HOME ?? "", ".pi", "agent"), "bin", "fd"));
	} catch {
		// already absent
	}
	const savedPath = process.env.PATH;
	const savedOffline = process.env.PI_OFFLINE;
	const savedToolAgentDir = process.env.PI_CODING_AGENT_DIR;
	process.env.PATH = join(toolHome, "bin");
	process.env.PI_CODING_AGENT_DIR = join(toolHome, "agent");
	process.env.PI_OFFLINE = "1";
	try {
		await ensureTool("fd");
		delete process.env.PI_OFFLINE;
		const savedFetch = globalThis.fetch;
		globalThis.fetch = (async () => {
			throw new Error("network unreachable (construction drive)");
		}) as never;
		try {
			await ensureTool("fd");
		} finally {
			globalThis.fetch = savedFetch;
		}
	} finally {
		if (savedPath === undefined) delete process.env.PATH;
		else process.env.PATH = savedPath;
		if (savedOffline === undefined) delete process.env.PI_OFFLINE;
		else process.env.PI_OFFLINE = savedOffline;
		if (savedToolAgentDir === undefined) delete process.env.PI_CODING_AGENT_DIR;
		else process.env.PI_CODING_AGENT_DIR = savedToolAgentDir;
	}
}

{
	// list-models.ts:32 — a models.json load failure warns before the
	// table prints.
	await listModels(
		{
			getError: () => "models.json is not valid JSON (construction drive)",
			getAvailable: async () => [model],
		} as never,
		undefined,
	);
}

{
	// file-processor.ts:80 — an unreadable @file (a directory) is a red
	// error and exit 1.
	// A directory never reaches this branch in the baseline — mime
	// detection throws EISDIR first — so drive it with a real file whose
	// readFile fails (tsx resolves the production import through the
	// CommonJS module object, which this patch replaces).
	const fileArgHome = mkdtempSync(join(tmpdir(), "pi-visible-file-arg-"));
	const fileArgFile = join(fileArgHome, "unreadable.txt");
	writeFileSync(fileArgFile, "content that cannot be read\n");
	const fileRequire = createRequire(import.meta.url);
	const fsPromises = fileRequire("node:fs/promises") as typeof import("node:fs/promises");
	const realReadFile = fsPromises.readFile;
	fsPromises.readFile = (async () => {
		throw new Error("EACCES: permission denied, open (construction drive)");
	}) as never;
	const realExit = process.exit;
	process.exit = ((code?: number) => {
		throw new Error(`__construction_exit_${code ?? 0}`);
	}) as never;
	try {
		await processFileArguments([fileArgFile]);
	} catch (error) {
		if (!(error instanceof Error && error.message.startsWith("__construction_exit_"))) throw error;
	} finally {
		fsPromises.readFile = realReadFile;
		process.exit = realExit;
		process.exitCode = undefined;
	}
}
