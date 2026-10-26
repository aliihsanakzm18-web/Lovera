package com.lovera.app.lovera

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

class LoveraPartnerWidgetProvider : HomeWidgetProvider() {

    companion object {
        private const val ACTION_AUTO_TICK = "com.lovera.app.lovera.PARTNER_WIDGET_TICK"
        private const val TICK_INTERVAL_MS = 60000L // Her 60 saniyede bir widget süresini güncelle
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_AUTO_TICK) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val thisWidget = ComponentName(context, LoveraPartnerWidgetProvider::class.java)
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
            val tickIntent = Intent(context, LoveraPartnerWidgetProvider::class.java).apply {
                action = ACTION_AUTO_TICK
                setPackage(context.packageName)
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                1001,
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
            val tickIntent = Intent(context, LoveraPartnerWidgetProvider::class.java).apply {
                action = ACTION_AUTO_TICK
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                1001,
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
            val views = RemoteViews(context.packageName, R.layout.lovera_partner_widget).apply {
                // Tema Tespiti (Koyu / Açık) - Varsayılan koyu gece teması
                val widgetTheme = widgetData.getString("widget_theme", "dark") ?: "dark"
                val isDarkTheme = when (widgetTheme) {
                    "light" -> false
                    "dark" -> true
                    else -> {
                        // "system" veya başka değer gelirse telefonun gece modunu kontrol et, yoksa varsayılan koyu (true)
                        val nightModeFlags = context.resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK
                        nightModeFlags != android.content.res.Configuration.UI_MODE_NIGHT_NO
                    }
                }

                // Seçili Tema Paketi Renklerini Oku (Yoksa Lovera Klasik varsayılanları)
                val primaryHex = widgetData.getString("widget_color_primary", "#8B5CF6") ?: "#8B5CF6"
                val primaryDarkHex = widgetData.getString("widget_color_primary_dark", "#A78BFA") ?: "#A78BFA"
                val primaryDeepHex = widgetData.getString("widget_color_primary_deep", "#7C3AED") ?: "#7C3AED"
                val secondaryHex = widgetData.getString("widget_color_secondary", "#34D399") ?: "#34D399"
                val darkBgHex = widgetData.getString("widget_color_dark_bg", "#0C0D12") ?: "#0C0D12"
                val darkSurfaceHex = widgetData.getString("widget_color_dark_surface", "#161820") ?: "#161820"
                val darkTextHex = widgetData.getString("widget_color_dark_text", "#F3F4F6") ?: "#F3F4F6"
                val darkMutedHex = widgetData.getString("widget_color_dark_text_muted", "#94A3B8") ?: "#94A3B8"
                val lightBgHex = widgetData.getString("widget_color_light_bg", "#F8F9FA") ?: "#F8F9FA"
                val lightSurfaceHex = widgetData.getString("widget_color_light_surface", "#FFFFFF") ?: "#FFFFFF"
                val lightTextHex = widgetData.getString("widget_color_text_dark", "#1E2024") ?: "#1E2024"
                val lightMutedHex = widgetData.getString("widget_color_text_muted", "#6C757D") ?: "#6C757D"

                val primaryColor = safeParseColor(primaryHex, "#8B5CF6")
                val primaryDarkColor = safeParseColor(primaryDarkHex, "#A78BFA")
                val primaryDeepColor = safeParseColor(primaryDeepHex, "#7C3AED")
                val secondaryColor = safeParseColor(secondaryHex, "#34D399")

                // 0. Tema Arka Plan Deseni (Seçili Palete Göre Dinamik Çizim) ve Çip Stilleri
                val themedBgBitmap = createThemedPartnerBackground(
                    context = context,
                    isDark = isDarkTheme,
                    bgColor = safeParseColor(if (isDarkTheme) darkBgHex else lightBgHex, if (isDarkTheme) "#0F0C1B" else "#F8FAFC"),
                    surfaceColor = safeParseColor(if (isDarkTheme) darkSurfaceHex else lightSurfaceHex, if (isDarkTheme) "#18132A" else "#FFFFFF"),
                    primaryColor = if (isDarkTheme) primaryDarkColor else primaryColor,
                    secondaryColor = secondaryColor
                )
                setImageViewBitmap(R.id.widget_bg_pattern, themedBgBitmap)

                if (isDarkTheme) {
                    setInt(R.id.widget_partner_chip, "setBackgroundResource", R.drawable.widget_chip_bg)
                    setInt(R.id.widget_counter_chip, "setBackgroundResource", R.drawable.widget_counter_bg)
                    setInt(R.id.widget_last_seen, "setBackgroundResource", R.drawable.widget_chip_bg)
                    setInt(R.id.widget_battery_chip, "setBackgroundResource", R.drawable.widget_chip_bg)
                    setInt(R.id.widget_status_chip, "setBackgroundResource", R.drawable.widget_chip_bg)
                    val textCol = safeParseColor(darkTextHex, "#F3F4F6")
                    val mutedCol = safeParseColor(darkMutedHex, "#E2E8F0")
                    setTextColor(R.id.widget_partner_heart, primaryDarkColor)
                    setTextColor(R.id.widget_partner_name, textCol)
                    setTextColor(R.id.widget_status_text, textCol)
                    setTextColor(R.id.widget_counter_label, mutedCol)
                } else {
                    setInt(R.id.widget_partner_chip, "setBackgroundResource", R.drawable.widget_chip_bg_light)
                    setInt(R.id.widget_counter_chip, "setBackgroundResource", R.drawable.widget_chip_bg_light)
                    setInt(R.id.widget_last_seen, "setBackgroundResource", R.drawable.widget_chip_bg_light)
                    setInt(R.id.widget_battery_chip, "setBackgroundResource", R.drawable.widget_chip_bg_light)
                    setInt(R.id.widget_status_chip, "setBackgroundResource", R.drawable.widget_chip_bg_light)
                    val textCol = safeParseColor(lightTextHex, "#1E1B4B")
                    val mutedCol = safeParseColor(lightMutedHex, "#4B5563")
                    setTextColor(R.id.widget_partner_heart, primaryColor)
                    setTextColor(R.id.widget_partner_name, textCol)
                    setTextColor(R.id.widget_status_text, textCol)
                    setTextColor(R.id.widget_counter_label, mutedCol)
                }

                // 0.1 Arka Plan Fotoğrafı & Kenardan Ortaya Karanlık (Vignette) Efekti
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

                val isEn = widgetData.getString("app_language", "tr") == "en"

                // 1. Partner İsmi
                val defaultPartner = if (isEn) "Partner" else "Partnerin"
                val partnerName = widgetData.getString("partner_name", defaultPartner) ?: defaultPartner
                setTextViewText(R.id.widget_partner_name, partnerName)

                // 2. Aşk Sayacı (Gün Sayısı ve Etiketi)
                val daysCount = widgetData.getString("days_count", "0") ?: "0"
                setTextViewText(R.id.widget_days_count, daysCount)
                setTextViewText(R.id.widget_counter_label, if (isEn) (if (daysCount == "1") "day" else "days") else "gün")
                setTextColor(R.id.widget_days_count, if (isDarkTheme) primaryDarkColor else primaryDeepColor)

                // 3. Batarya Seviyesi ve Rengi (Azaldıkça seviyesi ve rengi dinamik değişir)
                val batteryLevel = widgetData.getString("battery_level", "%--") ?: "%--"
                setTextViewText(R.id.widget_battery_text, batteryLevel)
                val numericBat = batteryLevel.replace("%", "").trim().toIntOrNull()
                val batteryColor = when {
                    numericBat == null -> android.graphics.Color.parseColor(if (isDarkTheme) "#34D399" else "#059669")
                    numericBat >= 50 -> android.graphics.Color.parseColor(if (isDarkTheme) "#34D399" else "#059669") // Yeşil
                    numericBat >= 20 -> android.graphics.Color.parseColor(if (isDarkTheme) "#FBBF24" else "#D97706") // Sarı / Turuncu
                    else -> android.graphics.Color.parseColor("#EF4444") // Kritik Kırmızı
                }
                setTextColor(R.id.widget_battery_text, batteryColor)

                // Şarj doluluk oranına göre dikey batarya görseli çiz ve aktar
                val batteryBitmap = createBatteryBitmap(context, numericBat ?: 100, batteryColor)
                setImageViewBitmap(R.id.widget_battery_icon, batteryBitmap)

                // 4. Durum: Evde / Dışarıda / Yürüyor / Arabada
                val defaultStatus = if (isEn) "Outdoors" else "Dışarıda"
                val rawStatus = widgetData.getString("status_text", defaultStatus) ?: defaultStatus
                val statusText = if (isEn) {
                    when (rawStatus) {
                        "Dışarıda" -> "Outdoors"
                        "Yürüyor" -> "Walking"
                        "Arabada" -> "Driving"
                        "Bağlantı bekleniyor" -> "Waiting for connection"
                        "Evim", "Ev" -> "Home"
                        "İş / Ofis", "İş Yeri", "Ofis" -> "Work"
                        else -> rawStatus
                    }
                } else rawStatus
                val statusEmoji = widgetData.getString("status_emoji", "📍") ?: "📍"
                setTextViewText(R.id.widget_status_text, statusText)
                setTextViewText(R.id.widget_status_emoji, statusEmoji)

                // 5. Son Görülme / Durum zamanı (Sistem saati ile gerçek zamanlı dinamik hesaplanır)
                val lastActiveMillis: Long = try {
                    widgetData.getLong("last_active_millis", 0L)
                } catch (_: Exception) {
                    try {
                        widgetData.getInt("last_active_millis", 0).toLong()
                    } catch (_: Exception) {
                        widgetData.getString("last_active_millis", "0")?.toLongOrNull() ?: 0L
                    }
                }
                val isPartnerAppOpen = widgetData.getBoolean("partner_is_app_open", false)
                val lastSeen: String = if (lastActiveMillis > 0) {
                    val diffMillis = System.currentTimeMillis() - lastActiveMillis
                    val diffMinutes = (diffMillis / 60000).toInt()
                    val diffHours = (diffMinutes / 60)
                    val diffDays = (diffHours / 24)

                    when {
                        isPartnerAppOpen && diffMinutes < 3 -> if (isEn) "Active now" else "Şimdi aktif"
                        diffMinutes < 1 -> if (isEn) "Just now" else "Şimdi"
                        diffMinutes == 1 -> if (isEn) "1m ago" else "1 dk önce"
                        diffMinutes < 60 -> if (isEn) "${diffMinutes}m ago" else "$diffMinutes dk önce"
                        diffHours < 24 -> if (isEn) "${diffHours}h ago" else "$diffHours sa önce"
                        diffDays < 30 -> if (isEn) "${diffDays}d ago" else "$diffDays gün önce"
                        else -> if (isEn) "${diffDays / 30}mo ago" else "${diffDays / 30} ay önce"
                    }
                } else {
                    val defaultOffline = if (isEn) "Offline" else "Çevrimdışı"
                    val fallback = widgetData.getString("last_seen", defaultOffline) ?: defaultOffline
                    if (fallback == "1 dk önce" || fallback == "Şimdi aktif" || fallback == "1m ago" || fallback == "Active now") defaultOffline else fallback
                }

                setTextViewText(R.id.widget_last_seen, lastSeen)
                if (lastSeen.contains("Şimdi aktif") || lastSeen.contains("Canlı") || lastSeen.contains("Active now") || lastSeen.contains("Live")) {
                    setTextColor(R.id.widget_last_seen, android.graphics.Color.parseColor(if (isDarkTheme) "#34D399" else "#059669")) // Canlı Zümrüt Yeşili
                } else {
                    setTextColor(R.id.widget_last_seen, android.graphics.Color.parseColor(if (isDarkTheme) "#E2E8F0" else "#475569")) // Net, Okunaklı Slate / Gri
                }

                // 6. Partnerden Gelen Mesaj Bildirim Baloncukları Yığını
                val unreadCount = widgetData.getInt("widget_unread_count", 0)
                val msg1 = widgetData.getString("widget_msg_1", "") ?: ""
                val msg2 = widgetData.getString("widget_msg_2", "") ?: ""
                val msg3 = widgetData.getString("widget_msg_3", "") ?: ""

                if (unreadCount > 0 && (msg1.isNotEmpty() || msg2.isNotEmpty() || msg3.isNotEmpty())) {
                    setViewVisibility(R.id.widget_message_container, View.VISIBLE)

                    val bubbleBg = if (isDarkTheme) R.drawable.widget_message_bubble_bg else R.drawable.widget_message_bubble_bg_light
                    val msg3Color = if (isDarkTheme) "#FFFFFF" else "#1E1B4B"
                    val msg2Color = if (isDarkTheme) "#E2E8F0" else "#334155"
                    val msg1Color = if (isDarkTheme) "#B3DDD6FE" else "#64748B"

                    // 1. En eski mesaj balonu
                    if (msg1.isNotEmpty()) {
                        setInt(R.id.widget_msg_bubble_1, "setBackgroundResource", bubbleBg)
                        setTextViewText(R.id.widget_msg_text_1, msg1)
                        setTextColor(R.id.widget_msg_text_1, android.graphics.Color.parseColor(msg1Color))
                        setViewVisibility(R.id.widget_msg_bubble_1, View.VISIBLE)
                    } else {
                        setViewVisibility(R.id.widget_msg_bubble_1, View.GONE)
                    }

                    // 2. Orta mesaj balonu
                    if (msg2.isNotEmpty()) {
                        setInt(R.id.widget_msg_bubble_2, "setBackgroundResource", bubbleBg)
                        setTextViewText(R.id.widget_msg_text_2, msg2)
                        setTextColor(R.id.widget_msg_text_2, android.graphics.Color.parseColor(msg2Color))
                        setViewVisibility(R.id.widget_msg_bubble_2, View.VISIBLE)
                    } else {
                        setViewVisibility(R.id.widget_msg_bubble_2, View.GONE)
                    }

                    // 3. En yeni mesaj balonu
                    if (msg3.isNotEmpty()) {
                        setInt(R.id.widget_msg_bubble_3, "setBackgroundResource", bubbleBg)
                        setTextViewText(R.id.widget_msg_text_3, msg3)
                        setTextColor(R.id.widget_msg_text_3, android.graphics.Color.parseColor(msg3Color))
                        setViewVisibility(R.id.widget_msg_bubble_3, View.VISIBLE)
                        if (unreadCount > 3) {
                            setTextViewText(R.id.widget_msg_badge_more, "+${unreadCount - 3}")
                            setViewVisibility(R.id.widget_msg_badge_more, View.VISIBLE)
                        } else {
                            setViewVisibility(R.id.widget_msg_badge_more, View.GONE)
                        }
                    } else {
                        setViewVisibility(R.id.widget_msg_bubble_3, View.GONE)
                    }
                } else {
                    setViewVisibility(R.id.widget_message_container, View.GONE)
                }

                // Widget'a dokunulduğunda: Mesaj varsa sohbete, yoksa ana ekrana yönlendir
                val targetUri = if (unreadCount > 0) "lovera://open_chat" else "lovera://open_dashboard"
                val clickIntent = es.antonborri.home_widget.HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    android.net.Uri.parse(targetUri)
                )
                setOnClickPendingIntent(R.id.widget_root, clickIntent)
                setOnClickPendingIntent(R.id.widget_message_container, clickIntent)
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

    private fun createThemedPartnerBackground(
        context: Context,
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

        // 1. Zemin Degrade
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

        // 2. Sol Üst Primary Aurora Işıltısı
        paint.shader = android.graphics.RadialGradient(
            size * 0.15f,
            size * 0.15f,
            size * 0.55f,
            intArrayOf(withAlpha(primaryColor, if (isDark) 64 else 48), withAlpha(primaryColor, 0)),
            floatArrayOf(0f, 1f),
            android.graphics.Shader.TileMode.CLAMP
        )
        canvas.drawRect(0f, 0f, size.toFloat(), size.toFloat(), paint)

        // 3. Sağ Alt Secondary Aurora Işıltısı
        paint.shader = android.graphics.RadialGradient(
            size * 0.85f,
            size * 0.85f,
            size * 0.55f,
            intArrayOf(withAlpha(secondaryColor, if (isDark) 54 else 40), withAlpha(secondaryColor, 0)),
            floatArrayOf(0f, 1f),
            android.graphics.Shader.TileMode.CLAMP
        )
        canvas.drawRect(0f, 0f, size.toFloat(), size.toFloat(), paint)
        paint.shader = null

        // 4. Eski Romantik Doodle & Kozmik Vektör Süslemeleri (200x200 viewport'tan 360x360'a ölçekli)
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

        // Kalp 1 (Sol Üst)
        val heartPath = android.graphics.Path().apply {
            moveTo(46f, 62f)
            cubicTo(40f, 54f, 30f, 56f, 28f, 66f)
            cubicTo(26f, 76f, 46f, 90f, 46f, 90f)
            cubicTo(46f, 90f, 66f, 76f, 64f, 66f)
            cubicTo(62f, 56f, 52f, 54f, 46f, 62f)
            close()
        }
        fillPaint.color = withAlpha(primaryColor, if (isDark) 28 else 24)
        strokePaint.color = withAlpha(primaryColor, if (isDark) 55 else 48)
        strokePaint.strokeWidth = 1.1f
        canvas.drawPath(heartPath, fillPaint)
        canvas.drawPath(heartPath, strokePaint)

        // 4 Köşeli Parlak Yıldız ✦ (Sağ Üst)
        val starPath = android.graphics.Path().apply {
            moveTo(152f, 48f)
            quadTo(152f, 56f, 160f, 56f)
            quadTo(152f, 56f, 152f, 64f)
            quadTo(152f, 56f, 144f, 56f)
            quadTo(152f, 56f, 152f, 48f)
            close()
        }
        fillPaint.color = withAlpha(secondaryColor, if (isDark) 36 else 30)
        strokePaint.color = withAlpha(secondaryColor, if (isDark) 65 else 55)
        strokePaint.strokeWidth = 0.9f
        canvas.drawPath(starPath, fillPaint)
        canvas.drawPath(starPath, strokePaint)

        // Hilal Ay 🌙 (Sol Orta/Alt)
        val moonPath = android.graphics.Path().apply {
            moveTo(38f, 124f)
            cubicTo(44f, 124f, 50f, 129f, 50f, 136f)
            cubicTo(50f, 143f, 44f, 148f, 38f, 148f)
            cubicTo(42f, 146f, 45f, 141f, 45f, 136f)
            cubicTo(45f, 131f, 42f, 126f, 38f, 124f)
            close()
        }
        fillPaint.color = withAlpha(primaryColor, if (isDark) 28 else 24)
        strokePaint.color = withAlpha(primaryColor, if (isDark) 52 else 45)
        strokePaint.strokeWidth = 0.9f
        canvas.drawPath(moonPath, fillPaint)
        canvas.drawPath(moonPath, strokePaint)

        // Mektup Zarfı ✉️ (Merkez Sağ)
        val envPath = android.graphics.Path().apply {
            addRect(142f, 106f, 168f, 124f, android.graphics.Path.Direction.CW)
            moveTo(142f, 106f)
            lineTo(155f, 116f)
            lineTo(168f, 106f)
        }
        fillPaint.color = withAlpha(primaryColor, if (isDark) 16 else 14)
        strokePaint.color = withAlpha(primaryColor, if (isDark) 48 else 42)
        strokePaint.strokeWidth = 1.0f
        canvas.drawRect(142f, 106f, 168f, 124f, fillPaint)
        canvas.drawPath(envPath, strokePaint)

        // Sonsuzluk Sembolü ∞ (Sağ Alt)
        val infPath = android.graphics.Path().apply {
            moveTo(132f, 156f)
            cubicTo(127f, 151f, 120f, 151f, 115f, 156f)
            cubicTo(110f, 161f, 117f, 166f, 122f, 161f)
            cubicTo(127f, 156f, 134f, 151f, 139f, 156f)
            cubicTo(144f, 161f, 137f, 166f, 132f, 161f)
            close()
        }
        strokePaint.color = withAlpha(secondaryColor, if (isDark) 52 else 45)
        strokePaint.strokeWidth = 1.0f
        canvas.drawPath(infPath, strokePaint)

        // Yörüngeli Halka 🪐 (Sol Merkez)
        fillPaint.color = withAlpha(primaryColor, if (isDark) 22 else 18)
        strokePaint.color = withAlpha(primaryColor, if (isDark) 45 else 38)
        strokePaint.strokeWidth = 0.9f
        canvas.drawCircle(48f, 100f, 7f, fillPaint)
        canvas.drawCircle(48f, 100f, 7f, strokePaint)
        val orbitPath = android.graphics.Path().apply {
            moveTo(36f, 102f)
            quadTo(48f, 96f, 60f, 102f)
            quadTo(48f, 108f, 36f, 102f)
        }
        strokePaint.color = withAlpha(secondaryColor, if (isDark) 48 else 40)
        strokePaint.strokeWidth = 0.8f
        canvas.drawPath(orbitPath, strokePaint)

        // Minik Parıltı Noktaları & Yıldız Tozu
        fillPaint.color = withAlpha(primaryColor, if (isDark) 50 else 42)
        canvas.drawCircle(98f, 46f, 1.3f, fillPaint)
        canvas.drawCircle(106f, 146f, 1.3f, fillPaint)
        canvas.drawCircle(86f, 112f, 1.6f, fillPaint)
        canvas.drawCircle(122f, 82f, 1.1f, fillPaint)
        canvas.drawCircle(166f, 142f, 1.3f, fillPaint)
        canvas.drawCircle(32f, 86f, 1.1f, fillPaint)

        canvas.restore()

        canvas.restore()

        // 5. Dış Çerçeve (Stroke)
        paint.style = android.graphics.Paint.Style.STROKE
        paint.strokeWidth = 3f
        paint.color = withAlpha(primaryColor, if (isDark) 95 else 75)
        canvas.drawRoundRect(rect, radius, radius, paint)

        return bitmap
    }
}
