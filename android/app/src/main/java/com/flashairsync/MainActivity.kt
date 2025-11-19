package com.flashairsync

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.flashairsync.core.*
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    // Permission launcher for WiFi (Android 13+)
    private val wifiPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { isGranted ->
        permissionGranted = isGranted
    }

    // Permission launcher for location (Android 10-12)
    private val locationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { isGranted ->
        permissionGranted = isGranted
    }

    // Permission launcher for media (Android 13+)
    private val mediaPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        permissionGranted = permissions.values.all { it }
    }

    private var permissionGranted by mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Request permissions on startup
        requestPermissions()

        setContent {
            FlashAirSyncTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    ImportScreen()
                }
            }
        }
    }

    private fun requestPermissions() {
        when {
            // Android 13+ (API 33+): Need NEARBY_WIFI_DEVICES and READ_MEDIA_*
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> {
                // Request WiFi permission
                wifiPermissionLauncher.launch(Manifest.permission.NEARBY_WIFI_DEVICES)

                // Request media permissions
                mediaPermissionLauncher.launch(
                    arrayOf(
                        Manifest.permission.READ_MEDIA_IMAGES,
                        Manifest.permission.READ_MEDIA_VIDEO
                    )
                )
            }

            // Android 10-12 (API 29-32): Need ACCESS_FINE_LOCATION for WiFi
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q -> {
                locationPermissionLauncher.launch(Manifest.permission.ACCESS_FINE_LOCATION)
            }

            // Android 9 and below: Need WRITE_EXTERNAL_STORAGE
            else -> {
                // Permissions handled via manifest for older versions
                permissionGranted = true
            }
        }
    }
}

@Composable
fun FlashAirSyncTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = lightColorScheme(),
        content = content
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ImportScreen() {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    // Load settings from build configuration (debug = mock server, release = real FlashAir)
    val settings = remember {
        SyncSettings(
            ssid = context.getString(R.string.flashair_ssid),
            passphrase = context.getString(R.string.flashair_passphrase),
            host = context.getString(R.string.flashair_host)
        )
    }

    val useMockServer = remember {
        context.resources.getBoolean(R.bool.use_mock_server)
    }

    val syncEngine = remember {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            SyncEngine(context, settings)
        } else {
            null
        }
    }

    val syncState by if (syncEngine != null) {
        syncEngine.syncState.collectAsState()
    } else {
        remember { mutableStateOf(SyncState.Idle) }
    }

    val importItems by if (syncEngine != null) {
        syncEngine.importItems.collectAsState()
    } else {
        remember { mutableStateOf(emptyList()) }
    }

    val gitCommitId = context.getString(R.string.git_commit_id)

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("FlashAir Sync") },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer,
                    titleContentColor = MaterialTheme.colorScheme.onPrimaryContainer
                )
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(24.dp)
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Header
            Text(
                text = "📡",
                style = MaterialTheme.typography.displayLarge,
                modifier = Modifier.padding(bottom = 16.dp)
            )

            Text(
                text = "FlashAir Photo Importer",
                style = MaterialTheme.typography.headlineMedium,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(bottom = 8.dp)
            )

            Text(
                text = syncState.statusMessage,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(bottom = 32.dp)
            )

            // Progress indicator
            if (syncState.isActive) {
                LinearProgressIndicator(
                    progress = syncState.progressPercent,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(bottom = 16.dp)
                )
            }

            // Start/Cancel button
            if (syncEngine != null) {
                if (syncState.isActive) {
                    Button(
                        onClick = { syncEngine.cancel() },
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.error
                        ),
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(56.dp)
                    ) {
                        Text("Cancel Sync")
                    }
                } else {
                    Button(
                        onClick = {
                            scope.launch {
                                try {
                                    syncEngine.startSync("/DCIM")
                                } catch (e: Exception) {
                                    // Error is already captured in syncState
                                }
                            }
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(56.dp)
                    ) {
                        Text("Start Sync")
                    }
                }
            } else {
                // Android 9 or below
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer
                    )
                ) {
                    Text(
                        text = "⚠️ This app requires Android 10 or later",
                        modifier = Modifier.padding(16.dp),
                        color = MaterialTheme.colorScheme.onErrorContainer
                    )
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Import items list
            if (importItems.isNotEmpty()) {
                Card(
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp)
                    ) {
                        Text(
                            text = "Files (${importItems.size})",
                            style = MaterialTheme.typography.titleMedium,
                            modifier = Modifier.padding(bottom = 8.dp)
                        )

                        importItems.take(10).forEach { item ->
                            ImportItemRow(item)
                        }

                        if (importItems.size > 10) {
                            Text(
                                text = "... and ${importItems.size - 10} more",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(top = 8.dp)
                            )
                        }
                    }
                }
            }

            // Result display
            if (syncState is SyncState.Completed) {
                val result = (syncState as SyncState.Completed).result
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 16.dp),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.primaryContainer
                    )
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text(
                            text = "✅ Sync Complete",
                            style = MaterialTheme.typography.titleMedium,
                            modifier = Modifier.padding(bottom = 8.dp)
                        )
                        Text(
                            text = result.summary,
                            style = MaterialTheme.typography.bodySmall,
                            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                        )
                    }
                }
            }

            // Error display
            if (syncState is SyncState.Failed) {
                val error = (syncState as SyncState.Failed).error
                val errorHint = if (useMockServer) {
                    "\n\nMake sure mock server is running at:\n${settings.host}"
                } else {
                    "\n\nMake sure:\n• FlashAir card is powered on\n• Device is in range\n• SSID: ${settings.ssid}"
                }
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 16.dp),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer
                    )
                ) {
                    Text(
                        text = "❌ Error: $error$errorHint",
                        modifier = Modifier.padding(16.dp),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onErrorContainer
                    )
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            // Footer
            Text(
                text = if (useMockServer) "Mode: Mock Server" else "Mode: Real FlashAir",
                style = MaterialTheme.typography.bodySmall,
                color = if (useMockServer) MaterialTheme.colorScheme.secondary else MaterialTheme.colorScheme.primary,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 16.dp)
            )

            Text(
                text = "Host: ${settings.host}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 4.dp)
            )

            Text(
                text = "Build: $gitCommitId",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 4.dp)
            )
        }
    }
}

@Composable
fun ImportItemRow(item: ImportItem) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = item.entry.name,
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.weight(1f)
        )

        when (val state = item.state) {
            is ImportState.Pending -> Text("⏳", style = MaterialTheme.typography.bodySmall)
            is ImportState.Downloading -> Text(
                "${(state.progress * 100).toInt()}%",
                style = MaterialTheme.typography.bodySmall
            )
            is ImportState.Saving -> Text("💾", style = MaterialTheme.typography.bodySmall)
            is ImportState.Completed -> Text("✅", style = MaterialTheme.typography.bodySmall)
            is ImportState.Failed -> Text("❌", style = MaterialTheme.typography.bodySmall)
            is ImportState.Skipped -> Text("⏭️", style = MaterialTheme.typography.bodySmall)
        }
    }
}

private fun formatBytes(bytes: Long): String {
    val kb = bytes / 1024.0
    val mb = kb / 1024.0
    return when {
        mb >= 1.0 -> String.format("%.2f MB", mb)
        kb >= 1.0 -> String.format("%.2f KB", kb)
        else -> "$bytes B"
    }
}
