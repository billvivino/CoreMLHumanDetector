//
//  BodyTrackingViewController.swift
//  Basketball Path Tracking
//
//  Created by Bill Vivino on 8/25/22.
//

import Foundation

import Foundation
import SwiftUI
import AVKit

struct BodyTrackingViewController: UIViewControllerRepresentable {
    @Binding var avPlayer: AVPlayer
    @Binding var itemHasChanged: Bool
    @Binding var model: Model
    
    func makeUIViewController(context: Context) -> VideoVC {
        let videoVC = VideoVC(nibName: nil, bundle: nil)
        videoVC.player = self.avPlayer
        videoVC.model = self.model
        return videoVC
    }
    
    func updateUIViewController(_ uiViewController: VideoVC, context: Context) {
        if itemHasChanged {
            uiViewController.viewDidLoad()
            itemHasChanged = false
        }
    }
    
    typealias UIViewControllerType = VideoVC
}
