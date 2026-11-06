package org.ucsfdigitalhealth.wearableai

import org.junit.Assert.assertEquals
import org.junit.Test

class CsvCodecTest {
    @Test fun polarEpoch() {
        assertEquals("2000-01-01T00:00:00.000", CsvCodec.sensorTimestamp(0))
    }
    @Test fun backendShapedRowConvertsPolarEpoch() {
        assertEquals("2019-01-01T03:20:00.000;599628000000000000;24;35;1005",
            CsvCodec.sensorRow(599_628_000_000_000_000L, 24, 35, 1005))
    }
    @Test fun escapesFields() {
        assertEquals("a;\"b;c\";\"say \"\"hi\"\"\"", CsvCodec.semicolonRow("a", "b;c", "say \"hi\""))
    }
}
