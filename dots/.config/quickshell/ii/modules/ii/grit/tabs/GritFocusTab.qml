import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.grit.components

/**
 * Focus: the timer, its tag, and proof that the time went somewhere.
 *
 * The stage takes its colour from the selected tag, so switching from Deep work to
 * Admin changes the room you are sitting in, not just a label. The timer itself
 * lives in GritService and keeps running with the window closed.
 */
Item {
    id: root

    property bool compact: false
    property bool wide: false
    property real layoutWidth: root.width
    property ClockSidePanel panels: null

    readonly property real padding: root.compact ? GritStyle.pagePadding : GritStyle.pagePaddingWide
    readonly property real contentWidth: root.layoutWidth - root.padding * 2
    readonly property var tag: GritService.activeTag
    readonly property color colTag: GritStyle.tagColor(root.tag)
    readonly property color colTagContainer: GritStyle.tagContainer(root.tag)
    readonly property color colTagOn: GritStyle.tagOn(root.tag)
    readonly property bool running: GritService.timerRunning
    readonly property bool onBreak: GritService.timerPhase !== "focus"
    readonly property real stageWidth: Math.min(root.contentWidth, 780)
    readonly property real ringSize: Math.max(220, Math.min(root.stageWidth - 120, root.wide ? 330 : 280))
    readonly property real digitSize: Math.max(40, root.ringSize * 0.235)
    readonly property string phaseLabel: root.onBreak ? GritService.timerPhaseLabel : Translation.tr("Focus")
    readonly property string phaseIcon: root.onBreak ? "coffee" : "psychiatry"
    readonly property var weekTags: GritService.tagStats(7)
    readonly property real weekMax: {
        let max = 1;
        for (const item of root.weekTags)
            max = Math.max(max, Number(item.seconds ?? 0));
        return max;
    }
    readonly property var recent: GritService.recentSessions(5)
    readonly property var tagTasks: GritService.tasksForTag(GritService.activeTagId)
    readonly property int goalMinutes: Math.max(0, Number(root.tag?.dailyGoalMinutes ?? 0))
    readonly property int goalTodayMinutes: GritService.tagTodayMinutes(root.tag?.id ?? "")
    readonly property real goalProgress: GritService.tagGoalProgress(root.tag)
    property string newTaskText: ""
    readonly property string subtitle: root.tag
        ? Translation.tr("%1 · %2 of %3 planned")
            .arg(String(root.tag.name))
            .arg(GritStyle.durationShort(Math.round(GritService.timerProgress * GritService.timerDurationSec / 60)))
            .arg(GritStyle.durationShort(Math.round(GritService.timerDurationSec / 60)))
        : Translation.tr("Pick a tag to begin")

    function tagMinutes(tagId, days): int {
        return Math.round(GritService.sessionsInRange(days, "focus")
            .filter(session => String(session.tagId) === String(tagId))
            .reduce((total, session) => total + Number(session.durationSec ?? 0), 0) / 60);
    }

    function editTag(tagId = ""): void {
        root.panels.show(tagEditor, {
            tagId: String(tagId ?? ""),
            panels: root.panels
        });
    }

    function deleteTag(tagId = ""): void {
        if (GritService.activeTags.length <= 1)
            return;
        root.panels.show(deleteTagSheet, {
            tagId: String(tagId ?? GritService.activeTagId),
            panels: root.panels
        });
    }

    function addTagTask(): void {
        const text = root.newTaskText.trim();
        if (text.length === 0 || !root.tag)
            return;
        GritService.createTagTask(root.tag.id, text);
        root.newTaskText = "";
    }

    function openTask(taskId = ""): void {
        root.panels.show(taskEditor, {
            taskId: String(taskId ?? ""),
            panels: root.panels
        });
    }

    focus: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space) {
            GritService.toggleTimer();
            event.accepted = true;
        } else if (event.key === Qt.Key_R) {
            GritService.resetTimer();
            event.accepted = true;
        } else if (event.key === Qt.Key_N) {
            GritService.skipTimer();
            event.accepted = true;
        }
    }

    Component {
        id: tagEditor
        GritTagEditorSheet {}
    }

    Component {
        id: deleteTagSheet
        GritDeleteTagSheet {}
    }

    Component {
        id: taskEditor
        GritTaskEditorSheet {}
    }

    StyledFlickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight + root.padding + GritStyle.fabClearance
        clip: true

        ColumnLayout {
            id: column
            width: root.contentWidth
            x: root.padding
            spacing: GritStyle.gap

            // ── Tag selector ────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: GritStyle.gapSmall

                Flow {
                    Layout.fillWidth: true
                    spacing: GritStyle.gapSmall

                    Repeater {
                        model: GritService.activeTags

                        GritTagChip {
                            required property var modelData
                            tag: modelData
                            selected: String(modelData.id) === String(GritService.activeTagId)
                            opacity: GritService.timerRunning && !selected ? 0.5 : 1
                            enabled: !GritService.timerRunning
                            trailingText: root.tagMinutes(modelData.id, 1) > 0
                                ? GritStyle.durationShort(root.tagMinutes(modelData.id, 1)) : ""
                            onClicked: GritService.selectTag(modelData.id)
                        }
                    }
                }

                ClockIconButton {
                    symbol: "add"
                    tooltip: Translation.tr("New tag")
                    colBackground: GritStyle.colField
                    onClicked: root.editTag("")
                }

                ClockIconButton {
                    visible: GritService.activeTags.length > 1
                    symbol: "tune"
                    tooltip: Translation.tr("Edit this tag")
                    colBackground: root.colTagContainer
                    colIcon: root.colTagOn
                    onClicked: root.editTag(GritService.activeTagId)
                }

                ClockIconButton {
                    visible: GritService.activeTags.length > 1
                    symbol: "delete"
                    tooltip: Translation.tr("Delete this tag")
                    colBackground: ColorUtils.mix(GritStyle.colError, GritStyle.colSurface, 0.12)
                    colIcon: GritStyle.colError
                    onClicked: root.deleteTag(GritService.activeTagId)
                }
            }

            // ── Today's goal for this tag ───────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                visible: root.goalMinutes > 0
                implicitHeight: 42
                radius: GritStyle.radiusNormal
                color: ColorUtils.mix(root.colTag, GritStyle.colSurface, 0.07)
                border.width: 1
                border.color: ColorUtils.applyAlpha(root.colTag, 0.14)

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: GritStyle.gapLarge
                        rightMargin: GritStyle.gapLarge
                    }
                    spacing: GritStyle.gap

                    MaterialSymbol {
                        text: "flag"
                        iconSize: 16
                        fill: 1
                        color: root.colTag
                    }

                    StyledText {
                        text: Translation.tr("Today's goal")
                        font.pixelSize: GritStyle.textSmall
                        font.weight: Font.DemiBold
                        color: GritStyle.colOnSurfaceVariant
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 6
                        radius: 3
                        color: GritStyle.colField

                        Rectangle {
                            width: Math.max(parent.height, parent.width * Math.max(0, root.goalProgress))
                            height: parent.height
                            radius: 3
                            color: root.colTag

                            Behavior on width {
                                animation: GritStyle.motionSpatial.numberAnimation.createObject(this)
                            }
                        }
                    }

                    StyledText {
                        text: Translation.tr("%1 / %2")
                            .arg(GritStyle.durationShort(root.goalTodayMinutes))
                            .arg(GritStyle.durationShort(root.goalMinutes))
                        font.pixelSize: GritStyle.textSmall
                        font.family: GritStyle.fontNumbers
                        color: root.colTag
                    }
                }
            }

            // ── Timer stage ─────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Math.max(400, stage.implicitHeight + GritStyle.gapHuge * 2)
                radius: GritStyle.radiusCard
                color: root.colTagContainer

                Behavior on color {
                    animation: GritStyle.motionFast.colorAnimation.createObject(this)
                }

                // A large tag-coloured shape turning slowly behind the timer. It is
                // anchored to the ring, not the whole stage, so the heading and
                // controls below cannot pull it off centre.
                ColumnLayout {
                    id: stage
                    anchors {
                        centerIn: parent
                        left: parent.left
                        right: parent.right
                        leftMargin: GritStyle.gapHuge
                        rightMargin: GritStyle.gapHuge
                    }
                    spacing: GritStyle.gap

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: GritStyle.gapSmall

                        MaterialShapeWrappedMaterialSymbol {
                            text: root.phaseIcon
                            iconSize: 18
                            padding: 7
                            shape: root.onBreak ? "SoftBurst" : String(root.tag?.shape ?? "Cookie7Sided")
                            color: root.colTag
                            colSymbol: GritStyle.tagOnSolid(root.tag)
                        }

                        StyledText {
                            text: root.phaseLabel
                            font.family: GritStyle.fontTitle
                            font.variableAxes: GritStyle.axesTitle
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: root.colTagOn
                            animateChange: !GritStyle.reducedMotion
                        }

                        StyledText {
                            visible: !root.onBreak
                            text: "· " + String(root.tag?.name ?? "")
                            font.pixelSize: GritStyle.textNormal
                            color: root.colTagOn
                            opacity: 0.7
                        }
                    }

                    Item {
                        id: ring
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: root.ringSize
                        implicitHeight: root.ringSize

                        // A quiet disc inside the ring gives the digits a surface. The tag's
                        // own shape already shows in the heading pill above.
                        Rectangle {
                            anchors.centerIn: parent
                            width: root.ringSize - Math.max(7, root.ringSize * 0.035) * 2 - 12
                            height: width
                            radius: width / 2
                            color: ColorUtils.applyAlpha(root.colTagOn, 0.07)
                        }

                        ClockProgressRing {
                            anchors.fill: parent
                            value: 1 - GritService.timerProgress
                            thickness: Math.max(7, root.ringSize * 0.035)
                            wavy: root.running
                            animateWave: false
                            tickDuration: root.running ? 1000 : 0
                            multisample: true
                            colIndicator: root.colTag
                            colTrack: ColorUtils.applyAlpha(root.colTagOn, 0.16)
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 0

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: GritStyle.durationClock(GritService.timerSecondsLeft)
                                font.family: GritStyle.fontMain
                                font.variableAxes: GritStyle.axesDigitsBold
                                font.pixelSize: root.digitSize
                                color: root.colTagOn
                                animateChange: false
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.running
                                    ? Translation.tr("of %1").arg(GritStyle.durationShort(Math.round(GritService.timerDurationSec / 60)))
                                    : (GritService.timerPaused ? Translation.tr("Paused") : Translation.tr("Ready"))
                                font.pixelSize: GritStyle.textNormal
                                color: root.colTagOn
                                opacity: 0.75
                            }
                        }

                        // A deliberate pulse while running, so the stage breathes with
                        // the session instead of looking frozen between seconds.
                        SequentialAnimation on scale {
                            running: (root.running && !GritStyle.reducedMotion) && !Appearance.motionOff
                            loops: Animation.Infinite
                            NumberAnimation {
                                from: 1
                                to: 1.008
                                duration: 2400
                                easing.type: Easing.InOutSine
                            }
                            NumberAnimation {
                                from: 1.008
                                to: 1
                                duration: 2400
                                easing.type: Easing.InOutSine
                            }
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 6

                        Repeater {
                            model: GritService.timerCycles

                            Rectangle {
                                id: segment
                                required property int index
                                readonly property bool done: segment.index < GritService.timerCycle
                                    || (segment.index === GritService.timerCycle && root.onBreak)
                                readonly property bool current: segment.index === GritService.timerCycle

                                implicitWidth: segment.current ? 42 : 12
                                implicitHeight: 12
                                radius: 6
                                color: segment.done ? root.colTag
                                    : segment.current ? ColorUtils.applyAlpha(root.colTag, 0.45)
                                    : ColorUtils.applyAlpha(root.colTagOn, 0.16)

                                Behavior on implicitWidth {
                                    animation: GritStyle.motionSpatial.numberAnimation.createObject(this)
                                }
                                Behavior on color {
                                    animation: GritStyle.motionFast.colorAnimation.createObject(this)
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: GritStyle.gapSmall
                        spacing: GritStyle.gapLarge

                        ClockIconButton {
                            symbol: "restart_alt"
                            tooltip: Translation.tr("Reset")
                            size: GritStyle.fabSize
                            iconSize: GritStyle.iconLarge
                            colBackground: ColorUtils.applyAlpha(root.colTagOn, 0.12)
                            colIcon: root.colTagOn
                            onClicked: GritService.resetTimer()
                        }

                        ClockPlayButton {
                            running: root.running
                            colIdle: root.colTag
                            colIdleHover: ColorUtils.mix(root.colTag, root.colTagOn, 0.9)
                            colOnIdle: GritStyle.tagOnSolid(root.tag)
                            colRunning: ColorUtils.applyAlpha(root.colTagOn, 0.16)
                            colOnRunning: root.colTagOn
                            onClicked: GritService.toggleTimer()
                        }

                        ClockIconButton {
                            symbol: "skip_next"
                            tooltip: Translation.tr("Skip to the next phase")
                            size: GritStyle.fabSize
                            iconSize: GritStyle.iconLarge
                            colBackground: ColorUtils.applyAlpha(root.colTagOn, 0.12)
                            colIcon: root.colTagOn
                            onClicked: GritService.skipTimer()
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: GritStyle.gapTiny
                        text: root.tag
                            ? Translation.tr("%1 focus · %2 break · %3 cycles")
                                .arg(GritStyle.durationShort(Number(root.tag.focusMinutes ?? 25)))
                                .arg(GritStyle.durationShort(Number(root.tag.breakMinutes ?? 5)))
                                .arg(String(root.tag.cycles ?? 4))
                            : ""
                        font.pixelSize: GritStyle.textSmall
                        color: root.colTagOn
                        opacity: 0.7
                    }
                }
            }

            // ── Session note ────────────────────────────────────────────
            ClockFormField {
                Layout.fillWidth: true
                symbol: "notes"
                shapeKind: MaterialShape.Shape.Cookie7Sided
                caption: Translation.tr("Session note")
                placeholder: Translation.tr("What are you working on?")
                text: String(GritService.timer?.note ?? "")
                onAccepted: GritService.setTimerNote(text)
            }

            // ── Tag to-do list ──────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                visible: root.tag !== null
                implicitHeight: todoColumn.implicitHeight + GritStyle.cardPadding * 2
                radius: GritStyle.radiusLarge
                color: ColorUtils.mix(root.colTag, GritStyle.colSurface, 0.05)
                border.width: 1
                border.color: ColorUtils.applyAlpha(root.colTag, 0.16)

                ColumnLayout {
                    id: todoColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: GritStyle.cardPadding
                    }
                    spacing: GritStyle.gapSmall

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: GritStyle.gapSmall

                        MaterialShape {
                            implicitWidth: 20
                            implicitHeight: 20
                            shapeString: String(root.tag?.shape ?? "Cookie7Sided")
                            color: root.colTag
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("To-do · %1").arg(String(root.tag?.name ?? ""))
                            elide: Text.ElideRight
                            font.pixelSize: GritStyle.textNormal
                            font.weight: Font.DemiBold
                            color: GritStyle.colOnSurface
                        }

                        StyledText {
                            text: Translation.tr("%1 open").arg(String(root.tagTasks.filter(task => !task.done).length))
                            font.pixelSize: GritStyle.textSmall
                            color: root.colTag
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: GritStyle.gapSmall

                        ClockFormField {
                            Layout.fillWidth: true
                            symbol: "add_task"
                            shapeKind: MaterialShape.Shape.Cookie7Sided
                            caption: Translation.tr("Add a to-do for this tag")
                            placeholder: Translation.tr("One small next step")
                            text: root.newTaskText
                            onTextChanged: root.newTaskText = text
                            onAccepted: root.addTagTask()
                        }

                        ClockIconButton {
                            symbol: "add"
                            size: 44
                            tooltip: Translation.tr("Add to-do")
                            colBackground: root.colTag
                            colIcon: GritStyle.tagOnSolid(root.tag)
                            enabled: root.newTaskText.trim().length > 0
                            onClicked: root.addTagTask()
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Repeater {
                            model: root.tagTasks

                            RowLayout {
                                id: tagTaskRow
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: GritStyle.gapSmall

                                RippleButton {
                                    implicitWidth: 28
                                    implicitHeight: 28
                                    buttonRadius: tagTaskRow.modelData.done ? GritStyle.radiusSmall : 14
                                    buttonRadiusPressed: GritStyle.radiusSmall
                                    colBackground: tagTaskRow.modelData.done ? root.colTag : "transparent"
                                    colBackgroundHover: GritStyle.tagContainer(root.tag)
                                    colRipple: GritStyle.tagContainer(root.tag)
                                    borderWidth: tagTaskRow.modelData.done ? 0 : 1
                                    borderColor: ColorUtils.applyAlpha(root.colTag, 0.6)
                                    onClicked: GritService.toggleTask(tagTaskRow.modelData.id)

                                    contentItem: Item {
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            visible: tagTaskRow.modelData.done
                                            text: "check"
                                            iconSize: 16
                                            fill: 1
                                            color: GritStyle.tagOnSolid(root.tag)
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 0

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: String(tagTaskRow.modelData.title ?? "")
                                        elide: Text.ElideRight
                                        font.pixelSize: GritStyle.textNormal
                                        color: tagTaskRow.modelData.done
                                            ? GritStyle.colSubtext : GritStyle.colOnSurface
                                        font.strikeout: tagTaskRow.modelData.done === true
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        visible: String(tagTaskRow.modelData.due ?? "").length > 0
                                        text: GritService.relativeDay(String(tagTaskRow.modelData.due ?? ""))
                                        font.pixelSize: GritStyle.textSmall
                                        color: String(tagTaskRow.modelData.due ?? "") < GritService.todayKey
                                            && !tagTaskRow.modelData.done
                                            ? GritStyle.colError : GritStyle.colSubtext
                                    }
                                }

                                ClockIconButton {
                                    symbol: "edit"
                                    size: 28
                                    iconSize: 15
                                    tooltip: Translation.tr("Edit to-do")
                                    onClicked: root.openTask(tagTaskRow.modelData.id)
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: root.tagTasks.length === 0
                            text: Translation.tr("No to-dos for this tag yet.")
                            font.pixelSize: GritStyle.textSmall
                            color: GritStyle.colSubtext
                        }
                    }
                }
            }

            // ── Week by tag + recent ────────────────────────────────────
            GridLayout {
                Layout.fillWidth: true
                Layout.topMargin: GritStyle.gapSmall
                columns: root.contentWidth >= 840 ? 2 : 1
                columnSpacing: GritStyle.gap
                rowSpacing: GritStyle.gap

                Rectangle {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    implicitHeight: tagColumn.implicitHeight + GritStyle.cardPadding * 2
                    radius: GritStyle.radiusLarge
                    color: GritStyle.colSurface

                    ColumnLayout {
                        id: tagColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: GritStyle.cardPadding
                        }
                        spacing: GritStyle.gapSmall

                        RowLayout {
                            Layout.fillWidth: true

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("This week, by tag")
                                font.pixelSize: GritStyle.textNormal
                                font.weight: Font.DemiBold
                                color: GritStyle.colOnSurface
                            }

                            StyledText {
                                text: GritStyle.durationShort(GritService.focusMinutesInRange(7))
                                font.pixelSize: GritStyle.textNormal
                                font.weight: Font.Bold
                                color: GritStyle.colSubtext
                            }
                        }

                        Repeater {
                            model: root.weekTags

                            ColumnLayout {
                                id: tagRow
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 3

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: GritStyle.gapSmall

                                    MaterialShape {
                                        implicitWidth: 20
                                        implicitHeight: 20
                                        shapeString: String(tagRow.modelData.shape ?? "Cookie7Sided")
                                        color: GritStyle.tagColor(tagRow.modelData.tag)
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: String(tagRow.modelData.name ?? "")
                                        elide: Text.ElideRight
                                        font.pixelSize: GritStyle.textNormal
                                        color: GritStyle.colOnSurface
                                    }

                                    StyledText {
                                        text: GritStyle.durationShort(Math.round(Number(tagRow.modelData.seconds ?? 0) / 60))
                                        font.pixelSize: GritStyle.textSmall
                                        font.weight: Font.DemiBold
                                        color: GritStyle.tagColor(tagRow.modelData.tag)
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 7
                                    radius: 4
                                    color: GritStyle.colField

                                    Rectangle {
                                        width: Math.max(parent.height, parent.width * (Number(tagRow.modelData.seconds ?? 0) / root.weekMax))
                                        height: parent.height
                                        radius: parent.radius
                                        color: GritStyle.tagColor(tagRow.modelData.tag)
                                    }
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: root.weekTags.length === 0
                            text: Translation.tr("Finish a focus session and its tag will appear here.")
                            wrapMode: Text.WordWrap
                            font.pixelSize: GritStyle.textSmall
                            color: GritStyle.colSubtext
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    implicitHeight: recentColumn.implicitHeight + GritStyle.cardPadding * 2
                    radius: GritStyle.radiusLarge
                    color: GritStyle.colSurface

                    ColumnLayout {
                        id: recentColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: GritStyle.cardPadding
                        }
                        spacing: GritStyle.gapSmall

                        RowLayout {
                            Layout.fillWidth: true

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Recent sessions")
                                font.pixelSize: GritStyle.textNormal
                                font.weight: Font.DemiBold
                                color: GritStyle.colOnSurface
                            }

                            StyledText {
                                text: GritStyle.durationShort(GritService.todayFocusMinutes)
                                font.pixelSize: GritStyle.textNormal
                                font.weight: Font.Bold
                                color: GritStyle.colSubtext
                            }
                        }

                        Repeater {
                            model: root.recent

                            GritSessionRow {
                                Layout.fillWidth: true
                                showDate: true
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: root.recent.length === 0
                            text: Translation.tr("No sessions yet. The first one is the hardest.")
                            wrapMode: Text.WordWrap
                            font.pixelSize: GritStyle.textSmall
                            color: GritStyle.colSubtext
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: GritStyle.fabClearance
            }
        }
    }
}
