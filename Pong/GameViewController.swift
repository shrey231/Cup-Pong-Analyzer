//
//  GameViewController.swift
//  Pong
//
//  Created by Shreyas Vaderiyattil on 11/11/21.
//

import UIKit
import SpriteKit
import GameplayKit
import AVFoundation
import Vision

class GameViewController: UIViewController {
    @IBOutlet weak var scoreLabel: UILabel!
    @IBOutlet weak var speedLabel: UILabel!
    @IBOutlet weak var gameStatusLabel: OverlayLabel!
    @IBOutlet weak var overhandLabel: UILabel!
    @IBOutlet weak var trickLabel: UILabel!
    @IBOutlet weak var metricsStackView: UIStackView!
    private let gameManager = GameManager.shared
    private let detectPlayerRequest = VNDetectHumanBodyPoseRequest()
    private var playerDetected = false
    private var isBallinTarget = false
    private var throwRegion = CGRect.null
    private var targetRegion = CGRect.null
    private let trajectoryView = TrajectoryView()
    private let playerBoundingBox = BoundingBoxView()
    private let jointSegmentView = JointSegmentView()
    private var noObservationFrameCount = 0
    private var trajectoryInFlightPoseObservations = 0
    private var showSummaryGesture: UITapGestureRecognizer!
    private let trajectoryQueue = DispatchQueue(label: "com.ActionAndVision.trajectory", qos: .userInteractive)
    private let bodyPoseDetectionMinConfidence: VNConfidence = 0.6
    private let trajectoryDetectionMinConfidence: VNConfidence = 0.9
    private let bodyPoseRecognizedPointMinConfidence: VNConfidence = 0.1
    private lazy var detectTrajectoryRequest: VNDetectTrajectoriesRequest! =
                        VNDetectTrajectoriesRequest(frameAnalysisSpacing: .zero, trajectoryLength: GameConstants.trajectoryLength)

    var lastThrowMetrics: ThrowMetrics {
        get {
            return gameManager.lastThrowMetrics
        }
        set {
            gameManager.lastThrowMetrics = newValue
        }
    }

