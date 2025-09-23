//
//  DanmakuTextCell.swift
//  DanmuKitMacExample
//
//  Created by Augment Agent on 2025/8/23.
//  Example text danmaku cell for macOS
//

import Cocoa
import DanmakuKit

/// Example text danmaku cell for macOS
public class DanmakuTextCell: DanmakuCell {
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func displaying(_ context: CGContext, _ size: CGSize, _ isCancelled: Bool) {
        guard !isCancelled, let model = model as? DanmakuTextCellModel else { return }

        // 可配置的描边+阴影（默认都为 0，相当于纯文字，与 iOS 视觉一致）
        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext
        defer { NSGraphicsContext.restoreGraphicsState() }

        let text = NSString(string: model.text)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: model.font,
            .foregroundColor: model.textColor
        ]

        // 如果有阴影设置，先绘制阴影
        if model.shadowOpacity > 0 {
            let shadow = NSShadow()
            shadow.shadowColor = model.shadowColor.withAlphaComponent(model.shadowOpacity)
            shadow.shadowOffset = model.shadowOffset
            shadow.shadowBlurRadius = model.shadowBlur
            
            var shadowAttributes = attributes
            shadowAttributes[.shadow] = shadow
            
            text.draw(at: .zero, withAttributes: shadowAttributes)
        }

        // 如果有描边设置，先绘制描边
        if model.strokeWidth > 0 && model.strokeOpacity > 0 {
            var strokeAttributes = attributes
            strokeAttributes[.strokeColor] = model.strokeColor.withAlphaComponent(model.strokeOpacity)
            strokeAttributes[.strokeWidth] = model.strokeWidth
            
            text.draw(at: .zero, withAttributes: strokeAttributes)
        }

        // 绘制主文本
        text.draw(at: .zero, withAttributes: attributes)
    }
}
