import SwiftUI
import AVFoundation
import Vision

struct ArtworkRecognitionView: View {
    @State private var classificationLabel: String = "Inquadra un'opera..."
    
    var body: some View {
        ZStack {
            CameraPreview(label: $classificationLabel)
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                Text("Capodimonte Scanner")
                    .font(.caption)
                    .padding(6)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .padding(.top, 40)
                
                Spacer()
                
                Text(classificationLabel)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 50)
            }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    @Binding var label: String
    
    func makeUIView(context: Context) -> CameraView {
        let view = CameraView()
        view.delegate = context.coordinator
        return view
    }
    
    func updateUIView(_ uiView: CameraView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(label: $label)
    }
    
    class Coordinator: NSObject, CameraViewDelegate {
        @Binding var label: String
        init(label: Binding<String>) { _label = label }
        
        func didDetectArtwork(name: String, confidence: Float) {
            DispatchQueue.main.async {
                if confidence > 0.6 {
                    self.label = "Opera: \(name.replacingOccurrences(of: "_", with: " "))\n(Sicurezza: \(Int(confidence * 100))%)"
                } else {
                    self.label = "Inquadra meglio..."
                }
            }
        }
        
        func didFailWith(error: String) {
            DispatchQueue.main.async {
                self.label = "ERRORE: \(error)"
            }
        }
    }
}

protocol CameraViewDelegate: AnyObject {
    func didDetectArtwork(name: String, confidence: Float)
    func didFailWith(error: String)
}

class CameraView: UIView, AVCaptureVideoDataOutputSampleBufferDelegate {
    weak var delegate: CameraViewDelegate?
    private let session = AVCaptureSession()
    private var model: VNCoreMLModel?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupModel()
        setupCamera()
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    private func setupModel() {
        do {
            let config = MLModelConfiguration()
            let coreMLModel = try capodimonte(configuration: config)
            self.model = try VNCoreMLModel(for: coreMLModel.model)
        } catch {
            delegate?.didFailWith(error: "Modello non caricato")
        }
    }
    
    private func setupCamera() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            delegate?.didFailWith(error: "Fotocamera non trovata (Sei sul simulatore?)")
            return
        }
        
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            delegate?.didFailWith(error: "Accesso camera negato")
            return
        }
        
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        session.addOutput(output)
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = self.bounds
        previewLayer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(previewLayer)
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        self.layer.sublayers?.forEach { $0.frame = self.bounds }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer), let model = model else { return }
        let request = VNCoreMLRequest(model: model) { request, error in
            if let results = request.results as? [VNClassificationObservation], let topResult = results.first {
                self.delegate?.didDetectArtwork(name: topResult.identifier, confidence: topResult.confidence)
            }
        }
        request.imageCropAndScaleOption = .centerCrop
        try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([request])
    }
}
