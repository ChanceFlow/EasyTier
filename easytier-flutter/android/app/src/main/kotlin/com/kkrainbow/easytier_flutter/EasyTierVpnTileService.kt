package com.kkrainbow.easytier_flutter

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log

/**
 * Quick-settings tile for the EasyTier tunnel.
 *
 * A tap never starts the data plane by itself: the TUN fd must reach Dart (and
 * from there the Rust core), and newer Android versions block starting a
 * `specialUse` foreground service from the background. So the tile:
 *  - hands `start`/`stop` to Dart through [VpnTileBridge] when the app is in
 *    the foreground and Dart is listening;
 *  - otherwise opens the app and persists the pending action in
 *    SharedPreferences, which Dart drains via the `consumeTileAction` method.
 *
 * This is the Flutter port of the Tauri client's EasyTierVpnTileService,
 * including the stale-action rule: a tap always derives its intent from the
 * live tunnel state and overwrites any leftover pending action.
 */
class EasyTierVpnTileService : TileService() {

    companion object {
        private const val TAG = "EasyTierVpnTile"

        private const val PREFS_NAME = "easytier_vpn_tile"
        private const val PENDING_ACTION_KEY = "pending_action"

        const val ACTION_START = "start"
        const val ACTION_STOP = "stop"

        /** Reads and clears the pending action, atomically enough for a tile tap. */
        @Synchronized
        fun consumePendingAction(context: Context): String? {
            val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val action = preferences.getString(PENDING_ACTION_KEY, null)
            if (action != null) {
                preferences.edit().remove(PENDING_ACTION_KEY).commit()
            }
            return action
        }

        /** Asks the system to refresh the tile (state changed under it). */
        fun requestStateUpdate(context: Context) {
            try {
                requestListeningState(
                    context,
                    ComponentName(context, EasyTierVpnTileService::class.java),
                )
            } catch (t: Throwable) {
                Log.w(TAG, "could not request tile listening state", t)
            }
        }

        private fun savePendingAction(context: Context, action: String) {
            // TileService may be reclaimed as soon as onClick returns, so the
            // write has to be synchronous.
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

    private fun handleClick() {
        val desired = if (EasyTierVpnService.isRunning()) ACTION_STOP else ACTION_START
        savePendingAction(this, desired)

        // Starting needs the VPN consent grant, which can only be presented
        // from a visible activity.
        val consentMissing = desired == ACTION_START && VpnService.prepare(this) != null

        val delivered = MainActivity.isInForeground && VpnTileBridge.dispatch(desired)
        if (!delivered) {
            // Nothing can act on the tap right now: surface the app, which
            // drains the pending action (and shows the consent dialog).
            updateTileState()
            openApp()
            return
        }

        // Delivered to Dart: optimistic feedback while the async start/stop
        // lands. Without consent the real state is still "not connected".
        updateTileState(if (consentMissing) null else desired)
    }

    /**
     * @param pendingAction action just handed to Dart, for immediate feedback;
     *   null reads the real service state.
     */
    private fun updateTileState(pendingAction: String? = null) {
        val tile = qsTile ?: return
        val active = when (pendingAction) {
            ACTION_START -> true
            ACTION_STOP -> false
            else -> EasyTierVpnService.isRunning()
        }
        tile.state = if (active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            tile.stateDescription = getString(
                if (active) R.string.vpn_tile_state_on else R.string.vpn_tile_state_off,
            )
        }
        tile.updateTile()
    }

    private fun openApp() {
        val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        } ?: return

        try {
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
        } catch (t: Throwable) {
            Log.w(TAG, "could not open the app from the tile", t)
        }
    }
}
