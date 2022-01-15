//
//  AppDelegate.swift
//  Pong
//
//  Created by Shreyas Vaderiyattil on 11/11/21.
//

import UIKit
import CoreData

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?


    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        warmUpVisionPipeline()
        return true
    }

 


}

