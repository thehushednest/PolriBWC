package id.co.senopati.polribwc

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.util.Base64
import android.util.Log
import org.json.JSONObject
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.InetSocketAddress
import java.net.Socket
import java.util.Timer
import java.util.TimerTask
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

class PttAudioBridge(
    private val context: Context,
    private val emitEvent: (String, Map<String, Any?>) -> Unit = { _, _ -> },
) {
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val playbackExecutor = Executors.newSingleThreadExecutor()

    private var tcpSocket: Socket? = null
    private var socketWriter: BufferedWriter? = null
    private var socketReaderThread: Thread? = null
    private var recorderThread: Thread? = null
    private var reconnectTimer: Timer? = null
    private var audioRecord: AudioRecord? = null
    private var audioTrack: AudioTrack? = null
    private var isManualDisconnect = false

    @Volatile
    private var socketHost: String = ""

    @Volatile
    private var socketPort: Int = 0

    @Volatile
    private var username: String = ""

    @Volatile
    private var channelId: String = "ch3"

    @Volatile
    private var deviceId: String = ""

    @Volatile
    private var isSocketOpen = false

    private val isCapturing = AtomicBoolean(false)
    private val isConnecting = AtomicBoolean(false)
    private val consecutiveSendFailures = AtomicInteger(0)
    private val socketGeneration = AtomicInteger(0)

    @Volatile
    private var rxPacketCount: Long = 0

    private companion object {
        const val TAG = "PolriPtt"
        const val CONNECT_TIMEOUT_MS = 3000
    }

    private val sampleRate = 16000
    private val channelInConfig = AudioFormat.CHANNEL_IN_MONO
    private val channelOutConfig = AudioFormat.CHANNEL_OUT_MONO
    private val audioEncoding = AudioFormat.ENCODING_PCM_16BIT
    private val frameBytes = 640
    private val sendFailureThreshold = 25
    private val startTalkingSocketWaitMs = 500L

    fun connect(
        host: String,
        port: Int,
        username: String,
        channelId: String,
        deviceId: String,
    ) {
        socketHost = host
        socketPort = port
        this.username = username
        this.channelId = channelId
        this.deviceId = deviceId
        isManualDisconnect = false
        emitState("connecting", detail = "Menghubungkan audio PTT TCP…")
        ensureMediaVolumeAudible()
        connectInternal()
    }

    fun updateChannel(channelId: String) {
        this.channelId = channelId
        ioExecutor.execute {
            if (!isSocketOpen) {
                connectInternal()
            } else {
                val sent = sendJson(
                    mapOf(
                        "type" to "join",
                        "username" to username,
                        "channelId" to channelId,
                        "deviceId" to deviceId,
                    ),
                    "join",
                    reportOnFailure = true,
                )
                if (sent) {
                    emitState("connected", detail = "Join PTT TCP terkirim ke $channelId.")
                }
            }
        }
    }

    fun startTalking(): Boolean {
        if (isCapturing.get()) return true
        if (socketHost.isBlank() || socketPort <= 0) {
            emitError("Audio PTT TCP belum dikonfigurasi.")
            return false
        }
        configureCommunicationAudioRouting()
        connectInternal()

        val waitUntil = System.currentTimeMillis() + startTalkingSocketWaitMs
        while (!isSocketOpen && System.currentTimeMillis() < waitUntil) {
            try {
                Thread.sleep(20)
            } catch (_: InterruptedException) {
                break
            }
        }

        val minBuffer = AudioRecord.getMinBufferSize(sampleRate, channelInConfig, audioEncoding)
        if (minBuffer <= 0) {
            emitError("Gagal menentukan buffer mikrofon PTT.")
            return false
        }

        val record = try {
            AudioRecord(
                MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                sampleRate,
                channelInConfig,
                audioEncoding,
                maxOf(minBuffer * 2, frameBytes * 4),
            )
        } catch (_: Exception) {
            emitError("AudioRecord gagal dibuat. Periksa izin mikrofon.")
            return false
        }
        if (record.state != AudioRecord.STATE_INITIALIZED) {
            try {
                record.release()
            } catch (_: Exception) {
            }
            emitError("Mikrofon PTT belum siap dipakai.")
            return false
        }

        isCapturing.set(true)
        consecutiveSendFailures.set(0)
        audioRecord = record
        enableAudioEffects(record.audioSessionId)
        try {
            record.startRecording()
        } catch (_: Exception) {
            isCapturing.set(false)
            try {
                record.release()
            } catch (_: Exception) {
            }
            audioRecord = null
            emitError("Gagal memulai rekam mikrofon PTT.")
            return false
        }
        emitState("recording", detail = "Mikrofon PTT aktif via TCP.")

        recorderThread = Thread {
            val readBuffer = ByteArray(frameBytes)
            while (isCapturing.get()) {
                if (!isSocketOpen) {
                    connectInternal()
                    try {
                        record.read(readBuffer, 0, readBuffer.size)
                    } catch (_: Exception) {
                    }
                    try {
                        Thread.sleep(40)
                    } catch (_: InterruptedException) {
                        break
                    }
                    emitState(
                        "reconnecting",
                        detail = "Socket TCP PTT reconnect, frame di-buffer…",
                    )
                    continue
                }
                val read = try {
                    record.read(readBuffer, 0, readBuffer.size)
                } catch (_: Exception) {
                    -1
                }
                if (read <= 0) continue

                val payload = Base64.encodeToString(readBuffer.copyOf(read), Base64.NO_WRAP)
                ioExecutor.execute {
                    val sent = sendJson(
                        mapOf(
                            "type" to "audio",
                            "username" to username,
                            "channelId" to channelId,
                            "sampleRate" to sampleRate,
                            "payload" to payload,
                        ),
                        "audio",
                        reportOnFailure = false,
                    )
                    if (sent) {
                        consecutiveSendFailures.set(0)
                    } else {
                        val fails = consecutiveSendFailures.incrementAndGet()
                        if (fails == sendFailureThreshold) {
                            emitError("Paket audio PTT gagal dikirim ke relay TCP.")
                        }
                    }
                }
            }
        }.apply {
            name = "polri-bwc-ptt-record"
            start()
        }
        return true
    }

    fun stopTalking() {
        isCapturing.set(false)
        consecutiveSendFailures.set(0)
        try {
            audioRecord?.stop()
        } catch (_: Exception) {
        }
        try {
            audioRecord?.release()
        } catch (_: Exception) {
        }
        audioRecord = null
        recorderThread = null
        resetAudioRouting()
        emitState(
            if (isSocketOpen) "connected" else "disconnected",
            detail = if (isSocketOpen) "Mikrofon PTT berhenti." else "Audio PTT terputus.",
        )
    }

    fun disconnect() {
        isManualDisconnect = true
        stopTalking()
        stopReconnect()
        closeSocketOnly()
        releasePlayback()
        resetAudioRouting()
        emitState("disconnected", detail = "Audio PTT TCP dimatikan.")
    }

    private fun connectInternal() {
        if (socketHost.isBlank() || socketPort <= 0 || isConnecting.get() || isSocketOpen) return
        isConnecting.set(true)
        emitState("connecting", detail = "Menghubungkan socket TCP PTT…")
        ioExecutor.execute {
            val generation = socketGeneration.incrementAndGet()
            try {
                closeSocketOnly()
                val socket = Socket()
                socket.tcpNoDelay = true
                socket.keepAlive = true
                socket.connect(InetSocketAddress(socketHost, socketPort), CONNECT_TIMEOUT_MS)
                val writer = BufferedWriter(OutputStreamWriter(socket.getOutputStream(), Charsets.UTF_8))
                val reader = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.UTF_8))

                if (generation != socketGeneration.get()) {
                    try {
                        writer.close()
                    } catch (_: Exception) {
                    }
                    try {
                        socket.close()
                    } catch (_: Exception) {
                    }
                    return@execute
                }

                tcpSocket = socket
                socketWriter = writer
                isSocketOpen = true
                isConnecting.set(false)
                consecutiveSendFailures.set(0)
                stopReconnect()

                if (isCapturing.get()) {
                    configureCommunicationAudioRouting()
                } else {
                    ensureMediaVolumeAudible()
                }
                ensureAudioTrack()
                emitState("connected", detail = "Socket TCP PTT terhubung, menyiapkan hello.")
                val sent = sendJson(
                    mapOf(
                        "type" to "hello",
                        "username" to username,
                        "channelId" to channelId,
                        "deviceId" to deviceId,
                    ),
                    "hello",
                    reportOnFailure = true,
                )
                if (sent) {
                    emitState(
                        if (isCapturing.get()) "recording" else "connected",
                        detail = "Hello PTT TCP terkirim.",
                    )
                }

                socketReaderThread = Thread {
                    try {
                        while (generation == socketGeneration.get()) {
                            val line = reader.readLine() ?: break
                            handleIncoming(line)
                        }
                    } catch (e: Exception) {
                        if (generation == socketGeneration.get()) {
                            val reason = e.message?.takeIf { it.isNotBlank() } ?: e.javaClass.simpleName
                            handleSocketClosed(generation, "Socket TCP PTT gagal: $reason")
                        }
                    } finally {
                        if (generation == socketGeneration.get()) {
                            handleSocketClosed(generation, "Socket TCP PTT ditutup oleh relay.")
                        }
                    }
                }.apply {
                    name = "polri-bwc-ptt-tcp-read"
                    start()
                }
            } catch (e: Exception) {
                isSocketOpen = false
                isConnecting.set(false)
                closeSocketOnly()
                val reason = e.message?.takeIf { it.isNotBlank() } ?: e.javaClass.simpleName
                val state = if (isCapturing.get()) "reconnecting" else "disconnected"
                emitState(state, detail = "Socket TCP PTT gagal dibuat: $reason")
                if (!isManualDisconnect) {
                    scheduleReconnect()
                }
            }
        }
    }

    private fun handleSocketClosed(generation: Int, detail: String) {
        if (generation != socketGeneration.get()) return
        clearSocketReference()
        isConnecting.set(false)
        val state = if (isCapturing.get()) "reconnecting" else "disconnected"
        emitState(state, detail = detail)
        if (!isManualDisconnect) {
            scheduleReconnect()
        }
    }

    private fun handleIncoming(text: String) {
        try {
            val json = JSONObject(text)
            when (json.optString("type")) {
                "audio" -> {
                    val from = json.optString("username")
                    val incomingChannelId = json.optString("channelId")
                    if (from == username) return
                    if (incomingChannelId != channelId) {
                        Log.d(
                            TAG,
                            "drop-rx channel mismatch self=$channelId pkt=$incomingChannelId from=$from",
                        )
                        return
                    }
                    val payload = json.optString("payload")
                    if (payload.isBlank()) return
                    val bytes = Base64.decode(payload, Base64.DEFAULT)
                    playbackExecutor.execute {
                        ensureAudioTrack()
                        val track = audioTrack
                        if (track == null) {
                            Log.w(TAG, "rx audioTrack null, drop ${bytes.size} bytes from=$from")
                            return@execute
                        }
                        try {
                            val written = track.write(bytes, 0, bytes.size)
                            rxPacketCount++
                            if (rxPacketCount == 1L || rxPacketCount % 50L == 0L) {
                                Log.d(
                                    TAG,
                                    "rx#$rxPacketCount from=$from bytes=${bytes.size} written=$written state=${track.playState}",
                                )
                            }
                            if (track.playState != AudioTrack.PLAYSTATE_PLAYING) {
                                try {
                                    track.play()
                                } catch (_: Exception) {
                                }
                            }
                        } catch (e: Exception) {
                            Log.w(TAG, "rx write error: ${e.message}")
                        }
                    }
                }
                "floor_lost" -> {
                    if (isCapturing.get()) {
                        emitError("Floor PTT hilang di server. Silakan tekan ulang PTT.")
                    }
                }
                "ping", "ack" -> Unit
            }
        } catch (_: Exception) {
        }
    }

    private fun ensureAudioTrack() {
        if (audioTrack != null) return
        ensureMediaVolumeAudible()
        val minBuffer = AudioTrack.getMinBufferSize(sampleRate, channelOutConfig, audioEncoding)
        if (minBuffer <= 0) {
            Log.w(TAG, "getMinBufferSize returned $minBuffer, cannot build AudioTrack")
            return
        }
        val bufferBytes = maxOf(minBuffer * 2, frameBytes * 8)
        val preferredSpeaker = findBuiltInSpeaker()
        val track = try {
            AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build(),
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(audioEncoding)
                        .setSampleRate(sampleRate)
                        .setChannelMask(channelOutConfig)
                        .build(),
                )
                .setTransferMode(AudioTrack.MODE_STREAM)
                .setBufferSizeInBytes(bufferBytes)
                .build()
        } catch (e: Exception) {
            Log.e(TAG, "AudioTrack.Builder failed: ${e.message}")
            return
        }
        if (track.state != AudioTrack.STATE_INITIALIZED) {
            Log.w(TAG, "AudioTrack not initialized (state=${track.state})")
            try {
                track.release()
            } catch (_: Exception) {
            }
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && preferredSpeaker != null) {
            try {
                track.preferredDevice = preferredSpeaker
            } catch (_: Exception) {
            }
        }
        try {
            track.setVolume(1.0f)
        } catch (_: Exception) {
        }
        try {
            track.play()
        } catch (e: Exception) {
            Log.e(TAG, "AudioTrack.play failed: ${e.message}")
            try {
                track.release()
            } catch (_: Exception) {
            }
            return
        }
        audioTrack = track
        Log.d(
            TAG,
            "AudioTrack ready rate=$sampleRate buffer=$bufferBytes state=${track.playState}",
        )
    }

    private fun ensureMediaVolumeAudible() {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        try {
            val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            val current = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
            if (current < max / 2) {
                audioManager.setStreamVolume(
                    AudioManager.STREAM_MUSIC,
                    max / 2,
                    0,
                )
                Log.d(TAG, "raise STREAM_MUSIC volume $current -> ${max / 2}")
            }
        } catch (_: Exception) {
        }
    }

    private fun enableAudioEffects(audioSessionId: Int) {
        try {
            NoiseSuppressor.create(audioSessionId)?.enabled = true
        } catch (_: Exception) {
        }
        try {
            AcousticEchoCanceler.create(audioSessionId)?.enabled = true
        } catch (_: Exception) {
        }
        try {
            AutomaticGainControl.create(audioSessionId)?.enabled = true
        } catch (_: Exception) {
        }
    }

    private fun configureCommunicationAudioRouting() {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        try {
            audioManager.stopBluetoothSco()
        } catch (_: Exception) {
        }
        audioManager.isBluetoothScoOn = false
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        audioManager.isSpeakerphoneOn = true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            findBuiltInSpeaker()?.let { speaker ->
                try {
                    audioManager.setCommunicationDevice(speaker)
                } catch (_: Exception) {
                }
            }
        }
    }

    private fun resetAudioRouting() {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                audioManager.clearCommunicationDevice()
            } catch (_: Exception) {
            }
        }
        audioManager.isSpeakerphoneOn = false
        audioManager.mode = AudioManager.MODE_NORMAL
    }

    private fun findBuiltInSpeaker(): AudioDeviceInfo? {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return null
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager.availableCommunicationDevices.firstOrNull {
                it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).firstOrNull {
                it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
            }
        } else {
            null
        }
    }

    private fun scheduleReconnect() {
        if (isManualDisconnect || reconnectTimer != null || socketHost.isBlank() || socketPort <= 0) {
            return
        }
        reconnectTimer = Timer("polri-bwc-ptt-reconnect", true).apply {
            schedule(
                object : TimerTask() {
                    override fun run() {
                        reconnectTimer = null
                        connectInternal()
                    }
                },
                1500,
            )
        }
    }

    private fun stopReconnect() {
        reconnectTimer?.cancel()
        reconnectTimer = null
    }

    private fun releasePlayback() {
        try {
            audioTrack?.pause()
            audioTrack?.flush()
            audioTrack?.release()
        } catch (_: Exception) {
        }
        audioTrack = null
    }

    private fun sendJson(
        payload: Map<String, Any>,
        label: String,
        reportOnFailure: Boolean,
    ): Boolean {
        val writer = socketWriter ?: return false
        try {
            writer.write(JSONObject(payload).toString())
            writer.newLine()
            writer.flush()
            return true
        } catch (_: Exception) {
            clearSocketReference()
            if (!isManualDisconnect) {
                scheduleReconnect()
            }
            if (reportOnFailure) {
                val state = if (isCapturing.get()) "reconnecting" else "disconnected"
                emitState(state, detail = "Gagal mengirim $label ke relay TCP.")
            }
            return false
        }
    }

    private fun closeSocketOnly() {
        try {
            socketWriter?.close()
        } catch (_: Exception) {
        }
        try {
            tcpSocket?.close()
        } catch (_: Exception) {
        }
        try {
            socketReaderThread?.interrupt()
        } catch (_: Exception) {
        }
        socketWriter = null
        tcpSocket = null
        socketReaderThread = null
        isSocketOpen = false
    }

    private fun clearSocketReference() {
        try {
            socketWriter?.close()
        } catch (_: Exception) {
        }
        try {
            tcpSocket?.close()
        } catch (_: Exception) {
        }
        socketWriter = null
        tcpSocket = null
        socketReaderThread = null
        isSocketOpen = false
    }

    private fun emitState(state: String, detail: String = "") {
        emitEvent(
            "pttAudioState",
            mapOf(
                "state" to state,
                "detail" to detail,
                "channelId" to channelId,
                "username" to username,
                "isCapturing" to isCapturing.get(),
                "isSocketOpen" to isSocketOpen,
            ),
        )
    }

    private fun emitError(message: String) {
        emitEvent(
            "pttAudioError",
            mapOf(
                "message" to message,
                "channelId" to channelId,
                "username" to username,
            ),
        )
    }
}
