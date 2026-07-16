package frezzy.gonow.ui.main

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel

class MainViewModel : ViewModel() {

    var selectedTab by mutableIntStateOf(0)
        private set

    fun selectTab(index: Int) {
        selectedTab = index
    }

    companion object {
        const val TAB_MAP = 0
        const val TAB_TASKS = 1
        const val TAB_CHAT = 2
        const val TAB_PROFILE = 3
    }
}
