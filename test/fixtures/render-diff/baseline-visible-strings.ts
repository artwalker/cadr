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

type Candidate = {
	source: ts.SourceFile;
	expression: ts.Expression;
	kind: string;
	priority: number;
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
	};
	sink: { kind: string };
	branches: Branch[];
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
const visiblePropertyNames = new Set([
	"description", "help", "hint", "instructions", "label", "message", "placeholder",
	"prompt", "subtitle", "text", "title", "warning",
]);
const visibleCallPattern = /^(?:add|append|display|notify|render|report|set|show|update|write)(?:Error|Help|Hint|Instructions|Label|Message|Notice|Prompt|Status|Text|Title|Warning)/;
const exactVisibleCalls = new Set([
	"showAuth", "showDetails", "showExtensionConfirm", "showExtensionEditor", "showExtensionInput",
	"showExtensionNotify", "showExtensionSelector", "showInfo", "showManualInput", "showProgress",
	"showPrompt", "showWaiting",
]);
const visibleVariablePattern = /(?:DESCRIPTION|ERROR|HELP|HINT|INSTRUCTIONS|LABEL|MESSAGE|PLACEHOLDER|PROMPT|STATUS|TEXT|TITLE|WARNING)$/;
const visibleRenderPattern = /(?:display|format|render|status|summary|text|title)/i;
const nonVisibleReturnFunctions = new Set([
	"getModelSearchText",
	"getModelSelectorSearchText",
]);
const visibleCallArgumentPositions = new Map<string, readonly number[]>([
	["setTextInternal", [0]],
]);
const directOutputs = new Set([
	"process.stdout.write", "process.stderr.write", "console.log", "console.error", "console.warn", "this.output.write",
]);
const styleCalls = new Set(["bold", "dim", "italic", "strikethrough", "underline"]);
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

function addVisibleArgument(source: ts.SourceFile, expression: ts.Expression | undefined, kind: string, priority: number): void {
	if (!expression) return;
	if (ts.isArrayLiteralExpression(expression)) {
		for (const element of expression.elements) {
			if (ts.isExpression(element)) addCandidate(source, element, kind, priority);
		}
		return;
	}
	addCandidate(source, expression, kind, priority);
}

function calledName(expression: ts.Expression): string | undefined {
	if (ts.isIdentifier(expression)) return expression.text;
	if (ts.isPropertyAccessExpression(expression)) return expression.name.text;
	return undefined;
}

function enclosingFunctionName(node: ts.Node): string {
	let current: ts.Node | undefined = node.parent;
	while (current) {
		if (ts.isMethodDeclaration(current) || ts.isFunctionDeclaration(current) || ts.isGetAccessorDeclaration(current)) {
			return current.name?.getText() ?? "";
		}
		current = current.parent;
	}
	return "";
}

function addCandidate(source: ts.SourceFile, expression: ts.Expression | undefined, kind: string, priority: number): void {
	if (expression) candidates.push({ source, expression, kind, priority });
}

