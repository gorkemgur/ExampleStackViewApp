//
//  UIStackViewExtension.swift
//  ExampleStackView
//
//  Created by Görkem Gür on 13.09.2022.
//

import Foundation
import UIKit

extension UIStackView {
    func addArrangedSubviews(_ views: [UIView]) {
        for view in views {
            addArrangedSubview(view)
        }
    }
    
    /// SwifterSwift: Removes all views in stack’s array of arranged subviews.
    func removeArrangedSubviews() {
        for view in arrangedSubviews {
            removeArrangedSubview(view)
        }
    }
    
    func getTappedView(index: Int) -> UIView {
        var tappedView = MockView()
        for view in arrangedSubviews {
            if view.tag == index {
                tappedView = view as? MockView ?? MockView()
                tappedView.setSelected()
            }
        }
        return tappedView
    }
}
