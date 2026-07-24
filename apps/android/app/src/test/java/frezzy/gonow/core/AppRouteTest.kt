package frezzy.gonow.core

import org.junit.Assert.assertEquals
import org.junit.Test

class AppRouteTest {
    @Test fun parsesBackendActionPaths() {
        assertEquals(AppRoute.ActivityDetail("a1"), AppRoute.parse("gonow://activities/a1"))
        assertEquals(AppRoute.Conversation("c1"), AppRoute.parse("gonow://chats/c1"))
        assertEquals(AppRoute.PublicProfile("u1"), AppRoute.parse("gonow://people/u1"))
        assertEquals(AppRoute.Social, AppRoute.parse("gonow://invitations/i1"))
    }

    @Test fun rejectsUnknownAndMalformedRoutes() {
        assertEquals(null, AppRoute.parse("gonow://unknown/value"))
        assertEquals(null, AppRoute.parse("not a uri"))
    }
}
