package com.lovera.app.lovera

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

class LoveraDrawingWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.lovera_drawing_widget).apply {
                val drawingImagePath = widgetData.getString("drawing_image_path", null)
                val senderName = widgetData.getString("drawing_sender_name", null)
                val timestampMillis = widgetData.getLong("drawing_timestamp_millis", 0L)
                val timeAgo: String = if (timestampMillis > 0) {
                    val diffMillis = System.currentTimeMillis() - timestampMillis
                    val diffMinutes = (diffMillis / 60000).toInt()
                    when {
                        diffMinutes < 1 -> "Şimdi"
                        diffMinutes < 60 -> "$diffMinutes dk önce"
                        diffMinutes < 1440 -> "${diffMinutes / 60} sa önce"
                        else -> "${diffMinutes / 1440} gün önce"
                    }
                } else {
                    widgetData.getString("drawing_time_ago", "Şimdi") ?: "Şimdi"
                }

                if (drawingImagePath != null && drawingImagePath.isNotEmpty()) {
                    val file = File(drawingImagePath)
                    if (file.exists()) {
                        try {
                            val bitmap = BitmapFactory.decodeFile(file.absolutePath)
                            if (bitmap != null) {
                                setImageViewBitmap(R.id.widget_drawing_image, bitmap)
                                setViewVisibility(R.id.widget_drawing_image, View.VISIBLE)
                                setViewVisibility(R.id.widget_drawing_placeholder, View.GONE)

                                // Gönderen rozeti
                                setViewVisibility(R.id.widget_drawing_badge, View.VISIBLE)
                                setTextViewText(R.id.widget_drawing_sender_text, senderName ?: "Partnerin")
                                setTextViewText(R.id.widget_drawing_time_text, "• $timeAgo")
                            } else {
                                showPlaceholder()
                            }
                        } catch (e: Exception) {
                            showPlaceholder()
                        }
                    } else {
                        showPlaceholder()
                    }
                } else {
                    showPlaceholder()
                }

                // Tıklanma Aksiyonu: Doğrudan çizim ekranını açacak Uri ile yönlendirme
                val clickIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("lovera://open_drawing")
                )
                setOnClickPendingIntent(R.id.widget_drawing_root, clickIntent)
                setOnClickPendingIntent(R.id.widget_drawing_btn_reply, clickIntent)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun RemoteViews.showPlaceholder() {
        setViewVisibility(R.id.widget_drawing_image, View.GONE)
        setViewVisibility(R.id.widget_drawing_badge, View.GONE)
        setViewVisibility(R.id.widget_drawing_placeholder, View.VISIBLE)
    }
}
