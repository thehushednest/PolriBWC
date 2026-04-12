package com.polri.bodyworn.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FiberManualRecord
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.polri.bodyworn.MainUiState
import com.polri.bodyworn.data.Recording
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@Composable
fun BodyWornApp(
    state: MainUiState,
    onOfficerLogin: (String, String) -> Unit,
    onLogout: () -> Unit,
    onStartRecording: () -> Unit,
    onDismissMessage: () -> Unit
) {
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.statusMessage) {
        val message = state.statusMessage ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(message)
        onDismissMessage()
    }

    Scaffold(
        snackbarHost = { SnackbarHost(hostState = snackbarHostState) },
        containerColor = Color(0xFFF3F6F8)
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    brush = Brush.verticalGradient(
                        colors = listOf(Color(0xFF0A2740), Color(0xFF123E5C), Color(0xFFF3F6F8))
                    )
                )
                .padding(innerPadding)
        ) {
            if (state.officer == null) {
                LoginScreen(
                    onOfficerLogin = onOfficerLogin,
                    hasCameraPermission = state.hasCameraPermission,
                    hasAudioPermission = state.hasAudioPermission,
                    hasLocationPermission = state.hasLocationPermission
                )
            } else {
                DashboardScreen(
                    state = state,
                    onLogout = onLogout,
                    onStartRecording = onStartRecording
                )
            }
        }
    }
}

@Composable
private fun LoginScreen(
    onOfficerLogin: (String, String) -> Unit,
    hasCameraPermission: Boolean,
    hasAudioPermission: Boolean,
    hasLocationPermission: Boolean
) {
    var officerName by rememberSaveable { mutableStateOf("") }
    var unitName by rememberSaveable { mutableStateOf("") }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.Center
    ) {
        Card(
            colors = CardDefaults.cardColors(containerColor = Color(0xFFF7FAFC)),
            shape = RoundedCornerShape(28.dp)
        ) {
            Column(modifier = Modifier.padding(24.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = Icons.Default.Shield,
                        contentDescription = null,
                        tint = Color(0xFF0A2740),
                        modifier = Modifier.size(32.dp)
                    )
                    Spacer(modifier = Modifier.size(12.dp))
                    Column {
                        Text(
                            text = "Body Worn Camera",
                            style = MaterialTheme.typography.headlineSmall,
                            fontWeight = FontWeight.Bold,
                            color = Color(0xFF0A2740)
                        )
                        Text(
                            text = "Mode dinas personel Polri",
                            style = MaterialTheme.typography.bodyMedium,
                            color = Color(0xFF486273)
                        )
                    }
                }

                Spacer(modifier = Modifier.height(20.dp))
                OutlinedTextField(
                    value = officerName,
                    onValueChange = { officerName = it },
                    label = { Text("Nama Personel") },
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(modifier = Modifier.height(12.dp))
                OutlinedTextField(
                    value = unitName,
                    onValueChange = { unitName = it },
                    label = { Text("Satuan / Unit") },
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
                    modifier = Modifier.fillMaxWidth()
                )

                Spacer(modifier = Modifier.height(18.dp))
                PermissionChip("Kamera", hasCameraPermission)
                PermissionChip("Audio", hasAudioPermission)
                PermissionChip("Lokasi", hasLocationPermission)

                Spacer(modifier = Modifier.height(18.dp))
                Button(
                    onClick = { onOfficerLogin(officerName, unitName) },
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFC1121F))
                ) {
                    Text("Aktifkan Sesi Dinas")
                }
            }
        }
    }
}

@Composable
private fun PermissionChip(label: String, granted: Boolean) {
    AssistChip(
        onClick = {},
        enabled = false,
        label = { Text("$label: ${if (granted) "siap" else "belum diizinkan"}") }
    )
}

