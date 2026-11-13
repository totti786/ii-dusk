package main

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"os"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/ayn2op/arikawa/v3/discord"
	"github.com/ayn2op/arikawa/v3/gateway"
)

func TestParseSnowflakeRejectsUnsafeValues(t *testing.T) {
	for _, value := range []string{"", "0", "-1", "1.2", "18446744073709551616", "12345678901234567890x"} {
		if _, err := parseSnowflake(value); err == nil {
			t.Errorf("parseSnowflake(%q) accepted an invalid id", value)
		}
	}
	for _, value := range []string{"1", "12345678901234567890"} {
		if parsed, err := parseSnowflake(value); err != nil || parsed == 0 {
			t.Errorf("parseSnowflake(%q) = %v, %v", value, parsed, err)
		}
	}
}

func TestRequestUsesStringSnowflakeFields(t *testing.T) {
	var requestValue request
	if err := requestValue.UnmarshalJSON([]byte("{\"cmd\":\"join\",\"guild_id\":\"12345678901234567890\",\"channel_id\":\"42\"}")); err != nil {
		t.Fatal(err)
	}
	if requestValue.GuildID != "12345678901234567890" || requestValue.ChannelID != "42" {
		t.Fatalf("request ids were not preserved as strings: %#v", requestValue)
	}
}

func TestRequestRejectsNonObjects(t *testing.T) {
	for _, payload := range []string{"null", "[]", "\"connect\"", ""} {
		var value request
		if err := value.UnmarshalJSON([]byte(payload)); err == nil {
			t.Errorf("request accepted non-object JSON %q", payload)
		}
	}
}

func TestRequestedValueSupportsExplicitAndToggleCommands(t *testing.T) {
	value := true
	if got, ok := requestedValue("mute", nil, &value, false); !ok || !got {
		t.Fatalf("explicit mute was not selected: %v, %v", got, ok)
	}
	if got, ok := requestedValue("toggle_mute", nil, nil, true); !ok || got {
		t.Fatalf("toggle mute did not invert current state: %v, %v", got, ok)
	}
	if got, ok := requestedValue("deafen", nil, nil, false); ok || got {
		t.Fatalf("missing explicit deafen value should be absent: %v, %v", got, ok)
	}
}

func TestSafeErrorDoesNotExposeCredentialMaterial(t *testing.T) {
	for _, err := range []error{
		errors.New("request failed: authorization Bearer secret-token"),
		errors.New("X-Super-Properties: secret"),
		errors.New("cookie token=secret"),
	} {
		message := safeError(err)
		if message == err.Error() || message == "" {
			t.Errorf("safeError(%q) did not redact credential material: %q", err, message)
		}
	}
	if got := safeError(errors.New("a useful bounded error")); got != "a useful bounded error" {
		t.Fatalf("safeError changed a safe message: %q", got)
	}
}

func TestSafeDiagnosticMessageDropsRawDetails(t *testing.T) {
	if got := safeDiagnosticMessage("failed to create Opus encoder", slog.LevelError); got != "Microphone audio encoder failed to start." {
		t.Fatalf("known diagnostic = %q", got)
	}
	if got := safeDiagnosticMessage("request failed: token=secret", slog.LevelError); got != "Discordo Voice reported a runtime error." {
		t.Fatalf("unknown diagnostic leaked detail: %q", got)
	}
}

