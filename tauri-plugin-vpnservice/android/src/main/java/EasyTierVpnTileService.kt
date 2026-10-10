package com.plugin.vpnservice

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

class EasyTierVpnTileService : TileService() {
    companion object {
        private const val PREFS_NAME = "easytier_vpn_tile"
        private const val PENDING_ACTION_KEY = "pending_action"
        const val ACTION_START = "start"
        const val ACTION_STOP = "stop"

        @Synchronized
        fun consumePendingAction(context: Context): String? {
            val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val action = preferences.getString(PENDING_ACTION_KEY, null)
            if (action != null) {
                preferences.edit().remove(PENDING_ACTION_KEY).commit()
            }
            return action
        }

        fun requestStateUpdate(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                requestListeningState(context, ComponentName(context, EasyTierVpnTileService::class.java))
            }
        }

        private fun savePendingAction(context: Context, action: String) {
            // TileService may be reclaimed as soon as onClick returns, so persist synchronously.
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(PENDING_ACTION_KEY, action)
                .commit()
        }
    }

    override fun onStartListening() {
        super.onStartListening()
        updateTileState()
    }

    override fun onClick() {
        super.onClick()

        if (isLocked) {
            unlockAndRun(::handleClick)
        } else {
            handleClick()
        }
    }

    /**
     * A tap always carries the FRESH intent, derived from the live tunnel state
     * (`TauriVpnService.self`); the persisted pending action is only the
     * fallback the app drains when it was not running. Deriving it from live
     * state (instead of reading back a stored value) is what keeps the switch
     * from getting pinned to a stale action for ever.
     */
    private fun handleClick() {
        val desired = if (TauriVpnService.self == null) ACTION_START else ACTION_STOP

        // Overwrite unconditionally: a leftover value from an earlier session
        // must never override the intent the user just expressed. JS consumes
        // (and clears) it via consumeVpnTileAction right after the event below;
        // if the event cannot be delivered, the app boot drain consumes it.
        savePendingAction(this, desired)

        // A start without the VPN consent grant cannot run from the background:
        // the app is brought forward below so the system dialog can be shown,
        // while the pending action stays for JS to drain.
        val permissionRequired = desired == ACTION_START && VpnService.prepare(this) != null

        // Only true when a live JS listener exists (see VpnServicePlugin), so a
        // tap is never treated as handled when nothing can act on it.
        val delivered = VpnServicePlugin.dispatchTileAction(desired)

        if (!delivered) {
            // Nothing reached a live JS handler: surface the app so it drains
            // the pending action (and shows the consent dialog when needed).
            updateTileState()
            openApp()
            return
        }

        // Handed to a live JS handler: optimistic feedback while the async
        // start/stop lands. Without the consent grant nothing can start yet, so
        // keep showing the real (inactive) state.
        updateTileState(if (permissionRequired) null else desired)

        if (permissionRequired) {
            openApp()
        }
    }

    /**
     * @param pendingAction the action that was just handed over, used for
     *   immediate optimistic feedback; null reads the real service state.
     */
    private fun updateTileState(pendingAction: String? = null) {
        val tile = qsTile ?: return
        val active = when (pendingAction) {
            ACTION_START -> true
            ACTION_STOP -> false
            else -> TauriVpnService.self != null
        }
        tile.state = if (active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        // The visible label comes from the manifest; expose the on/off state to
        // accessibility services (Tile#setStateDescription is API 30+).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            tile.stateDescription = tileStateDescription(active)
        }
        tile.updateTile()
    }

    /**
     * Localized state label. Tile-specific strings are preferred when present;
     * otherwise fall back to the app-wide notification copy so the label still
     * follows the device language. Runtime lookup keeps this library module
     * free of compile-time dependencies on app-module resources.
     */
    private fun tileStateDescription(active: Boolean): CharSequence {
        val candidates = if (active) {
            arrayOf("vpn_tile_state_on", "notification_title_connected")
        } else {
            arrayOf("vpn_tile_state_off", "notification_action_disconnect")
        }
        for (name in candidates) {
            val id = resources.getIdentifier(name, "string", packageName)
            if (id != 0) {
                return getString(id)
            }
        }
        return if (active) "Connected" else "Not connected"
    }

    private fun openApp() {
        val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        } ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pendingIntent = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            startActivityAndCollapse(pendingIntent)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
