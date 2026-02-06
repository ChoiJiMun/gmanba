import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity

@available(iOS 16.0, *)
class AppBlockerManager: ObservableObject {
    static let shared = AppBlockerManager()
    
    private let center = AuthorizationCenter.shared
    private let store = ManagedSettingsStore()
    
    @Published var selectedApps = FamilyActivitySelection()
    @Published var isAuthorized = false
    
    private init() {
        checkAuthorizationStatus()
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
    
    func blockSelectedApps() {
        checkAuthorizationStatus()
        guard isAuthorized else { return }
        
        // 선택한 앱들을 차단
        store.shield.applications = selectedApps.applicationTokens
        store.shield.applicationCategories = .specific(selectedApps.categoryTokens)
        store.shield.webDomains = selectedApps.webDomainTokens
        
        // 차단된 앱 정보 저장
        saveBlockedApps()
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
    
    func loadBlockedApps() {
        if let data = UserDefaults.standard.data(forKey: "blockedApps"),
           let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            selectedApps = decoded
            blockSelectedApps()
        }
    }
}
