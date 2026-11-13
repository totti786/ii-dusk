.pragma library

// What an OpenCode chat shows for each call it makes through the shell's tools: one line saying what
// was looked at or changed, and a few lines of detail. Pure, so it can be tested without the shell.

var ICONS = {
    get_environment: "computer", system_get_status: "monitor_heart", system_health: "monitor_heart",
    windows_list: "window", keybinds_search: "keyboard", settings_search: "manage_search", settings_get: "settings",
    settings_set: "tune", read_file: "description", list_directory: "folder_open", read_logs: "receipt_long",
    list_changes: "history", write_file: "edit_document", undo_change: "undo", brightness_set: "brightness_6",
    run_shell_command: "terminal", run_privileged_command: "admin_panel_settings"
};

function clip(text, limit) {
    var value = String(text === undefined || text === null ? "" : text);
    return value.length > limit ? value.slice(0, limit - 1) + "…" : value;
}

function firstLine(text) {
    return String(text || "").split("\n")[0];
}

function parse(text) {
    try { return JSON.parse(text); } catch (e) { return null; }
}

function show(value) {
    return value === null || value === undefined ? "unset" : JSON.stringify(value);
}

/** The words for a call that is under way, from its input alone. */
function running(tool, input) {
    input = input || {};
    switch (tool) {
    case "get_environment": return "Looking at the system";
    case "system_get_status": return "Checking system status";
    case "system_health": return "Checking system health";
    case "windows_list": return "Listing open windows";
    case "keybinds_search": return "Searching keybindings: " + clip(input.query, 60);
    case "settings_search": return "Searching settings: " + clip(input.query, 60);
    case "settings_get": return "Reading settings: " + clip((input.keys || []).join(", "), 80);
    case "settings_set": return "Changing settings";
    case "read_file": return "Reading " + clip(input.path, 80);
    case "list_directory": return "Listing " + clip(input.path, 80);
    case "read_logs": return "Reading the " + clip(input.source, 20) + " log";
    case "list_changes": return "Listing its changes";
    case "write_file": return "Editing " + clip(input.path, 80);
    case "undo_change": return "Undoing " + clip(input.id, 30);
    case "brightness_set": return "Setting brightness to " + clip(input.percent, 6) + "%";
    case "run_shell_command":
    case "run_privileged_command": return "Running " + clip(firstLine(input.command), 80);
    }
    return "Using " + tool;
}

/**
 * The finished card: {title, detail, ok, icon}. `resultText` is the tool's answer, `failure` the error
 * message when the call failed. ok is false when the call failed or changed nothing it was asked to.
 */
function finished(tool, input, resultText, failure) {
    input = input || {};
    var icon = ICONS[tool] || "build";
    var title = running(tool, input);
    if (failure) {
        return { title: title, detail: clip(failure, 300), ok: false, icon: icon };
    }
    var result = parse(resultText);
    if (tool === "settings_set" && result) {
        var applied = result.applied || [];
        var skipped = result.skipped || [];
        var lines = applied.map(function (c) { return c.key + ": " + show(c.previous) + " → " + show(c.value); })
            .concat(skipped.map(function (c) { return c.key + ": not changed (" + clip(c.reason, 90) + ")"; }));
        var heading = applied.length > 0
            ? "Changed " + applied.length + (applied.length === 1 ? " setting" : " settings")
            : "Changed nothing";
        return { title: heading, detail: clip(lines.join("\n"), 600), ok: applied.length > 0, icon: icon };
    }
    if ((tool === "settings_search" || tool === "keybinds_search") && result && result.matches) {
        var found = result.matches.length;
        return { title: title, detail: found === 0 ? "No match" : found + (found === 1 ? " match" : " matches"), ok: true, icon: icon };
    }
    if (tool === "write_file" && resultText) {
        return { title: clip(firstLine(resultText), 140), detail: "Ask to undo it, or open Settings › AI for the change list", ok: true, icon: icon };
    }
    if (tool === "undo_change" || tool === "brightness_set") {
        return { title: clip(firstLine(resultText) || title, 140), detail: "", ok: true, icon: icon };
    }
    if (tool === "run_shell_command" || tool === "run_privileged_command") {
        var body = String(resultText || "");
        var code = /Exit code (\d+)/.exec(body);
        return { title: title, detail: code ? "Exit code " + code[1] : "", ok: !code || code[1] === "0", icon: icon };
    }
    return { title: title, detail: "", ok: true, icon: icon };
}
