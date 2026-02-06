import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity

@available(iOS 16.0, *)
class AppBlockerManager: ObservableObject {
    static let shared = AppBlockerManager()
    
    private let center: AuthorizationCenter
    private lazy var store = ManagedSettingsStore()
    // UserDefaults를 분리하여 SharedPreferences와의 충돌 방지
    private let userDefaults = UserDefaults(suiteName: "group.com.jimoon.jamgltime.blocker") ?? .standard
    
    @Published var selectedApps = FamilyActivitySelection()
    @Published var isAuthorized = false
    
    private init() {
        // checkAuthorizationStatus() - 초기화 시점에는 확인하지 않음
        // center를 여기서 초기화하지만 사용은 나중에 함
        self.center = AuthorizationCenter.shared
    }
    
    func checkAuthorizationStatus() {
        isAuthorized = center.authorizationStatus == .approved
    }
    
    func requestAuthorization() async throws {
        try await center.requestAuthorization(for: .individual)
        await MainActor.run {
            self.isAuthorized = center.authorizationStatus == .approved
        }
    }
    
    func blockSelectedApps(save: Bool = true) {
        guard isAuthorized else { 
            print("Not authorized to block apps")
            return 
        }
        
        print("Blocking apps: \(selectedApps)")
        
        // 선택한 앱들을 차단 (카테고리/도메인 차단은 제외하여 자체 앱 실행 방해 방지)
        store.shield.applications = selectedApps.applicationTokens
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        
        // 차단된 앱 정보 저장
        if save {
            saveBlockedApps()
        }
    }
    
    func unblockAllApps() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        
        // 저장된 정보 삭제
        clearBlockedApps()
    }
    
    private func saveBlockedApps() {
        // ApplicationToken을 UserDefaults에 저장 (실제로는 안전한 저장소 사용 권장)
        if let encoded = try? JSONEncoder().encode(selectedApps) {
            UserDefaults.standard.set(encoded, forKey: "blockedApps")
        }
    }
    
    private func clearBlockedApps() {
        UserDefaults.standard.removeObject(forKey: "blockedApps")
    }
    
    func loadBlockedApps() async {
        print("Loading blocked apps...")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            if let data = UserDefaults.standard.data(forKey: "blockedApps") {
                do {
                    let decoded = try JSONDecoder().decode(FamilyActivitySelection.self, from: data)
                    print("Loaded blocked apps from storage: \(decoded.applicationTokens.count) apps")
                    
                    DispatchQueue.main.async {
                        self.selectedApps = decoded
                        // self.checkAuthorizationStatus() // Startup Crash Fix: UI block prevention
                        // self.blockSelectedApps(save: false) // Startup crash fix: Do not re-apply shield on load
                        print("Blocked apps loaded into memory.")
                    }
                } catch {
                    print("Error decoding blocked apps: \(error)")
                }
            } else {
                // 앱 삭제 후 재설치 시, UserDefaults는 비어있지만 시스템 Shield 설정은 남아있을 수 있음 (Ghost Setting).
                // 따라서 저장된 설정이 없으면 명시적으로 Shield를 초기화하여 좀비 차단을 해제해야 함.
                print("No saved blocked apps found. Clearing potential ghost shields.")
                DispatchQueue.main.async {
                    self.unblockAllApps()
                }
            }
        }
    }
}
