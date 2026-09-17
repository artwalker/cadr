import { getSelfUpdateUnavailableInstruction } from "../src/config.ts";
import { shareSession } from "../src/modes/interactive/session-share.ts";

getSelfUpdateUnavailableInstruction("@earendil-works/pi-coding-agent");

// v0.85.1 moved the gh auth probe into shareSession. Drive that catch arm
// under RENDER_DIFF_FORCE_GH_PROBE_THROW so the not-installed string is built.
await shareSession({
	session: {
		sessionManager: {
			getSessionId: () => "construction-share",
			getCwd: () => "/tmp",
			getBranch: () => [],
		},
		state: { systemPrompt: "", tools: [] },
		modelRuntime: {
			getProvider: () => undefined,
		},
		exportToHtml: async () => {},
	} as never,
	ui: { setFocus() {}, requestRender() {} } as never,
	editorContainer: { clear() {}, addChild() {} } as never,
	editor: {} as never,
	showStatus() {},
	showError() {},
});
