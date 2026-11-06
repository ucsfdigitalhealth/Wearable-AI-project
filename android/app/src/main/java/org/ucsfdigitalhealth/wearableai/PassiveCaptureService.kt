package org.ucsfdigitalhealth.wearableai

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import kotlinx.coroutines.flow.MutableStateFlow
import java.io.BufferedWriter
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.util.concurrent.ConcurrentHashMap

/** Explicitly enabled foreground capture; Android does not permit silent indefinite background GPS. */
class PassiveCaptureService : Service(), SensorEventListener, LocationListener {
    companion object {
        const val START = "wearable.phone.START"
        const val STOP = "wearable.phone.STOP"
        const val CHANNEL = "phone-sensors"
        val isRunning = MutableStateFlow(false)
    }

    private lateinit var sensorManager: SensorManager
    private lateinit var locationManager: LocationManager
    private lateinit var thread: HandlerThread
    private lateinit var handler: Handler
    private lateinit var folder: File
    private val writers = ConcurrentHashMap<String, BufferedWriter>()
    private val counters = ConcurrentHashMap<String, Int>()
    private var registered = false
    private var listeningLocation = false
    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val state = when (intent?.action) {
                Intent.ACTION_SCREEN_ON -> "screen_on"
                Intent.ACTION_SCREEN_OFF -> "screen_off"
                Intent.ACTION_USER_PRESENT -> "user_present"
                else -> "unknown"
            }
            write("screen", "timestamp_ns,event", CsvCodec.phoneRow(nowNs(), state))
        }
    }

    override fun onCreate() {
        super.onCreate()
        folder = File(filesDir, "Exports")
        sensorManager = getSystemService(SENSOR_SERVICE) as SensorManager
        locationManager = getSystemService(LOCATION_SERVICE) as LocationManager
        thread = HandlerThread("passive-sensor-events").also { it.start() }
        handler = Handler(thread.looper)
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "Phone sensor collection", NotificationManager.IMPORTANCE_LOW))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (registered) return START_NOT_STICKY
        val notification = NotificationCompat.Builder(this, CHANNEL)
            .setContentTitle("WearableAI phone data")
            .setContentText("Location, motion and screen events are being recorded")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true).build()
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(87, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
            } else {
                startForeground(87, notification)
            }
        } catch (_: SecurityException) {
            stopSelf()
            return START_NOT_STICKY
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        registerReceiver(screenReceiver, filter)
        registered = true
        for (type in listOf(Sensor.TYPE_ACCELEROMETER, Sensor.TYPE_GYROSCOPE, Sensor.TYPE_MAGNETIC_FIELD)) {
            sensorManager.getDefaultSensor(type)?.let { sensor ->
                sensorManager.registerListener(this, sensor, 200_000, handler) // ~5Hz; phone-dependent
            }
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED) {
            sensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)?.let { sensor ->
                sensorManager.registerListener(this, sensor, SensorManager.SENSOR_DELAY_NORMAL, handler)
            }
        }
        try {
            val fine = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
            val coarse = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
            val provider = if (fine && locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                LocationManager.GPS_PROVIDER
            } else if ((fine || coarse) && locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                LocationManager.NETWORK_PROVIDER
            } else null
            if (provider != null) {
                locationManager.requestLocationUpdates(provider, 10_000L, 5f, this, thread.looper)
                listeningLocation = true
            }
        } catch (_: SecurityException) { /* Permission revoked while starting. Motion may still run. */ }
        write("screen", "timestamp_ns,event", CsvCodec.phoneRow(nowNs(), "collection_started"))
        isRunning.value = true
        return START_NOT_STICKY
    }

    override fun onSensorChanged(event: SensorEvent) {
        val unixNs = nowNs() + (event.timestamp - SystemClock.elapsedRealtimeNanos())
        when (event.sensor.type) {
            Sensor.TYPE_ACCELEROMETER, Sensor.TYPE_GYROSCOPE, Sensor.TYPE_MAGNETIC_FIELD -> {
                val name = when (event.sensor.type) {
                    Sensor.TYPE_ACCELEROMETER -> "accelerometer"
                    Sensor.TYPE_GYROSCOPE -> "gyroscope"
                    else -> "magnetometer"
                }
                // SI units: ACC = m/s^2, GYRO = rad/s, MAG = microtesla.
                write("motion", "timestamp_ns,sensor,x,y,z,units", CsvCodec.phoneRow(
                    unixNs, name, event.values[0], event.values[1], event.values[2],
                    when (name) { "accelerometer" -> "m/s2"; "gyroscope" -> "rad/s"; else -> "uT" }
                ))
            }
            Sensor.TYPE_STEP_COUNTER -> write("activity", "timestamp_ns,step_counter_since_boot",
                CsvCodec.phoneRow(unixNs, event.values[0].toLong()))
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    override fun onLocationChanged(location: Location) {
        write("gps", "timestamp_ns,latitude,longitude,altitude_m,accuracy_m,speed_mps,bearing_deg",
            CsvCodec.phoneRow(location.time * 1_000_000L, location.latitude, location.longitude,
                location.altitude, location.accuracy, location.speed, location.bearing))
    }

    @Synchronized
    private fun write(stream: String, header: String, row: String) {
        val day = LocalDate.now(ZoneOffset.UTC).toString()
        val id = day + "/phone_" + stream
        try {
            val writer = writers.getOrPut(id) {
                val dayFolder = File(folder, day).also { it.mkdirs() }
                val file = File(dayFolder, "phone_${stream}_${day.replace("-", "")}.csv")
                val needsHeader = !file.exists() || file.length() == 0L
                val w = java.io.FileOutputStream(file, true).bufferedWriter(Charsets.UTF_8, 8192)
                if (needsHeader) w.appendLine(header)
                w
            }
            writer.appendLine(row)
            val rows = (counters[id] ?: 0) + 1
            counters[id] = rows
            if (rows % 10 == 0) writer.flush()
        } catch (ex: Exception) {
            android.util.Log.e("WearableAI", "Passive CSV write failed", ex)
        }
    }

    override fun onDestroy() {
        if (registered) {
            runCatching { unregisterReceiver(screenReceiver) }
            sensorManager.unregisterListener(this)
        }
        if (listeningLocation) runCatching { locationManager.removeUpdates(this) }
        synchronized(this) { writers.values.forEach { runCatching { it.flush(); it.close() } }; writers.clear() }
        thread.quitSafely()
        isRunning.value = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
    private fun nowNs(): Long = System.currentTimeMillis() * 1_000_000L
}
