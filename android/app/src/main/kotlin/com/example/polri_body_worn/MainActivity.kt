package id.co.senopati.polribwc

import android.content.Context
import android.content.Intent
import android.os.BatteryManager
import android.os.Build
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), SensorEventListener {
    private lateinit var deviceChannel: MethodChannel
    private val pttAudioBridge by lazy {
        PttAudioBridge(this) { event, payload ->
            emitDeviceEvent(event, payload)
        }
    }
    private var sensorManager: SensorManager? = null
    private var proximitySensor: Sensor? = null
    private var lastProximityNear: Boolean? = null

    private fun registerProximityListener() {
        val sensor = proximitySensor ?: return
        lastProximityNear = null
        sensorManager?.unregisterListener(this)
        sensorManager?.registerListener(
            this,
            sensor,
            SensorManager.SENSOR_DELAY_FASTEST,
        )
    }

    private fun emitProximityState(near: Boolean) {
        emitDeviceEvent("proximityChanged", mapOf("near" to near))
    }

    private fun emitDeviceEvent(method: String, payload: Map<String, Any?>) {
        if (!::deviceChannel.isInitialized) return
        runOnUiThread {
            deviceChannel.invokeMethod(method, payload)
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        // Keep Activity visible over the lock screen so volume-key PTT works
        // even when the phone screen is locked.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        proximitySensor = sensorManager?.getDefaultSensor(Sensor.TYPE_PROXIMITY)

        deviceChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "polri_bwc/device",
        )

        deviceChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getBatteryLevel" -> {
                    val batteryManager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                    val level = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                    result.success(level)
                }

                "configurePttAudio" -> {
                    val host = call.argument<String>("host") ?: ""
                    val port = call.argument<Int>("port") ?: 8788
                    val username = call.argument<String>("username") ?: ""
                    val channelId = call.argument<String>("channelId") ?: "ch3"
                    val deviceId = call.argument<String>("deviceId") ?: ""
                    pttAudioBridge.connect(host, port, username, channelId, deviceId)
                    result.success(true)
                }

                "updatePttChannel" -> {
                    val channelId = call.argument<String>("channelId") ?: "ch3"
                    pttAudioBridge.updateChannel(channelId)
                    result.success(true)
                }

                "startNativePtt" -> {
                    result.success(pttAudioBridge.startTalking())
                }

                "stopNativePtt" -> {
                    pttAudioBridge.stopTalking()
                    result.success(true)
                }

                "disconnectPttAudio" -> {
                    pttAudioBridge.disconnect()
                    result.success(true)
                }

                "startPersistentMode" -> {
                    startPersistentService()
                    result.success(true)
                }

                "stopPersistentMode" -> {
                    stopService(Intent(this, PolriPersistentService::class.java))
                    result.success(true)
                }

                "updatePersistentNotification" -> {
                    val status = call.argument<String>("status") ?: "Standby"
                    val channel = call.argument<String>("channel") ?: ""
                    PolriPersistentService.update(this, status, channel)
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        registerProximityListener()
    }

    override fun onPause() {
        emitProximityState(false)
        lastProximityNear = false
        sensorManager?.unregisterListener(this)
        super.onPause()
    }

    override fun onDestroy() {
        pttAudioBridge.disconnect()
        emitProximityState(false)
        sensorManager?.unregisterListener(this)
        super.onDestroy()
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event?.sensor?.type != Sensor.TYPE_PROXIMITY) return
        val sensor = proximitySensor ?: return
        val near = event.values.firstOrNull()?.let { it < sensor.maximumRange } ?: false
        if (lastProximityNear == near) return
        lastProximityNear = near
        emitProximityState(near)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN ||
            event.keyCode == KeyEvent.KEYCODE_VOLUME_UP
        ) {
            if (::deviceChannel.isInitialized) {
                when (event.action) {
                    KeyEvent.ACTION_DOWN -> {
                        if (event.repeatCount == 0) {
                            deviceChannel.invokeMethod(
                                "hardwarePtt",
                                mapOf(
                                    "state" to "down",
                                    "keyCode" to event.keyCode,
                                ),
                            )
                        }
                    }

                    KeyEvent.ACTION_UP -> {
                        deviceChannel.invokeMethod(
                            "hardwarePtt",
                            mapOf(
                                "state" to "up",
                                "keyCode" to event.keyCode,
                            ),
                        )
                    }
                }
            }
            return true
        }

        return super.dispatchKeyEvent(event)
    }

    private fun startPersistentService() {
        val intent = Intent(this, PolriPersistentService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
}
