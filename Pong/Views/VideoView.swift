//
//  VideoView.swift
//  Pong
//
//  Created by Shreyas Vaderiyattil on 11/27/21.
//

import Foundation
import UIKit
import AVFoundation

protocol NormalizedGeometryConverting {
    func viewRectConverted(fromNormalizedContentsRect normalizedRect: CGRect) -> CGRect
    func viewPointConverted(fromNormalizedContentsPoint normalizedPoint: CGPoint) -> CGPoint
}

class VideoRenderView: UIView, NormalizedGeometryConverting {
    private var renderLayer: AVPlayerLayer!
    
    var player: AVPlayer? {
        get {
            return renderLayer.player
        }
        set {
            renderLayer.player = newValue
        }
    }
    
    override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        renderLayer = layer as? AVPlayerLayer
        renderLayer.videoGravity = .resizeAspect
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func viewRectConverted(fromNormalizedContentsRect normalizedRect: CGRect) -> CGRect {
        let videoRect = renderLayer.videoRect
        let origin = CGPoint(x: videoRect.origin.x + normalizedRect.origin.x * videoRect.width,
                             y: videoRect.origin.y + normalizedRect.origin.y * videoRect.height)
        let size = CGSize(width: normalizedRect.width * videoRect.width,
                          height: normalizedRect.height * videoRect.height)
        let convertedRect = CGRect(origin: origin, size: size)
        return convertedRect.integral
    }

    func viewPointConverted(fromNormalizedContentsPoint normalizedPoint: CGPoint) -> CGPoint {
        let videoRect = renderLayer.videoRect
        let convertedPoint = CGPoint(x: videoRect.origin.x + normalizedPoint.x * videoRect.width,
                                     y: videoRect.origin.y + normalizedPoint.y * videoRect.height)
        return convertedPoint
    }
}

class CameraFeedView: UIView, NormalizedGeometryConverting {
    private var previewLayer: AVCaptureVideoPreviewLayer!
    
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    init(frame: CGRect, session: AVCaptureSession, videoOrientation: AVCaptureVideoOrientation) {
        super.init(frame: frame)
        previewLayer = layer as? AVCaptureVideoPreviewLayer
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspect
        previewLayer.connection?.videoOrientation = videoOrientation
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func viewRectConverted(fromNormalizedContentsRect normalizedRect: CGRect) -> CGRect {
        return previewLayer.layerRectConverted(fromMetadataOutputRect: normalizedRect)
    }

    func viewPointConverted(fromNormalizedContentsPoint normalizedPoint: CGPoint) -> CGPoint {
        return previewLayer.layerPointConverted(fromCaptureDevicePoint: normalizedPoint)
    }
}



