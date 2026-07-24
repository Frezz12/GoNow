package frezzy.gonow.core

import org.junit.Assert.assertEquals
import org.junit.Test

class AppLanguageTest {
    @Test fun exposesIosLocaleSet() {
        assertEquals(9, AppLanguage.entries.size)
        assertEquals(
            listOf(null, "ru", "en", "en-US", "de", "fr", "es", "pt-BR", "zh-Hans"),
            AppLanguage.entries.map { it.tag }
        )
    }

    @Test fun usesSafeFallbacks() {
        assertEquals(AppLanguage.SYSTEM, AppLanguage.fromTag(null))
        assertEquals(AppLanguage.ENGLISH, AppLanguage.fromTag("unknown"))
        assertEquals(AppLanguage.PORTUGUESE_BRAZIL, AppLanguage.fromTag("pt-br"))
    }
}
