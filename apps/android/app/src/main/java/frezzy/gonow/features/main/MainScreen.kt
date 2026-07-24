package frezzy.gonow.features.main

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.automirrored.outlined.Chat
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.Lifecycle
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import frezzy.gonow.features.activity.ActivityCreationSheet
import frezzy.gonow.features.activity.ActivityCreationViewModel
import frezzy.gonow.features.activity.ActivityDetailSheet
import frezzy.gonow.features.authentication.AuthViewModel
import frezzy.gonow.features.chat.ChatTab
import frezzy.gonow.features.chat.ChatViewModel
import frezzy.gonow.features.chat.ConversationSheet
import frezzy.gonow.features.map.ActivityMapViewModel
import frezzy.gonow.features.map.MapTab
import frezzy.gonow.features.notifications.NotificationsSheet
import frezzy.gonow.features.notifications.NotificationsViewModel
import frezzy.gonow.features.profile.ProfileEditorSheet
import frezzy.gonow.features.profile.ProfileTab
import frezzy.gonow.features.settings.SettingsSheet
import frezzy.gonow.features.social.SocialHubSheet
import frezzy.gonow.features.social.SocialSection
import frezzy.gonow.features.tasks.TasksTab
import frezzy.gonow.features.tasks.TasksViewModel
import frezzy.gonow.core.SettingsPrefs
import frezzy.gonow.core.AppContainer
import frezzy.gonow.core.AppRoute
import frezzy.gonow.core.location.DeviceLocationProvider
import frezzy.gonow.core.weather.WeatherViewModel
import frezzy.gonow.models.ProfileStatus
import frezzy.gonow.models.User
import frezzy.gonow.models.NotificationDestination
import frezzy.gonow.ui.theme.*
import frezzy.gonow.R

data class BottomNavItem(
    val index: Int,
    val route: String,
    val label: String,
    val selectedIcon: ImageVector,
    val unselectedIcon: ImageVector
)

private const val MAP_ROUTE = "map"
private const val TASKS_ROUTE = "tasks"
private const val CHAT_ROUTE = "chat"
private const val PROFILE_ROUTE = "profile"

