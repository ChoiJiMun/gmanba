//
//  ShieldConfigurationExtension.swift
//  ShieldConfiguration
//
//  Created by OoN JIM on 2/6/26.
//

import ManagedSettings
import ManagedSettingsUI
import UIKit

// Override the functions below to customize the shields used in various situations.
// The system provides a default appearance for any methods that your subclass doesn't override.
// Make sure that your class name matches the NSExtensionPrincipalClass in your Info.plist.
class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    
    // MARK: - Custom Shield Configuration
    // 원하는 디자인(아이콘, 멘트, 색상)을 여기서 정의합니다.
    private func customShieldConfiguration(appName: String? = nil) -> ShieldConfiguration {
        // App Name Handling:
        // ShieldConfiguration does not automatically provide the app name in the text.
        // We can only set a static message or a generic one.
        // However, iOS usually shows the app icon at the top by default if we don't provide one,
        // OR we can provide a custom icon (e.g. Lock Icon).
        
        // 1. Icon (자물쇠 아이콘)
        // 시스템 심볼 "lock.circle.fill" 사용 (SF Symbols)
        // 색상은 흑백으로 나오거나 틴트 컬러를 따릅니다.
        // *주의: 커스텀 이미지를 쓰려면 Assets.xcassets에 추가해야 함. 여기선 안전하게 시스템 아이콘 사용.
        // let icon = UIImage(systemName: "lock.circle.fill")
        
        // 2. Colors
        let backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0) // 다크 모드 배경
        let titleColor = UIColor.white
        let subtitleColor = UIColor.lightGray
        let buttonColor = UIColor(red: 159/255.0, green: 232/255.0, blue: 1/255.0, alpha: 1.0) // #9FE801 (그만바 라임색)
        let buttonTextColor = UIColor.black
        
        // 3. Text Content
        // 요청하신 멘트: "현재 3개의 앱(3개가 선택되었다면)이 잠김상태입니다."
        // 하지만 Extension 안에서는 '몇 개가 잠겼는지' 알 수 있는 방법이 없습니다. (샌드박스 제한)
        // 따라서 가장 자연스러운 고정 멘트를 사용해야 합니다.
        
        return ShieldConfiguration(
            // Background
            backgroundColor: backgroundColor,
            
            // Icon: Use system lock icon
            icon: UIImage(systemName: "lock.shield.fill")?.withTintColor(buttonColor, renderingMode: .alwaysOriginal),
            
            // Title: "앱 잠김" -> "Restricted by Gmanba"
            title: ShieldConfiguration.Label(
                text: "Restricted by Gmanba",
                color: titleColor
            ),
            
            // Subtitle: "이 앱은 그만바에 의해 잠겼습니다." -> 상세 설명
            // "현재 앱이 잠김 상태입니다." (영어)
            subtitle: ShieldConfiguration.Label(
                text: "This app is currently locked to help you focus.",
                color: subtitleColor
            ),
            
            // Primary Button: "확인" (기본) -> 커스텀 라벨
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Confirm",
                color: buttonTextColor
            ),
            
            // Button Background: 그만바 라임색
            primaryButtonBackgroundColor: buttonColor,
            
            // Secondary Button: 숨김 (안 보이게)
            secondaryButtonLabel: nil
        )
    }

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        // Customize the shield as needed for applications.
        return customShieldConfiguration()
    }
    
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        // Customize the shield as needed for applications shielded because of their category.
        return customShieldConfiguration()
    }
    
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        // Customize the shield as needed for web domains.
        return customShieldConfiguration()
    }
    
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        // Customize the shield as needed for web domains shielded because of their category.
        return customShieldConfiguration()
    }
}
