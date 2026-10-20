package com.kkrainbow.easytier_flutter

import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log

/**
 * One established Android TUN, described by the request that created it.
 *
 * Android has no way to read this back from the interface, so the service is
 * the source of truth for "what is currently established" and [MainActivity]
 * serves it to Dart through the `status` method (and the `start` result).
 */
data class VpnTunnelSpec(
    val ipv4Cidr: String,
    val routes: List<String>,
    val dns: List<String>,
    val mtu: Int,
    val ipv6Cidr: String?,
    val session: String,
    val disallowedApplications: List<String> = emptyList(),
) {
    companion object {
        /**
         * Rebuilds the spec from the intent [MainActivity] handed to
         * [EasyTierVpnService]. Returns null when the intent carries no tunnel
         * request (e.g. a stray service restart); we never re-establish a
         * tunnel from defaults.
         */
        fun fromIntent(intent: Intent?): VpnTunnelSpec? {
            if (intent == null) return null
            val ipv4 = intent.getStringExtra(EasyTierVpnService.EXTRA_IPV4_CIDR)?.trim()
            if (ipv4.isNullOrEmpty()) return null
            return VpnTunnelSpec(
                ipv4Cidr = ipv4,
                routes = intent.getStringArrayListExtra(EasyTierVpnService.EXTRA_ROUTES)
                    ?.filterNotNull().orEmpty(),
                dns = intent.getStringArrayListExtra(EasyTierVpnService.EXTRA_DNS)
                    ?.filterNotNull().orEmpty(),
                mtu = intent.getIntExtra(
                    EasyTierVpnService.EXTRA_MTU,
                    EasyTierVpnService.DEFAULT_MTU,
                ).takeIf { it > 0 } ?: EasyTierVpnService.DEFAULT_MTU,
                ipv6Cidr = intent.getStringExtra(EasyTierVpnService.EXTRA_IPV6_CIDR)
                    ?.takeIf { it.contains('/') },
                session = intent.getStringExtra(EasyTierVpnService.EXTRA_SESSION)
                    ?.takeIf { it.isNotBlank() } ?: EasyTierVpnService.DEFAULT_SESSION,
                disallowedApplications =
                    intent.getStringArrayListExtra(EasyTierVpnService.EXTRA_DISALLOWED_APPLICATIONS)
                        ?.filterNotNull().orEmpty(),
            )
        }
    }
}

/**
 * EasyTier's Android data plane: a real [VpnService] that owns the process-wide
 * TUN slot.
 *
 * Responsibilities:
 *  - `Builder.establish()` the TUN from the request passed by [MainActivity];
 *  - `detachFd()` it and report the raw fd to Dart (which hands it to the Rust
 *    core through `set_tun_fd`);
 *  - keep the foreground-service notification (see [VpnNotification]);
 *  - report every teardown reason to Dart, in particular [REASON_REVOKED] when
 *    Android hands the VPN slot to another app (`onRevoke`), so the UI can
 *    leave "connected" instead of lying;
 *  - enforce the single-tunnel constraint: a new start tears the previous
 *    interface down first.
 *
 * fd ownership: `establish()` -> `detachFd()` makes this service the owner of
 * the raw descriptor; the Rust core only borrows it (`tun::Configuration::
 * close_fd_on_drop(false)` in `virtual_nic.rs`). Closing the descriptor on
 * teardown here is therefore what actually kills the data plane - and it means
 * a missed close would leak one fd per connect, which is why every teardown
 * path goes through [releaseTunnel].
 */
class EasyTierVpnService : VpnService() {

