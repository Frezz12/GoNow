package frezzy.gonow.models

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ContractDecodingTest {
    private val json = Json { ignoreUnknownKeys = true }

    @Test fun decodesNotificationDestinationAndPayload() {
        val value = json.decodeFromString<GoNowNotification>(
            """{"id":"n1","category":"activities","kind":"activity_application","title":"Заявка","body":"Новая заявка","entityType":"activity","entityId":"a1","actionPath":"gonow://activities/a1","payload":{"applicationId":"p1"},"isRead":false,"createdAt":"2026-07-22T10:00:00Z"}"""
        )
        assertEquals(NotificationDestination.Activity("a1"), value.destination)
        assertEquals("p1", value.payload.applicationId)
    }

    @Test fun decodesProfileMediaBackwardCompatibly() {
        val value = json.decodeFromString<ProfilePhotos>(
            """{"avatar":{"id":"p1","contentType":"image/jpeg","bytes":12,"createdAt":"2026-07-22T10:00:00Z","contentPath":"users/me/photos/p1/content"},"photos":[]}"""
        )
        assertEquals("p1", value.avatar?.id)
        assertTrue(value.avatars.isEmpty())
        assertEquals(0, value.avatar?.likeCount)
    }

    @Test fun decodesBackendMapImageUrl() {
        val value = json.decodeFromString<MapActivityResponse>(
            """{"id":"a1","title":"Walk","category":"walking","coordinate":{"latitude":55.75,"longitude":37.61},"imageUrl":"activities/a1/photos/p1/content"}"""
        )
        assertEquals("activities/a1/photos/p1/content", value.imageURL)
    }

    @Test fun decodesRealtimeEvents() {
        val chat = json.decodeFromString<ChatRealtimeEvent>(
            """{"event":"message","conversationId":"c1","messageId":"m1","userId":"u1"}"""
        )
        assertEquals("m1", chat.messageId)
        val notification = json.decodeFromString<NotificationRealtimeEvent>(
            """{"event":"created","kind":"message","recipientId":"u1","notificationId":"n1","unreadCount":4}"""
        )
        assertEquals(4, notification.unreadCount)
    }
}
