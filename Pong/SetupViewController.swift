//
//  SetupViewController.swift
//  Pong
//
//  Created by Shreyas Vaderiyattil on 11/23/21.
//


import UIKit
import AVFoundation
import Vision

class SetupViewController: UIViewController {

    @IBOutlet var statusLabel: OverlayLabel!
 
    private let gameManager = GameManager.shared
    private let cupLocationGuide = BoundingBoxView()
    private let cupBoundingBox = BoundingBoxView()

    private var cupDetectionRequest: VNCoreMLRequest!
    private let cupDetectionConfidence: VNConfidence = 0.6
    
    enum SceneSetupStage {
        case detectingCups
        case detectingCupsPlacement
        case detectingSceneStability
        case detectingCupsContours
        case setupComplete
    }

    private var setupStage = SceneSetupStage.detectingCups
    
    enum SceneStabilityResult {
        case unknown
        case stable
        case unstable
    }
    
    private let sceneStabilityRequestHandler = VNSequenceRequestHandler()
    private let sceneStabilityRequiredHistoryLength = 15
    private var sceneStabilityHistoryPoints = [CGPoint]()
    private var previousSampleBuffer: CMSampleBuffer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        cupLocationGuide.borderColor = #colorLiteral(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        cupLocationGuide.borderWidth = 3
        cupLocationGuide.borderCornerRadius = 4
        cupLocationGuide.borderCornerSize = 30
        cupLocationGuide.backgroundOpacity = 0.25
        cupLocationGuide.isHidden = false
        view.addSubview(cupLocationGuide)
        cupBoundingBox.borderColor = #colorLiteral(red: 1, green: 0.5763723254, blue: 0, alpha: 1)
        cupBoundingBox.borderWidth = 2
        cupBoundingBox.borderCornerRadius = 4
        cupBoundingBox.borderCornerSize = 0
        cupBoundingBox.backgroundOpacity = 0.45
        cupBoundingBox.isHidden = false
        view.addSubview(cupBoundingBox)
        updateSetupState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        do {
            let model = try VNCoreMLModel(for: CupDetector_1(configuration: MLModelConfiguration()).model)
            cupDetectionRequest = VNCoreMLRequest(model: model)
            cupDetectionRequest.imageCropAndScaleOption = .scaleFit
        } catch {
            print("Could not create Vision request for cup detector")
        }
    }
    
    func updateBoundingBox(_ boundingBox: BoundingBoxView, withViewRect rect: CGRect?, visionRect: CGRect) {
        DispatchQueue.main.async {
            boundingBox.frame = rect ?? .zero
            boundingBox.visionRect = visionRect
        }
    }
    
    func updateSetupState() {
        let cupBox = cupBoundingBox
        DispatchQueue.main.async {
            switch self.setupStage {
            case .detectingCups:
                self.statusLabel.text = "Locating Cups"
            case .detectingCupsPlacement:
                var boxPlacedCorrectly = true
                if !self.cupLocationGuide.isHidden {
                    boxPlacedCorrectly = cupBox.containedInside(self.cupLocationGuide)
                }
                cupBox.borderColor = boxPlacedCorrectly ? #colorLiteral(red: 0.4641711116, green: 1, blue: 0, alpha: 1) : #colorLiteral(red: 1, green: 0.5763723254, blue: 0, alpha: 1)
                if boxPlacedCorrectly {
                    self.statusLabel.text = "Keep Device Still"
                    self.setupStage = .detectingSceneStability
                } else {
                    self.statusLabel.text = "Place Cups into the Box"
                }
            case .detectingSceneStability:
                switch self.sceneStability {
                case .unknown:
                    break
                case .unstable:
                    self.previousSampleBuffer = nil
                    self.sceneStabilityHistoryPoints.removeAll()
                    self.setupStage = .detectingCupsPlacement
                case .stable:
                    self.setupStage = .detectingCupsContours
                }
            default:
                break
            }
        }
    }
    
    func analyzecupContours(_ contours: [VNContour]) -> (edgePath: CGPath, holePath: CGPath)? {
        let polyContours = contours.compactMap { (contour) -> VNContour? in
            guard let polyContour = try? contour.polygonApproximation(epsilon: 0.01),
                  polyContour.pointCount >= 3 else {
                return nil
            }
            return polyContour
        }
        guard let cupContour = polyContours.max(by: { $0.pointCount < $1.pointCount }) else {
            return nil
        }

        let contourPoints = cupContour.normalizedPoints.map { return CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
        let diagonalThreshold = CGFloat(0.02)
        var largestDiff = CGFloat(0.0)
        let cupPath = UIBezierPath()
        let countLessOne = contourPoints.count - 1
        for (point1, point2) in zip(contourPoints.prefix(countLessOne), contourPoints.suffix(countLessOne)) where
            min(point1.x, point2.x) < 0.5 && max(point1.x, point2.x) > 0.5 && point1.y >= 0.3 && point2.y >= 0.3 {
            let diffX = abs(point1.x - point2.x)
            let diffY = abs(point1.y - point2.y)
            guard diffX > diagonalThreshold && diffY > diagonalThreshold else {
                continue
            }
            if diffX + diffY > largestDiff {
                largestDiff = diffX + diffY
                cupPath.removeAllPoints()
                cupPath.move(to: point1)
                cupPath.addLine(to: point2)
            }
        }
        if largestDiff <= 0  {
            return nil
        }
        var holePath: CGPath?
        for contour in polyContours where contour != cupContour {
            let normalizedPath = contour.normalizedPath
            let normalizedBox = normalizedPath.boundingBox
            if normalizedBox.minX >= 0.5 && normalizedBox.minY >= 0.5 {
                holePath = normalizedPath
                break
            }
        }
        
        let detectedHolePath = holePath
        if detectedHolePath == nil {
            return nil
        }
        
        return (cupPath.cgPath, detectedHolePath) as! (edgePath: CGPath, holePath: CGPath)
    }
    
    var sceneStability: SceneStabilityResult {
        guard sceneStabilityHistoryPoints.count > sceneStabilityRequiredHistoryLength else {
            return .unknown
        }
        var movingAverage = CGPoint.zero
        movingAverage.x = sceneStabilityHistoryPoints.map { $0.x }.reduce(.zero, +)
        movingAverage.y = sceneStabilityHistoryPoints.map { $0.y }.reduce(.zero, +)
        let distance = abs(movingAverage.x) + abs(movingAverage.y)
        return (distance < 10 ? .stable : .unstable)
    }
}

