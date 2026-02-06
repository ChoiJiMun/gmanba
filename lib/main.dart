import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';

// Constants Definition
class AppConstants {
  // App Package Name
  static const String appPackageName = 'kr.jamgltime.app';
  
  // Timer Related
  static const Duration timerInterval = Duration(seconds: 1);
  static const Duration serviceStartDelay = Duration(milliseconds: 500);
  
  // Time Related Constants
  static const int minLockDurationMinutes = 5;
  static const int maxLockDurationMinutes = 1440; // 24 hours
  static const int defaultScheduledHour = 9;
  static const int defaultScheduledMinute = 0;
  static const int defaultScheduledDuration = 30;
  
  // Scheduled Lock Check Window (minutes)
  static const int scheduledLockCheckWindowMinutes = 60;
  
  // Essential System Packages
  static const List<String> essentialSystemPackages = [
    'com.android.systemui',
    'com.android.settings',
    'com.android.packageinstaller',
    'com.android.permissioncontroller',
    'com.google.android.gms',
  ];
  
  // Quick Time Selection Options (minutes)
  static const List<int> quickTimeOptions = [10, 30, 60, 120, 180, 240, 360, 720, 1440];
  
  // Scheduled Lock Quick Time Options (minutes)
  static const List<int> quickScheduleDurationOptions = [30, 60, 120, 180, 240, 360, 720, 1440];

  // Special Package Name for Phone Lock
  static const String phoneLockPackageName = 'PHONE_LOCK_ALL';

  // AdMob Ad ID
  static String get adMobBannerUnitId {
    if (Platform.isAndroid) {
      // Android Real Ad ID
      return 'ca-app-pub-5359935982195695/7226678194';
    } else if (Platform.isIOS) {
      // iOS Test Ad ID (Development & TestFlight)
      // TODO: Create and replace with iOS-specific App/Ad Unit ID in AdMob Console.
      return 'ca-app-pub-3940256099942544/2934735716';
    }
    return '';
  }
}

