package org.ucsfdigitalhealth.wearableai

import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/** Polar's 2000-01-01 UTC nanosecond epoch is NOT the Unix epoch. */
object CsvCodec {
    const val POLAR_UNIX_OFFSET_NS: Long = 946_684_800_000_000_000L
    private val utcFormat = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS")
        .withZone(ZoneOffset.UTC)

    /** Matches Ethan's semicolon-delimited files and Beni's iOS output. */
    fun sensorTimestamp(polarNs: Long): String =
        utcFormat.format(Instant.ofEpochSecond(0L, Math.addExact(polarNs, POLAR_UNIX_OFFSET_NS)))

    fun sensorRow(polarNs: Long, vararg measurements: Any?): String =
        semicolonRow(sensorTimestamp(polarNs), polarNs, *measurements)

    fun semicolonRow(vararg fields: Any?): String =
        fields.joinToString(";") { escape(it?.toString().orEmpty(), ';') }

    fun phoneRow(vararg fields: Any?): String =
        fields.joinToString(",") { escape(it?.toString().orEmpty(), ',') }

    private fun escape(value: String, separator: Char): String {
        return if (value.any { it == separator || it == '\"' || it == '\n' || it == '\r' }) {
            "\"" + value.replace("\"", "\"\"") + "\""
        } else value
    }
}
