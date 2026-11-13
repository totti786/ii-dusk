import QtQuick
import qs.modules.common
import qs.modules.common.functions as CF
import "OpencodeActivity.js" as Activity

/**
 * The local OpenCode server, for a chat that answers through it rather than
 * through a model API of its own.
 *
 * The server keeps the conversation. `opencode_bridge.py` maps each shell chat to one
 * OpenCode session and sends only the newest message, so the request body carries
 * the earlier turns for the bridge to check and to replay if it has to start over.
 * The whole turn runs as one script: the bridge prints the session's events one per
 * line, and this strategy reads them the way it reads any other stream.
 *
 * The shell's own tools reach the session through the bridge. OpenCode asks before each
 * call, and that question becomes an approval card in the chat; the card's answer goes
 * back through the bridge.
 */
ApiStrategy {
    readonly property string shellActionPrefix: "ii-shell_"
    readonly property string approvalKind: "opencodeShellApproval"
    readonly property string activityKind: "opencodeToolActivity"
    /** Tool call id → the shell tool it is for, from the stream's input.started events. */
    property var callTools: ({})

    function buildEndpoint(model: AiModel): string {
        return "opencode://local";
    }

    /**
     * The earlier turns, the new message, the instructions, and the names of the shell
     * tools the policy allows for this turn. Built-in OpenCode tools are never offered.
     */
    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>) {
        const turns = Array.from(messages ?? []);
        const last = turns.length > 0 ? turns[turns.length - 1] : null;
        let text = String(last?.rawContent ?? last?.content ?? "");
        const prior = turns.slice(0, -1)
            .filter(turn => turn.role === "user" || turn.role === "assistant")
            .map(turn => ({
                "role": turn.role,
                "text": String(turn.rawContent ?? turn.content ?? "")
            }));
        // Catalog values are "providerID/modelID", as the server names its models.
        const value = String(model.value ?? "");
        const slash = value.indexOf("/");
        // Context and files are for the new message only, and are not part of the text the
        // chat keeps: earlier turns reach the server as they were typed, so the history matches.
        const files = [];
        let context = "";
        for (const file of Array.from(last?.attachments ?? [])) {
            if (file.kind === "context") {
                context += `\n\n${String(file.content ?? "")}`;
                continue;
            }
            files.push({
                "kind": String(file.kind ?? ""),
                "name": String(file.name ?? ""),
                "path": String(file.path ?? ""),
                "mime": String(file.mime ?? "")
            });
        }
        // The wire tools are OpenAI-shaped here; the bridge needs only their names.
        const toolNames = Array.from(tools ?? [])
            .map(tool => String(tool?.function?.name ?? tool?.name ?? ""))
            .filter(name => name.length > 0);
        return {
            "chatId": chatSessionId,
            "prior": prior,
            "text": text,
            "context": context,
            "files": files,
            "instructions": systemPrompt ?? "",
            "tools": toolNames,
            // The user's two choices; the bridge, not this request, decides what each one allows.
            "auto": Config.options?.ai?.tools?.opencodeAuto === true,
            "configWrites": Config.options?.ai?.tools?.opencodeConfigWrites !== false,
            "model": {
                "providerID": slash > 0 ? value.slice(0, slash) : "",
                "modelID": slash > 0 ? value.slice(slash + 1) : value
            }
        };
    }

    /**
     * The request is the bridge run with its arguments, not a curl call: it
     * needs the server's address and password, which only it reads.
     */
    function buildScript(bodyPath: string, statusMarker: string): string {
        const quote = value => `'${CF.StringUtils.shellSingleQuoteEscape(value)}'`;
        return "#!/usr/bin/env bash\n"
            + `exec python3 ${quote(Directories.opencodeBridgeScriptPath)} turn ${quote(bodyPath)} ${quote(statusMarker)} ${quote(Directories.aiOpencodeSessionsPath)}\n`;
    }

    /** Approval cards that are still waiting on the user, set to `state`. A run that ends leaves none waiting. */
    function settleApprovals(message, state: string, summary: string) {
        return Array.from(message?.toolCards ?? [])
            .filter(card => card.kind === approvalKind && card.state === "pending")
            .map(card => ({
                "callId": String(card.callId),
                "state": state,
                "summary": summary
            }));
    }

    function parseResponseLine(line: string, message: AiMessageData) {
        const text = String(line ?? "").trim();
        if (text.length === 0)
            return {};
        let event;
        try {
            event = JSON.parse(text);
        } catch (e) {
            // Not an event. The bridge only prints events, so this is noise to skip.
            console.log("[AI] OpenCode: Could not parse line: ", e);
            return {};
        }
        const data = event.data ?? {};
        switch (event.type) {
        case "session.reasoning.delta":
            appendThought(message, String(data.delta ?? ""));
            return {};
        case "session.text.delta":
            appendAnswer(message, String(data.delta ?? ""));
            return {};
        case "session.step.ended": {
            const tokens = data.tokens ?? {};
            const input = Number(tokens.input ?? 0);
            const output = Number(tokens.output ?? 0);
            return {
                "tokenUsage": {
                    "input": input,
                    "output": output,
                    "total": input + output,
                    "thinking": Number(tokens.reasoning ?? 0),
                    "cost": Number(data.cost ?? -1)
                }
            };
        }
        case "session.tool.input.started": {
            const name = String(data.name ?? "");
            if (name.indexOf(shellActionPrefix) === 0)
                callTools[String(data.id ?? "")] = name.slice(shellActionPrefix.length);
            return {};
        }
        case "session.tool.called": {
            const id = String(data.id ?? "");
            const tool = callTools[id];
            // A call that asked first already has its approval card; this is for the ones that did not.
            const asked = Array.from(message?.toolCards ?? []).some(card => String(card.data?.toolCallId ?? "") === id);
            if (!tool || asked)
                return {};
            return {
                "toolCards": [{
                    "callId": "tool:" + id,
                    "kind": activityKind,
                    "state": "running",
                    "summary": Activity.running(tool, data.input ?? {}),
                    "data": { "tool": tool, "input": data.input ?? {}, "icon": Activity.ICONS[tool] ?? "build", "ok": true, "detail": "" }
                }]
            };
        }
        case "session.tool.success":
        case "session.tool.failed": {
            const id = String(data.id ?? "");
            const tool = callTools[id];
            if (!tool)
                return {};
            const card = Array.from(message?.toolCards ?? []).find(entry => String(entry.callId) === "tool:" + id);
            // An approval card took this call over; its result is not a second card.
            if (!card || card.state === "merged")
                return {};
            const failed = event.type === "session.tool.failed";
            const text = Array.from(data.content ?? []).map(part => String(part?.text ?? "")).join("");
            const done = Activity.finished(tool, card.data?.input ?? {}, text, failed ? String(data.error?.message ?? "It did not work.") : "");
            return {
                "toolCards": [{
                    "callId": "tool:" + id,
                    "state": "done",
                    "summary": done.title,
                    "data": { "tool": tool, "input": card.data?.input ?? {}, "icon": done.icon, "ok": done.ok, "detail": done.detail }
                }]
            };
        }
        case "permission.asked": {
            // Only the shell's own tools get a card. The bridge refuses every other request itself.
            const action = String(data.action ?? "");
            if (action.indexOf(shellActionPrefix) !== 0)
                return {};
            const toolCallId = String(data.source?.id ?? "");
            const cards = [{
                "callId": String(data.id ?? ""),
                "kind": approvalKind,
                "state": "pending",
                "summary": "",
                "data": {
                    "tool": action.slice(shellActionPrefix.length),
                    "input": data.metadata?.input ?? {},
                    "sessionId": String(data.sessionID ?? ""),
                    "requestId": String(data.id ?? ""),
                    "toolCallId": toolCallId
                }
            }];
            // The activity card for this call may have been drawn first. The approval card replaces it.
            if (toolCallId.length > 0)
                cards.push({ "callId": "tool:" + toolCallId, "state": "merged" });
            return { "toolCards": cards };
        }
        case "permission.replied": {
            const refused = String(data.reply ?? "") === "reject";
            return {
                "toolCards": [{
                    "callId": String(data.requestID ?? ""),
                    "state": refused ? "denied" : "done",
                    "summary": refused ? "Not allowed" : "Allowed"
                }]
            };
        }
        case "session.execution.succeeded":
            closeThought(message);
            return { "finished": true, "toolCards": settleApprovals(message, "denied", "Not answered") };
        case "session.execution.failed": {
            closeThought(message);
            const errorText = `**Error**: ${data.error?.message ?? "OpenCode could not finish this answer."}`;
            message.rawContent += errorText;
            message.content += errorText;
            return { "finished": true, "toolCards": settleApprovals(message, "denied", "Not answered") };
        }
        default:
            return {};
        }
    }
}
