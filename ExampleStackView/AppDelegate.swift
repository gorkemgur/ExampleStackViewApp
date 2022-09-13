//
//  AppDelegate.swift
//  ExampleStackView
//
//  Created by Görkem Gür on 13.09.2022.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        let navigationController = UINavigationController(rootViewController: ExampleStackViewController())
        navigationController.setNavigationBarHidden(true, animated: true)
        self.window = UIWindow(frame: UIScreen.main.bounds)
        self.window?.rootViewController = ExampleStackViewController()
        self.window?.makeKeyAndVisible()
        
        return true
        
    }
    
}

