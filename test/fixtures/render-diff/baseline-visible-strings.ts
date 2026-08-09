import fs from "node:fs";
import path from "node:path";
import { createHash } from "node:crypto";
import ts from "typescript";

type StylePath = string[];

type Segment =
	| { kind: "literal"; text: string; stylePath: StylePath }
	| { kind: "slot"; expression: string; stylePath: StylePath };

type Branch = {
	id: string;
	conditions: string[];
	runtimeChoices: string[];
	segments: Segment[];
};

type PresentationChannel = "printable-visible" | "terminal-protocol";

type CandidateMetadata =
	| { commandName: string; field: "name" | "description" | "argumentHint" }
	| { surface: "extension-selector"; field: "title" | "item" };

type Candidate = {
	source: ts.SourceFile;
	expression: ts.Expression;
	kind: string;
	channel: PresentationChannel;
	priority: number;
	metadata?: CandidateMetadata;
	opaqueRuntime?: boolean;
};

type Entry = {
	id: string;
	site: {
		path: string;
		line: number;
		column: number;
		endLine: number;
		endColumn: number;
		start: number;
		end: number;
		kind: string;
		nodeSha256: string;
		metadata?: CandidateMetadata;
	};
	sink: { kind: string; channel: PresentationChannel };
	branches: Branch[];
};

type SinkContract = {
	argumentPositions: readonly number[];
	channel: PresentationChannel;
};

const argv = process.argv.slice(2);
const baselineRoot = path.resolve(argv[0] ?? ".");
const baselineCommit = argv[1];
const instrumentIndex = argv.indexOf("--instrument", 2);
const instrumentRoot = instrumentIndex >= 0 && argv[instrumentIndex + 1]
	? path.resolve(argv[instrumentIndex + 1])
	: undefined;
if (!baselineCommit || instrumentIndex >= 0 && !instrumentRoot) {
	throw new Error("usage: baseline-visible-strings.ts <baseline-root> <commit> [--instrument DEST]");
}

const sourceRoots = ["packages/coding-agent/src", "packages/tui/src"];
const parsedSourceExtensions = new Set([".ts", ".tsx", ".mts", ".cts"]);
const exactAssetRules = new Map<string, { kind: string; reason: string }>([
	["packages/coding-agent/src/modes/interactive/theme/dark.json", {
		kind: "terminal-theme", reason: "Built-in terminal theme; SHA-256 and declared roles are part of the presentation source universe.",
	}],
	["packages/coding-agent/src/modes/interactive/theme/light.json", {
		kind: "terminal-theme", reason: "Built-in terminal theme; SHA-256 and declared roles are part of the presentation source universe.",
	}],
	["packages/coding-agent/src/modes/interactive/theme/theme-schema.json", {
		kind: "excluded-theme-schema", reason: "Validation metadata only; it is not rendered, while the two built-in theme instances are inventoried separately.",
	}],
	["packages/coding-agent/src/modes/interactive/assets/clankolas.png", {
		kind: "terminal-image-asset", reason: "Binary terminal announcement image; exact content is locked by SHA-256 because it is not statically parseable.",
	}],
	["packages/coding-agent/src/core/export-html/template.css", {
		kind: "excluded-html-export-asset", reason: "Browser-only session export asset; it belongs to the export-file channel, not terminal rendering.",
	}],
	["packages/coding-agent/src/core/export-html/template.html", {
		kind: "excluded-html-export-asset", reason: "Browser-only session export asset; it belongs to the export-file channel, not terminal rendering.",
	}],
	["packages/coding-agent/src/core/export-html/template.js", {
		kind: "excluded-html-export-asset", reason: "Browser-only session export asset; it belongs to the export-file channel, not terminal rendering.",
	}],
	["packages/coding-agent/src/core/export-html/vendor/highlight.min.js", {
		kind: "excluded-third-party-html-export-asset", reason: "Vendored third-party browser script embedded only in exported HTML; the export-file gate owns its bytes and license assertions.",
	}],
	["packages/coding-agent/src/core/export-html/vendor/marked.min.js", {
		kind: "excluded-third-party-html-export-asset", reason: "Vendored third-party browser script embedded only in exported HTML; the export-file gate owns its bytes and license assertions.",
	}],
]);
const slashCommandPropertyNames = new Set(["name", "description", "argumentHint"]);
const callSinkContracts = new Map<string, SinkContract>([
	["addDiagnostic", { argumentPositions: [0], channel: "printable-visible" }],
	["addLoadedSection", { argumentPositions: [0], channel: "printable-visible" }],
	["appendStatus", { argumentPositions: [1], channel: "printable-visible" }],
	["setMessage", { argumentPositions: [0], channel: "printable-visible" }],
	["setText", { argumentPositions: [0], channel: "printable-visible" }],
	["setTextInternal", { argumentPositions: [0], channel: "printable-visible" }],
	["setTitle", { argumentPositions: [0], channel: "printable-visible" }],
	["showAuth", { argumentPositions: [0, 1], channel: "printable-visible" }],
	["showDetails", { argumentPositions: [0], channel: "printable-visible" }],
	["showError", { argumentPositions: [0], channel: "printable-visible" }],
	["showExtensionConfirm", { argumentPositions: [0, 1], channel: "printable-visible" }],
	["showExtensionEditor", { argumentPositions: [0, 1], channel: "printable-visible" }],
	["showExtensionInput", { argumentPositions: [0, 1], channel: "printable-visible" }],
	["showExtensionNotify", { argumentPositions: [0], channel: "printable-visible" }],
	["showExtensionSelector", { argumentPositions: [0, 1], channel: "printable-visible" }],
	["showInfo", { argumentPositions: [0], channel: "printable-visible" }],
	["showManualInput", { argumentPositions: [0], channel: "printable-visible" }],
	["showProgress", { argumentPositions: [0], channel: "printable-visible" }],
	["showPrompt", { argumentPositions: [0, 1], channel: "printable-visible" }],
	["showStatus", { argumentPositions: [0], channel: "printable-visible" }],
	["showWaiting", { argumentPositions: [0], channel: "printable-visible" }],
	["showWarning", { argumentPositions: [0], channel: "printable-visible" }],
	["writeRawStdout", { argumentPositions: [0], channel: "printable-visible" }],
]);
const directPrintableOutputs = new Set([
	"process.stdout.write", "process.stderr.write", "console.log", "console.error", "console.warn", "this.output.write",
]);
const textConstructors = new Set([
	"Text", "Markdown", "ExpandableText", "TruncatedText", "Loader", "CancellableLoader", "BorderedLoader",
]);
// Component constructors whose visible string arguments sit at non-zero
// positions.  LoginDialogComponent takes its dialog title as the fifth
// parameter (titleOverride, login-dialog.ts:35); the ambient-auth flow passes
// the fixed " setup" suffix through it (interactive-mode.ts:5198).
const constructorArgumentPositions = new Map<string, number[]>([
	["LoginDialogComponent", [4]],
]);
const tuiThemeValueCalls = new Set([
	"bold", "code", "codeBlock", "codeBlockBorder", "description", "fallbackColor", "hint", "italic",
	"label", "link", "linkUrl", "listBullet", "noMatch", "quote", "quoteBorder", "scrollInfo",
	"selectedPrefix", "selectedText", "strikethrough", "underline", "value",
]);
// Style wrappers are transparent to the fixed string fragments inside them.
// The color entries cover chalk's color API: the extractor keys on the
// property name only, so theme.fg-style calls were already resolved while
// chalk.red/chalk.yellow/chalk.green wrappers silently collapsed the whole
// call into an opaque runtime slot and dropped the literal (Goal 18 I7).
const styleCalls = new Set([
	"bold", "dim", "italic", "strikethrough", "underline",
	"red", "green", "yellow", "cyan", "blue", "magenta", "white", "black", "gray", "grey", "inverse",
	"bgRed", "bgGreen", "bgYellow", "bgBlue", "bgCyan", "bgMagenta", "bgWhite", "bgBlack",
]);
const candidates: Candidate[] = [];

function digest(value: string): string {
	return createHash("sha256").update(value).digest("hex");
}

function walkFiles(directory: string): string[] {
	if (!fs.existsSync(directory)) return [];
	const files: string[] = [];
	for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
		const entryPath = path.join(directory, entry.name);
		if (entry.isDirectory()) files.push(...walkFiles(entryPath));
		else if (entry.isFile()) files.push(entryPath);
	}
	return files;
}

function addVisibleArgument(
	source: ts.SourceFile,
	expression: ts.Expression | undefined,
	kind: string,
	channel: PresentationChannel,
	priority: number,
	opaqueRuntime = false,
): void {
	if (!expression) return;
	if (ts.isSpreadElement(expression)) {
		addCandidate(source, expression.expression, kind, channel, priority, undefined, opaqueRuntime);
		return;
	}
	if (ts.isArrayLiteralExpression(expression)) {
		for (const element of expression.elements) {
			if (ts.isSpreadElement(element)) {
				addCandidate(source, element.expression, kind, channel, priority, undefined, opaqueRuntime);
			} else if (ts.isExpression(element)) {
				addCandidate(source, element, kind, channel, priority, undefined, opaqueRuntime);
			}
		}
		return;
	}
	addCandidate(source, expression, kind, channel, priority, undefined, opaqueRuntime);
}

function calledName(expression: ts.Expression): string | undefined {
	if (ts.isIdentifier(expression)) return expression.text;
	if (ts.isPropertyAccessExpression(expression)) return expression.name.text;
	return undefined;
}

function enclosingFunction(node: ts.Node): ts.FunctionLikeDeclaration | undefined {
	let current: ts.Node | undefined = node.parent;
	while (current) {
		if (
			ts.isArrowFunction(current) || ts.isConstructorDeclaration(current) ||
			ts.isFunctionDeclaration(current) || ts.isFunctionExpression(current) ||
			ts.isGetAccessorDeclaration(current) || ts.isMethodDeclaration(current) ||
			ts.isSetAccessorDeclaration(current)
		) return current;
		current = current.parent;
	}
}

function enclosingFunctionName(node: ts.Node, source: ts.SourceFile): string | undefined {
	const functionLike = enclosingFunction(node);
	return functionLike?.name?.getText(source);
}

function addCandidate(
	source: ts.SourceFile,
	expression: ts.Expression | undefined,
	kind: string,
	channel: PresentationChannel,
	priority: number,
	metadata?: CandidateMetadata,
	opaqueRuntime = false,
): void {
	if (expression) candidates.push({ source, expression, kind, channel, priority, metadata, opaqueRuntime });
}

function terminalWriteTarget(target: string): boolean {
	return target === "this.terminal.write" || target === "terminal.write";
}

const exactTerminalProtocolIdentifiers = new Set([
	"packages/tui/src/TuiMainScreen.ts:positionHardwareCursor:buffer",
	"packages/tui/src/terminal.ts:queryAndEnableKittyProtocol:KITTY_KEYBOARD_PROTOCOL_QUERY",
]);
const exactTerminalProtocolFunctions = new Set([
	"packages/tui/src/TuiAltScreen.ts:beforeTerminalStart",
	"packages/tui/src/TuiAltScreen.ts:beforeTerminalStop",
]);

