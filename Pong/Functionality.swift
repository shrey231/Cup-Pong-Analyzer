//
//  Functionality.swift
//  Pong
//
//  Created by Shreyas Vaderiyattil on 11/25/21.
//

import Foundation
import Vision
import UIKit


enum ThrowType: String, CaseIterable {
    case Overhand = "Overhand"
    case Trick = "Trick"
    case none = "None"
}

enum Scoring: Int {
    case zero = 0
    case one = 1
    case two = 2
    case four = 4
}
struct GameConstants {
    static let maxThrows = 6
    static let tableLength = 1.22
    static let trajectoryLength = 5
    static let maxPoseObservations = 90
    static let frameLimit = 20
    static let maxDistanceTrajectory: CGFloat = 250
    static let maxTrajectoryObservations = 10
}

struct ThrowMetrics {
    var score = Scoring.zero
    var speed = 0.0
    var throwType = ThrowType.none
    var overhandCount = 0
    var trickCount = 0
    var finalBallLocation: CGPoint = .zero

    mutating func updateThrowType(_ type: ThrowType) {
        throwType = type
    }

    mutating func updateFinalBallLocation(_ location: CGPoint) {
        finalBallLocation = location
    }

    mutating func updateMetrics(newScore: Scoring, speeds: Double, overHand: Int, trick: Int) {
        score = newScore
        speed = speeds
        overhandCount = overHand
        trickCount = trick
    }
}

struct PlayerStats {
    var totalScore = 0
    var throwCount = 0
    var overhandCount = 0
    var trickCount = 0
    var releaseAngle = 0.0
    var avgReleaseAngle = 0.0
    var poseObservations = [VNHumanBodyPoseObservation]()
    var averageSpeed = [Double]()
    var throwPaths = [CGPath]()
    
    mutating func reset() {
        overhandCount = 0
        trickCount = 0
        totalScore = 0
        throwCount = 0
        poseObservations = []
    }

    mutating func resetObservations() {
        poseObservations = []
    }
    
    

    mutating func adjustMetrics(score: Scoring, speed: Double, throwType: ThrowType) {
        throwCount += 1
        totalScore += score.rawValue
        if throwType == ThrowType.Overhand {
            overhandCount += 1
        }else if throwType == ThrowType.Trick{
            trickCount += 1
        }
        averageSpeed.append(speed)
    }

    mutating func storePath(_ path: CGPath) {
        throwPaths.append(path)
    }

    mutating func storeObservation(_ observation: VNHumanBodyPoseObservation) {
        if poseObservations.count >= GameConstants.maxPoseObservations {
            poseObservations.removeFirst()
        }
        poseObservations.append(observation)
    }

    
    
  mutating func getLastThrowType() -> ThrowType {
        guard let actionClassifier = try? OverhandDetector_2(configuration: MLModelConfiguration()),
              let poseMultiArray = prepareInputWithObservations(poseObservations),
              let predictions = try? actionClassifier.prediction(poses: poseMultiArray),
              let throwType = ThrowType(rawValue: predictions.label.capitalized) else {
                print("None")
            return .none
        }
      print(throwType)
      print("Score: \(totalScore)")
        return throwType
    }
}

let jointsOfInterest: [VNHumanBodyPoseObservation.JointName] = [
    .rightWrist,
    .rightElbow,
    .rightShoulder,
    .rightHip,
]

func getBodyJointsFor(observation: VNHumanBodyPoseObservation) -> ([VNHumanBodyPoseObservation.JointName: CGPoint]) {
    var joints = [VNHumanBodyPoseObservation.JointName: CGPoint]()
    let identifiedPoints = try? observation.recognizedPoints(.all)
    if identifiedPoints == nil {
        return joints
    }
    for (key, point) in identifiedPoints! {
        if point.confidence <= 0.1 {
            continue
        }
        if jointsOfInterest.contains(key) {
            joints[key] = point.location
        }
    }
    return joints
}


func armJoints(for observation: VNHumanBodyPoseObservation) -> (CGPoint, CGPoint) {
    var rightElbow = CGPoint(x: 0, y: 0)
    var rightWrist = CGPoint(x: 0, y: 0)
    let identifiedPoints = try? observation.recognizedPoints(.all)

    if identifiedPoints == nil {
        return (rightElbow, rightWrist)
    }
    for (key, point) in identifiedPoints! where point.confidence > 0.1 {
        switch key {
        case .rightElbow:
            rightElbow = point.location
        case .rightWrist:
            rightWrist = point.location
        default:
            break
        }
    }
    return (rightElbow, rightWrist)
}

