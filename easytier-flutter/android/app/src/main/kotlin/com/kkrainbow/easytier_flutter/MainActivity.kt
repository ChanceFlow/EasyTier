package com.kkrainbow.easytier_flutter

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter host activity and the Android end of the VPN MethodChannel.
 *
 * Command channel: [METHOD_CHANNEL] (Dart -> Kotlin)
 *   - `prepare`              -> bool: shows the system VPN consent dialog when needed
 *   - `start` (args map)     -> tunnel map {fd, ipv4Cidr, ipv6Cidr, routes, dns, mtu, session}
 *                               or a PlatformException: `need_prepare` | `bad_args` |
 *                               `vpn_busy` | `vpn_start_failed` | `vpn_start_timeout`
 *   - `stop`                 -> null
 *   - `status`               -> map {running, ipv4Cidr, ipv6Cidr, routes, dns, mtu, lastError}
 *   - `requestPermission`    -> bool: POST_NOTIFICATIONS runtime permission (API 33+)
 *   - `notificationStatus`   -> map {granted, enabled}
 *   - `openNotificationSettings` -> null
 *   - `updateNotification`   -> null; args {rxBps, txBps, connected}
 *   - `consumeTileAction`    -> "start" | "stop" | null (pending quick-settings tap)
 *
 * Event channel: [EVENT_CHANNEL] (Kotlin -> Dart), map payloads with a `type`:
 *   - `started`     {fd, ipv4Cidr, ipv6Cidr, routes, dns, mtu, session}
 *   - `stopped`     {reason: user|revoked|destroy|superseded|error}
 *   - `error`       {message}
 *   - `tileAction`  {action: start|stop}
 *
 * The `started` event is only pushed to Dart when it is NOT the result of the
 * pending `start` call below (quick-settings tile / service restart); the
 * caller of `start` receives the same payload as its method result. That keeps
 * the fd handed to the Rust core exactly once.
 */
class MainActivity : FlutterActivity(), EventChannel.StreamHandler {

    companion object {
        private const val TAG = "MainActivity"

        const val METHOD_CHANNEL = "com.kkrainbow.easytier/vpn"
        const val EVENT_CHANNEL = "com.kkrainbow.easytier/vpn/events"

        private const val REQUEST_VPN_CONSENT = 0x5650
        private const val REQUEST_NOTIFICATIONS = 0x5651

        /** Upper bound for "service reported a TUN fd"; covers slow establish(). */
        private const val START_TIMEOUT_MS = 10_000L

        /**
         * If Dart stops pushing rate samples for this long, replace the stale
         * numbers with a static background sentence (same 15s watchdog as the
         * Tauri client; needed because engines throttle timers in background).
         */
        private const val NOTIFICATION_WATCHDOG_MS = 15_000L

        private val CIDR = Regex("^[0-9a-fA-F:.]+/\\d{1,3}$")

        /**
         * True while this activity is resumed. The quick-settings tile reads it:
         * starting a `specialUse` foreground service from the background is
         * blocked on targetSdk 31+, and VPN consent needs a visible Activity,
         * so a tile tap while backgrounded opens the app instead.
         */
        @Volatile
        var isInForeground: Boolean = false
    }

    private var methodChannel: MethodChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    private var pendingPrepareResult: MethodChannel.Result? = null
    private var pendingStartResult: MethodChannel.Result? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private var lastConnected = false

    private val startTimeout = Runnable {
        if (pendingStartResult != null) {
            resolveStartError(
                "vpn_start_timeout",
                "The VPN service did not report a TUN fd within ${START_TIMEOUT_MS / 1000}s",
            )
            EasyTierVpnService.self?.stopTunnel(EasyTierVpnService.REASON_ERROR)
        }
    }

    private val notificationWatchdog = Runnable {
        if (!EasyTierVpnService.isRunning()) return@Runnable
        // The engine's timers were throttled while backgrounded: keep the
        // tunnel state visible but stop claiming live numbers.
        VpnNotification.notify(
            this,
            VpnNotification.State(connected = lastConnected, stale = true),
        )
    }