    companion object {
        private const val TAG = "EasyTierVpnService"

        /** Explicit start from [MainActivity]. */
        const val ACTION_START = "com.kkrainbow.easytier_flutter.action.VPN_START"

        /** Notification "Disconnect" action; same value as [VpnNotification.ACTION_DISCONNECT]. */
        const val ACTION_DISCONNECT = VpnNotification.ACTION_DISCONNECT

        // Intent extras. Prefixed so they cannot collide with the system's own.
        const val EXTRA_IPV4_CIDR = "com.kkrainbow.easytier_flutter.extra.IPV4_CIDR"
        const val EXTRA_IPV6_CIDR = "com.kkrainbow.easytier_flutter.extra.IPV6_CIDR"
        const val EXTRA_ROUTES = "com.kkrainbow.easytier_flutter.extra.ROUTES"
        const val EXTRA_DNS = "com.kkrainbow.easytier_flutter.extra.DNS"
        const val EXTRA_MTU = "com.kkrainbow.easytier_flutter.extra.MTU"
        const val EXTRA_SESSION = "com.kkrainbow.easytier_flutter.extra.SESSION"
        const val EXTRA_DISALLOWED_APPLICATIONS =
            "com.kkrainbow.easytier_flutter.extra.DISALLOWED_APPLICATIONS"

        const val DEFAULT_SESSION = "EasyTier"

        /**
         * MTU used by the previous mobile clients (Tauri / android-jni). Kept as
         * the default so the Flutter client does not silently change the wire
         * behaviour; Dart can override it per request.
         */
        const val DEFAULT_MTU = 1300

        // Teardown reasons reported to Dart (`vpn stopped` event `reason` field).
        const val REASON_USER = "user"
        const val REASON_REVOKED = "revoked"
        const val REASON_DESTROY = "destroy"
        const val REASON_SUPERSEDED = "superseded"
        const val REASON_ERROR = "error"

        /**
         * The running service, or null. Read by [MainActivity] for the
         * `status`/`start`/`stop` methods and by the quick-settings tile.
         * Written only on the main thread; read from any thread.
         */
        @Volatile
        var self: EasyTierVpnService? = null

        /** The tunnel currently established by [self], null when down. */
        @Volatile
        var activeTunnel: VpnTunnelSpec? = null

        /** Last establish()/start failure, surfaced to Dart through `status`. */
        @Volatile
        var lastStartError: String? = null

        fun isRunning(): Boolean = self != null
    }

    /** Raw fd handed to Dart; -1 when no tunnel is established. */
    private var tunFd: Int = -1
    private var established = false
    private var tearingDown = false

    override fun onCreate() {
        super.onCreate()
        self = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Notification "Disconnect": drop the tunnel without opening the app.
        if (intent?.action == ACTION_DISCONNECT) {
            stopTunnel(REASON_USER)
            return START_NOT_STICKY
        }

        val spec = VpnTunnelSpec.fromIntent(intent)
        if (spec == null) {
            Log.e(TAG, "start requested without a tunnel request; refusing")
            lastStartError = "start requested without a tunnel request"
            VpnEventBus.emit(errorPayload(lastStartError))
            stopSelf()
            return START_NOT_STICKY
        }

        // Single TUN only: a second start into this same instance replaces the
        // previous interface. (MainActivity also tears an older instance down
        // before starting a new one; this covers the restarted-service case.)
        if (established || tunFd >= 0) {
            releaseTunnel(REASON_SUPERSEDED)
        }

        try {
            // Must happen within ~5s of startForegroundService().
            startInForeground()
        } catch (t: Throwable) {
            lastStartError = t.message ?: t.javaClass.simpleName
            Log.e(TAG, "failed to enter the foreground", t)
            VpnEventBus.emit(errorPayload(lastStartError))
            stopTunnel(REASON_ERROR)
            return START_NOT_STICKY
        }

        val pfd = try {
            establish(spec)
        } catch (t: Throwable) {
            lastStartError = t.message ?: t.javaClass.simpleName
            Log.e(TAG, "failed to establish the TUN", t)
            VpnEventBus.emit(errorPayload(lastStartError))
            stopTunnel(REASON_ERROR)
            return START_NOT_STICKY
        }

        // Hand the descriptor to Dart. detachFd() transfers ownership to this
        // process's app code (us); the fd stays valid for the Rust core as long
        // as we do not close it.
        tunFd = pfd.detachFd()
        established = true
        activeTunnel = spec
        lastStartError = null

        Log.i(TAG, "tunnel established, fd=$tunFd ipv4=${spec.ipv4Cidr} routes=${spec.routes}")
        VpnNotification.notify(this, VpnNotification.State(connected = false))
        VpnEventBus.emit(startedPayload(spec, tunFd))
        EasyTierVpnTileService.requestStateUpdate(this)

        // Never resurrect a tunnel from a null intent: the TUN lives in this
        // process, and a restart would also lose the fd ownership chain.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        Log.d(TAG, "service destroying")
        // The system removes the FGS notification on stop; tearing down the fd
        // and clearing `self` is what this hook must guarantee (see onRevoke
        // for the "taken from us" case).
        releaseTunnel(REASON_DESTROY)
        if (self === this) self = null
        EasyTierVpnTileService.requestStateUpdate(this)
        super.onDestroy()
    }

    override fun onRevoke() {
        Log.i(TAG, "vpn slot revoked by the system")
        releaseTunnel(REASON_REVOKED)
        stopForeground(STOP_FOREGROUND_REMOVE)
        if (self === this) self = null
        EasyTierVpnTileService.requestStateUpdate(this)
        super.onRevoke()
        stopSelf()
    }

