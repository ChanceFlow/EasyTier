package com.kkrainbow.easytier

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.webkit.WebView
import androidx.activity.OnBackPressedCallback

class MainActivity : TauriActivity() {
    /**
     * Wry keeps its `RustWebView` in a private field with no public getter, but
     * `WryActivity.setWebView` calls the public `onWebViewCreate(webView)` hook
     * right after the native side attaches the view. Capture it there so the
     * back callback can hand a back press to the page.
     */
    @Volatile
    private var contentWebView: WebView? = null

    override fun onWebViewCreate(webView: WebView) {
        super.onWebViewCreate(webView)
        contentWebView = webView
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestNotificationPermission()
        // Back must not tear down the tunnel (upstream #2546). Give the SPA the
        // first chance to consume it - the JS back guard pushes one history
        // entry per open overlay, so `goBack()` closes the top overlay - and
        // only send the task to the background when the webview has no
        // in-page history left.
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                val webView = contentWebView
                if (webView != null && webView.canGoBack()) {
                    webView.goBack()
                } else {
                    moveTaskToBack(true)
                }
            }
        })
        initService()
    }

    private fun requestNotificationPermission() {
        // Android 13+: without this grant, even foreground-service
        // notifications are hidden and the IO ticker would be invisible.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 101)
        }
    }

    private fun initService() {
        val serviceIntent = Intent(this, MainForegroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }
}
