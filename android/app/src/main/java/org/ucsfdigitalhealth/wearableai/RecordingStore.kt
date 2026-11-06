package org.ucsfdigitalhealth.wearableai

import android.content.Context
import com.polar.sdk.api.model.PolarOfflineRecordingData
import com.polar.sdk.api.model.PolarOfflineRecordingEntry
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Durable, app-private CSVs: files/Exports/YYYY-MM-DD/<stream>_<time>_<id>.csv. */
class RecordingStore(context: Context) {
    data class ExportFile(val file: File, val day: String, val stream: String, val bytes: Long)
    val root: File = File(context.filesDir, "Exports")
    private val _files = MutableStateFlow<List<ExportFile>>(emptyList())
    val files: StateFlow<List<ExportFile>> = _files

    init { root.mkdirs(); refresh() }

    fun refresh() {
        _files.value = root.walkTopDown().filter { it.isFile && it.extension == "csv" }
            .map { ExportFile(it, it.parentFile?.name.orEmpty(), it.name.substringBefore('_'), it.length()) }
            .sortedWith(compareByDescending<ExportFile> { it.day }.thenBy { it.file.name })
            .toList()
    }

    fun hasCopy(deviceId: String, entry: PolarOfflineRecordingEntry): Boolean =
        destination(deviceId, entry).exists()

    /** Returns false if this precise sensor file was already downloaded; never deletes source. */
    suspend fun persist(deviceId: String, entry: PolarOfflineRecordingEntry, data: PolarOfflineRecordingData): Boolean =
        withContext(Dispatchers.IO) {
            val target = destination(deviceId, entry)
            if (target.exists()) return@withContext false
            target.parentFile?.mkdirs()
            val temp = File(target.parentFile, target.name + ".partial")
            try {
                FileOutputStream(temp).use { output ->
                    output.bufferedWriter(StandardCharsets.UTF_8).use { writer ->
                        val header = headerFor(data)
                        writer.appendLine(header)
                        when (data) {
                            is PolarOfflineRecordingData.PpgOfflineRecording -> {
                                for (sample in data.data.samples) {
                                    val c = sample.channelSamples
                                    require(c.size >= 4) { "PPG sample has ${c.size} channels; expected 3 PPG + ambient" }
                                    writer.appendLine(CsvCodec.sensorRow(sample.timeStamp, c[0], c[1], c[2], c[3]))
                                }
                            }
                            is PolarOfflineRecordingData.AccOfflineRecording -> {
                                for (s in data.data.samples) writer.appendLine(CsvCodec.sensorRow(s.timeStamp, s.x, s.y, s.z))
                            }
                            is PolarOfflineRecordingData.GyroOfflineRecording -> {
                                for (s in data.data.samples) writer.appendLine(CsvCodec.sensorRow(s.timeStamp, s.x, s.y, s.z))
                            }
                            is PolarOfflineRecordingData.MagOfflineRecording -> {
                                for (s in data.data.samples) writer.appendLine(CsvCodec.sensorRow(s.timeStamp, s.x, s.y, s.z))
                            }
                            else -> throw IllegalArgumentException("Offline recording type not yet implemented: ${entry.type}")
                        }
                    }
                }
                check(temp.renameTo(target)) { "Failed to finalize ${target.name}" }
            } catch (t: Throwable) {
                temp.delete()
                throw t
            }
            refresh()
            true
        }

    private fun headerFor(data: PolarOfflineRecordingData): String = when (data) {
        is PolarOfflineRecordingData.PpgOfflineRecording ->
            "Phone timestamp;sensor timestamp [ns];channel 0;channel 1;channel 2;ambient"
        is PolarOfflineRecordingData.AccOfflineRecording ->
            "Phone timestamp;sensor timestamp [ns];X [mg];Y [mg];Z [mg]"
        is PolarOfflineRecordingData.GyroOfflineRecording ->
            "Phone timestamp;sensor timestamp [ns];X [dps];Y [dps];Z [dps]"
        is PolarOfflineRecordingData.MagOfflineRecording ->
            "Phone timestamp;sensor timestamp [ns];X [gauss];Y [gauss];Z [gauss]"
        else -> throw IllegalArgumentException("Unsupported recording class: ${data.javaClass.simpleName}")
    }

    private fun destination(deviceId: String, entry: PolarOfflineRecordingEntry): File {
        val day = entry.date.toLocalDate().toString()
        val utcStart = entry.date.atOffset(ZoneOffset.UTC)
        val time = DateTimeFormatter.ofPattern("yyyyMMdd_HHmmss", Locale.US).format(utcStart)
        val hash = MessageDigest.getInstance("SHA-256")
            .digest((deviceId + ":" + entry.path).toByteArray(StandardCharsets.UTF_8))
            .take(6).joinToString("") { "%02x".format(it.toInt() and 0xff) }
        val stream = entry.type.name.lowercase(Locale.US).replace("magnetometer", "mag")
        return File(File(root, day), "${stream}_${time}_${hash}.csv")
    }
}
