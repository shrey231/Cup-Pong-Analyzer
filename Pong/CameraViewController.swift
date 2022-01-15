//
//  CameraView.swift
//  Pong
//
//  Created by Shreyas Vaderiyattil on 11/27/21.
//

import UIKit
import AVFoundation

protocol CameraViewControllerOutputDelegate: AnyObject {
    func cameraViewController(_ controller: CameraViewController, didReceiveBuffer buffer: CMSampleBuffer, orientation: CGImagePropertyOrientation)
}

class CameraViewController: UIViewController {
    
    weak var outputDelegate: CameraViewControllerOutputDelegate?
    private let videoDataOutputQueue = DispatchQueue(label: "CameraFeedDataOutput", qos: .userInitiated,
                                                     attributes: [], autoreleaseFrequency: .workItem)
    private let gameManager = GameManager.shared

    private var cameraFeedView: CameraFeedView!
    private var cameraFeedSession: AVCaptureSession?

    override func viewDidLoad() {
        super.viewDidLoad()
        startObservingStateChanges()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        cameraFeedSession?.stopRunning()
    }
    
    func setupAVSession() throws {

        let wideAngle = AVCaptureDevice.DeviceType.builtInWideAngleCamera
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [wideAngle], mediaType: .video, position: .unspecified)
        
        let videoDevice = discoverySession.devices.first
        if videoDevice == nil {
            return
        }
        
        let deviceInput = try? AVCaptureDeviceInput(device: videoDevice!)
        if deviceInput == nil {
            return
        }
        
        let session = AVCaptureSession()
        session.beginConfiguration()
   
        if videoDevice!.supportsSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        } else {
            session.sessionPreset = .high
        }
        
        guard session.canAddInput(deviceInput!) else {
            return
        }
        session.addInput(deviceInput!)
        
        let dataOutput = AVCaptureVideoDataOutput()
        if session.canAddOutput(dataOutput) {
            session.addOutput(dataOutput)
          
            dataOutput.alwaysDiscardsLateVideoFrames = true
            dataOutput.videoSettings = [
                String(kCVPixelBufferPixelFormatTypeKey): Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
            ]
            dataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        } else {
            return
        }
        let captureConnection = dataOutput.connection(with: .video)
        captureConnection?.preferredVideoStabilizationMode = .standard
        captureConnection?.isEnabled = true
        session.commitConfiguration()
        cameraFeedSession = session
 
        let videoOrientation: AVCaptureVideoOrientation
        switch view.window?.windowScene?.interfaceOrientation {
        case .landscapeRight:
            videoOrientation = .landscapeRight
        default:
            videoOrientation = .portrait
        }
        
        cameraFeedView = CameraFeedView(frame: view.bounds, session: session, videoOrientation: videoOrientation)
        setupVideoOutputView(cameraFeedView)
        cameraFeedSession?.startRunning()
    }
    
    func viewRectForVisionRect(_ visionRect: CGRect) -> CGRect {
        let flippedRect = visionRect.applying(CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -1))
        let viewRect: CGRect  = cameraFeedView.viewRectConverted(fromNormalizedContentsRect: flippedRect)
       
        return viewRect
    }


    func viewPointForVisionPoint(_ visionPoint: CGPoint) -> CGPoint {
        let flippedPoint = visionPoint.applying(CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -1))
        let viewPoint: CGPoint =  cameraFeedView.viewPointConverted(fromNormalizedContentsPoint: flippedPoint)
        return viewPoint
    }
    func setupVideoOutputView(_ videoOutputView: UIView) {
        videoOutputView.translatesAutoresizingMaskIntoConstraints = false
        videoOutputView.backgroundColor = #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)
        view.addSubview(videoOutputView)
        NSLayoutConstraint.activate([
            videoOutputView.leftAnchor.constraint(equalTo: view.leftAnchor),
            videoOutputView.rightAnchor.constraint(equalTo: view.rightAnchor),
            videoOutputView.topAnchor.constraint(equalTo: view.topAnchor),
            videoOutputView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }


}

extension CameraViewController: GameStateChangeObserver {
    func gameManagerDidEnter(state: GameManager.State, from previousState: GameManager.State?) {
        if state is GameManager.SetupCameraState {
            do {
                try setupAVSession()
            } catch {
                return
            }
        }
    }
}

extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        outputDelegate?.cameraViewController(self, didReceiveBuffer: sampleBuffer, orientation: .up)
        
        DispatchQueue.main.async {
            let stateMachine = self.gameManager.stateMachine
            if stateMachine.currentState is GameManager.SetupCameraState {
   
                stateMachine.enter(GameManager.DetectingCupState.self)
            }
        }
    }
}
