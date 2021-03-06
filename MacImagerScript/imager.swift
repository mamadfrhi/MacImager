//
//  main.swift
//  MacImager
//
//  Created by iMamad on 28.05.22.
//

import Foundation
import AppKit
import Network

// MARK: COMMAND HELPER
func shell(_ command: String) -> String {
    let task = Process()
    let pipe = Pipe()
    
    task.standardOutput = pipe
    task.standardError = pipe
    task.arguments = ["-c", command]
    task.launchPath = "/bin/zsh"
    task.standardInput = nil
    task.launch()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)!
    
    return output
}

// MARK: MODEL
struct image : Decodable {
    let urls: [String : URL]
}

// MARK: - PROPERTIES
let generalSemaphore = DispatchSemaphore(value: 0)
var docDirStr = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/").absoluteString
let screens = NSScreen.screens
let dpg = DispatchGroup()

// MARK: - FUNCTIONS
// MARK: NETWORK HELPERS
enum Orientation : String {
    case landscape = "landscape"
    case portrait = "portrait"
}
private func makeURLRequest(screenSize: CGSize,
                            orientation: Orientation,
                            imageTopic: String) -> URLRequest {
    let clientID = "eSG6DfH3BRBdhKHLi5-MMY8CWQjTpfAhcHyOMBY4G-Y"
    var urlString = "https://api.unsplash.com/photos/random?" + "client_id=" + clientID
    let parameters = [
        ["query" : imageTopic],
        ["w" : "\(screenSize.width)"],
        ["h" : "\(screenSize.height)"],
        ["orientation" : orientation.rawValue]
    ]
    for parameter in parameters {
        let key = parameter.keys.first!
        let value = parameter.values.first!
        let str = "&" + key + "=" + value
        urlString.append(contentsOf: str)
    }
    let url = URL(string: urlString)!
    return URLRequest(url: url)
}
private func makeImageURL(with index: Int) -> URL {
    let imageURLStr = docDirStr + "/" + "desktop-image-\(index).jpeg"
    return URL(string: imageURLStr)!
}
private func checkInternet(internet: @escaping (Bool) -> Void) {
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { path in
        if path.status == .satisfied {
            internet(true)
        } else {
            internet(false)
        }
    }
    monitor.start(queue: DispatchQueue.global())
}

// MARK: - CONTROLLER
// 3
private func updateDesktop() {
    for i in 0 ..< screens.count {
        let imageURL = makeImageURL(with: i)
        let screen = NSScreen.screens[i]
        try? NSWorkspace.shared.setDesktopImageURL(imageURL, for: screen, options: [:])
        print("Monitor \(i) set!")
    }
    
    let _ = shell("killall Dock")
    print("All done! :p")
    generalSemaphore.signal()
}

// 2
private func downloadNewWallpapers(imageTopic: String) {
    for (i, screen) in screens.enumerated() {
        dpg.enter()
        
        // extract screen feature
        let frame = screen.frame
        let size = CGSize(width: frame.width, height: frame.height)
        var orientation : Orientation = .landscape
        if size.height > size.width { // the screen is portrait
            orientation = .portrait
        }
        
        // start request
        let urlReq = makeURLRequest(screenSize: size, orientation: orientation, imageTopic: imageTopic)
        URLSession.shared.dataTask(with: urlReq) { (data, response, error) in
            if let jsonData = try? JSONDecoder().decode(image.self, from: data!),
               let rawImageURL = jsonData.urls["raw"],
               let imageData = try? Data(contentsOf: rawImageURL) {
                let imageURL = makeImageURL(with: i)
                if let _ = try? imageData.write(to: imageURL) {
                    dpg.leave()
                    print("Image \(i) has been written.")
                } else {
                    print("Can't write downloaded image \(i) on file!")
                    dpg.leave()
                }
            } else {
                print("Error while download and decoding JSON file of the image \(i)!")
                dpg.leave()
            }
        }
        .resume()
    }
    
    dpg.notify(queue: .global()) {
        updateDesktop()
    }
}

// 1
private func requestDownload(imageTopic: String) {
    // PROBLEM: if decrease .now() + 60 to .now() + 5
    // and net will be off and it calls the current function 3 times
    // it'll download 4 images for each monitor
    checkInternet { net in
        if net {
            downloadNewWallpapers(imageTopic: imageTopic)
        } else {
            print("Internet Connection isn't connected!")
            DispatchQueue.global().asyncAfter(deadline: .now() + 60) {
                requestDownload(imageTopic: imageTopic)
            }
        }
    }
}

// 0
let defaultImageTopic = "minimal"
let arguments = CommandLine.arguments
if arguments.count > 1 && arguments[1].count > 0 { // the first argument is always name of the script file
    let imageTopic = CommandLine.arguments[1]
    print("I'm gonna download ", imageTopic)
    requestDownload(imageTopic: imageTopic)
} else {
    print("I'm gonna download ", defaultImageTopic)
    requestDownload(imageTopic: defaultImageTopic)
}
generalSemaphore.wait()
