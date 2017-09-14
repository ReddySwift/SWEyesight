//
//  SWFilterVideoVC.swift
//  Eyesight
//
//  Created by Oleg Stepanenko on 07.09.17.
//  Copyright © 2017 StephanWhite. All rights reserved.
//

import UIKit
import AVFoundation
import GPUImage

class SWFilterVideoVC: UIViewController {

    let videoManager = SWVideoManager.instance
    private var selectedFilter : BasicOperation? {
        didSet {
            if let filter = oldValue {
                filter.removeAllTargets()
                movie.removeAllTargets()
            }
            if let filter = selectedFilter {
                movie --> filter --> renderView
            }
        }
    }
    var selectedFilterType : SWFilterType = SWFilterType.None {
        didSet {
            selectedFilter = SWFilterItem.createFilter(selectedFilterType)
        }
    }
    var movie : MovieInput! {
        didSet {
            if let movie = oldValue {
                movie.removeAllTargets()
            }
            guard
                let movie = movie,
                let filter = selectedFilter
                else { return }
            movie --> filter
        }
    }
    var videoURL: URL?
    
    @IBOutlet weak var renderView: RenderView!
    @IBOutlet weak var filterCollectionView: UICollectionView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        self.navigationController?.setNavigationBarHidden(false, animated: false)
        self.runMovie()
        movie --> renderView
        filterCollectionView.reloadData()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.stopMovie()
        videoManager.filters.forEach {filterItem in
            filterItem.filter.removeAllTargets()
        }
        movie.removeAllTargets()
    }

    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func stopMovie() {
        NSObject.cancelPreviousPerformRequests(withTarget: self,
                                               selector: #selector(self.runMovie),
                                               object: nil)
        if let movie = movie {
            movie.cancel()
        }
    }
    
    @objc func runMovie() {
        self.stopMovie()
        if let url = self.videoURL {
            do {
                let inputOptions = [AVURLAssetPreferPreciseDurationAndTimingKey:NSNumber(value:true)]
                let inputAsset = AVURLAsset(url:url, options:inputOptions)
                renderView.fillMode = .preserveAspectRatio
                renderView.orientation = self.orientationForAsset(inputAsset) ?? .portrait

                movie = try MovieInput(asset:inputAsset, playAtActualSpeed:true, loop:false)
                movie.runBenchmark = true
                movie.start()
                let duration = TimeInterval(inputAsset.duration.seconds+0)
                self.perform(#selector(self.runMovie), with: nil, afterDelay:duration)
            } catch {
                print("Couldn't process movie with error: \(error)")
            }
        }
    }
    
    func orientationForAsset(_ asset: AVAsset) -> ImageOrientation? {
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            return nil
        }
        let trackTransform = videoTrack.preferredTransform
        if trackTransform.a == -1 && trackTransform.d == -1 {
            return ImageOrientation.portraitUpsideDown
        } else if trackTransform.a == 1 && trackTransform.d == 1  {
            return ImageOrientation.portrait
        } else if trackTransform.b == -1 && trackTransform.c == 1 {
            return ImageOrientation.landscapeRight
        } else {
            return ImageOrientation.landscapeLeft
        }
    }
    
    @IBAction func filterMovie(_ sender: Any) {
        //filter movie
        self.stopMovie()
        self.selectedFilter?.removeAllTargets()
        self.movie?.removeAllTargets()
        if let filter = selectedFilter {
            do {
                let inputOptions = [AVURLAssetPreferPreciseDurationAndTimingKey:NSNumber(value:true)]
                let inputAsset = AVURLAsset(url:self.videoURL!, options:inputOptions)
                guard let videoTrack = inputAsset.tracks(withMediaType: .video).first else {
                    return
                }
                let size = videoTrack.naturalSize
                let movieIn = try MovieInput(asset:inputAsset, playAtActualSpeed:false, loop:false)
                let movieOut = try MovieOutput(URL:videoManager.filteredVideoURL,
                                               size:Size(width: Float(size.width), height: Float(size.height)))
                //movie.runBenchmark = true
                movieIn --> filter --> movieOut

                
                try? FileManager.default.removeItem(at: videoManager.filteredVideoURL)
                
                movieOut.startRecording()
                movieIn.start()
                movieOut.finishRecording({
                    filter.removeAllTargets()
                    movieIn.removeAllTargets()
                })
            }
            catch {
                print("Couldn't process movie with error: \(error)")
            }
        }
        self.performSegue(withIdentifier: "showPlayer", sender: nil)
    }
    
    // MARK: - Navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showPlayer" {
            if let destinationVC = segue.destination as? SWPlayVideoVC {
                if selectedFilterType != .none {
                    destinationVC.videoURL = videoManager.filteredVideoURL
                }
                else {
                    destinationVC.videoURL = self.videoURL
                }
            }
        }
    }

}

extension SWFilterVideoVC: UICollectionViewDelegate, UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return videoManager.filters.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "filterCell",
                                                      for: indexPath) as! SWFilterViewCell
        let item = videoManager.filters[indexPath.row]
        cell.filterItem = item
        cell.imageView.backgroundColor = selectedFilterType == item.id ? UIColor.gray : UIColor(white: 0.5, alpha: 0.3)
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        selectedFilterType = videoManager.filters[indexPath.row].id
        collectionView.reloadData()
    }
}
