package frezzy.gonow.core

import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class DiskMediaCacheTest {
    @get:Rule val temporaryFolder = TemporaryFolder()

    @Test fun coalescesConcurrentLoadsAndPersistsToDisk() = runBlocking {
        val directory = temporaryFolder.newFolder("media")
        val cache = DiskMediaCache(directory)
        val loads = AtomicInteger()
        val expected = byteArrayOf(1, 2, 3, 4)

        val results = (1..8).map {
            async {
                cache.get("users/photos/1") {
                    loads.incrementAndGet()
                    expected
                }
            }
        }.awaitAll()

        assertEquals(1, loads.get())
        results.forEach { assertArrayEquals(expected, it) }
        val newCache = DiskMediaCache(directory)
        assertArrayEquals(expected, newCache.get("users/photos/1") { error("disk cache missed") })
    }

    @Test
    fun exposesStableDiskFileWithoutReloading() = runBlocking {
        val directory = temporaryFolder.newFolder("media-cache-file")
        val cache = DiskMediaCache(directory)
        var loads = 0
        val first = cache.file("video/1") { loads++; byteArrayOf(4, 5, 6) }
        val second = cache.file("video/1") { loads++; byteArrayOf(9) }
        assertEquals(first.absolutePath, second.absolutePath)
        assertEquals(listOf<Byte>(4, 5, 6), second.readBytes().toList())
        assertEquals(1, loads)
    }
}
