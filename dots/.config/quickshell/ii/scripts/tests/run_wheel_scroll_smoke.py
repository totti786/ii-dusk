"""Exercise plain WheelScroll touchpad and mouse handling in Qt offscreen.

The test loads the production WheelScroll, TouchpadKinetic and ScrollWheel
implementation with only Config/Appearance and the decorative scrollbar
replaced. The QML test calls WheelScroll.handleWheel, the same body used by the
real WheelHandler.onWheel path, so phase and zero-delta ScrollEnd behaviour are
covered without requiring a physical touchpad.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def main():
    runner = next((str(p) for p in (
        Path('/usr/lib64/qt6/bin/qmltestrunner'),
        Path('/usr/lib/qt6/bin/qmltestrunner'),
    ) if p.exists()), None) or shutil.which('qmltestrunner6')
    if not runner:
        raise SystemExit('Qt 6 qmltestrunner is required')

    with tempfile.TemporaryDirectory(prefix='ii-wheel-scroll-') as directory:
        out = Path(directory)

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
            property bool settingsPerformanceMode: false
        }
        property QtObject interactions: QtObject {
            property QtObject scrolling: QtObject {
                property bool fasterTouchpadScroll: false
                property real touchpadScrollFactor: 450
                property bool touchpadKinetic: false
                property real mouseScrollFactor: 120
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
        put('qs/modules/common/widgets/WheelScroll.qml',
            (ROOT / 'modules/common/widgets/WheelScroll.qml').read_text())
        put('qs/modules/common/widgets/TouchpadKinetic.qml',
            (ROOT / 'modules/common/widgets/TouchpadKinetic.qml').read_text())
        scroll_wheel = (ROOT / 'modules/common/functions/ScrollWheel.qml').read_text()
        # qmltestrunner does not need Quickshell's Singleton base; a QtObject
        # with pragma Singleton provides the same import-time contract here.
        scroll_wheel = scroll_wheel.replace('import Quickshell\n', 'import QtQuick\n')
        scroll_wheel = scroll_wheel.replace('Singleton {', 'QtObject {')
        put('qs/modules/common/functions/ScrollWheel.qml', scroll_wheel)
        put('tests/tst_WheelScroll.qml', (ROOT / 'tests/scroll/tst_WheelScroll.qml').read_text())

        for folder in sorted((out / 'qs').rglob('*')):
            if not folder.is_dir():
                continue
            entries = []
            for qml in sorted(folder.glob('*.qml')):
                singleton = 'singleton ' if 'pragma Singleton' in qml.read_text() else ''
                entries.append(f'{singleton}{qml.stem} 1.0 {qml.name}')
            if entries:
                put(str(folder.relative_to(out) / 'qmldir'), '\n'.join(entries) + '\n')

        env = dict(os.environ, QT_QPA_PLATFORM='offscreen',
                   QT_QUICK_BACKEND='software', QT_QUICK_CONTROLS_STYLE='Basic')
        result = subprocess.run([runner, '-input', str(out / 'tests'),
                                 '-import', str(out)],
                                env=env, capture_output=True, text=True, timeout=60)
        print(result.stdout, end='')
        print(result.stderr, end='')
        raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()
