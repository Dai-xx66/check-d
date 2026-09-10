package com.daixx66.check_d

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.temporal.ChronoUnit

/** A read-only Android Home Screen AppWidget backed by the Flutter snapshot. */
class CheckDHomeWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { update(context, appWidgetManager, it) }
    }

    companion object {
        private const val preferences = "check_d_home_widget"

        fun update(context: Context, manager: AppWidgetManager, id: Int) {
            val views = RemoteViews(context.packageName, R.layout.home_widget)
            val raw = context.getSharedPreferences(preferences, Context.MODE_PRIVATE)
                .getString("snapshot", null)
            val snapshot = raw?.let { runCatching { JSONObject(it) }.getOrNull() }
            if (snapshot == null || isStale(snapshot)) renderFallback(context, views)
            else render(context, snapshot, views)
            views.setOnClickPendingIntent(R.id.widget_root, openTodayIntent(context))
            manager.updateAppWidget(id, views)
        }

        private fun render(context: Context, snapshot: JSONObject, views: RemoteViews) {
            val current = snapshot.optJSONObject("current")
            val next = snapshot.optJSONObject("next")
            val today = snapshot.optJSONObject("today")
            if (current == null || today == null) {
                renderFallback(context, views)
                return
            }
            views.setTextViewText(R.id.widget_title, "Check D")
            views.setTextViewText(R.id.widget_date, text(snapshot, "dateText", "今天"))
            views.setTextViewText(R.id.widget_state, text(current, "subtitle", "现在"))
            views.setTextViewText(R.id.widget_current_title, text(current, "title", "今天慢慢来 ♡"))
            val timeText = text(current, "timeText")
            views.setTextViewText(R.id.widget_current_time, timeText)
            views.setViewVisibility(R.id.widget_current_time, if (timeText.isBlank()) View.GONE else View.VISIBLE)
            views.setImageViewResource(R.id.widget_sheep, sheepResource(context, text(current, "sheepState", "idle")))

            val progress = current.optDouble("progress", -1.0)
            views.setViewVisibility(R.id.widget_course_progress, if (progress in 0.0..1.0) View.VISIBLE else View.GONE)
            if (progress in 0.0..1.0) views.setProgressBar(R.id.widget_course_progress, 100, (progress * 100).toInt(), false)

            val concurrent = current.optJSONObject("concurrentTimer")
            val concurrentText = concurrent?.let {
                val prefix = if (text(it, "status") == "paused") "已暂停" else "同时专注"
                val extra = current.optInt("additionalTimerCount", 0)
                joinSegments(prefix, text(it, "title"), duration(it.optInt("elapsedSeconds", 0)), if (extra > 0) "另有 $extra 项" else null)
            }.orEmpty()
            views.setTextViewText(R.id.widget_concurrent, concurrentText)
            views.setViewVisibility(R.id.widget_concurrent, if (concurrentText.isBlank() || !isCourse(current)) View.GONE else View.VISIBLE)

            if (next == null) {
                views.setTextViewText(R.id.widget_next_title, "接下来")
                views.setTextViewText(R.id.widget_next_detail, "今天慢慢来 ♡")
            } else {
                views.setTextViewText(R.id.widget_next_title, "接下来 · ${text(next, "title", "暂无安排")}")
                views.setTextViewText(R.id.widget_next_detail, joinSegments(text(next, "timeText"), textOrNull(next, "location")))
            }
            views.setTextViewText(R.id.widget_summary_complete, "✓ 已完成 ${today.optInt("completedCount", 0)}")
            views.setTextViewText(R.id.widget_summary_pending, "待完成 ${today.optInt("pendingCount", 0)}")
        }

        private fun renderFallback(context: Context, views: RemoteViews) {
            views.setTextViewText(R.id.widget_title, "Check D")
            views.setTextViewText(R.id.widget_date, "今天")
            views.setTextViewText(R.id.widget_state, "现在")
            views.setTextViewText(R.id.widget_current_title, "今天慢慢来 ♡")
            views.setTextViewText(R.id.widget_current_time, "打开 Check D 更新今天状态")
            views.setImageViewResource(R.id.widget_sheep, sheepResource(context, "idle"))
            views.setViewVisibility(R.id.widget_course_progress, View.GONE)
            views.setViewVisibility(R.id.widget_concurrent, View.GONE)
            views.setTextViewText(R.id.widget_next_title, "接下来")
            views.setTextViewText(R.id.widget_next_detail, "暂无安排")
            views.setTextViewText(R.id.widget_summary_complete, "✓ 已完成 0")
            views.setTextViewText(R.id.widget_summary_pending, "待完成 0")
        }

        private fun openTodayIntent(context: Context): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = Uri.parse("checkd://today")
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            return PendingIntent.getActivity(context, 1101, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        private fun isStale(snapshot: JSONObject): Boolean {
            if (snapshot.optInt("schemaVersion") != 2 || text(snapshot, "dateKey") != LocalDate.now().toString()) return true
            val generatedAt = text(snapshot, "generatedAt")
            if (generatedAt.isBlank()) return true
            return runCatching { Instant.parse(generatedAt).isBefore(Instant.now().minus(6, ChronoUnit.HOURS)) }.getOrDefault(true)
        }

        private fun isCourse(current: JSONObject): Boolean = text(current, "mode") in setOf("courseTeaching", "courseBreak")

        private fun sheepResource(context: Context, state: String): Int = when (state) {
            "course" -> context.resources.getIdentifier("sheep_course", "drawable", context.packageName)
            "breakTime" -> context.resources.getIdentifier("sheep_break", "drawable", context.packageName)
            "focus" -> context.resources.getIdentifier("sheep_focus", "drawable", context.packageName)
            "paused" -> context.resources.getIdentifier("sheep_paused", "drawable", context.packageName)
            else -> context.resources.getIdentifier("sheep_idle", "drawable", context.packageName)
        }

        private fun text(source: JSONObject, key: String, fallback: String = ""): String = textOrNull(source, key) ?: fallback

        private fun textOrNull(source: JSONObject, key: String): String? {
            val value = source.opt(key)
            if (value == null || value == JSONObject.NULL) return null
            return value.toString().trim().takeUnless { it.isBlank() || it == "null" || it == "undefined" }
        }

        private fun joinSegments(vararg values: String?): String = values.mapNotNull { it?.trim()?.takeUnless(String::isBlank) }.joinToString(" · ")

        private fun duration(seconds: Int): String {
            val minutes = seconds / 60
            return if (minutes >= 60) "${minutes / 60}小时${minutes % 60}分" else "$minutes 分钟"
        }
    }
}
