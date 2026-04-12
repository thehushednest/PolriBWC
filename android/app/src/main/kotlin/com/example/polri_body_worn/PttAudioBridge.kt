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

class PttAudioBridge(
    private val context: Context,
) {
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private var socket: Socket? = null
    private var writer: BufferedWriter? = null
    private var readerThread: Thread? = null
    private var recorderThread: Thread? = null
    private var audioRecord: AudioRecord? = null
    private var audioTrack: AudioTrack? = null
    private var pingTimer: Timer? = null
    private var reconnectTimer: Timer? = null
    private var isManualDisconnect = false

    @Volatile
    private var host: String = ""

    @Volatile
    private var port: Int = 8788

    @Volatile
    private var username: String = ""

    @Volatile
    private var channelId: String = "ch3"

    @Volatile
    private var deviceId: String = ""

    private val isCapturing = AtomicBoolean(false)
    private val isConnecting = AtomicBoolean(false)

    private val sampleRate = 16000
    private val channelInConfig = AudioFormat.CHANNEL_IN_MONO
    private val channelOutConfig = AudioFormat.CHANNEL_OUT_MONO
    private val audioEncoding = AudioFormat.ENCODING_PCM_16BIT
    private val frameBytes = 640

    fun connect(
        host: String,
        port: Int,
        username: String,
        channelId: String,
        deviceId: String,
    ) {
        this.host = host
        this.port = port
        this.username = username
        this.channelId = channelId
        this.deviceId = deviceId
        isManualDisconnect = false
        configureAudioRouting()
        _connectInternal()
    }

    fun updateChannel(channelId: String) {
        this.channelId = channelId
        ioExecutor.execute {
            if (socket == null || socket?.isClosed == true) {
                _connectInternal()
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
        _connectInternal()

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
                if (socket == null || socket?.isClosed == true) {
                    _connectInternal()
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
        stopPing()
        stopReconnect()
        closeSocketOnly()
        releasePlayback()
        resetAudioRouting()
    }

    private fun _connectInternal() {
        if (host.isBlank() || isConnecting.get() || (socket != null && socket?.isClosed == false)) {
            return
        }
        isConnecting.set(true)
        ioExecutor.execute {
            try {
                closeSocketOnly()
                val newSocket = Socket()
                newSocket.connect(InetSocketAddress(host, port), 2500)
                newSocket.tcpNoDelay = true
                newSocket.keepAlive = true
                socket = newSocket
                writer = BufferedWriter(OutputStreamWriter(newSocket.getOutputStream(), Charsets.UTF_8))
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
                startPing()
                stopReconnect()
                startReader(newSocket)
            } catch (_: Exception) {
                closeSocketOnly()
                if (!isManualDisconnect) {
                    scheduleReconnect()
                }
            } finally {
                isConnecting.set(false)
            }
        }
    }

    private fun startReader(currentSocket: Socket) {
        readerThread?.interrupt()
        readerThread = Thread {
            try {
                val reader = BufferedReader(InputStreamReader(currentSocket.getInputStream(), Charsets.UTF_8))
                while (!Thread.currentThread().isInterrupted) {
                    val line = reader.readLine() ?: break
                    handleIncoming(line)
                }
            } catch (_: Exception) {
            } finally {
                closeSocketOnly()
                stopPing()
                if (!isManualDisconnect) {
                    scheduleReconnect()
                }
            }
        }.apply {
            name = "polri-bwc-ptt-reader"
            start()
        }
    }

    private fun handleIncoming(line: String) {
        try {
            val json = JSONObject(line)
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
                "ping" -> Unit
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

    private fun startPing() {
        stopPing()
        pingTimer = Timer("polri-bwc-ptt-ping", true).apply {
            scheduleAtFixedRate(
                object : TimerTask() {
                    override fun run() {
                        ioExecutor.execute {
                            sendJson(
                                mapOf(
                                    "type" to "ping",
                                    "username" to username,
                                    "channelId" to channelId,
                                ),
                            )
                        }
                    }
                },
                3000,
                5000,
            )
        }
    }

    private fun stopPing() {
        pingTimer?.cancel()
        pingTimer = null
    }

    private fun scheduleReconnect() {
        if (isManualDisconnect || reconnectTimer != null || host.isBlank()) return
        reconnectTimer = Timer("polri-bwc-ptt-reconnect", true).apply {
            schedule(
                object : TimerTask() {
                    override fun run() {
                        reconnectTimer = null
                        _connectInternal()
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
        val currentWriter = writer ?: return
        try {
            currentWriter.write(JSONObject(payload).toString())
            currentWriter.newLine()
            currentWriter.flush()
        } catch (_: Exception) {
            closeSocketOnly()
            if (!isManualDisconnect) {
                scheduleReconnect()
            }
        }
    }

    private fun closeSocketOnly() {
        try {
            writer?.close()
        } catch (_: Exception) {
        }
        writer = null
        try {
            socket?.close()
        } catch (_: Exception) {
        }
        socket = null
    }
}
