import { getSelfUpdateUnavailableInstruction } from "../src/config.ts";
import { InteractiveMode } from "../src/modes/interactive/interactive-mode.ts";

getSelfUpdateUnavailableInstruction("@earendil-works/pi-coding-agent");

const interactive = Object.create(InteractiveMode.prototype);
Object.assign(interactive, {
	showError() {},
});
await (InteractiveMode.prototype as any).handleShareCommand.call(interactive);