function inspect(source: ts.SourceFile, node: ts.Node): void {
	const relativePath = path.relative(baselineRoot, source.fileName).replaceAll(path.sep, "/");
	const interactiveSource = relativePath.includes("/modes/interactive/");
	const tuiSource = relativePath.startsWith("packages/tui/src/");
	const visibleCoreReturnSource =
		relativePath.includes("/core/tools/") ||
		relativePath.endsWith("/core/auth-guidance.ts") ||
		relativePath.endsWith("/core/session-cwd.ts") ||
		relativePath.includes("/utils/image-");
	if (ts.isCallExpression(node)) {
		const name = calledName(node.expression);
		const target = node.expression.getText(source);
		if (name === "fg" || name === "bg") {
			addCandidate(source, node, `theme.${name}`, 10);
		} else if (directOutputs.has(target)) {
			for (const argument of node.arguments) addVisibleArgument(source, argument, `output:${target}`, 100);
		} else if (name && (visibleCallPattern.test(name) || exactVisibleCalls.has(name))) {
			const positions = visibleCallArgumentPositions.get(name) ?? node.arguments.map((_argument, index) => index);
			for (const position of positions) addVisibleArgument(source, node.arguments[position], `call:${name}`, 100);
		}
	} else if (ts.isNewExpression(node)) {
		const name = calledName(node.expression);
		if (name === "Text" || name === "Markdown" || name === "ExpandableText" || name?.endsWith("Status") || name?.endsWith("Loader")) {
			addCandidate(source, node.arguments?.[0], `new:${name}`, 100);
		}
	} else if (ts.isPropertyAssignment(node)) {
		const name = node.name.getText(source).replace(/^['"]|['"]$/g, "");
		if (interactiveSource && visiblePropertyNames.has(name)) {
			addCandidate(source, node.initializer, `property:${name}`, 80);
		}
	} else if (ts.isVariableDeclaration(node) && ts.isIdentifier(node.name)) {
		if (interactiveSource && visibleVariablePattern.test(node.name.text)) {
			addCandidate(source, node.initializer, `variable:${node.name.text}`, 80);
		}
	} else if (
		ts.isReturnStatement(node) &&
		(interactiveSource || tuiSource || visibleCoreReturnSource) &&
		visibleRenderPattern.test(enclosingFunctionName(node)) &&
		!nonVisibleReturnFunctions.has(enclosingFunctionName(node))
	) {
		addCandidate(source, node.expression, "render-return", 80);
	}
	ts.forEachChild(node, (child) => inspect(source, child));
}

type BranchBuild = { conditions: string[]; runtimeChoices: string[]; segments: Segment[] };

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
	const result: BranchBuild[] = [];
	for (const lhs of left) for (const rhs of right) {
		result.push({
			conditions: [...lhs.conditions, ...rhs.conditions],
			runtimeChoices: [...lhs.runtimeChoices, ...rhs.runtimeChoices],
			segments: [...lhs.segments, ...rhs.segments],
		});
		if (result.length > 256) throw new Error("visible-string expression has more than 256 static branches");
	}
	return result;
}

function localInitializer(source: ts.SourceFile, node: ts.Node, name: string): ts.Expression | undefined {
	let scope: ts.Node = source;
	for (let current: ts.Node | undefined = node.parent; current; current = current.parent) {
		if (ts.isFunctionLike(current)) {
			scope = current;
			break;
		}
	}
	let best: ts.VariableDeclaration | undefined;
	const visit = (current: ts.Node): void => {
		if (current !== scope && ts.isFunctionLike(current)) return;
		if (
			ts.isVariableDeclaration(current) && ts.isIdentifier(current.name) &&
			current.name.text === name && current.initializer && current.getStart(source) < node.getStart(source) &&
			(!best || current.getStart(source) > best.getStart(source))
		) best = current;
		ts.forEachChild(current, visit);
	};
	visit(scope);
	return best?.initializer;
}

function parseExpression(
	source: ts.SourceFile,
	node: ts.Expression,
	stylePath: StylePath = [],
	resolving: ReadonlySet<string> = new Set(),
): BranchBuild[] {
	if (ts.isStringLiteralLike(node)) {
		return [{ conditions: [], runtimeChoices: [], segments: literalSegments(node.text, stylePath) }];
	}
	if (ts.isTemplateExpression(node)) {
		let result: BranchBuild[] = [{ conditions: [], runtimeChoices: [], segments: literalSegments(node.head.text, stylePath) }];
		for (const span of node.templateSpans) {
			result = combine(result, parseExpression(source, span.expression, stylePath));
			result = combine(result, [{ conditions: [], runtimeChoices: [], segments: literalSegments(span.literal.text, stylePath) }]);
		}
		return result;
	}
	if (ts.isParenthesizedExpression(node) || ts.isAsExpression(node) || ts.isSatisfiesExpression(node)) {
		return parseExpression(source, node.expression, stylePath, resolving);
	}
	if (ts.isIdentifier(node)) {
		const key = `${node.text}:${node.getStart(source)}`;
		const initializer = resolving.has(key) ? undefined : localInitializer(source, node, node.text);
		if (initializer) return parseExpression(source, initializer, stylePath, new Set([...resolving, key]));
	}
	if (ts.isBinaryExpression(node) && node.operatorToken.kind === ts.SyntaxKind.PlusToken) {
		return combine(parseExpression(source, node.left, stylePath, resolving), parseExpression(source, node.right, stylePath, resolving));
	}
	if (ts.isConditionalExpression(node)) {
		const condition = node.condition.getText(source);
		const choice = `C-${digest(`${path.relative(baselineRoot, source.fileName)}\0${node.getStart(source)}\0${node.getEnd()}`).slice(0, 12)}`;
		return [
			...parseExpression(source, node.whenTrue, stylePath, resolving).map((branch) => ({
				...branch,
				conditions: [condition, ...branch.conditions],
				runtimeChoices: [`${choice}:true`, ...branch.runtimeChoices],
			})),
			...parseExpression(source, node.whenFalse, stylePath, resolving).map((branch) => ({
				...branch,
				conditions: [`!(${condition})`, ...branch.conditions],
				runtimeChoices: [`${choice}:false`, ...branch.runtimeChoices],
			})),
		];
	}
	if (ts.isCallExpression(node)) {
		const name = calledName(node.expression);
		if (
			name === "trim" && ts.isPropertyAccessExpression(node.expression) &&
			node.arguments.length === 0
		) return parseExpression(source, node.expression.expression, stylePath, resolving);
		if ((name === "fg" || name === "bg") && node.arguments[1]) {
			return parseExpression(source, node.arguments[1], [...stylePath, styleName(name, node.arguments[0], source)], resolving);
		}
		if (name && styleCalls.has(name) && node.arguments[0]) {
			return parseExpression(source, node.arguments[0], [...stylePath, name], resolving);
		}
		if (name === "keyHint" && node.arguments[1]) {
			return combine(
				[{ conditions: [], runtimeChoices: [], segments: [{ kind: "slot", expression: `keyText(${node.arguments[0]?.getText(source) ?? ""})`, stylePath: [...stylePath, "fg:dim"] }] }],
				combine(
					[{ conditions: [], runtimeChoices: [], segments: [{ kind: "literal", text: " ", stylePath: [...stylePath, "fg:muted"] }] }],
					parseExpression(source, node.arguments[1], [...stylePath, "fg:muted"], resolving),
				),
			);
		}
		if (name === "rawKeyHint" && node.arguments[0] && node.arguments[1]) {
			return combine(
				parseExpression(source, node.arguments[0], [...stylePath, "fg:dim"], resolving),
				combine(
					[{ conditions: [], runtimeChoices: [], segments: [{ kind: "literal", text: " ", stylePath: [...stylePath, "fg:muted"] }] }],
					parseExpression(source, node.arguments[1], [...stylePath, "fg:muted"], resolving),
				),
			);
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
	return branches.some((branch) => branch.segments.length > 0);
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
		const branches = parseExpression(source, candidate.expression);
		if (meaningful(branches)) selected.push(candidate);
	}
}

const entries: Entry[] = selected
	.sort((left, right) => left.source.fileName.localeCompare(right.source.fileName) || left.expression.getStart(left.source) - right.expression.getStart(right.source))
	.map((candidate) => {
		const source = candidate.source;
		const start = candidate.expression.getStart(source);
		const end = candidate.expression.getEnd();
		const nodeText = source.text.slice(start, end);
		const nodeSha256 = digest(nodeText);
		const relativePath = path.relative(baselineRoot, source.fileName).replaceAll(path.sep, "/");
		const begin = source.getLineAndCharacterOfPosition(start);
		const finish = source.getLineAndCharacterOfPosition(end);
		const id = `VS-${digest(`${relativePath}\0${start}\0${end}\0${candidate.kind}\0${nodeSha256}`).slice(0, 16)}`;
		const branches = parseExpression(source, candidate.expression)
			.map((branch) => ({ ...branch, segments: normalizeSegments(branch.segments) }))
			.filter((branch) => branch.segments.length > 0)
			.map((branch) => ({
				id: `B-${digest(JSON.stringify(branch)).slice(0, 12)}`,
				conditions: branch.conditions,
				runtimeChoices: branch.runtimeChoices,
				segments: branch.segments,
			}));
		return {
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
			},
			sink: { kind: candidate.kind },
			branches,
		};
	});

if (instrumentRoot) {
	function conditionalChoiceId(source: ts.SourceFile, node: ts.ConditionalExpression): string {
		return `C-${digest(`${path.relative(baselineRoot, source.fileName)}\0${node.getStart(source)}\0${node.getEnd()}`).slice(0, 12)}`;
	}

	type Insertion = { text: string; kind: "open" | "close"; span: number };

	function instrumentConditionalChoices(
		source: ts.SourceFile,
		expression: ts.Expression,
		choiceHelper: string,
		allowedChoices: ReadonlySet<string>,
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
						addInsertion(end, { text: "))", kind: "close", span });
					}
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
	for (const source of sourceFiles) {
		const relativePath = path.relative(baselineRoot, source.fileName).replaceAll(path.sep, "/");
		let text = source.text;
		const fileEntries = byPath.get(relativePath) ?? [];
		if (fileEntries.length > 0) {
			const siteHelper = `__cadrRenderDiffVisibleSite_${digest(relativePath).slice(0, 8)}`;
			const choiceHelper = `__cadrRenderDiffVisibleChoice_${digest(relativePath).slice(0, 8)}`;
			for (const entry of [...fileEntries].sort((left, right) => right.site.start - left.site.start)) {
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
				const original = instrumentConditionalChoices(
					source, candidate.expression, choiceHelper, allowedChoices,
				);
				const branchTable = entry.branches.map((branch) => [branch.runtimeChoices.join(","), branch.id]);
				text = text.slice(0, entry.site.start) +
					`${siteHelper}(${JSON.stringify(entry.id)}, ${JSON.stringify(branchTable)}, (${original}))` +
					text.slice(entry.site.end);
			}
			text += `\nfunction ${choiceHelper}<T>(choice: string, value: T): T {\n` +
				`\tif (process.env.RENDER_DIFF_VISIBLE_SITES !== \"1\") return value;\n` +
				`\tconst marker = \`\\x1b]777;cadr-visible-choice=\${choice}\\x07\`;\n` +
				`\tif (typeof value === \"string\") return (\`\${marker}\${value}\` as unknown as T);\n` +
				`\tif (Array.isArray(value) && value.every((item) => typeof item === \"string\") && value.length > 0) return ([marker + value[0], ...value.slice(1)] as unknown as T);\n` +
				`\treturn value;\n` +
				`}\n` +
				`function ${siteHelper}<T>(siteId: string, branches: ReadonlyArray<readonly [string, string]>, value: T): T {\n` +
				`\tif (process.env.RENDER_DIFF_VISIBLE_SITES !== \"1\") return value;\n` +
				`\tconst values = typeof value === \"string\" ? [value] : Array.isArray(value) && value.every((item) => typeof item === \"string\") ? value : undefined;\n` +
				`\tif (!values || values.length === 0) return value;\n` +
				`\tconst choices: string[] = [];\n` +
				`\tconst clean = values.map((item) => item.replace(/\\x1b\\]777;cadr-visible-choice=(C-[0-9a-f]{12}:(?:true|false))\\x07/g, (_marker, choice: string) => { choices.push(choice); return \"\"; }));\n` +
				`\tconst signature = choices.join(\",\");\n` +
				`\tconst branchId = branches.find(([expected]) => expected === signature)?.[1];\n` +
				`\tif (!branchId) return ((typeof value === \"string\" ? clean[0] : clean) as unknown as T);\n` +
				`\tclean[0] = \`\\x1b]777;cadr-visible-branch;site=\${siteId};branch=\${branchId}\\x07\${clean[0]}\`;\n` +
				`\treturn ((typeof value === \"string\" ? clean[0] : clean) as unknown as T);\n` +
				`}\n`;
		}
		const destination = path.join(instrumentRoot, relativePath);
		fs.mkdirSync(path.dirname(destination), { recursive: true });
		const temporary = `${destination}.cadr-visible-${process.pid}`;
		fs.writeFileSync(temporary, text, "utf8");
		fs.renameSync(temporary, destination);
	}
}

process.stdout.write(`${JSON.stringify({
	schemaVersion: 2,
	baselineCommit,
		extractionRules: {
			sourceRoots,
			parsedSourceExtensions: [...parsedSourceExtensions].sort(),
			unit: "one statically enumerated branch of one presentation sink expression",
			composition: "template, binary concatenation, conditional branches, nested styles, and key hints",
			instrumentation: "per-file branch-aware OSC 777 provenance prefixes travel with the value to the terminal only when RENDER_DIFF_VISIBLE_SITES=1",
			soundnessBoundary: "heuristic closure over the declared source roots and syntactic sink rules; this is not a proof over arbitrary data flow or dynamically computed output sinks",
		},
	sourceInventory,
	entries,
}, null, 2)}\n`);
