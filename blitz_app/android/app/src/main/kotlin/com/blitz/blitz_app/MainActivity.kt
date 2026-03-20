package com.blitz.blitz_app

import android.app.Activity
import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.text.TextUtils
import android.app.Notification
import android.app.RemoteInput
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// ─────────────────────────────────────────────────────────────────────────────
// ZenNotificationService — reads live notifications from the device
// ─────────────────────────────────────────────────────────────────────────────
class ZenNotificationService : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        sbn ?: return
        // Skip our own app
        if (sbn.packageName == "com.blitz.blitz_app") return
        // Skip system noise
        val extras = sbn.notification.extras
        val title = extras.getCharSequence("android.title")?.toString() ?: ""
        val text = extras.getCharSequence("android.text")?.toString() ?: ""
        if (title.isBlank() && text.isBlank()) return

        var canReply = false
        val actions = sbn.notification.actions
        if (actions != null) {
            for (action in actions) {
                if (action.remoteInputs != null && action.remoteInputs.isNotEmpty()) {
                    canReply = true
                    replyActions[sbn.id] = action
                    break
                }
            }
        }

        val event = mapOf(
            "id"          to sbn.id,
            "pkg"         to sbn.packageName,
            "title"       to title,
            "text"        to text,
            "app_name"    to getAppName(sbn.packageName),
            "posted_at"   to sbn.postTime,
            "removed"     to false,
            "can_reply"   to canReply
        )
        eventSink?.success(event)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        sbn ?: return
        replyActions.remove(sbn.id)
        val event = mapOf(
            "id"      to sbn.id,
            "pkg"     to sbn.packageName,
            "removed" to true
        )
        eventSink?.success(event)
    }

    private fun getAppName(packageName: String): String {
        return try {
            val pm = applicationContext.packageManager
            val info: ApplicationInfo = pm.getApplicationInfo(packageName, 0)
            pm.getApplicationLabel(info).toString()
        } catch (_: Exception) {
            packageName.split(".").last()
        }
    }

    companion object {
        var eventSink: EventChannel.EventSink? = null
        val replyActions = mutableMapOf<Int, Notification.Action>()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MainActivity — registers MethodChannel + EventChannel for Flutter
// ─────────────────────────────────────────────────────────────────────────────
class MainActivity : FlutterActivity() {

    private val METHOD_CHANNEL = "com.zen/notifications"
    private val EVENT_CHANNEL  = "com.zen/notifications/stream"
    private val FOCUS_CHANNEL  = "com.zen/focus"



    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── MethodChannel: permission check / request ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isPermissionGranted" ->
                        result.success(isNotificationListenerEnabled())
                    "requestPermission" -> {
                        startActivity(
                            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(null)
                    }
                    "replyToNotification" -> {
                        val id = call.argument<Int>("id")
                        val message = call.argument<String>("message")
                        val action = ZenNotificationService.replyActions[id]
                        if (action != null && message != null) {
                            val results = Bundle()
                            results.putCharSequence(action.remoteInputs[0].resultKey, message)
                            val intent = Intent()
                            RemoteInput.addResultsToIntent(action.remoteInputs, intent, results)
                            try {
                                action.actionIntent.send(this, 0, intent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("REPLY_FAILED", e.message, null)
                            }
                        } else {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Focus Mode MethodChannel ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FOCUS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasUsagePermission" -> result.success(hasUsageStatsPermission())
                    "requestUsagePermission" -> {
                        startActivity(
                            Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(null)
                    }
                    "hasOverlayPermission" -> {
                        val has = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                            Settings.canDrawOverlays(this) else true
                        result.success(has)
                    }
                    "requestOverlayPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            startActivity(Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        }
                        result.success(null)
                    }
                    "isAccessibilityEnabled" -> {
                        result.success(isAccessibilityServiceEnabled())
                    }
                    "requestAccessibilityPermission" -> {
                        startActivity(
                            Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(null)
                    }
                    "setFocusMode" -> {
                        val active = call.argument<Boolean>("active") ?: false
                        val blockedList = call.argument<List<String>>("blocked")
                        val prefs = getSharedPreferences(ZenBlockerService.PREFS_NAME, Context.MODE_PRIVATE)
                        val editor = prefs.edit().putBoolean(ZenBlockerService.KEY_FOCUS_ACTIVE, active)
                        if (blockedList != null) {
                            editor.putStringSet(ZenBlockerService.KEY_BLOCKED_PACKAGES, blockedList.toSet())
                        }
                        editor.apply()
                        result.success(null)
                    }
                    "isBlockedAppInForeground" -> {
                        val blocked = isSocialMediaInForeground()
                        result.success(blocked)
                    }
                    "getForegroundPackage" -> {
                        result.success(getForegroundPackage())
                    }
                    "openSpotify" -> {
                        openSpotify()
                        result.success(null)
                    }
                    "openApp" -> {
                        val pkg = call.argument<String>("package")
                        if (pkg != null) openPackage(pkg)
                        result.success(null)
                    }
                    "getSocialMediaPackages" -> {
                        val prefs = getSharedPreferences(ZenBlockerService.PREFS_NAME, Context.MODE_PRIVATE)
                        val blocked = prefs.getStringSet(ZenBlockerService.KEY_BLOCKED_PACKAGES, ZenBlockerService.DEFAULT_BLOCKED) 
                            ?: ZenBlockerService.DEFAULT_BLOCKED
                        result.success(blocked.toList())
                    }
                    "setDoNotDisturb" -> {
                        val active = call.argument<Boolean>("active") ?: false
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            if (nm.isNotificationPolicyAccessGranted) {
                                nm.setInterruptionFilter(if (active) android.app.NotificationManager.INTERRUPTION_FILTER_NONE else android.app.NotificationManager.INTERRUPTION_FILTER_ALL)
                            } else {
                                startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            }
                        }
                        result.success(null)
                    }
                    "setVolume" -> {
                        val level = call.argument<Int>("level") ?: 0
                        val am = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
                        val max = am.getStreamMaxVolume(android.media.AudioManager.STREAM_NOTIFICATION)
                        val value = ((max * (level / 100.0)).toInt()).coerceIn(0, max)
                        am.setStreamVolume(android.media.AudioManager.STREAM_NOTIFICATION, value, android.media.AudioManager.FLAG_SHOW_UI)
                        result.success(null)
                    }
                    "getInstalledApps" -> {
                        result.success(getInstalledApps())
                    }
                    else -> result.notImplemented()
                }
            }

        // ── EventChannel: stream of notification events ──
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    ZenNotificationService.eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    ZenNotificationService.eventSink = null
                }
            })
    }

    private fun isNotificationListenerEnabled(): Boolean {
        val flat = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners"
        ) ?: return false
        val cn = ComponentName(this, ZenNotificationService::class.java)
        return flat.contains(cn.flattenToString())
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        val cn = ComponentName(this, ZenBlockerService::class.java)
        return enabledServices.contains(cn.flattenToString())
    }

    private fun hasUsageStatsPermission(): Boolean {
        return try {
            val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName
            )
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            false
        }
    }

    private fun getForegroundPackage(): String? {
        return try {
            val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val now = System.currentTimeMillis()
            val stats = usm.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                now - 5000, now
            )
            stats?.maxByOrNull { it.lastTimeUsed }?.packageName
        } catch (e: Exception) {
            null
        }
    }

    private fun isSocialMediaInForeground(): Boolean {
        val foreground = getForegroundPackage() ?: return false
        val prefs = getSharedPreferences(ZenBlockerService.PREFS_NAME, Context.MODE_PRIVATE)
        val blocked = prefs.getStringSet(ZenBlockerService.KEY_BLOCKED_PACKAGES, ZenBlockerService.DEFAULT_BLOCKED) 
            ?: ZenBlockerService.DEFAULT_BLOCKED
        return blocked.contains(foreground)
    }

    private fun openSpotify() {
        val spotifyPkg = "com.spotify.music"
        try {
            val intent = packageManager.getLaunchIntentForPackage(spotifyPkg)
            if (intent != null) {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
            } else {
                // Spotify not installed — open Play Store
                val fallback = Intent(
                    Intent.ACTION_VIEW,
                    Uri.parse("market://details?id=$spotifyPkg")
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(fallback)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun openPackage(pkg: String) {
        try {
            val intent = packageManager.getLaunchIntentForPackage(pkg)
                ?: return
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun getInstalledApps(): List<Map<String, Any>> {
        val pm = packageManager
        val apps = pm.getInstalledApplications(android.content.pm.PackageManager.GET_META_DATA)
        val result = mutableListOf<Map<String, Any>>()
        
        for (app in apps) {
            // Only include launchable apps
            pm.getLaunchIntentForPackage(app.packageName) ?: continue
            
            try {
                val label = pm.getApplicationLabel(app).toString()
                val icon = pm.getApplicationIcon(app)
                
                // Convert icon to byte array for Flutter
                val width = if (icon.intrinsicWidth > 0) icon.intrinsicWidth else 128
                val height = if (icon.intrinsicHeight > 0) icon.intrinsicHeight else 128
                
                val bitmap = if (icon is android.graphics.drawable.BitmapDrawable) {
                    icon.bitmap
                } else {
                    val b = android.graphics.Bitmap.createBitmap(width, height, android.graphics.Bitmap.Config.ARGB_8888)
                    val canvas = android.graphics.Canvas(b)
                    icon.setBounds(0, 0, canvas.width, canvas.height)
                    icon.draw(canvas)
                    b
                }
                
                // Resize for efficiency
                val stream = java.io.ByteArrayOutputStream()
                val scaled = android.graphics.Bitmap.createScaledBitmap(bitmap, 96, 96, true)
                scaled.compress(android.graphics.Bitmap.CompressFormat.PNG, 80, stream)
                
                result.add(mapOf(
                    "name" to label,
                    "package" to app.packageName,
                    "icon" to stream.toByteArray()
                ))
            } catch (e: Exception) {
                // Ignore failures for specific apps
            }
        }
        return result.sortedBy { it["name"].toString().toLowerCase() }
    }
}
