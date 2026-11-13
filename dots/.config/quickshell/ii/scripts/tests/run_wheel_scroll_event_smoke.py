"""Deliver real Qt6 QWheelEvents through WheelHandler offscreen.

This complements the QML logic smoke test with Qt's normal QQuickWindow wheel
dispatch and explicit scroll phases. QtTest's offscreen wheel source is a
synthetic mouse, so it cannot expose a physical TouchPad device type; the
phase path still exercises the production touchpad branch. It never talks to a
compositor or changes user configuration.
"""
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]


SCENE = '''
import QtQuick
import QtQuick.Window
import qs.modules.common
import qs.modules.common.widgets

Window {
    id: win
    objectName: "wheelWindow"
    visible: true
    width: 640
    height: 420
    color: "black"

    ListView {
        id: vertical
        objectName: "vertical"
        width: 260
        height: 320
        model: 80
        delegate: Item { width: 260; height: 40 }
        WheelScroll { id: verticalWheel; objectName: "verticalWheel" }
    }

    ListView {
        id: horizontal
        objectName: "horizontal"
        x: 300
        width: 320
        height: 120
        orientation: ListView.Horizontal
        model: 40
        delegate: Item { width: 90; height: 120 }
        WheelScroll { id: horizontalWheel; objectName: "horizontalWheel" }
    }

}
'''


def make_fixture(out):
    def put(name, text):
        path = out / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    put('qs/modules/common/Config.qml', '''pragma Singleton
import QtQuick
QtObject {
    property bool ready: true
    property QtObject options: QtObject {
        property QtObject appearance: QtObject {
            property bool settingsPerformanceMode: true
        }
        property QtObject interactions: QtObject {
            property QtObject scrolling: QtObject {
                property bool fasterTouchpadScroll: true
                property real touchpadScrollFactor: 50
                property bool touchpadKinetic: false
                property real mouseScrollFactor: 80
                property real mouseScrollDeltaThreshold: 120
            }
        }
    }
}
''')
    put('qs/modules/common/Appearance.qml', '''pragma Singleton
import QtQuick
QtObject {
    property real animMultiplier: 1.0
    property var animationCurves: ({expressiveDefaultSpatial: [0.4, 0, 0.2, 1]})
    property QtObject animation: QtObject {
        property QtObject scroll: QtObject {
            property int duration: 10
            property int type: Easing.OutCubic
            property var bezierCurve: [0.4, 0, 0.2, 1]
        }
    }
}
''')
    put('qs/modules/common/widgets/StyledScrollBar.qml',
        'import QtQuick\nimport QtQuick.Controls\nScrollBar {}')
    for name in ('WheelScroll', 'TouchpadKinetic'):
        put(f'qs/modules/common/widgets/{name}.qml',
            (ROOT / f'modules/common/widgets/{name}.qml').read_text())
    source = (ROOT / 'modules/common/functions/ScrollWheel.qml').read_text()
    source = source.replace('import Quickshell\n', 'import QtQuick\n')
    source = source.replace('Singleton {', 'QtObject {')
    put('qs/modules/common/functions/ScrollWheel.qml', source)
    put('WheelScrollEventScene.qml', SCENE)

    for folder in sorted((out / 'qs').rglob('*')):
        if not folder.is_dir():
            continue
        entries = []
        for qml in sorted(folder.glob('*.qml')):
            singleton = 'singleton ' if 'pragma Singleton' in qml.read_text() else ''
            entries.append(f'{singleton}{qml.stem} 1.0 {qml.name}')
        if entries:
            put(str(folder.relative_to(out) / 'qmldir'), '\n'.join(entries) + '\n')


def main():
    try:
        from PySide6.QtCore import QCoreApplication, QEventLoop, QObject, QPoint, QPointF, QTimer, Qt
        from PySide6.QtTest import QTest
        from PySide6.QtQml import QQmlApplicationEngine
    except ImportError as exc:
        raise SystemExit(f'PySide6 is required for real wheel-event smoke: {exc}')

    with tempfile.TemporaryDirectory(prefix='ii-wheel-events-') as directory:
        out = Path(directory)
        make_fixture(out)
        app = QCoreApplication.instance()
        if app is None:
            # QGuiApplication is required by QQmlApplicationEngine/Window, but
            # importing it lazily keeps the test's dependency error readable.
            from PySide6.QtGui import QGuiApplication
            app = QGuiApplication(sys.argv)
        engine = QQmlApplicationEngine()
        engine.addImportPath(str(out))
        warnings = []
        engine.warnings.connect(lambda messages: warnings.extend(messages))
        engine.load(str(out / 'WheelScrollEventScene.qml'))
        roots = engine.rootObjects()
        if not roots:
            for warning in warnings:
                print(warning, file=sys.stderr)
            raise SystemExit('QML event scene failed to load')
        window = roots[0]
        window.show()
        window.requestActivate()
        app.processEvents()

        def pump(milliseconds=80):
            loop = QEventLoop()
            QTimer.singleShot(milliseconds, loop.quit)
            loop.exec()
            app.processEvents()

        vertical = window.findChild(QObject, 'vertical')
        horizontal = window.findChild(QObject, 'horizontal')
        if vertical is None or horizontal is None:
            raise SystemExit('wheel scene objects were not found')
        app.processEvents()
        vertical.setProperty('contentY', 500)
        horizontal.setProperty('contentX', 200)
        pump(30)

        def wheel(pos, pixel, angle, phase):
            # QTest uses the platform's normal QQuickWindow dispatch path. Its
            # synthetic device is a mouse, but the explicit phase still
            # exercises ScrollWheel's touchpad classification branch. All
            # assertions inspect the resulting content position after this
            # real event path.
            QTest.wheelEvent(window, QPointF(*pos), QPoint(*angle),
                             QPoint(*pixel), Qt.KeyboardModifier.NoModifier,
                             phase)
            app.processEvents()
            return True

        before = vertical.property('contentY')
        wheel((100, 100), (0, -10), (0, -120), Qt.ScrollPhase.ScrollUpdate)
        pump(120)
        delta = vertical.property('contentY') - before
        if not (48 <= delta <= 52):
            raise SystemExit(f'touchpad factor was not applied vertically: {delta}')

        before = vertical.property('contentY')
        wheel((100, 100), (0, 0), (0, 120), Qt.ScrollPhase.NoScrollPhase)
        pump(30)
        if not (78 <= before - vertical.property('contentY') <= 82):
            raise SystemExit('mouse wheel factor/stacking changed')

        before = horizontal.property('contentX')
        wheel((400, 60), (-10, 0), (-120, 0), Qt.ScrollPhase.ScrollUpdate)
        pump(260)
        delta = horizontal.property('contentX') - before
        if not (48 <= delta <= 52):
            raise SystemExit(f'touchpad factor was not applied horizontally: {delta}')

        before = horizontal.property('contentX')
        wheel((400, 60), (0, -10), (0, -120), Qt.ScrollPhase.ScrollUpdate)
        pump(40)
        if horizontal.property('contentX') != before:
            raise SystemExit('orthogonal touchpad event moved horizontal content')

        # The phase-only release has no delta but must reach the active axis.
        wheel((100, 100), (0, 0), (0, 0), Qt.ScrollPhase.ScrollEnd)
        print('real QWheelEvent delivery: PASS')


if __name__ == '__main__':
    main()
