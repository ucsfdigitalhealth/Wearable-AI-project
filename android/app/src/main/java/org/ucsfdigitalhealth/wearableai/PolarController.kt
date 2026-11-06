package org.ucsfdigitalhealth.wearableai

import android.content.Context
import com.polar.sdk.api.PolarBleApi
import com.polar.sdk.api.PolarBleApiCallback
import com.polar.sdk.api.PolarBleApiDefaultImpl
import com.polar.sdk.api.model.PolarDeviceInfo
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import java.time.LocalDateTime

/** Real BLE offline-recording sync, with no simulated success paths. */
class PolarController(context: Context, private val store: RecordingStore) {
    data class SensorDevice(val id: String, val name: String, val rssi: Int)

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val api: PolarBleApi = PolarBleApiDefaultImpl.defaultImplementation(context, setOf(
        PolarBleApi.PolarBleSdkFeature.FEATURE_HR,
        PolarBleApi.PolarBleSdkFeature.FEATURE_DEVICE_INFO,
        PolarBleApi.PolarBleSdkFeature.FEATURE_BATTERY_INFO,
        PolarBleApi.PolarBleSdkFeature.FEATURE_POLAR_OFFLINE_RECORDING,
        PolarBleApi.PolarBleSdkFeature.FEATURE_POLAR_DEVICE_TIME_SETUP
    ))
    private var scanJob: Job? = null
    private var liveHrJob: Job? = null
    private var deviceId: String? = null
    private val _devices = MutableStateFlow<List<SensorDevice>>(emptyList())
    private val _connected = MutableStateFlow<String?>(null)
    private val _status = MutableStateFlow("Disconnected")
    private val _busy = MutableStateFlow(false)
    private val _progress = MutableStateFlow(0f)
    private val _latestHr = MutableStateFlow<Int?>(null)

    val devices: StateFlow<List<SensorDevice>> = _devices
    val connected: StateFlow<String?> = _connected
    val status: StateFlow<String> = _status
    val busy: StateFlow<Boolean> = _busy
    val progress: StateFlow<Float> = _progress
    val latestHr: StateFlow<Int?> = _latestHr

    init {
        api.setAutomaticReconnection(true)
        api.setApiCallback(object : PolarBleApiCallback() {
            override fun deviceConnecting(polarDeviceInfo: PolarDeviceInfo) {
                _status.value = "Connecting to " + polarDeviceInfo.name
            }
            override fun deviceConnected(polarDeviceInfo: PolarDeviceInfo) {
                deviceId = polarDeviceInfo.deviceId
                _connected.value = polarDeviceInfo.deviceId
                _status.value = "Connected: " + polarDeviceInfo.name
            }
            @Suppress("DEPRECATION")
            override fun deviceDisconnected(polarDeviceInfo: PolarDeviceInfo) {
                _connected.value = null
                _status.value = "Disconnected from " + polarDeviceInfo.name
            }
            override fun deviceDisconnected(polarDeviceInfo: PolarDeviceInfo, info: com.polar.sdk.api.PolarBleDisconnectInfo) {
                _connected.value = null
                _status.value = "Disconnected: " + polarDeviceInfo.name
            }
            override fun bleSdkFeatureReady(identifier: String, feature: PolarBleApi.PolarBleSdkFeature) {
                if (feature == PolarBleApi.PolarBleSdkFeature.FEATURE_POLAR_OFFLINE_RECORDING) {
                    _status.value = "Ready to sync offline recordings"
                }
            }
        })
    }

    fun scan() {
        scanJob?.cancel()
        _devices.value = emptyList()
        _status.value = "Scanning for Polar sensors..."
        scanJob = scope.launch {
            try {
                api.searchForDevice().collect { info ->
                    if (!info.name.contains("Verity", ignoreCase = true) &&
                        !info.name.contains("Polar", ignoreCase = true)) return@collect
                    val record = SensorDevice(info.deviceId, info.name, info.rssi)
                    _devices.value = (_devices.value.filterNot { it.id == record.id } + record)
                        .sortedByDescending { it.rssi }
                }
            } catch (ex: Exception) {
                if (ex !is kotlinx.coroutines.CancellationException) _status.value = "Scan error: " + ex.message
            }
        }
        scope.launch {
            delay(12_000)
            scanJob?.cancel()
            if (_connected.value == null) _status.value = "Scan complete. Select a sensor to connect."
        }
    }

