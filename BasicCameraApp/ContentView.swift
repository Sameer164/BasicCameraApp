//
//  ContentView.swift
//  BasicCameraApp
//
//  Created by Sameer on 2/8/25.
//

import SwiftUI
import SwiftData
import AVFoundation

struct ContentView: View {
    var body: some View {
        CameraView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}

struct CameraView: View {
    @StateObject var camera = CameraModel()
    
    var body: some View {
        ZStack {
            if let depthMap = camera.depthMap {
                // Display the returned depth map image.
                Image(uiImage: depthMap)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .ignoresSafeArea()
                    .overlay(
                        // Overlay a retake button at the top.
                        HStack {
                            Button(action: {
                                // Reset the session and clear the depth map.
                                camera.resetBatch()
                                camera.depthMap = nil
                            }, label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundColor(.black)
                                    .padding()
                                    .background(Color.white.opacity(0.8))
                                    .clipShape(Circle())
                            })
                            .padding(.leading, 16)
                            .padding(.top, 16)
                            
                            Spacer()
                        }
                    )
            } else {
                // Show the camera preview with controls if no depth map exists.
                CameraPreview(camera: camera)
                    .ignoresSafeArea(.all, edges: .all)
                
                VStack {
                    // Top overlay: show a retake (reset) button if there are any pictures.
                    HStack {
                        Spacer()
                        if !camera.capturedImages.isEmpty && camera.capturedImages.count < 5 {
                            Button(action: {
                                camera.resetBatch()
                            }, label: {
                                Image(systemName: "arrow.triangle.2.circlepath.camera")
                                    .foregroundColor(.black)
                                    .padding()
                                    .background(Color.white)
                                    .clipShape(Circle())
                            })
                            .padding(.trailing, 10)
                        }
                    }
                    .padding(.top, 10)
                    
                    Spacer()
                    
                    // Display progress text.
                    Text("\(camera.capturedImages.count) / 5")
                        .foregroundColor(.white)
                        .font(.headline)
                        .padding(.bottom, 10)
                    
                    // Bottom controls.
                    if camera.capturedImages.count == 5 {
                        // When 5 pictures are captured, show Replace, Retake, and Send buttons.
                        HStack {
                            Button(action: {
                                camera.replaceLastPic()
                            }, label: {
                                Text("Replace")
                                    .foregroundColor(.black)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 10)
                                    .background(Color.white)
                                    .clipShape(Capsule())
                            })
                            
                            Spacer()
                            
                            Button(action: {
                                camera.resetBatch()
                            }, label: {
                                Text("Retake")
                                    .foregroundColor(.black)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 10)
                                    .background(Color.white)
                                    .clipShape(Capsule())
                            })
                            
                            Spacer()
                            
                            Button(action: {
                                Task {
                                    do {
                                        let depthImage = try await camera.sendImages()
                                        await MainActor.run {
                                            camera.depthMap = depthImage
                                        }
                                    } catch {
                                        print("Error sending images: \(error.localizedDescription)")
                                    }
                                }
                            }, label: {
                                Text("Send")
                                    .foregroundColor(.black)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 10)
                                    .background(Color.white)
                                    .clipShape(Capsule())
                            })
                        }
                        .padding(.horizontal)
                    } else {
                        // When fewer than 5 pictures have been taken.
                        HStack {
                            if !camera.capturedImages.isEmpty {
                                Button(action: {
                                    camera.replaceLastPic()
                                }, label: {
                                    Text("Replace")
                                        .foregroundColor(.black)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                        .background(Color.white)
                                        .clipShape(Capsule())
                                })
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                camera.takePic()
                            }, label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 65, height: 65)
                                    Circle()
                                        .stroke(Color.white, lineWidth: 2)
                                        .frame(width: 75, height: 75)
                                }
                            })
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            camera.Check()
        }
    }
}





class CameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    @Published var isTaken = false
    @Published var session = AVCaptureSession()
    @Published var alert = false
    @Published var output = AVCapturePhotoOutput()
    @Published var preview: AVCaptureVideoPreviewLayer!
    
    @Published var capturedImages: [Data] = []
    @Published var depthMap: UIImage? = nil

    
    func Check() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.setUp()
            return
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) {status in
                if status {
                    self.setUp()
                    return
                }
            }
        case .denied:
            self.alert.toggle()
            return
        default:
            return
        }
    }
    
    func setUp() {
        do{
            self.session.beginConfiguration()
            let device = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back)
            let input = try AVCaptureDeviceInput(device: device!)
            
            if self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            if self.session.canAddOutput(output){
                self.session.addOutput(output)
            }
            self.session.commitConfiguration()
            
        }catch {
            print(error.localizedDescription)
        }
    }
    
    func takePic(){
        guard self.capturedImages.count < 5 else { return }
        DispatchQueue.global(qos: .background).async {
            self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate:self)
        }
    }
    
    func resetBatch() {
            DispatchQueue.global(qos: .background).async {
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                DispatchQueue.main.async {
                    withAnimation {
                        self.capturedImages = []
                    }
                }
            }
        }

    
    func replaceLastPic() {
        if !capturedImages.isEmpty {
            capturedImages.removeLast()
            // If the session is not running (because 5 pics had been taken before) restart it.
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        if error != nil {
            return
        }
        guard let imageData = photo.fileDataRepresentation() else { return }
        DispatchQueue.main.async {
            self.capturedImages.append(imageData)
            print("Picture taken... count: \(self.capturedImages.count)")
            // When 5 images have been captured, stop the session.
            if self.capturedImages.count == 5 {
                self.session.stopRunning()
            }
        }
        
    }
    
    // Focus Implementation
    func focus(at point: CGPoint) {
        // Get the active capture device from the first input.
        guard let deviceInput = session.inputs.first as? AVCaptureDeviceInput else { return }
        let device = deviceInput.device
        
        do {
            try device.lockForConfiguration()
            
            // Check if the device supports focusing at a point of interest.
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            
            // Optionally adjust exposure as well.
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .continuousAutoExposure
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Error setting focus: \(error)")
        }
    }

}


struct CameraPreview: UIViewRepresentable {
    @ObservedObject var camera: CameraModel
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame:UIScreen.main.bounds)
        camera.preview = AVCaptureVideoPreviewLayer(session: camera.session)
        camera.preview.frame = view.frame
        camera.preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(camera.preview)
        
        //Adding tap gesture
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tapGesture)

        
        camera.session.startRunning()
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        
    }
    
    // Coordinator for Tap Gesture
    func makeCoordinator() -> Coordinator {
        Coordinator(camera: camera)
    }
    
    // Coordinator to handle tap gestures.
    
    class Coordinator: NSObject {
            var camera: CameraModel
            
            init(camera: CameraModel) {
                self.camera = camera
            }
            
            @objc func handleTap(_ sender: UITapGestureRecognizer) {
                guard let tappedView = sender.view,
                      let previewLayer = camera.preview else { return }
                
                // Get the tap location in the view.
                let location = sender.location(in: tappedView)
                
                // Convert the location to the camera’s coordinate space.
                let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: location)
                
                // Call the focus method on the camera model.
                camera.focus(at: devicePoint)
            }
        }
}

enum NetworkError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The URL provided is invalid. Please verify the endpoint."
        case .invalidResponse:
            return "The server responded with an unexpected status code. Check your network connection or server."
        case .invalidData:
            return "The data received from the server was invalid or corrupted."
        }
    }
}


extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}


extension CameraModel {
    
    /// Sends the captured images to the server and returns the response string.
    func sendImages() async throws -> UIImage {
        let endpoint = "https://ff19-76-69-193-101.ngrok-free.app/upload"
        guard let url = URL(string: endpoint) else {
            throw NetworkError.invalidURL
        }
        
        // Prepare the URLRequest.
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Create a unique boundary string.
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Build the multipart/form-data body.
        let body = createBody(with: capturedImages, boundary: boundary)
        request.httpBody = body
        
        // Execute the request using async/await.
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Verify the response status code is 200 (OK).
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NetworkError.invalidResponse
        }
        
        guard let image = UIImage(data: data) else {
            throw NetworkError.invalidData
        }
        return image

        
    }
    
    /// Helper function to create the multipart/form-data body.
    private func createBody(with images: [Data], boundary: String) -> Data {
        var body = Data()
        
        // Loop through each image in the capturedImages array.
        for (index, imageData) in images.enumerated() {
            let paramName = "image\(index + 1)"
            let filename = "image\(index + 1).jpg"
            
            // Append the starting boundary.
            body.appendString("--\(boundary)\r\n")
            
            // Append the Content-Disposition.
            body.appendString("Content-Disposition: form-data; name=\"\(paramName)\"; filename=\"\(filename)\"\r\n")
            
            // Append the Content-Type.
            body.appendString("Content-Type: image/jpeg\r\n\r\n")
            
            // Append the actual image data.
            body.append(imageData)
            body.appendString("\r\n")
        }
        
        // Append the closing boundary.
        body.appendString("--\(boundary)--\r\n")
        
        return body
    }
}
