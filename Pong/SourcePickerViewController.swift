//
//  SourceViewController.swift
//  Pong
//
//  Created by Shreyas Vaderiyattil on 11/22/21.
//

import Foundation
import UIKit
import AVFoundation

class SourcePickerViewController: UIViewController {

    private let gameManager = GameManager.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        gameManager.stateMachine.enter(GameManager.InactiveState.self)
    }
    
    @IBAction func revertToSourcePicker(_ segue: UIStoryboardSegue) {
        gameManager.reset()
    }
}

extension SourcePickerViewController: UIDocumentPickerDelegate {
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        gameManager.recordedVideoSource = nil
    }
    
    func  documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let url = urls.first
        if url == nil  {
            return
        }
        gameManager.recordedVideoSource = AVAsset(url: url!)
        performSegue(withIdentifier: "ShowRootControllerSegue", sender: self)
    }
}
