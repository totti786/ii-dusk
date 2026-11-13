.pragma library

var LITE = {
    "animations:enabled": 0,
    "decoration:blur:enabled": 0,
    "decoration:shadow:enabled": 0,
    "decoration:dim_inactive": 0,
    "decoration:rounding_power": 2,
    "render:direct_scanout": 1
};

var GAME_MODE = {
    "animations:enabled": 0,
    "decoration:shadow:enabled": 0,
    "decoration:blur:enabled": 0,
    "general:gaps_in": 0,
    "general:gaps_out": 0,
    "general:border_size": 1,
    "decoration:rounding": 0,
    // Irrelevant with rounding 0, but 0 is out of range (min 1, 2 before 0.57)
    "decoration:rounding_power": 2,
    "general:allow_tearing": 1
};

var LITE_KEYS = [
    "animations:enabled",
    "decoration:blur:enabled",
    "decoration:shadow:enabled",
    "decoration:dim_inactive",
    "decoration:rounding_power",
    "render:direct_scanout"
];

var GAME_MODE_KEYS = [
    "animations:enabled",
    "decoration:shadow:enabled",
    "decoration:blur:enabled",
    "general:gaps_in",
    "general:gaps_out",
    "general:border_size",
    "decoration:rounding",
    "decoration:rounding_power",
    "general:allow_tearing"
];

var GAME_MODE_RULE_MARKER = "shell:game-mode-opaque";
var GAME_MODE_RULE = 'hl.window_rule({name="' + GAME_MODE_RULE_MARKER + '",match={class=".*"},'
    + 'opacity="1.0 override 1.0 override 1.0 override",opaque=true})';

function merge(state) {
    state = state || {};
    var result = {};
    if (state.lite) {
        for (var liteKey in LITE)
            result[liteKey] = LITE[liteKey];
    }
    if (state.reduceMotion)
        result["animations:enabled"] = 0;
    if (state.gameMode) {
        for (var gameKey in GAME_MODE)
            result[gameKey] = GAME_MODE[gameKey];
    }
    return result;
}

function plan(state, resetScope, releaseGameMode) {
    state = state || {};
    var set = merge(state);
    var reset = [];
    var seen = Object.create(null);
    var scope = resetScope || [];
    for (var i = 0; i < scope.length; i++) {
        var key = scope[i];
        if (Object.prototype.hasOwnProperty.call(set, key) || Object.prototype.hasOwnProperty.call(seen, key))
            continue;
        seen[key] = true;
        reset.push(key);
    }
    return {
        set: set,
        reset: reset,
        addLines: state.gameMode ? [GAME_MODE_RULE] : [],
        removeMatching: releaseGameMode === true && !state.gameMode ? [GAME_MODE_RULE_MARKER] : []
    };
}