func TestDiagnosticHandlerSanitizesAndMarksFatal(t *testing.T) {
	file, err := os.CreateTemp(t.TempDir(), "diagnostic-")
	if err != nil {
		t.Fatal(err)
	}
	out := newOutput(file)
	fatal := false
	handler := &diagnosticHandler{out: out, fatal: func() { fatal = true }}
	logger := slog.New(handler)
	ctx := context.Background()
	if handler.Enabled(ctx, slog.LevelInfo) {
		t.Fatal("info diagnostics should be filtered")
	}
	if handler.Enabled(ctx, slog.LevelDebug) {
		t.Fatal("debug diagnostics should be filtered")
	}
	logger.Info("ordinary dependency diagnostic")
	logger.Debug("ordinary dependency diagnostic")
	record := slog.NewRecord(time.Now(), slog.LevelError, "failed to create Opus encoder", 0)
	record.AddAttrs(slog.String("token", "secret-token"), slog.String("detail", "private transport detail"))
	if err := handler.Handle(ctx, record); err != nil {
		t.Fatal(err)
	}
	if !fatal {
		t.Fatal("codec diagnostic did not request helper shutdown")
	}
	if err := file.Sync(); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(file.Name())
	if err != nil {
		t.Fatal(err)
	}
	var event map[string]any
	if err := json.Unmarshal(data, &event); err != nil {
		t.Fatalf("diagnostic output is not one JSON event: %v (%s)", err, data)
	}
	if event["type"] != "diagnostic" || event["level"] != "error" ||
		event["message"] != "Microphone audio encoder failed to start." {
		t.Fatalf("unexpected diagnostic event: %#v", event)
	}
	if string(data) == "" ||
		containsAny(string(data), "failed to create Opus encoder", "secret-token", "private transport detail") {
		t.Fatalf("diagnostic leaked raw details: %s", data)
	}
}

func containsAny(value string, needles ...string) bool {
	for _, needle := range needles {
		if strings.Contains(value, needle) {
			return true
		}
	}
	return false
}

func TestSnowflakeStringKeepsWireValuesExact(t *testing.T) {
	channel := discord.Channel{ID: discord.ChannelID(123), GuildID: discord.GuildID(456)}
	if got := snowflakeString(channel.ID); got != "123" {
		t.Fatalf("snowflakeString(channel.ID) = %q", got)
	}
	if got := snowflakeString(channel.GuildID); got != "456" {
		t.Fatalf("snowflakeString(channel.GuildID) = %q", got)
	}
}

func TestOrderGuildsFollowsDiscordSidebarMetadata(t *testing.T) {
	settings := &gateway.UserSettings{
		GuildFolders: []gateway.GuildFolder{
			{ID: 99, GuildIDs: []discord.GuildID{3, 1}},
			// A folder with ID zero and one guild is Discord's representation of
			// an ungrouped server; it still has a meaningful sidebar position.
			{ID: 0, GuildIDs: []discord.GuildID{4}},
		},
		GuildPositions: []discord.GuildID{2, 1, 5, 3},
	}
	guilds := []discord.Guild{
		{ID: 1, Name: "Alpha"},
		{ID: 2, Name: "Bravo"},
		{ID: 3, Name: "Charlie"},
		{ID: 4, Name: "Delta"},
		{ID: 5, Name: "Echo"},
	}
	ordered := orderGuilds(settings, []discord.GuildID{5, 6, 2}, guilds)
	if got := guildIDs(ordered); !reflect.DeepEqual(got, []discord.GuildID{3, 1, 4, 2, 5}) {
		t.Fatalf("sidebar order = %v", got)
	}
}

func TestOrderGuildsUsesReadyAndDeterministicCachedFallback(t *testing.T) {
	guilds := []discord.Guild{
		{ID: 9, Name: "Cached nine"},
		{ID: 2, Name: "Ready two"},
		{ID: 7, Name: "Cached seven"},
		{ID: 4, Name: "Ready four"},
	}
	ordered := orderGuilds(nil, []discord.GuildID{4, 2, 99, 4}, guilds)
	if got := guildIDs(ordered); !reflect.DeepEqual(got, []discord.GuildID{4, 2, 7, 9}) {
		t.Fatalf("ready/fallback order = %v", got)
	}
}

func guildIDs(guilds []discord.Guild) []discord.GuildID {
	ids := make([]discord.GuildID, 0, len(guilds))
	for _, guild := range guilds {
		ids = append(ids, guild.ID)
	}
	return ids
}
