package kr.jamgltime.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat

/**
 * 앱 차단 포그라운드 서비스.
 * 접근성(Accessibility) 없이 '앱 사용 데이터(Usage Stats)' + '다른 앱 위에 표시(Overlay)'만 사용.
 * - 포그라운드 앱 감지: UsageStatsManager
 * - 홈으로 보내기: Intent.ACTION_MAIN + CATEGORY_HOME
 */
class AppBlockerService : Service() {

    private var blockedApps: MutableMap<String, Long> = mutableMapOf()
    private var lastPackage = ""
    private var lastBlockedPackage = ""
    private val handler = Handler(Looper.getMainLooper())
    private var checkTimer: Runnable? = null
    private var foregroundCheckTimer: Runnable? = null
    private var overlayView: View? = null
    private var phoneLockOverlayView: View? = null  // 폰 잠금용 전체 화면 오버레이
    private var windowManager: WindowManager? = null
    private var phoneLockEndTimeMillis: Long = 0L
    private var phoneLockStartTimeMillis: Long = 0L
    private var phoneLockTotalMillis: Long = 0L
    private var phoneLockCountdown: Runnable? = null
    private var phoneLockGuardTimer: Runnable? = null

    private var screenReceiver: android.content.BroadcastReceiver? = null
    private var isScreenOn = true

    companion object {
        private const val NOTIFICATION_ID_UNLOCK = 1003
        private const val NOTIFICATION_ID_PHONE_LOCK = 1002
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "app_blocker_channel"
        private const val CHANNEL_ID_HIGH = "app_blocker_channel_high"
        private const val PREFS_NAME = "app_blocker_prefs"
        private const val KEY_BLOCKED_APPS = "blocked_apps_json"
        private const val FOREGROUND_CHECK_INTERVAL_MS = 500L  // 0.5초마다 체크 (반응성 및 배터리 균형)
    }

    override fun onBind(intent: Intent?): IBinder? = null  // Started 서비스만 사용

