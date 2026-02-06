import SwiftUI
import FamilyControls

@available(iOS 16.0, *)
struct AppPickerView: View {
    @StateObject private var manager = AppBlockerManager.shared
    @Environment(\.dismiss) private var dismiss
    var onAppsSelected: (() -> Void)?
    var onCancel: (() -> Void)?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Select Apps to Block")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top, 20)
                
                Text("Selected apps will be unavailable during the lock period")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                FamilyActivityPicker(selection: $manager.selectedApps)
                    .padding()
                
                Button(action: {
                    dismiss()
                    onAppsSelected?()
                }) {
                    Text("Done")
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
                leading: Button("Cancel") {
                    dismiss()
                    onCancel?()
                }
            )
        }
    }
}

@available(iOS 16.0, *)
struct AppPickerViewControllerRepresentable: UIViewControllerRepresentable {
    var onAppsSelected: (() -> Void)?
    var onCancel: (() -> Void)?
    
    func makeUIViewController(context: Context) -> UIHostingController<AppPickerView> {
        let controller = UIHostingController(
            rootView: AppPickerView(
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