    fun connect(id: String) {
        scanJob?.cancel()
        deviceId = id
        runCatching { api.connectToDevice(id) }
            .onSuccess { _status.value = "Connecting to " + id + "..." }
            .onFailure { _status.value = "Connect failed: " + it.message }
    }

    fun disconnect() {
        stopLiveHr()
        deviceId?.let { runCatching { api.disconnectFromDevice(it) } }
        _connected.value = null
    }

    fun startLiveHr() {
        if (liveHrJob?.isActive == true) return
        val id = _connected.value ?: run { _status.value = "Connect first"; return }
        liveHrJob = scope.launch {
            try {
                api.startHrStreaming(id).collect { data ->
                    _latestHr.value = data.samples.lastOrNull()?.hr
                }
            } catch (ex: Exception) {
                if (ex !is kotlinx.coroutines.CancellationException) _status.value = "Live HR failed: " + ex.message
            }
        }
    }

    fun stopLiveHr() {
        liveHrJob?.cancel()
        liveHrJob = null
        _latestHr.value = null
    }

    /** Starts autonomous recording on the wearable (BLE may disconnect afterwards). */
    fun startOffline() = launchBusy("Starting offline PPG + ACC...") {
        val id = requireConnected()
        val available = api.getAvailableOfflineRecordingDataTypes(id)
        val active = api.getOfflineRecordingStatus(id)
        val results = mutableListOf<String>()
        for (type in listOf(PolarBleApi.PolarDeviceDataType.PPG, PolarBleApi.PolarDeviceDataType.ACC)) {
            if (type !in available) {
                results += type.name + " unavailable"
                continue
            }
            if (type in active) {
                results += type.name + " already recording"
                continue
            }
            try {
                val settings = api.requestOfflineRecordingSettings(id, type).maxSettings()
                api.startOfflineRecording(id, type, settings)
                results += type.name + " started"
            } catch (ex: Exception) { results += type.name + " failed: " + ex.message }
        }
        _status.value = results.joinToString("; ")
    }

    fun stopOffline() = launchBusy("Stopping offline recording...") {
        val id = requireConnected()
        val active = api.getOfflineRecordingStatus(id)
        val results = mutableListOf<String>()
        for (type in listOf(PolarBleApi.PolarDeviceDataType.PPG, PolarBleApi.PolarDeviceDataType.ACC)) {
            if (type in active) {
                try {
                    api.stopOfflineRecording(id, type)
                    results += type.name + " stopped"
                } catch (ex: Exception) { results += type.name + " failed: " + ex.message }
            }
        }
        _status.value = results.ifEmpty { listOf("No PPG/ACC recordings running") }.joinToString("; ")
    }

    /** Downloads every unsynced offline file. Leaves originals on the device for safety. */
    fun sync() = launchBusy("Listing recordings...") {
        val id = requireConnected()
        val entries = api.listOfflineRecordings(id).toList().filter { entry ->
            entry.type in setOf(
                PolarBleApi.PolarDeviceDataType.PPG,
                PolarBleApi.PolarDeviceDataType.ACC,
                PolarBleApi.PolarDeviceDataType.GYRO,
                PolarBleApi.PolarDeviceDataType.MAGNETOMETER
            )
        }
        val total = entries.size
        var downloaded = 0
        var skipped = 0
        for ((index, entry) in entries.withIndex()) {
            _status.value = "Syncing " + entry.type.name + " (" + (index + 1) + "/" + total + ")"
            if (store.hasCopy(id, entry)) {
                skipped++
            } else {
                val raw = api.getOfflineRecord(id, entry)
                if (store.persist(id, entry, raw)) downloaded++
            }
            _progress.value = (index + 1).toFloat() / total.coerceAtLeast(1)
        }
        _status.value = "Sync complete: " + downloaded + " files saved, " + skipped + " already synced"
    }

    private fun requireConnected(): String = _connected.value
        ?: error("Connect to the Polar Verity Sense first")

    private fun launchBusy(startMessage: String, action: suspend () -> Unit) {
        if (_busy.value) return
        scope.launch {
            _busy.value = true
            _progress.value = 0f
            _status.value = startMessage
            try { action() }
            catch (ex: Exception) {
                _status.value = "Operation failed: " + (ex.message ?: ex.javaClass.simpleName)
            } finally { _busy.value = false }
        }
    }

    fun close() {
        liveHrJob?.cancel()
        scanJob?.cancel()
        scope.cancel()
        api.shutDown()
    }
}
