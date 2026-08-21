import Foundation
import AVFoundation
import Photos
import ContrailCore
import ContrailData
import ContrailPhoto

/// §7.1/§7.2: drives still capture end to end -- `AVCapturePhotoOutput` for the
/// shutter itself, then the post-shutter wait (the ring buffer's "ten seconds
/// after," per §7.1) before the JPEG is finalized with all three metadata tiers and
/// saved to Photos. Deliberately photo-only: §7.1 also asks for video, but video
/// metadata embedding is a materially different mechanism (MP4/QuickTime atoms, not
/// JPEG APP segments) with its own real engineering scope -- cut whole, not
/// partially built, matching this build's own "cut by whole feature" rule. Flagged
/// here rather than silently doing less than the spec's own wording suggests.
@MainActor
final class PhotoCaptureController: NSObject, ObservableObject {
    struct PendingCapture {
        let captureUptime: TimeInterval
        let instantaneousOutput: EstimatorOutput
        let preWindow: [EstimatorOutput]
        let title: String
        let description: String
    }

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var pendingCaptures: [Int64: PendingCapture] = [:]

    @Published private(set) var isConfigured = false
    @Published private(set) var isProcessing = false
    @Published private(set) var lastError: String?
    /// A temp-file copy of the just-saved JPEG, for the share sheet -- a `URL` (not
    /// `UIImage`, which isn't `Equatable`) so SwiftUI's `.onChange(of:)` can drive
    /// the share sheet's presentation directly off it.
    @Published private(set) var lastSavedFileURL: URL?

    /// Requests camera + Photos-add authorization and configures the capture
    /// session. Safe to call once; a second call is a no-op if already configured.
    func start() async {
        guard !isConfigured else { return }

        let cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        guard cameraGranted else {
            lastError = "Camera access was denied."
            return
        }
        let photosStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard photosStatus == .authorized || photosStatus == .limited else {
            lastError = "Photos access was denied -- captures can't be saved."
            return
        }

        do {
            try configureSession()
            isConfigured = true
            // `AVCaptureSession.startRunning()` is a blocking call Apple's own docs
            // say to make from a background queue -- plain GCD, not `Task`, since
            // `AVCaptureSession` predates `Sendable` and a `Task.detached` closure
            // capturing it trips Swift 6's data-race checking for no real benefit.
            DispatchQueue.global(qos: .userInitiated).async { [session] in
                session.startRunning()
            }
        } catch {
            lastError = "Could not start the camera: \(error)"
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
        else {
            throw CaptureError.noCameraAvailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CaptureError.cannotConfigure }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else { throw CaptureError.cannotConfigure }
        session.addOutput(photoOutput)
    }

    enum CaptureError: Error {
        case noCameraAvailable
        case cannotConfigure
    }

    /// Triggers the shutter. The actual save happens ~10s later, after the ring
    /// buffer has accumulated the post-shutter half of §7.1's window -- `isProcessing`
    /// stays true for that whole span so the UI can show it's still working.
    func capturePhoto(
        latestOutput: EstimatorOutput, ringBuffer: PhotoRingBuffer,
        origin: AirportRecord, destination: AirportRecord, departureDate: Date,
        flightDirectory: URL
    ) {
        guard isConfigured else { return }
        isProcessing = true
        lastError = nil

        let title = PhotoCaptionGenerator.title(
            origin: origin, destination: destination, departureDate: departureDate,
            nearestCity: latestOutput.route.nearestCity.value, phase: latestOutput.phase.value
        )
        let description = PhotoCaptionGenerator.description(
            altitudeMetres: latestOutput.position.altitudeGPS.value,
            groundspeedMS: latestOutput.motion.groundspeed.value,
            edrCubeRoot: latestOutput.turbulence.edrCubeRoot.value,
            nearestCity: latestOutput.route.nearestCity.value
        )

        let settings = AVCapturePhotoSettings()
        pendingCaptures[settings.uniqueID] = PendingCapture(
            captureUptime: latestOutput.uptime, instantaneousOutput: latestOutput,
            preWindow: ringBuffer.window(around: latestOutput.uptime, halfWidth: 10),
            title: title, description: description
        )
        photoOutput.capturePhoto(with: settings, delegate: self)

        // Hand the post-shutter finalization off to a task keyed by this capture's
        // uptime rather than blocking the caller -- `ringBuffer` keeps accumulating
        // real samples for these 10 seconds via the caller's own ongoing updates.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            await self?.finalize(uniqueID: settings.uniqueID, ringBuffer: ringBuffer, flightDirectory: flightDirectory)
        }
    }

