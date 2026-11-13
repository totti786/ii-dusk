pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/** The audio recorder is capturing, running or held. */
ContinuousSource {
    id: source

    activityId: "audioRecording"
    condition: AudioRecorderService.recording
}
