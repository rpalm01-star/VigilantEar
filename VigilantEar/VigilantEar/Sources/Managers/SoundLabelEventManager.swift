//
//  SoundLabelEventManager.swift
//  VigilantEar
//
//  Created by Robert Palmer on 4/30/26.
//
import Foundation

actor SoundLabelEventManager {
    private var events: [String: SoundLabelEvent] = [:]
    
    var agingThreshold: TimeInterval = 1.0 {
        didSet { performCleanup() }
    }
    
    // MARK: - Streams
    private var eventContinuation: AsyncStream<[SoundLabelEvent]>.Continuation?
    private var newEventContinuation: AsyncStream<SoundLabelEvent>.Continuation?
    
    nonisolated func eventChanges() -> AsyncStream<[SoundLabelEvent]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [SoundLabelEvent].self)
        Task { await self.setEventContinuation(continuation) }
        return stream
    }
    
    nonisolated func newEvents() -> AsyncStream<SoundLabelEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: SoundLabelEvent.self)
        Task { await self.setNewEventContinuation(continuation) }
        return stream
    }
    
    private func setEventContinuation(_ continuation: AsyncStream<[SoundLabelEvent]>.Continuation) {
        self.eventContinuation = continuation
        continuation.yield(Array(events.values))
    }
    
    private func setNewEventContinuation(_ continuation: AsyncStream<SoundLabelEvent>.Continuation) {
        self.newEventContinuation = continuation
    }
    
    private func notifyListeners() {
        eventContinuation?.yield(Array(events.values))
    }
    
    private func performCleanup() {
        let cutoff = Date().addingTimeInterval(-agingThreshold)
        events = events.filter { $0.value.creationTime >= cutoff }
        notifyListeners()
    }
    
    // MARK: - Private core logic
    private func _addOrUpdate(_ rawMLSoundLabel: String, confidence: Double) async {
        let now = Date()
        
        events.removeValue(forKey: rawMLSoundLabel)   // remove any previous
        
        let event = SoundLabelEvent(
            rawMLSoundLabel: rawMLSoundLabel,
            creationTime: now,
            confidence: confidence
        )
        events[rawMLSoundLabel] = event
        
        performCleanup()
        newEventContinuation?.yield(event)
    }
    
    // MARK: - Public API (only this one)
    nonisolated func addOrUpdateDetached(_ rawMLSoundLabel: String, confidence: Double) {
        Task.detached { [weak self] in
            await self?._addOrUpdate(rawMLSoundLabel, confidence: confidence)
        }
    }
    
    // MARK: - Query methods (still async, as they should be)
    func currentEvents() async -> [SoundLabelEvent] {
        performCleanup()
        return Array(events.values)
    }
    
    func uniqueLabels() async -> [String] {
        performCleanup()
        return Array(events.keys).sorted()
    }
    
    func filterEvents(keeping predicate: @Sendable (SoundLabelEvent) -> Bool) async {
        events = events.filter { predicate($0.value) }
        notifyListeners()
    }
    
    func clear() async {
        events.removeAll()
        notifyListeners()
    }
}
