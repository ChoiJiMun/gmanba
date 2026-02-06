package kr.jamgltime.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import org.json.JSONArray
import org.json.JSONObject
import java.util.*

import android.app.AlarmManager
import android.app.PendingIntent

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        println("=== AlarmReceiver: 알람 수신 ===")

        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "Gmanba:AlarmReceiverWakeLock"
        )
        // 10초간 WakeLock 유지 (서비스 시작 충분한 시간 확보)
        wakeLock.acquire(10 * 1000L)
        
        try {
            // 다음 알람 예약 (무조건 실행)
            scheduleNextAlarm(context, intent)

            val packageName = intent.getStringExtra("packageName") ?: return
            val appName = intent.getStringExtra("appName") ?: return
            val durationMinutes = intent.getIntExtra("durationMinutes", 0)
            val weekdays = intent.getIntegerArrayListExtra("weekdays") ?: return
            val strictMode = intent.getBooleanExtra("strictMode", false)
            
            // 현재 요일 확인
            val calendar = Calendar.getInstance()
            // Calendar.DAY_OF_WEEK: 1=Sunday, 2=Monday, ... 7=Saturday
            // Dart DateTime.weekday: 1=Monday, ... 7=Sunday
            // 변환 필요
            val androidDayOfWeek = calendar.get(Calendar.DAY_OF_WEEK)
            val dartDayOfWeek = if (androidDayOfWeek == 1) 7 else androidDayOfWeek - 1
            
            if (!weekdays.contains(dartDayOfWeek)) {
                println("오늘($dartDayOfWeek)은 예약된 요일(${weekdays})이 아님")
                return
            }
            
            println("예약 잠금 실행: $appName ($packageName), $durationMinutes 분, Strict: $strictMode")
            
            // SharedPreferences 업데이트
            val hour = intent.getIntExtra("hour", -1)
            val minute = intent.getIntExtra("minute", -1)
            if (hour != -1 && minute != -1) {
                updateLockedApps(context, packageName, appName, durationMinutes, strictMode, hour, minute)
            }
            
            // 서비스 시작 (일반 차단 목록 업데이트 + 폰 잠금 포함)
            startBlockingService(context)
        } catch (e: Exception) {
            println("AlarmReceiver 실행 중 오류 발생: $e")
            e.printStackTrace()
        } finally {
            if (wakeLock.isHeld) {
                wakeLock.release()
            }
        }
    }

    private fun scheduleNextAlarm(context: Context, intent: Intent) {
        try {
            val id = intent.getIntExtra("alarmId", -1)
            val hour = intent.getIntExtra("hour", -1)
            val minute = intent.getIntExtra("minute", -1)
            
            if (id == -1 || hour == -1 || minute == -1) {
                println("다음 알람 예약 실패: 필수 정보 누락 (id=$id, h=$hour, m=$minute)")
                return
            }

            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            
            // 다음 날 같은 시간 설정
            val calendar = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, minute)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
                add(Calendar.DAY_OF_YEAR, 1) // 내일
            }
            
            // PendingIntent 재생성
            val nextIntent = Intent(context, AlarmReceiver::class.java).apply {
                putExtras(intent) // 기존 extra 복사
            }
            
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                id,
                nextIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, calendar.timeInMillis, pendingIntent)
            } else {
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, calendar.timeInMillis, pendingIntent)
            }
            println("다음 알람 예약됨: ID=$id, ${hour}:${minute}")
        } catch (e: Exception) {
            println("다음 알람 예약 중 오류: $e")
        }
    }
    
    private fun updateLockedApps(context: Context, packageName: String, appName: String, durationMinutes: Int, strictMode: Boolean, hour: Int, minute: Int) {
        try {
            // Flutter SharedPreferences는 'FlutterSharedPreferences'라는 이름의 파일 사용
            // 키 앞에는 'flutter.' 접두사가 붙음
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val jsonString = prefs.getString("flutter.lockedApps", "[]") ?: "[]"
            
            val jsonArray = if (jsonString.isNotEmpty()) JSONArray(jsonString) else JSONArray()
            
            val newArray = JSONArray()
            val now = System.currentTimeMillis()
            
            // 시작 시간 및 종료 시간 계산
            val calendar = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, minute)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            val startMillis = calendar.timeInMillis
            val endMillis = startMillis + durationMinutes * 60 * 1000
            
            // 유효성 검사: 이미 끝난 예약이면 업데이트하지 않음
            if (endMillis <= now) {
                println("예약 잠금 시간이 이미 지났습니다. (종료: ${Date(endMillis)})")
                // 기존 항목 유지만 수행 (아래 루프에서 처리)
            }
            
            // 1. 기존 항목 중 만료되지 않은 다른 앱들은 유지
            // 2. 같은 패키지는 제거 (새로 추가할 것이므로)
            
            for (i in 0 until jsonArray.length()) {
                val item = jsonArray.getJSONObject(i)
                val pkg = item.getString("packageName")
                
                // 같은 패키지는 건너뜀 (업데이트)
                if (pkg == packageName) continue
                
                // 만료된 항목도 여기서 정리해버리면 좋음
                try {
                    // unlockTime은 Long(Timestamp) 또는 String으로 저장될 수 있음
                    // 안전하게 처리하기 위해 object로 가져와서 처리
                    val unlockTimeObj = item.get("unlockTime")
                    val unlockTime = if (unlockTimeObj is Number) {
                        unlockTimeObj.toLong()
                    } else {
                        unlockTimeObj.toString().toLongOrNull() ?: 0L
                    }
                    
                    if (unlockTime > now) {
                        newArray.put(item)
                    }
                } catch (e: Exception) {
                    // 파싱 에러나면 제거
                }
            }
            
            // 새 잠금 추가 (유효한 경우에만)
            if (endMillis > now) {
                val newItem = JSONObject()
                newItem.put("name", appName)
                newItem.put("packageName", packageName)
                // Flutter의 LockedApp.fromJson은 int(timestamp)를 기대함
                newItem.put("unlockTime", endMillis)
                newItem.put("icon", 57553) // Icons.block (Material Icon CodePoint) - 더미 값
                newItem.put("strictMode", strictMode)
                
                newArray.put(newItem)
                println("잠금 추가됨: $appName (~${Date(endMillis)})")
            }
            
            // 저장
            prefs.edit().putString("flutter.lockedApps", newArray.toString()).apply()
            println("lockedApps 업데이트 완료: ${newArray.length()}개 앱 잠금 중")
            
        } catch (e: Exception) {
            println("lockedApps 업데이트 오류: $e")
            e.printStackTrace()
        }
    }
    
    private fun startBlockingService(context: Context) {
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val jsonString = prefs.getString("flutter.lockedApps", "[]") ?: "[]"
            val jsonArray = if (jsonString.isNotEmpty()) JSONArray(jsonString) else JSONArray()
            
            val blockedApps = ArrayList<String>()
            val unlockTimes = ArrayList<String>()
            var isStrictMode = false
            var phoneLockDuration = 0
            var isPhoneLockActive = false
            
            val now = System.currentTimeMillis()
            
            for (i in 0 until jsonArray.length()) {
                val item = jsonArray.getJSONObject(i)
                val pkg = item.getString("packageName")
                
                try {
                    val unlockTimeObj = item.get("unlockTime")
                    val unlockTime = if (unlockTimeObj is Number) {
                        unlockTimeObj.toLong()
                    } else {
                        unlockTimeObj.toString().toLongOrNull() ?: 0L
                    }
                    
                    if (unlockTime > now) {
                        blockedApps.add(pkg)
                        unlockTimes.add(unlockTime.toString())
                        if (item.optBoolean("strictMode", false)) {
                            isStrictMode = true
                        }
                        
                        if (pkg == "PHONE_LOCK_ALL") {
                            isPhoneLockActive = true
                            val remainingMillis = unlockTime - now
                            phoneLockDuration = (remainingMillis / 60000).toInt()
                            if (phoneLockDuration < 1) phoneLockDuration = 1
                        }
                    }
                } catch (e: Exception) {
                    // ignore
                }
            }
            
            if (isPhoneLockActive) {
                println("PHONE_LOCK_ALL 감지됨: $phoneLockDuration 분 남음")
                val serviceIntent = Intent(context, AppBlockerService::class.java).apply {
                    action = "kr.jamgltime.app.PHONE_LOCK"
                    putExtra("durationMinutes", phoneLockDuration)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
            } else if (blockedApps.isNotEmpty()) {
                val serviceIntent = Intent(context, AppBlockerService::class.java).apply {
                    putStringArrayListExtra("blockedApps", blockedApps)
                    putStringArrayListExtra("unlockTimes", unlockTimes)
                    putExtra("strictMode", isStrictMode)
                }
                
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
            } else {
                // 차단할 앱이 없으면 서비스 종료 (선택 사항)
                 val serviceIntent = Intent(context, AppBlockerService::class.java)
                 context.stopService(serviceIntent)
            }
            
        } catch (e: Exception) {
            println("BlockingService 시작 오류: $e")
            e.printStackTrace()
        }
    }
}
