import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.widgets

ContentPage {
    id: root
    forceWidth: false

    signal goBack

    property string widgetId: "quran_lockup"
    readonly property var options: Config.options.background.widgets[root.widgetId]

    RowLayout {
        spacing: 12

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

            onClicked: root.goBack()
        }

        StyledText {
            text: Translation.tr("Quran Calligraphy Widget Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Quran Calligraphy Settings")
        icon: "menu_book"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive(root.widgetId)

            PagePlaceholder {
                anchors.fill: parent
                icon: "menu_book"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Quran Calligraphy Widget disabled")
                description: Translation.tr("Enable the Quran Calligraphy Widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive(root.widgetId)

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("An ayah set straight on the wallpaper, as a piece of calligraphy. While the Quran player recites, the words light up as they are said. Click the text to open the reader at that ayah.")
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
            }

            StyledText {
                Layout.topMargin: 12
                text: Translation.tr("Verse")
                color: Appearance.colors.colOnLayer1
            }
            ConfigSelectionArray {
                Layout.fillWidth: true
                currentValue: root.options.source
                options: [
                    { displayName: Translation.tr("Ayah of the day"), value: "daily", icon: "today" },
                    { displayName: Translation.tr("Bookmarks"), value: "bookmarks", icon: "bookmark" },
                    { displayName: Translation.tr("Last read"), value: "last", icon: "history" }
                ]
                onSelected: value => root.options.source = value
            }
            StyledText {
                visible: root.options.source === "bookmarks"
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: String(Config.options.quran.bookmarks ?? "") === ""
                    ? Translation.tr("No verses are bookmarked yet; the ayah of the day shows until you bookmark one in the reader (press B on a verse).")
                    : Translation.tr("The bookmarked verses, one after another.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            StyledText {
                visible: root.options.source !== "last"
                Layout.topMargin: 12
                text: root.options.source === "bookmarks" ? Translation.tr("Change verse every") : Translation.tr("Change ayah every")
                color: Appearance.colors.colOnLayer1
            }
            ConfigSelectionArray {
                visible: root.options.source !== "last"
                Layout.fillWidth: true
                currentValue: root.options.rotate
                options: [
                    { displayName: Translation.tr("Day"), value: "day", icon: "light_mode" },
                    { displayName: Translation.tr("6 hours"), value: "6h", icon: "schedule" },
                    { displayName: Translation.tr("Hour"), value: "hour", icon: "update" }
                ]
                onSelected: value => root.options.rotate = value
            }

            StyledText {
                Layout.topMargin: 12
                text: Translation.tr("Calligraphy")
                color: Appearance.colors.colOnLayer1
            }
            ConfigSelectionArray {
                Layout.fillWidth: true
                currentValue: root.options.font
                options: [
                    { displayName: Translation.tr("Uthmani (Hafs)"), value: "hafs", icon: "auto_stories" },
                    { displayName: Translation.tr("Ruqaa"), value: "ruqaa", icon: "draw" },
                    { displayName: Translation.tr("Katibeh"), value: "katibeh", icon: "brush" },
                    { displayName: Translation.tr("Mirza"), value: "mirza", icon: "ink_pen" }
                ]
                onSelected: value => root.options.font = value
            }
            StyledText {
                visible: root.options.font !== "hafs"
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: Translation.tr("The decorative fonts leave out the small recitation signs they have no glyphs for.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            StyledText {
                Layout.topMargin: 12
                text: Translation.tr("Ink")
                color: Appearance.colors.colOnLayer1
            }
            ConfigSelectionArray {
                Layout.fillWidth: true
                currentValue: root.options.ink
                options: [
                    { displayName: Translation.tr("Light"), value: "light", icon: "light_mode" },
                    { displayName: Translation.tr("Accent"), value: "accent", icon: "palette" },
                    { displayName: Translation.tr("Follow wallpaper"), value: "auto", icon: "wallpaper" },
                    { displayName: Translation.tr("Dark"), value: "dark", icon: "dark_mode" }
                ]
                onSelected: value => root.options.ink = value
            }
        }
    }
}
