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
                    alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
                } else {
                    alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
                }
            } else if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
            } else {
                alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
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

                val isEn = widgetData.getString("app_language", "tr") == "en"

                val timeAgo: String = if (timestampMillis > 0L) {
                    val diffMillis = Math.max(0L, System.currentTimeMillis() - timestampMillis)
                    val diffMinutes = (diffMillis / 60000).toInt()
                    val diffHours = diffMinutes / 60
                    val diffDays = diffHours / 24

                    when {
                        diffMinutes < 1 -> if (isEn) "Just now" else "Şimdi"
                        diffMinutes < 60 -> if (isEn) "${diffMinutes}m ago" else "$diffMinutes dk önce"
                        diffHours < 24 -> if (isEn) "${diffHours}h ago" else "$diffHours sa önce"
                        diffDays < 30 -> if (isEn) "${diffDays}d ago" else "$diffDays gün önce"
                        else -> if (isEn) "${diffDays / 30}mo ago" else "${diffDays / 30} ay önce"
                    }
                } else {
                    val defaultTime = if (isEn) "Just now" else "Şimdi"
                    val fallback = widgetData.getString("drawing_time_ago", defaultTime) ?: defaultTime
                    if (fallback.contains("dk önce") || fallback == "Şimdi" || fallback.contains("m ago") || fallback == "Just now") {
                        if (isEn) "Previous drawing" else "Eski çizim"
                    } else fallback
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

                // Seçili Tema Paketi Renklerini Oku
                val primaryHex = widgetData.getString("widget_color_primary", "#8B5CF6") ?: "#8B5CF6"
                val primaryDarkHex = widgetData.getString("widget_color_primary_dark", "#A78BFA") ?: "#A78BFA"
                val secondaryHex = widgetData.getString("widget_color_secondary", "#34D399") ?: "#34D399"
                val darkBgHex = widgetData.getString("widget_color_dark_bg", "#0C0D12") ?: "#0C0D12"
                val darkSurfaceHex = widgetData.getString("widget_color_dark_surface", "#161820") ?: "#161820"
                val darkTextHex = widgetData.getString("widget_color_dark_text", "#F3F4F6") ?: "#F3F4F6"
                val lightBgHex = widgetData.getString("widget_color_light_bg", "#F8F9FA") ?: "#F8F9FA"
                val lightSurfaceHex = widgetData.getString("widget_color_light_surface", "#FFFFFF") ?: "#FFFFFF"
                val lightTextHex = widgetData.getString("widget_color_text_dark", "#1E2024") ?: "#1E2024"

                val primaryColor = safeParseColor(primaryHex, "#8B5CF6")
                val primaryDarkColor = safeParseColor(primaryDarkHex, "#A78BFA")
                val secondaryColor = safeParseColor(secondaryHex, "#34D399")

                // Placeholder ve buton metinlerini dile göre ayarla
                setTextViewText(R.id.widget_drawing_empty_title, if (isEn) "Live Drawing Canvas" else "Canlı Çizim Tuvali")
                setTextViewText(R.id.widget_drawing_empty_subtitle, if (isEn) "Tap to draw ✨" else "Çizmek için tıkla ✨")
                try {
                    setTextViewText(R.id.widget_drawing_btn_reply_text, if (isEn) "🖌️ Draw" else "🖌️ Çiz")
                } catch (_: Exception) {}

                // Arka plan deseni ve çip stilleri (Seçili Palete Göre Dinamik Çizim)
                val themedBgBitmap = createThemedDrawingBackground(
                    isDark = isDarkTheme,
                    bgColor = safeParseColor(if (isDarkTheme) darkBgHex else lightBgHex, if (isDarkTheme) "#0F0C1B" else "#F8FAFC"),
                    surfaceColor = safeParseColor(if (isDarkTheme) darkSurfaceHex else lightSurfaceHex, if (isDarkTheme) "#18132A" else "#FFFFFF"),
                    primaryColor = if (isDarkTheme) primaryDarkColor else primaryColor,
                    secondaryColor = secondaryColor
                )
                setImageViewBitmap(R.id.widget_drawing_bg_pattern, themedBgBitmap)

                if (isDarkTheme) {
                    setInt(R.id.widget_drawing_badge, "setBackgroundResource", R.drawable.widget_chip_bg)
                    setInt(R.id.widget_drawing_btn_reply, "setBackgroundResource", R.drawable.widget_chip_bg)
                    val textCol = safeParseColor(darkTextHex, "#F3F4F6")
                    setTextColor(R.id.widget_drawing_sender_text, textCol)
                    setTextColor(R.id.widget_drawing_time_text, primaryDarkColor)
                    setTextColor(R.id.widget_drawing_empty_title, textCol)
                    setTextColor(R.id.widget_drawing_empty_subtitle, primaryDarkColor)
                } else {
                    setInt(R.id.widget_drawing_badge, "setBackgroundResource", R.drawable.widget_chip_bg_light)
                    setInt(R.id.widget_drawing_btn_reply, "setBackgroundResource", R.drawable.widget_chip_bg_light)
                    val textCol = safeParseColor(lightTextHex, "#1E1B4B")
                    setTextColor(R.id.widget_drawing_sender_text, textCol)
                    setTextColor(R.id.widget_drawing_time_text, primaryColor)
                    setTextColor(R.id.widget_drawing_empty_title, textCol)
                    setTextColor(R.id.widget_drawing_empty_subtitle, primaryColor)
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
                                val defaultPartner = if (isEn) "Partner" else "Partnerin"
                                val rawDisplay = senderName ?: defaultPartner
                                val isSelf = rawDisplay.equals("sen", ignoreCase = true) || rawDisplay.equals("you", ignoreCase = true)
                                val finalSenderName = if (isSelf) rawDisplay else {
                                    val firstOnly = formatFirstNameOnly(rawDisplay)
                                    if (firstOnly.isNotEmpty()) firstOnly else rawDisplay
                                }
                                setTextViewText(R.id.widget_drawing_sender_text, finalSenderName)
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

    private fun formatFirstNameOnly(rawName: String?): String {
        if (rawName == null) return ""
        val clean = rawName.trim()
        if (clean.isEmpty()) return ""
        if (!clean.contains(" ")) return clean
        val parts = clean.split("\\s+".toRegex()).filter { it.isNotEmpty() }
        if (parts.size <= 1) return clean
        return if (parts.size > 2) {
            parts.subList(0, parts.size - 1).joinToString(" ")
        } else {
            parts[0]
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

    private fun safeParseColor(hex: String, fallbackHex: String): Int {
        return try {
            android.graphics.Color.parseColor(hex)
        } catch (_: Exception) {
            android.graphics.Color.parseColor(fallbackHex)
        }
    }

    private fun withAlpha(color: Int, alpha: Int): Int {
        return (alpha.coerceIn(0, 255) shl 24) or (color and 0x00FFFFFF)
    }

    private fun createThemedDrawingBackground(
        isDark: Boolean,
        bgColor: Int,
        surfaceColor: Int,
        primaryColor: Int,
        secondaryColor: Int
    ): android.graphics.Bitmap {
        val size = 360
        val bitmap = android.graphics.Bitmap.createBitmap(size, size, android.graphics.Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(bitmap)
        val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)
        val radius = 48f
        val rect = android.graphics.RectF(2f, 2f, size - 2f, size - 2f)

        val bgPath = android.graphics.Path().apply {
            addRoundRect(rect, radius, radius, android.graphics.Path.Direction.CW)
        }
        canvas.save()
        canvas.clipPath(bgPath)

        paint.style = android.graphics.Paint.Style.FILL
        paint.shader = android.graphics.RadialGradient(
            size * 0.5f,
            size * 0.5f,
            size * 0.75f,
            intArrayOf(surfaceColor, bgColor),
            floatArrayOf(0f, 1f),
            android.graphics.Shader.TileMode.CLAMP
        )
        canvas.drawRect(0f, 0f, size.toFloat(), size.toFloat(), paint)

        // Sol Üst Primary Aurora
        paint.shader = android.graphics.RadialGradient(
            size * 0.15f,
            size * 0.15f,
            size * 0.55f,
            intArrayOf(withAlpha(primaryColor, if (isDark) 60 else 44), withAlpha(primaryColor, 0)),
            floatArrayOf(0f, 1f),
            android.graphics.Shader.TileMode.CLAMP
        )
        canvas.drawRect(0f, 0f, size.toFloat(), size.toFloat(), paint)

        // Sağ Alt Secondary Aurora
        paint.shader = android.graphics.RadialGradient(
            size * 0.85f,
            size * 0.85f,
            size * 0.55f,
            intArrayOf(withAlpha(secondaryColor, if (isDark) 50 else 36), withAlpha(secondaryColor, 0)),
            floatArrayOf(0f, 1f),
            android.graphics.Shader.TileMode.CLAMP
        )
        canvas.drawRect(0f, 0f, size.toFloat(), size.toFloat(), paint)
        paint.shader = null

        // 3. Eski Sanatsal Çizim Motifleri (Palet, Fırça, Kalem, Kalp, Cetvel, Kılavuz - 200x200 viewport'tan 360x360'a ölçekli)
        canvas.save()
        val scale = size / 200f
        canvas.scale(scale, scale)

        val fillPaint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            style = android.graphics.Paint.Style.FILL
        }
        val strokePaint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            style = android.graphics.Paint.Style.STROKE
            strokeCap = android.graphics.Paint.Cap.ROUND
            strokeJoin = android.graphics.Paint.Join.ROUND
        }

        // Köşe Eskiz Çerçeve Çentikleri (L Şeklinde)
        strokePaint.color = withAlpha(primaryColor, if (isDark) 52 else 45)
        strokePaint.strokeWidth = 1.2f
        val cornerPath = android.graphics.Path().apply {
            moveTo(12f, 20f); lineTo(12f, 12f); lineTo(20f, 12f)
            moveTo(188f, 20f); lineTo(188f, 12f); lineTo(180f, 12f)
            moveTo(12f, 180f); lineTo(12f, 188f); lineTo(20f, 188f)
            moveTo(188f, 180f); lineTo(188f, 188f); lineTo(180f, 188f)
        }
        canvas.drawPath(cornerPath, strokePaint)

        // Ressam Paleti 🎨 (Sol Üst / Orta)
        val palettePath = android.graphics.Path().apply {
            moveTo(44f, 52f)
            cubicTo(54f, 46f, 68f, 52f, 68f, 64f)
            cubicTo(68f, 76f, 60f, 82f, 50f, 82f)
            cubicTo(40f, 82f, 32f, 74f, 32f, 62f)
            cubicTo(32f, 54f, 38f, 48f, 44f, 52f)
            close()
        }
        fillPaint.color = withAlpha(primaryColor, if (isDark) 24 else 20)
        strokePaint.color = withAlpha(primaryColor, if (isDark) 60 else 52)
        strokePaint.strokeWidth = 1.0f
        canvas.drawPath(palettePath, fillPaint)
        canvas.drawPath(palettePath, strokePaint)

        // Palet Başparmak Deliği & Renk Noktaları
        fillPaint.color = bgColor
        strokePaint.strokeWidth = 0.8f
        canvas.drawCircle(40f, 68f, 3f, fillPaint)
        canvas.drawCircle(40f, 68f, 3f, strokePaint)

        fillPaint.color = withAlpha(secondaryColor, 75)
        canvas.drawCircle(46f, 56f, 1.8f, fillPaint)
        fillPaint.color = withAlpha(primaryColor, 75)
        canvas.drawCircle(56f, 58f, 1.8f, fillPaint)
        fillPaint.color = withAlpha(secondaryColor, 65)
        canvas.drawCircle(60f, 68f, 1.8f, fillPaint)

        // Ressam Fırçası 🖌️ (Sağ Üst)
        val brushPath = android.graphics.Path().apply {
            moveTo(168f, 36f)
            lineTo(150f, 54f)
            lineTo(146f, 56f)
            lineTo(144f, 62f)
            lineTo(140f, 64f)
            lineTo(142f, 60f)
            lineTo(144f, 58f)
            lineTo(148f, 54f)
            lineTo(166f, 34f)
            close()
        }
        fillPaint.color = withAlpha(primaryColor, if (isDark) 26 else 22)
        strokePaint.color = withAlpha(primaryColor, if (isDark) 62 else 55)
        strokePaint.strokeWidth = 1.0f
        canvas.drawPath(brushPath, fillPaint)
        canvas.drawPath(brushPath, strokePaint)
        fillPaint.color = withAlpha(secondaryColor, if (isDark) 55 else 48)
        canvas.drawCircle(136f, 69f, 2.2f, fillPaint)

        // Kurşun Kalem ✏️ (Sağ Alt)
        val pencilPath = android.graphics.Path().apply {
            moveTo(160f, 130f)
            lineTo(144f, 146f)
            lineTo(138f, 154f)
            lineTo(138f, 150f)
            lineTo(146f, 142f)
            lineTo(162f, 126f)
            close()
        }
        fillPaint.color = withAlpha(secondaryColor, if (isDark) 24 else 20)
        strokePaint.color = withAlpha(secondaryColor, if (isDark) 58 else 50)
        strokePaint.strokeWidth = 0.9f
        canvas.drawPath(pencilPath, fillPaint)
        canvas.drawPath(pencilPath, strokePaint)

        // Akıcı Dalgalı Fırça Darbesi ~ (Alt Orta)
        val wavePath = android.graphics.Path().apply {
            moveTo(50f, 158f)
            cubicTo(70f, 148f, 85f, 168f, 105f, 158f)
            cubicTo(120f, 150f, 135f, 162f, 150f, 154f)
        }
        strokePaint.color = withAlpha(primaryColor, if (isDark) 50 else 44)
        strokePaint.strokeWidth = 1.1f
        canvas.drawPath(wavePath, strokePaint)

        // Cetvel Çizgileri 📐 (Sol Alt)
        val rulerPath = android.graphics.Path().apply {
            moveTo(30f, 120f); lineTo(30f, 140f)
            moveTo(30f, 120f); lineTo(35f, 120f)
            moveTo(30f, 125f); lineTo(33f, 125f)
            moveTo(30f, 130f); lineTo(35f, 130f)
            moveTo(30f, 135f); lineTo(33f, 135f)
            moveTo(30f, 140f); lineTo(35f, 140f)
        }
        strokePaint.color = withAlpha(primaryColor, if (isDark) 44 else 38)
        strokePaint.strokeWidth = 0.8f
        canvas.drawPath(rulerPath, strokePaint)

        // Çizilmiş Romantik Kalp Eskizi (Merkez Sol)
        val sketchHeart = android.graphics.Path().apply {
            moveTo(85f, 78f)
            cubicTo(80f, 72f, 72f, 74f, 70f, 82f)
            cubicTo(68f, 90f, 85f, 102f, 85f, 102f)
            cubicTo(85f, 102f, 102f, 90f, 100f, 82f)
            cubicTo(98f, 74f, 90f, 72f, 85f, 78f)
            close()
        }
        fillPaint.color = withAlpha(primaryColor, if (isDark) 20 else 16)
        strokePaint.color = withAlpha(primaryColor, if (isDark) 52 else 45)
        strokePaint.strokeWidth = 1.0f
        canvas.drawPath(sketchHeart, fillPaint)
        canvas.drawPath(sketchHeart, strokePaint)

        // Işıltı Yıldızı ✦
        val starPath = android.graphics.Path().apply {
            moveTo(115f, 45f)
            quadTo(115f, 51f, 121f, 51f)
            quadTo(115f, 51f, 115f, 57f)
            quadTo(115f, 51f, 109f, 51f)
            quadTo(115f, 51f, 115f, 45f)
            close()
        }
        fillPaint.color = withAlpha(secondaryColor, if (isDark) 36 else 30)
        strokePaint.color = withAlpha(secondaryColor, if (isDark) 62 else 52)
        strokePaint.strokeWidth = 0.8f
        canvas.drawPath(starPath, fillPaint)
        canvas.drawPath(starPath, strokePaint)

        // Minik Sanatsal Boya Sıçramaları
        fillPaint.color = withAlpha(primaryColor, if (isDark) 50 else 42)
        canvas.drawCircle(96f, 128f, 1.4f, fillPaint)
        canvas.drawCircle(156f, 92f, 1.2f, fillPaint)
        canvas.drawCircle(65f, 108f, 1.0f, fillPaint)
        canvas.drawCircle(126f, 116f, 1.2f, fillPaint)
        canvas.drawCircle(80f, 48f, 1.5f, fillPaint)
        canvas.drawCircle(168f, 162f, 1.2f, fillPaint)

        canvas.restore()

        canvas.restore()

        // Dış Çerçeve
        paint.style = android.graphics.Paint.Style.STROKE
        paint.strokeWidth = 3f
        paint.color = withAlpha(primaryColor, if (isDark) 95 else 75)
        canvas.drawRoundRect(rect, radius, radius, paint)

        return bitmap
    }
}
