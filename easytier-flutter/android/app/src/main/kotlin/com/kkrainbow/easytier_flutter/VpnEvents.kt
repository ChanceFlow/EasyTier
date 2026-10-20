package com.kkrainbow.easytier_flutter

import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * Process-wide bridge between [EasyTierVpnService] and the Flutter side.
 *
 * The VPN foreground service can outlive the activity (the system keeps it
 * while the tunnel is up), so the service must never hold an `EventChannel`
 * sink directly. It emits events here instead; [MainActivity] registers a
 * listener when Dart starts listening and unregisters it on teardown. When no
 * listener is registered the events are dropped - the Dart side then
 * reconciles through `status()` on the next attach, which is exactly what the
 * Tauri client's boot drain did.
 *
 * Events are always delivered on the main thread and in emission order, which
 * keeps the start/stop ordering used by the fd handoff deterministic.
 */
internal object VpnEventBus {
    private const val TAG = "VpnEventBus"

    private val mainHandler = Handler(Looper.getMainLooper())

    fun interface Listener {
        fun onVpnEvent(event: Map<String, Any?>)
    }

    @Volatile
    private var listener: Listener? = null

    fun register(listener: Listener?) {
        this.listener = listener
    }

    fun emit(event: Map<String, Any?>) {
        mainHandler.post {
            try {
                listener?.onVpnEvent(event)
            } catch (t: Throwable) {
                Log.e(TAG, "vpn event delivery failed: $event", t)
            }
        }
    }
}

/**
 * Quick-settings tile -> Dart action channel.
 *
 * [EasyTierVpnTileService] may only report a tap as handled when a live Dart
 * listener consumed it; otherwise the tile falls back to opening the app,
 * which drains the persisted pending action on boot. This mirrors the
 * "delivered == has a live listener" contract of the deprecated Tauri client.
 */
internal object VpnTileBridge {
    private const val TAG = "VpnTileBridge"

    @Volatile
    var listener: ((String) -> Boolean)? = null

    fun dispatch(action: String): Boolean {
        val current = listener ?: return false
        return try {
            current(action)
        } catch (t: Throwable) {
            Log.e(TAG, "tile action dispatch failed", t)
            false
        }
    }
}