    var playerStats: PlayerStats {
        get {
            return gameManager.playerStats
        }
        set {
            gameManager.playerStats = newValue
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setUIElements()
        showSummaryGesture = UITapGestureRecognizer(target: self, action: #selector(handleShowSummaryGesture(_:)))
        showSummaryGesture.numberOfTapsRequired = 2
        view.addGestureRecognizer(showSummaryGesture)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        detectTrajectoryRequest = nil
    }

    func getScoreLabelAttributedStringForScore(_ score: Int) -> NSAttributedString {
        let totalScore = NSMutableAttributedString(string: "Total Score ", attributes: [.foregroundColor: #colorLiteral(red: 1, green: 1, blue: 1, alpha: 0.65)])
        totalScore.append(NSAttributedString(string: "\(score)", attributes: [.foregroundColor: #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1)]))
        totalScore.append(NSAttributedString(string: "/24", attributes: [.foregroundColor: #colorLiteral(red: 1, green: 1, blue: 1, alpha: 0.65)]))
        return totalScore
    }
    
    func getTrickLabelAttributedString(_ trick: Int) -> NSAttributedString {
       
        return NSAttributedString(string: "\(trick)", attributes: [.foregroundColor: #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1)])
    }
    
    func getOverhandLabelAttributedString(_ overhand: Int) -> NSAttributedString {
        return NSAttributedString(string: "\(overhand)", attributes: [.foregroundColor: #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1)])
    }
    
    func getSpeedLabelAttributedString(_ speed: Double) -> NSAttributedString {
        return NSAttributedString(string: "\(speed)", attributes: [.foregroundColor: #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1)])
    }

    func setUIElements() {
        resetKPILabels()
        playerBoundingBox.borderColor = #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1)
        playerBoundingBox.backgroundOpacity = 0
        playerBoundingBox.isHidden = false
        view.addSubview(playerBoundingBox)
        view.addSubview(jointSegmentView)
        view.addSubview(trajectoryView)
        gameStatusLabel.text = "Waiting for player"

        scoreLabel.attributedText = getScoreLabelAttributedStringForScore(0)
    }

    func resetKPILabels() {

        metricsStackView.isHidden = true
    }

    func updateKPILabels() {
        metricsStackView.isHidden = false
        scoreLabel.attributedText = getScoreLabelAttributedStringForScore(gameManager.playerStats.totalScore)
        trickLabel.attributedText = getTrickLabelAttributedString(gameManager.playerStats.trickCount)
        overhandLabel.attributedText = getOverhandLabelAttributedString(gameManager.playerStats.overhandCount)
        speedLabel.attributedText = getSpeedLabelAttributedString(lastThrowMetrics.speed)
    }

    func updateBoundingBox(_ boundingBox: BoundingBoxView, withRect rect: CGRect?) {
        boundingBox.frame = rect ?? .zero
    }

    func humanBoundingBox(for observation: VNHumanBodyPoseObservation) -> CGRect {
        var box = CGRect.zero
        var normalizedBoundingBox = CGRect.null
        guard observation.confidence > bodyPoseDetectionMinConfidence, let points = try? observation.recognizedPoints(forGroupKey: .all) else {
            return box
        }
        for (_, point) in points where point.confidence > bodyPoseRecognizedPointMinConfidence {
            normalizedBoundingBox = normalizedBoundingBox.union(CGRect(origin: point.location, size: .zero))
        }
        if !normalizedBoundingBox.isNull {
            box = normalizedBoundingBox
        }
        let joints = getBodyJointsFor(observation: observation)
        DispatchQueue.main.async {
            self.jointSegmentView.joints = joints
        }
        if gameManager.stateMachine.currentState is GameManager.TrackThrowsState {
            playerStats.storeObservation(observation)
            if trajectoryView.inFlight {
                trajectoryInFlightPoseObservations += 1
            }
        }
        return box
    }

    func resetTrajectoryRegions() {
        let cupRegion = gameManager.cupRegion
        let playerRegion = playerBoundingBox.frame
        let throwWindowXBuffer: CGFloat = 5
        let throwWindowYBuffer: CGFloat = 50
        let targetWindowXBuffer: CGFloat = 50
        let throwRegionWidth: CGFloat = 200
        throwRegion = CGRect(x: playerRegion.maxX + throwWindowXBuffer, y: 0, width: throwRegionWidth, height: playerRegion.maxY - throwWindowYBuffer)
        targetRegion = CGRect(x: cupRegion.minX - targetWindowXBuffer, y: 0,
                              width: cupRegion.width + targetWindowXBuffer, height: cupRegion.maxY)
    }


    func updateTrajectoryRegions() {
        let trajectoryLocation = trajectoryView.fullTrajectory.currentPoint
        let didBallCrossCenterOfThrowRegion = trajectoryLocation.x > throwRegion.origin.x + throwRegion.width / 2
        guard !(throwRegion.contains(trajectoryLocation) && didBallCrossCenterOfThrowRegion) else {
            return
        }
        let overlapWindowBuffer: CGFloat = 50
        if targetRegion.contains(trajectoryLocation) {

            throwRegion = targetRegion
        } else if trajectoryLocation.x + throwRegion.width / 2 - overlapWindowBuffer < targetRegion.origin.x {
            throwRegion.origin.x = trajectoryLocation.x - throwRegion.width / 2
        }
        trajectoryView.roi = throwRegion
    }
    
    func processTrajectoryObservations(_ controller: CameraViewController, _ results: [VNTrajectoryObservation]) {
        if self.trajectoryView.inFlight && results.count < 1 {
            self.noObservationFrameCount += 1
            if self.noObservationFrameCount > GameConstants.frameLimit {
                self.updatePlayerStats(controller)
            }
        } else {
            for path in results where path.confidence > trajectoryDetectionMinConfidence {
                self.trajectoryView.duration = path.timeRange.duration.seconds
                self.trajectoryView.points = path.detectedPoints
                if !self.trajectoryView.fullTrajectory.isEmpty {
                    
                    self.updateTrajectoryRegions()
                    if self.trajectoryView.isThrowComplete {
                        self.updatePlayerStats(controller)
                    }
                }
                self.noObservationFrameCount = 0
            }
        }
    }
    
    func updatePlayerStats(_ controller: CameraViewController) {
        let finalBallLocation = trajectoryView.finalBallLocation
        playerStats.storePath(self.trajectoryView.fullTrajectory.cgPath)
        trajectoryView.resetPath()
        lastThrowMetrics.updateThrowType(playerStats.getLastThrowType())
        let score = computeScore(controller.viewPointForVisionPoint(finalBallLocation))
        let releaseSpeed = round((round(trajectoryView.speed * gameManager.pointToMeterMultiplier * 2.24 * 100) / 100) / 6)
        lastThrowMetrics.updateMetrics(newScore: score, speeds: releaseSpeed, overHand: playerStats.overhandCount,trick: playerStats.trickCount)
        print(lastThrowMetrics.speed)
        self.gameManager.stateMachine.enter(GameManager.ThrowCompletedState.self)
    }
    
    func computeScore(_ finalBallLocation: CGPoint) -> Scoring {
       return lastThrowMetrics.throwType == .Trick ? Scoring.four : Scoring.one
    }
}

extension GameViewController: GameStateChangeObserver {
    func gameManagerDidEnter(state: GameManager.State, from previousState: GameManager.State?) {
        switch state {
        case is GameManager.DetectedPlayerState:
            playerDetected = true
            playerStats.reset()
            gameStatusLabel.text = "Go"
            self.gameManager.stateMachine.enter(GameManager.TrackThrowsState.self)
        case is GameManager.TrackThrowsState:
            resetTrajectoryRegions()
            trajectoryView.roi = throwRegion
        case is GameManager.ThrowCompletedState:
            playerStats.adjustMetrics(score: lastThrowMetrics.score,
                                      speed: lastThrowMetrics.speed, throwType: lastThrowMetrics.throwType)
            playerStats.resetObservations()
            trajectoryInFlightPoseObservations = 0
            self.updateKPILabels()
            
            gameStatusLabel.text = lastThrowMetrics.score.rawValue > 0 ? "+\(lastThrowMetrics.score.rawValue)" : ""
            if self.playerStats.throwCount == GameConstants.maxThrows {
                self.gameManager.stateMachine.enter(GameManager.ShowSummaryState.self)
            } else {
                self.gameManager.stateMachine.enter(GameManager.TrackThrowsState.self)
            }
        default:
            break
        }
    }
}

extension GameViewController: CameraViewControllerOutputDelegate {
    func cameraViewController(_ controller: CameraViewController, didReceiveBuffer buffer: CMSampleBuffer, orientation: CGImagePropertyOrientation) {
        let visionHandler = VNImageRequestHandler(cmSampleBuffer: buffer, orientation: orientation, options: [:])
        if gameManager.stateMachine.currentState is GameManager.TrackThrowsState {
            DispatchQueue.main.async {
                let normalizedFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
                self.jointSegmentView.frame = controller.viewRectForVisionRect(normalizedFrame)
                self.trajectoryView.frame = controller.viewRectForVisionRect(normalizedFrame)
            }
            trajectoryQueue.async {
                do {
                    try visionHandler.perform([self.detectTrajectoryRequest])
                    if let results = self.detectTrajectoryRequest.results {
                        DispatchQueue.main.async {
                            self.processTrajectoryObservations(controller, results)
                        }
                    }
                } catch {
                    return
                }
            }
        }
        if !(self.trajectoryView.inFlight && self.trajectoryInFlightPoseObservations >= GameConstants.maxTrajectoryObservations) {
            do {
                try visionHandler.perform([detectPlayerRequest])
                if let result = detectPlayerRequest.results?.first {
                    let box = humanBoundingBox(for: result)
                    let boxView = playerBoundingBox
                    DispatchQueue.main.async {
                        let inset: CGFloat = -20.0
                        let viewRect = controller.viewRectForVisionRect(box).insetBy(dx: inset, dy: inset)
                        self.updateBoundingBox(boxView, withRect: viewRect)
                        if !self.playerDetected && !boxView.isHidden {
                            self.gameStatusLabel.alpha = 0
                            self.resetTrajectoryRegions()
                            self.gameManager.stateMachine.enter(GameManager.DetectedPlayerState.self)
                        }
                    }
                }
            } catch {
               return
            }
        } else {
            DispatchQueue.main.async {
                if !self.playerBoundingBox.isHidden {
                    self.playerBoundingBox.isHidden = true
                    self.jointSegmentView.resetView()
                }
            }
        }
    }
}

extension GameViewController {
    @objc
    func handleShowSummaryGesture(_ gesture: UITapGestureRecognizer) {
        if gesture.state == .ended {
            self.gameManager.stateMachine.enter(GameManager.ShowSummaryState.self)
        }
    }
}
