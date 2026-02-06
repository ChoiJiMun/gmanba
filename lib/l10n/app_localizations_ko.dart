// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => '지만바';

  @override
  String get nowLock => '즉시 잠금';

  @override
  String get scheduleLock => '예약 잠금';

  @override
  String get phoneLock => '폰 잠금';

  @override
  String get addLock => '+ 잠금 추가';

  @override
  String get selectAppsToBlock => '차단할 앱 선택';

  @override
  String get selectedAppsUnavailable => '잠금 기간 동안 선택한 앱을 사용할 수 없습니다';

  @override
  String get done => '완료';

  @override
  String get cancel => '취소';

  @override
  String get confirm => '확인';

  @override
  String get lockDuration => '잠금 시간';

  @override
  String get startLock => '잠금 시작';

  @override
  String get permissionRequired => '권한 필요';

  @override
  String get permissionRequiredMessage => '앱이 정상적으로 작동하려면 다음 권한이 필요합니다.';

  @override
  String get notificationPermission => '알림 권한';

  @override
  String get notificationPermissionDesc => '잠금 시작/종료 알림을 위해 필요합니다.';

  @override
  String get overlayPermission => '다른 앱 위에 표시 권한';

  @override
  String get usageAccess => '사용 정보 접근 권한';

  @override
  String get grant => '허용';

  @override
  String get close => '닫기';

  @override
  String get emergencyUnlock => '긴급 해제';

  @override
  String get emergencyUnlockConfirm => '정말 잠금을 해제하시겠습니까?';

  @override
  String get searchAppsHint => '앱 검색 (이름)';

  @override
  String get noSearchResults => '검색 결과 없음';

  @override
  String get selectAppForSchedule => '예약할 앱 선택';

  @override
  String get activeLockWarningTitle => '잠시만요! 실행 중인 잠금이 있습니다.';

  @override
  String get activeLockWarningBody => '잠금이 실행 중일 때는 새로운 잠금을 추가할 수 없습니다.';

  @override
  String get strictMode => '강력 모드';

  @override
  String get strictModeDesc => '타이머가 끝날 때까지 해제 불가';

  @override
  String get selectWeekdays => '요일 선택';

  @override
  String get startTime => '시작 시간';

  @override
  String get endTime => '종료 시간';

  @override
  String get save => '저장';

  @override
  String get delete => '삭제';

  @override
  String get selected => '선택됨';

  @override
  String get unknown => '알 수 없음';

  @override
  String get locked => '잠김';

  @override
  String get hours => '시간';

  @override
  String get minutes => '분';

  @override
  String endsAt(Object time) {
    return '$time 종료';
  }

  @override
  String get setDuration => '시간 설정';

  @override
  String get modifySchedule => '일정 수정';

  @override
  String get addSchedule => '일정 추가';

  @override
  String get settings => '설정';

  @override
  String get language => '언어';

  @override
  String get remaining => '남음';

  @override
  String get seconds => '초';

  @override
  String get unlocked => '해제됨';
}
