//
//  SWPlayVideoVC.swift
//  Eyesight
//
//  Created by Oleg Stepanenko on 09.09.17.
//  Copyright © 2017 StephanWhite. All rights reserved.
//

import UIKit
import AVFoundation

class SWPlayVideoVC: UIViewController {
    /// Context used in KVO to identify rate changes.
    private var playerRateObservationContext = 0
    /// Context used in KVO to identify player status changes.
    private var playerStatusObservationContext = 1

    let videoManager = SWVideoManager.instance

    var videoURL: URL? {
        didSet {
            if let url = self.videoURL {
                self.videoPlayer = SWVideoManager.instance.createVideoPlayer(url: url)
            }
        }
    }
    
    private var videoPlayer: AVPlayer? {
        willSet {
            if let player = videoPlayer {
                player.removeObserver(self, forKeyPath: "rate")
                player.removeObserver(self, forKeyPath: #keyPath(AVPlayer.status))
                NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: player.currentItem)
            }
        }
        
        didSet {
            if let player = videoPlayer {
                player.addObserver(self, forKeyPath: "rate", options: [.new, .old], context: &playerRateObservationContext)
                player.addObserver(self, forKeyPath: #keyPath(AVPlayer.status), options: [.new], context: &playerStatusObservationContext)
                NotificationCenter.default.addObserver(self, selector: #selector(playerItemDidReachEnd(_:)),
                                                       name: .AVPlayerItemDidPlayToEndTime, object: player.currentItem)
                if self.isViewLoaded {
                    self.playerView.player = videoPlayer
                }
            }
        }
    }
    
    @IBOutlet var playerView: SWPlayerView!
    @IBOutlet weak var playPauseButton: UIButton!
    @IBOutlet weak var scrubber: UISlider!
    @IBOutlet weak var timerLabel: UILabel!
    @IBOutlet weak var exportButton: UIBarButtonItem!

    private var isPlaying = false
    private var scrubInFlight = false
    private var seekToZeroBeforePlaying = false
    private var lastScrubSliderValue: Float = 0
    private var playRateToRestore: Float = 0
    private var timeObserver: Any?

    deinit {
        self.removeObservers()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if let videoPlayer = self.videoPlayer {
            self.playerView.player = videoPlayer
        }
        self.updateScrubber()
        self.updateTimeLabel()
        self.addObservers()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(false, animated: false)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        addTimeObserverToPlayer()
        if let player = self.videoPlayer {
            player.play()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let player = self.videoPlayer {
            player.pause()
        }
        removeTimeObserverFromPlayer()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction func exportVideo(_ sender: Any) {
        if let videoURL = self.videoURL {
            videoManager.exportVideo(videoURL)
        }
//        self.videoPlayer?.seek(to: kCMTimeZero)
//        self.videoPlayer?.seek(to: CMTime(seconds: 0, preferredTimescale: 1))
//        self.videoPlayer?.play()
    }
    
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

    // MARK: - Notification
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        if let player = self.videoPlayer {
            player.removeObserver(self, forKeyPath: "rate")
            player.removeObserver(self, forKeyPath: #keyPath(AVPlayer.status))
        }
    }
    
    private func addObservers() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(self.startExportNotifiaction), name: .SWVideoManagerStartExport, object: nil)
        nc.addObserver(self, selector: #selector(self.stopExportNotifiaction), name: .SWVideoManagerStopExport, object: nil)
    }
    
    @objc private func startExportNotifiaction(notification: NSNotification) {
        let userInfo = notification.userInfo
        let isEnabled = (userInfo?["enabled"] as? Bool) ?? false
        if !isEnabled {
            self.askPermisionToCameraRoll()
        }
        else {
            //expot started successfully
        }
    }
    
    @objc private func stopExportNotifiaction(notification: NSNotification) {
        if let userInfo = notification.userInfo {
            let isSuccessful = (userInfo["success"] as? Bool) ?? false
            if isSuccessful {
                self.showSavedToCameraRollSuccessfully()
            }
            else {
                self.showUnableSaveToCameraRoll()
            }
            //we can export movie just one time
            self.exportButton.isEnabled = false
        }
    }

    @objc func playerItemDidReachEnd(_ notification: Notification) {
        seekToZeroBeforePlaying = true
    }

    private func askPermisionToCameraRoll() {
        let message = NSLocalizedString("Application doesn't have permission to save the movie to camera roll, please change privacy settings",
                                        comment: "Alert message when the user has denied access to the camera roll")
        let alertController = UIAlertController(title: "Eyesight Camera", message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                style: .cancel,
                                                handler: nil))
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"),
                                                style: .`default`,
                                                handler: { _ in
                                                    UIApplication.shared.open(URL(string: UIApplicationOpenSettingsURLString)!,
                                                                              options: [:],
                                                                              completionHandler: nil)
        }))
        