    // ---------------------------------------------------------------------
    // Flutter engine / channel wiring
    // ---------------------------------------------------------------------

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        methodChannel = MethodChannel(messenger, METHOD_CHANNEL).apply {
            setMethodCallHandler(::onMethodCall)
        }
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(this)
    }

    override fun onDestroy() {
        VpnTileBridge.listener = null
        VpnEventBus.register(null)
        eventSink = null
        mainHandler.removeCallbacks(startTimeout)
        mainHandler.removeCallbacks(notificationWatchdog)
        pendingPrepareResult?.let { pending ->
            pendingPrepareResult = null
            pending.error("cancelled", "activity destroyed while waiting for VPN consent", null)
        }
        pendingPermissionResult?.let { pending ->
            pendingPermissionResult = null
            pending.error("cancelled", "activity destroyed while waiting for permission", null)
        }
        if (pendingStartResult != null) {
            // The service may still finish the start; Dart has to reconcile via
            // `status`/events instead of this dead result.
            resolveStartError("cancelled", "activity destroyed while the VPN was starting")
        }
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        super.onDestroy()
    }

    override fun onResume() {
        super.onResume()
        isInForeground = true
    }

    override fun onPause() {
        isInForeground = false
        super.onPause()
    }

    // ---------------------------------------------------------------------
    // MethodChannel
    // ---------------------------------------------------------------------

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepare" -> prepareVpn(result)
            "start" -> startVpn(call, result)
            "stop" -> stopVpn(result)
            "status" -> result.success(statusPayload())
            "requestPermission" -> requestNotificationPermission(result)
            "notificationStatus" -> result.success(notificationStatusPayload())
            "openNotificationSettings" -> {
                openNotificationSettings()
                result.success(null)
            }
            "updateNotification" -> {
                updateNotification(call)
                result.success(null)
            }
            "consumeTileAction" -> result.success(EasyTierVpnTileService.consumePendingAction(this))
            else -> result.notImplemented()
        }
    }

    /** Shows the system "allow VPN connection" dialog when consent is missing. */
    private fun prepareVpn(result: MethodChannel.Result) {
        val consent = try {
            VpnService.prepare(this)
        } catch (t: Throwable) {
            result.error("vpn_prepare_failed", t.message, null)
            return
        }
        if (consent == null) {
            result.success(true)
            return
        }
        if (pendingPrepareResult != null) {
            result.error("vpn_busy", "another VPN consent request is already in progress", null)
            return
        }
        pendingPrepareResult = result
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(consent, REQUEST_VPN_CONSENT)
        } catch (t: Throwable) {
            pendingPrepareResult = null
            result.error("vpn_prepare_failed", t.message, null)
        }
    }

    private fun startVpn(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        if (args == null) {
            result.error("bad_args", "start expects a map of tunnel parameters", null)
            return
        }
        val ipv4Cidr = (args["ipv4Cidr"] as? String)?.trim().orEmpty()
        if (!CIDR.matches(ipv4Cidr)) {
            result.error("bad_args", "ipv4Cidr must be CIDR notation like 10.144.0.2/24", null)
            return
        }

        // Consent was withdrawn (or never granted): tell Dart to call prepare().
        if (VpnService.prepare(this) != null) {
            result.error("need_prepare", "the VPN consent dialog has not been accepted", null)
            return
        }
        if (pendingStartResult != null) {
            result.error("vpn_busy", "another VPN start is already in progress", null)
            return
        }

        // One TUN only: drop whatever is currently established before claiming
        // the slot. The resulting `stopped(superseded)` event reaches Dart, and
        // the new `started` event carries the fresh fd.
        EasyTierVpnService.self?.stopTunnel(EasyTierVpnService.REASON_SUPERSEDED)

        pendingStartResult = result
        mainHandler.postDelayed(startTimeout, START_TIMEOUT_MS)

        val intent = Intent(this, EasyTierVpnService::class.java).apply {
            action = EasyTierVpnService.ACTION_START
            putExtra(EasyTierVpnService.EXTRA_IPV4_CIDR, ipv4Cidr)
            putStringArrayListExtra(
                EasyTierVpnService.EXTRA_ROUTES,
                stringList(args["routes"]),
            )
            putStringArrayListExtra(
                EasyTierVpnService.EXTRA_DNS,
                stringList(args["dns"]),
            )
            putStringArrayListExtra(
                EasyTierVpnService.EXTRA_DISALLOWED_APPLICATIONS,
                stringList(args["disallowedApplications"]),
            )
            putExtra(
                EasyTierVpnService.EXTRA_MTU,
                (args["mtu"] as? Number)?.toInt() ?: EasyTierVpnService.DEFAULT_MTU,
            )
            (args["ipv6Cidr"] as? String)?.takeIf { it.contains('/') }?.let {
                putExtra(EasyTierVpnService.EXTRA_IPV6_CIDR, it)
            }
            (args["session"] as? String)?.takeIf { it.isNotBlank() }?.let {
                putExtra(EasyTierVpnService.EXTRA_SESSION, it)
            }
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (t: Throwable) {
            // targetSdk 31+: starting a foreground service from the background
            // is restricted; the UI must be foregrounded before connecting.
            Log.e(TAG, "failed to start the VPN service", t)
            resolveStartError("vpn_start_failed", t.message ?: t.javaClass.simpleName)
        }
    }

    private fun stopVpn(result: MethodChannel.Result) {
        resolveStartError("cancelled", "stop requested while the VPN was starting")
        mainHandler.removeCallbacks(notificationWatchdog)
        lastConnected = false
        val service = EasyTierVpnService.self
        if (service != null) {
            // Same-process call: tears down the fd and reports `stopped(user)`
            // to Dart through the event channel.
            service.stopTunnel(EasyTierVpnService.REASON_USER)
        } else {
            // Defensive: a half-started service instance with no tunnel.
            stopService(Intent(this, EasyTierVpnService::class.java))
        }
        result.success(null)
    }

    private fun updateNotification(call: MethodCall) {
        if (!EasyTierVpnService.isRunning()) return
        val args = call.arguments as? Map<*, *> ?: return
        val rx = (args["rxBps"] as? Number)?.toDouble() ?: 0.0
        val tx = (args["txBps"] as? Number)?.toDouble() ?: 0.0
        lastConnected = args["connected"] as? Boolean ?: (rx > 0.0 || tx > 0.0)

        VpnNotification.notify(
            this,
            VpnNotification.State(connected = lastConnected, rxBps = rx, txBps = tx),
        )

        mainHandler.removeCallbacks(notificationWatchdog)
        mainHandler.postDelayed(notificationWatchdog, NOTIFICATION_WATCHDOG_MS)
    }

    private fun statusPayload(): Map<String, Any?> {
        val spec = EasyTierVpnService.activeTunnel
        return mapOf(
            "running" to EasyTierVpnService.isRunning(),
            "ipv4Cidr" to spec?.ipv4Cidr,
            "ipv6Cidr" to spec?.ipv6Cidr,
            "routes" to (spec?.routes ?: emptyList<String>()),
            "dns" to (spec?.dns ?: emptyList<String>()),
            "mtu" to (spec?.mtu ?: 0),
            "lastError" to EasyTierVpnService.lastStartError,
        )
    }

    private fun notificationStatusPayload(): Map<String, Any?> {
        val granted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        val enabled = getSystemService(NotificationManager::class.java)
            ?.areNotificationsEnabled() ?: false
        return mapOf("granted" to granted, "enabled" to enabled)
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("vpn_busy", "another permission request is already in progress", null)
            return
        }
        pendingPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_NOTIFICATIONS,
        )
    }

    private fun openNotificationSettings() {
        try {
            startActivity(
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (t: Throwable) {
            try {
                startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                        .setData(Uri.fromParts("package", packageName, null))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
            } catch (t2: Throwable) {
                Log.w(TAG, "could not open notification settings", t2)
            }
        }
    }

    private fun stringList(raw: Any?): ArrayList<String> {
        val list = raw as? List<*> ?: return ArrayList()
        return list.mapNotNull { it as? String }.toCollection(ArrayList())
    }

    // ---------------------------------------------------------------------
    // Activity / permission results
    // ---------------------------------------------------------------------

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_VPN_CONSENT) {
            val pending = pendingPrepareResult
            pendingPrepareResult = null
            pending?.success(resultCode == Activity.RESULT_OK)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode == REQUEST_NOTIFICATIONS) {
            val pending = pendingPermissionResult
            pendingPermissionResult = null
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pending?.success(granted)
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    // ---------------------------------------------------------------------
    // EventChannel + service event fan-in
    // ---------------------------------------------------------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        VpnEventBus.register(vpnEventListener)
        VpnTileBridge.listener = tileActionListener
    }

    override fun onCancel(arguments: Any?) {
        VpnTileBridge.listener = null
        VpnEventBus.register(null)
        eventSink = null
    }

    private val vpnEventListener = VpnEventBus.Listener { event ->
        when (event["type"]) {
            "started" -> {
                val pending = pendingStartResult
                if (pending != null) {
                    // The `start` caller gets the fd as its method result; do
                    // not also push `started`, or Dart would attach it twice.
                    mainHandler.removeCallbacks(startTimeout)
                    pendingStartResult = null
                    pending.success(event)
                } else {
                    eventSink?.success(event)
                }
            }
            "error" -> {
                val message = event["message"] as? String
                if (pendingStartResult != null) {
                    resolveStartError("vpn_start_failed", message)
                } else {
                    eventSink?.success(event)
                }
            }
            "stopped" -> {
                // A deliberate stop/supersede while a start is in flight must
                // not fail that start; the result arrives as `started`,
                // `error` or the timeout.
                lastConnected = false
                mainHandler.removeCallbacks(notificationWatchdog)
                eventSink?.success(event)
            }
            else -> eventSink?.success(event)
        }
    }

    /**
     * Tile tap -> Dart. Returns true only when a live Dart listener consumed
     * the action; otherwise the tile opens the app, which drains the persisted
     * pending action via `consumeTileAction`.
     */
    private val tileActionListener: (String) -> Boolean = { action ->
        val sink = eventSink
        if (sink == null) {
            false
        } else {
            sink.success(mapOf("type" to "tileAction", "action" to action))
            true
        }
    }

    private fun resolveStartError(code: String, message: String?) {
        mainHandler.removeCallbacks(startTimeout)
        val pending = pendingStartResult ?: return
        pendingStartResult = null
        pending.error(code, message, null)
    }
}
