package frezzy.gonow.network

import frezzy.gonow.data.SessionStore
import frezzy.gonow.models.ApiError
import frezzy.gonow.models.TokenSet
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okhttp3.mockwebserver.SocketPolicy
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class ApiClientRefreshTest {
    private lateinit var server: MockWebServer
    private lateinit var store: FakeSessionStore

    @Before fun setUp() {
        server = MockWebServer()
        server.start()
        store = FakeSessionStore(TokenSet("old-access", "refresh-token", "2026-07-22T10:00:00Z"))
    }

    @After fun tearDown() {
        server.shutdown()
    }

    @Test fun concurrent401ResponsesUseOneRefresh() = runBlocking {
        val refreshes = AtomicInteger()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = when (request.path) {
                "/api/v1/auth/refresh" -> {
                    refreshes.incrementAndGet()
                    jsonResponse(authEnvelope("new-access"))
                }
                "/api/v1/users/me" -> if (request.getHeader("Authorization") == "Bearer new-access") {
                    jsonResponse(userEnvelope())
                } else {
                    MockResponse().setResponseCode(401)
                }
                else -> MockResponse().setResponseCode(404)
            }
        }
        val client = client()

        val users = (1..4).map {
            async(Dispatchers.IO) { client.authenticatedRequest { client.api.getCurrentUser().data } }
        }.awaitAll()

        assertEquals(4, users.size)
        assertEquals(1, refreshes.get())
        assertEquals("new-access", store.getAccessToken())
        assertEquals(0, store.clearCount)
    }

    @Test fun refreshServerFailureDoesNotClearSession() = runBlocking {
        server.dispatcher = refreshFailureDispatcher(500)
        val client = client()
        val result = runCatching { client.authenticatedRequest { client.api.getCurrentUser().data } }
        assertTrue(result.exceptionOrNull() is ApiError.Server)
        assertEquals("refresh-token", store.getRefreshToken())
        assertEquals(0, store.clearCount)
    }

    @Test fun rejectedRefreshClearsSession() = runBlocking {
        server.dispatcher = refreshFailureDispatcher(401)
        val client = client()
        val result = runCatching { client.authenticatedRequest { client.api.getCurrentUser().data } }
        assertTrue(result.exceptionOrNull() is ApiError.Unauthorized)
        assertEquals(1, store.clearCount)
    }

    @Test fun transportFailureDoesNotClearSession() = runBlocking {
        server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AT_START))
        val client = client()
        val result = runCatching { client.authenticatedRequest { client.api.getCurrentUser().data } }
        assertTrue(result.exceptionOrNull() is ApiError.Network)
        assertEquals("refresh-token", store.getRefreshToken())
        assertEquals(0, store.clearCount)
    }

    @Test fun activityPhotoUploadUsesExpectedMultipartContract() = runBlocking {
        server.enqueue(jsonResponse("""{"data":{"id":"p1","contentPath":"activities/a1/photos/p1/content","isCover":true,"sortIndex":0}}"""))
        val client = client()
        client.authenticatedRequest {
            client.api.uploadActivityPhoto("a1", 0, true, client.createImagePart(byteArrayOf(1, 2, 3), "activity.jpg"))
        }
        val request = server.takeRequest()
        assertEquals("/api/v1/activities/a1/photos?sortIndex=0&isCover=true", request.path)
        assertTrue(request.getHeader("Content-Type").orEmpty().startsWith("multipart/form-data"))
        val body = request.body.readUtf8()
        assertTrue(body.contains("name=\"file\"; filename=\"activity.jpg\""))
        assertTrue(body.contains("Content-Type: image/jpeg"))
    }

    private fun client() = ApiClient(store, server.url("/api/v1/").toString().trimEnd('/'))

    private fun refreshFailureDispatcher(code: Int) = object : Dispatcher() {
        override fun dispatch(request: RecordedRequest): MockResponse = when (request.path) {
            "/api/v1/users/me" -> MockResponse().setResponseCode(401)
            "/api/v1/auth/refresh" -> MockResponse().setResponseCode(code).setHeader("Content-Type", "application/json")
                .setBody("""{"error":{"code":"REFRESH_FAILED","message":"refresh failed","requestId":"r1"}}""")
            else -> MockResponse().setResponseCode(404)
        }
    }

    private fun jsonResponse(body: String) = MockResponse()
        .setResponseCode(200)
        .setHeader("Content-Type", "application/json")
        .setBody(body)

    private fun userEnvelope() = """{"data":${userJson()}}"""

    private fun authEnvelope(accessToken: String) =
        """{"data":{"user":${userJson()},"tokens":{"accessToken":"$accessToken","refreshToken":"new-refresh","accessTokenExpiresAt":"2026-07-23T10:00:00Z"}}}"""

    private fun userJson() =
        """{"id":"u1","email":"user@example.com","displayName":"User","username":"user_name","emailVerified":true,"createdAt":"2026-07-22T10:00:00Z"}"""
}

private class FakeSessionStore(tokens: TokenSet?) : SessionStore {
    @Volatile private var value = tokens
    var clearCount = 0
        private set

    override fun saveTokens(tokens: TokenSet) { value = tokens }
    override fun getAccessToken(): String? = value?.accessToken
    override fun getRefreshToken(): String? = value?.refreshToken
    override fun getAccessTokenExpiresAt(): String? = value?.accessTokenExpiresAt
    override fun clearTokens() { value = null; clearCount++ }
}
