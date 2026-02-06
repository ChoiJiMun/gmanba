package kr.jamgltime.app

import android.app.AlarmManager
import android.app.AppOpsManager
import android.app.PendingIntent
import java.util.Calendar
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import java.io.ByteArrayOutputStream
import java.util.ArrayList
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.app.ActivityManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.jimoon.jamgltime/app_blocker"
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledApps" -> {
                    val apps = getInstalledApps()
                    result.success(apps)
                }
                "getForegroundApp" -> {
                    val foregroundApp = getForegroundApp()
                    result.success(foregroundApp)
                }
                "requestPermissions" -> {
                    val hasPermissions = checkPermissions()
                    if (!hasPermissions) {
                        openPermissionSettings()
                    }
                    result.success(hasPermissions)
                }
                "checkPermissions" -> {
                    result.success(checkPermissions())
                }
                "checkPermissionStatus" -> {
                    val status = mapOf(
                        "usage" to checkUsageStats(),
                        "overlay" to checkOverlay(),
                        "alarm" to checkAlarm(),
                        "notification" to checkNotification()
                    )
                    result.success(status)
                }
                "checkAccessibilityPermission" -> {
                    result.success(false)
                }
                "openPermissionScreen" -> {
                    val type = call.argument<String>("type")
                    try {
                        when (type) {
                            "usage" -> {
                                startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                            }
                            "overlay" -> {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                    val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION)
                                    intent.data = android.net.Uri.parse("package:$packageName")
                                    startActivity(intent)
                                }
                            }
                            "alarm" -> {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                    val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                                    intent.data = android.net.Uri.parse("package:$packageName")
                                    startActivity(intent)
                                }
                            }
                            "notification" -> {
                                try {
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                                            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                                        }
                                        startActivity(intent)
                                    } else {
                                        val intent = Intent("android.settings.APP_NOTIFICATION_SETTINGS").apply {
                                            putExtra("app_package", packageName)
                                            putExtra("app_uid", applicationInfo.uid)
                                        }
                                        startActivity(intent)
                                    }
                                } catch (_: Exception) {
                                    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                        data = android.net.Uri.parse("package:$packageName")
                                    }
                                    startActivity(intent)
                                }
                            }
                            "accessibility" -> {
                                // Accessibility removed
                                result.success(false)
                            }
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("PERMISSION_ERROR", e.message, null)
                    }
                }
                "startBlockingService" -> {
                    val blockedApps = call.argument<List<String>>("blockedApps") ?: emptyList()
                    val unlockTimes = call.argument<List<String>>("unlockTimes") ?: emptyList()
                    val strictMode = call.argument<Boolean>("strictMode") ?: false
                    
                    if (blockedApps.isNotEmpty()) {
                        startBlockingService(blockedApps, unlockTimes, strictMode)
                    } else {
                        stopBlockingService()
                    }
                    result.success(true)
                }
                "stopBlockingService" -> {
                    stopBlockingService()
                    result.success(true)
                }
                "startPhoneLock" -> {
                    val duration = call.argument<Int>("duration") ?: 15
                    val strictMode = call.argument<Boolean>("strictMode") ?: false
                    try {
                        startPhoneLock(duration, strictMode)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("PHONE_LOCK_ERROR", e.message, null)
                    }
                }
                "scheduleAlarm" -> {
                    val id = call.argument<Int>("id") ?: 0
                    val hour = call.argument<Int>("hour") ?: 0
                    val minute = call.argument<Int>("minute") ?: 0
                    val weekdays = call.argument<List<Int>>("weekdays") ?: emptyList()
                    val duration = call.argument<Int>("duration") ?: 0
                    val pkgName = call.argument<String>("packageName") ?: ""
                    val appName = call.argument<String>("appName") ?: ""
                    val strictMode = call.argument<Boolean>("strictMode") ?: false
                    
                    scheduleAlarm(id, hour, minute, weekdays, duration, pkgName, appName, strictMode)
                    result.success(true)
                }
                "cancelAlarm" -> {
                    val id = call.argument<Int>("id") ?: 0
                    cancelAlarm(id)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
    
    private fun getInstalledApps(): List<Map<String, Any>> {
        val packageManager = packageManager
        val packages = packageManager.getInstalledApplications(PackageManager.GET_META_DATA)
        
        // 제외할 시스템 앱들
        val excludePackages = setOf(
            "com.android.systemui",
            "com.android.settings",
            "com.android.launcher",
            "com.android.launcher3",
            "android.widget.accessibility",
            "com.google.android.accessibility.switchaccess",
            "com.google.android.apps.accessibility.voiceaccess"
        )
        
        val appList = mutableListOf<Map<String, Any>>()
        
        for (appInfo in packages) {
            try {
                // 제외 목록에 있으면 스킵
                if (excludePackages.contains(appInfo.packageName)) {
                    continue
                }
                
                // 런처가 있는 앱만
                if (packageManager.getLaunchIntentForPackage(appInfo.packageName) == null) {
                    continue
                }
                
                // 시스템 앱 제외 (사용자가 설치한 앱만)
                val isUserApp = (appInfo.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) == 0 ||
                                (appInfo.flags and android.content.pm.ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
                
                if (!isUserApp) {
                    continue
                }
                
                // 앱 이름 가져오기
                val appName = try {
                    packageManager.getApplicationLabel(appInfo).toString()
                } catch (e: Exception) {
                    appInfo.packageName
                }

                // 앱 아이콘 가져오기
                val iconBytes = getAppIconBytes(appInfo.packageName)
                
                val appMap = mutableMapOf<String, Any>(
                    "name" to appName,
                    "packageName" to appInfo.packageName
                )
                
                if (iconBytes != null) {
                    appMap["icon"] = iconBytes
                }

                appList.add(appMap)
            } catch (e: Exception) {
                // 앱 정보 가져오기 실패 시 스킵
                continue
            }
        }
        
        return appList.sortedBy { it["name"] as String }
    }

    private fun getAppIconBytes(packageName: String): ByteArray? {
        try {
            val drawable = packageManager.getApplicationIcon(packageName)
            val bitmap = if (drawable is BitmapDrawable) {
                drawable.bitmap
            } else {
                val bitmap = Bitmap.createBitmap(drawable.intrinsicWidth, drawable.intrinsicHeight, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bitmap)
                drawable.setBounds(0, 0, canvas.width, canvas.height)
                drawable.draw(canvas)
                bitmap
            }
            
            // 성능을 위해 아이콘 크기 조정 (예: 72x72)
            val scaledBitmap = Bitmap.createScaledBitmap(bitmap, 72, 72, true)
            
            val stream = ByteArrayOutputStream()
            scaledBitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            return stream.toByteArray()
        } catch (e: Exception) {
            return null
        }
    }
    
    private fun getForegroundApp(): String {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        
        // Android 5.0 이상
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try {
                val tasks = activityManager.appTasks
                if (tasks.isNotEmpty()) {
                    val topTask = tasks[0]
                    val baseIntent = topTask.taskInfo?.baseIntent ?: return ""
                    return baseIntent.getStringExtra("package") ?: baseIntent.component?.packageName ?: ""
                }
            } catch (e: Exception) {
                // Usage Stats를 통한 방법 사용
            }
        }
        
        // Usage Stats 권한이 있을 경우 사용
        try {
            val usage = android.app.usage.UsageStatsManager::class.java
                .getDeclaredMethod("queryUsageStats", Int::class.java, Long::class.java, Long::class.java)
            
            val now = System.currentTimeMillis()
            val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as android.app.usage.UsageStatsManager
            val stats = usageStatsManager.queryUsageStats(
                android.app.usage.UsageStatsManager.INTERVAL_BEST,
                now - 1000 * 60,
                now
            )
            
            if (stats.isNotEmpty()) {
                val sortedStats = stats.sortedByDescending { it.lastTimeUsed }
                return sortedStats[0].packageName
            }
        } catch (e: Exception) {
            // 폴백
        }
        
        return ""
    }
    
    private fun checkPermissions(): Boolean {
        return checkUsageStats() && checkOverlay() && checkAlarm()
    }

    private fun checkUsageStats(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName
            )
        } else {
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun checkOverlay(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
    }

    private fun checkAlarm(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.canScheduleExactAlarms()
        } else {
            true
        }
    }
    
    private fun checkNotification(): Boolean {
        return try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            nm.areNotificationsEnabled()
        } catch (_: Exception) {
            true
        }
    }
    
    private fun openPermissionSettings() {
        // Usage Stats 권한 설정 화면
        if (!checkPermissions()) {
            val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    packageName
                )
            } else {
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    packageName
                )
            }
            
            if (mode != AppOpsManager.MODE_ALLOWED) {
                startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION)
                intent.data = android.net.Uri.parse("package:$packageName")
                startActivity(intent)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                if (!alarmManager.canScheduleExactAlarms()) {
                    val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                    intent.data = android.net.Uri.parse("package:$packageName")
                    startActivity(intent)
                }
            }
        }
    }
    
    private fun checkAccessibilityPermission(): Boolean {
        return false
    }

    private fun startBlockingService(blockedApps: List<String>, unlockTimes: List<String>, strictMode: Boolean) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        prefs.edit().putBoolean("flutter.isStrictMode", strictMode).apply()
        
        var maxTime = 0L
        for (timeStr in unlockTimes) {
            val t = timeStr.toLongOrNull() ?: 0L
            if (t > maxTime) maxTime = t
        }
        if (maxTime > 0) {
             prefs.edit().putLong("flutter.strictModeEndTime", maxTime).apply()
        }

        val intent = Intent(this, AppBlockerService::class.java)
        
        // 폰 잠금 패키지가 포함되어 있는지 확인
        val phoneLockIndex = blockedApps.indexOf("PHONE_LOCK_ALL")
        if (phoneLockIndex != -1) {
             // 억제 중이면 폰 잠금 시그널을 보내지 않음
             val suppressedUntilMinutes = prefs.getInt("flutter.phoneLockSuppressedUntilMinutes", 0)
             val nowMinutes = (System.currentTimeMillis() / 60000L).toInt()
             if (suppressedUntilMinutes > 0 && nowMinutes < suppressedUntilMinutes) {
                 println("=== 폰 잠금 억제 중: 서비스 폰 잠금 시작 스킵 ===")
             } else {
            intent.action = "kr.jamgltime.app.PHONE_LOCK"
            
            // 남은 시간 계산하여 durationMinutes 전달
            val unlockTimeStr = unlockTimes[phoneLockIndex]
            val unlockTime = unlockTimeStr.toLongOrNull() ?: 0L
            val remainingMillis = unlockTime - System.currentTimeMillis()
            val remainingMinutes = if (remainingMillis > 0) (remainingMillis / 60000).toInt() + 1 else 1
            
            intent.putExtra("durationMinutes", remainingMinutes)
            println("=== MainActivity: 폰 잠금 포함 서비스 시작 (남은 시간: ${remainingMinutes}분) ===")
             }
        }
        
        intent.putStringArrayListExtra("blockedApps", ArrayList(blockedApps))
        intent.putStringArrayListExtra("unlockTimes", ArrayList(unlockTimes))
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
    
    private fun startPhoneLock(duration: Int, strictMode: Boolean) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        // 억제 중이면 시작하지 않음
        val suppressedUntilMinutes = prefs.getInt("flutter.phoneLockSuppressedUntilMinutes", 0)
        val nowMinutes = (System.currentTimeMillis() / 60000L).toInt()
        if (suppressedUntilMinutes > 0 && nowMinutes < suppressedUntilMinutes) {
            println("=== 폰 잠금 억제 중: 시작 요청 무시 ===")
            return
        }
        prefs.edit().putBoolean("flutter.isStrictMode", strictMode).apply()
        val endTime = System.currentTimeMillis() + duration * 60 * 1000
        prefs.edit().putLong("flutter.strictModeEndTime", endTime).apply()

        val intent = Intent(this, AppBlockerService::class.java).apply {
            action = "kr.jamgltime.app.PHONE_LOCK"
            putExtra("durationMinutes", duration)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
    
    private fun stopBlockingService() {
        println("=== MainActivity: 서비스 중지 요청 ===")
        val intent = Intent(this, AppBlockerService::class.java)
        val stopped = stopService(intent)
        println("서비스 중지 결과: $stopped")
    }

    private fun scheduleAlarm(id: Int, hour: Int, minute: Int, weekdays: List<Int>, duration: Int, pkgName: String, appName: String, strictMode: Boolean) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, AlarmReceiver::class.java).apply {
            putExtra("alarmId", id)
            putExtra("hour", hour)
            putExtra("minute", minute)
            putExtra("packageName", pkgName)
            putExtra("appName", appName)
            putExtra("durationMinutes", duration)
            putExtra("strictMode", strictMode)
            putIntegerArrayListExtra("weekdays", ArrayList(weekdays))
        }
        
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        // 알람 시간 설정
        val calendar = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        
        // 종료 시간이 이미 지났다면 내일로 설정
        // (시작 시간이 지났더라도 종료 시간이 안 지났으면 오늘 실행 -> 즉시 발동)
        if (calendar.timeInMillis + duration * 60 * 1000 <= System.currentTimeMillis()) {
            calendar.add(Calendar.DAY_OF_YEAR, 1)
        }
        
        try {
            // Doze 모드에서도 정확한 실행을 위해 setExactAndAllowWhileIdle 사용
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    calendar.timeInMillis,
                    pendingIntent
                )
            } else {
                alarmManager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    calendar.timeInMillis,
                    pendingIntent
                )
            }
            println("알람 스케줄링됨(Exact): ID=$id, ${hour}:${minute}, $pkgName")
        } catch (e: SecurityException) {
            println("알람 권한 없음: $e")
        }
    }

    private fun cancelAlarm(id: Int) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, AlarmReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            id,
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        )
        
        if (pendingIntent != null) {
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
            println("알람 취소됨: ID=$id")
        }
    }
}
