package org.ucsfdigitalhealth.wearableai

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.Locale

/** A runnable Android counterpart of ios/Views/...; no fake device or Dropbox uploads. */
class MainActivity : ComponentActivity() {
    private lateinit var store: RecordingStore
    private lateinit var polar: PolarController
    private val cloud = DropboxCloud()
    private var csvToSave: File? = null

    private val saveCsv = registerForActivityResult(ActivityResultContracts.CreateDocument("text/csv")) { uri ->
        val source = csvToSave
        csvToSave = null
        if (uri != null && source != null) lifecycleScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    contentResolver.openOutputStream(uri)?.use { output -> source.inputStream().use { it.copyTo(output) } }
                        ?: error("Could not open the selected destination")
                }
                Toast.makeText(this@MainActivity, "Saved " + source.name, Toast.LENGTH_SHORT).show()
            } catch (error: Exception) {
                Toast.makeText(this@MainActivity, "Export failed: " + error.message, Toast.LENGTH_LONG).show()
            }
        }
    }

    private val blePermissions = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
        if (result.values.any { !it }) Toast.makeText(this, "Bluetooth permissions are needed to scan and connect", Toast.LENGTH_LONG).show()
    }
    private val phonePermissions = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
        val hasLocation = listOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
            .any { ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED }
        if (hasLocation) startPhoneCollection()
        else Toast.makeText(this, "Location permission is required for foreground GPS collection", Toast.LENGTH_LONG).show()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        store = RecordingStore(applicationContext)
        polar = PolarController(applicationContext, store)
        setContent {
            MaterialTheme(colorScheme = lightColorScheme(primary = androidx.compose.ui.graphics.Color(0xFF146C8D))) {
                WearableApp(
                    store = store, polar = polar, cloud = cloud,
                    onScan = { ensureBlePermissions { polar.scan() } },
                    onConnect = { id -> ensureBlePermissions { polar.connect(id) } },
                    onExport = { item -> csvToSave = item.file; saveCsv.launch(item.file.name) },
                    onConnectDropbox = { cloud.connect(this) },
                    onStartPhone = { requestPhoneCollection() },
                    onStopPhone = { stopService(Intent(this, PassiveCaptureService::class.java)); store.refresh() }
                )
            }
        }
    }

    override fun onResume() {
        super.onResume()
        cloud.onResumeAfterAuth()
        if (::store.isInitialized) store.refresh()
    }
    override fun onDestroy() {
        if (::polar.isInitialized) polar.close()
        super.onDestroy()
    }

    private fun ensureBlePermissions(onGranted: () -> Unit) {
        val required = arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        if (required.all { ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED }) onGranted()
        else blePermissions.launch(required)
    }

    private fun requestPhoneCollection() {
        val required = arrayOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
            Manifest.permission.POST_NOTIFICATIONS,
            Manifest.permission.ACTIVITY_RECOGNITION
        )
        val granted = required.take(2).any { ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED }
        if (!granted) phonePermissions.launch(required)
        else {
            val extras = required.drop(2).filter { ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED }
            if (extras.isNotEmpty()) phonePermissions.launch(extras.toTypedArray())
            else startPhoneCollection()
        }
    }

    private fun startPhoneCollection() {
        try {
            ContextCompat.startForegroundService(this, Intent(this, PassiveCaptureService::class.java).setAction(PassiveCaptureService.START))
        } catch (error: Exception) {
            Toast.makeText(this, "Could not start passive data collection: " + error.message, Toast.LENGTH_LONG).show()
        }
    }
}