func warmUpVisionPipeline() {
    guard let image = #imageLiteral(resourceName: "Score1").cgImage,
          let detectorModel = try? CupDetector_1(configuration: MLModelConfiguration()).model,
          let cupDetectionRequest = try? VNCoreMLRequest(model: VNCoreMLModel(for: detectorModel)) else {
        return
    }
    let bodyPoseRequest = VNDetectHumanBodyPoseRequest()
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try? handler.perform([bodyPoseRequest, cupDetectionRequest])
}

func resetMultiArray(_ prediction: MLMultiArray, with value: Double = 0.0) throws {
    let pointer = try UnsafeMutableBufferPointer<Double>(prediction)
    pointer.initialize(repeating: value)
}

func prepareInputWithObservations(_ observations: [VNHumanBodyPoseObservation]) -> MLMultiArray? {
    let numAvailableFrames = observations.count
    let observationsNeeded = 90
    var multiArrayBuffer = [MLMultiArray]()

    for frameIndex in 0 ..< min(numAvailableFrames, observationsNeeded) {
        let pose = observations[frameIndex]
        do {
            let oneFrameMultiArray = try pose.keypointsMultiArray()
            multiArrayBuffer.append(oneFrameMultiArray)
        } catch {
            continue
        }
    }
    
    if numAvailableFrames < observationsNeeded {
        for _ in 0 ..< (observationsNeeded - numAvailableFrames) {
            do {
                let oneFrameMultiArray = try MLMultiArray(shape: [1, 3, 18], dataType: .double)
                try resetMultiArray(oneFrameMultiArray)
                multiArrayBuffer.append(oneFrameMultiArray)
            } catch {
                continue
            }
        }
    }
    return MLMultiArray(concatenating: [MLMultiArray](multiArrayBuffer), axis: 0, dataType: .float)
}



extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat {
        return hypot(x - point.x, y - point.y)
    }
    
    func angleFromHorizontal(to point: CGPoint) -> Double {
        let angle = atan2(point.y - y, point.x - x)
        let deg = abs(angle * (180.0 / CGFloat.pi))
        return Double(round(100 * deg) / 100)
    }
}

extension UIBezierPath {
    convenience init(cornersOfRect borderRect: CGRect, cornerSize: CGSize, cornerRadius: CGFloat) {
        self.init()
        let widths = cornerSize.width
        let heights = cornerSize.height
        
        move(to: CGPoint(x: borderRect.minX, y: borderRect.minY + heights + cornerRadius))
        addLine(to: CGPoint(x: borderRect.minX, y: borderRect.minY + cornerRadius))
        addArc(withCenter: CGPoint(x: borderRect.minX + cornerRadius, y: borderRect.minY + cornerRadius),
               radius: cornerRadius,
               startAngle: CGFloat.pi,
               endAngle: -CGFloat.pi / 2,
               clockwise: true)
        addLine(to: CGPoint(x: borderRect.minX + widths + cornerRadius, y: borderRect.minY))
        
        move(to: CGPoint(x: borderRect.maxX - widths - cornerRadius, y: borderRect.minY))
        addLine(to: CGPoint(x: borderRect.maxX - cornerRadius, y: borderRect.minY))
        addArc(withCenter: CGPoint(x: borderRect.maxX - cornerRadius, y: borderRect.minY + cornerRadius),
               radius: cornerRadius,
               startAngle: -CGFloat.pi / 2,
               endAngle: 0,
               clockwise: true)
        addLine(to: CGPoint(x: borderRect.maxX, y: borderRect.minY + heights + cornerRadius))
      
        move(to: CGPoint(x: borderRect.maxX, y: borderRect.maxY - heights - cornerRadius))
        addLine(to: CGPoint(x: borderRect.maxX, y: borderRect.maxY - cornerRadius))
        addArc(withCenter: CGPoint(x: borderRect.maxX - cornerRadius, y: borderRect.maxY - cornerRadius),
               radius: cornerRadius,
               startAngle: 0,
               endAngle: CGFloat.pi / 2,
               clockwise: true)
        addLine(to: CGPoint(x: borderRect.maxX - widths - cornerRadius, y: borderRect.maxY))
      
        move(to: CGPoint(x: borderRect.minX + widths + cornerRadius, y: borderRect.maxY))
        addLine(to: CGPoint(x: borderRect.minX + cornerRadius, y: borderRect.maxY))
        addArc(withCenter: CGPoint(x: borderRect.minX + cornerRadius,
                                   y: borderRect.maxY - cornerRadius),
               radius: cornerRadius,
               startAngle: CGFloat.pi / 2,
               endAngle: CGFloat.pi,
               clockwise: true)
        addLine(to: CGPoint(x: borderRect.minX, y: borderRect.maxY - heights - cornerRadius))
    }
}