    /**
     * Tears the tunnel down from inside the app (`stop` method, notification
     * action, or a superseding start) and removes the ongoing notification.
     *
     * Safe to call from the main thread while the service is running; safe to
     * call when it is not (no-op).
     */
    fun stopTunnel(reason: String) {
        if (tearingDown) return
        tearingDown = true
        releaseTunnel(reason)
        stopForeground(STOP_FOREGROUND_REMOVE)
        if (self === this) self = null
        EasyTierVpnTileService.requestStateUpdate(this)
        stopSelf()
    }

    /**
     * Closes the TUN descriptor and reports the stop exactly once.
     *
     * Ownership note: the fd returned by `detachFd()` is ours, so closing it is
     * the teardown. We never close it twice (`established` flag) and never
     * close it while another tunnel is live (the field is cleared first).
     */
    private fun releaseTunnel(reason: String) {
        val wasEstablished = established || tunFd >= 0
        established = false
        val fd = tunFd
        tunFd = -1
        activeTunnel = null
        if (fd >= 0) {
            try {
                // adoptFd takes ownership of the raw descriptor, so close()
                // here is what actually closes our TUN fd.
                ParcelFileDescriptor.adoptFd(fd).close()
            } catch (t: Throwable) {
                Log.w(TAG, "failed to close TUN fd $fd", t)
            }
        }
        if (wasEstablished) {
            Log.i(TAG, "tunnel released, reason=$reason")
            VpnEventBus.emit(mapOf("type" to "stopped", "reason" to reason))
            EasyTierVpnTileService.requestStateUpdate(this)
        }
    }

    private fun startInForeground() {
        VpnNotification.ensureChannel(this)
        val notification = VpnNotification.build(this, VpnNotification.State(connected = false))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                VpnNotification.NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(VpnNotification.NOTIFICATION_ID, notification)
        }
    }

    private fun establish(spec: VpnTunnelSpec): ParcelFileDescriptor {
        val builder = Builder()
            .setSession(spec.session)
            .setMtu(spec.mtu)
            // The Rust core drives the descriptor through tokio's AsyncFd.
            .setBlocking(false)

        builder.addAddress(spec.ipv4Cidr.ipPart(), spec.ipv4Cidr.prefixPart())
        spec.ipv6Cidr?.let { builder.addAddress(it.ipPart(), it.prefixPart()) }

        for (route in spec.routes) {
            builder.addRoute(route.ipPart(), route.prefixPart())
        }
        for (server in spec.dns) {
            builder.addDnsServer(server)
        }

        // Android routes by uid; excluding our own package keeps the app's and
        // the Rust core's own sockets OUT of the tunnel. Without this, peer
        // connections and RPC would be routed back into the TUN and loop.
        // (The Tauri client passed its own package name explicitly.)
        try {
            builder.addDisallowedApplication(packageName)
        } catch (t: Throwable) {
            Log.w(TAG, "could not exclude $packageName from the tunnel", t)
        }
        for (app in spec.disallowedApplications) {
            if (app == packageName) continue
            try {
                builder.addDisallowedApplication(app)
            } catch (t: Throwable) {
                // An uninstalled/bogus package must not fail the whole tunnel.
                Log.w(TAG, "could not exclude $app from the tunnel", t)
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        return builder.establish()
            ?: throw IllegalStateException("VpnService.establish() returned null")
    }

    private fun String.ipPart(): String {
        val parts = split("/")
        require(parts.size == 2 && parts[0].isNotEmpty()) { "invalid CIDR: $this" }
        return parts[0]
    }

    private fun String.prefixPart(): Int {
        val parts = split("/")
        require(parts.size == 2) { "invalid CIDR: $this" }
        val prefix = parts[1].toIntOrNull()
            ?: throw IllegalArgumentException("invalid CIDR prefix: $this")
        require(prefix in 0..128) { "invalid CIDR prefix: $this" }
        return prefix
    }

    private fun startedPayload(spec: VpnTunnelSpec, fd: Int): Map<String, Any?> = mapOf(
        "type" to "started",
        "fd" to fd,
        "ipv4Cidr" to spec.ipv4Cidr,
        "ipv6Cidr" to spec.ipv6Cidr,
        "routes" to spec.routes,
        "dns" to spec.dns,
        "mtu" to spec.mtu,
        "session" to spec.session,
    )

    private fun errorPayload(message: String?): Map<String, Any?> = mapOf(
        "type" to "error",
        "message" to (message ?: "unknown VPN error"),
    )
}
