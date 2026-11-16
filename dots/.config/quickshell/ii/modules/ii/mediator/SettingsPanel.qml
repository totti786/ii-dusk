pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Where mediator's settings are edited: the Jellyfin server, the three library folders,
 * playback speed and the poster key. It reads and writes ~/.config/mediator/config.toml
 * through `mediator config`; only the fields that were changed are sent. The API key is
 * never read back, the field only says whether one is saved.
 */
Item {
    id: root

    signal closeRequested()

    readonly property var s: MediatorService.settings
    readonly property bool hasChanges: [jfUrl, jfUser, jfKey, jfInclude, pathAnime, pathShows, pathMovies,
                                        speed, autoFetch, alClientId, alAuto, alAddMissing,
                                        alRewatch, alComplete, alDates, streamHls, streamStremio, streamPrefer, streamAsk].some(f => f.changed)

    readonly property string statusLine: MediatorService.saveError !== "" ? MediatorService.saveError
        : root.hasChanges ? "Unsaved changes" : "Saved to " + (root.s.path ?? "")

    // Fill the fields from what the CLI reports
    function load(): void {
        const jf = root.s.jellyfin ?? {};
        jfUrl.original = jfUrl.text = jf.url ?? "";
        jfUser.original = jfUser.text = jf.username ?? "";
        jfKey.original = jfKey.text = "";
        jfKey.placeholder = jf.token_set ? "Saved. Type to replace it" : "Paste an API key from the Jellyfin dashboard";
        jfInclude.original = jfInclude.checked = jf.include ?? false;
        const lib = root.s.libraries ?? {};
        pathAnime.original = pathAnime.text = lib.anime ?? "";
        pathShows.original = pathShows.text = lib.shows ?? "";
        pathMovies.original = pathMovies.text = lib.movies ?? "";
        speed.original = speed.text = String(root.s.playback?.speed ?? 1);
        const po = root.s.posters ?? {};
        autoFetch.original = autoFetch.checked = po.auto_fetch ?? true;

        const st = root.s.streaming ?? {};
        streamHls.original = streamHls.checked = st.hls ?? false;
        streamStremio.original = streamStremio.checked = st.stremio ?? true;
        streamPrefer.original = streamPrefer.checked = st.prefer_stremio ?? false;
        streamAsk.original = streamAsk.checked = st.ask_before_torrent ?? true;

        const al = root.s.anilist ?? {};
        alClientId.original = alClientId.text = al.client_id ?? "";
        alToken.original = alToken.text = "";
        alToken.placeholder = al.token_set ? "Saved. Paste a new token or redirected URL to replace it"
            : "Paste token or the full redirected URL";
        alAuto.original = alAuto.checked = al.auto ?? true;
        alAddMissing.original = alAddMissing.checked = al.add_missing ?? false;
        alRewatch.original = alRewatch.checked = al.rewatch ?? false;
        alComplete.original = alComplete.checked = al.complete ?? true;
        alDates.original = alDates.checked = al.dates ?? true;
    }

    function save(): void {
        const p = {};
        if (jfUrl.changed) p["jellyfin.url"] = jfUrl.text;
        if (jfUser.changed) p["jellyfin.username"] = jfUser.text;
        if (jfKey.text !== "") p["jellyfin.token"] = jfKey.text;
        // A new server or user means the saved user id is stale; mediator finds it again
        if (jfUrl.changed || jfUser.changed) p["jellyfin.user_id"] = "";
        if (jfInclude.changed) p["jellyfin.include"] = jfInclude.checked;
        if (pathAnime.changed) p["libraries.anime"] = pathAnime.text;
        if (pathShows.changed) p["libraries.shows"] = pathShows.text;
        if (pathMovies.changed) p["libraries.movies"] = pathMovies.text;
        if (speed.changed) p["playback.speed"] = speed.text;
        if (autoFetch.changed) p["posters.auto_fetch"] = autoFetch.checked;
        if (streamHls.changed) p["streaming.hls"] = streamHls.checked;
        if (streamStremio.changed) p["streaming.stremio"] = streamStremio.checked;
        if (streamPrefer.changed) p["streaming.prefer_stremio"] = streamPrefer.checked;
        if (streamAsk.changed) p["streaming.ask_before_torrent"] = streamAsk.checked;
        if (alClientId.changed) p["anilist.client_id"] = alClientId.text;
        if (alAuto.changed) p["anilist.auto"] = alAuto.checked;
        if (alAddMissing.changed) p["anilist.add_missing"] = alAddMissing.checked;
        if (alRewatch.changed) p["anilist.rewatch"] = alRewatch.checked;
        if (alComplete.changed) p["anilist.complete"] = alComplete.checked;
        if (alDates.changed) p["anilist.dates"] = alDates.checked;
        if (Object.keys(p).length > 0)
            MediatorService.saveSettings(p);
    }

    // Deferred: filling the fields while bindings that read `s` re-evaluate loops them
    onSChanged: Qt.callLater(root.load)
    Component.onCompleted: {
        MediatorService.jellyfinState = "";
        MediatorService.saveError = "";
        MediatorService.loadSettings();
        MediatorService.loadAniListStatus();
        root.load();
        jfUrl.input.forceActiveFocus();
    }

    Keys.onEscapePressed: root.closeRequested()

    Flickable {
        WheelScroll {}
        id: scroller
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: saveBar.top }
        contentWidth: width
        contentHeight: column.implicitHeight + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: column
            width: Math.min(scroller.width, 680)
            x: (scroller.width - width) / 2
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    implicitWidth: backRow.implicitWidth + 24
                    implicitHeight: 34
                    radius: Appearance.rounding.full
                    color: backArea.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
                    RowLayout {
                        id: backRow
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol { text: "arrow_back"; iconSize: 18; color: Appearance.colors.colOnLayer0 }
                        StyledText { text: "Back"; color: Appearance.colors.colOnLayer0 }
                    }
                    MouseArea {
                        id: backArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeRequested()
                    }
                }
                StyledText {
                    text: "Settings"
                    color: Appearance.colors.colOnLayer0
                    font.pixelSize: 30
                    font.weight: Font.DemiBold
                }
            }

            StyledText {
                text: "JELLYFIN"
                color: Appearance.colors.colPrimary
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.letterSpacing: 1.4
                Layout.topMargin: 10
            }
            SettingsField {
                id: jfUrl
                label: "Server URL"
                placeholder: "https://jellyfin.example.com"
                hint: "Include the port if it is not 80 or 443."
            }
            SettingsField {
                id: jfUser
                label: "Username"
                placeholder: "Your Jellyfin user"
                hint: "Used to find your account when you paste an API key."
            }
            SettingsField {
                id: jfKey
                label: "API key"
                secret: true
                hint: "Dashboard → API Keys → +. It is stored in mediator's config, readable only by you."
            }
            SettingsToggle {
                id: jfInclude
                label: "Show Jellyfin in the library"
                hint: "Adds the server's Anime, Shows and Movies next to your local files, tagged Jellyfin."
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: text !== ""
                readonly property int loaded: MediatorService.titles.filter(t => t.source === "jellyfin").length
                text: {
                    if (root.hasChanges)
                        return "";
                    if (jfInclude.original && !(root.s.jellyfin?.configured ?? false))
                        return "Turned on, but the server URL or API key is missing, so nothing is listed.";
                    if (jfInclude.original)
                        return loaded > 0 ? `${loaded} titles from Jellyfin are in your library.`
                            : MediatorService.loading ? "Loading the server's titles…"
                            : "Nothing came back from the server. Test the connection, and check the library names there are Anime, Shows and Movies.";
                    if (MediatorService.jellyfinState === "ok")
                        return "Connected. Turn this on to list the server's titles.";
                    return "";
                }
                color: text.startsWith("Nothing") || text.startsWith("Turned on") ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 14
                Rectangle {
                    implicitWidth: testText.implicitWidth + 36
                    implicitHeight: 38
                    radius: Appearance.rounding.full
                    opacity: root.hasChanges ? 0.5 : 1
                    color: testArea.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
                    StyledText {
                        id: testText
                        anchors.centerIn: parent
                        text: "Test connection"
                        color: Appearance.colors.colOnLayer0
                    }
                    MouseArea {
                        id: testArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !root.hasChanges
                        cursorShape: Qt.PointingHandCursor
                        onClicked: MediatorService.testJellyfin()
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.hasChanges && MediatorService.jellyfinState === "" ? "Save first, then test."
                        : MediatorService.jellyfinMessage
                    color: MediatorService.jellyfinState === "ok" ? Appearance.colors.colPrimary
                         : MediatorService.jellyfinState === "failed" ? Appearance.m3colors.m3error
                         : Appearance.colors.colSubtext
                }
            }

            StyledText {
                text: "LIBRARIES"
                color: Appearance.colors.colPrimary
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.letterSpacing: 1.4
                Layout.topMargin: 18
            }
            SettingsField { id: pathAnime; label: "Anime folder"; placeholder: "~/Videos/Anime" }
            SettingsField { id: pathShows; label: "Shows folder"; placeholder: "~/Videos/Shows" }
            SettingsField { id: pathMovies; label: "Movies folder"; placeholder: "~/Videos/Movies" }

            StyledText {
                text: "PLAYBACK AND POSTERS"
                color: Appearance.colors.colPrimary
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.letterSpacing: 1.4
                Layout.topMargin: 18
            }
            SettingsField {
                id: speed
                label: "Default speed"
                placeholder: "1.0"
                hint: "Per-library speeds in the config file still win."
            }
            SettingsToggle {
                id: autoFetch
                label: "Fetch missing posters automatically"
                hint: "Looks them up online while the browser is open."
            }

            StyledText {
                text: "MOVIE AND SERIES STREAMING"
                color: Appearance.colors.colPrimary
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.letterSpacing: 1.4
                Layout.topMargin: 18
            }
            SettingsToggle {
                id: streamHls
                label: "Direct streams (main source)"
                hint: "Plays an HLS stream straight in mpv: fast, no torrent. Tried first."
            }
            SettingsToggle {
                id: streamStremio
                label: "Stremio torrents"
                hint: "Used when direct streams fail, or on their own if those are off. A stream you pick by hand always wins."
            }
            SettingsToggle {
                id: streamPrefer
                enabled: streamStremio.checked
                opacity: streamStremio.checked ? 1 : 0.45
                label: "Prefer Stremio for higher quality"
                hint: "Tries torrents first and picks the highest resolution with healthy seeders. Slower to start; direct streams become the fallback. Applies to playing and downloading."
            }
            SettingsToggle {
                id: streamAsk
                enabled: streamHls.checked && streamStremio.checked
                opacity: streamHls.checked && streamStremio.checked ? 1 : 0.45
                label: "Ask before switching to a torrent"
                hint: "When a direct stream fails, say so and let you choose a torrent instead of switching on its own."
            }

            StyledText {
                text: "SESSION"
                color: Appearance.colors.colPrimary
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.letterSpacing: 1.4
                Layout.topMargin: 18
            }
            SettingsToggle {
                id: together
                label: "Watch Together (Syncplay)"
                hint: "Plays through Syncplay for this shell session: local files, and streamed movies, shows and anime (at normal speed). A friend needs the same stream to join: local files by name, streams by link."
                checked: MediatorService.watchTogether
                original: MediatorService.watchTogether
                onCheckedChanged: {
                    if (MediatorService.watchTogether !== checked)
                        MediatorService.watchTogether = checked;
                }
            }

            StyledText {
                text: "ANILIST"
                color: Appearance.colors.colPrimary
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.letterSpacing: 1.4
                Layout.topMargin: 18
            }
            StyledText {
                Layout.fillWidth: true
                text: MediatorService.anilistStatus.ok
                    ? `Connected as ${MediatorService.anilistStatus.username || "AniList user"}`
                    : MediatorService.anilistStatus.configured
                        ? "Saved account needs attention"
                        : "Connect an AniList account to sync anime progress and scores."
                color: MediatorService.anilistStatus.ok ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    implicitWidth: consentText.implicitWidth + 34
                    implicitHeight: 38
                    radius: Appearance.rounding.full
                    color: consentArea.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
                    StyledText {
                        id: consentText
                        anchors.centerIn: parent
                        text: "Open AniList consent"
                        color: Appearance.colors.colOnLayer0
                    }
                    MouseArea {
                        id: consentArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: !MediatorService.anilistBusy
                        onClicked: MediatorService.openAniListConsent()
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: MediatorService.anilistBusy && MediatorService.anilistAction === "status"
                        ? "Checking…" : "The browser opens AniList's official authorization page."
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
                }
            }
            SettingsField {
                id: alClientId
                label: "Public client ID (optional)"
                placeholder: "Leave empty to use Mediator's built-in app"
                hint: "Only the public numeric id is needed; the app secret is not used."
            }
            SettingsField {
                id: alToken
                label: "Token or redirected URL"
                secret: true
                hint: "Paste the token or the full URL after consent. It is sent to mediator through stdin and never appears in arguments."
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    implicitWidth: connectText.implicitWidth + 34
                    implicitHeight: 38
                    radius: Appearance.rounding.full
                    opacity: MediatorService.anilistBusy ? 0.45 : 1
                    color: connectArea.containsMouse ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary
                    StyledText {
                        id: connectText
                        anchors.centerIn: parent
                        text: MediatorService.anilistBusy && MediatorService.anilistAction === "login" ? "Connecting…" : "Connect"
                        color: Appearance.colors.colOnPrimary
                        font.weight: Font.Medium
                    }
                    MouseArea {
                        id: connectArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !MediatorService.anilistBusy
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            MediatorService.connectAniList(alToken.text);
                            alToken.text = "";
                        }
                    }
                }
                Rectangle {
                    implicitWidth: logoutText.implicitWidth + 34
                    implicitHeight: 38
                    radius: Appearance.rounding.full
                    visible: MediatorService.anilistStatus.token_set || MediatorService.anilistStatus.configured
                    color: logoutArea.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
                    StyledText { id: logoutText; anchors.centerIn: parent; text: "Disconnect"; color: Appearance.colors.colOnLayer0 }
                    MouseArea {
                        id: logoutArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !MediatorService.anilistBusy
                        cursorShape: Qt.PointingHandCursor
                        onClicked: MediatorService.logoutAniList()
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: MediatorService.anilistError !== "" ? MediatorService.anilistError
                        : MediatorService.anilistMessage
                    color: MediatorService.anilistError !== "" ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    implicitWidth: syncText.implicitWidth + 34
                    implicitHeight: 38
                    radius: Appearance.rounding.full
                    opacity: MediatorService.anilistBusy ? 0.45 : 1
                    color: syncArea.containsMouse ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary
                    StyledText {
                        id: syncText
                        anchors.centerIn: parent
                        text: MediatorService.anilistBusy && MediatorService.anilistAction === "sync-all" ? "Syncing…" : "Sync library"
                        color: Appearance.colors.colOnPrimary
                        font.weight: Font.Medium
                    }
                    MouseArea {
                        id: syncArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !MediatorService.anilistBusy && MediatorService.anilistStatus.ok
                        cursorShape: Qt.PointingHandCursor
                        onClicked: MediatorService.syncAniListAll()
                    }
                }
                Rectangle {
                    implicitWidth: retryText.implicitWidth + 34
                    implicitHeight: 38
                    radius: Appearance.rounding.full
                    opacity: MediatorService.anilistBusy ? 0.45 : 1
                    color: retryArea.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
                    StyledText {
                        id: retryText
                        anchors.centerIn: parent
                        text: MediatorService.anilistBusy && MediatorService.anilistAction === "sync-pending" ? "Retrying…" : "Retry pending"
                        color: Appearance.colors.colOnLayer0
                    }
                    MouseArea {
                        id: retryArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !MediatorService.anilistBusy && MediatorService.anilistStatus.pending > 0
                        cursorShape: Qt.PointingHandCursor
                        onClicked: MediatorService.retryAniList()
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: MediatorService.anilistStatus.pending > 0
                        ? `${MediatorService.anilistStatus.pending} pending update${MediatorService.anilistStatus.pending === 1 ? "" : "s"}`
                        : ""
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
            SettingsToggle {
                id: alAuto
                label: "Sync automatically when anime is marked watched"
                hint: "Failed pushes remain pending so Retry pending can send them later."
            }
            SettingsToggle {
                id: alAddMissing
                label: "Add anime missing from my AniList"
                hint: "When off, only entries already on your list are updated."
            }
            SettingsToggle {
                id: alRewatch
                label: "Track rewatches"
                hint: "Allow a completed entry to start again from episode one."
            }
            SettingsToggle {
                id: alComplete
                label: "Mark entries completed at the final episode"
            }
            SettingsToggle {
                id: alDates
                label: "Set started and completed dates"
            }

            Item { Layout.preferredHeight: 20 }
        }
    }

    // Pinned under the scrolling fields, so Save is always in reach: a floating pill, not a band
    Item {
        id: saveBar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 76

        Rectangle {
            id: pill
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 10 }
            width: Math.min(parent.width - 32, 680)
            height: 56
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer2
            border.width: 1
            border.color: root.hasChanges ? Qt.alpha(Appearance.colors.colPrimary, 0.6) : Qt.alpha(Appearance.colors.colOutlineVariant, 0.5)
            Behavior on border.color {
                ColorAnimation { duration: Appearance.dur(200) }
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 20; rightMargin: 8 }
                spacing: 12

                MaterialSymbol {
                    text: MediatorService.saveError !== "" ? "error" : root.hasChanges ? "edit" : "check_circle"
                    fill: 1
                    iconSize: 20
                    color: MediatorService.saveError !== "" ? Appearance.m3colors.m3error
                        : root.hasChanges ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: MediatorService.saveError !== "" ? MediatorService.saveError
                        : root.hasChanges ? "Unsaved changes" : "All changes saved"
                    color: MediatorService.saveError !== "" ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                }
                Rectangle {
                    implicitWidth: saveText.implicitWidth + 40
                    implicitHeight: 40
                    radius: saveArea.pressed ? 12 : 20
                    color: !root.hasChanges ? "transparent"
                        : saveArea.containsMouse ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary
                    Behavior on radius {
                        NumberAnimation { duration: Appearance.dur(120) }
                    }
                    StyledText {
                        id: saveText
                        anchors.centerIn: parent
                        text: MediatorService.saving ? "Saving…" : "Save"
                        color: root.hasChanges ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                        font.weight: Font.Medium
                    }
                    MouseArea {
                        id: saveArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: root.hasChanges && !MediatorService.saving
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.save()
                    }
                }
            }
        }
    }
}
