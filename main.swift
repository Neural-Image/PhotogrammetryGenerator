/*
 
Developed by Nova Lu, October 2023, NeuralImage Corp.

Photogrammetry Generator 1.0 based on Apple's RealityKit.
 
*/

import ArgumentParser
import Foundation
import os
import RealityKit
import Metal
import ModelIO

private let logger = Logger(subsystem: "com.apple.sample.photogrammetry",
                            category: "HelloPhotogrammetry")

struct PhotogrammetryGenerator: ParsableCommand {
    
    private typealias Configuration = PhotogrammetrySession.Configuration
    private typealias Request = PhotogrammetrySession.Request
    
    public static let configuration = CommandConfiguration(
        abstract: "Reconstructs 3D mesh from a folder of images.")
    
    @Argument(help: "The local input file folder of images.")
    private var inputFolder: String
    
    @Argument(help: "Full path to the output file.")
    private var outputFilename: String
    
    @Option(name: .shortAndLong,
            parsing: .next,
            help: "detail {preview, reduced, medium, full, raw}  Detail level of the output.",
            transform: Request.Detail.init)
    private var detail: Request.Detail? = nil
    
    @Option(name: [.customShort("o"), .long],
            parsing: .next,
            help: "sampleOrdering {unordered, sequential}  Set to sequential if the input images are captured specifically in sequential order.",
            transform: Configuration.SampleOrdering.init)
    private var sampleOrdering: Configuration.SampleOrdering?
    
    @Option(name: .shortAndLong,
            parsing: .next,
            help: "featureSensitivity {normal, high}  Set to high if the scanned object does not contain a lot of discernible structures, edges or textures.",
            transform: Configuration.FeatureSensitivity.init)
    private var featureSensitivity: Configuration.FeatureSensitivity?
    
    func run() {
        guard PhotogrammetrySession.isSupported else {
            logger.error("Failed to run. Hardware doesn't support Object Capture.")
            print("Object Capture is not available on this computer.")
            Foundation.exit(1)
        }
        
        let inputFolderUrl = URL(fileURLWithPath: inputFolder, isDirectory: true)
        let configuration = makeConfigurationFromArguments()
        logger.log("Using configuration: \(String(describing: configuration))")
        
        var maybeSession: PhotogrammetrySession? = nil
        do {
            maybeSession = try PhotogrammetrySession(input: inputFolderUrl,
                                                     configuration: configuration)
            logger.log("Successfully created session.")
        } catch {
            logger.error("Error creating session: \(String(describing: error))")
            Foundation.exit(1)
        }
        guard let session = maybeSession else {
            Foundation.exit(1)
        }
        
        let waiter = Task {
            do {
                for try await output in session.outputs {
                    switch output {
                        case .processingComplete:
                            logger.log("Processing succesfully completed.")
                            let objPath = "/Users/nova/Downloads/test.obj"
                            let modelAsset = MDLAsset(url: URL(fileURLWithPath: outputFilename))
                            modelAsset.loadTextures()
                            do {
                                try modelAsset.export(to:URL(fileURLWithPath: objPath))
                                print("OBJ file exported.")
                            }
                            catch {
                                print(error)
                            }
                            Foundation.exit(0)
                        case .requestError(let request, let error):
                            logger.error("Request \(String(describing: request)) had an error: \(String(describing: error))")
                        case .requestComplete(let request, let result):
                            PhotogrammetryGenerator.handleRequestComplete(request: request, result: result)
                        case .requestProgress(let request, let fractionComplete):
                            PhotogrammetryGenerator.handleRequestProgress(request: request,
                                                                      fractionComplete: fractionComplete)
                        case .inputComplete:  // data ingestion only
                            logger.log("Data ingestion is complete.  Beginning processing...")
                        case .invalidSample(let id, let reason):
                            logger.warning("Invalid Sample id=\(id)  reason=\"\(reason)\"")
                        case .skippedSample(let id):
                            logger.warning("Sample id=\(id) was skipped by processing.")
                        case .automaticDownsampling:
                            logger.warning("Automatic downsampling applied.")
                        case .processingCancelled:
                            logger.warning("Processing cancelled.")
                        @unknown default:
                            logger.error("Output: unhandled message: \(output.localizedDescription)")

                    }
                }
            } catch {
                logger.error("Output: ERROR = \(String(describing: error))")
                Foundation.exit(0)
            }
        }
        
        // Prevent the compiler from mistakenly deallocating some objects.
        withExtendedLifetime((session, waiter)) {
            do {
                let request = makeRequestFromArguments()
                logger.log("Using request: \(String(describing: request))")
                try session.process(requests: [ request ])
                RunLoop.main.run()
            } catch {
                logger.critical("Process got error: \(String(describing: error))")
                Foundation.exit(1)
            }
        }
    }

