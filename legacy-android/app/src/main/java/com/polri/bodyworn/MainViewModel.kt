package com.polri.bodyworn

import android.Manifest
import android.app.Application
import android.location.Location
import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.polri.bodyworn.data.Recording
import com.polri.bodyworn.data.RecordingRepository
import com.polri.bodyworn.location.LocationSnapshotProvider
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

class MainViewModel(
    private val repository: RecordingRepository,
    private val locationProvider: LocationSnapshotProvider
) : ViewModel() {

    private val officerSession = MutableStateFlow<OfficerSession?>(null)
    private val statusMessage = MutableStateFlow<String?>(null)
    private val permissionState = MutableStateFlow(PermissionState())
    private var pendingCaptureUri: Uri? = null

    val uiState: StateFlow<MainUiState> = combine(
        repository.recordings,
        officerSession,
        statusMessage,
        permissionState
    ) { recordings, officer, message, permissions ->
        MainUiState(
            officer = officer,
            recordings = recordings,
            statusMessage = message,
            hasCameraPermission = permissions.cameraGranted,
            hasAudioPermission = permissions.audioGranted,
            hasLocationPermission = permissions.locationGranted
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = MainUiState()
    )

    fun login(name: String, unit: String) {
        if (name.isBlank() || unit.isBlank()) {
            statusMessage.value = "Nama personel dan satuan wajib diisi."
            return
        }
        officerSession.value = OfficerSession(
            officerName = name.trim(),
            unitName = unit.trim(),
            loginTimestamp = formatTimestamp(Instant.now().toEpochMilli())
        )
        statusMessage.value = "Sesi dinas aktif. Personel siap merekam."
    }

    fun logout() {
        officerSession.value = null
        statusMessage.value = "Sesi dinas ditutup."
    }

    fun handlePermissionResult(result: Map<String, Boolean>) {
        permissionState.value = PermissionState(
            cameraGranted = result[Manifest.permission.CAMERA] == true,
            audioGranted = result[Manifest.permission.RECORD_AUDIO] == true,
            locationGranted = result[Manifest.permission.ACCESS_FINE_LOCATION] == true ||
                result[Manifest.permission.ACCESS_COARSE_LOCATION] == true
        )
    }

    fun prepareCapture(uri: Uri) {
        pendingCaptureUri = uri
    }

    fun finalizeCapture(wasSuccessful: Boolean, outputUri: Uri?) {
        val officer = officerSession.value
        if (!wasSuccessful || outputUri == null) {
            statusMessage.value = "Perekaman dibatalkan."
            pendingCaptureUri = null
            return
        }
        if (officer == null) {
            statusMessage.value = "Silakan login dinas sebelum merekam."
            pendingCaptureUri = null
            return
        }
        val finalUri = pendingCaptureUri ?: outputUri
        viewModelScope.launch {
            val location = locationProvider.getCurrentLocation()
            repository.insertRecording(
                Recording(
                    officerName = officer.officerName,
                    unitName = officer.unitName,
                    fileUri = finalUri.toString(),
                    recordedAtEpochMillis = System.currentTimeMillis(),
                    latitude = location?.latitude,
                    longitude = location?.longitude,
                    source = "DEVICE_CAMERA_INTENT",
                    notes = "MVP rekaman body worn camera"
                )
            )
            statusMessage.value = buildRecordingMessage(location)
            pendingCaptureUri = null
        }
    }

    fun clearMessage() {
        statusMessage.value = null
    }

    private fun buildRecordingMessage(location: Location?): String {
        return if (location == null) {
            "Rekaman tersimpan. Lokasi belum tersedia pada perangkat ini."
        } else {
            "Rekaman tersimpan dengan metadata lokasi ${location.latitude.toCoord()}, ${location.longitude.toCoord()}."
        }
    }

    private fun Double.toCoord(): String = String.format("%.5f", this)

    private fun formatTimestamp(epochMillis: Long): String {
        val formatter = DateTimeFormatter.ofPattern("dd MMM yyyy HH:mm:ss")
        return Instant.ofEpochMilli(epochMillis)
            .atZone(ZoneId.systemDefault())
            .format(formatter)
    }

    class Factory(
        private val repository: RecordingRepository
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(
            modelClass: Class<T>,
            extras: androidx.lifecycle.viewmodel.CreationExtras
        ): T {
            val application = checkNotNull(
                extras[ViewModelProvider.AndroidViewModelFactory.APPLICATION_KEY]
            ) as Application
            val locationProvider = LocationSnapshotProvider(application)
            return MainViewModel(repository, locationProvider) as T
        }
    }
}

data class MainUiState(
    val officer: OfficerSession? = null,
    val recordings: List<Recording> = emptyList(),
    val statusMessage: String? = null,
    val hasCameraPermission: Boolean = false,
    val hasAudioPermission: Boolean = false,
    val hasLocationPermission: Boolean = false
)

data class OfficerSession(
    val officerName: String,
    val unitName: String,
    val loginTimestamp: String
)

data class PermissionState(
    val cameraGranted: Boolean = false,
    val audioGranted: Boolean = false,
    val locationGranted: Boolean = false
)
