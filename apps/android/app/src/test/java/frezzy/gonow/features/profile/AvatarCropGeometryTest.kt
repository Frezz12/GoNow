package frezzy.gonow.features.profile

import org.junit.Assert.assertEquals
import org.junit.Test

class AvatarCropGeometryTest {
    @Test
    fun centeredLandscapeCropUsesMiddleSquare() {
        val rect = AvatarCropGeometry.sourceRect(200f, 100f, 100f, 1f, CropOffset(0f, 0f))
        assertEquals(50f, rect.left, 0.001f)
        assertEquals(0f, rect.top, 0.001f)
        assertEquals(100f, rect.size, 0.001f)
    }

    @Test
    fun offsetCannotExposeAreaOutsideImage() {
        val offset = AvatarCropGeometry.clampedOffset(
            CropOffset(500f, 500f), 200f, 100f, 100f, 1f
        )
        assertEquals(50f, offset.x, 0.001f)
        assertEquals(0f, offset.y, 0.001f)
    }

    @Test
    fun zoomShrinksSourceSquare() {
        val rect = AvatarCropGeometry.sourceRect(200f, 100f, 100f, 2f, CropOffset(0f, 0f))
        assertEquals(50f, rect.size, 0.001f)
        assertEquals(75f, rect.left, 0.001f)
        assertEquals(25f, rect.top, 0.001f)
    }
}
