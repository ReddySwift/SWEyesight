//
//  SWPlayerView.swift
//  Eyesight
//
//  Created by Oleg Stepanenko on 09.09.17.
//  Copyright © 2017 StephanWhite. All rights reserved.
//

import UIKit
import AVFoundation

class SWPlayerView: UIView {

    override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }
    
    var videoGravity: AVLayerVideoGravity? {
        get {
            return playerLayer.videoGravity
        }
        set {
            if let gravity = newValue {
                playerLayer.videoGravity = gravity
            }
        }
    }
    
    var player: AVPlayer? {
        get {
            return playerLayer.player
        }
        
        set {
            playerLayer.player = newValue
        }
    }

    var playerLayer: AVPlayerLayer {
        return self.layer as! AVPlayerLayer
    }
}
