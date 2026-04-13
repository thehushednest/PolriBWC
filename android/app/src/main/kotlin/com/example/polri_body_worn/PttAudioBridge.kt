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
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.util.Timer
import java.util.TimerTask
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class PttAudioBridge(
    private val context: Context,
) {
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val httpClient = OkHttpClient.Builder()
        .pingInterval(5, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build()

    private var webSocket: WebSocket? = null
    private var recorderThread: Thread? = null
    private var reconnectTimer: Timer? = null
    private var audioRecord: AudioRecord? = null
    private var audioTrack: AudioTrack? = null
    private var isManualDisconnect = false

    @Volatile
    private var socketUrl: String = ""

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

    private val sampleRate = 16000
    private val channelInConfig = AudioFormat.CHANNEL_IN_MONO
    private val channelOutConfig = AudioFormat.CHANNEL_OUT_MONO
    private val audioEncoding = AudioFormat.ENCODING_PCM_16BIT
    private val frameBytes = 640

    fun connect(
        url: String,
        username: String,
        channelId: String,
        deviceId: String,
    ) {
        socketUrl = url
        this.username = username
        this.channelId = channelId
        this.deviceId = deviceId
        isManualDisconnect = false
        configureAudioRouting()
        connectInternal()
    }

    fun updateChannel(channelId: String) {
        this.channelId = channelId
        ioExecutor.execute {
            if (!isSocketOpen) {
                connectInternal()
            } else {
                sendJson(
                    mapOf(
                        "type" to "join",
                        "username" to username,
                        "channelId" to channelId,
                        "deviceId" to deviceId,
                    ),
                )
            }
        }
    }

    fun startTalking() {
        if (isCapturing.get()) return
        isCapturing.set(true)
        configureAudioRouting()
        connectInternal()

        val minBuffer = AudioRecord.getMinBufferSize(sampleRate, channelInConfig, audioEncoding)
        if (minBuffer <= 0) {
            isCapturing.set(false)
            return
        }

        val record = AudioRecord(
            MediaRecorder.AudioSource.VOICE_COMMUNICATION,
            sampleRate,
            channelInConfig,
            audioEncoding,
            maxOf(minBuffer * 2, frameBytes * 4),
        )
        audioRecord = record
        enableAudioEffects(record.audioSessionId)
        record.startRecording()

        recorderThread = Thread {
            val readBuffer = ByteArray(frameBytes)
            while (isCapturing.get()) {
                if (!isSocketOpen) {
                    connectInternal()
                    Thread.sleep(80)
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
                    sendJson(
                        mapOf(
                            "type" to "audio",
                            "username" to username,
                            "channelId" to channelId,
                            "sampleRate" to sampleRate,
                            "payload" to payload,
                        ),
                    )
                }
            }
        }.apply {
            name = "polri-bwc-ptt-record"
            start()
        }
    }

    fun stopTalking() {
        isCapturing.set(false)
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
    }

    fun disconnect() {
        isManualDisconnect = true
        stopTalking()
        stopReconnect()
        closeSocketOnly()
        releasePlayback()
        resetAudioRouting()
    }

    private fun connectInternal() {
        if (socketUrl.isBlank() || isConnecting.get() || isSocketOpen) return
        isConnecting.set(true)
        ioExecutor.execute {
            try {
                closeSocketOnly()
                val request = Request.Builder().url(socketUrl).build()
                httpClient.newWebSocket(request, object : WebSocketListener() {
                    override fun onOpen(webSocket: WebSocket, response: Response) {
                        this@PttAudioBridge.webSocket = webSocket
                        isSocketOpen = true
                        isConnecting.set(false)
                        stopReconnect()
                        configureAudioRouting()
                        ensureAudioTrack()
                        sendJson(
                            mapOf(
                                "type" to "hello",
                                "username" to username,
                                "channelId" to channelId,
                                "deviceId" to deviceId,
                            ),
                        )
                    }

                    override fun onMessage(webSocket: WebSocket, text: String) {
                        handleIncoming(text)
                    }

                    override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                        isSocketOpen = false
                        isConnecting.set(false)
                        closeSocketOnly()
                        if (!isManualDisconnect) {
                            scheduleReconnect()
                        }
                    }

                    override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                        isSocketOpen = false
                        closeSocketOnly()
                        if (!isManualDisconnect) {
                            scheduleReconnect()
                        }
                    }
                })
            } catch (_: Exception) {
                isSocketOpen = false
                isConnecting.set(false)
                closeSocketOnly()
                if (!isManualDisconnect) {
                    scheduleReconnect()
                }
            }
        }
    }

    private fun handleIncoming(text: String) {
        try {
            val json = JSONObject(text)
            when (json.optString("type")) {
                "audio" -> {
                    val from = json.optString("username")
                    val incomingChannelId = json.optString("channelId")
                    if (from == username || incomingChannelId != channelId) return
                    val payload = json.optString("payload")
                    if (payload.isBlank()) return
                    val bytes = Base64.decode(payload, Base64.DEFAULT)
                    ensureAudioTrack()
                    audioTrack?.write(bytes, 0, bytes.size)
                }
                "ping", "ack" -> Unit
            }
        } catch (_: Exception) {
        }
    }

    private fun ensureAudioTrack() {
        if (audioTrack != null) return
        configureAudioRouting()
        val minBuffer = AudioTrack.getMinBufferSize(sampleRate, channelOutConfig, audioEncoding)
        if (minBuffer <= 0) return
        val preferredSpeaker = findBuiltInSpeaker()
        audioTrack = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
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
            .setBufferSizeInBytes(maxOf(minBuffer * 2, frameBytes * 8))
            .build()
            .apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && preferredSpeaker != null) {
                    setPreferredDevice(preferredSpeaker)
                }
                play()
                setVolume(1.0f)
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

    private fun configureAudioRouting() {
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
        if (isManualDisconnect || reconnectTimer != null || socketUrl.isBlank()) return
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

    private fun sendJson(payload: Map<String, Any>) {
        val currentSocket = webSocket ?: return
        try {
            currentSocket.send(JSONObject(payload).toString())
        } catch (_: Exception) {
            closeSocketOnly()
            if (!isManualDisconnect) {
                scheduleReconnect()
            }
        }
    }

    private fun closeSocketOnly() {
        try {
            webSocket?.close(1000, "normal")
        } catch (_: Exception) {
        }
        webSocket = null
        isSocketOpen = false
    }
}