    override fun onCreate() {
        super.onCreate()
        println("=== AppBlockerService 생성 (접근성 없음, Usage Stats 사용) ===")
        restoreBlockedApps()

        // 화면 상태 감지 리시버 등록
        val filter = android.content.IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
        }
        screenReceiver = object : android.content.BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    Intent.ACTION_SCREEN_OFF -> {
                        isScreenOn = false
                        stopForegroundCheckTimer()
                    }
                    Intent.ACTION_SCREEN_ON -> {
                        isScreenOn = true
                        if (blockedApps.isNotEmpty()) startForegroundCheckTimer()
                    }
                }
            }
        }
        registerReceiver(screenReceiver, filter)

        if (blockedApps.isNotEmpty()) {
            startForegroundIfNeeded()
            startForegroundCheckTimer()
        }
    }

    private fun saveBlockedApps() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val json = blockedApps.entries.joinToString(",") { "${it.key}:${it.value}" }
        prefs.edit().putString(KEY_BLOCKED_APPS, json).apply()
        println("차단 목록 저장: $json")
    }

    private fun restoreBlockedApps() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val json = prefs.getString(KEY_BLOCKED_APPS, "") ?: ""
        if (json.isEmpty()) {
            println("복원할 차단 목록 없음")
            return
        }
        blockedApps.clear()
        json.split(",").forEach { entry ->
            val parts = entry.split(":")
            if (parts.size == 2) {
                val pkg = parts[0]
                val time = parts[1].toLongOrNull() ?: 0L
                blockedApps[pkg] = time
            }
        }
        println("=== 차단 목록 복원됨: ${blockedApps.size}개 ===")
        val now = System.currentTimeMillis()
        val expiredApps = blockedApps.filter { it.value <= now }
        expiredApps.keys.forEach { blockedApps.remove(it) }
        if (expiredApps.isNotEmpty()) {
            saveBlockedApps()
        }
        if (blockedApps.isNotEmpty()) {
            startAutoUnlockTimer()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val isBootRestore = intent?.getBooleanExtra("isBootRestore", false) ?: false
        val isScheduledLock = intent?.action == "kr.jamgltime.app.SCHEDULED_LOCK"
        val isPhoneLock = intent?.action == "kr.jamgltime.app.PHONE_LOCK"

        if (isPhoneLock) {
            println("=== 폰 잠금 시작 (전체 화면 오버레이) ===")
            val durationMinutes = intent?.getIntExtra("durationMinutes", 15) ?: 15
            phoneLockStartTimeMillis = System.currentTimeMillis()
            phoneLockTotalMillis = durationMinutes * 60 * 1000L
            phoneLockEndTimeMillis = phoneLockStartTimeMillis + phoneLockTotalMillis
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                startForeground(NOTIFICATION_ID_PHONE_LOCK, createPhoneLockNotification(), android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(NOTIFICATION_ID_PHONE_LOCK, createPhoneLockNotification())
            }
            handler.post { showPhoneLockOverlay() }
            startPhoneLockCountdown()
            startPhoneLockGuard()
            return START_STICKY
        }
        if (isScheduledLock) {
            println("=== 예약 잠금 신호 수신 (AlarmManager) ===")
            val packageName = intent?.getStringExtra("packageName") ?: ""
            val durationMinutes = intent?.getIntExtra("durationMinutes", 30) ?: 30
            if (packageName.isNotEmpty()) {
                val unlockTimeMillis = System.currentTimeMillis() + (durationMinutes * 60 * 1000)
                blockedApps[packageName] = unlockTimeMillis
                saveBlockedApps()
                startAutoUnlockTimer()
                startForegroundCheckTimer()
                updateNotification(getNotificationContentText())
                startForegroundIfNeeded()
            }
        } else if (!isBootRestore && intent != null) {
            val packages = intent.getStringArrayListExtra("blockedApps") ?: emptyList()
            val unlockTimes = intent.getStringArrayListExtra("unlockTimes") ?: emptyList()
            blockedApps.clear()
            packages.forEachIndexed { index, packageName ->
                val unlockTime = unlockTimes.getOrNull(index)?.toLongOrNull() ?: 0L
                blockedApps[packageName] = unlockTime
            }
            saveBlockedApps()
            startAutoUnlockTimer()
            if (blockedApps.isNotEmpty()) {
                startForegroundCheckTimer()
                updateNotification(getNotificationContentText())
                startForegroundIfNeeded()
            } else {
                // 빈 목록이 전달되면 서비스 종료
                println("빈 차단 목록 수신: 서비스 종료")
                // ANR 방지를 위해 잠시 startForeground 호출 후 종료
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForeground(NOTIFICATION_ID, createNotification())
                } else {
                    startForeground(NOTIFICATION_ID, createNotification())
                }
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopAutoUnlockTimer()
                stopForegroundCheckTimer()
                lastPackage = ""
                stopSelf()
                return START_NOT_STICKY
            }
        }

        // BootRestore 등의 경우로 진입했으나 차단 목록이 비어있는 경우 안전하게 종료
        if (blockedApps.isEmpty()) {
            println("차단 목록 없음: 서비스 안전 종료")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForeground(NOTIFICATION_ID, createNotification())
            } else {
                startForeground(NOTIFICATION_ID, createNotification())
            }
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        return START_STICKY
    }

    private fun startForegroundIfNeeded() {
        if (blockedApps.isNotEmpty()) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                startForeground(
                    NOTIFICATION_ID,
                    createNotification(),
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                )
            } else {
                startForeground(NOTIFICATION_ID, createNotification())
            }
        }
    }

    private fun startAutoUnlockTimer() {
        stopAutoUnlockTimer()
        checkTimer = object : Runnable {
            override fun run() {
                val now = System.currentTimeMillis()
                val expiredApps = blockedApps.filter { (_, unlockTime) -> now >= unlockTime }
                if (expiredApps.isNotEmpty()) {
                    val appNames = expiredApps.keys.joinToString(", ") { getAppName(it) }
                    showUnlockNotification(getString(R.string.unlock_complete_title), getString(R.string.unlock_complete_msg_format, appNames, expiredApps.size))
                    
                    expiredApps.keys.forEach { blockedApps.remove(it) }
                    saveBlockedApps()
                    if (blockedApps.isEmpty()) {
                        stopForeground(STOP_FOREGROUND_REMOVE)
                        stopAutoUnlockTimer()
                        stopForegroundCheckTimer()
                    } else {
                        updateNotification(getNotificationContentText())
                    }
                }
                if (blockedApps.isNotEmpty()) handler.postDelayed(this, 1000)
            }
        }
        handler.post(checkTimer!!)
    }

    private fun startForegroundCheckTimer() {
        stopForegroundCheckTimer()
        foregroundCheckTimer = object : Runnable {
            override fun run() {
                if (blockedApps.isNotEmpty()) checkAndBlockForegroundApp()
                if (blockedApps.isNotEmpty()) {
                    handler.postDelayed(this, FOREGROUND_CHECK_INTERVAL_MS)
                }
            }
        }
        handler.post(foregroundCheckTimer!!)
    }

    private fun stopForegroundCheckTimer() {
        foregroundCheckTimer?.let {
            handler.removeCallbacks(it)
            foregroundCheckTimer = null
        }
    }

    /** UsageStatsManager로 현재 포그라운드 앱 패키지명 반환 (접근성 미사용) */
    private fun getForegroundAppViaUsageStats(): String {
        return try {
            val now = System.currentTimeMillis()
            val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as android.app.usage.UsageStatsManager
            
            // queryEvents 사용 (이벤트 기반으로 더 정확하고 빠른 감지)
            val events = usageStatsManager.queryEvents(now - 1000 * 60, now) // 최근 1분
            val event = android.app.usage.UsageEvents.Event()
            var lastPackage = ""
            var lastTimeStamp = 0L
            
            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                if (event.eventType == android.app.usage.UsageEvents.Event.MOVE_TO_FOREGROUND) {
                    if (event.timeStamp > lastTimeStamp) {
                        lastTimeStamp = event.timeStamp
                        lastPackage = event.packageName
                    }
                }
            }
            
            lastPackage
        } catch (e: Exception) {
            println("UsageStats 감지 오류: ${e.message}")
            ""
        }
    }

    /** 차단 목록에 있으면 오버레이 + 홈으로 보내기 (Intent 사용, 접근성 미사용) */
    private fun checkAndBlockForegroundApp() {
        try {
            val currentPackage = getForegroundAppViaUsageStats()
            if (currentPackage.isEmpty()) return
            
            // DEBUG LOG
            println("Foreground Check: current=$currentPackage, myPackage=$packageName, blocked=${blockedApps.keys}")

            // Prevent self-blocking (Explicit & Dynamic)
            if (currentPackage == packageName || currentPackage == "kr.jamgltime.app") {
                if (lastBlockedPackage.isNotEmpty()) {
                     hideOverlay()
                     lastBlockedPackage = ""
                }
                return
            }
            
            // 차단 목록에 없는 앱(홈 화면 등)으로 이동했다면, 오버레이를 닫고 상태 초기화
            if (!blockedApps.containsKey(currentPackage)) {
                if (lastBlockedPackage.isNotEmpty()) {
                    hideOverlay()
                    lastBlockedPackage = ""
                }
                return
            }

            if (currentPackage == lastBlockedPackage) return

            val remainingMillis = (blockedApps[currentPackage] ?: 0L) - System.currentTimeMillis()
            if (remainingMillis <= 0) {
                lastBlockedPackage = ""
                return
            }

            lastBlockedPackage = currentPackage
            val appName = getAppName(currentPackage)
            val remainingMinutes = (remainingMillis / 60000).toInt()
            val message = if (remainingMinutes > 0) {
                "🔒 $appName\n${getString(R.string.app_locked_suffix)}\n\n$remainingMinutes${getString(R.string.available_after_suffix)}"
            } else "🔒 $appName\n${getString(R.string.app_locked_suffix)}\n\n${getString(R.string.less_than_one_minute)}"

            try {
                showOverlay(message)
                // 접근성 없이 홈으로 이동 (Intent 사용)
                val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(homeIntent)
                
                // PIP(Picture-in-Picture) 모드 차단을 위한 프로세스 종료 시도
                // (주의: 시스템 권한에 따라 실패할 수 있으나, 일반적인 경우 PIP 종료에 효과적)
                try {
                    val am = getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
                    am.killBackgroundProcesses(currentPackage)
                    println("PIP 차단 시도: $currentPackage 프로세스 종료 요청")
                } catch (e: Exception) {
                    println("PIP 차단 실패: ${e.message}")
                }
                
                handler.postDelayed({ hideOverlay() }, 500)
                
                // 차단 후 잠시 뒤에 상태를 초기화하여, 사용자가 바로 다시 진입했을 때 또 차단될 수 있도록 함
                handler.postDelayed({ lastBlockedPackage = "" }, 1500)
            } catch (e: Exception) {
                println("앱 차단 중 오류: ${e.message}")
                try {
                    startActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).setFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                } catch (_: Exception) {}
            }
        } catch (e: Exception) {
            println("포그라운드 앱 감지 에러: ${e.message}")
            lastBlockedPackage = ""
        }
    }

    private fun stopAutoUnlockTimer() {
        checkTimer?.let {
            handler.removeCallbacks(it)
            checkTimer = null
        }
    }

    private fun showOverlay(message: String) {
        try {
            if (windowManager == null) windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
            hideOverlay()
            
            val layout = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setBackgroundColor(Color.parseColor("#CC000000"))
                setPadding(60, 60, 60, 60)
            }

            val messageView = TextView(this).apply {
                text = message
                textSize = 24f
                setTextColor(Color.WHITE)
                gravity = Gravity.CENTER
                setPadding(0, 0, 0, 60)
            }

            layout.addView(messageView)
            
            overlayView = layout

            val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }
            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                layoutFlag,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT
            )
            params.gravity = Gravity.CENTER
            windowManager?.addView(overlayView, params)
        } catch (e: Exception) {
            println("Overlay 표시 실패: ${e.message}")
        }
    }

    private fun hideOverlay() {
        try {
            overlayView?.let {
                windowManager?.removeView(it)
                overlayView = null
            }
        } catch (e: Exception) {
            println("Overlay 제거 실패: ${e.message}")
        }
    }

    /** 폰 잠금: 전체 화면 오버레이 (다른 조작 불가) + 잠금 해제 버튼 */
    private fun showPhoneLockOverlay() {
        try {
            if (windowManager == null) windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
            hidePhoneLockOverlay()
            val layout = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setBackgroundColor(Color.parseColor("#E6000000"))
                setPadding(80, 80, 80, 80)
                gravity = Gravity.CENTER
                isClickable = true
                isFocusable = true
                setOnTouchListener { _, _ -> true }
            }
            val title = TextView(this).apply {
                text = getString(R.string.phone_locked_message)
                textSize = 28f
                setTextColor(Color.WHITE)
                gravity = Gravity.CENTER
                setPadding(0, 0, 0, 48)
            }
            val countdownCircle = CountdownCircleView(this).apply {
                layoutParams = LinearLayout.LayoutParams(320, 320).apply {
                    setMargins(0, 0, 0, 24)
                }
            }

            layout.addView(title)
            layout.addView(countdownCircle)
            
            phoneLockOverlayView = layout
            val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }
            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                layoutFlag,
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT
            )
            params.gravity = Gravity.CENTER
            windowManager?.addView(layout, params)
            
            updateCountdownViews(null, countdownCircle)
        } catch (e: Exception) {
            println("폰 잠금 오버레이 실패: ${e.message}")
        }
    }

    private fun startPhoneLockCountdown() {
        stopPhoneLockCountdown()
        phoneLockCountdown = object : Runnable {
            override fun run() {
                val remaining = phoneLockEndTimeMillis - System.currentTimeMillis()
                if (remaining <= 0) {
                    showUnlockNotification("폰 잠금 해제", "폰 잠금이 해제되었습니다.")
                    hidePhoneLockOverlay()
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                    return
                }
                handler.postDelayed(this, 1000)
            }
        }
        handler.post(phoneLockCountdown!!)
    }

    private fun startPhoneLockGuard() {
        stopPhoneLockGuard()
        phoneLockGuardTimer = object : Runnable {
            override fun run() {
                val remaining = phoneLockEndTimeMillis - System.currentTimeMillis()
                if (remaining <= 0) {
                    stopPhoneLockGuard()
                    return
                }

                // 현재 포그라운드 앱 확인
                val currentPkg = getForegroundAppViaUsageStats()
                // 설정 앱 차단 (오버레이 권한 해제 방지)
                if (currentPkg == "com.android.settings") {
                    println("Phone Lock Guard: 설정 앱 접근 차단 ($currentPkg)")
                    
                    // 사용자에게 차단 알림 표시
                    handler.post {
                        android.widget.Toast.makeText(applicationContext, "폰 잠금 중에는 설정을 변경할 수 없습니다.", android.widget.Toast.LENGTH_SHORT).show()
                    }

                    // 홈으로 강제 이동
                    val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                        addCategory(Intent.CATEGORY_HOME)
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    startActivity(homeIntent)
                    // 우리 앱을 띄워서 가리기 (선택적)
                    try {
                        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                        launchIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                        startActivity(launchIntent)
                    } catch (_: Exception) {}
                }

                handler.postDelayed(this, 300) // 0.3초마다 감시
            }
        }
        handler.post(phoneLockGuardTimer!!)
    }

    private fun stopPhoneLockGuard() {
        phoneLockGuardTimer?.let {
            handler.removeCallbacks(it)
            phoneLockGuardTimer = null
        }
    }

    private fun stopPhoneLockCountdown() {
        phoneLockCountdown?.let {
            handler.removeCallbacks(it)
            phoneLockCountdown = null
        }
    }

    private fun updateCountdownViews(textView: TextView?, circleView: CountdownCircleView?) {
        val update = object : Runnable {
            override fun run() {
                val remaining = phoneLockEndTimeMillis - System.currentTimeMillis()
                val label = if (remaining <= 0) {
                    "곧 해제됩니다..."
                } else {
                    val m = (remaining / 60000).toInt()
                    val s = ((remaining % 60000) / 1000).toInt()
                    String.format("%02d:%02d", m, s)
                }
                textView?.text = if (remaining <= 0) "곧 해제됩니다..." else "남은 시간 $label"
                if (phoneLockTotalMillis > 0) {
                    val progressed = (phoneLockTotalMillis - remaining).toFloat().coerceAtLeast(0f)
                    val p = (progressed / phoneLockTotalMillis).coerceIn(0f, 1f)
                    circleView?.setProgress(p, label)
                }
                if (remaining > 0) handler.postDelayed(this, 1000)
            }
        }
        handler.post(update)
    }

    private fun hidePhoneLockOverlay() {
        try {
            phoneLockOverlayView?.let {
                windowManager?.removeView(it)
                phoneLockOverlayView = null
            }
        } catch (e: Exception) {
            println("폰 잠금 오버레이 제거 실패: ${e.message}")
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        stopAutoUnlockTimer()
        stopForegroundCheckTimer()
        stopPhoneLockCountdown()
        hideOverlay()
        hidePhoneLockOverlay()
        lastBlockedPackage = ""
        
        screenReceiver?.let {
            unregisterReceiver(it)
            screenReceiver = null
        }

        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    /**
     * 긴급 해제 시, 같은 예약 구간 내에서는 폰 잠금이 자동으로 재시작되지 않도록 억제.
     * - flutter.phoneLockSuppressedUntil: 억제 만료 시각 (millis)
     * - flutter.lockedApps 에 등록된 PHONE_LOCK_ALL 항목 제거 (즉시 재시작 방지)
     */
    private fun suppressPhoneLockUntilEndTime() {
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            // 예약 종료 시각까지 억제
            prefs.edit().putLong("flutter.phoneLockSuppressedUntil", phoneLockEndTimeMillis).apply()
            // 분 단위(32-bit 안전)로도 저장하여 Dart에서 읽기 쉽게 함
            val untilMinutes = (phoneLockEndTimeMillis / 60000L).toInt()
            prefs.edit().putInt("flutter.phoneLockSuppressedUntilMinutes", untilMinutes).apply()
            // lockedApps 에서 PHONE_LOCK_ALL 제거
            val jsonString = prefs.getString("flutter.lockedApps", "[]") ?: "[]"
            val jsonArray = try {
                org.json.JSONArray(jsonString)
            } catch (_: Exception) {
                org.json.JSONArray()
            }
            val newArray = org.json.JSONArray()
            for (i in 0 until jsonArray.length()) {
                val item = jsonArray.getJSONObject(i)
                val pkg = item.optString("packageName", "")
                if (pkg != "PHONE_LOCK_ALL") {
                    newArray.put(item)
                }
            }
            prefs.edit().putString("flutter.lockedApps", newArray.toString()).apply()
            println("긴급 해제: 억제 설정 및 PHONE_LOCK_ALL 제거 완료")
        } catch (e: Exception) {
            println("긴급 해제 억제 설정 실패: ${e.message}")
        }
    }

    private fun createNotification(): Notification {
        createNotificationChannel()
        val pkgForIcon = blockedApps.keys.firstOrNull()
        val largeIcon = pkgForIcon?.let { getAppIconBitmap(it) }
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Gmanba")
            .setContentText(getNotificationContentText())
            .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
        if (largeIcon != null) builder.setLargeIcon(largeIcon)
        return builder.build()
    }

    private fun getNotificationContentText(): String {
        if (blockedApps.isEmpty()) return "Blocking apps..."
        val appNames = blockedApps.keys.map { getAppName(it) }
        return if (appNames.size <= 3) {
            "${appNames.joinToString(", ")} blocked"
        } else {
            "${appNames.take(2).joinToString(", ")} and ${appNames.size - 2} others blocked"
        }
    }

    private fun updateNotification(text: String) {
        val pkgForIcon = blockedApps.keys.firstOrNull()
        val largeIcon = pkgForIcon?.let { getAppIconBitmap(it) }
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Gmanba")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
        if (largeIcon != null) builder.setLargeIcon(largeIcon)
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).notify(NOTIFICATION_ID, builder.build())
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "App Blocking Service", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shown while apps are being blocked"
            }
            (getSystemService(NotificationManager::class.java)).createNotificationChannel(channel)
        }
    }

    private fun createPhoneLockNotification(): Notification {
        createNotificationChannel()
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.app_lock_notification_title))
            .setContentText(getString(R.string.app_lock_notification_msg))
            .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
    }

    private fun createHighPriorityNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID_HIGH, "Unlock Notification", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Shows notification when app is unlocked"
                enableVibration(true)
            }
            (getSystemService(NotificationManager::class.java)).createNotificationChannel(channel)
        }
    }

    private fun showUnlockNotification(title: String, message: String) {
        createHighPriorityNotificationChannel()
        val notification = NotificationCompat.Builder(this, CHANNEL_ID_HIGH)
            .setContentTitle(title)
            .setContentText(message)
            .setSmallIcon(android.R.drawable.ic_lock_idle_lock) // 또는 잠금 해제 아이콘
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .build()
        
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).notify(NOTIFICATION_ID_UNLOCK, notification)
    }

    private fun getAppIconBitmap(packageName: String): Bitmap? {
        return try {
            val drawable: Drawable = packageManager.getApplicationIcon(packageName)
            val bitmap = if (drawable is BitmapDrawable) {
                drawable.bitmap
            } else {
                val bmp = Bitmap.createBitmap(
                    drawable.intrinsicWidth.coerceAtLeast(72),
                    drawable.intrinsicHeight.coerceAtLeast(72),
                    Bitmap.Config.ARGB_8888
                )
                val canvas = Canvas(bmp)
                drawable.setBounds(0, 0, canvas.width, canvas.height)
                drawable.draw(canvas)
                bmp
            }
            Bitmap.createScaledBitmap(bitmap, 96, 96, true)
        } catch (_: Exception) {
            null
        }
    }

    private fun getAppName(packageName: String): String {
        return try {
            packageManager.getApplicationLabel(packageManager.getApplicationInfo(packageName, 0)).toString()
        } catch (e: Exception) {
            packageName
        }
    }

    class CountdownCircleView(context: Context) : View(context) {
        private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            color = Color.parseColor("#40FFFFFF")
            strokeWidth = 18f
            strokeCap = Paint.Cap.ROUND
        }
        private val fgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            color = Color.WHITE
            strokeWidth = 18f
            strokeCap = Paint.Cap.ROUND
        }
        private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = 64f
            textAlign = Paint.Align.CENTER
        }
        private var progress = 0f
        private var label = ""
        fun setProgress(p: Float, l: String) {
            progress = p
            label = l
            invalidate()
        }
        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val size = Math.min(width, height).toFloat()
            val radius = size / 2f - 28f
            val cx = width / 2f
            val cy = height / 2f
            val rect = RectF(cx - radius, cy - radius, cx + radius, cy + radius)
            canvas.drawArc(rect, -90f, 360f, false, bgPaint)
            canvas.drawArc(rect, -90f, 360f * progress, false, fgPaint)
            val y = cy - (textPaint.descent() + textPaint.ascent()) / 2f
            canvas.drawText(label, cx, y, textPaint)
        }
    }
}
