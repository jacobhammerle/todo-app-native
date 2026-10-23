// Renders Claude Code's stream-json output as readable CI log lines:
// the agent's narration, each tool call, tool errors, and the final result.
const rl = require("readline").createInterface({ input: process.stdin });
rl.on("line", (line) => {
  let e;
  try {
    e = JSON.parse(line);
  } catch {
    return;
  }
  if (e.type === "assistant" && Array.isArray(e.message?.content)) {
    for (const c of e.message.content) {
      if (c.type === "text" && c.text.trim())
        console.log(`🤖 ${c.text.trim()}`);
      if (c.type === "tool_use") {
        const i = c.input || {};
        const detail =
          i.command || i.file_path || i.pattern || JSON.stringify(i);
        console.log(`  ▶ ${c.name}: ${String(detail).slice(0, 250)}`);
      }
    }
  } else if (e.type === "user" && Array.isArray(e.message?.content)) {
    for (const c of e.message.content) {
      if (c.type === "tool_result" && c.is_error) {
        const txt =
          typeof c.content === "string"
            ? c.content
            : Array.isArray(c.content)
              ? c.content.map((x) => x.text || "").join(" ")
              : "";
        console.log(`  ✗ ${String(txt).slice(0, 300)}`);
      }
    }
  } else if (e.type === "result") {
    console.log(
      `— agent finished: ${e.subtype || ""} (turns: ${e.num_turns ?? "?"})`,
    );
  }
});
