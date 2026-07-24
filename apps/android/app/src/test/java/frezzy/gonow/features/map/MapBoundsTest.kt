package frezzy.gonow.features.map

import frezzy.gonow.models.MapBounds
import frezzy.gonow.models.MapCoordinate
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MapBoundsTest {
    @Test fun containsCoordinatesAcrossAntimeridian() {
        val bounds = MapBounds(-10.0, 170.0, 10.0, -170.0)
        assertTrue(bounds.contains(MapCoordinate(0.0, 179.0)))
        assertTrue(bounds.contains(MapCoordinate(0.0, -179.0)))
        assertFalse(bounds.contains(MapCoordinate(0.0, 0.0)))
    }

    @Test fun viewportCoverageHandlesAntimeridian() {
        val loaded = MapBounds(-20.0, 160.0, 20.0, -160.0)
        assertTrue(loaded.covers(MapBounds(-10.0, 170.0, 10.0, -170.0)))
        assertFalse(loaded.covers(MapBounds(-10.0, -20.0, 10.0, 20.0)))
    }
}
