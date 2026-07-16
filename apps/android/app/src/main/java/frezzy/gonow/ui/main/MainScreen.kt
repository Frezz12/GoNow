package frezzy.gonow.ui.main

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import frezzy.gonow.models.User
import frezzy.gonow.ui.theme.*

data class BottomNavItem(
    val index: Int,
    val label: String,
    val selectedIcon: ImageVector,
    val unselectedIcon: ImageVector
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(
    user: User?,
    viewModel: MainViewModel,
    onRefreshProfile: () -> Unit,
    onLogout: () -> Unit,
    isRefreshing: Boolean
) {
    val items = listOf(
        BottomNavItem(0, "Карта", Icons.Filled.Map, Icons.Outlined.Map),
        BottomNavItem(1, "Задания", Icons.Filled.Checklist, Icons.Outlined.Checklist),
        BottomNavItem(2, "Чат", Icons.Filled.Chat, Icons.Outlined.Chat),
        BottomNavItem(3, "Профиль", Icons.Filled.Person, Icons.Outlined.Person)
    )

    var showCreateSheet by remember { mutableStateOf(false) }

    Scaffold(
        containerColor = Color.Transparent,
        bottomBar = {
            Box {
                NavigationBar(
                    containerColor = GlassBackground,
                    tonalElevation = 0.dp
                ) {
                    items.forEachIndexed { index, item ->
                        if (index == 2) {
                            // Spacer for center FAB
                            NavigationBarItem(
                                icon = { Spacer(Modifier.size(24.dp)) },
                                label = { Spacer(Modifier) },
                                selected = false,
                                onClick = {},
                                enabled = false,
                                colors = NavigationBarItemDefaults.colors(
                                    disabledIconColor = Color.Transparent,
                                    disabledTextColor = Color.Transparent
                                )
                            )
                        }
                        NavigationBarItem(
                            icon = {
                                Icon(
                                    imageVector = if (viewModel.selectedTab == item.index)
                                        item.selectedIcon else item.unselectedIcon,
                                    contentDescription = item.label
                                )
                            },
                            label = { Text(item.label, fontSize = 11.sp) },
                            selected = viewModel.selectedTab == item.index,
                            onClick = { viewModel.selectTab(item.index) },
                            colors = NavigationBarItemDefaults.colors(
                                selectedIconColor = Primary,
                                selectedTextColor = Primary,
                                unselectedIconColor = TextSecondary,
                                unselectedTextColor = TextSecondary,
                                indicatorColor = Primary.copy(alpha = 0.12f)
                            )
                        )
                    }
                }

                // Center FAB pill
                Box(
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .offset(y = (-16).dp)
                ) {
                    val gradient = Brush.horizontalGradient(
                        colors = listOf(ButtonStart, ButtonEnd)
                    )
                    val shape = RoundedCornerShape(26.dp)

                    Surface(
                        onClick = { showCreateSheet = true },
                        shape = shape,
                        color = Color.Transparent,
                        shadowElevation = 8.dp
                    ) {
                        Row(
                            modifier = Modifier
                                .background(gradient)
                                .padding(horizontal = 18.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Surface(
                                shape = androidx.compose.foundation.shape.CircleShape,
                                color = Color.White.copy(alpha = 0.2f),
                                modifier = Modifier.size(24.dp)
                            ) {
                                Icon(
                                    imageVector = Icons.Filled.Add,
                                    contentDescription = null,
                                    tint = Color.White,
                                    modifier = Modifier.padding(4.dp)
                                )
                            }
                            Text(
                                text = "Создать",
                                color = Color.White,
                                fontWeight = FontWeight.SemiBold,
                                fontSize = 14.sp
                            )
                        }
                    }
                }
            }
        }
    ) { padding ->
        Box(modifier = Modifier.padding(padding)) {
            when (viewModel.selectedTab) {
                MainViewModel.TAB_MAP -> MapTab()
                MainViewModel.TAB_TASKS -> TasksTab()
                MainViewModel.TAB_CHAT -> ChatTab()
                MainViewModel.TAB_PROFILE -> ProfileTab(
                    user = user,
                    onRefresh = onRefreshProfile,
                    onLogout = onLogout,
                    isLoading = isRefreshing
                )
            }
        }
    }

    if (showCreateSheet) {
        CreateTaskSheet(onDismiss = { showCreateSheet = false })
    }
}
