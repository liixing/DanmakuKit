//
//  DanmakuTextCellModel.swift
//  DanmuKitMacExample
//
//  Created by Augment Agent on 2025/8/23.
//  Example text danmaku model for macOS
//

import Cocoa
import DanmakuKit

/// Example text danmaku model for macOS
public class DanmakuTextCellModel: DanmakuCellModel {
    
    public var identifier: String = ""
    
    public var text: String = ""
    
    public var font: NSFont = NSFont.systemFont(ofSize: 15)
    
    /// 文本颜色（默认白色）
    public var textColor: NSColor = NSColor.white

    /// 可配置描边（默认关闭：width/opactiy = 0）
    public var strokeColor: NSColor = NSColor.black
    public var strokeWidth: CGFloat = 0
    public var strokeOpacity: CGFloat = 0

    /// 可配置阴影（默认关闭：opacity/blur = 0）
    public var shadowColor: NSColor = NSColor.black
    public var shadowOpacity: CGFloat = 0
    public var shadowBlur: CGFloat = 0
    public var shadowOffset: CGSize = CGSize(width: 1, height: 1)
    
    public var size: CGSize = .zero
    
    public var track: UInt?
    
    public var displayTime: Double = 8.0
    
    public var type: DanmakuCellType = .floating
    
    public var cellClass: DanmakuCell.Type {
        return DanmakuTextCell.self
    }
    
    public init() {}
    
    public init(text: String) {
        self.text = text
        self.identifier = UUID().uuidString
        calculateSize()
    }
    
    public func calculateSize() {
        // 计算文本尺寸，必要时考虑描边和阴影带来的额外边距
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let boundingRect = attributedString.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        
        // 添加一些边距以适应描边和阴影
        let extraWidth = max(strokeWidth * 2, shadowOffset.width + shadowBlur)
        let extraHeight = max(strokeWidth * 2, shadowOffset.height + shadowBlur)
        
        size = CGSize(
            width: ceil(boundingRect.width + extraWidth),
            height: ceil(boundingRect.height + extraHeight)
        )
    }
    
    public func isEqual(to cellModel: DanmakuCellModel) -> Bool {
        return identifier == cellModel.identifier
    }
}
