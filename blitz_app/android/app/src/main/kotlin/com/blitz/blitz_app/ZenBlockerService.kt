package com.blitz.blitz_app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.PixelFormat
import android.os.Build
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.TextView

/**
 * ZenBlockerService — Accessibility service that runs silently in the background.
 *
 * When Focus Mode is ACTIVE (stored in SharedPreferences), and the user tries to
 * open a blocked social media app, this service:
 *   1. Detects the foreground package change via AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
 *   2. Immediately shows a full-screen "blocked" overlay on top of EVERYTHING
 *   3. After 1.5s, launches Zen back to the foreground forcing the user back
 *
 * This is the same mechanism used by Freedom, Forest, and StayFocusd.
 */
class ZenBlockerService : AccessibilityService() {

    private var overlayView: View? = null
    private lateinit var windowManager: WindowManager
    private lateinit var prefs: SharedPreferences

    companion object {
        const val PREFS_NAME = "zen_focus"
        const val KEY_FOCUS_ACTIVE = "focus_active"
        const val KEY_BLOCKED_PACKAGES = "blocked_packages"

        // Default social media packages
        val DEFAULT_BLOCKED = setOf(
            "com.instagram.android",
            "com.twitter.android",
            "com.zhiliaoapp.musically",
            "com.facebook.katana",
            "com.snapchat.android",
            "com.reddit.frontpage",
            "com.linkedin.android",
            "com.pinterest",
            "com.whatsapp",
            "org.telegram.messenger",
            "com.discord",
            "com.facebook.lite",
            "com.instagram.lite",
            "com.tiktok"
        )

        var instance: ZenBlockerService? = null
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
            notificationTimeout = 100
        }
        serviceInfo = info
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return

        val pkg = event.packageName?.toString() ?: return

        // Skip our own app
        if (pkg == "com.blitz.blitz_app") return

        // Only block if Focus Mode is actually active
        val focusActive = prefs.getBoolean(KEY_FOCUS_ACTIVE, false)
        if (!focusActive) return

        // Get the list of currently blocked packages
        val blocked = prefs.getStringSet(KEY_BLOCKED_PACKAGES, DEFAULT_BLOCKED) ?: DEFAULT_BLOCKED

        if (blocked.contains(pkg)) {
            showBlockOverlay()
        }
    }

    private fun showBlockOverlay() {
        if (overlayView != null) return // Already showing

        try {
            val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                WindowManager.LayoutParams.TYPE_PHONE

            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                type,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_FULLSCREEN,
                PixelFormat.TRANSLUCENT
            )

            // Build the overlay view programmatically (no XML needed)
            val view = buildBlockView()
            overlayView = view
            windowManager.addView(view, params)

            // Auto-dismiss and return to Zen after 2.5 seconds
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                dismissOverlay()
                bringBackZen()
            }, 2500)

        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun buildBlockView(): View {
        // Pure programmatic layout — no XML layout file needed
        val context = applicationContext

        val frame = android.widget.FrameLayout(context).apply {
            setBackgroundColor(0xF2020510.toInt()) // Near-black with opacity
        }

        val container = android.widget.LinearLayout(context).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            gravity = android.view.Gravity.CENTER
            layoutParams = android.widget.FrameLayout.LayoutParams(
                android.widget.FrameLayout.LayoutParams.MATCH_PARENT,
                android.widget.FrameLayout.LayoutParams.MATCH_PARENT
            )
        }

        val shield = android.widget.TextView(context).apply {
            text = "🛡️"
            textSize = 72f
            gravity = android.view.Gravity.CENTER
            setPadding(0, 0, 0, 24)
        }

        val title = android.widget.TextView(context).apply {
            text = "Focus Mode Active"
            textSize = 24f
            setTextColor(0xFFFFFFFF.toInt())
            gravity = android.view.Gravity.CENTER
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            setPadding(40, 0, 40, 12)
        }

        val subtitle = android.widget.TextView(context).apply {
            text = "This app is blocked during your study session.\nYou'll be redirected back to Zen."
            textSize = 14f
            setTextColor(0xFF888888.toInt())
            gravity = android.view.Gravity.CENTER
            setPadding(60, 0, 60, 0)
        }

        container.addView(shield)
        container.addView(title)
        container.addView(subtitle)
        frame.addView(container)

        return frame
    }

    private fun dismissOverlay() {
        overlayView?.let {
            try {
                windowManager.removeView(it)
            } catch (_: Exception) {}
            overlayView = null
        }
    }

    private fun bringBackZen() {
        try {
            val intent = packageManager.getLaunchIntentForPackage("com.blitz.blitz_app")
                ?: return
            intent.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
            )
            startActivity(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onInterrupt() {
        dismissOverlay()
        instance = null
    }

    override fun onDestroy() {
        super.onDestroy()
        dismissOverlay()
        instance = null
    }
}
