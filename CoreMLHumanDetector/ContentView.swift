//
//  ContentView.swift
//  CoreMLHumanDetector
//
//  Created by Bill Vivino on 3/18/23.
//

import SwiftUI
import AVFoundation

enum Model {
    case modelOne
    case modelTwo
}

struct ContentView: View {
    @State private var avPlayer = AVPlayer()
    @State private var itemHasChanged = false
    @State private var model: Model = .modelOne
    @State private var selectionNumber = -1
    @AppStorage("selection") var selection: URL?
    
    var body: some View {
        NavigationStack {
            BodyTrackingViewController(avPlayer: $avPlayer, itemHasChanged: $itemHasChanged, model: $model)
                .navigationTitle("Body Detector")
                .toolbar {
                    ToolbarItemGroup(placement: .cancellationAction) {
                        Menu {
                            Button {
                                self.selection = Bundle.main.url(forResource: "video_1", withExtension: "mp4")
                                self.selectionNumber = 0
                            } label: {
                                HStack {
                                    Text("Video 1")
                                    if self.selectionNumber == 0 {
                                        Image(systemName: "checkmark")
                                    } else {
                                        Image(systemName: "video.fill")
                                    }
                                }
                            }
                            
                            Button {
                                self.selection = Bundle.main.url(forResource: "video_2", withExtension: "mp4")
                                self.selectionNumber = 1
                            } label: {
                                HStack {
                                    Text("Video 2")
                                    if self.selectionNumber == 1 {
                                        Image(systemName: "checkmark")
                                    } else {
                                        Image(systemName: "video.fill")
                                    }
                                }
                            }
                            
                            Button {
                                self.selection = Bundle.main.url(forResource: "video_3", withExtension: "mp4")
                                self.selectionNumber = 2
                            } label: {
                                HStack {
                                    Text("Video 3")
                                    if self.selectionNumber == 2 {
                                        Image(systemName: "checkmark")
                                    } else {
                                        Image(systemName: "video.fill")
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Load Video")
                                Image(systemName: "video.fill.badge.plus")
                            }
                            .padding(5)
                            .background {
                                RoundedRectangle(cornerRadius: 8.0)
                                    .fill(Color.gray)
                                    .opacity(0.5)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8.0)
                                            .stroke()
                                    }
                            }
                        }
                    }
                    
                    ToolbarItemGroup(placement: .primaryAction) {
                        Menu {
                            Button {
                                self.model = .modelOne
                            } label: {
                                HStack {
                                    Text("Model: YOLOv3FP16")
                                    if self.model == .modelOne {
                                        Image(systemName: "checkmark")
                                    } else {
                                        Image(systemName: "eye")
                                    }
                                }
                            }
                            
                            Button {
                                self.model = .modelTwo
                            } label: {
                                HStack {
                                    Text("Model: YOLOv3TinyFP16")
                                    if self.model == .modelTwo {
                                        Image(systemName: "checkmark")
                                    } else {
                                        Image(systemName: "eye.fill")
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Choose ML Model")
                            }
                            .padding(5)
                            .background {
                                RoundedRectangle(cornerRadius: 8.0)
                                    .fill(Color.gray)
                                    .opacity(0.5)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8.0)
                                            .stroke()
                                    }
                            }
                        }
                    }
                }
        }
        .onChange(of: selection) { newValue in
            if let selection = newValue {
                print(selection)
                avPlayer.replaceCurrentItem(with: AVPlayerItem(url: selection))
                self.itemHasChanged = true
            } else {
                avPlayer.replaceCurrentItem(with: nil)
                self.itemHasChanged = true
            }
        }
        .onChange(of: model) { newValue in
            self.itemHasChanged = true
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