@Composable
private fun DashboardScreen(
    state: MainUiState,
    onLogout: () -> Unit,
    onStartRecording: () -> Unit
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        item {
            HeroCard(
                officerName = state.officer?.officerName.orEmpty(),
                unitName = state.officer?.unitName.orEmpty(),
                loginTimestamp = state.officer?.loginTimestamp.orEmpty(),
                hasLocationPermission = state.hasLocationPermission,
                onLogout = onLogout,
                onStartRecording = onStartRecording
            )
        }
        item {
            Text(
                text = "Log Rekaman Lokal",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = Color(0xFF0A2740)
            )
        }
        if (state.recordings.isEmpty()) {
            item {
                Card(
                    colors = CardDefaults.cardColors(containerColor = Color.White),
                    shape = RoundedCornerShape(24.dp)
                ) {
                    Text(
                        text = "Belum ada rekaman. Tekan tombol mulai rekam untuk membuat log body worn camera pertama.",
                        modifier = Modifier.padding(20.dp),
                        color = Color(0xFF486273)
                    )
                }
            }
        } else {
            items(state.recordings, key = { it.id }) { recording ->
                RecordingCard(recording = recording)
            }
        }
    }
}

@Composable
private fun HeroCard(
    officerName: String,
    unitName: String,
    loginTimestamp: String,
    hasLocationPermission: Boolean,
    onLogout: () -> Unit,
    onStartRecording: () -> Unit
) {
    Card(
        shape = RoundedCornerShape(28.dp),
        colors = CardDefaults.cardColors(containerColor = Color(0xFF081C2A))
    ) {
        Column(modifier = Modifier.padding(20.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        text = officerName,
                        style = MaterialTheme.typography.headlineSmall,
                        color = Color.White,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = unitName,
                        style = MaterialTheme.typography.bodyLarge,
                        color = Color(0xFFB7D5E5)
                    )
                }
                AssistChip(onClick = {}, enabled = false, label = { Text("ON DUTY") })
            }

            Spacer(modifier = Modifier.height(16.dp))
            Text(text = "Sesi aktif sejak $loginTimestamp", color = Color(0xFFD3E3EC))
            Spacer(modifier = Modifier.height(8.dp))
            AssistChip(
                onClick = {},
                enabled = false,
                leadingIcon = { Icon(Icons.Default.MyLocation, contentDescription = null) },
                label = { Text(if (hasLocationPermission) "Lokasi aktif" else "Lokasi belum aktif") }
            )
            Spacer(modifier = Modifier.height(20.dp))
            Button(
                onClick = onStartRecording,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFC1121F))
            ) {
                Icon(Icons.Default.Videocam, contentDescription = null)
                Spacer(modifier = Modifier.size(8.dp))
                Text("Mulai Rekam")
            }
            TextButton(onClick = onLogout, modifier = Modifier.align(Alignment.End)) {
                Text("Tutup sesi", color = Color(0xFFB7D5E5))
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RecordingCard(recording: Recording) {
    val context = LocalContext.current
    Card(
        onClick = {
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(Uri.parse(recording.fileUri), "video/*")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            context.startActivity(intent)
        },
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(containerColor = Color.White)
    ) {
        Column(modifier = Modifier.padding(18.dp)) {
            Text(
                text = recording.officerName,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = Color(0xFF0A2740)
            )
            Text(
                text = "${recording.unitName} | ${formatTimestamp(recording.recordedAtEpochMillis)}",
                style = MaterialTheme.typography.bodyMedium,
                color = Color(0xFF486273)
            )
            Spacer(modifier = Modifier.height(10.dp))
            HorizontalDivider()
            Spacer(modifier = Modifier.height(10.dp))
            Text(text = "Sumber: ${recording.source}", color = Color(0xFF213847))
            Text(text = buildLocationLabel(recording), color = Color(0xFF213847))
            Text(text = recording.notes, color = Color(0xFF486273))
            Spacer(modifier = Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.Default.FiberManualRecord,
                    contentDescription = null,
                    tint = Color(0xFFC1121F),
                    modifier = Modifier.size(12.dp)
                )
                Spacer(modifier = Modifier.size(6.dp))
                Text("Tap untuk buka video", color = Color(0xFF486273))
            }
        }
    }
}

private fun buildLocationLabel(recording: Recording): String {
    val latitude = recording.latitude
    val longitude = recording.longitude
    return if (latitude == null || longitude == null) {
        "Lokasi: tidak tersedia"
    } else {
        "Lokasi: ${"%.5f".format(latitude)}, ${"%.5f".format(longitude)}"
    }
}

private fun formatTimestamp(epochMillis: Long): String {
    val formatter = DateTimeFormatter.ofPattern("dd MMM yyyy HH:mm:ss")
    return Instant.ofEpochMilli(epochMillis)
        .atZone(ZoneId.systemDefault())
        .format(formatter)
}
