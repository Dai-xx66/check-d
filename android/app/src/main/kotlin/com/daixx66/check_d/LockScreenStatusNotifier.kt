package com.daixx66.check_d

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Native presentation only. Flutter projects the effective course/timer state. */
object LockScreenStatusNotifier {
    // Notification channels are immutable once created. Use a new ID so users
    // with the Stage 12 low-importance channel receive the corrected defaults.
    private const val channelId = "check_d_live_status_v2"
    private const val notificationId = 12031

    fun sync(context: Context, rawJson: String): Boolean {
        val snapshot = JSONObject(rawJson)
        if (snapshot.optString("mode") == "idle") {
            NotificationManagerCompat.from(context).cancel(notificationId)
            return false
        }
        if (!canPost(context)) return false

        ensureChannel(context)
        val mode = snapshot.optString("mode")
        val course = snapshot.optJSONObject("course")
        val timer = snapshot.optJSONObject("timer")
        val nextCourse = snapshot.optJSONObject("nextCourse")
        val title = optionalString(course, "title")
            ?: optionalString(timer, "title")
            ?: "Check D"
        val stateLabel = when (mode) {
            "courseTeaching" -> "上课中"
            "courseBreak" -> "课间休息"
            "timerRunning" -> "专注进行中"
            "timerPaused" -> "已暂停"
            else -> "Check D"
        }
        val courseDetail = course?.let(::courseDetail)
        val primaryDetail = when {
            courseDetail != null -> courseDetail
            timer != null && mode == "timerPaused" -> "累计 ${duration(timer.optInt("elapsedSeconds"))}"
            else -> "正在记录专注时间"
        }
        val concurrentTimerDetail = if (course != null && timer != null) {
            val timerTitle = optionalString(timer, "title") ?: "计时事项"
            if (timer.optString("status") == "paused") {
                joinSegments("已暂停 $timerTitle", "累计 ${duration(timer.optInt("elapsedSeconds"))}")
            } else {
                "同时专注 $timerTitle"
            }
        } else null
        val additionalTimerDetail = if (course != null) {
            snapshot.optInt("additionalTimerCount").takeIf { it > 0 }?.let {
                "另有 $it 项"
            }
        } else null
        val collapsedText = if (course != null && concurrentTimerDetail != null) {
            joinSegments(concurrentTimerDetail, additionalTimerDetail)
        } else {
            primaryDetail
        }
        val expandedLines = listOfNotNull(
            courseDetail,
            concurrentTimerDetail,
            additionalTimerDetail,
            nextCourseDetail(nextCourse),
        )
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            data = android.net.Uri.parse("checkd://today")
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            notificationId,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_lock_screen_status)
            .setLargeIcon(BitmapFactory.decodeResource(context.resources, sheepResource(mode)))
            .setContentTitle("$stateLabel · $title")
            .setContentText(collapsedText)
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    expandedLines.joinToString("\n"),
                ),
            )
            .setContentIntent(pendingIntent)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

        val publicVersion = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_lock_screen_status)
            .setContentTitle("$stateLabel · $title")
            .setContentText(collapsedText)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
        builder.setPublicVersion(publicVersion)

        // Android 16+ can promote an eligible, user-initiated live update to
        // more prominent system surfaces. It remains an OS/user decision.
        if (timer?.optString("status") == "running") {
            builder.setRequestPromotedOngoing(true)
        }

        if (course != null) {
            builder.setProgress(100, (course.optDouble("progress") * 100).toInt().coerceIn(0, 100), false)
        }
        if (timer?.optString("status") == "running") {
            val startedAt = timer?.optLong("runningSinceEpochMs") ?: 0L
            if (startedAt > 0) {
                builder.setWhen(startedAt).setUsesChronometer(true).setShowWhen(true)
            }
        } else {
            builder.setShowWhen(false)
        }
        NotificationManagerCompat.from(context).notify(notificationId, builder.build())
        return true
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                channelId,
                "实时状态",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "显示当前课程或专注状态"
                setShowBadge(false)
                setLockscreenVisibility(Notification.VISIBILITY_PUBLIC)
                setSound(null, null)
                enableVibration(false)
                enableLights(false)
            },
        )
    }

    private fun canPost(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return false
        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    private fun courseDetail(course: JSONObject): String? {
        val timeRange = if (course.optLong("startAtEpochMs") > 0 && course.optLong("endAtEpochMs") > 0) {
            "${clock(course.optLong("startAtEpochMs"))} — ${clock(course.optLong("endAtEpochMs"))}"
        } else null
        return joinSegments(timeRange, optionalString(course, "classroom")).takeIf { it.isNotEmpty() }
    }

    private fun nextCourseDetail(course: JSONObject?): String? {
        if (course == null) return null
        val time = course.optLong("startAtEpochMs").takeIf { it > 0 }?.let(::clock)
        val detail = joinSegments(
            optionalString(course, "title"),
            time,
            optionalString(course, "classroom"),
        )
        return detail.takeIf { it.isNotEmpty() }?.let { "下节课：$it" }
    }

    private fun optionalString(object_: JSONObject?, key: String): String? {
        val value = object_?.opt(key) ?: return null
        if (value == JSONObject.NULL) return null
        return value.toString().trim().takeIf { text ->
            text.isNotEmpty() &&
                !text.equals("null", ignoreCase = true) &&
                !text.equals("undefined", ignoreCase = true)
        }
    }

    private fun joinSegments(vararg segments: String?): String =
        segments.mapNotNull { it?.trim()?.takeIf(String::isNotEmpty) }.joinToString(" · ")

    private fun sheepResource(mode: String): Int = when (mode) {
        "courseTeaching" -> R.drawable.sheep_course
        "courseBreak" -> R.drawable.sheep_break
        "timerPaused" -> R.drawable.sheep_paused
        else -> R.drawable.sheep_focus
    }

    private fun clock(epochMs: Long): String =
        SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(epochMs))

    private fun duration(seconds: Int): String {
        val minutes = seconds / 60
        return if (minutes >= 60) "${minutes / 60}h ${minutes % 60}m" else "${minutes}m"
    }
}
