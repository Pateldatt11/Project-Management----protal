package com.example.test

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.graphics.Color
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterFragmentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        applyNativeSystemBarPolicy()
        super.onCreate(savedInstanceState)
        applyNativeSystemBarPolicy()
    }

    override fun onResume() {
        super.onResume()
        applyNativeSystemBarPolicy()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) applyNativeSystemBarPolicy()
    }

    private fun applyNativeSystemBarPolicy() {
        try {
            window.statusBarColor = Color.TRANSPARENT
            window.navigationBarColor = Color.TRANSPARENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                window.isStatusBarContrastEnforced = false
                window.isNavigationBarContrastEnforced = true
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                window.attributes = window.attributes.apply {
                    layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                window.setDecorFitsSystemWindows(false)
                window.insetsController?.apply {
                    show(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                    systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                    var appearance = 0
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        appearance = appearance or WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        appearance = appearance or WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
                    }
                    if (appearance != 0) {
                        setSystemBarsAppearance(appearance, appearance)
                    }
                }
            } else {
                @Suppress("DEPRECATION")
                var flags = View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                        View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                        View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    @Suppress("DEPRECATION")
                    flags = flags or View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    @Suppress("DEPRECATION")
                    flags = flags or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
                }
                @Suppress("DEPRECATION")
                window.decorView.systemUiVisibility = flags
            }
        } catch (_: Exception) {
        }
    }

    private val pickerChannelName = "project_management_dashboard/file_picker"
    private val pickBusinessFileRequest = 7301
    private var pendingResult: MethodChannel.Result? = null
    private var pendingMaxBytes: Long = 25L * 1024L * 1024L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Creates high-priority notification channel for floating heads-up push banners
        createHighPriorityNotificationChannel()

        // Business file picker channel handler
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pickerChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickBusinessFile" -> {
                    if (pendingResult != null) {
                        result.error("PICKER_BUSY", "A file picker is already open.", null)
                        return@setMethodCallHandler
                    }
                    @Suppress("UNCHECKED_CAST")
                    val mimeTypes = call.argument<List<String>>("mimeTypes") ?: defaultMimeTypes()
                    pendingMaxBytes = (call.argument<Number>("maxBytes")?.toLong() ?: (25L * 1024L * 1024L))
                    pendingResult = result
                    openBusinessFilePicker(mimeTypes)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun createHighPriorityNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelId = "urgent_work_alerts_v3"
            val channelName = "Urgent Work Alerts"
            val channelDescription = "Heads-up floating task and meeting notifications"
            val importance = NotificationManager.IMPORTANCE_HIGH // Enables top floating banner

            val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val audioAttributes = AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_COMMUNICATION_INSTANT)
                .build()

            val channel = NotificationChannel(channelId, channelName, importance).apply {
                description = channelDescription
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 300, 200, 300)
                enableLights(true)
                lightColor = Color.RED
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setSound(soundUri, audioAttributes)
                setShowBadge(true)
            }

            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager?.createNotificationChannel(channel)
        }
    }

    private fun openBusinessFilePicker(mimeTypes: List<String>) {
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes.toTypedArray())
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            }
            startActivityForResult(intent, pickBusinessFileRequest)
        } catch (error: Exception) {
            val result = pendingResult
            pendingResult = null
            result?.error("PICKER_OPEN_FAILED", error.message ?: "Could not open Android file picker.", null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickBusinessFileRequest) return

        val result = pendingResult
        pendingResult = null
        if (result == null) return

        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return
        }

        val uri = data.data!!
        try {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (_: Exception) {
        }

        try {
            val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
            if (bytes == null) {
                result.error("FILE_READ_FAILED", "Could not read selected file.", null)
                return
            }
            if (bytes.size > pendingMaxBytes) {
                result.error("FILE_TOO_LARGE", "Selected file is larger than 25 MB.", null)
                return
            }

            val name = displayName(uri) ?: "attachment"
            val mimeType = contentResolver.getType(uri) ?: guessMimeType(name) ?: "application/octet-stream"
            result.success(
                mapOf(
                    "name" to name,
                    "mimeType" to mimeType,
                    "sizeBytes" to bytes.size,
                    "bytes" to bytes,
                )
            )
        } catch (error: Exception) {
            result.error("FILE_READ_FAILED", error.message ?: "Could not read selected file.", null)
        }
    }

    private fun displayName(uri: Uri): String? {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) {
                    val value = cursor.getString(index)
                    if (!value.isNullOrBlank()) return value
                }
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/')
    }

    private fun guessMimeType(fileName: String): String? {
        val extension = fileName.substringAfterLast('.', "").lowercase(Locale.ROOT)
        if (extension.isBlank()) return null
        return when (extension) {
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "webp" -> "image/webp"
            "pdf" -> "application/pdf"
            "doc" -> "application/msword"
            "docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            "xls" -> "application/vnd.ms-excel"
            "xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            "txt" -> "text/plain"
            else -> MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
        }
    }

    private fun defaultMimeTypes(): List<String> = listOf(
        "image/png",
        "image/jpeg",
        "image/webp",
        "application/pdf",
        "application/msword",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/vnd.ms-excel",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "text/plain",
    )
}