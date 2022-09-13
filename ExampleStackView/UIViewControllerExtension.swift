//
//  UIViewControllerExtension.swift
//  ExampleStackView
//
//  Created by Görkem Gür on 13.09.2022.
//

import Foundation
import UIKit

extension UIViewController {
    
    func getRandomModel() -> [MockExampleModel] {
        var mockExampleList = [MockExampleModel]()
        
        for i in 0...24 {
            mockExampleList.append(MockExampleModel(title: randomString(length: 10), description: randomString(length: 8),index: i))
        }
        return mockExampleList
    }
    
    func randomString(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
        return String((0..<length).map{ _ in letters.randomElement()! })
    }
    
}