extension SetupViewController: CameraViewControllerOutputDelegate {
    func cameraViewController(_ controller: CameraViewController, didReceiveBuffer buffer: CMSampleBuffer, orientation: CGImagePropertyOrientation) {
        do {
            switch setupStage {
            case .setupComplete:
                return
            case .detectingSceneStability:
                try checkSceneStability(controller, buffer, orientation)
            case .detectingCupsContours:
                try detectcupContours(controller, buffer, orientation)
            case .detectingCups, .detectingCupsPlacement:
                try detectcup(controller, buffer, orientation)
            }
            updateSetupState()
        } catch {
            print("Error123")
        }
    }
    
    private func checkSceneStability(_ controller: CameraViewController, _ buffer: CMSampleBuffer, _ orientation: CGImagePropertyOrientation) throws {
        guard let previousBuffer = self.previousSampleBuffer else {
            self.previousSampleBuffer = buffer
            return
        }
        let registrationRequest = VNTranslationalImageRegistrationRequest(targetedCMSampleBuffer: buffer)
        try sceneStabilityRequestHandler.perform([registrationRequest], on: previousBuffer, orientation: orientation)
        self.previousSampleBuffer = buffer
        if let alignmentObservation = registrationRequest.results?.first {
            let transform = alignmentObservation.alignmentTransform
            sceneStabilityHistoryPoints.append(CGPoint(x: transform.tx, y: transform.ty))
        }
    }

