package dev.gamelingo.tv

import org.junit.Assert.*
import org.junit.Test

class PlacementTest {
    @Test fun cyclesAllPositions() {
        assertEquals(Placement.TOP, Placement.BOTTOM.next())
        assertEquals(Placement.CENTER, Placement.TOP.next())
        assertEquals(Placement.BOTTOM, Placement.CENTER.next())
    }
    @Test fun missingOrOldSettingUsesSafeDefault() {
        assertEquals(Placement.BOTTOM, Placement.from("unknown"))
        assertEquals(Placement.BOTTOM, Placement.from(null))
        assertEquals(Placement.TOP, Placement.from("TOP"))
    }
}
