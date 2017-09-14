//
//  SWCapturePreviewView.swift
//  Eyesight
//
//  Created by Oleg Stepanenko on 07.09.17.
//  Copyright © 2017 StephanWhite. All rights reserved.
//

import UIKit
import AVFoundation

class SWCapturePreviewView: UIView {
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    var videoOrientation: AVCaptureVideoOrientation? {
        get {
            return previewLayer.connection?.videoOrientation ?? .portrait
        }
        set {
            guard newValue != nil,
                previewLayer.connection != nil,
                previewLayer.connection!.isVideoOrientationSupported else {
                    return
            }
            previewLayer.connection!.videoOrientation = newValue!
        }
    }
    
    var videoGravity: AVLayerVideoGravity? {
        get {
            return previewLayer.videoGravity
        }
        set {
            if let gravity = newValue {
                previewLayer.videoGravity = gravity
            }
        }
    }

    var session: AVCaptureSession? {
        get {
            return previewLayer.session
        }
        
        set {
            previewLayer.session = newValue
        }
    }
    
    private var previewLayer: AVCaptureVideoPreviewLayer {
        return self.layer as! AVCaptureVideoPreviewLayer
    }
}
