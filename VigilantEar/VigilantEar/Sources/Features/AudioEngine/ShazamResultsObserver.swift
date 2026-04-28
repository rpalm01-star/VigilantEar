//
//  ShazamResultsObserver.swift
//  VigilantEar
//
//  Created by Robert Palmer on 4/24/26.
//


import ShazamKit

final class ShazamResultsObserver: NSObject, @unchecked Sendable, SHSessionDelegate {
    private weak var pipeline: AcousticProcessingPipeline?
    
    nonisolated init(pipeline: AcousticProcessingPipeline) {
        self.pipeline = pipeline
        super.init()
    }
    
    nonisolated func session(_ session: SHSession, didFind match: SHMatch) {
        guard let mediaItem = match.mediaItems.first,
              let title = mediaItem.title,
              let artist = mediaItem.artist else { return }
        
        AppGlobals.doLog(message: "🎵 Shazam Match Found: \(title)", step: "Shazam")
        
        Task {
            await pipeline?.registerSongMatch(title: title, artist: artist)
        }
    }
    
    nonisolated func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {
        if let err = error {
            AppGlobals.doLog(message: "🎵 Shazam Error: \(err.localizedDescription)", step: "Shazam")
        }
    }
}
