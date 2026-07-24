package frezzy.gonow.network

import frezzy.gonow.data.SessionStore
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener

interface RealtimeClient {
    fun events(path: String): Flow<String>
    fun send(path: String, text: String): Boolean
    fun close(path: String)
    fun closeAll()
}

class OkHttpRealtimeClient(
    private val client: OkHttpClient,
    private val webSocketBaseUrl: String,
    private val sessionStore: SessionStore
) : RealtimeClient {

    private val sockets = ConcurrentHashMap<String, WebSocket>()

    override fun events(path: String): Flow<String> = callbackFlow {
        val stopped = AtomicBoolean(false)
        val reconnectScheduled = AtomicBoolean(false)
        var retryAttempt = 0

        fun connect() {
            if (stopped.get()) return
            val request = Request.Builder()
                .url(webSocketBaseUrl + path.trimStart('/'))
                .apply {
                    sessionStore.getAccessToken()?.let { header("Authorization", "Bearer $it") }
                }
                .build()

            val socket = client.newWebSocket(request, object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    retryAttempt = 0
                    reconnectScheduled.set(false)
                    sockets[path] = webSocket
                }

                override fun onMessage(webSocket: WebSocket, text: String) {
                    trySend(text)
                }

                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                    sockets.remove(path, webSocket)
                    if (!stopped.get()) launchReconnect()
                }

                override fun onFailure(webSocket: WebSocket, error: Throwable, response: Response?) {
                    sockets.remove(path, webSocket)
                    if (!stopped.get()) launchReconnect()
                }

                private fun launchReconnect() {
                    if (!reconnectScheduled.compareAndSet(false, true)) return
                    val delayMillis = (1_000L shl retryAttempt.coerceAtMost(5)).coerceAtMost(30_000L)
                    retryAttempt++
                    launch {
                        delay(delayMillis)
                        reconnectScheduled.set(false)
                        connect()
                    }
                }
            })
            sockets[path] = socket
        }

        connect()
        awaitClose {
            stopped.set(true)
            sockets.remove(path)?.close(1000, "Screen closed")
        }
    }

    override fun send(path: String, text: String): Boolean = sockets[path]?.send(text) == true

    override fun close(path: String) {
        sockets.remove(path)?.close(1000, "Closed")
    }

    override fun closeAll() {
        sockets.entries.toList().forEach { (path, socket) ->
            sockets.remove(path, socket)
            socket.close(1000, "Session closed")
        }
    }
}
