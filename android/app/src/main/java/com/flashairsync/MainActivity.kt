package com.flashairsync

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
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
import com.flashairsync.core.FlashAirClient
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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
    // State
    var isLoading by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }

    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    // Development host - 10.0.2.2 routes to host machine's localhost in Android emulator
    val host = "http://10.0.2.2:8080"
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
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
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
                text = if (isLoading) "Connecting..." else "Ready to sync",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(bottom = 32.dp)
            )

            Button(
                onClick = {
                    scope.launch {
                        isLoading = true
                        error = null
                        result = null

                        try {
                            val client = FlashAirClient(host)
                            val entries = client.listDirectory("/DCIM")

                            val fileCount = entries.count { !it.isDirectory }
                            val dirCount = entries.count { it.isDirectory }

                            result = buildString {
                                appendLine("✅ Connected to FlashAir!")
                                appendLine()
                                appendLine("Found in /DCIM:")
                                appendLine("• $dirCount directories")
                                appendLine("• $fileCount files")
                                appendLine()
                                appendLine("Entries:")
                                entries.forEach { entry ->
                                    val icon = if (entry.isDirectory) "📁" else "📄"
                                    val size = if (entry.isDirectory) "" else " (${formatBytes(entry.size)})"
                                    appendLine("$icon ${entry.name}$size")
                                }
                            }
                        } catch (e: Exception) {
                            error = "❌ Error: ${e.message}\n\nMake sure mock server is running at:\n$host"
                        } finally {
                            isLoading = false
                        }
                    }
                },
                enabled = !isLoading,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp)
            ) {
                if (isLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(24.dp),
                        color = MaterialTheme.colorScheme.onPrimary
                    )
                } else {
                    Text("Connect & List /DCIM")
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Result display
            result?.let {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.primaryContainer
                    )
                ) {
                    Text(
                        text = it,
                        modifier = Modifier.padding(16.dp),
                        style = MaterialTheme.typography.bodySmall,
                        fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                    )
                }
            }

            // Error display
            error?.let {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer
                    )
                ) {
                    Text(
                        text = it,
                        modifier = Modifier.padding(16.dp),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onErrorContainer
                    )
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            Text(
                text = "Dev Host: $host",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 16.dp)
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

private fun formatBytes(bytes: Long): String {
    val kb = bytes / 1024.0
    val mb = kb / 1024.0
    return when {
        mb >= 1.0 -> String.format("%.2f MB", mb)
        kb >= 1.0 -> String.format("%.2f KB", kb)
        else -> "$bytes B"
    }
}
