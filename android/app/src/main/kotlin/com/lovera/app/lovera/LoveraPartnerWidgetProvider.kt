package com.lovera.app.lovera

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

class LoveraPartnerWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.lovera_partner_widget).apply {
                // 0. Arka Plan Fotoğrafı & Kenardan Ortaya Karanlık (Vignette) Efekti
                val bgImagePath = widgetData.getString("widget_bg_image_path", null)
                if (bgImagePath != null && bgImagePath.isNotEmpty()) {
                    val file = File(bgImagePath)
                    if (file.exists()) {
                        try {
                            val bitmap = BitmapFactory.decodeFile(file.absolutePath)
                            if (bitmap != null) {
                                setImageViewBitmap(R.id.widget_bg_image, bitmap)
                                setViewVisibility(R.id.widget_bg_image, View.VISIBLE)
                                setViewVisibility(R.id.widget_bg_overlay, View.VISIBLE)
                            } else {
                                setViewVisibility(R.id.widget_bg_image, View.GONE)
                                setViewVisibility(R.id.widget_bg_overlay, View.GONE)
                            }
                        } catch (e: Exception) {
                            setViewVisibility(R.id.widget_bg_image, View.GONE)
                            setViewVisibility(R.id.widget_bg_overlay, View.GONE)
                        }
                    } else {
                        setViewVisibility(R.id.widget_bg_image, View.GONE)
                        setViewVisibility(R.id.widget_bg_overlay, View.GONE)
                    }
                } else {
                    setViewVisibility(R.id.widget_bg_image, View.GONE)
                    setViewVisibility(R.id.widget_bg_overlay, View.GONE)
                }

                // 1. Partner İsmi
                val partnerName = widgetData.getString("partner_name", "Partnerin") ?: "Partnerin"
                setTextViewText(R.id.widget_partner_name, partnerName)

                // 2. Aşk Sayacı (Gün Sayısı)
                val daysCount = widgetData.getString("days_count", "0") ?: "0"
                setTextViewText(R.id.widget_days_count, daysCount)

                // 3. Batarya Seviyesi ve Rengi (Azaldıkça seviyesi ve rengi dinamik değişir)
                val batteryLevel = widgetData.getString("battery_level", "%--") ?: "%--"
                setTextViewText(R.id.widget_battery_text, batteryLevel)
                val numericBat = batteryLevel.replace("%", "").trim().toIntOrNull()
                val batteryColor = when {
                    numericBat == null -> android.graphics.Color.parseColor("#34D399")
                    numericBat >= 50 -> android.graphics.Color.parseColor("#34D399") // Yeşil
                    numericBat >= 20 -> android.graphics.Color.parseColor("#FBBF24") // Sarı / Turuncu
                    else -> android.graphics.Color.parseColor("#EF4444") // Kritik Kırmızı
                }
                setTextColor(R.id.widget_battery_text, batteryColor)

                // Şarj doluluk oranına göre dikey batarya görseli çiz ve aktar
                val batteryBitmap = createBatteryBitmap(context, numericBat ?: 100, batteryColor)
                setImageViewBitmap(R.id.widget_battery_icon, batteryBitmap)

                // 4. Durum: Evde / Dışarıda / Yürüyor / Arabada
                val statusText = widgetData.getString("status_text", "Dışarıda") ?: "Dışarıda"
                val statusEmoji = widgetData.getString("status_emoji", "📍") ?: "📍"
                setTextViewText(R.id.widget_status_text, statusText)
                setTextViewText(R.id.widget_status_emoji, statusEmoji)

                // 5. Son Görülme / Durum zamanı
                val lastSeen = widgetData.getString("last_seen", "Şimdi aktif") ?: "Şimdi aktif"
                setTextViewText(R.id.widget_last_seen, lastSeen)
                if (lastSeen.contains("Şimdi aktif") || lastSeen.contains("Canlı")) {
                    setTextColor(R.id.widget_last_seen, android.graphics.Color.parseColor("#34D399")) // Canlı Yeşil
                } else {
                    setTextColor(R.id.widget_last_seen, android.graphics.Color.parseColor("#CBD5E1")) // Normal Açık Gri/Lavanta
                }

                // Widget'a dokunulduğunda Lovera uygulamasını aç
                val launchIntent = Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                val pendingIntent = PendingIntent.getActivity(
                    context,
                    0,
                    launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    /**
     * Şarj yüzdesine göre iOS / modern stil dikey batarya simgesi çizer.
     * Pil seviyesi azaldıkça doluluk seviyesi aşağı iner, rengi değişir.
     */
    private fun createBatteryBitmap(context: Context, percentage: Int, color: Int): android.graphics.Bitmap {
        val density = context.resources.displayMetrics.density
        val width = (13 * density).toInt().coerceAtLeast(24)
        val height = (20 * density).toInt().coerceAtLeast(36)

        val bitmap = android.graphics.Bitmap.createBitmap(width, height, android.graphics.Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(bitmap)

        val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)

        // 1. Dış Çerçeve (Gövde)
        val strokeWidth = 1.5f * density
        paint.style = android.graphics.Paint.Style.STROKE
        paint.strokeWidth = strokeWidth
        paint.color = android.graphics.Color.parseColor("#94A3B8") // Slate border

        val capHeight = 2f * density
        val capWidth = width * 0.45f
        val bodyTop = capHeight + strokeWidth / 2f
        val bodyBottom = height - strokeWidth / 2f
        val bodyLeft = strokeWidth / 2f
        val bodyRight = width - strokeWidth / 2f
        val cornerRadius = 3f * density

        val bodyRect = android.graphics.RectF(bodyLeft, bodyTop, bodyRight, bodyBottom)
        canvas.drawRoundRect(bodyRect, cornerRadius, cornerRadius, paint)

        // 2. Üst Terminal Kutup Başlığı (Küçük çıkıntı)
        paint.style = android.graphics.Paint.Style.FILL
        paint.color = android.graphics.Color.parseColor("#94A3B8")
        val capLeft = (width - capWidth) / 2f
        val capRect = android.graphics.RectF(capLeft, 0f, capLeft + capWidth, capHeight + strokeWidth)
        canvas.drawRoundRect(capRect, 1.5f * density, 1.5f * density, paint)

        // 3. İç Doluluk Seviyesi (Şarj oranına göre alttan yukarı dolar/boşalır)
        val validPercent = percentage.coerceIn(0, 100)
        if (validPercent > 0) {
            val padding = 2f * density
            val innerLeft = bodyLeft + strokeWidth / 2f + padding
            val innerRight = bodyRight - strokeWidth / 2f - padding
            val innerBottom = bodyBottom - strokeWidth / 2f - padding
            val innerMaxTop = bodyTop + strokeWidth / 2f + padding
            val availableHeight = innerBottom - innerMaxTop

            val fillHeight = (availableHeight * (validPercent / 100f)).coerceAtLeast(1f * density)
            val fillTop = innerBottom - fillHeight

            paint.color = color
            val fillRect = android.graphics.RectF(innerLeft, fillTop, innerRight, innerBottom)
            canvas.drawRoundRect(fillRect, 1.5f * density, 1.5f * density, paint)
        }

        return bitmap
    }
}
