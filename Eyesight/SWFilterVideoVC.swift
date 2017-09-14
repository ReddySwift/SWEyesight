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
    /// Context used in KVO to identify selectedFilter changes.
    private var selectedFilterObservationContext = 0

    let videoManager = SWVideoManager.instance
    
    @IBOutlet weak var renderView: RenderView!
    @IBOutlet weak var filterCollectionView: UICollectionView!
    
    override func viewWillAppear(_ animated: Bool) {
        self.navigationController?.setNavigationBarHidden(false, animated: false)
        self.runMovie()
        videoManager.selectedFilter --> renderView
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        videoManager.stopFilterMovie()
        videoManager.filterMovie = nil
        videoManager.selectedFilter.removeAllTargets()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @objc func runMovie() {
        if let asset = videoManager.filterMovieAsset() {
            renderView.fillMode = .preserveAspectRatio
            renderView.orientation = self.orientationForAsset(asset) ?? .portrait
            videoManager.runFilterMovie()
            
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
        videoManager.makeFilteredMovie()
        self.performSegue(withIdentifier: "showPlayer", sender: nil)
    }

    // MARK: - Navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showPlayer" {
            if let destinationVC = segue.destination as? SWPlayVideoVC {
                var videoURL = videoManager.filteredVideoURL
                if (videoManager.selectedFilterType == .None || !FileManager.default.fileExists(atPath: videoURL.absoluteString)),
                    let url = videoManager.filterMovieURL {
                    videoURL = url
                }
                destinationVC.videoURL = videoURL
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
        cell.imageView.backgroundColor = videoManager.selectedFilterType == item.id ? UIColor.gray : UIColor(white: 0.5, alpha: 0.3)
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        videoManager.selectedFilterType = videoManager.filters[indexPath.row].id
        videoManager.selectedFilter --> renderView
        collectionView.reloadData()
    }
}
