import { readFileSync } from "node:fs";
import { createContext, runInContext } from "node:vm";

// Same loader as packages/coding-agent/test/export-html-cjk.test.ts at v1.4.0.
function loadMarkdownParser(html) {
  const sessionData = html.match(/<script id="session-data" type="application\/json">([^<]+)<\/script>/)?.[1];
  const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((match) => match[1]);
  const viewer = scripts.pop();
  if (!sessionData || !viewer) {
    throw new Error("Missing exported session data or viewer script");
  }
  const context = createContext({
    atob,
    TextDecoder,
    URLSearchParams,
    document: {
      getElementById: () => ({ textContent: sessionData }),
      querySelector: () => null,
    },
    window: { location: { search: "" } },
  });
  for (const script of scripts) {
    runInContext(script, context);
  }
  return runInContext(
    viewer.replace(
      "function safeMarkedParse(",
      "return safeMarkedParse; function safeMarkedParse(",
    ),
    context,
  );
}

const html = readFileSync(process.argv[2], "utf8");
const parse = loadMarkdownParser(html);
const inputs = [
  "**这是测试。**后面",
  "**一句话说清：**一台机器",
  "**要点到此为止。**20 小时",
  "字**「引用」**字",
  "*斜体。*后面",
  "**end.**Then next",
];
process.stdout.write(JSON.stringify(inputs.map((text) => parse(text))));
