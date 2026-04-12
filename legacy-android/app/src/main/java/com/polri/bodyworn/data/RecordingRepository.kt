package com.polri.bodyworn.data

class RecordingRepository(
    private val recordingDao: RecordingDao
) {
    val recordings = recordingDao.observeAll()

    suspend fun insertRecording(recording: Recording) {
        recordingDao.insert(recording)
    }
}