    fileprivate func detectcup(_ controller: CameraViewController, _ buffer: CMSampleBuffer, _ orientation: CGImagePropertyOrientation) throws {
        let visionHandler = VNImageRequestHandler(cmSampleBuffer: buffer, orientation: orientation, options: [:])
        try visionHandler.perform([cupDetectionRequest])
        var rect: CGRect?
        var visionRect = CGRect.null
        if let results = cupDetectionRequest.results as? [VNDetectedObjectObservation] {
            let filteredResults = results.filter { $0.confidence > cupDetectionConfidence }
            if !filteredResults.isEmpty {
                visionRect = filteredResults[0].boundingBox
                rect = controller.viewRectForVisionRect(visionRect)
            }
        }
       
        let guideVisionRect = CGRect(x: 0.7, y: 0.3, width: 0.28, height: 0.3)
        let guideRect = controller.viewRectForVisionRect(guideVisionRect)
        updateBoundingBox(cupLocationGuide, withViewRect: guideRect, visionRect: guideVisionRect)
        
        updateBoundingBox(cupBoundingBox, withViewRect: rect, visionRect:  visionRect)
        self.setupStage = (rect == nil) ? .detectingCups : .detectingCupsPlacement
    }
    
    private func detectcupContours(_ controller: CameraViewController, _ buffer: CMSampleBuffer, _ orientation: CGImagePropertyOrientation) throws {
        let visionHandler = VNImageRequestHandler(cmSampleBuffer: buffer, orientation: orientation, options: [:])
        let contoursRequest = VNDetectContoursRequest()
        contoursRequest.contrastAdjustment = 1.7
        contoursRequest.regionOfInterest = cupBoundingBox.visionRect
        try visionHandler.perform([contoursRequest])
        if let result = contoursRequest.results?.first {
            guard let subpaths = analyzecupContours(result.topLevelContours) else {
                return
            }
            DispatchQueue.main.sync {
                self.gameManager.cupRegion = cupBoundingBox.frame
                let edgeNormalizedBB = subpaths.edgePath.boundingBox
                let edgeSize = CGSize(width: edgeNormalizedBB.width * cupBoundingBox.frame.width,
                                      height: edgeNormalizedBB.height * cupBoundingBox.frame.height)
                let cupLength = hypot(edgeSize.width, edgeSize.height)
                self.gameManager.pointToMeterMultiplier = GameConstants.tableLength / Double(cupLength)
                if let imageBuffer = CMSampleBufferGetImageBuffer(buffer) {
                    let imageData = CIImage(cvImageBuffer: imageBuffer).oriented(orientation)
                    self.gameManager.previewImage = UIImage(ciImage: imageData)
                }
                var holeRect = subpaths.holePath.boundingBox
                holeRect.origin.y = 1 - holeRect.origin.y - holeRect.height
                let cupRect = cupBoundingBox.visionRect
                let normalizedHoleRegion = CGRect(
                        x: cupRect.origin.x + holeRect.origin.x * cupRect.width,
                        y: cupRect.origin.y + holeRect.origin.y * cupRect.height,
                        width: holeRect.width * cupRect.width,
                        height: holeRect.height * cupRect.height)
                self.gameManager.holeRegion = controller.viewRectForVisionRect(normalizedHoleRegion)
                let highlightPath = UIBezierPath(cgPath: subpaths.edgePath)
                highlightPath.append(UIBezierPath(cgPath: subpaths.holePath))
                cupBoundingBox.visionPath = highlightPath.cgPath
                cupBoundingBox.borderColor = #colorLiteral(red: 1, green: 1, blue: 1, alpha: 0.199807363)
                self.gameManager.stateMachine.enter(GameManager.DetectedCupState.self)
            }
        }
    }
}

extension SetupViewController: GameStateChangeObserver {
    func gameManagerDidEnter(state: GameManager.State, from previousState: GameManager.State?) {
        switch state {
        case is GameManager.DetectedCupState:
            setupStage =  .setupComplete
            statusLabel.text = "Cups Detected"
            self.gameManager.stateMachine.enter(GameManager.DetectingPlayerState.self)
        default:
            break
        }
    }
}