        self.present(alertController, animated: true, completion: nil)
    }

    private func showUnableSaveToCameraRoll() {
        let message = NSLocalizedString("Unable to save movie", comment: "Alert message when something goes wrong during save movie to camera roll")
        let alertController = UIAlertController(title: "Eyesight Camera", message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil))
        
        self.present(alertController, animated: true, completion: nil)
    }

    private func showSavedToCameraRollSuccessfully() {
        let message = NSLocalizedString("Movie saved", comment: "Movie is saved to camera roll successfully")
        let alertController = UIAlertController(title: "Eyesight Camera", message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil))
        
        self.present(alertController, animated: true, completion: nil)
    }

    // MARK: - KVO Observation
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?,
                               context: UnsafeMutableRawPointer?) {
        
        // Make sure the this KVO callback was intended for this view controller.
        if context == &playerRateObservationContext {
            
            guard let newRate = change?[.newKey] as? Float,
                let oldRate = change?[.oldKey] as? Float else { return }
            if newRate != oldRate {
                isPlaying = (newRate != 0) || (playRateToRestore != 0)
                
                updatePlayPauseButton()
                updateScrubber()
                updateTimeLabel()
            }
        } else if context == &playerStatusObservationContext {
            guard let playerItem = object as? AVPlayerItem else { return }
            if playerItem.status == .readyToPlay {
                /*
                 Once the AVPlayerItem becomes ready to play, i.e.
                 playerItem.status == AVPlayerItemStatusReadyToPlay,
                 its duration can be fetched from the item.
                 */
                addTimeObserverToPlayer()
            } else if playerItem.status == .failed {
                if let error = playerItem.error {
                    print("error=\(error)")
                }
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    func addTimeObserverToPlayer() {
        
        guard let videoPlayer = self.videoPlayer,
            let currentPlayerItem = videoPlayer.currentItem else { return }
        
        if currentPlayerItem.status != .readyToPlay { return }
        
        let duration: Double = CMTimeGetSeconds(playerItemDuration())
        
        if __inline_isfinited(duration) != 0 {
            
            let width = (Double(scrubber.bounds.width))
            var interval = 0.5 * (duration / width)
            
            // The time label needs to update at least once per second.
            if interval > 1.0 {
                interval = 1.0
            }
            
            let updateTime = CMTimeMakeWithSeconds(interval, Int32(NSEC_PER_SEC))
            timeObserver = videoPlayer.addPeriodicTimeObserver(forInterval: updateTime, queue: DispatchQueue.main,
                                                               using: { [unowned self] _ in
                                                                self.updateScrubber()
                                                                self.updateTimeLabel()
            })
        }
    }
    
    func removeTimeObserverFromPlayer() {
        guard let timeObserver = self.timeObserver else { return }
        self.timeObserver = nil
        guard let videoPlayer = self.videoPlayer else { return }
        videoPlayer.removeTimeObserver(timeObserver)
    }

    
    // MARK: Playback
    
    @IBAction func togglePlayPause(_ sender: AnyObject) {
        guard let videoPlayer = self.videoPlayer else {
            return
        }
        isPlaying = !isPlaying
        if isPlaying {
            if seekToZeroBeforePlaying {
                videoPlayer.seek(to: kCMTimeZero)
                seekToZeroBeforePlaying = false
                updateScrubber()
            }
            videoPlayer.play()
        } else {
            videoPlayer.pause()
        }
    }
    
    @IBAction func beginScrubbing(_ sender: AnyObject) {
        guard let videoPlayer = self.videoPlayer else { return }
        seekToZeroBeforePlaying = false
        playRateToRestore = videoPlayer.rate
        videoPlayer.rate = 0
        
        removeTimeObserverFromPlayer()
    }
    
    @IBAction func scrub(_ sender: AnyObject) {
        
        lastScrubSliderValue = scrubber.value
        
        if !scrubInFlight {
            scrubToSliderValue(lastScrubSliderValue)
        }
    }
    
    func scrubToSliderValue(_ sliderValue: Float) {
        
        let duration = CMTimeGetSeconds(playerItemDuration())
        
        if __inline_isfinited(duration) > 0 {
            
            guard let player = self.videoPlayer else {
                return
            }
            let width = scrubber?.bounds.width ?? 1
            
            let time = duration * Float64(sliderValue)
            let tolerance = 1 * (duration / Float64(width))
            
            scrubInFlight = true
            
            player.seek(to: CMTimeMakeWithSeconds(time, Int32(NSEC_PER_SEC)),
                        toleranceBefore: CMTimeMakeWithSeconds(tolerance, Int32(NSEC_PER_SEC)),
                        toleranceAfter: CMTimeMakeWithSeconds(tolerance, Int32(NSEC_PER_SEC)),
                        completionHandler: { (_) in
                            self.scrubInFlight = false
                            self.updateTimeLabel()
            })
        }
    }
    
    @IBAction func endScrubbing(_ sender: AnyObject) {
        
        if scrubInFlight {
            scrubToSliderValue(lastScrubSliderValue)
        }
        addTimeObserverToPlayer()
        videoPlayer.map({ $0.rate = playRateToRestore })
        playRateToRestore = 0
    }
    
    private func updatePlayPauseButton() {
        playPauseButton.setTitle(self.isPlaying ? "Stop" : "Play", for: .normal)
    }
    
    private func updateTimeLabel() {
        
        guard let player = self.videoPlayer else {
            return
        }
        var seconds = CMTimeGetSeconds(player.currentTime())
        if __inline_isfinited(seconds) <= 0 {
            seconds = 0
        }
        
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        
        guard let formattedString = formatter.string(from: TimeInterval(seconds)) else { return }
        timerLabel.text = formattedString
    }
    
    private func updateScrubber() {
        
        let duration = CMTimeGetSeconds(playerItemDuration())
        if __inline_isfinited(duration) != 0 {
            guard let player = self.videoPlayer else { return }
            let time = CMTimeGetSeconds(player.currentTime())
            scrubber.setValue(Float(time/duration), animated: true)
        } else {
            scrubber.setValue(0, animated: true)
        }
    }

    private func playerItemDuration() -> CMTime {
        
        var itemDuration = kCMTimeInvalid
        guard let player = self.videoPlayer,
            let playerItem = player.currentItem else { return itemDuration }
        
        if playerItem.status == AVPlayerItemStatus.readyToPlay {
            itemDuration = playerItem.duration
        }
        
        return itemDuration
    }

}
