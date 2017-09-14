//
//  SWVideoManager.swift
//  Eyesight
//
//  Created by Oleg Stepanenko on 07.09.17.
//  Copyright © 2017 StephanWhite. All rights reserved.
//

import UIKit
import AVFoundation
import Photos
import GPUImage

extension NSNotification.Name {
    static let SWVideoManagerStartSession = Notification.Name(rawValue: "SWVideoManagerStartSession")
    static let SWVideoManagerStopSession = Notification.Name(rawValue: "SWVideoManagerStopSession")
    static let SWVideoManagerStartRecording = Notification.Name(rawValue: "SWVideoManagerStartRecording")
    static let SWVideoManagerStopRecording = Notification.Name(rawValue: "SWVideoManagerStopRecording")
    static let SWVideoManagerStartFilterMovie = Notification.Name(rawValue: "SWVideoManagerStartFilterMovie")
    static let SWVideoManagerStartExport = Notification.Name(rawValue: "SWVideoManagerStartExport")
    static let SWVideoManagerStopExport = Notification.Name(rawValue: "SWVideoManagerStopExport")
}

enum SWFilterType {
    case None
    case Amaro
    case Brannan
    case Earlybird
    case LordKelvin
    case Inversion
    case Hue
    case Sepia
    case Grayscale
}

class SWFilterItem {
    var id :SWFilterType
    var title :String
    lazy var filter: BasicOperation = {
        return SWFilterItem.createFilter(id)
    }()
    
    public init(_ identifier:SWFilterType, title:String!) {
        self.id = identifier
        self.title = title
    }
    
    class func createFilter(_ type: SWFilterType) -> BasicOperation {
        switch type {
        case .None:
            return SaturationAdjustment()
        case .Inversion:
            return ColorInversion()
        case .Hue:
            return HueAdjustment()
        case .Sepia:
            return SepiaToneFilter()
        case .Grayscale:
            let grayscale = SaturationAdjustment()
            grayscale.saturation = 0
            return grayscale
        default: //not implemented .Amaro, .Brannan, .Earlybird, .LordKelvin:
            return SaturationAdjustment()
        }
    }
}

class SWVideoManager: NSObject, AVCaptureFileOutputRecordingDelegate {
    static let instance = SWVideoManager()
    
    enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    var isRecording: Bool {
        get {
            return videoOutput.isRecording
        }
    }
    
    private var videoOrientation: AVCaptureVideoOrientation {
        get {
            return self.videoOutput.connection(with: .video)!.videoOrientation
        }
        set {
            print("videoOrientation=\(newValue.rawValue)")
            self.videoOutput.connection(with: .video)!.videoOrientation = newValue
        }
    }
    
    private var setupResult: SessionSetupResult = .success
    private let captureSession = AVCaptureSession()
    
    let filters : [SWFilterItem] = [
        SWFilterItem(.None, title:"None"),
        SWFilterItem(.Inversion, title:"Inversion"),
        SWFilterItem(.Hue, title:"Hue"),
        SWFilterItem(.Sepia, title:"Sepia"),
        SWFilterItem(.Grayscale, title:"Grayscale"),
        SWFilterItem(.Amaro, title:"Amaro"),
        SWFilterItem(.Brannan, title:"Brannan"),
        SWFilterItem(.Earlybird, title:"Earlybird"),
        SWFilterItem(.LordKelvin, title:"LordKelvin"),
    ]
    
    var selectedFilter : BasicOperation = SaturationAdjustment() {
        didSet {
            oldValue.removeAllTargets()
            if let filterMovie = filterMovie {
                filterMovie.removeAllTargets()
                filterMovie --> selectedFilter
            }
        }
    }
    
    var selectedFilterType : SWFilterType = SWFilterType.None {
        didSet {
            selectedFilter = SWFilterItem.createFilter(selectedFilterType)
        }
    }
    
    var filterMovieURL :URL?
    
    func filterMovieAsset() -> AVURLAsset? {
        if let url = filterMovieURL {
            let inputOptions = [AVURLAssetPreferPreciseDurationAndTimingKey:NSNumber(value:true)]
            return AVURLAsset(url:url, options:inputOptions)
        }
        
        return nil
    }
    
    var filterMovie : MovieInput! {
        didSet {
            if let movie = oldValue {
                movie.removeAllTargets()
            }
            guard
                let movie = filterMovie
                else { return }
            movie --> selectedFilter
        }
    }

