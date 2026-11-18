package com.example.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AccountTree
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.ErrorOutline
import androidx.compose.material.icons.rounded.ExpandLess
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Save
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.data.local.UserPreferences
import com.example.data.model.ApiTraceEntry
import com.example.data.model.WebDiscoveryResult
import com.example.ui.theme.HdEmerald
import com.example.ui.theme.HdEmeraldContainer
import com.example.ui.theme.JioCrimson
import com.example.ui.theme.JioCrimsonContainer
import com.example.ui.theme.LiveCyan

@Composable
fun ApiChainScreen(
    traceEntries: List<ApiTraceEntry>,
    lastDiscovery: WebDiscoveryResult?,
    preferences: UserPreferences,
    onRerunDiscoveryChain: () -> Unit,
    onSaveCustomBaseUrl: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    var baseUrlInput by remember(preferences.customApiBaseUrl) {
        mutableStateOf(preferences.customApiBaseUrl)
    }

    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .testTag("api_chain_list"),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item(key = "header") {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    text = "Website Request Initiator Chain",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "Live network trace starting from https://www.jiotv.com/tv-guide across CDN & EPG endpoints.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        item(key = "blueprint_card") {
            Card(
                shape = RoundedCornerShape(18.dp),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainer
                ),
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.AccountTree,
                            contentDescription = null,
                            tint = LiveCyan
                        )
                        Text(
                            text = "JioTV Web Initiator Graph",
                            style = MaterialTheme.typography.titleMedium
                        )
                    }

                    val chainSteps = listOf(
                        "1. Document Root → https://www.jiotv.com/tv-guide",
                        "2. Next.js Data → /_next/data/{buildId}/tv-guide.json",
                        "3. Dictionary → jiotv.data.cdn.jio.com/apis/v1.3/dictionary/get",
                        "4. Channels → jiotv.data.cdn.jio.com/apis/v3.1/getMobileChannelList/get/",
                        "5. EPG Schedule → jiotv.data.cdn.jio.com/apis/v1.3/getepg/get",
                        "6. Media CDN → jiotvimages.cdn.jio.com & jiotv.catchup.cdn.jio.com"
                    )
                    chainSteps.forEach { step ->
                        Text(
                            text = step,
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }

                    if (lastDiscovery != null) {
                        Surface(
                            shape = RoundedCornerShape(10.dp),
                            color = MaterialTheme.colorScheme.surfaceContainerHigh
                        ) {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(10.dp),
                                verticalArrangement = Arrangement.spacedBy(4.dp)
                            ) {
                                Text(
                                    text = "Discovery Status: HTTP ${lastDiscovery.statusCode ?: "N/A"} • Next Build: ${lastDiscovery.nextBuildId ?: "Not exposed"}",
                                    style = MaterialTheme.typography.labelMedium,
                                    color = LiveCyan
                                )
                                if (lastDiscovery.discoveredEndpoints.isNotEmpty()) {
                                    Text(
                                        text = "Discovered in HTML: ${lastDiscovery.discoveredEndpoints.joinToString(", ")}",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }
                    }

                    Button(
                        onClick = onRerunDiscoveryChain,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(48.dp)
                            .testTag("rerun_chain_button")
                    ) {
                        Icon(Icons.Rounded.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Run Full Initiator Chain")
                    }
                }
            }
        }

        item(key = "proxy_config") {
            Card(
                shape = RoundedCornerShape(18.dp),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainer
                ),
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Text(
                        text = "Optional Custom API Base / Relay URL",
                        style = MaterialTheme.typography.titleSmall
                    )
                    Text(
                        text = "Leave blank to use official JioTV CDN APIs directly. Useful if JioTV geo-blocks non-Indian IPs and you run a JioTV relay.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    OutlinedTextField(
                        value = baseUrlInput,
                        onValueChange = { baseUrlInput = it },
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag("custom_base_url_input"),
                        placeholder = { Text("https://your-jiotv-relay.example.com") },
                        singleLine = true,
                        shape = RoundedCornerShape(12.dp)
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Button(
                            onClick = { onSaveCustomBaseUrl(baseUrlInput) },
                            modifier = Modifier
                                .weight(1f)
                                .height(48.dp)
                                .testTag("save_base_url_button")
                        ) {
                            Icon(Icons.Rounded.Save, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(6.dp))
                            Text("Apply & Reload")
                        }
                        if (baseUrlInput.isNotBlank()) {
                            OutlinedButton(
                                onClick = {
                                    baseUrlInput = ""
                                    onSaveCustomBaseUrl("")
                                },
                                modifier = Modifier.height(48.dp)
                            ) {
                                Text("Reset")
                            }
                        }
                    }
                }
            }
        }

        item(key = "trace_title") {
            Text(
                text = "Recorded Network Calls (${traceEntries.size})",
                style = MaterialTheme.typography.titleMedium
            )
        }

        items(traceEntries.reversed(), key = { it.id }) { entry ->
            ApiTraceCard(entry = entry)
        }
    }
}

@Composable
private fun ApiTraceCard(entry: ApiTraceEntry) {
    var expanded by remember(entry.id) { mutableStateOf(false) }

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { expanded = !expanded }
            .testTag("trace_card_${entry.stepOrder}"),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainer
        ),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(
                    imageVector = if (entry.isSuccess) Icons.Rounded.CheckCircle else Icons.Rounded.ErrorOutline,
                    contentDescription = null,
                    tint = if (entry.isSuccess) HdEmerald else JioCrimson,
                    modifier = Modifier.size(20.dp)
                )
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "#${entry.stepOrder} • ${entry.endpointLabel}",
                        style = MaterialTheme.typography.titleSmall,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = "Initiator: ${entry.initiator}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                Surface(
                    shape = RoundedCornerShape(6.dp),
                    color = if (entry.isSuccess) HdEmeraldContainer else JioCrimsonContainer
                ) {
                    Text(
                        text = "${entry.statusCode ?: "ERR"} • ${entry.durationMs}ms",
                        style = MaterialTheme.typography.labelSmall,
                        color = if (entry.isSuccess) HdEmerald else JioCrimson,
                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 3.dp)
                    )
                }
                Icon(
                    imageVector = if (expanded) Icons.Rounded.ExpandLess else Icons.Rounded.ExpandMore,
                    contentDescription = if (expanded) "Collapse" else "Expand"
                )
            }

            Text(
                text = entry.summary,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface
            )

            AnimatedVisibility(visible = expanded) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(
                            MaterialTheme.colorScheme.surfaceContainerHigh,
                            RoundedCornerShape(10.dp)
                        )
                        .padding(10.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text(
                        text = "${entry.method} ${entry.url}",
                        style = MaterialTheme.typography.labelSmall,
                        color = LiveCyan
                    )
                    if (!entry.contentType.isNullOrBlank()) {
                        Text(
                            text = "Content-Type: ${entry.contentType}",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Text(
                        text = entry.rawSnippet,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}