function terminalWriteChannel(
	source: ts.SourceFile,
	expression: ts.Expression | undefined,
): PresentationChannel {
	if (!expression) return "printable-visible";
	const relativePath = path.relative(baselineRoot, source.fileName).replaceAll(path.sep, "/");
	if (exactTerminalProtocolFunctions.has(`${relativePath}:${enclosingFunctionName(expression, source) ?? ""}`)) {
		return "terminal-protocol";
	}
	if (ts.isParenthesizedExpression(expression)) return terminalWriteChannel(source, expression.expression);
	if (ts.isConditionalExpression(expression)) {
		return terminalWriteChannel(source, expression.whenTrue) === "terminal-protocol" &&
			terminalWriteChannel(source, expression.whenFalse) === "terminal-protocol"
			? "terminal-protocol"
			: "printable-visible";
	}
	if (ts.isStringLiteralLike(expression)) {
		return /^\x1b(?:\[|\]|_|P)/.test(expression.text) ? "terminal-protocol" : "printable-visible";
	}
	if (ts.isTemplateExpression(expression)) {
		return /^\x1b(?:\[|\]|_|P)/.test(expression.head.text) ? "terminal-protocol" : "printable-visible";
	}
	if (
		ts.isCallExpression(expression) && ts.isPropertyAccessExpression(expression.expression) &&
		expression.expression.name.text === "join" && ts.isArrayLiteralExpression(expression.expression.expression)
	) {
		return expression.expression.expression.elements.every(
			(element) => ts.isExpression(element) && terminalWriteChannel(source, element) === "terminal-protocol",
		)
			? "terminal-protocol"
			: "printable-visible";
	}
	if (ts.isIdentifier(expression)) {
		const contract = `${relativePath}:${enclosingFunctionName(expression, source) ?? ""}:${expression.text}`;
		if (exactTerminalProtocolIdentifiers.has(contract)) return "terminal-protocol";
		const declaration = localDeclaration(source, expression, expression.text);
		if (
			declaration?.initializer && ts.isVariableDeclarationList(declaration.parent) &&
			(declaration.parent.flags & ts.NodeFlags.Const) !== 0
		) return terminalWriteChannel(source, declaration.initializer);
	}
	return "printable-visible";
}

