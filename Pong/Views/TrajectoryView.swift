//
//  VideoView.swift
//  Pong
//
//  Created by Shreyas Vaderiyattil on 11/27/21.
//

import UIKit
import Vision

class TrajectoryView: UIView {
    var roi = CGRect.null
    var inFlight = false
    var outOfROIPoints = 0
    var fullTrajectory = UIBezierPath()
    var duration = 0.0
    var speed = 0.0
    var points: [VNPoint] = [] {
        didSet {
            if isTrajectoryMovingForward {
                updatePathLayer()
            }
        }
    }
    
    private let pathLayer = CAShapeLayer()
    private let blurLayer = CAShapeLayer()
    private let shadowLayer = CAShapeLayer()

    private var distanceWithCurrentTrajectory: CGFloat = 0
    private var isTrajectoryMovingForward: Bool {
        if let firstPoint = points.first, let lastPoint = points.last {
            return lastPoint.location.x > firstPoint.location.x
        }
        return false
    }

    var isThrowComplete: Bool {
        if inFlight && outOfROIPoints > GameConstants.frameLimit {
            return true
        }
        return false
    }

    var finalBallLocation: CGPoint {
        let BallLocation = fullTrajectory.currentPoint
        let flipVertical = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -1)
        let scaleDown = CGAffineTransform(scaleX: (1 / bounds.width), y: (1 / bounds.height))
        let normalizedLocation = BallLocation.applying(scaleDown).applying(flipVertical)
        return normalizedLocation
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayer()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }

    func resetPath() {
        inFlight = false
        outOfROIPoints = 0
        distanceWithCurrentTrajectory = 0
        fullTrajectory.removeAllPoints()
        pathLayer.path = fullTrajectory.cgPath
        blurLayer.path = fullTrajectory.cgPath
        shadowLayer.path = fullTrajectory.cgPath
    }

    func addPath(_ path: CGPath) {
        fullTrajectory.cgPath = path
        pathLayer.lineWidth = 2
        pathLayer.path = fullTrajectory.cgPath
        shadowLayer.lineWidth = 4
        shadowLayer.path = fullTrajectory.cgPath
    }

    private func setupLayer() {
        shadowLayer.lineWidth = 12.0
        shadowLayer.lineCap = .round
        shadowLayer.fillColor = UIColor.clear.cgColor
        shadowLayer.strokeColor = #colorLiteral(red: 0.9882352941, green: 0.4666666667, blue: 0, alpha: 0.4519210188).cgColor
        layer.addSublayer(shadowLayer)
        blurLayer.lineWidth = 8.0
        blurLayer.lineCap = .round
        blurLayer.fillColor = UIColor.clear.cgColor
        blurLayer.strokeColor = #colorLiteral(red: 0.9960784314, green: 0.737254902, blue: 0, alpha: 0.597468964).cgColor
        layer.addSublayer(blurLayer)
        pathLayer.lineWidth = 4.0
        pathLayer.lineCap = .round
        pathLayer.fillColor = UIColor.clear.cgColor
        pathLayer.strokeColor = #colorLiteral(red: 0.9960784314, green: 0.737254902, blue: 0, alpha: 0.7512574914).cgColor
        layer.addSublayer(pathLayer)
    }
    
    private func updatePathLayer() {
        let trajectory = UIBezierPath()
        guard let startingPoint = points.first else {
            return
        }
        trajectory.move(to: startingPoint.location)
        for point in points.dropFirst() {
            trajectory.addLine(to: point.location)
        }
        let flipVertical = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -1)
        trajectory.apply(flipVertical)
        trajectory.apply(CGAffineTransform(scaleX: bounds.width, y: bounds.height))
        let startScaled = startingPoint.location.applying(flipVertical).applying(CGAffineTransform(scaleX: bounds.width, y: bounds.height))
        var distanceWithCurrentTrajectory: CGFloat = 0
        if inFlight {
            distanceWithCurrentTrajectory = startScaled.distance(to: fullTrajectory.currentPoint)
        }
        if (roi.contains(trajectory.currentPoint) || (inFlight && roi.contains(startScaled))) &&
            distanceWithCurrentTrajectory < GameConstants.maxDistanceTrajectory {
            if !inFlight {
                let trajectoryLength = trajectory.currentPoint.distance(to: startScaled)
                speed = Double(trajectoryLength) / duration
                fullTrajectory = trajectory
            }
            fullTrajectory.append(trajectory)
            shadowLayer.path = fullTrajectory.cgPath
            blurLayer.path = fullTrajectory.cgPath
            pathLayer.path = fullTrajectory.cgPath
            outOfROIPoints = 0
            inFlight = true
        } else {
            outOfROIPoints += 1
        }
    }
}