    // Configurate the session based on input argument.
    private func makeConfigurationFromArguments() -> PhotogrammetrySession.Configuration {
        var configuration = PhotogrammetrySession.Configuration()
        sampleOrdering.map { configuration.sampleOrdering = $0 }
        featureSensitivity.map { configuration.featureSensitivity = $0 }
        return configuration
    }

    // Make the request from command-line arguments.
    private func makeRequestFromArguments() -> PhotogrammetrySession.Request {
        let outputUrl = URL(fileURLWithPath: outputFilename)
        if let detailSetting = detail {
            return PhotogrammetrySession.Request.modelFile(url: outputUrl, detail: detailSetting)
        } else {
            return PhotogrammetrySession.Request.modelFile(url: outputUrl)
        }
    }
    
    // The session completed.
    private static func handleRequestComplete(request: PhotogrammetrySession.Request,
                                              result: PhotogrammetrySession.Result) {
        logger.log("Request complete: \(String(describing: request)) with result...")
        switch result {
            case .modelFile(let url):
                logger.log("\tmodelFile available at url=\(url)")
            default:
                logger.warning("\tUnexpected result: \(String(describing: result))")
        }
    }
    
    // The session has a progress update.
    private static func handleRequestProgress(request: PhotogrammetrySession.Request,
                                              fractionComplete: Double) {
        logger.log("Progress(request = \(String(describing: request)) = \(fractionComplete)")
    }

}

// MARK: Extension

private func handleRequestProgress(request: PhotogrammetrySession.Request,
                                   fractionComplete: Double) {
    print("Progress(request = \(String(describing: request)) = \(fractionComplete)")
}

// Option illegal.
private enum IllegalOption: Swift.Error {
    case invalidDetail(String)
    case invalidSampleOverlap(String)
    case invalidSampleOrdering(String)
    case invalidFeatureSensitivity(String)
}

// Verify the input arguments.
@available(macOS 12.0, *)
extension PhotogrammetrySession.Request.Detail {
    init(_ detail: String) throws {
        switch detail {
            case "preview": self = .preview
            case "reduced": self = .reduced
            case "medium": self = .medium
            case "full": self = .full
            case "raw": self = .raw
            default: throw IllegalOption.invalidDetail(detail)
        }
    }
}

@available(macOS 12.0, *)
extension PhotogrammetrySession.Configuration.SampleOrdering {
    init(sampleOrdering: String) throws {
        if sampleOrdering == "unordered" {
            self = .unordered
        } else if sampleOrdering == "sequential" {
            self = .sequential
        } else {
            throw IllegalOption.invalidSampleOrdering(sampleOrdering)
        }
    }
    
}

@available(macOS 12.0, *)
extension PhotogrammetrySession.Configuration.FeatureSensitivity {
    init(featureSensitivity: String) throws {
        if featureSensitivity == "normal" {
            self = .normal
        } else if featureSensitivity == "high" {
            self = .high
        } else {
            throw IllegalOption.invalidFeatureSensitivity(featureSensitivity)
        }
    }
}

// MARK: - Main process

if #available(macOS 12.0, *) {
    PhotogrammetryGenerator.main()
} else {
    fatalError("Requires minimum macOS 12.0.")
}
