package com.cocoscout.app.door

import android.app.Activity
import android.view.WindowManager

/**
 * Keeps the screen from locking while anything asks it to: the door page
 * while it's showing, the scanner while it's open. Like KeepAwake.swift.
 */
object KeepAwake {
    private val holders = mutableSetOf<String>()

    fun hold(activity: Activity?, holder: String) {
        holders.add(holder)
        update(activity)
    }

    fun release(activity: Activity?, holder: String) {
        holders.remove(holder)
        update(activity)
    }

    private fun update(activity: Activity?) {
        val window = activity?.window ?: return
        if (holders.isEmpty()) {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }
}
