// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Gmanba';

  @override
  String get nowLock => 'Now Lock';

  @override
  String get scheduleLock => 'Schedule Lock';

  @override
  String get phoneLock => 'Phone Lock';

  @override
  String get addLock => '+ Add Lock';

  @override
  String get selectAppsToBlock => 'Select Apps to Block';

  @override
  String get selectedAppsUnavailable =>
      'Selected apps will be unavailable during the lock period';

  @override
  String get done => 'Done';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get lockDuration => 'Lock Duration';

  @override
  String get startLock => 'Start Lock';

  @override
  String get permissionRequired => 'Permission Required';

  @override
  String get permissionRequiredMessage =>
      'Please grant the following permissions for the app to function properly.';

  @override
  String get notificationPermission => 'Notification Permission';

  @override
  String get notificationPermissionDesc =>
      'Required for lock start/end notifications.';

  @override
  String get overlayPermission => 'Overlay Permission';

  @override
  String get usageAccess => 'Usage Access';

  @override
  String get grant => 'Grant';

  @override
  String get close => 'Close';

  @override
  String get emergencyUnlock => 'Emergency Unlock';

  @override
  String get emergencyUnlockConfirm => 'Are you sure you want to unlock?';

  @override
  String get searchAppsHint => 'Search apps (name)';

  @override
  String get noSearchResults => 'No search results';

  @override
  String get selectAppForSchedule => 'Select App for Schedule';

  @override
  String get activeLockWarningTitle => 'Wait! You have an active lock.';

  @override
  String get activeLockWarningBody =>
      'You cannot add a new lock while a lock is active.';

  @override
  String get strictMode => 'Strict Mode';

  @override
  String get strictModeDesc => 'Prevent unlocking until timer ends';

  @override
  String get selectWeekdays => 'Select Weekdays';

  @override
  String get startTime => 'Start Time';

  @override
  String get endTime => 'End Time';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get selected => 'Selected';

  @override
  String get unknown => 'Unknown';

  @override
  String get locked => 'Locked';

  @override
  String get hours => 'hours';

  @override
  String get minutes => 'minutes';

  @override
  String endsAt(Object time) {
    return 'Ends at $time';
  }

  @override
  String get setDuration => 'Set Duration';

  @override
  String get modifySchedule => 'Modify Schedule';

  @override
  String get addSchedule => 'Add Schedule';

  @override
  String get settings => 'Settings';

  @override
  String get language => 'Language';

  @override
  String get remaining => 'remaining';

  @override
  String get seconds => 'seconds';

  @override
  String get unlocked => 'Unlocked';
}