    func stopFilterMovie() {
        NSObject.cancelPreviousPerformRequests(withTarget: self,
                                               selector: #selector(self.runFilterMovie),
                                               object: nil)
        if let filterMovie = filterMovie {
            filterMovie.cancel()
            self.filterMovie = nil
        }
    }
    
    @objc func runFilterMovie() {
        self.stopFilterMovie()
        do {
            guard
                let url = self.filterMovieURL,
                let inputAsset = self.filterMovieAsset()
            else { return }
            filterMovie = try MovieInput(url:url, playAtActualSpeed:true, loop:false)
            filterMovie.runBenchmark = true
            filterMovie.start()
            NotificationCenter.default.post(Notification(name: .SWVideoManagerStartFilterMovie, object: self, userInfo: ["filterMovie": filterMovie, "inputAsset": inputAsset]))
            let duration = TimeInterval(inputAsset.duration.seconds+0)
            self.perform(#selector(self.runFilterMovie), with: nil, afterDelay:duration)
        } catch {
            print("Couldn't process movie with error: \(error)")
        }
    }

    func makeFilteredMovie() {
        //filter movie
        self.stopFilterMovie()
        self.filterMovie = nil
        selectedFilter.removeAllTargets()
        if self.selectedFilterType != .None {
            do {
                guard
                    let inputAsset = self.filterMovieAsset(),
                    let videoTrack = inputAsset.tracks(withMediaType: .video).first
                    else { return }
                let size = videoTrack.naturalSize
                let movieIn = try MovieInput(asset:inputAsset, playAtActualSpeed:false, loop:false)
                let movieOut = try MovieOutput(URL:self.filteredVideoURL,
                                               size:Size(width: Float(size.width), height: Float(size.height)), liveVideo: true)
                movieIn --> selectedFilter --> movieOut
                try? FileManager.default.removeItem(at: self.filteredVideoURL)
                
                movieOut.startRecording()
                movieIn.start()
                movieOut.finishRecording({
                    self.selectedFilter.removeAllTargets()
                    movieIn.removeAllTargets()
                })
            }
            catch {
                print("Couldn't process movie with error: \(error)")
            }
        }
    }
    
    private let player = AVPlayer()
    private var isSessionRunning = false
    
    // Communicate with the session and other session objects on this queue.
    private let sessionQueue = DispatchQueue(label: "session queue", attributes: [], autoreleaseFrequency: .workItem)
    private let shareVideoQueue = DispatchQueue(label: "save to camera roll queue", attributes: [], autoreleaseFrequency: .workItem)
    private var exportVideoEnabled = true
    private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInDualCamera,
                                                                                             .builtInWideAngleCamera],
                                                                               mediaType: .video,
                                                                               position: .unspecified)
    private var videoDeviceInput: AVCaptureDeviceInput!
    private let videoOutput = AVCaptureMovieFileOutput()
    lazy var capturedVideoURL: URL = {
        let directory = NSTemporaryDirectory() as NSString
        return URL(fileURLWithPath: directory.appendingPathComponent("captured.mp4"))
    }()
    lazy var filteredVideoURL: URL = {
        let directory = NSTemporaryDirectory() as NSString
        return URL(fileURLWithPath: directory.appendingPathComponent("filtered.mp4"))
    }()
    
    func setupCaptureSession() {
        // Check video authorization status, video access is required
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // The user has previously granted access to the camera
            break
            
        case .notDetermined:
            /*
             The user has not yet been presented with the option to grant video access
             We suspend the session queue to delay session setup until the access request has completed
             */
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })
            
        default:
            // The user has previously denied access
            setupResult = .notAuthorized
        }
        
        /*
         Setup the capture session.
         In general it is not safe to mutate an AVCaptureSession or any of its
         inputs, outputs, or connections from multiple threads at the same time.
         
         Why not do all of this on the main queue?
         Because AVCaptureSession.startRunning() is a blocking call which can
         take a long time. We dispatch session setup to the sessionQueue so
         that the main queue isn't blocked, which keeps the UI responsive.
         */
        sessionQueue.async {
            self.configureSession()
        }
    }
    
    func startCaptureSession() {
        sessionQueue.async {
            if self.setupResult == .success {
                // Only setup observers and start the session running if setup succeeded
                //TODO: self.addObservers()
                self.captureSession.startRunning()
                self.isSessionRunning = self.captureSession.isRunning
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(Notification(name: .SWVideoManagerStartSession, object: self, userInfo: ["session": self.captureSession, "setupResult": self.setupResult]))
            }
        }
    }
    
    func stopCaptureSession() {
        sessionQueue.async {
            if self.setupResult == .success {
                self.captureSession.stopRunning()
                self.isSessionRunning = self.captureSession.isRunning
                //self.removeObservers()
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(Notification(name: .SWVideoManagerStopSession))
            }
        }
    }
    
    func tempURL() -> URL? {
        let directory = NSTemporaryDirectory() as NSString
        
        if directory != "" {
            let path = directory.appendingPathComponent(NSUUID().uuidString + ".mp4")
            return URL(fileURLWithPath: path)
        }
        
        return nil
    }
    
    func startRecording(_ videoOrientation: AVCaptureVideoOrientation?) {
        
        if self.isRecording == false {
            let connection = videoOutput.connection(with: AVMediaType.video)
            if (connection?.isVideoOrientationSupported)! {
                if let orientation = videoOrientation {
                    connection?.videoOrientation = orientation
                }
            }
            if (connection?.isVideoStabilizationSupported)! {
                connection?.preferredVideoStabilizationMode = AVCaptureVideoStabilizationMode.auto
            }
            
            let device = videoDeviceInput.device
            if (device.isSmoothAutoFocusSupported) {
                do {
                    try device.lockForConfiguration()
                    device.isSmoothAutoFocusEnabled = false
                    device.unlockForConfiguration()
                } catch {
                    print("Error setting configuration: \(error)")
                }
            }
            
            videoOutput.startRecording(to: self.capturedVideoURL, recordingDelegate: self)
        }
        else {
            stopRecording()
        }
        
    }
    
    func stopRecording() {
        if self.isRecording == true {
            videoOutput.stopRecording()
        }
    }
    
    func createVideoPlayer(url: URL) -> AVPlayer {
        let player = AVPlayer(url: url)
        return player
    }

    func setFilter() {
        
    }
    
    func applyFilter() {
        
    }
    
    func exportVideo(_ outputURL: URL) {
        switch PHPhotoLibrary.authorizationStatus() {
        case .authorized:
            self.exportVideoEnabled = true
            
            break
            
        case .notDetermined:
            shareVideoQueue.suspend()
            PHPhotoLibrary.requestAuthorization { status in
                self.exportVideoEnabled = (status == .authorized)
                self.shareVideoQueue.resume()
            }
            
        default:
            // The user has previously denied access
            self.exportVideoEnabled = false
        }
        
        self.shareVideoQueue.async {
            DispatchQueue.main.async {
                NotificationCenter.default.post(Notification(name: .SWVideoManagerStartExport, object: self, userInfo:
                    ["enabled":self.exportVideoEnabled, "outputFileURL": outputURL]))
            }
            if !self.exportVideoEnabled { return }
            
            PHPhotoLibrary.shared().performChanges({
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = true
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .video, fileURL: outputURL, options: options)
            }, completionHandler: { success, error in
                DispatchQueue.main.async {
                    NotificationCenter.default.post(Notification(name: .SWVideoManagerStopExport, object: self, userInfo:
                        ["success":success, "outputFileURL": outputURL]))
                }
                if !success {
                    guard let theError = error else { return }
                    print("An export error occurred: \(theError.localizedDescription)")
                    return
                }
            }
            )
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(Notification(name: .SWVideoManagerStartRecording, object: self, userInfo: ["captureFileOutput":output, "outputFileURL": fileURL]))
        }
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(Notification(name: .SWVideoManagerStopRecording, object: self, userInfo: ["captureFileOutput":output, "outputFileURL": outputFileURL]))
        }
    }
    
    //MARK: - Private
    
    // Call this on the session queue
    private func configureSession() {
        if setupResult != .success {
            return
        }
        
        let defaultVideoDevice: AVCaptureDevice? = videoDeviceDiscoverySession.devices.first
        
        guard let videoDevice = defaultVideoDevice else {
            print("Could not find any video device")
            setupResult = .configurationFailed
            return
        }
        
        do {
            videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
        } catch {
            print("Could not create video device input: \(error)")
            setupResult = .configurationFailed
            return
        }
        
        captureSession.beginConfiguration()
        
        captureSession.sessionPreset = AVCaptureSession.Preset.high
        
        // Add a video input
        guard captureSession.canAddInput(videoDeviceInput) else {
            print("Could not add video device input to the session")
            setupResult = .configurationFailed
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(videoDeviceInput)
        
        // Add a video data output
        guard captureSession.canAddOutput(videoOutput) else {
            print("Could not add video data output to the session")
            setupResult = .configurationFailed
            captureSession.commitConfiguration()
            return
        }
        captureSession.addOutput(videoOutput)
        
        captureSession.commitConfiguration()
    }
}
