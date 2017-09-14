//
//  SWCaptureVideoVC.swift
//  Eyesight
//
//  Created by Oleg Stepanenko on 07.09.17.
//  Copyright © 2017 StephanWhite. All rights reserved.
//

import UIKit
import AVFoundation

extension UIInterfaceOrientation {
    var videoOrientation: AVCaptureVideoOrientation? {
        switch self {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        default: return nil
        }
    }
}

class SWCaptureVideoVC: UIViewController {
    let videoManager = SWVideoManager.instance
    @IBOutlet weak var previewView: SWCapturePreviewView!
    @IBOutlet weak var recButton: UIButton!
    @IBOutlet weak var recButtonFrameView: UIView!
    @IBOutlet weak var recButtonActivityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var recIndicator: UIView!
    @IBOutlet weak var recTimerLabel: UILabel!
    
    private var videoURL: URL?
    private var startRecordingTime: Date?
    private let formatter = DateIntervalFormatter()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.recButton.isEnabled = false
        self.recButtonActivityIndicator.stopAnimating()
        self.recButtonFrameView.layer.cornerRadius = 25
        self.recButtonFrameView.layer.borderColor = UIColor.white.cgColor
        self.recButtonFrameView.layer.borderWidth = 2
        self.recButton.layer.cornerRadius = 22
        self.recButton.backgroundColor = UIColor.init(white: 1, alpha: 0.3)
        self.recIndicator.layer.cornerRadius = 8
        
        videoManager.setupCaptureSession()
        //TODO:        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(focusAndExposeTap))
        //        previewView.addGestureRecognizer(tapGesture)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.navigationController?.setNavigationBarHidden(true, animated: false)
        self.addObservers()
        videoManager.startCaptureSession()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        videoManager.stopCaptureSession()
        self.removeObservers()
        super.viewWillDisappear(animated)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        coordinator.animate(
            alongsideTransition: { _ in
                self.previewView.videoOrientation = UIApplication.shared.statusBarOrientation.videoOrientation
        }, completion: nil
        )
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showPlayer" {
            if let destinationVC = segue.destination as? SWPlayVideoVC {
                destinationVC.videoURL = self.videoURL
            }
        }
        else if segue.identifier == "selectFilter" {
            videoManager.filterMovieURL = self.videoURL
        }
    }
    
    @IBAction func recButtonUp(_ sender: Any) {
        if (!videoManager.isRecording) {
            videoManager.startRecording(UIApplication.shared.statusBarOrientation.videoOrientation)
        }
        else {
            videoManager.stopRecording()
            self.recButton.isHidden = true
            self.recButtonActivityIndicator.startAnimating()
        }
    }
}

extension SWCaptureVideoVC {
    private func updateTimeLabel() {
        
        var interval :TimeInterval = 0
        if let startRecordingTime = self.startRecordingTime {
            interval = -(startRecordingTime.timeIntervalSinceNow)
            if interval <= 0 {
                interval = 0
            }
        }
        
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        
        if let formattedString = formatter.string(from: interval) {
            self.recTimerLabel.text = formattedString
        }
        else {
            self.recTimerLabel.text = "0:00:00"
        }
    }
    
    @objc private func tickTimer() {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        self.updateTimeLabel()
        self.perform(#selector(self.tickTimer), with: nil, afterDelay: 0.5)
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func addObservers() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(self.startSessionNotifiaction), name: .SWVideoManagerStartSession, object: nil)
        nc.addObserver(self, selector: #selector(self.startRecordingNotifiaction), name: .SWVideoManagerStartRecording, object: nil)
        nc.addObserver(self, selector: #selector(self.stopRecordingNotifiaction), name: .SWVideoManagerStopRecording, object: nil)
    }
    
    @objc private func startSessionNotifiaction(notification: NSNotification) {
        let userInfo = notification.userInfo
        let setupResult = userInfo?["setupResult"] as? SWVideoManager.SessionSetupResult
        if .notAuthorized == setupResult {
            self.askPermisionToCamera()
            self.recButton.isEnabled = false
        }
        else if .configurationFailed == setupResult {
            self.showUnableCapture()
            self.recButton.isEnabled = false
        }
        else {
            self.recButton.isEnabled = true
            let session = notification.userInfo?["session"] as? AVCaptureSession
            self.previewView.session = session
            self.previewView.videoOrientation = UIApplication.shared.statusBarOrientation.videoOrientation;
            self.previewView.videoGravity = AVLayerVideoGravity.resizeAspect
        }

    }
    
    @objc private func startRecordingNotifiaction(notification: NSNotification) {
        self.startRecordingTime = Date()
        self.recIndicator.isHidden = false
        self.recIndicator.alpha = 1;
        self.recButton.backgroundColor = UIColor.red
        UIView.animate(withDuration: 0.5,
                       delay: 0.0,
                       options:[.autoreverse, .repeat, .curveEaseInOut],
                       animations:{
                        self.recIndicator.alpha = 0;
        },
                       completion: nil)
        self.perform(#selector(self.tickTimer), with: nil, afterDelay: 0.0)
    }
    
    @objc private func stopRecordingNotifiaction(notification: NSNotification) {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        self.startRecordingTime = nil
        self.updateTimeLabel()
        self.recButton.isHidden = false
        self.recButton.backgroundColor = UIColor.init(white: 1, alpha: 0.3)
        self.recIndicator.isHidden = true
        self.recIndicator.layer.removeAllAnimations()
        self.recButtonActivityIndicator.stopAnimating()
        
        if let userInfo = notification.userInfo,
           let videoURL = userInfo["outputFileURL"] as? URL {
            self.videoURL = videoURL
            self.performSegue(withIdentifier: "selectFilter", sender: nil)
        }
    }
    
    private func askPermisionToCamera() {
        let message = NSLocalizedString("Application doesn't have permission to use the camera, please change privacy settings",
                                        comment: "Alert message when the user has denied access to the camera")
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
    
    private func showUnableCapture() {
        let message = NSLocalizedString("Unable to capture media", comment: "Alert message when something goes wrong during capture session configuration")
        let alertController = UIAlertController(title: "Eyesight Camera", message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil))
        
        self.present(alertController, animated: true, completion: nil)
    }
}

