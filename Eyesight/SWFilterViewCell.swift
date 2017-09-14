//
//  SWFilterViewCell.swift
//  Eyesight
//
//  Created by Oleg Stepanenko on 13.09.17.
//  Copyright © 2017 StephanWhite. All rights reserved.
//

import UIKit
import GPUImage

class SWFilterViewCell: UICollectionViewCell {
    
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    
    override func layoutSubviews() {
        imageView.layer.cornerRadius = frame.size.width / 2
    }
    
    var filterItem: SWFilterItem! {
        didSet {
            titleLabel.text = filterItem.title
            //imageView.image = filterItem.image
        }
    }
    
}