// Utility Functions
class AppUtils {
  // Korean Initial Consonant Extraction (for search)
  static String getChosung(String text) {
    const chosungList = [
      'ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ',
      'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ'
    ];
    
    String result = '';
    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (code >= 0xAC00 && code <= 0xD7A3) {
        final index = ((code - 0xAC00) / 28 / 21).floor();
        result += chosungList[index];
      } else {
        result += text[i];
      }
    }
    return result.toLowerCase();
  }
  
  // App Filtering (Exclude System Apps & Self)
  static List<dynamic> filterApps(List<dynamic> apps) {
    return apps.where((app) {
      final packageName = app['packageName'] as String? ?? '';
      final appName = app['name'] as String? ?? '';
      
      // Exclude Gmanba App
      if (packageName == AppConstants.appPackageName) return false;
      
      // Exclude Android Switch (User Request)
      if (appName == 'Android Switch') return false;
      
      // Exclude Core System Apps
      if (packageName.startsWith('android.')) return false;
      
      // Exclude Essential Android System Packages
      if (AppConstants.essentialSystemPackages.contains(packageName)) return false;
      
      return true;
    }).toList();
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MobileAds.instance.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'), // English
        Locale('ko'), // Korean
      ],
      theme: ThemeData(
        primarySwatch: Colors.green,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        brightness: Brightness.light,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  late MethodChannel platform;
  List<LockedApp> lockedApps = [];
  List<ScheduledLock> scheduledLocks = [];
  Timer? _timer;
  int _selectedIndex = 0;  // 0: Now Lock, 1: Schedule Lock
  
  // AdMob Banner
  BannerAd? _bannerAd;
  bool _isBannerAdReady = false;

  bool _isLoading = true; // Add loading state

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Register App Lifecycle Observer
    platform = const MethodChannel('com.jimoon.jamgltime/app_blocker');
    
    // Load Banner Ad
    _loadBannerAd();
    
    // Start Initialization
    _init();
  }

  Future<void> _init() async {
    print('=== App Initialization Started ===');
    try {
      // 1. Load Data
      await _loadLockedApps();
      await _loadScheduledLocks();
      
      // Delay initialization to prevent native crashes on cold start (especially after force quit)
      await Future.delayed(const Duration(milliseconds: 1000));

      // 2. iOS Restore & Sync
      if (Platform.isIOS) {
        try {
          // Request Authorization removed from startup to prevent crashes.
          // It will be requested when user tries to add a lock.
          
          await platform.invokeMethod('restoreBlockedApps');
        } catch (e) {
          print('Error restoring/authorizing iOS: $e');
        }
      }
      
      // 3. Logic Checks
      await _cleanupExpiredApps();
      await _syncServiceOnStartup();
      _checkMissedScheduledLocks();
      
      // 4. Timer Start
      _startTimer();
      
      // 5. Post-Frame Tasks (Permissions)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndShowPermissionDialog();
      });
      
    } catch (e) {
      print('Initialization Error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      print('=== App Initialization Completed ===');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Unregister App Lifecycle Observer
    _timer?.cancel();
    _bannerAd?.dispose();
    super.dispose();
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: AppConstants.adMobBannerUnitId, // Use ID defined in Constants
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (_) {
          setState(() {
            _isBannerAdReady = true;
          });
        },
        onAdFailedToLoad: (ad, err) {
          print('Failed to load a banner ad: ${err.message}');
          _isBannerAdReady = false;
          ad.dispose();
        },
      ),
    );

    _bannerAd?.load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Check state when app resumes (Foreground)
    if (state == AppLifecycleState.resumed) {
      print('=== App Resumed: State Check & Scheduled Lock Check ===');
      _cleanupExpiredApps();      // Unlock Expired Locks
      _checkMissedScheduledLocks(); // Check Missed Scheduled Locks
      _syncServiceOnStartup();    // Sync Service State
    }
  }

  Future<void> _checkAndShowPermissionDialog() async {
    // iOS does not show Android-specific permission dialogs (Usage Stats, Overlay, Alarm)
    if (Platform.isIOS) return;

    final prefs = await SharedPreferences.getInstance();
    final isFirstRun = !prefs.containsKey('permissions_checked');
    
    if (isFirstRun) {
      final notifGranted = await Permission.notification.isGranted;
      if (!notifGranted) {
        await Permission.notification.request();
      }
    }
    
    // Show permission dialog on first run or if essential permissions are missing
    if (isFirstRun || !(await _hasAllRequiredPermissions())) {
      if (mounted) {
        _showPermissionDialog();
      }
    }
  }
  
  Future<bool> _hasAllRequiredPermissions() async {
    if (Platform.isIOS) return true;
    final overlayGranted = await Permission.systemAlertWindow.isGranted;
    final alarmGranted = await Permission.scheduleExactAlarm.isGranted;
    final notificationGranted = await Permission.notification.isGranted;
    return overlayGranted && alarmGranted && notificationGranted;
  }
  
  void _showPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const PermissionDialog(),
    );
  }
  
  Future<void> _requestPermissions() async {
    final permissions = [
      Permission.scheduleExactAlarm,
      Permission.systemAlertWindow,
      Permission.notification,
    ];

    for (final permission in permissions) {
      final status = await permission.request();
      print('Permission Request - ${permission.toString()}: $status');
    }
  }

  Future<void> _startPhoneLockWithDuration(int minutes, {bool strictMode = false}) async {
    try {
      await platform.invokeMethod('startPhoneLock', {
        'duration': minutes,
        'strictMode': strictMode,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(strictMode 
                ? '🔒 Strict Mode Activated! (Settings blocked & Uninstall disabled)' 
                : 'Phone Lock started. It will unlock automatically when timer ends.'),
            backgroundColor: strictMode ? Colors.red.shade900 : null,
          ),
        );
      }
    } catch (e) {
      print('Phone Lock Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _chooseAndStartPhoneLock() async {
    // Calculate existing scheduled weekdays for phone lock
    final occupiedWeekdays = scheduledLocks
        .where((lock) => lock.packageName == AppConstants.phoneLockPackageName)
        .expand((lock) => lock.weekdays)
        .toList();

    // Navigate to Phone Lock setup screen (Full screen)
    final scheduleData = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => ScheduleLockScreen(
          isPhoneLockMode: true,
          disabledWeekdays: occupiedWeekdays,
        ),
      ),
    );

    if (scheduleData == null) return;

    // Prepare new lock object
    final newLock = ScheduledLock(
      appName: 'Phone Lock',
      packageName: AppConstants.phoneLockPackageName,
      weekdays: scheduleData['weekdays'],
      hour: scheduleData['hour'],
      minute: scheduleData['minute'],
      durationMinutes: scheduleData['duration'],
      strictMode: scheduleData['strictMode'] ?? false,
    );

    // Immediate lock warning popup (if current time is within schedule) - Confirm before saving
    bool shouldProceed = true;
    if (mounted && newLock.isEnabled) {
      final now = DateTime.now();
      final currentMinutes = now.hour * 60 + now.minute;
      final startMinutes = newLock.hour * 60 + newLock.minute;
      final endMinutes = startMinutes + newLock.durationMinutes;
      
      if (newLock.weekdays.contains(now.weekday) && 
          currentMinutes >= startMinutes && 
          currentMinutes < endMinutes) {
          
          shouldProceed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('⚠️ Immediate Lock Warning', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              content: const Text(
                'The scheduled time includes the current time.\nClicking Confirm will start the lock immediately.\nIf you cancel, the schedule will not be saved.',
                style: TextStyle(color: Colors.black87),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Confirm', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ) ?? false;
      }
    }
    
    if (!shouldProceed) {
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Phone Lock schedule cancelled.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    // Confirmed: Save and Schedule
    setState(() {
      scheduledLocks.add(newLock);
    });

    // Register Alarm
    if (Platform.isAndroid) {
      await _scheduleAlarm(newLock);
    }
    
    // iOS relies on Timer (no AlarmManager)

    await _saveScheduledLocks();

    // Check for missed scheduled locks immediately
    _checkMissedScheduledLocks();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Phone Lock scheduled. (Starts at ${newLock.hour}:${newLock.minute.toString().padLeft(2, '0')})'),
          backgroundColor: Colors.grey.shade800,
        ),
      );
      
      // Switch to Schedule tab to verify
      setState(() {
        _selectedIndex = 1;
      });
    }
  }

  Future<void> _syncServiceOnStartup() async {
    print('=== 앱 시작 시 서비스 동기화 ===');
    try {
      // 시작 시에는 권한을 요청하지 않고 그냥 복구
      if (lockedApps.isNotEmpty) {
        print('저장된 잠금 목록 복구: ${lockedApps.length}개 앱');
        
        // iOS: Skip blocking on startup to avoid re-application/crash loops.
        // The system persists the shield. Native restoreBlockedApps handles loading state.
        if (Platform.isAndroid) {
          await _updateBlockingService();
        } else {
          print('iOS: Skipping redundant block application on startup');
        }
      }
    } catch (e) {
      print('서비스 복구 오류: $e');
    }
    print('서비스 동기화 완료: ${lockedApps.length}개 앱 차단 중');
  }
  
  Future<void> _cleanupExpiredApps() async {
    final beforeCount = lockedApps.length;
    
    // Find expired apps
    final expiredApps = lockedApps
        .where((app) => app.unlockTime.isBefore(DateTime.now()))
        .toList();
    
    setState(() {
      lockedApps.removeWhere((app) => app.unlockTime.isBefore(DateTime.now()));
    });
    
    // If expired apps exist, save and update service
    if (lockedApps.length != beforeCount) {
      final unlockedAppNames = expiredApps.map((app) => app.name).join(', ');
      print('App Restart: ${beforeCount - lockedApps.length} apps auto-unlocked: $unlockedAppNames');
      
      await _saveLockedApps();
      await _updateBlockingService();
      
      // Popup notification
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ App Restart: $unlockedAppNames unlocked!'),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }


  void _startTimer() {
    DateTime? lastScheduledCheck;
    
    _timer = Timer.periodic(AppConstants.timerInterval, (_) async {
      if (!mounted) return;
      
      final now = DateTime.now();
      
      // Check scheduled locks only every minute (Performance optimization)
      if (lastScheduledCheck == null || 
          now.difference(lastScheduledCheck!).inSeconds >= 60) {
        _checkMissedScheduledLocks(); // Use integrated logic
        lastScheduledCheck = now;
      }
      
      final beforeCount = lockedApps.length;
      
      // Find expired apps
      final expiredApps = lockedApps
          .where((app) => app.unlockTime.isBefore(now))
          .toList();
      
      if (expiredApps.isNotEmpty) {
        print('=== Timer: ${expiredApps.length} apps expired ===');
        for (var app in expiredApps) {
          print('- ${app.name} (${app.packageName}): ${app.unlockTime} < $now');
        }
        setState(() {
          lockedApps.removeWhere((app) => app.unlockTime.isBefore(now));
        });
      } else if (lockedApps.isNotEmpty) {
        // No expired apps but locked apps exist, update UI every second for countdown
        setState(() {});
      }
      
      // If apps removed, show notification and update service
      if (lockedApps.length != beforeCount && mounted) {
        // Unlocked app names
        final unlockedAppNames = expiredApps.map((app) => app.name).join(', ');
        
        print('=== App Unlock Notification ===');
        print('Unlocked: $unlockedAppNames');
        print('Remaining: ${lockedApps.length}');
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $unlockedAppNames unlocked!'),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
        
        await _saveLockedApps();
        await _updateBlockingService();
      }
    });
  }
  
  Future<void> _updateBlockingService() async {
    try {
      // Check if phone lock is temporarily suppressed
      int suppressedUntilMinutes = 0;
      try {
        final prefs = await SharedPreferences.getInstance();
        suppressedUntilMinutes = prefs.getInt('phoneLockSuppressedUntilMinutes') ?? 0;
      } catch (_) {}

      // Check if phone lock is active
      final phoneLockIndex = lockedApps.indexWhere((app) => app.packageName == AppConstants.phoneLockPackageName);
      if (phoneLockIndex != -1) {
         final phoneLockApp = lockedApps[phoneLockIndex];
         // Skip if suppressed
         final nowMinutes = DateTime.now().millisecondsSinceEpoch ~/ 60000;
         if (suppressedUntilMinutes > 0 && nowMinutes < suppressedUntilMinutes) {
           print('Phone lock suppressed - Skipping service start');
           return;
         }
         final duration = phoneLockApp.unlockTime.difference(DateTime.now()).inMinutes;
         
         final effectiveDuration = duration < 1 ? 1 : duration;
         
         print('Phone lock mode active: $effectiveDuration min remaining');
         try {
           await platform.invokeMethod('startPhoneLock', {
             'duration': effectiveDuration,
             'strictMode': phoneLockApp.strictMode,
           });
           return; // Phone lock takes precedence
         } catch (e) {
           print('Phone lock service call failed: $e');
         }
      }

      if (Platform.isIOS) {
        if (lockedApps.isNotEmpty) {
          print('iOS: Blocking active');
          await platform.invokeMethod('blockApps');
        } else {
          print('iOS: Blocking inactive');
          await platform.invokeMethod('unblockApps');
        }
        return;
      }

      final allBlockedPackageNames = lockedApps
          .map((app) => app.packageName)
          .toList();
      
      final allUnlockTimes = lockedApps
          .map((app) => app.unlockTime.millisecondsSinceEpoch.toString())
          .toList();

      // If any app is strict, service runs in strict mode
      final isStrictMode = lockedApps.any((app) => app.strictMode);
      
      // Always update service
      print('Updating block list: ${allBlockedPackageNames.length} apps (Strict: $isStrictMode)');
      print('Service manages time internally');
      
      // Delay service start to fix Android 12+ timing issues
      await Future.delayed(AppConstants.serviceStartDelay);
      
      try {
        await platform.invokeMethod('startBlockingService', {
          'blockedApps': allBlockedPackageNames,
          'unlockTimes': allUnlockTimes,
          'strictMode': isStrictMode,
        });
        
        if (allBlockedPackageNames.isEmpty) {
          print('Block list empty - sending empty list to service');
        } else {
          print('Block list update complete: ${allBlockedPackageNames.length} apps');
        }
      } catch (platformException) {
        print('Service call failed: $platformException');
        // Do not exit app on service failure
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ Blocking Service Error. Please restart the app.'),
              backgroundColor: Colors.orange.shade700,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      print('Error updating blocking service: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error occurred: $e'),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _loadLockedApps() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = prefs.getString('lockedApps');
      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> jsonList = json.decode(jsonString);
        if (jsonList.isNotEmpty) {
          setState(() {
            lockedApps = jsonList
                .map((e) {
                  try {
                    return LockedApp.fromJson(e as Map<String, dynamic>);
                  } catch (e) {
                    print('앱 데이터 파싱 오류: $e');
                    return null;
                  }
                })
                .whereType<LockedApp>()
                .toList();
          });
        }
      }
    } catch (e) {
      print('앱 목록 로드 오류: $e');
      // 에러 발생 시 빈 리스트로 초기화
      setState(() {
        lockedApps = [];
      });
    }
  }

  Future<void> _saveLockedApps() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = lockedApps.map((app) => app.toJson()).toList();
      await prefs.setString('lockedApps', json.encode(jsonList));
    } catch (e) {
      print('Error saving apps: $e');
    }
  }

  Future<void> _loadScheduledLocks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = prefs.getString('scheduledLocks');
      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> jsonList = json.decode(jsonString);
        if (jsonList.isNotEmpty) {
          setState(() {
            scheduledLocks = jsonList
                .map((e) {
                  try {
                    return ScheduledLock.fromJson(e as Map<String, dynamic>);
                  } catch (e) {
                    print('예약 잠금 데이터 파싱 오류: $e');
                    return null;
                  }
                })
                .whereType<ScheduledLock>()
                .toList();
          });
        }
      }
    } catch (e) {
      print('예약 잠금 목록 로드 오류: $e');
      // 에러 발생 시 빈 리스트로 초기화
      setState(() {
        scheduledLocks = [];
      });
    }
  }

  Future<void> _saveScheduledLocks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = scheduledLocks.map((lock) => lock.toJson()).toList();
      await prefs.setString('scheduledLocks', json.encode(jsonList));
    } catch (e) {
      print('Error saving scheduled locks: $e');
    }
  }

  int _getAlarmId(ScheduledLock lock) {
    return ("${lock.packageName}${lock.hour}${lock.minute}").hashCode;
  }

  Future<void> _scheduleAlarm(ScheduledLock lock) async {
    print('Alarm schedule request: ${lock.appName} (${lock.hour}:${lock.minute})');
    try {
      await platform.invokeMethod('scheduleAlarm', {
        'id': _getAlarmId(lock),
        'hour': lock.hour,
        'minute': lock.minute,
        'weekdays': lock.weekdays,
        'duration': lock.durationMinutes,
        'packageName': lock.packageName,
        'appName': lock.appName,
        'strictMode': lock.strictMode,
      });
    } catch (e) {
      print('Alarm schedule failed: $e');
    }
  }

  Future<void> _cancelAlarm(ScheduledLock lock) async {
    // iOS does not support AlarmManager, so we skip this
    if (Platform.isIOS) return;
    
    print('Alarm cancel request: ${lock.appName} (${lock.hour}:${lock.minute})');
    try {
      await platform.invokeMethod('cancelAlarm', {
        'id': _getAlarmId(lock),
      });
    } catch (e) {
      print('Alarm cancel failed: $e');
    }
  }

  void _checkMissedScheduledLocks() async {
    print('=== Checking missed scheduled locks ===');
    final now = DateTime.now();
    final currentWeekday = now.weekday;
    final currentTimeInMinutes = now.hour * 60 + now.minute;
    final today = DateTime(now.year, now.month, now.day);
    // Check if phone lock is temporarily suppressed
    int suppressedUntilMinutes = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      suppressedUntilMinutes = prefs.getInt('phoneLockSuppressedUntilMinutes') ?? 0;
    } catch (_) {}

    for (int i = 0; i < scheduledLocks.length; i++) {
      var scheduled = scheduledLocks[i];
      
      if (!scheduled.isEnabled) continue;
      
      if (!scheduled.weekdays.contains(currentWeekday)) continue;
      
      final scheduledTimeInMinutes = scheduled.hour * 60 + scheduled.minute;
      
      // Check if scheduled time has passed today (within duration window)
      if (currentTimeInMinutes >= scheduledTimeInMinutes && 
          currentTimeInMinutes < scheduledTimeInMinutes + scheduled.durationMinutes) {
        
        // Skip if phone lock is suppressed
        if (scheduled.packageName == AppConstants.phoneLockPackageName &&
            suppressedUntilMinutes > 0 &&
            (DateTime.now().millisecondsSinceEpoch ~/ 60000) < suppressedUntilMinutes) {
          print('Phone lock suppressed - Skipping missed lock execution');
          continue;
        }
        
        // Check if already executed today
        final lastExecDate = scheduled.lastExecutedDate;
        if (lastExecDate != null && 
            lastExecDate.year == today.year && 
            lastExecDate.month == today.month && 
            lastExecDate.day == today.day) {
          // Already executed today - skip
          continue;
        }
        
        // Check if already locked
        final existingLockedApps = lockedApps.where((app) => 
          app.packageName == scheduled.packageName
        ).toList();
        
        final isAlreadyLocked = existingLockedApps.any((app) => 
          app.unlockTime.isAfter(now)
        );
        
        if (!isAlreadyLocked) {
          // Remove existing expired lock if any
          setState(() {
            lockedApps.removeWhere((app) => 
              app.packageName == scheduled.packageName && 
              !app.unlockTime.isAfter(now)
            );
          });
          
          // Check permissions
          try {
            if (Platform.isIOS) {
               // iOS checks handled elsewhere or not needed here
            } else {
              final dynamic result = await platform.invokeMethod('checkPermissions');
              final bool? hasPermissions = result as bool?;
              if (hasPermissions != true) {
                print('Missed lock failed: No permission - ${scheduled.appName}');
                continue;
              }
            }
          } catch (e) {
            print('Permission check error: $e');
            continue;
          }
          
          // Execute scheduled lock (calculate remaining time)
          final minutesSinceScheduled = currentTimeInMinutes - scheduledTimeInMinutes;
          final remainingMinutes = (scheduled.durationMinutes - minutesSinceScheduled).clamp(0, scheduled.durationMinutes);
          
          if (remainingMinutes > 0) {
            setState(() {
              // Double check duplicates before adding
              final stillLocked = lockedApps.any((app) => 
                app.packageName == scheduled.packageName && 
                app.unlockTime.isAfter(now)
              );
              
              if (!stillLocked) {
                lockedApps.add(LockedApp(
                  name: scheduled.appName,
                  icon: scheduled.packageName == AppConstants.phoneLockPackageName 
                      ? Icons.phone_locked 
                      : Icons.block,
                  iconBytes: scheduled.iconBytes,
                  unlockTime: now.add(Duration(minutes: remainingMinutes)),
                  packageName: scheduled.packageName,
                  strictMode: scheduled.strictMode,
                ));
                
                // Update last execution time
                scheduledLocks[i] = scheduled.copyWith(lastExecutedDate: now);
              }
            });
            
            _saveLockedApps();
            _saveScheduledLocks();
            _updateBlockingService();
            
            print('Missed lock executed: ${scheduled.appName} ($remainingMinutes min)');
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('⏰ ${scheduled.appName} Scheduled Lock Active ($remainingMinutes min)'),
                  backgroundColor: Colors.orange.shade700,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          }
        }
      }
    }
    print('Missed lock check complete');
  }



  Future<void> _selectAppsFirst() async {
    try {
      print('=== Step 1: Select Apps ===');

      // iOS Handling
      if (Platform.isIOS) {
        // 1. Request Permission
        final bool? authStatus = await platform.invokeMethod('checkAuthStatus');
        if (authStatus != true) {
          final bool? granted = await platform.invokeMethod('requestAuthorization');
          if (granted != true) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Screen Time permission required. Please enable it in Settings.'),
                backgroundColor: Colors.red,
              ),
            );
            return;
          }
        }

        // 2. Open App Picker
        final dynamic picked = await platform.invokeMethod('showAppPicker');
        if (picked is Map) {
          final int apps = (picked['apps'] ?? 0) as int;
          final int categories = (picked['categories'] ?? 0) as int;
          final int domains = (picked['domains'] ?? 0) as int;
          final int total = apps + categories + domains;
          
          if (!mounted) return;

          final List<Map<String, String>> dummyApp = [{
            'packageName': 'ios_selected_apps',
            'appName': total > 0 ? 'Selected Apps (iOS) • $total' : 'Selected Apps (iOS)',
          }];
          _selectTimeSecond(dummyApp);
        } else if (picked == true) {
          // iOS security restriction: cannot retrieve selected app list.
          // Create a dummy "iOS Blocked Apps" list to proceed.
          if (!mounted) return;
          final List<Map<String, String>> dummyApp = [{
            'packageName': 'ios_selected_apps',
            'appName': 'Selected Apps (iOS)',
          }];
          _selectTimeSecond(dummyApp);
        }
        return;
      }

      // Android Handling: Check Permissions
      final bool? hasPermissions =
          await platform.invokeMethod('checkPermissions');
      if (hasPermissions != true) {
        if (!mounted) return;
        final result = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Permission Required', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            content: const Text(
              'Usage Access permission is required for App Lock.',
              style: TextStyle(color: Colors.black87),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Settings', style: TextStyle(color: Colors.blue)),
              ),
            ],
          ),
        );

        if (result == true) {
          await platform.invokeMethod('requestPermissions');
        }
        return;
      }

      // Get App List
      final List<dynamic>? apps;
      try {
        apps = await platform.invokeMethod('getInstalledApps') as List<dynamic>?;
      } catch (e) {
        print('Error getting app list: $e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load app list: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
        return;
      }
      
      if (apps == null || apps.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No installed apps found.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Exclude Gmanba and core system apps
      final filteredApps = AppUtils.filterApps(apps);

      // Select Apps from Bottom Sheet
      if (!mounted) return;
      
      // Extract package names of currently locked apps
      final lockedPackageNames = lockedApps
          .where((app) => app.unlockTime.isAfter(DateTime.now()))
          .map((app) => app.packageName)
          .toSet();
      
      final selectedApps = await showModalBottomSheet<List<Map<String, dynamic>>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        isDismissible: true,
        enableDrag: true,
        builder: (context) => AppSelectorBottomSheet(
          apps: filteredApps,
          lockedPackageNames: lockedPackageNames,
        ),
      );

      if (selectedApps == null || selectedApps.isEmpty) {
        print('App selection cancelled');
        return;
      }

      print('Selected Apps: ${selectedApps.length}');

      // Step 2: Proceed to Time Selection
      if (!mounted) return;
      _selectTimeSecond(selectedApps);
    } catch (e) {
      print('Error in _selectAppsFirst: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  // Step 2: Select Time
  Future<void> _selectTimeSecond(List<Map<String, dynamic>> selectedApps) async {
    try {
      print('=== Step 2: Time Selection ===');

      if (!mounted) return;
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => _TimePickerDialog(
          onConfirm: (mins, strict) => Navigator.pop(context, {'minutes': mins, 'strictMode': strict}),
        ),
      );

      if (result == null) {
        print('Time selection cancelled');
        return;
      }

      final minutes = result['minutes'] as int;
      final isStrictMode = result['strictMode'] as bool;

      if (minutes <= 0) {
        print('Invalid time selection');
        return;
      }

      print('Selected Time: $minutes min, Strict Mode: $isStrictMode');

      // Update UI after frame
      SchedulerBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;

        print('=== Step 3: Add Apps and Save ===');

        int addedCount = 0;
        final List<String> skipped = [];
        final now = DateTime.now();
        setState(() {
          for (var app in selectedApps) {
            final name = app['appName'] as String? ?? 'Unknown App';
            final pkgName = app['packageName'] as String? ?? '';

            final bool isCurrentlyLocked = lockedApps.any(
              (existing) => existing.packageName == pkgName && existing.unlockTime.isAfter(now),
            );
            if (isCurrentlyLocked) {
              skipped.add(name);
              continue;
            }
            lockedApps.removeWhere(
              (existing) => existing.packageName == pkgName && !existing.unlockTime.isAfter(now),
            );

            lockedApps.add(LockedApp(
              name: name,
              icon: Icons.block,
              iconBytes: app['icon'] as Uint8List?,
              unlockTime: DateTime.now().add(Duration(minutes: minutes)),
              packageName: pkgName,
              strictMode: isStrictMode,
            ));

            print('- Added: $name');
            addedCount++;
          }
        });

        await _saveLockedApps();

        // Step 4: Update Blocking Service
        print('=== Step 4: Update Blocking Service ===');
        await _updateBlockingService();

        if (mounted) {
          final strictMsg = isStrictMode ? '\n(Strict Mode Active)' : '';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$addedCount apps locked for $minutes min!$strictMsg'),
              duration: const Duration(seconds: 2),
              backgroundColor: isStrictMode ? Colors.red.shade900 : null,
            ),
          );
          if (skipped.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Skipped (Already Locked): ${skipped.join(', ')}'),
                backgroundColor: Colors.orange.shade700,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }

        print('=== Done ===');
      });
    } catch (e) {
      print('Error in _selectTimeSecond: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _editScheduledLock(int index) async {
    // iOS: Permission check handled by FamilyControls
    if (!Platform.isIOS) {
      // Check permissions
      try {
        final bool? hasPermissions = await platform.invokeMethod('checkPermissions');
        if (hasPermissions != true) {
          if (!mounted) return;
          final result = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Permission Required', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              content: const Text(
                'Usage Access permission is required to edit scheduled locks.',
                style: TextStyle(color: Colors.black87),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Settings', style: TextStyle(color: Colors.blue)),
                ),
              ],
            ),
          );

          if (result == true) {
            await platform.invokeMethod('requestPermissions');
          }
          return;
        }
      } catch (e) {
        print('Error checking permissions: $e');
        return;
      }
    }
    
    final lock = scheduledLocks[index];
    
    // 해당 앱(또는 폰 잠금)의 다른 예약과 겹치지 않도록 비활성화된 요일 계산
    List<int> disabledWeekdays = scheduledLocks
        .asMap()
        .entries
        .where((entry) => 
            entry.value.packageName == lock.packageName && 
            entry.key != index) // 현재 수정 중인 예약은 제외
        .expand((entry) => entry.value.weekdays)
        .toList();
    
    // 현재 잠금 상태 확인
    final isCurrentlyLocked = lockedApps.any((app) => 
      app.packageName == lock.packageName && 
      app.unlockTime.isAfter(DateTime.now())
    );
    
    if (!mounted) return;
    final scheduleData = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => ScheduleLockScreen(
          initialWeekdays: lock.weekdays,
          initialHour: lock.hour,
          initialMinute: lock.minute,
          initialDuration: lock.durationMinutes,
          initialStrictMode: lock.strictMode,
          isCurrentlyLocked: isCurrentlyLocked,
          isPhoneLockMode: lock.packageName == AppConstants.phoneLockPackageName,
          disabledWeekdays: disabledWeekdays,
        ),
      ),
    );

    if (scheduleData == null) return;

    if (scheduleData['delete'] == true) {
      await _cancelAlarm(scheduledLocks[index]);
      setState(() {
        scheduledLocks.removeAt(index);
      });
      await _saveScheduledLocks();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${lock.appName} schedule deleted.'),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // 변경 여부 확인 및 자동 활성화 로직
    bool shouldEnable = lock.isEnabled;
    if (!shouldEnable) {
      // 비활성화 상태였다면, 설정이 변경되었는지 확인
      final oldWeekdays = Set.from(lock.weekdays);
      final newWeekdays = Set.from(scheduleData['weekdays']);
      
      final bool isChanged = 
          lock.hour != scheduleData['hour'] ||
          lock.minute != scheduleData['minute'] ||
          lock.durationMinutes != scheduleData['duration'] ||
          lock.strictMode != (scheduleData['strictMode'] ?? false) ||
          oldWeekdays.length != newWeekdays.length ||
          !oldWeekdays.containsAll(newWeekdays);
          
      if (isChanged) {
        shouldEnable = true; // 변경사항이 있으면 자동으로 활성화
      }
    }

    // 수정된 예약 객체 미리 생성
    final newLock = ScheduledLock(
      appName: lock.appName,
      packageName: lock.packageName,
      weekdays: scheduleData['weekdays'],
      hour: scheduleData['hour'],
      minute: scheduleData['minute'],
      durationMinutes: scheduleData['duration'],
      strictMode: scheduleData['strictMode'] ?? false,
      isEnabled: shouldEnable,
      lastExecutedDate: null, // 수정 후 다시 실행 가능하게
      iconBytes: lock.iconBytes,
    );

    // 즉시 잠금 경고 팝업 (현재 시간이 예약 시간에 포함될 경우) - 저장 전 확인
    bool shouldProceed = true;
    if (mounted && newLock.isEnabled) {
      final now = DateTime.now();
      final currentMinutes = now.hour * 60 + now.minute;
      final startMinutes = newLock.hour * 60 + newLock.minute;
      final endMinutes = startMinutes + newLock.durationMinutes;
      
      if (newLock.weekdays.contains(now.weekday) && 
          currentMinutes >= startMinutes && 
          currentMinutes < endMinutes) {
          
          shouldProceed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('⚠️ Immediate Lock Alert', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              content: const Text(
                'The modified schedule includes the current time.\nClicking Confirm will start the lock immediately.\nCancel to discard changes.',
                style: TextStyle(color: Colors.black87),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(AppLocalizations.of(context)!.cancel, style: TextStyle(color: Colors.grey.shade600)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(AppLocalizations.of(context)!.confirm, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ) ?? false;
      }
    }

    if (!shouldProceed) {
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Schedule edit cancelled.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    // Cancel existing alarm
    await _cancelAlarm(scheduledLocks[index]);

    setState(() {
      scheduledLocks[index] = newLock;
    });

    // Register new alarm (only if enabled)
    if (scheduledLocks[index].isEnabled) {
      await _scheduleAlarm(scheduledLocks[index]);
    }
    
    await _saveScheduledLocks();

    // Check immediate lock
    if (mounted && scheduledLocks[index].isEnabled) {
       _checkMissedScheduledLocks();
    }

    if (mounted) {
      String message = isCurrentlyLocked
          ? '${lock.appName} schedule updated!\n(Current lock remains, next schedule will apply)'
          : '${lock.appName} schedule updated!';
          
      if (!lock.isEnabled && shouldEnable) {
        message = '${lock.appName} schedule updated and auto-enabled.';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.orange.shade700,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _removeLockedApp(int index) async {
    setState(() {
      lockedApps.removeAt(index);
    });
    await _saveLockedApps();
    await _updateBlockingService();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        toolbarHeight: 0, // AppBar 숨김
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // 메인 콘텐츠
          Padding(
            padding: const EdgeInsets.only(bottom: 240), // 하단 바 공간 확보 (Ad + Nav)
            child: Column(
              children: [
                Expanded(
                  child: _selectedIndex == 0 ? _buildCurrentLocksTab() : _buildScheduledLocksTab(),
                ),
              ],
            ),
          ),
          
          // 하단 네비게이션 및 추가 버튼
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Add Lock Button (Show only on current lock tab or always)
                        // Floating above the bottom bar
                        if (_selectedIndex != 2) // When not in Phone Lock screen
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: ElevatedButton(
                                onPressed: () {
                                   if (_selectedIndex == 0) {
                                     _selectAppsFirst();
                                   } else if (_selectedIndex == 1) {
                                     _addScheduledLock();
                                   }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF9FE801), // Lime Green
                                  foregroundColor: Colors.black,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(28),
                                  ),
                                ),
                                child: Text(
                                  AppLocalizations.of(context)!.addLock,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // Bottom Tab Buttons
                        Container(
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 20,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildBottomTabButton(0, AppLocalizations.of(context)!.nowLock, 'nowlock'),
                              _buildBottomTabButton(1, AppLocalizations.of(context)!.scheduleLock, 'schedule'),
                              _buildBottomTabButton(2, AppLocalizations.of(context)!.phoneLock, 'phonelock'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Ad Banner
                  if (_isBannerAdReady)
                    Container(
                      alignment: Alignment.center,
                      width: _bannerAd!.size.width.toDouble(),
                      height: _bannerAd!.size.height.toDouble(),
                      margin: const EdgeInsets.only(top: 16, bottom: 8),
                      child: AdWidget(ad: _bannerAd!),
                    )
                  else
                    const SizedBox(height: 32), // Default bottom padding
                ],
              ),
            ),
          ),
          
          // Loading Overlay
          if (_isLoading)
            Container(
              color: Colors.white,
              child: const Center(
                child: CircularProgressIndicator(color: Color(0xFF9FE801)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomTabButton(int index, String label, String iconPrefix) {
    final isSelected = _selectedIndex == index;
    // Phone Lock button has no separate selection state, executes or shows state on tap
    // But displayed as 3rd tab in UI
    
    // Determine Icon
    String iconPath;
    if (index == 2) { // Phone Lock
      final isPhoneLocked = lockedApps.any((app) => app.packageName == AppConstants.phoneLockPackageName);
      iconPath = isPhoneLocked ? 'assets/icon/phonelocktrue.svg' : 'assets/icon/phonelockfalse.svg';
    } else {
      iconPath = isSelected ? 'assets/icon/${iconPrefix}true.svg' : 'assets/icon/${iconPrefix}false.svg';
    }

    return GestureDetector(
      onTap: () {
        if (index == 2) {
          _chooseAndStartPhoneLock();
        } else {
          setState(() => _selectedIndex = index);
        }
      },
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.black : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(
                  iconPath,
                  width: 24,
                  height: 24,
                  colorFilter: ColorFilter.mode(
                    isSelected ? Colors.white : Colors.grey,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: isSelected ? Colors.white : Colors.grey,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
            // Badge (List count)
            if (index == 0 && lockedApps.isNotEmpty)
              Positioned(
                top: -8,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    '${lockedApps.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            if (index == 1 && scheduledLocks.isNotEmpty)
              Positioned(
                top: -8,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    '${scheduledLocks.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatRemainingTime(BuildContext context, Duration duration) {
    if (duration.isNegative) return AppLocalizations.of(context)!.unlocked;
    
    final local = AppLocalizations.of(context)!;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    
    final h = duration.inHours;
    final m = duration.inMinutes % 60;
    final s = duration.inSeconds % 60;
    
    String hPart = '';
    String mPart = '';
    String sPart = '';
    
    if (h > 0) {
      hPart = isKo ? '$h${local.hours}' : '$h ${local.hours}';
      if (m > 0) {
        mPart = isKo ? '$m${local.minutes}' : '$m ${local.minutes}';
      }
      return '$hPart $mPart ${local.remaining}'.replaceAll('  ', ' ').trim();
    } else {
      if (m > 0) {
        mPart = isKo ? '$m${local.minutes}' : '$m ${local.minutes}';
      }
      if (s > 0 || m == 0) {
        sPart = isKo ? '$s${local.seconds}' : '$s ${local.seconds}';
      }
      return '$mPart $sPart ${local.remaining}'.replaceAll('  ', ' ').trim();
    }
  }

  Widget _buildCurrentLocksTab() {
    return Column(
        children: [
          // 제목
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                lockedApps.isEmpty ? 'No Locked Apps' : '${lockedApps.length} Apps Locked',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
          ),
          // 앱 목록
          Expanded(
            child: lockedApps.isEmpty
                ? Center(
                    child: Text(
                      'Press "Add Lock" to start',
                      style: TextStyle(color: Colors.grey.shade400),
                    ),
                  )
                : ListView.builder(
                    itemCount: lockedApps.length,
                    itemBuilder: (context, index) {
                      final app = lockedApps[index];
                      final remainingTime =
                          app.unlockTime.difference(DateTime.now());

                      return ListTile(
                        leading: SizedBox(
                          width: 40,
                          height: 40,
                          child: app.packageName == AppConstants.phoneLockPackageName
                              ? Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.all(8),
                                  child: SvgPicture.asset(
                                    'assets/icon/Devices/phone.svg',
                                    width: 24,
                                    height: 24,
                                  ),
                                )
                              : app.iconBytes != null
                                  ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(
                                    app.iconBytes!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) =>
                                        Icon(app.icon, color: Colors.green),
                                  ),
                                )
                              : Icon(app.icon, color: Colors.green),
                        ),
                        title: Text(
                          app.name,
                          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          _formatRemainingTime(context, remainingTime),
                          style: TextStyle(
                            color: remainingTime.isNegative
                                ? Colors.green
                                : Colors.orange,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.delete_forever,
                            color: Colors.redAccent,
                          ),
                          tooltip: 'Unlock Forcefully',
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                backgroundColor: Colors.white,
                                title: const Text('Unlock Confirmation', style: TextStyle(color: Colors.black)),
                                content: const Text(
                                  'Are you sure you want to forcefully unlock this app?\n(For testing and emergency use)',
                                  style: TextStyle(color: Colors.black87),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                    child: const Text('Unlock', style: TextStyle(color: Colors.white)),
                                  ),
                                ],
                              ),
                            );

                            if (confirm == true) {
                              await _removeLockedApp(index);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Lock for ${app.name} has been released.'),
                                    backgroundColor: Colors.red.shade700,
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
          // Button removed (replaced by Add Lock button)
        ],
      );
  }

  Widget _buildScheduledLocksTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              scheduledLocks.isEmpty ? 'No Scheduled Locks' : '${scheduledLocks.length} Scheduled',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
        ),
        // 예약 잠금 강제 종료 금지 안내 제거됨 (사용자 요청)

        if (scheduledLocks.isNotEmpty) const SizedBox(height: 12),
        Expanded(
          child: scheduledLocks.isEmpty
              ? Center(
                  child: Text(
                    'Press "Add Lock" to start',
                    style: TextStyle(color: Colors.grey.shade400),
                  ),
                )
              : ListView.builder(
                  itemCount: scheduledLocks.length,
                  itemBuilder: (context, index) {
                    final lock = scheduledLocks[index];
                    final weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                    final selectedDays = lock.weekdays
                        .map((w) => weekdayNames[w - 1])
                        .join(', ');

                    final isPhoneLock = lock.packageName == AppConstants.phoneLockPackageName;

                    return ListTile(
                      leading: SizedBox(
                        width: 40,
                        height: 40,
                        child: isPhoneLock
                            ? Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.all(8),
                                child: SvgPicture.asset(
                                   'assets/icon/Devices/phone.svg',
                                   width: 24,
                                   height: 24,
                                 ),
                              )
                            : lock.iconBytes != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.memory(
                                      lock.iconBytes!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) =>
                                          const Icon(Icons.schedule, color: Colors.orange),
                                    ),
                                  )
                                : const Icon(Icons.schedule, color: Colors.orange),
                      ),
                      title: Text(
                        lock.appName,
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '$selectedDays\n${lock.hour.toString().padLeft(2, '0')}:${lock.minute.toString().padLeft(2, '0')} - ${lock.durationMinutes}m duration',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      trailing: CupertinoSwitch(
                        value: lock.isEnabled,
                        onChanged: (bool value) async {
                          setState(() {
                            scheduledLocks[index] = ScheduledLock(
                              appName: lock.appName,
                              packageName: lock.packageName,
                              weekdays: lock.weekdays,
                              hour: lock.hour,
                              minute: lock.minute,
                              durationMinutes: lock.durationMinutes,
                              strictMode: lock.strictMode,
                              isEnabled: value,
                              lastExecutedDate: lock.lastExecutedDate,
                              iconBytes: lock.iconBytes,
                            );
                          });
                          await _saveScheduledLocks();

                          if (value) {
                            await _scheduleAlarm(scheduledLocks[index]);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('${lock.appName} Enabled.'),
                                  duration: const Duration(seconds: 1),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } else {
                            await _cancelAlarm(scheduledLocks[index]);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('${lock.appName} Disabled.'),
                                  duration: const Duration(seconds: 1),
                                  backgroundColor: Colors.grey,
                                ),
                              );
                            }
                          }
                        },
                      ),
                      onTap: () => _editScheduledLock(index),
                    );
                  },
                ),
        ),
        // 하단 버튼 제거 (Add Lock 버튼으로 대체)
      ],
    );
  }

  Future<void> _addScheduledLock() async {
    // Step 1: Select App
    try {
      if (Platform.isIOS) {
        // iOS permission check (AuthStatus)
        final bool? authStatus = await platform.invokeMethod('checkAuthStatus');
        if (authStatus != true) {
           await platform.invokeMethod('requestAuthorization');
           return;
        }
        
        // iOS fixed to "Selected Apps" without app selection
        if (!mounted) return;

        // Calculate existing scheduled weekdays
        final occupiedWeekdays = scheduledLocks
            .where((lock) => lock.packageName == 'ios_selected_apps')
            .expand((lock) => lock.weekdays)
            .toList();

        final scheduleData = await Navigator.push<Map<String, dynamic>>(
          context,
          MaterialPageRoute(builder: (context) => ScheduleLockScreen(
            disabledWeekdays: occupiedWeekdays,
          )),
        );

        if (scheduleData == null) return;

        // Step 3: Add Schedule
        setState(() {
          scheduledLocks.add(ScheduledLock(
            appName: 'Selected Apps (iOS)',
            packageName: 'ios_selected_apps',
            weekdays: scheduleData['weekdays'],
            hour: scheduleData['hour'],
            minute: scheduleData['minute'],
            durationMinutes: scheduleData['duration'],
            strictMode: scheduleData['strictMode'] ?? false,
          ));
        });

        // Alarm registration (Skipped for iOS as AlarmManager is not supported, relies on Timer)
        if (Platform.isAndroid) {
          await _scheduleAlarm(scheduledLocks.last);
        }

        await _saveScheduledLocks();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('iOS Schedule Lock added! (Works only when app is running)'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final bool? hasPermissions = await platform.invokeMethod('checkPermissions');
      if (hasPermissions != true) {
        if (!mounted) return;
        final result = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Permission Required', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            content: const Text(
              'Usage Access permission is required for Scheduled Lock.',
              style: TextStyle(color: Colors.black87),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Settings', style: TextStyle(color: Colors.blue)),
              ),
            ],
          ),
        );

        if (result == true) {
          await platform.invokeMethod('requestPermissions');
        }
        return;
      }

      if (!mounted) return;
      
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                  strokeWidth: 2,
                ),
              ),
              const SizedBox(width: 16),
              const Text('Loading apps...', style: TextStyle(color: Colors.black87)),
            ],
          ),
        ),
      );

      try {
        final List<dynamic>? apps = await platform.invokeMethod('getInstalledApps').timeout(
          const Duration(seconds: 10),
          onTimeout: () => null,
        );
        
        if (!mounted) return;
        Navigator.pop(context); // Close loading dialog

        if (apps == null || apps.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No installed apps found.')),
          );
          return;
        }

        // Exclude Gmanba app and core system apps
        final filteredApps = AppUtils.filterApps(apps);

        if (!mounted) return;
        final selectedApp = await showModalBottomSheet<Map<String, dynamic>>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => SingleAppSelectorBottomSheet(apps: filteredApps),
        );

        if (selectedApp == null) return;

        // Step 2: Select Weekday, Hour, Minute
        if (!mounted) return;
        
        // Calculate existing scheduled weekdays
        final occupiedWeekdays = scheduledLocks
            .where((lock) => lock.packageName == selectedApp['packageName'])
            .expand((lock) => lock.weekdays)
            .toList();

        final scheduleData = await Navigator.push<Map<String, dynamic>>(
          context,
          MaterialPageRoute(builder: (context) => ScheduleLockScreen(
            disabledWeekdays: occupiedWeekdays,
          )),
        );

        if (scheduleData == null) return;

        // Step 3: Prepare to add schedule
        final newLock = ScheduledLock(
            appName: selectedApp['appName'] as String,
            packageName: selectedApp['packageName'] as String,
            weekdays: scheduleData['weekdays'],
            hour: scheduleData['hour'],
            minute: scheduleData['minute'],
            durationMinutes: scheduleData['duration'],
            strictMode: scheduleData['strictMode'] ?? false,
            iconBytes: selectedApp['icon'] as Uint8List?,
        );

        // Immediate lock warning popup (if current time is within schedule) - Confirm before saving
        bool shouldProceed = true;
        if (mounted && newLock.isEnabled) {
          final now = DateTime.now();
          final currentMinutes = now.hour * 60 + now.minute;
          final startMinutes = newLock.hour * 60 + newLock.minute;
          final endMinutes = startMinutes + newLock.durationMinutes;
          
          if (newLock.weekdays.contains(now.weekday) && 
              currentMinutes >= startMinutes && 
              currentMinutes < endMinutes) {
              
              shouldProceed = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (context) => AlertDialog(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: const Text('⚠️ Immediate Lock Warning', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  content: const Text(
                    'The scheduled time includes the current time.\nClicking Confirm will start the lock immediately.\nIf you cancel, the schedule will not be saved.',
                    style: TextStyle(color: Colors.black87),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Confirm', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ) ?? false;
          }
        }

        if (!shouldProceed) {
             if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Schedule addition cancelled.'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          return;
        }

        // Confirmed: Save and Schedule
        setState(() {
          scheduledLocks.add(newLock);
        });

        // Register Alarm
        await _scheduleAlarm(newLock);

        await _saveScheduledLocks();
        
        // Immediately check if the newly added schedule applies to current time
        // (e.g. Current 17:40, Set 17:40 Start -> Immediate lock should trigger)
        _checkMissedScheduledLocks();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${selectedApp['appName']} Schedule Lock added!'),
              backgroundColor: Colors.orange.shade700,
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        // Close loading dialog if open
        try {
          Navigator.pop(context);
        } catch (_) {}
        
        print('Error loading app list: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load app list: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } catch (e) {
      print('Error adding scheduled lock: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}

// App Selection Bottom Sheet
class AppSelectorBottomSheet extends StatefulWidget {
  final List<dynamic> apps;
  final Set<String> lockedPackageNames;

  const AppSelectorBottomSheet({super.key, 
    required this.apps,
    this.lockedPackageNames = const {},
  });

  @override
  State<AppSelectorBottomSheet> createState() => _AppSelectorBottomSheetState();
}

class _AppSelectorBottomSheetState extends State<AppSelectorBottomSheet> {
  Set<int> selectedIndices = {};
  String searchQuery = '';
  List<dynamic> filteredApps = [];

  @override
  void initState() {
    super.initState();
    filteredApps = List.from(widget.apps);
    _sortApps();
  }

  void _sortApps() {
    filteredApps.sort((a, b) {
      final nameA = (a['name'] ?? '').toString().toLowerCase();
      final nameB = (b['name'] ?? '').toString().toLowerCase();
      return nameA.compareTo(nameB);
    });
  }

  void _filterApps(String query) {
    setState(() {
      searchQuery = query;
      if (query.isEmpty) {
        filteredApps = List.from(widget.apps);
      } else {
        final queryLower = query.toLowerCase();
        
        filteredApps = widget.apps.where((app) {
          final name = (app['name'] ?? '').toString().toLowerCase();
          
          // Normal Search
          if (name.contains(queryLower)) return true;
          
          return false;
        }).toList();
      }
      _sortApps();
      // Clear selection when search results change
      selectedIndices.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag Handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Select Apps to Block',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      '${selectedIndices.length} Selected',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  onChanged: _filterApps,
                  style: const TextStyle(color: Colors.black),
                  decoration: InputDecoration(
                    hintText: 'Search apps (name)',
                    hintStyle: TextStyle(color: Colors.grey.shade500),
                    prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
                    suffixIcon: searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, color: Colors.grey.shade400),
                            onPressed: () {
                              _filterApps('');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Divider(color: Colors.grey.shade200, height: 1),
              // App List
              Expanded(
                child: filteredApps.isEmpty
                    ? Center(
                        child: Text(
                          'No results found',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: filteredApps.length,
                        itemBuilder: (context, index) {
                          final app = filteredApps[index];
                          final packageName = app['packageName'] as String? ?? '';
                          final isLocked = widget.lockedPackageNames.contains(packageName);
                          
                          // Find original index
                          final originalIndex = widget.apps.indexWhere(
                            (a) => a['packageName'] == packageName
                          );
                          final isSelected = selectedIndices.contains(originalIndex);

                    return ListTile(
                      leading: Stack(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isLocked
                                  ? Colors.grey.withOpacity(0.2)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: app['icon'] != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.memory(
                                      app['icon'] as Uint8List,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) =>
                                          Icon(
                                        Icons.apps,
                                        color: isLocked ? Colors.grey : Colors.green,
                                      ),
                                    ),
                                  )
                                : Icon(
                                    Icons.apps,
                                    color: isLocked ? Colors.grey : Colors.green,
                                  ),
                          ),
                          if (isLocked)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.lock,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Text(
                        app['name'] ?? 'Unknown',
                        style: TextStyle(
                          color: isLocked ? Colors.grey : Colors.black,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      subtitle: isLocked
                          ? const Text(
                              '🔒 Locked',
                              style: TextStyle(color: Colors.redAccent, fontSize: 12),
                            )
                          : null,
                      trailing: Checkbox(
                        value: isSelected,
                        activeColor: Colors.green,
                        onChanged: isLocked
                            ? null  // Locked apps cannot be selected
                            : (value) {
                                setState(() {
                                  if (value == true) {
                                    selectedIndices.add(originalIndex);
                                  } else {
                                    selectedIndices.remove(originalIndex);
                                  }
                                });
                              },
                      ),
                      onTap: isLocked
                          ? null  // Locked apps cannot be tapped
                          : () {
                              setState(() {
                                if (isSelected) {
                                  selectedIndices.remove(originalIndex);
                                } else {
                                  selectedIndices.add(originalIndex);
                                }
                              });
                            },
                    );
                  },
                ),
              ),
              // Bottom Buttons
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                child: SafeArea(
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 15),
                            backgroundColor: Colors.grey.shade200,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: selectedIndices.isEmpty
                              ? null
                              : () {
                                  final selected = selectedIndices
                                      .map((i) => {
                                            'appName': widget.apps[i]['name']
                                                as String,
                                            'packageName': widget.apps[i]
                                                ['packageName'] as String,
                                            'icon': widget.apps[i]['icon'],
                                          })
                                      .toList();
                                  Navigator.pop(context, selected);
                                },
                          style: ElevatedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 15),
                            backgroundColor: selectedIndices.isEmpty
                                ? Colors.grey.shade300
                                : Colors.green,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('Next'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Time Selection Dialog
class _TimePickerDialog extends StatefulWidget {
  final Function(int, bool) onConfirm;

  const _TimePickerDialog({required this.onConfirm});

  @override
  State<_TimePickerDialog> createState() => __TimePickerDialogState();
}

class __TimePickerDialogState extends State<_TimePickerDialog> {
  int selectedMinutes = AppConstants.minLockDurationMinutes;
  bool isStrictMode = false;
  static const platform = MethodChannel('com.jimoon.jamgltime/app_blocker');

  String _formatDuration(BuildContext context, int totalMinutes) {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    final local = AppLocalizations.of(context)!;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    
    String hPart = '';
    String mPart = '';
    
    if (h > 0) {
      hPart = isKo ? '$h${local.hours}' : '$h ${local.hours}';
    }
    if (m > 0 || h == 0) {
      mPart = isKo ? '$m${local.minutes}' : '$m ${local.minutes}';
    }
    
    if (h > 0 && m > 0) {
      return '$hPart $mPart';
    } else if (h > 0) {
      return hPart;
    } else {
      return mPart;
    }
  }

  Widget _buildDurationRichText(BuildContext context, int totalMinutes) {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    final local = AppLocalizations.of(context)!;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    
    List<InlineSpan> spans = [];
    
    // Style for numbers (Large)
    final numberStyle = const TextStyle(
      color: Colors.green,
      fontSize: 32,
      fontWeight: FontWeight.bold,
    );
    
    // Style for text (Small)
    final textStyle = const TextStyle(
      color: Colors.green,
      fontSize: 18, 
      fontWeight: FontWeight.bold,
    );

    if (h > 0) {
      spans.add(TextSpan(text: '$h', style: numberStyle));
      spans.add(TextSpan(text: isKo ? local.hours : ' ${local.hours}', style: textStyle));
      if (m > 0) {
        spans.add(const TextSpan(text: ' '));
      }
    }
    
    if (m > 0 || h == 0) {
      spans.add(TextSpan(text: '$m', style: numberStyle));
      spans.add(TextSpan(text: isKo ? local.minutes : ' ${local.minutes}', style: textStyle));
    }
    
    return Text.rich(
      TextSpan(children: spans),
      textAlign: TextAlign.center,
    );
  }

  String _formatEndTime(BuildContext context, int totalMinutes) {
    final now = DateTime.now();
    final end = now.add(Duration(minutes: totalMinutes));
    final timeStr = '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
    return AppLocalizations.of(context)!.endsAt(timeStr);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        AppLocalizations.of(context)!.setDuration,
        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDurationRichText(context, selectedMinutes),
            const SizedBox(height: 4),
            Text(
              _formatEndTime(context, selectedMinutes),
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            Slider(
              value: selectedMinutes.toDouble(),
              min: AppConstants.minLockDurationMinutes.toDouble(),
              max: AppConstants.maxLockDurationMinutes.toDouble(),
              divisions: AppConstants.maxLockDurationMinutes - AppConstants.minLockDurationMinutes,
              activeColor: Colors.green,
              inactiveColor: Colors.grey.shade300,
              label: _formatDuration(context, selectedMinutes),
              onChanged: (value) {
                if (value.toInt() != selectedMinutes) {
                  HapticFeedback.selectionClick();
                }
                setState(() {
                  selectedMinutes = value.toInt();
                });
              },
            ),
            const SizedBox(height: 20),
            // Quick Selection Buttons
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: AppConstants.quickTimeOptions
                  .map(
                    (mins) {
                      final isSelected = selectedMinutes == mins;
                      return ElevatedButton(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            selectedMinutes = mins;
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isSelected
                              ? Colors.green
                              : Colors.grey.shade200,
                          foregroundColor: isSelected
                              ? Colors.white
                              : Colors.black,
                          elevation: 0,
                        ),
                        child: Text(
                          _formatDuration(context, mins),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      );
                    },
                  )
                  .toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            AppLocalizations.of(context)!.cancel,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onConfirm(selectedMinutes, false); // isStrictMode always false
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text(
            'Confirm',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

// Single App Selection Bottom Sheet
class SingleAppSelectorBottomSheet extends StatefulWidget {
  final List<dynamic> apps;

  const SingleAppSelectorBottomSheet({super.key, required this.apps});

  @override
  State<SingleAppSelectorBottomSheet> createState() => _SingleAppSelectorBottomSheetState();
}

class _SingleAppSelectorBottomSheetState extends State<SingleAppSelectorBottomSheet> {
  String searchQuery = '';
  List<dynamic> filteredApps = [];

  @override
  void initState() {
    super.initState();
    filteredApps = List.from(widget.apps);
    _sortApps();
  }

  void _sortApps() {
    filteredApps.sort((a, b) {
      final nameA = (a['name'] ?? '').toString().toLowerCase();
      final nameB = (b['name'] ?? '').toString().toLowerCase();
      return nameA.compareTo(nameB);
    });
  }

  void _filterApps(String query) {
    setState(() {
      searchQuery = query;
      if (query.isEmpty) {
        filteredApps = List.from(widget.apps);
      } else {
        final queryLower = query.toLowerCase();
        
        filteredApps = widget.apps.where((app) {
          final name = (app['name'] ?? '').toString().toLowerCase();
          
          if (name.contains(queryLower)) return true;
          
          return false;
        }).toList();
      }
      _sortApps();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Select App for Schedule',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  onChanged: _filterApps,
                  style: const TextStyle(color: Colors.black),
                  decoration: InputDecoration(
                    hintText: 'Search apps (name)',
                    hintStyle: TextStyle(color: Colors.grey.shade500),
                    prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
                    suffixIcon: searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, color: Colors.grey.shade400),
                            onPressed: () {
                              _filterApps('');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Divider(color: Colors.grey.shade200, height: 1),
              Expanded(
                child: filteredApps.isEmpty
                    ? Center(
                        child: Text(
                          'No search results',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: filteredApps.length,
                        itemBuilder: (context, index) {
                          final app = filteredApps[index];
                    return ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: app['icon'] != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.memory(
                                  app['icon'] as Uint8List,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(
                                        color: Colors.orange.withOpacity(0.2),
                                        child: const Icon(Icons.apps, color: Colors.orange),
                                      ),
                                ),
                              )
                            : Container(
                                color: Colors.orange.withOpacity(0.2),
                                child: const Icon(Icons.apps, color: Colors.orange),
                              ),
                      ),
                      title: Text(
                        app['name'] ?? 'Unknown',
                        style: const TextStyle(color: Colors.black),
                      ),
                      onTap: () {
                        Navigator.pop(context, {
                          'appName': app['name'] as String,
                          'packageName': app['packageName'] as String,
                          'icon': app['icon'],
                        });
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// 예약 잠금 설정 화면 (전체 화면)
class ScheduleLockScreen extends StatefulWidget {
  final List<int>? initialWeekdays;
  final int? initialHour;
  final int? initialMinute;
  final int? initialDuration;
  final bool initialStrictMode; // Strict Mode 초기값
  final bool isCurrentlyLocked;
  final bool isPhoneLockMode;
  final List<int> disabledWeekdays;

  const ScheduleLockScreen({super.key, 
    this.initialWeekdays,
    this.initialHour,
    this.initialMinute,
    this.initialDuration,
    this.initialStrictMode = false,
    this.isCurrentlyLocked = false,
    this.isPhoneLockMode = false,
    this.disabledWeekdays = const [],
  });

  @override
  State<ScheduleLockScreen> createState() => _ScheduleLockScreenState();
}

class _ScheduleLockScreenState extends State<ScheduleLockScreen> {
  late Set<int> selectedWeekdays;
  late int selectedHour;
  late int selectedMinute;
  late int selectedDuration;
  
  // For Phone Lock Mode (End Time)
  late int selectedEndHour;
  late int selectedEndMinute;
  
  late bool isStrictMode;
  late bool isEditing;
  static const platform = MethodChannel('com.jimoon.jamgltime/app_blocker');

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    
    // 수정 모드일 때만 기존 값 사용하고, 새로 생성(초기화)일 때는 현재 시간 사용
    if (widget.initialHour != null && widget.initialMinute != null) {
      isEditing = true;
      selectedWeekdays = Set.from(widget.initialWeekdays ?? {});
      selectedHour = widget.initialHour!;
      selectedMinute = widget.initialMinute!;
      selectedDuration = widget.initialDuration ?? AppConstants.defaultScheduledDuration;
      
      // 최소 시간 보정 (기존 데이터 호환성)
      if (selectedDuration < AppConstants.minLockDurationMinutes) {
        selectedDuration = AppConstants.minLockDurationMinutes;
      }
      
      isStrictMode = widget.initialStrictMode;
    } else {
      isEditing = false;
      // 새로 추가하는 경우: 현재 시간 + 1분 (바로 시작되는 애매함 방지)
      final initTime = now.add(const Duration(minutes: 1));
      selectedWeekdays = Set.from(widget.initialWeekdays ?? {});
      selectedHour = initTime.hour;
      selectedMinute = initTime.minute;
      selectedDuration = widget.initialDuration ?? AppConstants.defaultScheduledDuration;
      isStrictMode = false;
    }
    
    // Initialize End Time based on Start Time + Duration
    final startDateTime = DateTime(now.year, now.month, now.day, selectedHour, selectedMinute);
    final endDateTime = startDateTime.add(Duration(minutes: selectedDuration));
    selectedEndHour = endDateTime.hour;
    selectedEndMinute = endDateTime.minute;
  }


  @override
  Widget build(BuildContext context) {
    final weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.isPhoneLockMode ? 'Phone Lock Settings' : 'Schedule Lock Settings', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: Colors.white,
                    title: const Text('Delete Confirmation', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    content: const Text('Are you sure you want to delete this schedule?', style: TextStyle(color: Colors.black87)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        child: const Text('Delete', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );

                if (confirm == true && mounted) {
                  Navigator.pop(context, {'delete': true});
                }
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 현재 잠금 상태 안내
                    if (widget.isCurrentlyLocked)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          border: Border.all(color: Colors.orange, width: 1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '💡 This app is currently locked. Modifications will apply from the next schedule, keeping the current lock active.',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      
                    // 요일 선택
                    const Text('Select Weekdays:', style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(7, (index) {
                          final weekday = index + 1;
                          final isSelected = selectedWeekdays.contains(weekday);
                          final isDisabled = widget.disabledWeekdays.contains(weekday);
                          
                          return GestureDetector(
                            onTap: isDisabled ? () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('This weekday is already occupied by another schedule for this app.'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            } : () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                if (isSelected) {
                                  selectedWeekdays.remove(weekday);
                                } else {
                                  selectedWeekdays.add(weekday);
                                }
                              });
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isDisabled 
                                    ? Colors.grey.shade300 
                                    : (isSelected ? Colors.orange : Colors.transparent),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isDisabled 
                                      ? Colors.grey.shade400 
                                      : (isSelected ? Colors.orange : Colors.grey.shade400),
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                weekdayNames[index],
                                style: TextStyle(
                                  color: isDisabled 
                                      ? Colors.grey.shade500 
                                      : (isSelected ? Colors.white : Colors.grey.shade600),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  decoration: isDisabled ? TextDecoration.lineThrough : null,
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    // 시간 선택
                    const Text('Start Time:', style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: CupertinoTheme(
                        data: const CupertinoThemeData(
                          textTheme: CupertinoTextThemeData(
                            dateTimePickerTextStyle: TextStyle(
                              color: Colors.black,
                              fontSize: 26,
                            ),
                          ),
                        ),
                        child: CupertinoDatePicker(
                          mode: CupertinoDatePickerMode.time,
                          use24hFormat: true,
                          // 날짜는 중요하지 않고 시간만 사용됨 (현재 날짜 기준)
                          initialDateTime: DateTime(
                            DateTime.now().year,
                            DateTime.now().month,
                            DateTime.now().day,
                            selectedHour,
                            selectedMinute,
                          ),
                          onDateTimeChanged: (DateTime newDateTime) {
                            HapticFeedback.selectionClick();
                            setState(() {
                              selectedHour = newDateTime.hour;
                              selectedMinute = newDateTime.minute;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    // 종료 시간 (모든 모드에서 사용)
                    const Text('End Time:', style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: CupertinoTheme(
                        data: const CupertinoThemeData(
                          textTheme: CupertinoTextThemeData(
                            dateTimePickerTextStyle: TextStyle(
                              color: Colors.black,
                              fontSize: 26,
                            ),
                          ),
                        ),
                        child: CupertinoDatePicker(
                          mode: CupertinoDatePickerMode.time,
                          use24hFormat: true,
                          initialDateTime: DateTime(
                            DateTime.now().year,
                            DateTime.now().month,
                            DateTime.now().day,
                            selectedEndHour,
                            selectedEndMinute,
                          ),
                          onDateTimeChanged: (DateTime newDateTime) {
                            HapticFeedback.selectionClick();
                            setState(() {
                              selectedEndHour = newDateTime.hour;
                              selectedEndMinute = newDateTime.minute;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            
            // 하단 확인 버튼
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: selectedWeekdays.isEmpty
                      ? null
                      : () {
                          // 시작 시간 보정 로직 제거 (사용자 요청: 현재 시간도 즉시 잠금 가능하게)
                          int adjustedHour = selectedHour;
                          int adjustedMinute = selectedMinute;
                          
                          int duration = 0;
                          
                          // 모든 모드에서 시작/종료 시간으로 duration 계산
                          int startMinutes = adjustedHour * 60 + adjustedMinute;
                          int endMinutes = selectedEndHour * 60 + selectedEndMinute;
                          
                          if (endMinutes <= startMinutes) {
                            // 다음날로 넘어감 (종료 시간이 시작 시간보다 이르거나 같으면 다음날로 간주)
                            endMinutes += 24 * 60;
                          }
                          
                          duration = endMinutes - startMinutes;
                          
                          // 최소 시간 보정
                          if (duration < AppConstants.minLockDurationMinutes) {
                            duration = AppConstants.minLockDurationMinutes;
                          }
                      
                          Navigator.pop(context, {
                            'weekdays': selectedWeekdays.toList(),
                            'hour': adjustedHour,
                            'minute': adjustedMinute,
                            'duration': duration,
                            'strictMode': false, // 사용자가 원하지 않아 항상 false로 고정
                          });
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: selectedWeekdays.isEmpty
                        ? Colors.grey.shade300
                        : (widget.isPhoneLockMode ? Colors.green : Colors.orange), // 폰 잠금은 녹색
                  ),
                  child: const Text(
                    'Confirm',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PermissionDialog extends StatefulWidget {
  const PermissionDialog({super.key});

  @override
  State<PermissionDialog> createState() => _PermissionDialogState();
}

class _PermissionDialogState extends State<PermissionDialog> with WidgetsBindingObserver {
  static const platform = MethodChannel('com.jimoon.jamgltime/app_blocker');
  Map<String, bool> _status = {
    'usage': false,
    'overlay': false,
    'alarm': false,
    'notification': false,
  };
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    try {
      final result = await platform.invokeMethod('checkPermissionStatus');
      if (mounted) {
        setState(() {
          _status = Map<String, bool>.from(result);
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error checking permissions: $e');
    }
  }

  bool get _allGranted => _status.values.every((v) => v);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Required Permissions',
        style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
      ),
      content: _isLoading
          ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!_allGranted)
                    const Text(
                      'Please grant the following permissions for the app to work correctly.\nTap each button to open Settings.',
                      style: TextStyle(color: Colors.black54, fontSize: 14),
                    )
                  else
                    const Text(
                      'All permissions granted.\nTap Confirm to start.',
                      style: TextStyle(color: Colors.green, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  const SizedBox(height: 24),
                  if (_status['usage'] == false) ...[
                    _PermissionRow(
                      icon: Icons.pie_chart_outline,
                      title: 'Usage Access',
                      subtitle: 'Required to detect running apps and block them.',
                      buttonLabel: 'Grant',
                      onTap: () => platform.invokeMethod('openPermissionScreen', {'type': 'usage'}),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_status['overlay'] == false) ...[
                    _PermissionRow(
                      icon: Icons.layers,
                      title: 'Display Over Other Apps',
                      subtitle: 'Required to show the block screen.',
                      buttonLabel: 'Grant',
                      onTap: () => platform.invokeMethod('openPermissionScreen', {'type': 'overlay'}),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_status['alarm'] == false) ...[
                    _PermissionRow(
                      icon: Icons.alarm,
                      title: 'Alarms & Reminders',
                      subtitle: 'Required for accurate scheduled locking.',
                      buttonLabel: 'Grant',
                      onTap: () => platform.invokeMethod('openPermissionScreen', {'type': 'alarm'}),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_status['notification'] == false) ...[
                    _PermissionRow(
                      icon: Icons.notifications_active,
                      title: 'Push Notifications',
                      subtitle: 'Required for lock/unlock notifications.',
                      buttonLabel: 'Grant',
                      onTap: () => platform.invokeMethod('openPermissionScreen', {'type': 'notification'}),
                    ),
                  ],
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () async {
            if (_allGranted) {
               Navigator.pop(context);
               final prefs = await SharedPreferences.getInstance();
               await prefs.setBool('permissions_checked', true);
            } else {
               ScaffoldMessenger.of(context).showSnackBar(
                 const SnackBar(content: Text('You must grant all permissions to use the app.')),
               );
            }
          },
          child: Text(
            'Confirm',
            style: TextStyle(
              color: _allGranted ? Colors.green : Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

// Permission Row Widget
class _PermissionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onTap;

  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.green, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: onTap,
                  icon: const Icon(Icons.settings, size: 18, color: Colors.green),
                  label: Text(
                    buttonLabel,
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.green,
                    side: const BorderSide(color: Colors.green),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 잠금 앱 데이터 모델
class LockedApp {
  final String name;
  final IconData icon;
  final Uint8List? iconBytes;
  final DateTime unlockTime;
  final String packageName;
  final bool strictMode;

  LockedApp({
    required this.name,
    this.icon = Icons.block,
    this.iconBytes,
    required this.unlockTime,
    required this.packageName,
    this.strictMode = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'unlockTime': unlockTime.millisecondsSinceEpoch,
        'packageName': packageName,
        'strictMode': strictMode,
        'iconBase64': iconBytes != null ? base64Encode(iconBytes!) : null,
      };

  factory LockedApp.fromJson(Map<String, dynamic> json) {
    // 하위 호환성: String(ISO8601) 또는 int(timestamp) 모두 처리
    DateTime parseTime(dynamic value) {
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      } else if (value is String) {
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      return DateTime.now();
    }

    Uint8List? decodedIcon;
    if (json['iconBase64'] != null) {
      try {
        decodedIcon = base64Decode(json['iconBase64']);
      } catch (e) {
        print('Error decoding icon: $e');
      }
    }

    return LockedApp(
      name: json['name'] ?? 'Unknown',
      icon: Icons.block,
      iconBytes: decodedIcon,
      unlockTime: parseTime(json['unlockTime']),
      packageName: json['packageName'] ?? '',
      strictMode: json['strictMode'] ?? false,
    );
  }
}

// 예약 잠금 데이터 모델
class ScheduledLock {
  final String appName;
  final String packageName;
  final List<int> weekdays; // 1=월, 2=화, ..., 7=일
  final int hour;
  final int minute;
  final int durationMinutes;
  final bool strictMode; // Strict Mode 추가
  final bool isEnabled; // 활성화 여부 토글
  final DateTime? lastExecutedDate; // 마지막 실행 날짜 (중복 방지)
  final Uint8List? iconBytes; // 앱 아이콘 데이터

  ScheduledLock({
    required this.appName,
    required this.packageName,
    required this.weekdays,
    required this.hour,
    required this.minute,
    required this.durationMinutes,
    this.strictMode = false,
    this.isEnabled = true,
    this.lastExecutedDate,
    this.iconBytes,
  });

  Map<String, dynamic> toJson() => {
        'appName': appName,
        'packageName': packageName,
        'weekdays': weekdays,
        'hour': hour,
        'minute': minute,
        'durationMinutes': durationMinutes,
        'strictMode': strictMode,
        'isEnabled': isEnabled,
        'lastExecutedDate': lastExecutedDate?.toIso8601String(),
        'iconBase64': iconBytes != null ? base64Encode(iconBytes!) : null,
      };

  factory ScheduledLock.fromJson(Map<String, dynamic> json) {
    Uint8List? decodedIcon;
    if (json['iconBase64'] != null) {
      try {
        decodedIcon = base64Decode(json['iconBase64']);
      } catch (e) {
        print('Error decoding scheduled lock icon: $e');
      }
    }

    return ScheduledLock(
        appName: json['appName'] ?? 'Unknown',
        packageName: json['packageName'] ?? '',
        weekdays: (json['weekdays'] as List<dynamic>).map((e) => e as int).toList(),
        hour: json['hour'] ?? 0,
        minute: json['minute'] ?? 0,
        durationMinutes: json['durationMinutes'] ?? 30,
        strictMode: json['strictMode'] ?? false,
        isEnabled: json['isEnabled'] ?? true,
        lastExecutedDate: json['lastExecutedDate'] != null 
            ? DateTime.parse(json['lastExecutedDate'] as String)
            : null,
        iconBytes: decodedIcon,
      );
  }

  // copyWith 메서드 추가
  ScheduledLock copyWith({
    String? appName,
    String? packageName,
    List<int>? weekdays,
    int? hour,
    int? minute,
    int? durationMinutes,
    bool? strictMode,
    bool? isEnabled,
    DateTime? lastExecutedDate,
    Uint8List? iconBytes,
  }) {
    return ScheduledLock(
      appName: appName ?? this.appName,
      packageName: packageName ?? this.packageName,
      weekdays: weekdays ?? this.weekdays,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      strictMode: strictMode ?? this.strictMode,
      isEnabled: isEnabled ?? this.isEnabled,
      lastExecutedDate: lastExecutedDate ?? this.lastExecutedDate,
      iconBytes: iconBytes ?? this.iconBytes,
    );
  }
}
