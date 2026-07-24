package frezzy.gonow.models

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class UsernameRulesTest {
    @Test fun normalizesAtPrefixWhitespaceAndCase() {
        assertEquals("nikolay_26", UsernameRules.normalize(" @Nikolay_26 "))
    }

    @Test fun validatesBackendRules() {
        assertNull(UsernameRules.validationMessage("nikolay_26"))
        assertNotNull(UsernameRules.validationMessage("26nikolay"))
        assertNotNull(UsernameRules.validationMessage("николай"))
        assertNotNull(UsernameRules.validationMessage("admin"))
    }
}
