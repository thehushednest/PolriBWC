package com.polri.bodyworn

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.core.content.FileProvider
import com.polri.bodyworn.data.AppDatabase
import com.polri.bodyworn.data.RecordingRepository
import com.polri.bodyworn.ui.BodyWornApp
import com.polri.bodyworn.ui.theme.BodyWornTheme
import java.io.File

class MainActivity : ComponentActivity() {
    private val viewModel: MainViewModel by viewModels {
        MainViewModel.Factory(
            repository = RecordingRepository(
                AppDatabase.getInstance(applicationContext).recordingDao()
            )
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        setContent {
            BodyWornTheme {
                val uiState by viewModel.uiState.collectAsState()
                var pendingUri by rememberSaveable { mutableStateOf<String?>(null) }

                val permissionLauncher = rememberLauncherForActivityResult(
                    contract = ActivityResultContracts.RequestMultiplePermissions()
                ) { result ->
                    viewModel.handlePermissionResult(result)
                }

                val videoCaptureLauncher = rememberLauncherForActivityResult(
                    contract = ActivityResultContracts.StartActivityForResult()
                ) { result ->
                    val uri = pendingUri?.let(Uri::parse)
                    viewModel.finalizeCapture(
                        wasSuccessful = result.resultCode == RESULT_OK,
                        outputUri = uri
                    )
                    pendingUri = null
                }

                LaunchedEffect(Unit) {
                    permissionLauncher.launch(
                        arrayOf(
                            Manifest.permission.CAMERA,
                            Manifest.permission.RECORD_AUDIO,
                            Manifest.permission.ACCESS_FINE_LOCATION,
                            Manifest.permission.ACCESS_COARSE_LOCATION
                        )
                    )
                }

                BodyWornApp(
                    state = uiState,
                    onOfficerLogin = viewModel::login,
                    onLogout = viewModel::logout,
                    onStartRecording = {
                        val captureRequest = createVideoCaptureIntent()
                        pendingUri = captureRequest.outputUri.toString()
                        viewModel.prepareCapture(captureRequest.outputUri)
                        videoCaptureLauncher.launch(captureRequest.intent)
                    },
                    onDismissMessage = viewModel::clearMessage
                )
            }
        }
    }

    private fun createVideoCaptureIntent(): CaptureRequest {
        val recordingsDir = File(getExternalFilesDir(null), "Movies")
        if (!recordingsDir.exists()) {
            recordingsDir.mkdirs()
        }

        val outputFile = File(recordingsDir, "bwc_${System.currentTimeMillis()}.mp4")
        val outputUri = FileProvider.getUriForFile(
            this,
            "${BuildConfig.APPLICATION_ID}.fileprovider",
            outputFile
        )

        val intent = Intent(android.provider.MediaStore.ACTION_VIDEO_CAPTURE).apply {
            putExtra(android.provider.MediaStore.EXTRA_OUTPUT, outputUri)
            putExtra(android.provider.MediaStore.EXTRA_DURATION_LIMIT, 900)
            putExtra(android.provider.MediaStore.EXTRA_VIDEO_QUALITY, 1)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        return CaptureRequest(intent = intent, outputUri = outputUri)
    }
}

data class CaptureRequest(
    val intent: Intent,
    val outputUri: Uri
)
