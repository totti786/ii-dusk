pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "DiwanCore.js" as Core

/// The front page: where to start. Themes, eras, meters and collections of the catalogue, a way back
/// into the poem last read, and a few doors (random, saved, poets).
Item {
    id: root

    /// { themes, eras, meters, collections }, each [{ slug, name, count }]
    property var terms: ({})
    /// The poem last read, if any
    property var poem: null
    property int savedCount: 0
    property bool loading: false
    property string error: ""
    property string family: "Amiri"
    /// The poem of the day: { slug, title, poet, era, meter, verse: [sadr, ajuz], count }, or null
    property var daily: null
    /// Poems read lately, as list rows, newest first
    property var recent: []

    signal openPoem(string slug)
    signal openTerm(string label, string kind, string slug)
    signal openPoets()
    signal openSaved()
    signal openRandom()
    signal resume()
    signal retry()

    readonly property bool ready: root.terms.themes !== undefined
    readonly property real colW: Math.min(root.width - (root.width < 800 ? 32 : 80), 1080)
    readonly property real gap: 14
    readonly property int totalPoems: (root.terms.eras ?? []).reduce((sum, e) => sum + e.count, 0)
    readonly property real eraMax: Math.sqrt((root.terms.eras ?? []).reduce((m, e) => Math.max(m, e.count), 1))
    readonly property var meters: (root.terms.meters ?? []).slice().sort((a, b) => (a.name === "غير معروف") - (b.name === "غير معروف") || b.count - a.count)

    /// Tile width so that a row of tiles at least `min` wide fills the column exactly
    function tileW(min: real): real {
        const n = Math.max(1, Math.floor((root.colW + root.gap) / (min + root.gap)));
        return (root.colW - root.gap * (n - 1)) / n;
    }

    // ── keyboard: arrows pick the nearest door, tile or card in a direction, Enter opens it ──

    /// Everything that can be picked registers itself here and answers activate()
    property var navItems: []
    property var curItem: null
    property bool navActive: false

    function navAdd(item: var): void {
        root.navItems.push(item);
    }
    function navRemove(item: var): void {
        root.navItems = root.navItems.filter(i => i !== item);
        if (root.curItem === item)
            root.curItem = null;
    }
    function centerOf(item: var): var {
        const p = item.mapToItem(page, 0, 0);
        return { x: p.x + item.width / 2, y: p.y + item.height / 2 };
    }

    /// dx: 1 right, -1 left; dy: 1 down, -1 up
    function navMove(dx: int, dy: int): void {
        const items = root.navItems.filter(i => i.visible && i.width > 0);
        if (items.length === 0)
            return;
        if (!root.navActive || root.curItem === null || !items.includes(root.curItem)) {
            // First press: the top row, from its right-hand end (Arabic reads that way)
            root.navActive = true;
            const first = items.map(i => ({ i: i, c: root.centerOf(i) }))
                .sort((a, b) => (Math.abs(a.c.y - b.c.y) > 20 ? a.c.y - b.c.y : b.c.x - a.c.x))[0].i;
            root.curItem = first;
            root.reveal(first);
            return;
        }
        const c = root.centerOf(root.curItem);
        let best = null;
        let bestScore = Infinity;
        items.forEach(it => {
            if (it === root.curItem)
                return;
            const p = root.centerOf(it);
            const ddx = p.x - c.x, ddy = p.y - c.y;
            const along = dy !== 0 ? ddy * dy : ddx * dx;
            const across = dy !== 0 ? Math.abs(ddx) : Math.abs(ddy);
            // Sideways moves stay on the same row; up and down take the nearest in a column-ish line
            if (along < 8 || (dy === 0 && across > it.height * 0.6))
                return;
            const score = along + across * 2;
            if (score < bestScore) {
                bestScore = score;
                best = it;
            }
        });
        if (best !== null) {
            root.curItem = best;
            root.reveal(best);
        }
    }

    function navActivate(): void {
        if (root.navActive && root.curItem !== null)
            root.curItem.activate();
    }

    /// Scroll just enough to bring an item fully into view
    function reveal(item: var): void {
        const top = item.mapToItem(page, 0, 0).y;
        const bottom = top + item.height;
        if (top < flick.contentY + 16)
            root.scrollTo(top - 80);
        else if (bottom > flick.contentY + flick.height - 16)
            root.scrollTo(bottom - flick.height + 80);
    }
    function scrollTo(y: real): void {
        glide.stop();
        glide.to = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), y));
        glide.start();
    }

    /// Keyboard scrolling: move by `dy` pixels (or to an end with ±Infinity), gliding
    function scrollBy(dy: real): void {
        const top = 0;
        const bottom = Math.max(top, flick.contentHeight - flick.height);
        glide.stop();
        glide.to = Math.max(top, Math.min(bottom, flick.contentY + dy));
        glide.start();
    }
    NumberAnimation {
        id: glide
        target: flick
        property: "contentY"
        duration: Appearance.dur(220)
        easing.type: Easing.OutCubic
    }

    component Door: Rectangle {
        id: door
        property string icon: ""
        property string text: ""
        signal clicked()
        function activate(): void { door.clicked(); }
        Component.onCompleted: root.navAdd(door)
        Component.onDestruction: root.navRemove(door)
        border.width: root.navActive && root.curItem === door ? 2 : 0
        border.color: Appearance.colors.colPrimary
        implicitHeight: 46
        implicitWidth: doorRow.implicitWidth + 36
        radius: height / 2
        color: doorArea.containsMouse ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
        Behavior on color { ColorAnimation { duration: Appearance.dur(120) } }
        Row {
            id: doorRow
            anchors.centerIn: parent
            layoutDirection: Qt.RightToLeft
            spacing: 8
            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: door.icon
                iconSize: 22
                color: Appearance.colors.colPrimary
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: door.text
                font.family: root.family
                font.pixelSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colOnLayer0
            }
        }
        MouseArea {
            id: doorArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: door.clicked()
        }
    }

    component Tile: Rectangle {
        id: tile
        property string title: ""
        property string note: ""
        property string icon: ""
        /// 0..1: how much of the catalogue this is, drawn as a thin bar; negative hides it
        property real share: -1
        /// Icon above the name, for a row of narrow cards
        property bool stacked: false
        signal clicked()
        function activate(): void { tile.clicked(); }
        Component.onCompleted: root.navAdd(tile)
        Component.onDestruction: root.navRemove(tile)
        border.width: root.navActive && root.curItem === tile ? 2 : 0
        border.color: Appearance.colors.colPrimary
        height: tile.stacked ? 144 : 92
        radius: 20
        color: tileArea.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
        Behavior on color { ColorAnimation { duration: Appearance.dur(120) } }
        clip: true

        ColumnLayout {
            visible: tile.stacked
            anchors.centerIn: parent
            width: parent.width - 24
            spacing: 2
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                radius: Appearance.rounding.full
                color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, tileArea.containsMouse ? 0.22 : 0.13)
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: tile.icon
                    iconSize: 24
                    color: Appearance.colors.colPrimary
                }
            }
            Text {
                Layout.fillWidth: true
                text: tile.title
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                font.family: root.family
                font.pixelSize: 28
                color: Appearance.colors.colOnLayer0
            }
            Text {
                Layout.fillWidth: true
                text: tile.note
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                font.family: root.family
                font.pixelSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colSubtext
            }
        }

        RowLayout {
            visible: !tile.stacked
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            layoutDirection: Qt.RightToLeft
            spacing: 14
            Rectangle {
                visible: tile.icon !== ""
                Layout.preferredWidth: 46
                Layout.preferredHeight: 46
                radius: Appearance.rounding.full
                color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, tileArea.containsMouse ? 0.22 : 0.13)
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: tile.icon
                    iconSize: 24
                    color: Appearance.colors.colPrimary
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: tile.title
                    elide: Text.ElideLeft
                    horizontalAlignment: Text.AlignRight
                    font.family: root.family
                    font.pixelSize: 30
                    color: Appearance.colors.colOnLayer0
                }
                Text {
                    Layout.fillWidth: true
                    visible: tile.note !== ""
                    text: tile.note
                    elide: Text.ElideLeft
                    horizontalAlignment: Text.AlignRight
                    font.family: root.family
                    font.pixelSize: 18
                    color: Appearance.colors.colSubtext
                }
            }
        }
        // The share of the catalogue, growing from the right edge as the text does
        Rectangle {
            visible: tile.share >= 0
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            height: 4
            width: parent.width * Math.max(0.03, tile.share)
            color: Appearance.colors.colPrimary
            opacity: tileArea.containsMouse ? 0.8 : 0.45
        }
        MouseArea {
            id: tileArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.clicked()
        }
    }

    component Heading: RowLayout {
        id: head
        property string text: ""
        property string note: ""
        Layout.fillWidth: true
        layoutDirection: Qt.RightToLeft
        spacing: 14
        Text {
            text: head.text
            font.family: root.family
            font.pixelSize: 34
            color: Appearance.colors.colOnLayer0
        }
        Text {
            visible: head.note !== ""
            text: head.note
            font.family: root.family
            font.pixelSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colSubtext
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.5) }
            }
        }
    }

    Flickable {
        id: flick
        WheelScroll {}
        anchors.fill: parent
        visible: root.ready
        clip: true
        contentWidth: width
        contentHeight: page.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: page
            x: (flick.width - root.colW) / 2
            width: root.colW
            spacing: 0

            Item { Layout.preferredHeight: 34 }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "ديوان"
                font.family: root.family
                font.pixelSize: root.width < 700 ? 64 : 96
                color: Appearance.colors.colOnLayer0
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "الشعر العربي، من الجاهلية إلى اليوم"
                font.family: root.family
                font.pixelSize: root.width < 700 ? 21 : 28
                color: Appearance.colors.colSubtext
            }
            Item { Layout.preferredHeight: 14 }
            DiwanOrnament { Layout.alignment: Qt.AlignHCenter; span: 320 }
            Item { Layout.preferredHeight: 10 }
            Text {
                Layout.alignment: Qt.AlignHCenter
                visible: root.totalPoems > 0
                text: Core.count(root.totalPoems) + " قصيدة"
                font.family: root.family
                font.pixelSize: 20
                color: Appearance.colors.colPrimary
            }
            Item { Layout.preferredHeight: 28 }

            // Continue where the reading stopped
            // The poem of the day
            Rectangle {
                id: dailyCard
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.min(root.colW, 760)
                implicitHeight: dailyCol.implicitHeight + 44
                visible: root.daily !== null
                radius: 26
                function activate(): void { root.openPoem(root.daily.slug); }
                Component.onCompleted: root.navAdd(dailyCard)
                Component.onDestruction: root.navRemove(dailyCard)
                border.width: root.navActive && root.curItem === dailyCard ? 2 : 0
                border.color: Appearance.colors.colPrimary
                color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, dailyArea.containsMouse ? 0.2 : 0.12)
                Behavior on color { ColorAnimation { duration: Appearance.dur(120) } }
                ColumnLayout {
                    id: dailyCol
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        layoutDirection: Qt.RightToLeft
                        spacing: 8
                        MaterialSymbol { text: "wb_sunny"; iconSize: 20; color: Appearance.colors.colPrimary }
                        Text {
                            text: "قصيدة اليوم"
                            font.family: root.family
                            font.pixelSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colPrimary
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: root.daily ? [root.daily.meter !== "غير معروف" ? root.daily.meter : "", Core.verseCount(root.daily.count, true)].filter(s => s).join("  ·  ") : ""
                            font.family: root.family
                            font.pixelSize: 18
                            color: Appearance.colors.colSubtext
                        }
                    }
                    Item { Layout.preferredHeight: 4 }
                    Text {
                        Layout.fillWidth: true
                        text: root.daily?.title ?? ""
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        font.family: root.family
                        font.pixelSize: 34
                        color: Appearance.colors.colOnLayer0
                    }
                    Text {
                        Layout.fillWidth: true
                        text: [root.daily?.poet ?? "", root.daily?.era ?? ""].filter(s => s).join("  ·  ")
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        font.family: root.family
                        font.pixelSize: 20
                        color: Appearance.colors.colSubtext
                    }
                    Item { Layout.preferredHeight: 8 }
                    Repeater {
                        model: root.daily?.verse ?? []
                        delegate: Text {
                            required property string modelData
                            Layout.fillWidth: true
                            text: modelData
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            font.family: root.family
                            font.pixelSize: 28
                            color: Appearance.colors.colOnLayer0
                        }
                    }
                }
                MouseArea {
                    id: dailyArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openPoem(root.daily.slug)
                }
            }
            Item { Layout.preferredHeight: 18; visible: root.daily !== null }

            Rectangle {
                id: resumeCard
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.min(root.colW, 760)
                Layout.preferredHeight: 140
                visible: root.poem !== null
                radius: Appearance.rounding.large
                function activate(): void { root.resume(); }
                Component.onCompleted: root.navAdd(resumeCard)
                Component.onDestruction: root.navRemove(resumeCard)
                border.width: root.navActive && root.curItem === resumeCard ? 2 : 0
                border.color: Appearance.colors.colPrimary
                color: resumeArea.containsMouse ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
                Behavior on color { ColorAnimation { duration: Appearance.dur(120) } }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 26
                    anchors.rightMargin: 26
                    layoutDirection: Qt.RightToLeft
                    spacing: 18
                    MaterialSymbol {
                        text: "auto_stories"
                        iconSize: 40
                        color: Appearance.colors.colPrimary
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 2
                        Text {
                            Layout.fillWidth: true
                            text: "تابع القراءة"
                            horizontalAlignment: Text.AlignRight
                            font.family: root.family
                            font.pixelSize: 18
                            color: Appearance.colors.colPrimary
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.poem?.title ?? ""
                            elide: Text.ElideLeft
                            horizontalAlignment: Text.AlignRight
                            font.family: root.family
                            font.pixelSize: 32
                            color: Appearance.colors.colOnLayer0
                        }
                        Text {
                            Layout.fillWidth: true
                            text: [root.poem?.poet ?? "", root.poem?.era ?? ""].filter(s => s).join("  ·  ")
                            elide: Text.ElideLeft
                            horizontalAlignment: Text.AlignRight
                            font.family: root.family
                            font.pixelSize: 20
                            color: Appearance.colors.colSubtext
                        }
                    }
                    MaterialSymbol {
                        text: "arrow_back"
                        iconSize: 26
                        color: Appearance.colors.colSubtext
                    }
                }
                MouseArea {
                    id: resumeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.resume()
                }
            }
            Item { Layout.preferredHeight: 18; visible: root.poem !== null }

            Row {
                Layout.alignment: Qt.AlignHCenter
                layoutDirection: Qt.RightToLeft
                spacing: 12
                Door { icon: "casino"; text: "قصيدة عشوائية"; onClicked: root.openRandom() }
                Door {
                    icon: "bookmarks"
                    text: root.savedCount > 0 ? "المحفوظات  ·  " + Core.digits(root.savedCount) : "المحفوظات"
                    onClicked: root.openSaved()
                }
                Door { icon: "groups"; text: "الشعراء"; onClicked: root.openPoets() }
            }

            // Read lately
            Item { Layout.preferredHeight: 40; visible: root.recent.length > 0 }
            Text {
                Layout.fillWidth: true
                visible: root.recent.length > 0
                text: "قرأتَ مؤخرًا"
                horizontalAlignment: Text.AlignRight
                font.family: root.family
                font.pixelSize: 24
                color: Appearance.colors.colSubtext
            }
            Item { Layout.preferredHeight: 12; visible: root.recent.length > 0 }
            Flow {
                Layout.fillWidth: true
                visible: root.recent.length > 0
                layoutDirection: Qt.RightToLeft
                spacing: root.gap
                Repeater {
                    model: root.recent.slice(0, 6)
                    delegate: Rectangle {
                        id: recentCard
                        required property var modelData
                        width: root.tileW(300)
                        height: 82
                        radius: Appearance.rounding.normal
                        function activate(): void { root.openPoem(recentCard.modelData.slug); }
                        Component.onCompleted: root.navAdd(recentCard)
                        Component.onDestruction: root.navRemove(recentCard)
                        border.width: root.navActive && root.curItem === recentCard ? 2 : 0
                        border.color: Appearance.colors.colPrimary
                        color: recentArea.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
                        Behavior on color { ColorAnimation { duration: Appearance.dur(120) } }
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                text: recentCard.modelData.title
                                elide: Text.ElideLeft
                                horizontalAlignment: Text.AlignRight
                                font.family: root.family
                                font.pixelSize: Appearance.font.pixelSize.hugeass
                                color: Appearance.colors.colOnLayer0
                            }
                            Text {
                                Layout.fillWidth: true
                                text: recentCard.modelData.poet
                                elide: Text.ElideLeft
                                horizontalAlignment: Text.AlignRight
                                font.family: root.family
                                font.pixelSize: 18
                                color: Appearance.colors.colSubtext
                            }
                        }
                        MouseArea {
                            id: recentArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openPoem(recentCard.modelData.slug)
                        }
                    }
                }
            }

            // Themes
            Item { Layout.preferredHeight: 52 }
            Heading { text: "الأغراض"; note: "ما يقوله الشعر" }
            Item { Layout.preferredHeight: 18 }
            Flow {
                Layout.fillWidth: true
                layoutDirection: Qt.RightToLeft
                spacing: root.gap
                Repeater {
                    model: root.terms.themes ?? []
                    delegate: Tile {
                        required property var modelData
                        width: root.tileW(190)
                        stacked: true
                        icon: Core.themeIcon(modelData.slug)
                        title: modelData.name
                        note: Core.count(modelData.count) + " قصيدة"
                        onClicked: root.openTerm(modelData.name, "theme", modelData.slug)
                    }
                }
            }

            // Eras
            Item { Layout.preferredHeight: 52 }
            Heading { text: "العصور"; note: "مرتبة زمنيًا" }
            Item { Layout.preferredHeight: 18 }
            Flow {
                Layout.fillWidth: true
                layoutDirection: Qt.RightToLeft
                spacing: root.gap
                Repeater {
                    model: root.terms.eras ?? []
                    delegate: Tile {
                        required property var modelData
                        width: root.tileW(230)
                        title: modelData.name
                        note: Core.count(modelData.count) + " قصيدة"
                        share: Math.sqrt(modelData.count) / root.eraMax
                        onClicked: root.openTerm("العصر " + modelData.name, "era", modelData.slug)
                    }
                }
            }

            // Collections
            Item { Layout.preferredHeight: 52; visible: (root.terms.collections ?? []).length > 0 }
            Heading { visible: (root.terms.collections ?? []).length > 0; text: "المجموعات"; note: "مختارات مشهورة" }
            Item { Layout.preferredHeight: 18; visible: (root.terms.collections ?? []).length > 0 }
            Flow {
                Layout.fillWidth: true
                layoutDirection: Qt.RightToLeft
                spacing: root.gap
                Repeater {
                    model: root.terms.collections ?? []
                    delegate: Tile {
                        required property var modelData
                        width: root.tileW(260)
                        icon: "diamond"
                        title: modelData.name
                        note: Core.count(modelData.count) + " قصائد"
                        onClicked: root.openTerm(modelData.name, "collection", modelData.slug)
                    }
                }
            }

            // Meters
            Item { Layout.preferredHeight: 52 }
            Heading { text: "البحور"; note: "أوزان الخليل" }
            Item { Layout.preferredHeight: 18 }
            Flow {
                Layout.fillWidth: true
                layoutDirection: Qt.RightToLeft
                spacing: 10
                Repeater {
                    model: root.meters
                    delegate: Rectangle {
                        id: meter
                        required property var modelData
                        function activate(): void { root.openTerm("البحر " + meter.modelData.name, "meter", meter.modelData.slug); }
                        Component.onCompleted: root.navAdd(meter)
                        Component.onDestruction: root.navRemove(meter)
                        border.width: root.navActive && root.curItem === meter ? 2 : 0
                        border.color: Appearance.colors.colPrimary
                        height: 52
                        width: meterRow.implicitWidth + 36
                        radius: Appearance.rounding.full
                        color: meterArea.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
                        Behavior on color { ColorAnimation { duration: Appearance.dur(120) } }
                        Row {
                            id: meterRow
                            anchors.centerIn: parent
                            layoutDirection: Qt.RightToLeft
                            spacing: 10
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: meter.modelData.name
                                font.family: root.family
                                font.pixelSize: 26
                                color: Appearance.colors.colOnLayer0
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Core.count(meter.modelData.count)
                                font.family: root.family
                                font.pixelSize: 18
                                color: Appearance.colors.colSubtext
                            }
                        }
                        MouseArea {
                            id: meterArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openTerm("البحر " + meter.modelData.name, "meter", meter.modelData.slug)
                        }
                    }
                }
            }

            Item { Layout.preferredHeight: 20 }
            DiwanOrnament { Layout.alignment: Qt.AlignHCenter; span: 180; opacity: 0.7 }
            Item { Layout.preferredHeight: 60 }
        }
    }

    // Loading or failing before the vocabularies are in
    ColumnLayout {
        anchors.centerIn: parent
        visible: !root.ready
        spacing: 12
        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: root.error !== "" ? "cloud_off" : "hourglass_top"
            iconSize: 40
            color: Appearance.colors.colSubtext
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: 420
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: root.error !== "" ? root.error : "جارٍ التحميل…"
        }
        DiwanChip {
            Layout.alignment: Qt.AlignHCenter
            visible: root.error !== ""
            text: "حاول مرة أخرى"
            clickable: true
            onClicked: root.retry()
        }
    }
}
