package frezzy.gonow.core

import android.content.Context
import android.util.LruCache
import java.io.File
import java.security.MessageDigest
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

interface MediaCache {
    suspend fun get(path: String, loader: suspend () -> ByteArray): ByteArray
    suspend fun file(path: String, loader: suspend () -> ByteArray): File
    suspend fun put(path: String, bytes: ByteArray)
    suspend fun clear()
}

class DiskMediaCache internal constructor(private val directory: File) : MediaCache {
    constructor(context: Context) : this(File(context.cacheDir, "gonow-media"))

    init { directory.mkdirs() }
    private val memory = object : LruCache<String, ByteArray>(16 * 1024 * 1024) {
        override fun sizeOf(key: String, value: ByteArray): Int = value.size
    }
    private val mutex = Mutex()
    private val inFlight = mutableMapOf<String, CompletableDeferred<ByteArray>>()

    override suspend fun get(path: String, loader: suspend () -> ByteArray): ByteArray {
        memory.get(path)?.let { return it }
        readDisk(path)?.let {
            memory.put(path, it)
            return it
        }

        var owner = false
        val deferred = mutex.withLock {
            inFlight[path] ?: CompletableDeferred<ByteArray>().also {
                inFlight[path] = it
                owner = true
            }
        }
        if (!owner) return deferred.await()

        return try {
            val bytes = loader()
            put(path, bytes)
            deferred.complete(bytes)
            bytes
        } catch (error: Throwable) {
            deferred.completeExceptionally(error)
            throw error
        } finally {
            mutex.withLock { inFlight.remove(path, deferred) }
        }
    }

    override suspend fun file(path: String, loader: suspend () -> ByteArray): File {
        val target = fileFor(path)
        if (target.isFile) return target
        get(path, loader)
        check(target.isFile) { "Media cache write failed" }
        return target
    }

    override suspend fun put(path: String, bytes: ByteArray) {
        memory.put(path, bytes)
        withContext(Dispatchers.IO) {
            val target = fileFor(path)
            val temporary = File(directory, "${target.name}.tmp")
            temporary.writeBytes(bytes)
            if (!temporary.renameTo(target)) {
                target.writeBytes(bytes)
                temporary.delete()
            }
        }
    }

    override suspend fun clear() {
        memory.evictAll()
        withContext(Dispatchers.IO) {
            directory.listFiles()?.forEach(File::delete)
        }
    }

    private suspend fun readDisk(path: String): ByteArray? = withContext(Dispatchers.IO) {
        fileFor(path).takeIf(File::isFile)?.readBytes()
    }

    private fun fileFor(path: String): File {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(path.toByteArray())
            .joinToString("") { "%02x".format(it) }
        return File(directory, digest)
    }
}
