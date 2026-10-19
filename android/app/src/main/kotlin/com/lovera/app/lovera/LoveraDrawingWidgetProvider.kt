package com.lovera.app.lovera

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

class LoveraDrawingWidgetProvider : HomeWidgetProvider() {

    companion object {
        private const val ACTION_AUTO_TICK = "com.lovera.app.lovera.DRAWING_WIDGET_TICK"
        private const val TICK_INTERVAL_MS = 60000L // Her 60 saniyede bir çizim süresini güncelle
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_AUTO_TICK) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val thisWidget = ComponentName(context, LoveraDrawingWidgetProvider::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget)
            if (appWidgetIds != null && appWidgetIds.isNotEmpty()) {
                val widgetData = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
                onUpdate(context, appWidgetManager, appWidgetIds, widgetData)
            }
        }
    }

    private fun scheduleNextTick(context: Context) {
        try {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val tickIntent = Intent(context, LoveraDrawingWidgetProvider::class.java).apply {
                action = ACTION_AUTO_TICK
                setPackage(context.packageName)
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                1002,
                tickIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val triggerAtMillis = System.currentTimeMillis() + TICK_INTERVAL_MS
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                if (alarmManager.canScheduleExactAlarms()) {
                    alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC, triggerAtMillis, pendingIntent)
                } else {
                    alarmManager.setAndAllowWhileIdle(AlarmManager.RTC, triggerAtMillis, pendingIntent)
                }
            } else if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC, triggerAtMillis, pendingIntent)
            } else {
                alarmManager.set(AlarmManager.RTC, triggerAtMillis, pendingIntent)
            }
        } catch (_: Exception) {
            // Cihaz pil tasarrufu veya izin kısıtlaması durumunda sessizce geç
        }
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        try {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val tickIntent = Intent(context, LoveraDrawingWidgetProvider::class.java).apply {
                action = ACTION_AUTO_TICK
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                1002,
                tickIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager.cancel(pendingIntent)
        } catch (_: Exception) {}
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        // Bir sonraki dakika güncellemesini takvimle
        scheduleNextTick(context)
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.lovera_drawing_widget).apply {
                val drawingImagePath = widgetData.getString("drawing_image_path", null)
                val senderName = widgetData.getString("drawing_sender_name", null)
                val timestampMillis: Long = try {
                    widgetData.getLong("drawing_timestamp_millis", 0L)
                } catch (_: Exception) {
                    try {
                        widgetData.getInt("drawing_timestamp_millis", 0).toLong()
                    } catch (_: Exception) {
                        widgetData.getString("drawing_timestamp_millis", "0")?.toLongOrNull() ?: 0L
                    }
                }

                val timeAgo: String = if (timestampMillis > 0L) {
                    val diffMillis = System.currentTimeMillis() - timestampMillis
                    val diffMinutes = (diffMillis / 60000).toInt()
                    val diffHours = diffMinutes / 60
                    val diffDays = diffHours / 24

                    when {
                        diffMinutes < 1 -> "Şimdi"
                        diffMinutes < 60 -> "$diffMinutes dk önce"
                        diffHours < 24 -> "$diffHours sa önce"
                        diffDays < 30 -> "$diffDays gün önce"
                        else -> "${diffDays / 30} ay önce"
                    }
                } else {
                    val fallback = widgetData.getString("drawing_time_ago", "Şimdi") ?: "Şimdi"
                    if (fallback.contains("dk önce") || fallback == "Şimdi") "Eski çizim" else fallback
                }

                // Tema Tespiti (Koyu / Açık) - Varsayılan koyu gece teması
                val widgetTheme = widgetData.getString("widget_theme", "dark") ?: "dark"
                val isDarkTheme = when (widgetTheme) {
                    "light" -> false
                    "dark" -> true
                    else -> {
                        val nightModeFlags = context.resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK
                        nightModeFlags != android.content.res.Configuration.UI_MODE_NIGHT_NO
                    }
                }

                // Arka plan deseni ve çip stilleri (Sanatsal Eskiz & Çizim Teması)
                if (isDarkTheme) {
                    setImageViewResource(R.id.widget_drawing_bg_pattern, R.drawable.widget_drawing_background)
                    setInt(R.id.widget_drawing_badge, "setBackgroundResource", R.drawable.widget_chip_bg)
                    setInt(R.id.widget_drawing_btn_reply, "setBackgroundResource", R.drawable.widget_chip_bg)
                    setTextColor(R.id.widget_drawing_sender_text, android.graphics.Color.parseColor("#F3F4F6"))
                    setTextColor(R.id.widget_drawing_empty_title, android.graphics.Color.parseColor("#F3F4F6"))
                    setTextColor(R.id.widget_drawing_empty_subtitle, android.graphics.Color.parseColor("#A78BFA"))
                } else {
                    setImageViewResource(R.id.widget_drawing_bg_pattern, R.drawable.widget_drawing_background_light)
                    setInt(R.id.widget_drawing_badge, "setBackgroundResource", R.drawable.widget_chip_bg_light)
                    setInt(R.id.widget_drawing_btn_reply, "setBackgroundResource", R.drawable.widget_chip_bg_light)
                    setTextColor(R.id.widget_drawing_sender_text, android.graphics.Color.parseColor("#1E1B4B"))
                    setTextColor(R.id.widget_drawing_empty_title, android.graphics.Color.parseColor("#1E1B4B"))
                    setTextColor(R.id.widget_drawing_empty_subtitle, android.graphics.Color.parseColor("#7C3AED"))
                }

                if (drawingImagePath != null && drawingImagePath.isNotEmpty()) {
                    val file = File(drawingImagePath)
                    if (file.exists()) {
                        try {
                            val originalBitmap = BitmapFactory.decodeFile(file.absolutePath)
                            if (originalBitmap != null) {
                                val adjustedBitmap = adjustDrawingContrast(originalBitmap, isDarkTheme)
                                setImageViewBitmap(R.id.widget_drawing_image, adjustedBitmap)
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

    /**
     * Eğer çizilen renk widget'ın teması ile aynı/yakın tonda ise (koyu temada siyah/koyu çizim veya açık temada beyaz/açık çizim)
     * çizimin kaybolmaması için sadece o rengi otomatik zıt renge çevirir.
     * Canlı renkler (mor, pembe, kırmızı, sarı vb.) kesinlikle bozulmaz.
     */
    private fun adjustDrawingContrast(sourceBitmap: Bitmap, isDarkTheme: Boolean): Bitmap {
        return try {
            val width = sourceBitmap.width
            val height = sourceBitmap.height
            val pixels = IntArray(width * height)
            sourceBitmap.getPixels(pixels, 0, width, 0, 0, width, height)

            var modified = false

            for (i in pixels.indices) {
                val color = pixels[i]
                val a = (color shr 24) and 0xff
                if (a < 30) continue // Şeffaf arka plan piksellerine dokunma

                val r = (color shr 16) and 0xff
                val g = (color shr 8) and 0xff
                val b = color and 0xff

                if (isDarkTheme) {
                    // Koyu widget teması: Çizim siyah veya çok koyu gri/tonda ise (#1E293B gibi), koyu arka planda görünmesi için açık renge (#F3F4F6) çevir
                    if (r < 55 && g < 55 && b < 55) {
                        pixels[i] = (a shl 24) or (0xF3 shl 16) or (0xF4 shl 8) or 0xF6
                        modified = true
                    }
                } else {
                    // Açık widget teması: Çizim beyaz veya çok açık tonlarda ise (#FFFFFF gibi), açık arka planda görünmesi için koyu mürekkebe (#1E293B) çevir
                    if (r > 215 && g > 215 && b > 215) {
                        pixels[i] = (a shl 24) or (0x1E shl 16) or (0x29 shl 8) or 0x3B
                        modified = true
                    }
                }
            }

            if (modified) {
                Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
            } else {
                sourceBitmap
            }
        } catch (_: Exception) {
            sourceBitmap
        }
    }
}
