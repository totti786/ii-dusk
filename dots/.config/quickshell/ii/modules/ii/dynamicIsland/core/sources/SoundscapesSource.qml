pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.services

/**
 * A Soundscapes mix as an island activity: present for as long as there is a mix, playing
 * or paused, and gone when it is stopped or the daemon leaves.
 *
 * The service only hears from the daemon while something holds it, so this source watches
 * it, but only while the activity is allowed. Watching is passive: it never starts the
 * daemon, and it does not keep an idle one from exiting (see SoundscapesService.watch).
 * Glance and card read the service themselves.
 */
ContinuousSource {
    id: source

    activityId: "soundscapes"

    condition: SoundscapesService.linked && SoundscapesService.hasMix

    readonly property bool watching: source.allowed && (Config.options.soundscapes?.enable ?? true)
    property bool _held: false

    function sync(): void {
        if (source.watching && !source._held) {
            source._held = true;
            SoundscapesService.watch();
        } else if (!source.watching && source._held) {
            source._held = false;
            SoundscapesService.unwatch();
        }
    }

    onWatchingChanged: source.sync()
    Component.onCompleted: source.sync()
    Component.onDestruction: {
        if (source._held) {
            source._held = false;
            SoundscapesService.unwatch();
        }
    }
}