    private func finalize(uniqueID: Int64, ringBuffer: PhotoRingBuffer, flightDirectory: URL) async {
        defer { isProcessing = false }
        guard let pending = pendingCaptures.removeValue(forKey: uniqueID) else { return }
        guard let jpegData = capturedJPEGData.removeValue(forKey: uniqueID) else {
            lastError = "Photo capture did not produce image data."
            return
        }

        do {
            let finalJPEG = try PhotoMetadataWriter.embedMetadata(
                into: jpegData, capturedAt: pending.instantaneousOutput,
                title: pending.title, description: pending.description
            )
            let assetID = try await save(finalJPEG)

            let postWindow = ringBuffer.window(around: pending.captureUptime, halfWidth: 10)
            try writeSidecar(
                assetID: assetID, preWindow: pending.preWindow, postWindow: postWindow,
                capturedOutput: pending.instantaneousOutput, title: pending.title, description: pending.description,
                flightDirectory: flightDirectory
            )

            let shareURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
            try finalJPEG.write(to: shareURL, options: .atomic)
            lastSavedFileURL = shareURL
        } catch {
            lastError = "Could not finish saving the photo: \(error)"
        }
    }

    private func save(_ jpegData: Data) async throws -> String {
        var placeholderID: String?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: jpegData, options: nil)
            placeholderID = request.placeholderForCreatedAsset?.localIdentifier
        }
        guard let placeholderID else { throw CaptureError.cannotConfigure }
        return placeholderID
    }

    /// §7.2: "write a sidecar snapshot record ... alongside the flight log, keyed by
    /// the Photos asset local identifier." Written to local storage next to
    /// `manifest.json`/`samples.ndjson` -- iCloud replication is deferred for the
    /// flight log itself (see `AppModel.flightDirectory`'s own doc comment) and this
    /// follows the same, already-accepted deferral rather than being a special case.
    private func writeSidecar(
        assetID: String, preWindow: [EstimatorOutput], postWindow: [EstimatorOutput],
        capturedOutput: EstimatorOutput, title: String, description: String, flightDirectory: URL
    ) throws {
        struct Sidecar: Encodable {
            let assetID: String
            let title: String
            let description: String
            let capturedAt: EstimatorOutput
            let preWindow: [EstimatorOutput]
            let postWindow: [EstimatorOutput]
        }
        let sidecar = Sidecar(
            assetID: assetID, title: title, description: description,
            capturedAt: capturedOutput, preWindow: preWindow, postWindow: postWindow
        )
        let photosDirectory = flightDirectory.appendingPathComponent("Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let safeFilename = assetID.replacingOccurrences(of: "/", with: "_")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(sidecar).write(
            to: photosDirectory.appendingPathComponent("\(safeFilename).json"), options: .atomic
        )
    }

    private var capturedJPEGData: [Int64: Data] = [:]
}

extension PhotoCaptureController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?
    ) {
        let uniqueID = photo.resolvedSettings.uniqueID
        let data = photo.fileDataRepresentation()
        Task { @MainActor [weak self] in
            if let data {
                self?.capturedJPEGData[uniqueID] = data
            } else {
                self?.lastError = "Photo capture failed: \(error?.localizedDescription ?? "no image data")"
            }
        }
    }
}
