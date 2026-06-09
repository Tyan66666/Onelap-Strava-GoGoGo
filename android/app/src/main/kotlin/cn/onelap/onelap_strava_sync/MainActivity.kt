package cn.onelap.onelap_strava_sync

import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.ArrayDeque
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    private companion object {
        const val methodChannelName = "onelap_strava_sync/share_intake"
        const val eventChannelName = "onelap_strava_sync/shared_fit_events"
        const val cookieChannelName = "onelap_strava_sync/cookie"
        const val initialShareMethod = "getInitialSharedFit"
        const val sourcePlatform = "android"
        const val draftType = "draft"
        const val errorType = "error"
        const val defaultDisplayName = "shared.fit"
    }

    private var initialSharedFitPayload: Map<String, Any?>? = null
    private var sharedFitEventSink: EventChannel.EventSink? = null
    private val pendingSharedFitEvents: ArrayDeque<Map<String, Any?>> = ArrayDeque()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent, storeAsInitialPayload = true)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    initialShareMethod -> {
                        result.success(initialSharedFitPayload)
                        initialSharedFitPayload = null
                    }

                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                        sharedFitEventSink = events
                        flushPendingSharedFitEvents()
                    }

                    override fun onCancel(arguments: Any?) {
                        sharedFitEventSink = null
                    }
                },
            )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, cookieChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getCookies" -> {
                        val url = call.arguments as? String ?: ""
                        val cookies = CookieManager.getInstance().getCookie(url)
                        result.success(cookies ?: "")
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent, storeAsInitialPayload = false)
    }

    private fun handleIntent(intent: Intent?, storeAsInitialPayload: Boolean) {
        val payload: Map<String, Any?> = createPayloadForIntent(intent) ?: return
        if (storeAsInitialPayload) {
            initialSharedFitPayload = payload
            return
        }
        publishSharedFitEvent(payload)
    }

    private fun createPayloadForIntent(intent: Intent?): Map<String, Any?>? {
        val action: String = intent?.action ?: return null
        if (!isSupportedShareAction(action)) {
            return null
        }

        val sharedUris: List<Uri> = SharedFitIntentUriExtractor.extract(intent)
        val sharedUri: Uri? = sharedUris.singleOrNull()
        val displayName: String? = sharedUri?.let(::resolveDisplayName)
        val validationError: String? = SharedFitIntentValidator.validationError(
            uriCount = sharedUris.size,
            mimeType = intent.type,
            displayName = displayName,
            uriLastSegment = sharedUri?.lastPathSegment,
        )
        if (validationError != null) {
            return createErrorPayload(validationError)
        }

        val acceptedUri: Uri = sharedUri
            ?: return createErrorPayload("No FIT file was provided")

        return try {
            createDraftPayload(acceptedUri, displayName ?: defaultDisplayName)
        } catch (error: Exception) {
            createErrorPayload(clearErrorMessage(error))
        }
    }

    private fun isSupportedShareAction(action: String): Boolean {
        return action == Intent.ACTION_SEND ||
            action == Intent.ACTION_VIEW
    }

    private fun createDraftPayload(sharedUri: Uri, displayName: String): Map<String, Any?> {
        val localFile: File = copySharedUriToCache(sharedUri, displayName)
        return mapOf(
            "type" to draftType,
            "localFilePath" to localFile.absolutePath,
            "displayName" to displayName,
            "sourcePlatform" to sourcePlatform,
            "receivedAt" to utcTimestamp(),
        )
    }

    private fun copySharedUriToCache(sharedUri: Uri, displayName: String): File {
        val cacheDirectory: File = File(cacheDir, "shared-fit-intake")
        if (!cacheDirectory.exists() && !cacheDirectory.mkdirs()) {
            throw IOException("Unable to prepare app cache for shared FIT file")
        }

        val localFile: File = File(cacheDirectory, uniqueCacheFileName(displayName))
        contentResolver.openInputStream(sharedUri)?.use { inputStream ->
            localFile.outputStream().use { outputStream ->
                inputStream.copyTo(outputStream)
            }
        } ?: throw IOException("Shared FIT file is unavailable")

        return localFile
    }

    private fun uniqueCacheFileName(displayName: String): String {
        val sanitizedName: String = sanitizeFileName(displayName)
        return "${System.currentTimeMillis()}-$sanitizedName"
    }

    private fun sanitizeFileName(displayName: String): String {
        val trimmedName: String = displayName.trim()
        if (trimmedName.isEmpty()) {
            return defaultDisplayName
        }

        val sanitizedName: String = trimmedName.replace(Regex("[\\\\/:*?\"<>|]"), "_")
        return sanitizedName.ifEmpty { defaultDisplayName }
    }

    private fun resolveDisplayName(sharedUri: Uri): String {
        val queriedName: String? = queryDisplayName(sharedUri)
        if (!queriedName.isNullOrBlank()) {
            return queriedName
        }

        val lastSegmentName: String? = sharedUri.lastPathSegment
            ?.substringAfterLast('/')
            ?.takeIf { it.isNotBlank() }
        return lastSegmentName ?: defaultDisplayName
    }

    private fun queryDisplayName(sharedUri: Uri): String? {
        return try {
            val cursor: Cursor? = contentResolver.query(
                sharedUri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )
            cursor?.use {
                if (!it.moveToFirst()) {
                    return@use null
                }
                val nameColumnIndex: Int = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameColumnIndex < 0) {
                    return@use null
                }
                it.getString(nameColumnIndex)
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun publishSharedFitEvent(payload: Map<String, Any?>) {
        val eventSink: EventChannel.EventSink? = sharedFitEventSink
        if (eventSink == null) {
            pendingSharedFitEvents.addLast(payload)
            return
        }
        eventSink.success(payload)
    }

    private fun flushPendingSharedFitEvents() {
        val eventSink: EventChannel.EventSink = sharedFitEventSink ?: return
        while (pendingSharedFitEvents.isNotEmpty()) {
            eventSink.success(pendingSharedFitEvents.removeFirst())
        }
    }

    private fun createErrorPayload(message: String): Map<String, Any?> {
        return mapOf(
            "type" to errorType,
            "message" to message,
            "sourcePlatform" to sourcePlatform,
            "receivedAt" to utcTimestamp(),
        )
    }

    private fun clearErrorMessage(error: Exception): String {
        val detail: String = error.message?.trim().orEmpty()
        if (detail.isEmpty()) {
            return "Unable to read shared FIT file"
        }
        return "Unable to read shared FIT file: $detail"
    }

    private fun utcTimestamp(): String {
        val formatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        formatter.timeZone = TimeZone.getTimeZone("UTC")
        return formatter.format(Date())
    }
}
