package kr.jamgltime.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONArray
import java.util.ArrayList
import java.util.Calendar

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            println("=== 디바이스 부팅 완료: 예약 잠금 알람 복구 시작 ===")
            restoreScheduledAlarms(context)
            restoreActiveBlocks(context)
        }
    }

    private fun restoreActiveBlocks(context: Context) {
        try {
            // 활성화된 차단 복구를 위해 서비스 시작 시도
            // 서비스 내부에서 SharedPreferences(app_blocker_prefs)를 확인하여 복구함
            val serviceIntent = Intent(context, AppBlockerService::class.java).apply {
                putExtra("isBootRestore", true)
            }
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
            println("차단 서비스 복구 요청 보냄")
        } catch (e: Exception) {
            println("차단 서비스 복구 실패: $e")
        }
    }

    private fun restoreScheduledAlarms(context: Context) {
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val jsonString = prefs.getString("flutter.scheduledLocks", "[]") ?: "[]"
            val jsonArray = if (jsonString.isNotEmpty()) JSONArray(jsonString) else JSONArray()

            if (jsonArray.length() == 0) return

            println("복구할 예약 잠금: ${jsonArray.length()}개")

            for (i in 0 until jsonArray.length()) {
                try {
                    val item = jsonArray.getJSONObject(i)
                    val pkgName = item.getString("packageName")
                    val appName = item.getString("appName")
                    val hour = item.getInt("hour")
                    val minute = item.getInt("minute")
                    val duration = item.getInt("durationMinutes")
                    val strictMode = item.optBoolean("strictMode", false)
                    
                    val weekdaysJson = item.getJSONArray("weekdays")
                    val weekdays = ArrayList<Int>()
                    for (j in 0 until weekdaysJson.length()) {
                        weekdays.add(weekdaysJson.getInt(j))
                    }

                    // ID 생성 (Dart 코드와 동일한 로직)
                    val id = (pkgName + "$hour$minute").hashCode()

                    scheduleAlarm(context, id, hour, minute, weekdays, duration, pkgName, appName, strictMode)
                } catch (e: Exception) {
                    println("예약 항목 파싱 실패: $e")
                }
            }
        } catch (e: Exception) {
            println("알람 복구 실패: $e")
        }
    }

    private fun scheduleAlarm(context: Context, id: Int, hour: Int, minute: Int, weekdays: List<Int>, duration: Int, pkgName: String, appName: String, strictMode: Boolean) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, AlarmReceiver::class.java).apply {
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
            context,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val calendar = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        
        if (calendar.timeInMillis <= System.currentTimeMillis()) {
            calendar.add(Calendar.DAY_OF_YEAR, 1)
        }
        
        try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
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
            println("알람 복구됨(Exact): $appName ($hour:$minute)")
        } catch (e: SecurityException) {
            println("알람 권한 없음: $e")
        }
    }
}
