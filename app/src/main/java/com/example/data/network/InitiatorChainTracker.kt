package com.example.data.network

import com.example.data.model.ApiTraceEntry
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import java.util.UUID
import java.util.concurrent.atomic.AtomicInteger

class InitiatorChainTracker {
    private val stepCounter = AtomicInteger(0)
    private val _traces = MutableStateFlow<List<ApiTraceEntry>>(emptyList())
    val traces: StateFlow<List<ApiTraceEntry>> = _traces.asStateFlow()

    fun clear() {
        stepCounter.set(0)
        _traces.value = emptyList()
    }

    fun record(
        initiator: String,
        endpointLabel: String,
        url: String,
        method: String = "GET",
        statusCode: Int?,
        durationMs: Long,
        contentType: String?,
        summary: String,
        rawSnippet: String,
        isSuccess: Boolean
    ) {
        val entry = ApiTraceEntry(
            id = UUID.randomUUID().toString(),
            stepOrder = stepCounter.incrementAndGet(),
            initiator = initiator,
            endpointLabel = endpointLabel,
            url = url,
            method = method,
            statusCode = statusCode,
            durationMs = durationMs,
            contentType = contentType,
            summary = summary,
            rawSnippet = rawSnippet.take(1500),
            timestampMs = System.currentTimeMillis(),
            isSuccess = isSuccess
        )
        _traces.update { current ->
            (current + entry).takeLast(80)
        }
    }
}
