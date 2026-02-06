import SwiftUI
import FamilyControls

@available(iOS 16.0, *)
struct AppPickerView: View {
    @StateObject private var manager = AppBlockerManager.shared
    @Binding var isPresented: Bool
    var onAppsSelected: ((Int, Int, Int) -> Void)?
    var onCancel: (() -> Void)?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("차단할 앱을 선택하세요")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top, 20)
                
                Text("선택한 앱은 설정한 시간 동안 사용할 수 없습니다")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                FamilyActivityPicker(selection: $manager.selectedApps)
                    .padding()
                
                Button(action: {
                    isPresented = false
                    let appCount = manager.selectedApps.applicationTokens.count
                    let categoryCount = manager.selectedApps.categoryTokens.count
                    let domainCount = manager.selectedApps.webDomainTokens.count
                    onAppsSelected?(appCount, categoryCount, domainCount)
                }) {
                    Text("선택 완료")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .cornerRadius(12)
                        .padding(.horizontal)
                }
                
                Spacer()
            }
            .navigationBarItems(
                leading: Button("취소") {
                    isPresented = false
                    onCancel?()
                }
            )
        }
    }
}

@available(iOS 16.0, *)
struct AppPickerViewControllerRepresentable: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onAppsSelected: ((Int, Int, Int) -> Void)?
    var onCancel: (() -> Void)?
    
    func makeUIViewController(context: Context) -> UIHostingController<AppPickerView> {
        let controller = UIHostingController(
            rootView: AppPickerView(
                isPresented: $isPresented,
                onAppsSelected: onAppsSelected,
                onCancel: onCancel
            )
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIHostingController<AppPickerView>, context: Context) {
        // 업데이트 불필요
    }
}
