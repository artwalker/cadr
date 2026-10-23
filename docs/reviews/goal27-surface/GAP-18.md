# GAP-18 上游用例对应

范围是 v1.4.0 的 `/export`：JSONL 走 `resolvePath`（`path.resolve`），HTML 走 `normalizePath`（不 `path.resolve`），参数切分走 `getPathCommandArgument`。断言对着 `git show v1.4.0:<path>` 和本机 Node 22.22.0 的 `path.resolve` / `fileURLToPath` / `path.join`。

FiveAM 都在 `test/cadr-cli/session-command-test.lisp`，补全说明在 `test/cadr-cli/goal9-b3-overlay-contract-test.lisp`。

## `packages/coding-agent/test/export-jsonl-share.test.ts`

| 用例 | FiveAM | 状态 |
|---|---|---|
| `adds presentation data without changing conversation IDs or links` 的普通导出没有 `pi.share` | `jsonl-export-rewrites-the-current-branch-and-leaves-the-tree` | 已覆盖 |
| 同一用例里 `exportSessionForShare` 写入的展示条目、会话 id 和 parent 链 | 无 | 范围外：`session-share.ts` 的分享导出，不是 `/export` |

## `packages/coding-agent/test/interactive-mode-import-command.test.ts`

`getPathCommandArgument` 是 `/export` 和 `/import` 共用的。

| 用例 | FiveAM | 状态 |
|---|---|---|
| `strips quotes from /import path arguments` | `path-command-argument-matches-v140-get-path-command-argument` | 新增 |
| `preserves apostrophes in unquoted /import path arguments` | 同上 | 新增 |
| `enforces command token boundaries` | 同上（`/important`、`/exporter`） | 新增 |
| `passes unquoted path to runtimeHost.importFromJsonl` | `session-import` 用加引号的绝对路径走完导入 | 已覆盖。运行时宿主的 mock 接线是导入，不是本行的导出 |
| `passes unquoted apostrophe path to runtimeHost.importFromJsonl unchanged` | 切分在 `path-command-argument-matches-v140-get-path-command-argument` | 新增切分。导入确认框的整段往返不在本行 |
| `shows a non-fatal error when /import path does not exist` | `session-import` 对 `/import /does/not/exist.jsonl` 的失败文本 | 已覆盖 |

## `packages/coding-agent/test/paths.test.ts`

| 用例 | FiveAM | 状态 |
|---|---|---|
| `canonicalizePath` 的五个 `it` | 无 | 范围外：`/export` 不调用 `canonicalizePath`，也不 `realpath` |
| `getCwdRelativePath` 的两个 `it` | 无 | 范围外：`/export` 不调用 |
| `expands only home tilde shortcuts` | `jsonl-export-resolve-path-matches-v140`：`~/cadr-g27g-tilde.jsonl` 写到 home；`~draft.jsonl` 留在进程目录 | 新增 |
| `resolves relative paths against the base directory` | `jsonl-export-relative-path-uses-the-process-directory`、`jsonl-export-drops-dot-segments`。基准是 `process.cwd()`，不是 file URL | 已覆盖 / 新增。`resolvePath` 的第二个参数本身是 file URL 时，`exportSessionToJsonl` 传的是 `process.cwd()`，这条不走 |
| `accepts file URLs` | `jsonl-export-resolve-path-matches-v140`：`file://` 加 `dir/./a%20b.jsonl` 写成带空格的绝对路径，并去掉 `.` | 新增 |
| `throws for invalid file URLs` | 同上，状态行是 `Failed to export session: URI malformed` | 新增。Node 22.22.0 对 `file:///%E0%A4%A` 的消息就是这句 |
| `preserves POSIX absolute paths with literal percent sequences` | 同上，`report%2026.jsonl` 的状态行保留 `%20` | 新增 |
| `does not treat Windows file URL pathname strings as native paths` | 无 | 范围外：该用例在非 win32 上直接 return |
| `normalizeWindowsShellPath` 的两个 `it`，以及 `is applied by normal path handling on Windows` | 无 | 范围外：只在 Windows 上改写 `/mnt`、`/cygdrive` |
| `isLocalPath` 的六个 `it` | 无 | 范围外：`/export` 不调用 `isLocalPath` |

