//
//  VideoView.swift
//  Pong
//
//  Created by Shreyas Vaderiyattil on 11/27/21.
//

import UIKit

class SummaryViewController: UIViewController {

    @IBOutlet weak var overhandValue: UILabel!
    @IBOutlet weak var scoreValue: UILabel!
    @IBOutlet weak var avgSpeed: UILabel!
    @IBOutlet weak var backgroundImage: UIImageView!
    @IBOutlet weak var trickValue: UILabel!
    
    private let gameManager = GameManager.shared
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.updateUI()
    }

    private func updateUI() {
        let stats = gameManager.playerStats
        backgroundImage.image = gameManager.previewImage
        displayTrajectories()

        overhandValue.text = "\(stats.overhandCount)"
        trickValue.text = "\(stats.trickCount)"
        
        let score = NSMutableAttributedString(string: "\(stats.totalScore)", attributes: [.foregroundColor: UIColor.white])
        score.append(NSAttributedString(string: "/24", attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.65)]))
        scoreValue.attributedText = score
        
        var totalSpeed = gameManager.playerStats.averageSpeed.reduce(0, +)
        totalSpeed /= Double(gameManager.playerStats.averageSpeed.count)
        avgSpeed.text = "\(totalSpeed)"
        
    }

   private func displayTrajectories() {
        let stats = gameManager.playerStats
        let paths = stats.throwPaths
        let frame = view.bounds
        for path in paths {
            let trajectoryView = TrajectoryView(frame: frame)
            trajectoryView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(trajectoryView)
            NSLayoutConstraint.activate([
                trajectoryView.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor, constant: 0),
                trajectoryView.rightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.rightAnchor, constant: 0),
                trajectoryView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 0),
                trajectoryView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: 0)
            ])
            trajectoryView.addPath(path)
        }
    }
}