@Composable
private fun WearableApp(
    store: RecordingStore,
    polar: PolarController,
    cloud: DropboxCloud,
    onScan: () -> Unit,
    onConnect: (String) -> Unit,
    onExport: (RecordingStore.ExportFile) -> Unit,
    onConnectDropbox: () -> Unit,
    onStartPhone: () -> Unit,
    onStopPhone: () -> Unit
) {
    val files by store.files.collectAsState()
    val devices by polar.devices.collectAsState()
    val connected by polar.connected.collectAsState()
    val status by polar.status.collectAsState()
    val busy by polar.busy.collectAsState()
    val progress by polar.progress.collectAsState()
    val liveHr by polar.latestHr.collectAsState()
    val cloudStatus by cloud.status.collectAsState()
    val phoneRunning by PassiveCaptureService.isRunning.collectAsState()
    var tab by rememberSaveable { mutableStateOf(0) }
    var participant by rememberSaveable { mutableStateOf("P001") }
    val scope = rememberCoroutineScope()
    LaunchedEffect(phoneRunning) {
        delay(800)
        store.refresh()
    }
    val pages = listOf("Home", "Device", "Sessions", "Data", "Phone")
    Scaffold(
        topBar = {
            Surface(color = MaterialTheme.colorScheme.primary) {
                Row(Modifier.fillMaxWidth().padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column {
                        Text("WearableAI", style = MaterialTheme.typography.titleLarge, color = MaterialTheme.colorScheme.onPrimary, fontWeight = FontWeight.Bold)
                        Text("Polar Verity Sense Study", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onPrimary)
                    }
                    Spacer(Modifier.weight(1f))
                    Text(if (connected != null) "● Connected" else "○ Offline", color = MaterialTheme.colorScheme.onPrimary)
                }
            }
        },
        bottomBar = {
            NavigationBar {
                pages.forEachIndexed { i, name ->
                    NavigationBarItem(selected = tab == i, onClick = { tab = i }, icon = { Text(listOf("⌂", "◉", "▤", "⇩", "◌")[i]) }, label = { Text(name) })
                }
            }
        }
    ) { padding ->
        when (tab) {
            0 -> PageScroll(padding) {
                Header("Daily Summary", "Sensor and phone collection overview")
                StudyCard("Device") {
                    Text(if (connected == null) "No Verity Sense connected" else "Connected: $connected")
                    Text(status, style = MaterialTheme.typography.bodySmall)
                    if (liveHr != null) Text("Live HR: $liveHr BPM", fontWeight = FontWeight.Bold)
                    Button(onClick = { tab = 1 }) { Text("Connect / Sync") }
                }
                StudyCard("Local recordings") {
                    Text("${files.size} CSV files saved on this phone")
                    Text("${files.count { it.stream == "ppg" }} PPG · ${files.count { it.stream == "acc" }} accelerometer · ${files.count { it.stream == "phone" }} phone files")
                    Button(onClick = { tab = 2 }) { Text("View recordings") }
                }
                StudyCard("Data collection") {
                    Text(if (phoneRunning) "Passive phone collection is active" else "Passive phone collection is off")
                    Text("Run offline recordings on the sensor, sync them later over BLE, then export or upload CSVs.")
                    Button(onClick = { tab = 4 }) { Text("Phone data settings") }
                }
            }
            1 -> PageScroll(padding) {
                Header("Device", "Scan, record, and sync from Polar Verity Sense")
                StudyCard("Connection") {
                    Text(status)
                    if (connected == null) {
                        Button(onClick = onScan, enabled = !busy) { Text("Scan for devices") }
                        for (device in devices) {
                            HorizontalDivider()
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Column(Modifier.weight(1f)) {
                                    Text(device.name, fontWeight = FontWeight.Bold)
                                    Text("${device.id} • ${device.rssi} dBm", style = MaterialTheme.typography.bodySmall)
                                }
                                OutlinedButton(onClick = { onConnect(device.id) }) { Text("Connect") }
                            }
                        }
                    } else {
                        Text("Device ID: $connected")
                        OutlinedButton(onClick = { polar.disconnect() }) { Text("Disconnect") }
                    }
                }
                StudyCard("Live heart rate") {
                    Text(if (liveHr != null) "$liveHr BPM" else "No live HR stream running")
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = { polar.startLiveHr() }, enabled = connected != null) { Text("Start live HR") }
                        OutlinedButton(onClick = { polar.stopLiveHr() }) { Text("Stop") }
                    }
                }
                StudyCard("Recording settings") {
                    Text("PPG (optical channels) and ACC (3-axis, milli-g)")
                    Text("Offline recording continues on the sensor even when Bluetooth disconnects.", style = MaterialTheme.typography.bodySmall)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = { polar.startOffline() }, enabled = connected != null && !busy) { Text("Start recording") }
                        OutlinedButton(onClick = { polar.stopOffline() }, enabled = connected != null && !busy) { Text("Stop") }
                    }
                }
                StudyCard("Sync recordings") {
                    Text("Download offline recordings over BLE and convert them to local CSV files.")
                    if (busy) LinearProgressIndicator(progress = { progress }, modifier = Modifier.fillMaxWidth())
                    Button(onClick = { polar.sync() }, enabled = connected != null && !busy) { Text(if (busy) "Working..." else "Sync to phone") }
                    Text("Source recordings are never deleted from the sensor automatically.", style = MaterialTheme.typography.bodySmall)
                }
            }
            2 -> PageScroll(padding) {
                Header("Recordings", "Files retained in private on-device storage")
                StudyCard("Saved recordings") {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("${files.size} CSV files", modifier = Modifier.weight(1f))
                        OutlinedButton(onClick = { store.refresh() }) { Text("Refresh") }
                    }
                    if (files.isEmpty()) Text("No recordings yet. Connect to the sensor and select Sync to phone.")
                    files.forEach { file ->
                        HorizontalDivider()
                        FileLine(file, onSave = { onExport(file) })
                    }
                }
            }
            3 -> PageScroll(padding) {
                Header("Export Data", "Save CSV files or upload directly to Dropbox")
                StudyCard("File format") {
                    Text("CSV (.csv) • semicolon-delimited sensor data")
                    Text("PPG, ACC and phone data follow the schema in the Android README. Phone data files use comma separators.", style = MaterialTheme.typography.bodySmall)
                }
                StudyCard("Exported files") {
                    if (files.isEmpty()) Text("No CSV files yet. Sync from the device or collect phone data first.")
                    files.forEach { file ->
                        HorizontalDivider()
                        FileLine(file, onSave = { onExport(file) })
                    }
                }
                StudyCard("Upload to Dropbox") {
                    Text(cloudStatus)
                    OutlinedTextField(
                        value = participant, onValueChange = { participant = it },
                        label = { Text("Study participant ID") }, singleLine = true
                    )
                    Text("Destination: /VeritySense_Study/${participant}/<date>/", style = MaterialTheme.typography.bodySmall)
                    if (!cloud.isConfigured) {
                        Text("Cloud upload requires a Dropbox app key configured at build time. Local export works without Dropbox.")
                    } else if (!cloud.isLinked) {
                        Button(onClick = onConnectDropbox) { Text("Connect Dropbox") }
                    } else {
                        Button(onClick = {
                            scope.launch {
                                try { cloud.upload(files, participant) }
                                catch (error: Throwable) { cloud.report(error) }
                            }
                        }, enabled = files.isNotEmpty() && participant.matches(Regex("[A-Za-z0-9_-]{1,40}"))) {
                            Text("Upload ${files.size} CSV files")
                        }
                    }
                    Text("No files leave the phone until you explicitly tap Upload. Large uploads over 140 MB per file require a chunked uploader.", style = MaterialTheme.typography.bodySmall)
                }
            }
            else -> PageScroll(padding) {
                Header("Phone Data", "Passive GPS, motion, steps, and screen-state events")
                StudyCard("Collect phone data") {
                    Text(if (phoneRunning) "● Collecting (foreground service)" else "○ Not collecting")
                    Text("Records only while enabled. Android shows an ongoing notification. Stop when finished.")
                    if (phoneRunning) Button(onClick = onStopPhone) { Text("Stop collection") }
                    else Button(onClick = onStartPhone) { Text("Enable phone collection") }
                }
                StudyCard("Data collected") {
                    Text("• GPS: latitude, longitude, altitude, accuracy, speed and bearing")
                    Text("• Motion: accelerometer, gyroscope and magnetometer")
                    Text("• Activity: step counter (if permission and sensor are available)")
                    Text("• Screen: display on/off and device unlock while logging")
                    Text("Output: phone_*.csv in the same daily folder as sensor recordings.")
                }
                StudyCard("Background & privacy") {
                    Text("Collection uses an Android location foreground service, rather than an unrestricted hidden background process. GPS needs location permission; accurate, continuous data is not guaranteed under battery restrictions.")
                    Text("GPS and physiological records are sensitive. Data remains in private app storage until you choose to export or upload.")
                }
            }
        }
    }
}

@Composable
private fun PageScroll(padding: PaddingValues, content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp), content = content
    )
}

@Composable
private fun Header(title: String, subheading: String) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(title, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
        Text(subheading, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun StudyCard(title: String, body: @Composable ColumnScope.() -> Unit) {
    ElevatedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            body()
        }
    }
}

@Composable
private fun FileLine(item: RecordingStore.ExportFile, onSave: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Column(Modifier.weight(1f)) {
            Text(item.file.name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
            Text(item.day + " · " + String.format(Locale.US, "%,d", item.bytes) + " bytes", style = MaterialTheme.typography.labelSmall)
        }
        OutlinedButton(onClick = onSave) { Text("Save") }
    }
}
