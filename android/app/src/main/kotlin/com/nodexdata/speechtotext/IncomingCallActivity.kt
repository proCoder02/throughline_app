package com.nodexdata.speechtotext

import android.app.Activity
import android.app.KeyguardManager
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

private const val TAG = "TL_IncomingCallActivity"

/**
 * Native (non-Flutter) full-screen ringing UI, launched via a notification's
 * fullScreenIntent (see CallConnectionService.postIncomingCallNotification).
 * Exists because self-managed android.telecom.Connection state alone
 * (setRinging()) does not guarantee any visible UI -- whether an OEM dialer
 * renders it for a third-party self-managed call varies (confirmed broken
 * on this device's ColorOS dialer via adb/logcat: Telecom reached RINGING
 * but nothing appeared on screen). This activity draws the ringing screen
 * ourselves so it doesn't depend on the OEM's dialer at all. Deliberately
 * mirrors call_overlay.dart's incoming-call layout (same gradient, avatar,
 * circular Decline/Answer buttons) so the native and in-app screens read as
 * the same product rather than two different ones.
 */
class IncomingCallActivity : Activity() {

    companion object {
        // Tracks the currently-shown instance so a remote call_ended (see
        // CallConnection.endFromRemote) can dismiss this screen immediately.
        @Volatile
        var current: IncomingCallActivity? = null
            private set

        fun dismissIfShowing(callId: String) {
            val activity = current ?: return
            if (activity.callId == callId) {
                Log.d(TAG, "dismissIfShowing: dismissing for callId=$callId")
                activity.finish()
            }
        }
    }

    private var callId: String = ""

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        callId = intent.getStringExtra("call_id") ?: ""
        val callerName = intent.getStringExtra("caller_name") ?: "Unknown"
        val callerId = intent.getStringExtra("caller_id")
        val roomName = intent.getStringExtra("room_name")
        Log.d(TAG, "onCreate: callId=$callId callerName=$callerName")

        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        val keyguardManager = getSystemService(KEYGUARD_SERVICE) as? KeyguardManager
        keyguardManager?.requestDismissKeyguard(this, null)

        setContentView(buildUi(callerName))
        current = this
    }

    override fun onDestroy() {
        super.onDestroy()
        if (current === this) current = null
    }

    private fun weightedSpacer(weight: Float) = View(this).apply {
        layoutParams = LinearLayout.LayoutParams(0, 0, weight)
    }

    private fun buildUi(callerName: String): View {
        val root = LinearLayout(this).apply {
            layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            background = GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(Color.parseColor("#008069"), Color.parseColor("#0B141A"))
            )
            setPadding(dp(24), dp(24), dp(24), dp(24))
        }

        val initial = callerName.trim().let { if (it.isNotEmpty()) it[0].uppercaseChar().toString() else "?" }
        val avatarSize = dp(140)
        val avatar = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(avatarSize, avatarSize)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#33FFFFFF"))
            }
        }
        avatar.addView(
            TextView(this).apply {
                text = initial
                textSize = 56f
                setTextColor(Color.WHITE)
                gravity = Gravity.CENTER
                layoutParams = FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            }
        )

        val nameView = TextView(this).apply {
            text = callerName
            textSize = 26f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(0, dp(24), 0, 0)
        }
        val subtitleView = TextView(this).apply {
            text = "Incoming voice call..."
            textSize = 16f
            setTextColor(Color.parseColor("#B3FFFFFF"))
            gravity = Gravity.CENTER
            setPadding(0, dp(8), 0, 0)
        }

        val buttonRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                bottomMargin = dp(32)
            }
        }
        val declineButton = circleActionButton(
            iconRes = R.drawable.ic_call_end,
            label = "Decline",
            color = Color.parseColor("#DC3545"),
        ) {
            Log.d(TAG, "decline tapped: callId=$callId")
            CallConnectionService.activeConnections[callId]?.onReject()
            finish()
        }
        val answerButton = circleActionButton(
            iconRes = R.drawable.ic_call,
            label = "Answer",
            color = Color.parseColor("#25D366"),
        ) {
            Log.d(TAG, "answer tapped: callId=$callId")
            CallConnectionService.activeConnections[callId]?.onAnswer()
            finish()
        }
        buttonRow.addView(declineButton)
        buttonRow.addView(weightedSpacerFixed(dp(64)))
        buttonRow.addView(answerButton)

        root.addView(weightedSpacer(2f))
        root.addView(avatar)
        root.addView(nameView)
        root.addView(subtitleView)
        root.addView(weightedSpacer(3f))
        root.addView(buttonRow)
        return root
    }

    private fun weightedSpacerFixed(width: Int) = View(this).apply {
        layoutParams = LinearLayout.LayoutParams(width, 1)
    }

    /** A colored circular icon button with a text label underneath, matching
     * call_overlay.dart's _CallButton widget on the Flutter side. */
    private fun circleActionButton(iconRes: Int, label: String, color: Int, onTap: () -> Unit): LinearLayout {
        val size = dp(72)
        val circle = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(size, size)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(color)
            }
            elevation = dp(4).toFloat()
            isClickable = true
            setOnClickListener { onTap() }
        }
        circle.addView(
            ImageView(this).apply {
                setImageResource(iconRes)
                layoutParams = FrameLayout.LayoutParams(dp(32), dp(32), Gravity.CENTER)
            }
        )
        val labelView = TextView(this).apply {
            text = label
            textSize = 13f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(0, dp(8), 0, 0)
        }
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            addView(circle)
            addView(labelView)
        }
    }
}