@Composable
fun MainScreen(
    user: User?,
    avatarBytes: ByteArray?,
    viewModel: AuthViewModel,
    weatherViewModel: WeatherViewModel,
    locationProvider: DeviceLocationProvider,
    settingsPrefs: SettingsPrefs,
    activityMapViewModel: ActivityMapViewModel,
    activityCreationViewModel: ActivityCreationViewModel,
    chatViewModel: ChatViewModel,
    tasksViewModel: TasksViewModel,
    notificationsViewModel: NotificationsViewModel,
    appContainer: AppContainer,
    externalRoute: AppRoute?,
    onExternalRouteConsumed: () -> Unit,
    onLogout: () -> Unit
) {
    val authUiState by viewModel.uiStateFlow.collectAsStateWithLifecycle()
    val profileMediaState by viewModel.profileMediaStateFlow.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }
    LaunchedEffect(authUiState.errorMessage) {
        authUiState.errorMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearError()
        }
    }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        viewModel.refreshProfile()
        activityMapViewModel.reload()
        tasksViewModel.load()
        chatViewModel.load()
    }
    val items = listOf(
        BottomNavItem(0, MAP_ROUTE, stringResource(R.string.tab_map), Icons.Filled.Map, Icons.Outlined.Map),
        BottomNavItem(1, TASKS_ROUTE, stringResource(R.string.tab_tasks), Icons.Filled.Checklist, Icons.Outlined.Checklist),
        BottomNavItem(2, CHAT_ROUTE, stringResource(R.string.tab_chat), Icons.AutoMirrored.Filled.Chat, Icons.AutoMirrored.Outlined.Chat),
        BottomNavItem(3, PROFILE_ROUTE, stringResource(R.string.tab_profile), Icons.Filled.Person, Icons.Outlined.Person)
    )

    val tabNavController = rememberNavController()
    val currentTabRoute = tabNavController.currentBackStackEntryAsState().value?.destination?.route ?: MAP_ROUTE
    val selectedTab = items.firstOrNull { it.route == currentTabRoute }?.index ?: 0
    val selectTab: (Int) -> Unit = { index ->
        tabNavController.navigate(items.first { it.index == index }.route) {
            popUpTo(MAP_ROUTE) { saveState = true }
            launchSingleTop = true
            restoreState = true
        }
    }
    var showCreateSheet by remember { mutableStateOf(false) }
    var showProfileEditor by remember { mutableStateOf(false) }
    var showSettings by remember { mutableStateOf(false) }
    var showProfileRequiredAlert by remember { mutableStateOf(false) }
    var showNotifications by remember { mutableStateOf(false) }
    var activityConversation by remember { mutableStateOf<Pair<String, String>?>(null) }
    var activityDetailRequest by remember { mutableStateOf<Pair<String, String>?>(null) }
    var showSocialHub by remember { mutableStateOf(false) }
    var socialHubUserId by remember { mutableStateOf<String?>(null) }
    var socialHubSection by remember { mutableStateOf(SocialSection.FRIENDS) }
    LaunchedEffect(externalRoute) {
        when (val route = externalRoute) {
            is AppRoute.ActivityDetail -> activityDetailRequest = route.id to "Активность"
            is AppRoute.Conversation -> activityConversation = route.id to route.title
            is AppRoute.PublicProfile -> {
                socialHubUserId = route.id
                socialHubSection = SocialSection.PEOPLE
                showSocialHub = true
            }
            AppRoute.Social -> {
                socialHubUserId = null
                socialHubSection = SocialSection.FRIENDS
                showSocialHub = true
            }
            AppRoute.Notifications -> showNotifications = true
            null -> Unit
        }
        if (externalRoute != null) onExternalRouteConsumed()
    }

    Box(modifier = Modifier.fillMaxSize()) {
        Scaffold(
            containerColor = Color.Transparent,
            snackbarHost = { SnackbarHost(snackbarHostState) },
            bottomBar = {
                Surface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 10.dp),
                    shape = RoundedCornerShape(28.dp),
                    color = MaterialTheme.colorScheme.surface.copy(alpha = 0.94f),
                    shadowElevation = 5.dp,
                    tonalElevation = 1.dp
                ) {
                    NavigationBar(
                        containerColor = Color.Transparent,
                        tonalElevation = 0.dp
                    ) {
                        items.forEach { item ->
                            NavigationBarItem(
                                icon = {
                                    Icon(
                                        imageVector = if (selectedTab == item.index) item.selectedIcon else item.unselectedIcon,
                                        contentDescription = item.label
                                    )
                                },
                                label = { Text(item.label, fontSize = 11.sp) },
                                selected = selectedTab == item.index,
                                onClick = { selectTab(item.index) },
                                colors = NavigationBarItemDefaults.colors(
                                    selectedIconColor = MaterialTheme.colorScheme.primary,
                                    selectedTextColor = MaterialTheme.colorScheme.primary,
                                    unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                                    unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant,
                                    indicatorColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.82f)
                                )
                            )
                        }
                    }
                }
            }
        ) { padding ->
            NavHost(
                navController = tabNavController,
                startDestination = MAP_ROUTE,
                modifier = Modifier.padding(padding)
            ) {
                composable(MAP_ROUTE) {
                    MapTab(
                        user = user,
                        avatarBytes = avatarBytes,
                        onNavigateToProfile = { selectTab(3) },
                        onNotificationsTap = { showNotifications = true },
                        weatherViewModel = weatherViewModel,
                        locationProvider = locationProvider,
                        settingsPrefs = settingsPrefs,
                        mapViewModel = activityMapViewModel,
                        notificationUnreadCount = notificationsViewModel.unreadCount,
                        onActivityOpen = { id, title -> activityDetailRequest = id to title }
                    )
                }
                composable(TASKS_ROUTE) {
                    TasksTab(
                        mapViewModel = activityMapViewModel,
                        tasksViewModel = tasksViewModel,
                        onActivitySelected = { id -> activityDetailRequest = id to "Активность" }
                    )
                }
                composable(CHAT_ROUTE) {
                    ChatTab(
                        chatViewModel = chatViewModel,
                        socialRepository = appContainer.socialRepository,
                        mediaCache = appContainer.mediaCache,
                        onOpenSocial = { section ->
                            socialHubUserId = null
                            socialHubSection = section
                            showSocialHub = true
                        }
                    )
                }
                composable(PROFILE_ROUTE) {
                    ProfileTab(
                        user = user,
                        avatarBytes = avatarBytes,
                        profilePhotos = profileMediaState.profilePhotos.photos,
                        avatarHistory = profileMediaState.profilePhotos.avatars,
                        photoContentFiles = profileMediaState.photoContentFiles,
                        unavailablePhotoIds = profileMediaState.unavailablePhotoIds,
                        onRefresh = { viewModel.refreshProfile() },
                        onLogout = onLogout,
                        onEditProfile = { showProfileEditor = true },
                        onOpenSocial = {
                            socialHubUserId = null
                            socialHubSection = SocialSection.FRIENDS
                            showSocialHub = true
                        },
                        onSettings = { showSettings = true },
                        onUploadAvatar = { viewModel.uploadAvatar(it) },
                        onUploadPhoto = { viewModel.uploadPhoto(it) },
                        onDeletePhoto = { viewModel.deletePhoto(it) },
                        onUpdatePhotoDescription = viewModel::updatePhotoDescription,
                        onTogglePhotoLike = viewModel::togglePhotoLike,
                        onLoadPhotoContent = { viewModel.loadPhotoContent(it) },
                        isLoading = authUiState.isLoading
                    )
                }
            }
        }

        // Floating "Создать" button — only on Map tab
        if (selectedTab == 0) {
            Box(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 168.dp)
            ) {
                val shape = RoundedCornerShape(26.dp)

                Surface(
                    onClick = {
                        if (user?.profileStatus == ProfileStatus.REQUIRED) {
                            showProfileRequiredAlert = true
                        } else {
                            showCreateSheet = true
                        }
                    },
                    shape = shape,
                    color = Color.Transparent,
                    shadowElevation = 4.dp
                ) {
                    Row(
                        modifier = Modifier
                            .background(
                                Brush.horizontalGradient(listOf(ButtonStart, ButtonMid, ButtonEnd)),
                                shape
                            )
                            .padding(horizontal = 24.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Icon(Icons.Filled.Add, contentDescription = null, tint = MaterialTheme.colorScheme.onPrimary, modifier = Modifier.size(20.dp))
                        Text("Создать", color = MaterialTheme.colorScheme.onPrimary, fontWeight = FontWeight.Bold, fontSize = 15.sp)
                    }
                }
            }
        }
    }

    if (showCreateSheet) {
        ActivityCreationSheet(
            viewModel = activityCreationViewModel,
            locationProvider = locationProvider,
            mapStyleJson = activityMapViewModel.mapStyleJson,
            onDismiss = {
                val createdActivity = activityCreationViewModel.publishedActivity
                val createdCoordinate = activityCreationViewModel.draft.latitude?.let { latitude ->
                    activityCreationViewModel.draft.longitude?.let { longitude ->
                        frezzy.gonow.models.MapCoordinate(latitude, longitude)
                    }
                }
                showCreateSheet = false
                createdActivity?.let { activityMapViewModel.showCreatedActivity(it, createdCoordinate) }
                if (createdActivity != null) {
                    activityCreationViewModel.reset()
                }
                activityMapViewModel.reload()
            }
        )
    }

    if (showProfileEditor && user != null) {
        ProfileEditorSheet(
            user = user,
            avatarBytes = avatarBytes,
            onSave = { request -> viewModel.updateProfile(request); showProfileEditor = false },
            onUploadAvatar = { viewModel.uploadAvatar(it) },
            onDismiss = { showProfileEditor = false },
            isLoading = authUiState.isLoading,
            errorMessage = authUiState.errorMessage
        )
    }

    if (showSettings) {
        SettingsSheet(
            settingsPrefs = settingsPrefs,
            notificationRepository = appContainer.notificationRepository,
            socialRepository = appContainer.socialRepository,
            onDismiss = { showSettings = false },
            onLogout = { showSettings = false; onLogout() }
        )
    }

    if (showProfileRequiredAlert) {
        AlertDialog(
            onDismissRequest = { showProfileRequiredAlert = false },
            title = { Text("Сначала заполните профиль") },
            text = { Text("Укажите дату рождения, чтобы создавать задания и подавать заявки на активности.") },
            confirmButton = {
                TextButton(onClick = { showProfileRequiredAlert = false; selectTab(3) }) {
                    Text("Перейти в профиль")
                }
            },
            dismissButton = {
                TextButton(onClick = { showProfileRequiredAlert = false }) {
                    Text("Позже")
                }
            }
        )
    }

    activityDetailRequest?.let { (activityId, title) ->
        ActivityDetailSheet(
            repository = appContainer.activityRepository,
            mediaCache = appContainer.mediaCache,
            activityId = activityId,
            initialTitle = title,
            onOpenChat = { conversationId, title ->
                activityConversation = conversationId to title
            },
            onDismiss = {
                activityDetailRequest = null
                activityMapViewModel.clearSelection()
            }
        )
    }

    if (showNotifications) {
        NotificationsSheet(
            viewModel = notificationsViewModel,
            onDestination = { destination ->
                when (destination) {
                    is NotificationDestination.Activity -> activityDetailRequest = destination.id to "Активность"
                    is NotificationDestination.Conversation -> activityConversation = destination.id to destination.title
                    is NotificationDestination.User -> {
                        socialHubUserId = destination.id
                        socialHubSection = SocialSection.PEOPLE
                        showSocialHub = true
                    }
                    NotificationDestination.Social -> {
                        socialHubUserId = null
                        socialHubSection = SocialSection.INVITATIONS
                        showSocialHub = true
                    }
                }
            },
            onDismiss = { showNotifications = false }
        )
    }

    if (showSocialHub) {
        SocialHubSheet(
            repository = appContainer.socialRepository,
            initialSection = socialHubSection,
            initialUserId = socialHubUserId,
            onConversation = { conversation ->
                showSocialHub = false
                socialHubUserId = null
                activityConversation = conversation.id to conversation.title
            },
            onDismiss = {
                showSocialHub = false
                socialHubUserId = null
            }
        )
    }

    activityConversation?.let { (conversationId, title) ->
        ConversationSheet(
            repository = appContainer.socialRepository,
            mediaCache = appContainer.mediaCache,
            conversationId = conversationId,
            title = title,
            onDismiss = { activityConversation = null }
        )
    }
}