function builtinSlashCommandMetadata(source: ts.SourceFile, node: ts.PropertyAssignment): Candidate["metadata"] | undefined {
	const field = node.name.getText(source).replace(/^['"]|['"]$/g, "");
	if (!slashCommandPropertyNames.has(field)) return undefined;
	let object: ts.ObjectLiteralExpression | undefined;
	for (let current: ts.Node | undefined = node.parent; current; current = current.parent) {
		if (ts.isObjectLiteralExpression(current)) {
			object = current;
			break;
		}
	}
	if (!object) return undefined;
	const nameProperty = object.properties.find((property): property is ts.PropertyAssignment =>
		ts.isPropertyAssignment(property) && property.name.getText(source).replace(/^['"]|['"]$/g, "") === "name"
	);
	if (!nameProperty || !ts.isStringLiteralLike(nameProperty.initializer)) return undefined;
	for (let current: ts.Node | undefined = node.parent; current; current = current.parent) {
		if (
			ts.isVariableDeclaration(current) && ts.isIdentifier(current.name) &&
			current.name.text === "BUILTIN_SLASH_COMMANDS"
		) return {
			commandName: nameProperty.initializer.text,
			field: field as "name" | "description" | "argumentHint",
		};
		if (ts.isFunctionLike(current)) return undefined;
	}
	return undefined;
}

function stringTypeKind(type: ts.TypeNode | undefined): "string" | "string-array" | undefined {
	const returnType = type?.getText().replaceAll(" ", "");
	if (returnType === "string") return "string";
	if (returnType === "string[]" || returnType === "readonlystring[]" || returnType === "ReadonlyArray<string>") {
		return "string-array";
	}
	return undefined;
}

function explicitStringReturn(functionLike: ts.FunctionLikeDeclaration | undefined): "string" | "string-array" | undefined {
	return stringTypeKind(functionLike?.type);
}

function inTuiPresentationFunction(relativePath: string, node: ts.Node): boolean {
	if (!relativePath.startsWith("packages/tui/src/components/")) return false;
	return explicitStringReturn(enclosingFunction(node)) === "string-array";
}

function isTypedStringArrayIdentifier(source: ts.SourceFile, node: ts.Identifier): boolean {
	const functionLike = enclosingFunction(node);
	if (!functionLike) return false;
	let typed = false;
	const visit = (current: ts.Node): void => {
		if (typed || current.getStart(source) >= node.getStart(source)) return;
		if (current !== functionLike && ts.isFunctionLike(current)) return;
		if (
			(ts.isVariableDeclaration(current) || ts.isParameter(current)) &&
			ts.isIdentifier(current.name) && current.name.text === node.text &&
			stringTypeKind(current.type) === "string-array"
		) typed = true;
		ts.forEachChild(current, visit);
	};
	visit(functionLike);
	return typed;
}

function inspect(source: ts.SourceFile, node: ts.Node): void {
	const relativePath = path.relative(baselineRoot, source.fileName).replaceAll(path.sep, "/");
	if (ts.isCallExpression(node)) {
		const name = calledName(node.expression);
		const target = node.expression.getText(source);
		if (name === "fg" || name === "bg") {
			// Style wrappers are decoded only inside a typed presentation sink.
		} else if (terminalWriteTarget(target)) {
			const channel = terminalWriteChannel(source, node.arguments[0]);
			addVisibleArgument(
				source, node.arguments[0], `output:${target}`, channel, 100,
				channel === "printable-visible" && Boolean(node.arguments[0] && !ts.isStringLiteralLike(node.arguments[0]) && !ts.isTemplateExpression(node.arguments[0])),
			);
		} else if (directPrintableOutputs.has(target)) {
			const channel = terminalWriteChannel(source, node.arguments[0]);
			for (const argument of node.arguments) addVisibleArgument(source, argument, `output:${target}`, channel, 100);
		} else if (name && callSinkContracts.has(name)) {
			const contract = callSinkContracts.get(name)!;
			for (const position of contract.argumentPositions) {
				addVisibleArgument(source, node.arguments[position], `call:${name}`, contract.channel, 100);
			}
		} else if (
			name === "push" && ts.isPropertyAccessExpression(node.expression) &&
			ts.isIdentifier(node.expression.expression) &&
			inTuiPresentationFunction(relativePath, node) &&
			isTypedStringArrayIdentifier(source, node.expression.expression)
		) {
			for (const argument of node.arguments) {
				addVisibleArgument(source, argument, "typed-render-array-push", "printable-visible", 95);
			}
		}
	} else if (ts.isNewExpression(node)) {
		const name = calledName(node.expression);
		if (name && textConstructors.has(name)) {
			addCandidate(source, node.arguments?.[0], `new:${name}`, "printable-visible", 100);
		} else if (name && constructorArgumentPositions.has(name)) {
			for (const position of constructorArgumentPositions.get(name)!) {
				addVisibleArgument(source, node.arguments?.[position], `new:${name}`, "printable-visible", 100);
			}
		}
	} else if (ts.isPropertyAssignment(node)) {
		const name = node.name.getText(source).replace(/^['"]|['"]$/g, "");
		const slashMetadata = relativePath.endsWith("/core/slash-commands.ts")
			? builtinSlashCommandMetadata(source, node)
			: undefined;
		if (slashMetadata) {
			addCandidate(source, node.initializer, `slash-command:${name}`, "printable-visible", 90, slashMetadata);
		}
	} else if (
		ts.isVariableDeclaration(node) && ts.isIdentifier(node.name) && node.initializer &&
		relativePath.endsWith("/interactive-mode.ts") &&
		enclosingFunctionName(node, source) === "showLoginAuthTypeSelector"
	) {
		const field = node.name.text === "title" ? "title"
			: node.name.text === "subscriptionLabel" || node.name.text === "apiKeyLabel" ? "item"
				: undefined;
		if (field) {
			addCandidate(
				source, node.initializer, `selector-metadata:${node.name.text}`, "printable-visible", 90,
				{ surface: "extension-selector", field },
			);
		}
	} else if (ts.isReturnStatement(node) && inTuiPresentationFunction(relativePath, node)) {
		const returnKind = explicitStringReturn(enclosingFunction(node));
		if (!(returnKind === "string-array" && node.expression && ts.isIdentifier(node.expression))) {
			addVisibleArgument(source, node.expression, "typed-render-return", "printable-visible", 80);
		}
	}
	ts.forEachChild(node, (child) => inspect(source, child));
}

type BranchBuild = { conditions: string[]; runtimeChoices: string[]; segments: Segment[] };

type FlowState = BranchBuild & { decisions: Map<string, boolean> };

type ControlGuard = {
	id: string;
	condition: string;
	selected: boolean;
	conditionExpression?: ts.Expression;
};

type StringMutation = {
	node: ts.BinaryExpression;
	right: ts.Expression;
	operator: "=" | "+=";
	guards: ControlGuard[];
};

type ArrayPushMutation = {
	right: ts.Expression;
	guards: ControlGuard[];
};

type ChoiceInstrumentation = {
	source: ts.SourceFile;
	expression: ts.Expression;
	choices?: string[];
	conditionChoiceId?: string;
	nestedChoiceIds?: string[];
	persistent?: boolean;
};

const mutationChoiceInstrumentations = new Map<string, ChoiceInstrumentation>();
const unresolvedDataflow = new Map<string, Record<string, unknown>>();
const reachableTypedProducers = new Map<string, {
	source: ts.SourceFile;
	declaration: ts.FunctionLikeDeclaration;
}>();

function styleName(prefix: string, expression: ts.Expression | undefined, source: ts.SourceFile): string {
	if (!expression) return prefix;
	if (ts.isStringLiteralLike(expression)) return `${prefix}:${expression.text}`;
	return `${prefix}:{${expression.getText(source)}}`;
}

function applyAnsiCodes(stylePath: StylePath, codes: string): StylePath {
	let result = [...stylePath];
	for (const rawCode of (codes || "0").split(";")) {
		const code = Number(rawCode || "0");
		if (code === 0) result = [];
		else if (code === 1 && !result.includes("bold")) result.push("bold");
		else if (code === 3 && !result.includes("italic")) result.push("italic");
		else if (code === 4 && !result.includes("underline")) result.push("underline");
		else if (code === 9 && !result.includes("strikethrough")) result.push("strikethrough");
		else if (code === 22) result = result.filter((item) => item !== "bold");
		else if (code === 23) result = result.filter((item) => item !== "italic");
		else if (code === 24) result = result.filter((item) => item !== "underline");
		else if (code === 29) result = result.filter((item) => item !== "strikethrough");
	}
	return result;
}

function literalSegments(text: string, stylePath: StylePath): Segment[] {
	const result: Segment[] = [];
	const pattern = /\x1b\[([0-9;]*)m/g;
	let active = [...stylePath];
	let offset = 0;
	for (const match of text.matchAll(pattern)) {
		if (match.index! > offset) result.push({ kind: "literal", text: text.slice(offset, match.index), stylePath: active });
		active = applyAnsiCodes(active, match[1] ?? "");
		offset = match.index! + match[0].length;
	}
	if (offset < text.length) result.push({ kind: "literal", text: text.slice(offset), stylePath: active });
	return result;
}

function combine(left: BranchBuild[], right: BranchBuild[]): BranchBuild[] {
	const result = new Map<string, BranchBuild>();
	for (const lhs of left) for (const rhs of right) {
		const branch = {
			conditions: [...lhs.conditions, ...rhs.conditions],
			runtimeChoices: [...lhs.runtimeChoices, ...rhs.runtimeChoices],
			segments: [...lhs.segments, ...rhs.segments],
		};
		const observable = JSON.stringify({
			runtimeChoices: branch.runtimeChoices,
			segments: branch.segments.map((segment) => segment.kind === "literal"
				? segment
				: { kind: "slot", stylePath: segment.stylePath }),
		});
		if (!result.has(observable)) result.set(observable, branch);
		if (result.size > 4096) throw new Error("visible-string expression has more than 4096 observable static branches");
	}
	return [...result.values()];
}

function flowScope(source: ts.SourceFile, node: ts.Node): ts.Node {
	let scope: ts.Node = source;
	for (let current: ts.Node | undefined = node.parent; current; current = current.parent) {
		if (ts.isFunctionLike(current)) {
			scope = current;
			break;
		}
	}
	return scope;
}

function localDeclaration(source: ts.SourceFile, node: ts.Node, name: string): ts.VariableDeclaration | undefined {
	const scope = flowScope(source, node);
	let best: ts.VariableDeclaration | undefined;
	const search = (root: ts.Node): void => {
		const pending: ts.Node[] = [root];
		while (pending.length > 0) {
			const current = pending.pop()!;
			if (current !== root && ts.isFunctionLike(current)) continue;
			if (
				ts.isVariableDeclaration(current) && ts.isIdentifier(current.name) &&
				current.name.text === name && current.getStart(source) < node.getStart(source) &&
				(!best || current.getStart(source) > best.getStart(source))
			) best = current;
			ts.forEachChild(current, (child) => { pending.push(child); });
		}
	};
	search(scope);
	if (!best && scope !== source) search(source);
	return best;
}

function choiceId(source: ts.SourceFile, node: ts.Node): string {
	return `C-${digest(`${path.relative(baselineRoot, source.fileName)}\0${node.getStart(source)}\0${node.getEnd()}`).slice(0, 12)}`;
}

function controlGuards(source: ts.SourceFile, node: ts.Node, scope: ts.Node): ControlGuard[] {
	const guards: ControlGuard[] = [];
	let child: ts.Node = node;
	for (let current = node.parent; current && current !== scope; child = current, current = current.parent) {
		if (ts.isIfStatement(current)) {
			const inThen = child.getStart(source) >= current.thenStatement.getStart(source) && child.getEnd() <= current.thenStatement.getEnd();
			const inElse = current.elseStatement && child.getStart(source) >= current.elseStatement.getStart(source) && child.getEnd() <= current.elseStatement.getEnd();
			if (inThen || inElse) {
				guards.push({
					id: choiceId(source, current),
					condition: current.expression.getText(source),
					selected: Boolean(inThen),
					conditionExpression: current.expression,
				});
			}
		} else if (
			ts.isForStatement(current) || ts.isForInStatement(current) || ts.isForOfStatement(current) ||
			ts.isWhileStatement(current) || ts.isDoStatement(current)
		) {
			guards.push({
				id: choiceId(source, current),
				condition: `loop:${current.getStart(source)}`,
				selected: true,
			});
		}
	}
	return guards.reverse();
}

function localStringMutations(
	source: ts.SourceFile,
	use: ts.Node,
	name: string,
	declaration: ts.VariableDeclaration,
): StringMutation[] {
	const scope = flowScope(source, use);
	const result: StringMutation[] = [];
	const pending: ts.Node[] = [scope];
	while (pending.length > 0) {
		const current = pending.pop()!;
		if (current !== scope && ts.isFunctionLike(current)) continue;
		if (current.getStart(source) >= use.getStart(source)) continue;
		if (
			ts.isBinaryExpression(current) && ts.isIdentifier(current.left) && current.left.text === name &&
			current.getStart(source) > declaration.getStart(source) &&
			(current.operatorToken.kind === ts.SyntaxKind.EqualsToken || current.operatorToken.kind === ts.SyntaxKind.PlusEqualsToken)
		) {
			result.push({
				node: current,
				right: current.right,
				operator: current.operatorToken.kind === ts.SyntaxKind.EqualsToken ? "=" : "+=",
				guards: controlGuards(source, current, scope),
			});
		}
		ts.forEachChild(current, (child) => { pending.push(child); });
	}
	return result.sort((left, right) => left.node.getStart(source) - right.node.getStart(source));
}

function uniqueChoices(values: readonly string[]): string[] {
	return values.filter((value, index) => values.indexOf(value) === index);
}

function branchDecisions(runtimeChoices: readonly string[]): Map<string, boolean> {
	return new Map(runtimeChoices.map((choice) => {
		const separator = choice.lastIndexOf(":");
		return [choice.slice(0, separator), choice.slice(separator + 1) === "true"];
	}));
}

function trimSegments(segments: Segment[]): Segment[] {
	const result = segments.map((segment) => ({ ...segment, stylePath: [...segment.stylePath] }));
	for (const segment of result) {
		if (segment.kind === "slot") break;
		segment.text = segment.text.trimStart();
		if (segment.text !== "") break;
	}
	for (const segment of [...result].reverse()) {
		if (segment.kind === "slot") break;
		segment.text = segment.text.trimEnd();
		if (segment.text !== "") break;
	}
	return result.filter((segment) => segment.kind === "slot" || segment.text !== "");
}

function registerMutationInstrumentation(
	source: ts.SourceFile,
	mutation: Pick<StringMutation, "right" | "guards">,
): void {
	if (mutation.guards.length === 0) return;
	const rhsChoices: string[] = [];
	for (const guard of mutation.guards) {
		if (guard.conditionExpression) {
			const key = `${source.fileName}:${guard.conditionExpression.getStart(source)}:${guard.conditionExpression.getEnd()}:condition`;
			mutationChoiceInstrumentations.set(key, {
				source,
				expression: guard.conditionExpression,
				conditionChoiceId: guard.id,
			});
		} else rhsChoices.push(`${guard.id}:${guard.selected}`);
	}
	if (rhsChoices.length > 0) {
		const key = `${source.fileName}:${mutation.right.getStart(source)}:${mutation.right.getEnd()}:value`;
		mutationChoiceInstrumentations.set(key, {
			source,
			expression: mutation.right,
			choices: rhsChoices,
		});
	}
}

function registerPersistentExpressionChoices(source: ts.SourceFile, expression: ts.Expression): void {
	const choiceIds: string[] = [];
	const visit = (node: ts.Node): void => {
		if (
			ts.isConditionalExpression(node) ||
			ts.isBinaryExpression(node) &&
			(node.operatorToken.kind === ts.SyntaxKind.QuestionQuestionToken || node.operatorToken.kind === ts.SyntaxKind.BarBarToken)
		) choiceIds.push(choiceId(source, node));
		ts.forEachChild(node, visit);
	};
	visit(expression);
	if (choiceIds.length === 0) return;
	const key = `${source.fileName}:${expression.getStart(source)}:${expression.getEnd()}:persistent`;
	mutationChoiceInstrumentations.set(key, {
		source,
		expression,
		nestedChoiceIds: uniqueChoices(choiceIds),
		persistent: true,
	});
}

function parseLocalString(
	source: ts.SourceFile,
	use: ts.Identifier,
	stylePath: StylePath,
	resolving: ReadonlySet<string>,
	resolveInRoot: boolean,
): BranchBuild[] | undefined {
	const declaration = localDeclaration(source, use, use.text);
	if (!declaration?.initializer) return undefined;
	const key = `${use.text}:${declaration.getStart(source)}`;
	if (resolving.has(key)) return undefined;
	const nestedResolving = new Set([...resolving, key]);
	registerPersistentExpressionChoices(source, declaration.initializer);
	let states: FlowState[] = parseExpression(
		source, declaration.initializer, stylePath, nestedResolving, resolveInRoot,
	).map((branch) => ({
		...branch,
		decisions: branchDecisions(branch.runtimeChoices),
	}));
	const mutations = localStringMutations(source, use, use.text, declaration);
	for (const mutation of mutations) {
		registerMutationInstrumentation(source, mutation);
		const next: FlowState[] = [];
		for (const state of states) {
			let applicable: FlowState[] = [state];
			const skipped: FlowState[] = [];
			for (const guard of mutation.guards) {
				const guarded: FlowState[] = [];
				for (const candidate of applicable) {
					const known = candidate.decisions.get(guard.id);
					if (known === guard.selected) {
						guarded.push(candidate);
					} else if (known !== undefined) {
						skipped.push(candidate);
					} else {
						const applies = { ...candidate, decisions: new Map(candidate.decisions) };
						applies.decisions.set(guard.id, guard.selected);
						if (guard.conditionExpression || guard.selected) {
							applies.runtimeChoices = uniqueChoices([
								...applies.runtimeChoices,
								`${guard.id}:${guard.selected}`,
							]);
						}
						applies.conditions = [
							...applies.conditions,
							guard.selected ? guard.condition : `!(${guard.condition})`,
						];
						guarded.push(applies);
						const misses = { ...candidate, decisions: new Map(candidate.decisions) };
						misses.decisions.set(guard.id, !guard.selected);
						if (guard.conditionExpression) {
							misses.runtimeChoices = uniqueChoices([
								...misses.runtimeChoices,
								`${guard.id}:${!guard.selected}`,
							]);
						}
						misses.conditions = [
							...misses.conditions,
							guard.selected ? `!(${guard.condition})` : guard.condition,
						];
						skipped.push(misses);
					}
				}
				applicable = guarded;
			}
			next.push(...skipped);
			for (const candidate of applicable) {
				const guardIds = new Set(mutation.guards.map((guard) => guard.id));
				const guardChoices = candidate.runtimeChoices.filter((choice) =>
					guardIds.has(choice.slice(0, choice.lastIndexOf(":")))
				);
				for (const rhs of parseExpression(
					source, mutation.right, stylePath, nestedResolving, resolveInRoot,
				)) {
					const combined = mutation.operator === "+="
						? combine([candidate], [rhs])[0]!
						: {
							conditions: [...candidate.conditions, ...rhs.conditions],
							runtimeChoices: rhs.runtimeChoices,
							segments: rhs.segments,
						};
					next.push({
						...combined,
						runtimeChoices: uniqueChoices([
							...(mutation.operator === "+=" ? candidate.runtimeChoices : []),
							...guardChoices,
							...rhs.runtimeChoices,
						]),
						decisions: new Map([
							...candidate.decisions,
							...branchDecisions(rhs.runtimeChoices),
						]),
					});
				}
			}
		}
		states = next;
		if (states.length > 4096) {
			const relativePath = path.relative(baselineRoot, source.fileName).replaceAll(path.sep, "/");
			const position = source.getLineAndCharacterOfPosition(use.getStart(source));
			unresolvedDataflow.set(`${relativePath}:${use.getStart(source)}:${use.text}`, {
				path: relativePath,
				line: position.line + 1,
				column: position.character + 1,
				expression: use.text,
				reason: "same-function branch product exceeds the explicit 4096-branch static bound; retained as an opaque runtime slot",
			});
			return undefined;
		}
	}
	return states.map(({ decisions: _decisions, ...branch }) => branch);
}

function localStringArrayPushes(
	source: ts.SourceFile,
	use: ts.Node,
	name: string,
	declaration: ts.VariableDeclaration,
): ArrayPushMutation[] {
	const scope = flowScope(source, use);
	const result: ArrayPushMutation[] = [];
	const pending: ts.Node[] = [scope];
	while (pending.length > 0) {
		const current = pending.pop()!;
		if (current !== scope && ts.isFunctionLike(current)) continue;
		if (current.getStart(source) >= use.getStart(source)) continue;
		if (
			ts.isCallExpression(current) && ts.isPropertyAccessExpression(current.expression) &&
			current.expression.name.text === "push" && ts.isIdentifier(current.expression.expression) &&
			current.expression.expression.text === name && current.getStart(source) > declaration.getStart(source)
		) {
			for (const argument of current.arguments) {
				result.push({ right: argument, guards: controlGuards(source, current, scope) });
			}
		}
		ts.forEachChild(current, (child) => { pending.push(child); });
	}
	return result.sort((left, right) => left.right.getStart(source) - right.right.getStart(source));
}

function parseLocalStringArray(
	source: ts.SourceFile,
	use: ts.Identifier,
	delimiter: BranchBuild[],
	stylePath: StylePath,
	resolving: ReadonlySet<string>,
	resolveInRoot: boolean,
): BranchBuild[] | undefined {
	const declaration = localDeclaration(source, use, use.text);
	if (!declaration?.initializer) return undefined;
	if (stringTypeKind(declaration.type) !== "string-array" && !ts.isArrayLiteralExpression(declaration.initializer)) {
		return undefined;
	}
	const key = `array:${use.text}:${declaration.getStart(source)}`;
	if (resolving.has(key)) return undefined;
	const nestedResolving = new Set([...resolving, key]);
	registerPersistentExpressionChoices(source, declaration.initializer);
	let states: FlowState[] = [{ conditions: [], runtimeChoices: [], segments: [], decisions: new Map() }];
	if (ts.isArrayLiteralExpression(declaration.initializer)) {
		for (const element of declaration.initializer.elements) {
			if (!ts.isExpression(element)) continue;
			const value = parseExpression(source, element, stylePath, nestedResolving, resolveInRoot);
			states = combine(states, states.some((state) => state.segments.length > 0) ? combine(delimiter, value) : value)
				.map((branch) => ({ ...branch, decisions: branchDecisions(branch.runtimeChoices) }));
		}
	}
	for (const mutation of localStringArrayPushes(source, use, use.text, declaration)) {
		registerMutationInstrumentation(source, mutation);
		const next: FlowState[] = [];
		for (const state of states) {
			const conflicting = mutation.guards.some((guard) => {
				const known = state.decisions.get(guard.id);
				return known !== undefined && known !== guard.selected;
			});
			if (conflicting) {
				next.push(state);
				continue;
			}
			const unknownGuards = mutation.guards.filter((guard) => !state.decisions.has(guard.id));
			{
				const appliedDecisions = new Map(state.decisions);
				for (const guard of mutation.guards) appliedDecisions.set(guard.id, guard.selected);
				const choices = mutation.guards
					.filter((guard) => guard.conditionExpression || guard.selected)
					.map((guard) => `${guard.id}:${guard.selected}`);
				const values = parseExpression(source, mutation.right, stylePath, nestedResolving, resolveInRoot);
				const appended = state.segments.length > 0 ? combine(delimiter, values) : values;
				for (const branch of combine([state], appended)) {
					next.push({
						...branch,
						conditions: [
							...state.conditions,
							...unknownGuards.map((guard) => guard.selected ? guard.condition : `!(${guard.condition})`),
							...branch.conditions.slice(state.conditions.length),
						],
						runtimeChoices: uniqueChoices([...state.runtimeChoices, ...choices, ...branch.runtimeChoices]),
						decisions: appliedDecisions,
					});
				}
			}
			if (unknownGuards.length > 0) {
				const skippedDecisions = new Map(state.decisions);
				const guard = unknownGuards[0]!;
				skippedDecisions.set(guard.id, !guard.selected);
				next.push({
					...state,
					conditions: [...state.conditions, guard.selected ? `!(${guard.condition})` : guard.condition],
					runtimeChoices: guard.conditionExpression
						? uniqueChoices([...state.runtimeChoices, `${guard.id}:${!guard.selected}`])
						: state.runtimeChoices,
					decisions: skippedDecisions,
				});
			}
		}
		states = next;
		if (states.length > 4096) {
			recordUnresolvedProducer(source, use, use.text, "string-array branch product exceeds 4096");
			return undefined;
		}
	}
	return states.map(({ decisions: _decisions, ...branch }) => branch);
}

function sourceFileForModule(source: ts.SourceFile, specifier: string): ts.SourceFile | undefined {
	if (!specifier.startsWith(".")) return undefined;
	const base = path.resolve(path.dirname(source.fileName), specifier);
	const candidates = [base, `${base}.ts`, `${base}.tsx`, `${base}.mts`, `${base}.cts`, path.join(base, "index.ts")];
	return sourceFiles.find((candidate) => candidates.includes(path.resolve(candidate.fileName)));
}

function topLevelCallable(source: ts.SourceFile, name: string): ts.FunctionLikeDeclaration | undefined {
	for (const statement of source.statements) {
		if (ts.isFunctionDeclaration(statement) && statement.name?.text === name) return statement;
		if (ts.isVariableStatement(statement)) {
			for (const declaration of statement.declarationList.declarations) {
				if (
					ts.isIdentifier(declaration.name) && declaration.name.text === name && declaration.initializer &&
					(ts.isArrowFunction(declaration.initializer) || ts.isFunctionExpression(declaration.initializer))
				) return declaration.initializer;
			}
		}
	}
}

function resolveCallable(source: ts.SourceFile, call: ts.CallExpression): { source: ts.SourceFile; declaration: ts.FunctionLikeDeclaration } | undefined {
	const callee = call.expression;
	if (ts.isIdentifier(callee)) {
		const local = topLevelCallable(source, callee.text);
		if (local) return { source, declaration: local };
		for (const statement of source.statements) {
			if (!ts.isImportDeclaration(statement) || !ts.isStringLiteral(statement.moduleSpecifier)) continue;
			const target = sourceFileForModule(source, statement.moduleSpecifier.text);
			if (!target) continue;
			const clause = statement.importClause;
			if (clause?.name?.text === callee.text) {
				const declaration = topLevelCallable(target, "default");
				if (declaration) return { source: target, declaration };
			}
			if (clause?.namedBindings && ts.isNamedImports(clause.namedBindings)) {
				const binding = clause.namedBindings.elements.find((element) => element.name.text === callee.text);
				if (binding) {
					const declaration = topLevelCallable(target, binding.propertyName?.text ?? binding.name.text);
					if (declaration) return { source: target, declaration };
				}
			}
		}
	}
	if (ts.isPropertyAccessExpression(call.expression) && call.expression.expression.kind === ts.SyntaxKind.ThisKeyword) {
		const name = call.expression.name.text;
		for (let current: ts.Node | undefined = call.parent; current; current = current.parent) {
			if (ts.isClassDeclaration(current)) {
				const member = current.members.find((value): value is ts.MethodDeclaration =>
					ts.isMethodDeclaration(value) && value.name.getText(source) === name
				);
				if (member) return { source, declaration: member };
				break;
			}
		}
	}
}

function callableReturnExpressions(declaration: ts.FunctionLikeDeclaration): ts.Expression[] {
	if (ts.isArrowFunction(declaration) && !ts.isBlock(declaration.body)) return [declaration.body];
	if (!declaration.body || !ts.isBlock(declaration.body)) return [];
	const result: ts.Expression[] = [];
	const visit = (node: ts.Node): void => {
		if (node !== declaration.body && ts.isFunctionLike(node)) return;
		if (ts.isReturnStatement(node) && node.expression) result.push(node.expression);
		ts.forEachChild(node, visit);
	};
	visit(declaration.body);
	return result;
}

function recordUnresolvedProducer(source: ts.SourceFile, node: ts.Node, expression: string, reason: string): void {
	const relativePath = path.relative(baselineRoot, source.fileName).replaceAll(path.sep, "/");
	const position = source.getLineAndCharacterOfPosition(node.getStart(source));
	unresolvedDataflow.set(`${relativePath}:${node.getStart(source)}:${expression}:${reason}`, {
		path: relativePath,
		line: position.line + 1,
		column: position.character + 1,
		expression,
		reason,
	});
}

function parseClassPropertyString(
	source: ts.SourceFile,
	use: ts.PropertyAccessExpression,
	stylePath: StylePath,
	resolving: ReadonlySet<string>,
	resolveInRoot: boolean,
): BranchBuild[] | undefined {
	if (use.expression.kind !== ts.SyntaxKind.ThisKeyword) return undefined;
	let classDeclaration: ts.ClassDeclaration | undefined;
	for (let current: ts.Node | undefined = use.parent; current; current = current.parent) {
		if (ts.isClassDeclaration(current)) {
			classDeclaration = current;
			break;
		}
	}
	if (!classDeclaration) return undefined;
	const values: ts.Expression[] = [];
	for (const member of classDeclaration.members) {
		if (
			ts.isPropertyDeclaration(member) && member.name.getText(source) === use.name.text &&
			member.initializer
		) values.push(member.initializer);
	}
	const visit = (node: ts.Node): void => {
		if (node !== classDeclaration && ts.isClassLike(node)) return;
		if (
			ts.isBinaryExpression(node) && node.operatorToken.kind === ts.SyntaxKind.EqualsToken &&
			ts.isPropertyAccessExpression(node.left) && node.left.expression.kind === ts.SyntaxKind.ThisKeyword &&
			node.left.name.text === use.name.text && node.getStart(source) < use.getStart(source)
		) values.push(node.right);
		ts.forEachChild(node, visit);
	};
	visit(classDeclaration);
	if (values.length === 0) return undefined;
	return values.flatMap((value) => parseExpression(source, value, stylePath, resolving, resolveInRoot));
}

function parseExpression(
	source: ts.SourceFile,
	node: ts.Expression,
	stylePath: StylePath = [],
	resolving: ReadonlySet<string> = new Set(),
	resolveInRoot = true,
): BranchBuild[] {
	if (ts.isStringLiteralLike(node)) {
		return [{ conditions: [], runtimeChoices: [], segments: literalSegments(node.text, stylePath) }];
	}
	if (ts.isTemplateExpression(node)) {
		let result: BranchBuild[] = [{ conditions: [], runtimeChoices: [], segments: literalSegments(node.head.text, stylePath) }];
		for (const span of node.templateSpans) {
			result = combine(result, parseExpression(source, span.expression, stylePath, resolving, false));
			result = combine(result, [{ conditions: [], runtimeChoices: [], segments: literalSegments(span.literal.text, stylePath) }]);
		}
		return result;
	}
	if (ts.isParenthesizedExpression(node) || ts.isAsExpression(node) || ts.isSatisfiesExpression(node)) {
		return parseExpression(source, node.expression, stylePath, resolving, resolveInRoot);
	}
	if (ts.isIdentifier(node)) {
		const local = parseLocalString(source, node, stylePath, resolving, resolveInRoot);
		if (local) return local;
	}
	if (ts.isPropertyAccessExpression(node)) {
		const property = parseClassPropertyString(source, node, stylePath, resolving, resolveInRoot);
		if (property) return property;
	}
	if (ts.isBinaryExpression(node) && node.operatorToken.kind === ts.SyntaxKind.PlusToken) {
		return combine(
			parseExpression(source, node.left, stylePath, resolving, resolveInRoot),
			parseExpression(source, node.right, stylePath, resolving, resolveInRoot),
		);
	}
	if (
		ts.isBinaryExpression(node) &&
		(node.operatorToken.kind === ts.SyntaxKind.QuestionQuestionToken || node.operatorToken.kind === ts.SyntaxKind.BarBarToken)
	) {
		const condition = node.left.getText(source);
		const choice = choiceId(source, node);
		const selectedCondition = node.operatorToken.kind === ts.SyntaxKind.QuestionQuestionToken
			? `${condition} !== null && ${condition} !== undefined`
			: `Boolean(${condition})`;
		return [
			...parseExpression(source, node.left, stylePath, resolving, resolveInRoot).map((branch) => ({
				...branch,
				conditions: [selectedCondition, ...branch.conditions],
				runtimeChoices: [`${choice}:true`, ...branch.runtimeChoices],
			})),
			...parseExpression(source, node.right, stylePath, resolving, resolveInRoot).map((branch) => ({
				...branch,
				conditions: [`!(${selectedCondition})`, ...branch.conditions],
				runtimeChoices: [`${choice}:false`, ...branch.runtimeChoices],
			})),
		];
	}
	if (ts.isConditionalExpression(node)) {
		const condition = node.condition.getText(source);
		const choice = choiceId(source, node);
		return [
			...parseExpression(source, node.whenTrue, stylePath, resolving, resolveInRoot).map((branch) => ({
				...branch,
				conditions: [condition, ...branch.conditions],
				runtimeChoices: [`${choice}:true`, ...branch.runtimeChoices],
			})),
			...parseExpression(source, node.whenFalse, stylePath, resolving, resolveInRoot).map((branch) => ({
				...branch,
				conditions: [`!(${condition})`, ...branch.conditions],
				runtimeChoices: [`${choice}:false`, ...branch.runtimeChoices],
			})),
		];
	}
	if (ts.isCallExpression(node)) {
		const name = calledName(node.expression);
		if (
			name === "join" && ts.isPropertyAccessExpression(node.expression) &&
			ts.isIdentifier(node.expression.expression)
		) {
			const delimiter = node.arguments[0]
				? parseExpression(source, node.arguments[0], stylePath, resolving, resolveInRoot)
				: [{ conditions: [], runtimeChoices: [], segments: literalSegments(",", stylePath) }];
			const joined = parseLocalStringArray(
				source, node.expression.expression, delimiter, stylePath, resolving, resolveInRoot,
			);
			if (joined) return joined;
		}
		if (
			name === "trim" && ts.isPropertyAccessExpression(node.expression) &&
			node.arguments.length === 0
		) return parseExpression(
			source, node.expression.expression, stylePath, resolving, resolveInRoot,
		).map((branch) => ({
			...branch,
			segments: trimSegments(branch.segments),
		}));
		if ((name === "fg" || name === "bg") && node.arguments[1]) {
			return parseExpression(
				source, node.arguments[1], [...stylePath, styleName(name, node.arguments[0], source)], resolving, resolveInRoot,
			);
		}
		if (name && styleCalls.has(name) && node.arguments[0]) {
			return parseExpression(source, node.arguments[0], [...stylePath, name], resolving, resolveInRoot);
		}
		if (name && tuiThemeValueCalls.has(name) && node.arguments[0]) {
			return parseExpression(
				source, node.arguments[0], [...stylePath, `theme:${name}`], resolving, resolveInRoot,
			);
		}
		if (name === "keyHint" && node.arguments[1]) {
			return combine(
				[{ conditions: [], runtimeChoices: [], segments: [{ kind: "slot", expression: `keyText(${node.arguments[0]?.getText(source) ?? ""})`, stylePath: [...stylePath, "fg:dim"] }] }],
				combine(
					[{ conditions: [], runtimeChoices: [], segments: [{ kind: "literal", text: " ", stylePath: [...stylePath, "fg:muted"] }] }],
					parseExpression(
						source, node.arguments[1], [...stylePath, "fg:muted"], resolving, resolveInRoot,
					),
				),
			);
		}
		if (name === "rawKeyHint" && node.arguments[0] && node.arguments[1]) {
			return combine(
				parseExpression(source, node.arguments[0], [...stylePath, "fg:dim"], resolving, resolveInRoot),
				combine(
					[{ conditions: [], runtimeChoices: [], segments: [{ kind: "literal", text: " ", stylePath: [...stylePath, "fg:muted"] }] }],
					parseExpression(
						source, node.arguments[1], [...stylePath, "fg:muted"], resolving, resolveInRoot,
					),
				),
			);
		}
		const resolved = resolveInRoot ? resolveCallable(source, node) : undefined;
		if (resolved) {
			const key = `call:${resolved.source.fileName}:${resolved.declaration.getStart(resolved.source)}`;
			const returnContract = explicitStringReturn(resolved.declaration);
			if (returnContract) {
				reachableTypedProducers.set(key, resolved);
				return [{
					conditions: [],
					runtimeChoices: [],
					segments: [{
						kind: "slot",
						expression: `typed-producer:${node.getText(source)}`,
						stylePath,
					}],
				}];
			}
			if (resolving.has(key)) {
				recordUnresolvedProducer(
					source, node, node.getText(source),
					"recursive in-root producer lacks an explicit string or string[] return contract",
				);
			} else {
				const returns = callableReturnExpressions(resolved.declaration);
				if (returns.length > 0) {
					return returns.flatMap((value) => parseExpression(
						resolved.source, value, stylePath, new Set([...resolving, key]),
					));
				}
				recordUnresolvedProducer(
					source, node, node.getText(source),
					"in-root string producer has no return expression",
				);
			}
		}
	}
	return [{ conditions: [], runtimeChoices: [], segments: [{ kind: "slot", expression: node.getText(source), stylePath }] }];
}

function normalizeSegments(segments: Segment[]): Segment[] {
	const result: Segment[] = [];
	for (const segment of segments) {
		if (segment.kind === "literal" && segment.text === "") continue;
		const previous = result.at(-1);
		if (
			previous?.kind === "literal" && segment.kind === "literal" &&
			JSON.stringify(previous.stylePath) === JSON.stringify(segment.stylePath)
		) previous.text += segment.text;
		else result.push({ ...segment, stylePath: [...segment.stylePath] });
	}
	return result;
}

function meaningful(branches: BranchBuild[]): boolean {
	return branches.some((branch) => branch.segments.some((segment) => segment.kind === "literal" && segment.text !== ""));
}

function candidateBranches(candidate: Candidate): BranchBuild[] {
	if (candidate.opaqueRuntime) {
		return [{
			conditions: [],
			runtimeChoices: [],
			segments: [{ kind: "slot", expression: candidate.expression.getText(candidate.source), stylePath: [] }],
		}];
	}
	try {
		return parseExpression(candidate.source, candidate.expression);
	} catch (error) {
		throw new Error(
			`visible-string candidate failed at ${path.relative(baselineRoot, candidate.source.fileName)}:${candidate.expression.getStart(candidate.source)}:${candidate.kind}: ${error instanceof Error ? error.message : String(error)}`
		);
	}
}

const sourceFiles: ts.SourceFile[] = [];
const sourceInventory: Array<Record<string, unknown>> = [];
for (const sourceRoot of sourceRoots) {
	for (const filePath of walkFiles(path.join(baselineRoot, sourceRoot)).sort()) {
		const relativePath = path.relative(baselineRoot, filePath).replaceAll(path.sep, "/");
		const bytes = fs.readFileSync(filePath);
		const sha256 = createHash("sha256").update(bytes).digest("hex");
		const extension = path.extname(filePath);
		if (!parsedSourceExtensions.has(extension)) {
			const rule = exactAssetRules.get(relativePath);
			if (!rule) throw new Error(`unclassified presentation source asset: ${relativePath}`);
			const asset: Record<string, unknown> = { path: relativePath, sha256, ...rule };
			if (rule.kind === "terminal-theme") {
				const theme = JSON.parse(bytes.toString("utf8")) as Record<string, unknown>;
				asset.roles = {
					vars: Object.keys((theme.vars ?? {}) as object).sort(),
					colors: Object.keys((theme.colors ?? {}) as object).sort(),
					export: Object.keys((theme.export ?? {}) as object).sort(),
				};
			}
			sourceInventory.push(asset);
			continue;
		}
		sourceInventory.push({ path: relativePath, sha256, kind: "parsed-source" });
		const scriptKind = extension === ".tsx" ? ts.ScriptKind.TSX : ts.ScriptKind.TS;
		const source = ts.createSourceFile(filePath, bytes.toString("utf8"), ts.ScriptTarget.Latest, true, scriptKind);
		sourceFiles.push(source);
		inspect(source, source);
	}
}

function selectCandidates(): Candidate[] {
	const selected: Candidate[] = [];
	for (const source of sourceFiles) {
		const fileCandidates = candidates.filter((candidate) => candidate.source === source);
		const exact = new Map<string, Candidate>();
		for (const candidate of fileCandidates) {
			const key = `${candidate.expression.getStart(source)}:${candidate.expression.getEnd()}`;
			const previous = exact.get(key);
			if (!previous || candidate.priority > previous.priority) exact.set(key, candidate);
		}
		const unique = [...exact.values()];
		for (const candidate of unique) {
			const start = candidate.expression.getStart(source);
			const end = candidate.expression.getEnd();
			if (unique.some((other) => {
				if (other === candidate) return false;
				const otherStart = other.expression.getStart(source);
				const otherEnd = other.expression.getEnd();
				return otherStart <= start && otherEnd >= end && (otherStart < start || otherEnd > end);
			})) continue;
			const branches = candidateBranches(candidate);
			if (meaningful(branches)) selected.push(candidate);
		}
	}
	return selected;
}

const registeredTypedProducers = new Set<string>();
let selected = selectCandidates();
for (;;) {
	const pending = [...reachableTypedProducers.entries()].filter(([key]) => !registeredTypedProducers.has(key));
	if (pending.length === 0) break;
	for (const [key, producer] of pending) {
		registeredTypedProducers.add(key);
		for (const expression of callableReturnExpressions(producer.declaration)) {
			addCandidate(
				producer.source,
				expression,
				"typed-string-producer-return",
				"printable-visible",
				75,
			);
		}
	}
	selected = selectCandidates();
}

const entries: Entry[] = selected
	.sort((left, right) => left.source.fileName.localeCompare(right.source.fileName) || left.expression.getStart(left.source) - right.expression.getStart(right.source))
	.flatMap((candidate): Entry[] => {
		const source = candidate.source;
		const start = candidate.expression.getStart(source);
		const end = candidate.expression.getEnd();
		const nodeText = source.text.slice(start, end);
		const nodeSha256 = digest(nodeText);
		const relativePath = path.relative(baselineRoot, source.fileName).replaceAll(path.sep, "/");
		const begin = source.getLineAndCharacterOfPosition(start);
		const finish = source.getLineAndCharacterOfPosition(end);
		const id = `VS-${digest(`${relativePath}\0${start}\0${end}\0${candidate.kind}\0${nodeSha256}`).slice(0, 16)}`;
		const fixedFragments = new Map<string, Extract<Segment, { kind: "literal" }>>();
		for (const branch of candidateBranches(candidate)) {
			for (const segment of branch.segments) {
				if (segment.kind !== "literal" || segment.text === "") continue;
				const key = JSON.stringify({ text: segment.text, stylePath: segment.stylePath });
				if (!fixedFragments.has(key)) fixedFragments.set(key, segment);
			}
		}
		const branches = [...fixedFragments.values()].map((segment) => {
			const obligation = { conditions: [], runtimeChoices: [], segments: [segment] };
			return {
				id: `B-${digest(JSON.stringify(obligation)).slice(0, 12)}`,
				...obligation,
			};
		});
		if (branches.length === 0) return [];
		return [{
			id,
			site: {
				path: relativePath,
				line: begin.line + 1,
				column: begin.character + 1,
				endLine: finish.line + 1,
				endColumn: finish.character + 1,
				start,
				end,
				kind: candidate.kind,
				nodeSha256,
				...(candidate.metadata && { metadata: candidate.metadata }),
			},
			sink: { kind: candidate.kind, channel: candidate.channel },
			branches,
		}];
	});

// Coverage is defined over fixed source fragments, not the Cartesian product
// of every condition that can surround one eventual presentation sink.
mutationChoiceInstrumentations.clear();

if (instrumentRoot) {
	function conditionalChoiceId(source: ts.SourceFile, node: ts.ConditionalExpression): string {
		return choiceId(source, node);
	}

	type Insertion = { text: string; kind: "open" | "close"; span: number };

	function instrumentConditionalChoices(
		source: ts.SourceFile,
		expression: ts.Expression,
		choiceHelper: string,
		logicalChoiceHelper: string,
		allowedChoices: ReadonlySet<string>,
		persistent = false,
	): string {
		const expressionStart = expression.getStart(source);
		const expressionEnd = expression.getEnd();
		const insertions = new Map<number, Insertion[]>();
		const addInsertion = (position: number, insertion: Insertion): void => {
			const values = insertions.get(position) ?? [];
			values.push(insertion);
			insertions.set(position, values);
		};
		const visit = (node: ts.Node): void => {
			if (ts.isConditionalExpression(node)) {
				const choice = conditionalChoiceId(source, node);
				if (allowedChoices.has(choice)) {
					for (const [arm, selected] of [[node.whenTrue, true], [node.whenFalse, false]] as const) {
						const start = arm.getStart(source);
						const end = arm.getEnd();
						const span = end - start;
						addInsertion(start, {
							text: `${choiceHelper}(${JSON.stringify(`${choice}:${selected}`)}, (`,
							kind: "open",
							span,
						});
						addInsertion(end, { text: `), ${persistent})`, kind: "close", span });
					}
				}
			} else if (
				ts.isBinaryExpression(node) &&
				(node.operatorToken.kind === ts.SyntaxKind.QuestionQuestionToken || node.operatorToken.kind === ts.SyntaxKind.BarBarToken)
			) {
				const choice = choiceId(source, node);
				if (allowedChoices.has(choice)) {
					const span = node.getEnd() - node.getStart(source);
					addInsertion(node.left.getStart(source), {
						text: `${logicalChoiceHelper}(${JSON.stringify(choice)}, ${JSON.stringify(node.operatorToken.getText(source))}, () => (`,
						kind: "open",
						span,
					});
					addInsertion(node.left.getEnd(), { text: "), () => (", kind: "close", span });
					addInsertion(node.operatorToken.getStart(source), { text: "/*", kind: "open", span: 0 });
					addInsertion(node.operatorToken.getEnd(), { text: "*/", kind: "close", span: 0 });
					addInsertion(node.right.getEnd(), { text: `), ${persistent})`, kind: "close", span });
				}
			}
			ts.forEachChild(node, visit);
		};
		visit(expression);
		let result = source.text.slice(expressionStart, expressionEnd);
		for (const [position, values] of [...insertions.entries()].sort((left, right) => right[0] - left[0])) {
			const ordered = [...values].sort((left, right) => {
				if (left.kind !== right.kind) return left.kind === "close" ? -1 : 1;
				return left.kind === "open" ? right.span - left.span : left.span - right.span;
			});
			const offset = position - expressionStart;
			result = result.slice(0, offset) + ordered.map((value) => value.text).join("") + result.slice(offset);
		}
		return result;
	}

	const byPath = new Map<string, Entry[]>();
	for (const entry of entries) {
		const values = byPath.get(entry.site.path) ?? [];
		values.push(entry);
		byPath.set(entry.site.path, values);
	}
	const slashMetadataRecords = entries.flatMap((entry) => {
		if (!entry.site.metadata || !("commandName" in entry.site.metadata)) return [];
		const metadata = entry.site.metadata;
		return entry.branches.map((branch) => ({
			commandName: metadata.commandName,
			field: metadata.field,
			parts: branch.segments
				.filter((segment): segment is Extract<Segment, { kind: "literal" }> => segment.kind === "literal" && segment.text !== "")
				.map((segment) => segment.text),
			begin: `\x1b]777;cadr-visible-branch;phase=begin;site=${entry.id};branch=${branch.id}\x07`,
			end: `\x1b]777;cadr-visible-branch;phase=end;site=${entry.id};branch=${branch.id}\x07`,
		}));
	});
	const extensionSelectorMetadataRecords = entries.flatMap((entry) => {
		if (!entry.site.metadata || !("surface" in entry.site.metadata) || entry.site.metadata.surface !== "extension-selector") {
			return [];
		}
		return entry.branches.map((branch) => ({
			field: entry.site.metadata!.field,
			parts: branch.segments
				.filter((segment): segment is Extract<Segment, { kind: "literal" }> => segment.kind === "literal" && segment.text !== "")
				.map((segment) => segment.text),
			begin: `\x1b]777;cadr-visible-branch;phase=begin;site=${entry.id};branch=${branch.id}\x07`,
			end: `\x1b]777;cadr-visible-branch;phase=end;site=${entry.id};branch=${branch.id}\x07`,
		}));
	});
	const slashMetadataHelper = `__cadrRenderDiffSlashMetadata_${digest("slash-command-metadata").slice(0, 8)}`;
	const extensionSelectorMetadataHelper = `__cadrRenderDiffExtensionSelectorMetadata_${digest("extension-selector-metadata").slice(0, 8)}`;
	for (const source of sourceFiles) {
		const relativePath = path.relative(baselineRoot, source.fileName).replaceAll(path.sep, "/");
		let text = source.text;
		const fileEntries = byPath.get(relativePath) ?? [];
		if (fileEntries.length > 0) {
			const siteHelper = `__cadrRenderDiffVisibleSite_${digest(relativePath).slice(0, 8)}`;
			const choiceHelper = `__cadrRenderDiffVisibleChoice_${digest(relativePath).slice(0, 8)}`;
			const logicalChoiceHelper = `__cadrRenderDiffVisibleLogicalChoice_${digest(relativePath).slice(0, 8)}`;
			const conditionChoiceHelper = `__cadrRenderDiffVisibleCondition_${digest(relativePath).slice(0, 8)}`;
			const flushHelper = `__cadrRenderDiffFlushVisible_${digest(relativePath).slice(0, 8)}`;
			const installHelper = `__cadrRenderDiffInstallVisibleStreams_${digest(relativePath).slice(0, 8)}`;
			type Replacement = { start: number; end: number; text: string; label: string };
			const replacements: Replacement[] = [];
			for (const entry of fileEntries) {
				if (entry.site.metadata) continue;
				const candidate = selected.find((value) =>
					value.source === source &&
					value.expression.getStart(source) === entry.site.start &&
					value.expression.getEnd() === entry.site.end
				);
				if (!candidate) throw new Error(`missing candidate for visible-string site ${entry.id}`);
				const allowedChoices = new Set(
					entry.branches.flatMap((branch) =>
						branch.runtimeChoices.map((choice) => choice.slice(0, choice.lastIndexOf(":")))
					)
				);
				let original = instrumentConditionalChoices(
					source, candidate.expression, choiceHelper, logicalChoiceHelper, allowedChoices,
				);
				if (
					relativePath === "packages/tui/src/components/select-list.ts" &&
					ts.isCallExpression(candidate.expression) &&
					candidate.expression.expression.getText(source) === "this.renderItem"
				) original = `${slashMetadataHelper}(${candidate.expression.arguments[0]?.getText(source) ?? "item"}, (${original}))`;
		if (relativePath.endsWith("/components/extension-selector.ts")) {
					if (original.includes("title") && entry.site.kind === "new:Text") {
						original = `${extensionSelectorMetadataHelper}("title", (${original}))`;
					} else if (original === "text" && entry.site.kind === "new:Text") {
						original = `${extensionSelectorMetadataHelper}("item", (${original}))`;
					}
				}
				const branchTable = entry.branches.map((branch) => [
					branch.runtimeChoices.join(","),
					branch.id,
					branch.segments.filter((segment) => segment.kind === "literal" && segment.text !== "").map((segment) => (segment as Extract<Segment, { kind: "literal" }>).text),
				]);
				const instrumented = `${siteHelper}(${JSON.stringify(entry.id)}, ${JSON.stringify(branchTable)}, (${original}))`;
				replacements.push({
					start: entry.site.start,
					end: entry.site.end,
					text: candidate.kind.startsWith("output:")
						? `${flushHelper}(${instrumented})`
						: instrumented,
					label: entry.id,
				});
			}
			if (relativePath === "packages/tui/src/components/select-list.ts") {
				const visitRenderItem = (node: ts.Node): void => {
					if (
						ts.isCallExpression(node) &&
						node.expression.getText(source) === "this.renderItem" &&
						node.arguments[0]
					) replacements.push({
						start: node.getStart(source),
						end: node.getEnd(),
						text: `${slashMetadataHelper}(${node.arguments[0].getText(source)}, (${node.getText(source)}))`,
						label: "slash-command-metadata-render-seam",
					});
					ts.forEachChild(node, visitRenderItem);
				};
				visitRenderItem(source);
			}
			if (relativePath.endsWith("/components/extension-selector.ts")) {
				const visitExtensionText = (node: ts.Node): void => {
					if (ts.isNewExpression(node) && calledName(node.expression) === "Text") {
						const value = node.arguments?.[0];
						let field: "title" | "item" | undefined;
						if (value && ts.isIdentifier(value) && value.text === "text") field = "item";
						if (value) {
							const visitValue = (current: ts.Node): void => {
								if (ts.isIdentifier(current) && current.text === "title") field = "title";
								ts.forEachChild(current, visitValue);
							};
							visitValue(value);
						}
						if (value && field) {
							if (replacements.some((replacement) =>
								replacement.start <= value.getStart(source) && replacement.end >= value.getEnd()
							)) return;
							replacements.push({
								start: value.getStart(source),
								end: value.getEnd(),
								text: `${extensionSelectorMetadataHelper}(${JSON.stringify(field)}, (${value.getText(source)}))`,
								label: `extension-selector-${field}-render-seam`,
							});
						}
					}
					ts.forEachChild(node, visitExtensionText);
				};
				visitExtensionText(source);
			}
			for (const instrumentation of mutationChoiceInstrumentations.values()) {
				if (instrumentation.source !== source) continue;
				let wrapped = instrumentation.expression.getText(source);
				if (instrumentation.nestedChoiceIds) {
					wrapped = instrumentConditionalChoices(
						source,
						instrumentation.expression,
						choiceHelper,
						logicalChoiceHelper,
						new Set(instrumentation.nestedChoiceIds),
						instrumentation.persistent,
					);
				} else if (instrumentation.conditionChoiceId) {
					wrapped = `${conditionChoiceHelper}(${JSON.stringify(instrumentation.conditionChoiceId)}, (${wrapped}))`;
				} else for (const choice of instrumentation.choices ?? []) {
					wrapped = `${choiceHelper}(${JSON.stringify(choice)}, (${wrapped}))`;
				}
				replacements.push({
					start: instrumentation.expression.getStart(source),
					end: instrumentation.expression.getEnd(),
					text: wrapped,
					label: instrumentation.conditionChoiceId ?? instrumentation.nestedChoiceIds?.join(",") ?? instrumentation.choices?.join(",") ?? "choice",
				});
			}
			for (let index = 0; index < replacements.length; index++) {
				for (let otherIndex = index + 1; otherIndex < replacements.length; otherIndex++) {
					const left = replacements[index]!;
					const right = replacements[otherIndex]!;
					if (left.start < right.end && right.start < left.end) {
						throw new Error(`overlapping visible-string instrumentation: ${left.label} and ${right.label}`);
					}
				}
			}
			for (const replacement of replacements.sort((left, right) => right.start - left.start)) {
				text = text.slice(0, replacement.start) + replacement.text + text.slice(replacement.end);
			}
			text += `\nfunction ${choiceHelper}<T>(choice: string, value: T, persistent = false): T {\n` +
				`\tif (process.env.RENDER_DIFF_VISIBLE_SITES !== \"1\") return value;\n` +
				`\tif (persistent) { const separator = choice.lastIndexOf(\":\"); (__cadrRenderDiffPersistentVisibleChoices ??= new Map()).set(choice.slice(0, separator), choice.slice(separator + 1) === \"true\"); }\n` +
				`\telse (__cadrRenderDiffVisibleChoices ??= []).push(choice);\n` +
				`\treturn value;\n` +
				`}\n` +
				`function ${logicalChoiceHelper}<T>(choiceId: string, operator: "||" | "??", left: () => T, right: () => T, persistent = false): T {\n` +
				`\tconst value = left();\n` +
				`\tconst selected = operator === "??" ? value !== null && value !== undefined : Boolean(value);\n` +
				`\tif (process.env.RENDER_DIFF_VISIBLE_SITES === "1") { if (persistent) (__cadrRenderDiffPersistentVisibleChoices ??= new Map()).set(choiceId, selected); else (__cadrRenderDiffVisibleChoices ??= []).push(\`\${choiceId}:\${selected}\`); }\n` +
				`\treturn selected ? value : right();\n` +
				`}\n` +
				`function ${conditionChoiceHelper}<T>(choiceId: string, value: T): T {\n` +
				`\tif (process.env.RENDER_DIFF_VISIBLE_SITES === \"1\") (__cadrRenderDiffVisibleChoices ??= []).push(\`\${choiceId}:\${Boolean(value)}\`);\n` +
				`\treturn value;\n` +
				`}\n` +
				`var __cadrRenderDiffVisibleChoices: string[] | undefined;\n` +
				`var __cadrRenderDiffPersistentVisibleChoices: Map<string, boolean> | undefined;\n` +
				`function ${flushHelper}<T>(value: T): T {\n` +
				`\tif (process.env.RENDER_DIFF_VISIBLE_SITES !== \"1\" || typeof value !== \"string\") return value;\n` +
				`\tconst state = globalThis as typeof globalThis & { __cadrRenderDiffPendingVisibleSpans?: Array<{ key: string; begin: string; end: string; candidates: string[] }>; __cadrRenderDiffPendingVisibleKeys?: Set<string> };\n` +
				`\tconst pending = state.__cadrRenderDiffPendingVisibleSpans ?? [];\n` +
				`\tconst matched: Array<{ begin: string; end: string; start: number; finish: number }> = [];\n` +
				`\tconst remaining: typeof pending = [];\n` +
				`\tfor (const record of pending) {\n` +
				`\t\tconst candidate = record.candidates.find((item) => item !== \"\" && value.includes(item));\n` +
				`\t\tif (!candidate) { remaining.push(record); continue; }\n` +
				`\t\tconst start = value.indexOf(candidate);\n` +
				`\t\tmatched.push({ begin: record.begin, end: record.end, start, finish: start + candidate.length });\n` +
				`\t}\n` +
				`\tconst points = [...new Set(matched.flatMap((record) => [record.start, record.finish]))].sort((left, right) => left - right);\n` +
				`\tlet marked = \"\";\n` +
				`\tlet offset = 0;\n` +
				`\tfor (const point of points) {\n` +
				`\t\tmarked += value.slice(offset, point);\n` +
				`\t\tfor (const record of matched.filter((item) => item.finish === point).sort((left, right) => right.start - left.start)) marked += record.end;\n` +
				`\t\tfor (const record of matched.filter((item) => item.start === point).sort((left, right) => right.finish - left.finish)) marked += record.begin;\n` +
				`\t\toffset = point;\n` +
				`\t}\n` +
				`\tmarked += value.slice(offset);\n` +
				`\tif (value.includes(\"\\x1b[?2026l\")) { state.__cadrRenderDiffPendingVisibleSpans = []; state.__cadrRenderDiffPendingVisibleKeys = new Set(); }\n` +
				`\telse { state.__cadrRenderDiffPendingVisibleSpans = remaining; state.__cadrRenderDiffPendingVisibleKeys = new Set(remaining.map((record) => record.key)); }\n` +
				`\treturn marked as T;\n` +
				`}\n` +
				`function ${installHelper}(): void {\n` +
				`\tconst state = globalThis as typeof globalThis & { __cadrRenderDiffVisibleStreamsInstalled?: boolean; __cadrRenderDiffRawStderrWrite?: (chunk: string) => unknown };\n` +
				`\tif (state.__cadrRenderDiffVisibleStreamsInstalled) return;\n` +
				`\tstate.__cadrRenderDiffVisibleStreamsInstalled = true;\n` +
				`\tfor (const stream of [process.stdout, process.stderr]) {\n` +
				`\t\tconst original = stream.write.bind(stream);\n` +
				`\t\tif (stream === process.stderr) state.__cadrRenderDiffRawStderrWrite = (chunk: string) => original(chunk);\n` +
				`\t\tstream.write = ((chunk: string | Uint8Array, ...args: unknown[]) => original((typeof chunk === \"string\" ? ${flushHelper}(chunk) : chunk) as never, ...(args as []))) as typeof stream.write;\n` +
				`\t}\n` +
				`}\n` +
				`function ${siteHelper}<T>(siteId: string, branches: ReadonlyArray<readonly [string, string, readonly string[]]>, value: T): T {\n` +
				`\tconst visibleSites = process.env.RENDER_DIFF_VISIBLE_SITES === \"1\";\n` +
				`\tconst visibleConstructs = process.env.RENDER_DIFF_VISIBLE_CONSTRUCTS === \"1\";\n` +
				`\tif (!visibleSites && !visibleConstructs) return value;\n` +
				`\tconst values = typeof value === \"string\" ? [value] : Array.isArray(value) && value.every((item) => typeof item === \"string\") ? value : undefined;\n` +
				`\tif (!values || values.length === 0) return value;\n` +
				`\tconst visibleValue = values.join(\"\\n\");\n` +
				`\tconst state = globalThis as typeof globalThis & { __cadrRenderDiffPendingVisibleSpans?: Array<{ key: string; begin: string; end: string; candidates: string[] }>; __cadrRenderDiffPendingVisibleKeys?: Set<string>; __cadrRenderDiffRawStderrWrite?: (chunk: string) => unknown; __cadrRenderDiffConstructMarkers?: Set<string>; __cadrRenderDiffConstructFlushInstalled?: boolean };\n` +
				`\tconst keys = (state.__cadrRenderDiffPendingVisibleKeys ??= new Set());\n` +
				`\tfor (const [, branchId, parts] of branches) {\n` +
				`\t\tlet offset = 0;\n` +
				`\t\tif (!parts.every((part) => { const found = visibleValue.indexOf(part, offset); if (found < 0) return false; offset = found + part.length; return true; })) continue;\n` +
				`\t\tconst key = \`\${siteId}/\${branchId}\`;\n` +
				`\t\tif (keys.has(key)) continue;\n` +
				`\t\tkeys.add(key);\n` +
				`\t\tconst begin = \`\\x1b]777;cadr-visible-branch;phase=begin;site=\${siteId};branch=\${branchId}\\x07\`;\n` +
				`\t\tconst end = \`\\x1b]777;cadr-visible-branch;phase=end;site=\${siteId};branch=\${branchId}\\x07\`;\n` +
				`\t\tif (visibleConstructs) {\n` +
				`\t\t\tconst marker = \`\\x1b]777;cadr-visible-branch;phase=construct;site=\${siteId};branch=\${branchId}\\x07\`;\n` +
				`\t\t\tconst constructPath = process.env.RENDER_DIFF_VISIBLE_CONSTRUCTS_PATH;\n` +
				`\t\t\tif (constructPath) {\n` +
				`\t\t\t\tconst fs = process.getBuiltinModule(\"node:fs\") as { appendFileSync(path: string, data: string): void };\n` +
				`\t\t\t\tfs.appendFileSync(constructPath, marker);\n` +
				`\t\t\t} else (state.__cadrRenderDiffConstructMarkers ??= new Set()).add(marker);\n` +
				`\t\t\tif (!constructPath && !state.__cadrRenderDiffConstructFlushInstalled) {\n` +
				`\t\t\t\tstate.__cadrRenderDiffConstructFlushInstalled = true;\n` +
				`\t\t\t\tconst markers = state.__cadrRenderDiffConstructMarkers!;\n` +
				`\t\t\t\tprocess.once(\"exit\", () => { const write = state.__cadrRenderDiffRawStderrWrite ?? process.stderr.write.bind(process.stderr); for (const marker of markers) write(marker); });\n` +
				`\t\t\t}\n` +
				`\t\t}\n` +
				`\t\tif (visibleSites) (state.__cadrRenderDiffPendingVisibleSpans ??= []).push({ key, begin, end, candidates: [visibleValue, ...values, ...parts].filter((item, index, all) => item !== \"\" && all.indexOf(item) === index).sort((left, right) => right.length - left.length) });\n` +
				`\t}\n` +
				`\tif (visibleSites) ${installHelper}();\n` +
				`\treturn value;\n` +
				`}\n`;
			if (relativePath === "packages/tui/src/components/select-list.ts") {
				text += `\nconst __cadrRenderDiffSlashMetadataRecords = ${JSON.stringify(slashMetadataRecords)} as const;\n` +
					`function ${slashMetadataHelper}(item: SelectItem, value: string): string {\n` +
					`\tconst visibleSites = process.env.RENDER_DIFF_VISIBLE_SITES === \"1\";\n` +
					`\tconst visibleConstructs = process.env.RENDER_DIFF_VISIBLE_CONSTRUCTS === \"1\";\n` +
					`\tif (!visibleSites && !visibleConstructs) return value;\n` +
					`\tconst matched: Array<{ begin: string; end: string }> = [];\n` +
					`\tfor (const record of __cadrRenderDiffSlashMetadataRecords) {\n` +
					`\t\tif (item.label !== record.commandName) continue;\n` +
					`\t\tconst fieldValue = record.field === \"name\" ? item.label : (item.description ?? \"\");\n` +
					`\t\tif (record.parts.every((part) => fieldValue.includes(part))) matched.push(record);\n` +
					`\t}\n` +
					`\tif (visibleConstructs) {\n` +
					`\t\tconst constructPath = process.env.RENDER_DIFF_VISIBLE_CONSTRUCTS_PATH;\n` +
					`\t\tif (constructPath) {\n` +
					`\t\t\tconst fs = process.getBuiltinModule(\"node:fs\") as { appendFileSync(path: string, data: string): void };\n` +
					`\t\t\tfor (const record of matched) fs.appendFileSync(constructPath, record.begin.replace(\"phase=begin\", \"phase=construct\"));\n` +
					`\t\t} else {\n` +
					`\t\t\tconst state = globalThis as typeof globalThis & { __cadrRenderDiffConstructMarkers?: Set<string>; __cadrRenderDiffConstructFlushInstalled?: boolean; __cadrRenderDiffRawStderrWrite?: (chunk: string) => unknown };\n` +
					`\t\t\tconst markers = (state.__cadrRenderDiffConstructMarkers ??= new Set());\n` +
					`\t\t\tfor (const record of matched) markers.add(record.begin.replace(\"phase=begin\", \"phase=construct\"));\n` +
					`\t\t\tif (!state.__cadrRenderDiffConstructFlushInstalled) {\n` +
					`\t\t\t\tstate.__cadrRenderDiffConstructFlushInstalled = true;\n` +
					`\t\t\t\tprocess.once(\"exit\", () => { const write = state.__cadrRenderDiffRawStderrWrite ?? process.stderr.write.bind(process.stderr); for (const marker of markers) write(marker); });\n` +
					`\t\t\t}\n` +
					`\t\t}\n` +
					`\t}\n` +
					`\treturn visibleSites ? matched.reduceRight((result, record) => record.begin + result + record.end, value) : value;\n` +
					`}\n`;
			}
			if (relativePath.endsWith("/components/extension-selector.ts")) {
				text += `\nconst __cadrRenderDiffExtensionSelectorMetadataRecords = ${JSON.stringify(extensionSelectorMetadataRecords)} as const;\n` +
					`function ${extensionSelectorMetadataHelper}(field: "title" | "item", value: string): string {\n` +
					`\tconst visibleSites = process.env.RENDER_DIFF_VISIBLE_SITES === "1";\n` +
					`\tconst visibleConstructs = process.env.RENDER_DIFF_VISIBLE_CONSTRUCTS === "1";\n` +
					`\tif (!visibleSites && !visibleConstructs) return value;\n` +
					`\tconst matched = __cadrRenderDiffExtensionSelectorMetadataRecords.filter((record) => record.field === field && record.parts.every((part) => value.includes(part)));\n` +
					`\tif (visibleConstructs) {\n` +
					`\t\tconst constructPath = process.env.RENDER_DIFF_VISIBLE_CONSTRUCTS_PATH;\n` +
					`\t\tif (constructPath) {\n` +
					`\t\t\tconst fs = process.getBuiltinModule("node:fs") as { appendFileSync(path: string, data: string): void };\n` +
					`\t\t\tfor (const record of matched) fs.appendFileSync(constructPath, record.begin.replace("phase=begin", "phase=construct"));\n` +
					`\t\t} else {\n` +
					`\t\t\tconst state = globalThis as typeof globalThis & { __cadrRenderDiffConstructMarkers?: Set<string>; __cadrRenderDiffConstructFlushInstalled?: boolean; __cadrRenderDiffRawStderrWrite?: (chunk: string) => unknown };\n` +
					`\t\t\tconst markers = (state.__cadrRenderDiffConstructMarkers ??= new Set());\n` +
					`\t\t\tfor (const record of matched) markers.add(record.begin.replace("phase=begin", "phase=construct"));\n` +
					`\t\t\tif (!state.__cadrRenderDiffConstructFlushInstalled) {\n` +
					`\t\t\t\tstate.__cadrRenderDiffConstructFlushInstalled = true;\n` +
					`\t\t\t\tprocess.once("exit", () => { const write = state.__cadrRenderDiffRawStderrWrite ?? process.stderr.write.bind(process.stderr); for (const marker of markers) write(marker); });\n` +
					`\t\t\t}\n` +
					`\t\t}\n` +
					`\t}\n` +
					`\treturn visibleSites ? matched.reduceRight((result, record) => record.begin + result + record.end, value) : value;\n` +
					`}\n`;
			}
		}
		if (relativePath === "packages/coding-agent/src/config.ts") {
			const declaration = "export const isBunBinary =\n";
			if (!text.includes(declaration)) throw new Error("fixed-baseline isBunBinary declaration changed");
			text = text.replace(
				declaration,
				`${declaration}\tprocess.env.RENDER_DIFF_FORCE_BUN_BINARY === "1" ||\n`,
			);
		}
		if (relativePath === "packages/coding-agent/src/cli/session-picker.ts") {
			const signature = "): Promise<string | null> {\n";
			if (!text.includes(signature)) throw new Error("fixed-baseline session picker signature changed");
			text = text.replace(
				signature,
				`${signature}\tif (process.env.RENDER_DIFF_FORCE_NO_SESSION === "1") return null;\n`,
			);
		}
		if (
			relativePath === "packages/coding-agent/src/modes/interactive/interactive-mode.ts" &&
			text.includes("handleShareCommand")
		) {
			const ghProbe = `\t\ttry {\n\t\t\tconst authResult = spawnSync("gh", ["auth", "status"], { encoding: "utf-8" });`;
			if (!text.includes(ghProbe)) throw new Error("fixed-baseline share gh probe changed");
			text = text.replace(
				ghProbe,
				`\t\ttry {\n\t\t\tif (process.env.RENDER_DIFF_FORCE_GH_PROBE_THROW === "1") throw new Error("forced missing gh");\n\t\t\tconst authResult = spawnSync("gh", ["auth", "status"], { encoding: "utf-8" });`,
			);
		}
		const destination = path.join(instrumentRoot, relativePath);
		fs.mkdirSync(path.dirname(destination), { recursive: true });
		const temporary = `${destination}.cadr-visible-${process.pid}`;
		fs.writeFileSync(temporary, text, "utf8");
		fs.renameSync(temporary, destination);
	}
}

process.stdout.write(`${JSON.stringify({
	schemaVersion: 3,
	baselineCommit,
		extractionRules: {
			sourceRoots,
			parsedSourceExtensions: [...parsedSourceExtensions].sort(),
			unit: "one non-empty fixed string fragment, including whitespace-only geometry, from one explicitly contracted presentation sink or reachable typed string-producer return; runtime slots and Cartesian condition combinations are not fixed source strings",
			composition: "template, binary concatenation, same-function string =/+= flow, conditional alternatives, trim, typed render-array push, recursively discovered typed producer returns, module constants, nested styles, and key hints",
			channels: {
				"printable-visible": "text whose contract reaches a user-visible terminal, stdout, or stderr presentation sink",
				"terminal-protocol": "terminal control traffic; inventoried separately and not claimed as printable screen content",
			},
			instrumentation: "per-file fixed-fragment obligations retain the original application value, register pending provenance out of band when that exact fragment is present, and add paired OSC 777 begin/end spans only at stdout/stderr emission when RENDER_DIFF_VISIBLE_SITES=1; printable coverage requires a terminal cell or geometry effect inside the span",
			soundnessBoundary: "closed over declared explicit sink contracts, same-function flow, module constants, and recursively discovered in-root producers with explicit string/string[] return contracts; dynamic slots are not source strings, while any in-root producer without a contract is unresolved dataflow and fails validation; external and dynamically dispatched producers remain opaque runtime values",
		},
	sourceInventory,
	unresolvedDataflow: [...unresolvedDataflow.values()],
	entries,
}, null, 2)}\n`);
