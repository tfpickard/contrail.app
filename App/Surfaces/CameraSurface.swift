import SwiftUI
import AVFoundation

/// §7.1/§7.4: in-app still capture with a live preview, shutter, and share sheet
/// for the just-saved asset. Only meaningful mid-flight -- outside an active flight
/// there's no `FlightPlan`/`EstimatorOutput` to caption or tag the photo with.
struct CameraSurface: View {
    @Environment(AppModel.self) private var model
    @StateObject private var controller = PhotoCaptureController()
    @State private var shareURL: URL?

    var body: some View {
        Group {
            if !model.isFlightActive {
                ContentUnavailableView(
                    "No Active Flight", systemImage: "camera",
                    description: Text("Start a flight to caption and geotag photos automatically.")
                )
            } else {
                cameraBody
                    // Only spin up AVCaptureSession while there's actually a flight to
                    // caption a photo against -- starting it unconditionally on every
                    // appearance of this view would light the camera-in-use indicator
                    // and burn battery even when the "No Active Flight" state above is
                    // what's actually showing.
                    .task { await controller.start() }
            }
        }
        .navigationTitle("Camera")
    }

    private var cameraBody: some View {
        ZStack {
            if controller.isConfigured {
                CameraPreview(session: controller.session)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ProgressView("Starting camera…")
            }

            VStack {
                Spacer()
                if let error = controller.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.red.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.bottom, 8)
                }
                shutterButton
                    .padding(.bottom, 24)
            }
        }
        .onChange(of: controller.lastSavedFileURL) { _, url in
            shareURL = url
        }
        .sheet(item: Binding(get: { shareURL.map(IdentifiableURL.init) }, set: { shareURL = $0?.url })) { wrapped in
            ShareLink(item: wrapped.url) {
                Label("Share Last Photo", systemImage: "square.and.arrow.up")
            }
            .padding()
            .presentationDetents([.height(120)])
        }
    }

    @ViewBuilder
    private var shutterButton: some View {
        Button {
            capture()
        } label: {
            Circle()
                .strokeBorder(.white, lineWidth: 4)
                .frame(width: 72, height: 72)
                .overlay(Circle().fill(controller.isProcessing ? .gray : .white).padding(6))
        }
        .disabled(controller.isProcessing || !controller.isConfigured)
    }

    private func capture() {
        guard let output = model.latestOutput, let plan = model.flightPlan,
              let origin = model.originAirport, let destination = model.destinationAirport,
              let flightDirectory = model.currentFlightDirectory
        else { return }
        controller.capturePhoto(
            latestOutput: output, ringBuffer: model.photoRingBuffer,
            origin: origin, destination: destination, departureDate: plan.scheduledDeparture,
            flightDirectory: flightDirectory
        )
    }
}

private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