## `packages/coding-agent/test/path-utils.test.ts`

| 用例 | FiveAM | 状态 |
|---|---|---|
| `expandPath`、`resolveToCwd`、`resolveReadPath` 的全部 `it` | 无 | 范围外：这些函数会去掉 `@` 并改写 Unicode 空格。`/export` 调的是 `resolvePath`，默认 `stripAtPrefix` 和 `normalizeUnicodeSpaces` 都是 false。`/export @notes.jsonl` 由 `jsonl-export-keeps-at-prefix-and-unicode-spaces` 锁住保留 `@` |

## HTML 正文

| 文件 | 状态 |
|---|---|
| `export-html-cjk.test.ts` 两个 `it` | 范围外：HTML 正文的强调号，不是路径和状态行 |
| `export-html-skill-block.test.ts` 四个 `it` | 范围外：技能块渲染 |
| `export-html-whitespace.test.ts` 三个 `it` | 范围外：工具输出的空白，不是命令参数里的空白 |
| `export-html-xss.test.ts` 九个 `it` | 范围外：HTML 转义 |
| `theme-export.test.ts` 三个 `it` | 范围外：主题颜色 |
| `suite/regressions/5596-missing-theme-export.test.ts` | 范围外：缺主题时的回退主题 |

## `session-manager/tree-traversal.test.ts`

| 用例 | FiveAM | 状态 |
|---|---|---|
| `getBranch` 的四条：空会话、单条、根到叶、从指定条目往根 | `jsonl-export-rewrites-the-current-branch-and-leaves-the-tree` 重写当前分支的 parentId；`jsonl-export-stops-when-a-parent-is-missing` 在缺父节点时包含该条目后停止且不报错 | 已覆盖导出用到的走法 |
| 同文件其余 `it`（append、branch、fork、叶子指针） | 无 | 范围外：会话树的写入，不是 `/export` |

## 这条差距里写明的行为

| 行为 | FiveAM | 状态 |
|---|---|---|
| `./out.jsonl`、`foo/./bar.jsonl`、`foo/../baz.jsonl` 的状态行去掉 `.` 和 `..` | `jsonl-export-drops-dot-segments` | 新增 |
| 相对 `.jsonl` 写进进程目录；`../link/out.jsonl` 的状态行保留符号链接名 `link` | `jsonl-export-relative-path-uses-the-process-directory` | 已覆盖 |
| 未加引号的 JavaScript 空白（Node 22 的 25 个码位）切开参数，状态行是 `Session exported to: a`，文件是 HTML | `jsonl-export-keeps-at-prefix-and-unicode-spaces` | 新增 |
| 加引号后整段以 `.jsonl` 结尾，JSONL 路径保留该空白 | 同上 | 新增 |
| `/export` 后面是 Tab，或参数以 U+00A0 开头，按 `trimStart` 和 `command + " "` | `path-command-argument-matches-v140-get-path-command-argument` | 新增 |
| 没给路径、`.JSONL`、其它后缀是 HTML；`nested/report.html`、`./page.html`、`../side.html`、`foo/./bar.html` 原样进入状态行，并相对进程目录写入 | `jsonl-export-other-paths-stay-html`；默认文件名 `goal13-default-html-export-name-and-status-match-the-baseline-rule` | 新增 / 已覆盖 |
| 新会话头 version 3；请求时才写 `pi.share`；写失败有 `Failed to export session` | `jsonl-export-default-name-uses-a-fresh-stamp`、`jsonl-export-reports-a-write-failure` | 已覆盖 |
| 补全说明 `Export session (HTML default, or specify path: .html/.jsonl)` | `goal9-b3-builtin-autocomplete-command-contract-matches-baseline` | 已覆盖 |

## 第三次返修记录的三处

| 记录 | 结果 |
|---|---|
| 状态行留下 `.` | `jsonl-export-drops-dot-segments` 对着 Node `path.resolve` |
| 未加引号的 Unicode 空白仍写 JSONL | 25 个空白码位都改成 HTML，状态行是 `a`；加引号才写 JSONL |
| HTML 按会话目录写，状态行只剩文件名 | 相对 HTML 按进程目录写，状态行保留 `normalizePath` 的字符串 |
