import SwiftUI
import AVFoundation

/// Prompt 4: Caption Editor UI
/// Scrollable segment timeline, tap to seek, inline text editing, steppers for timing,
/// split, merge, delete, add caption at playhead, word highlight toggle, and full undo/redo.
public struct CaptionEditorView: View {
    @Binding public var segments: [CaptionSegment]
    public let currentTime: TimeInterval
    public let onSeek: (TimeInterval) -> Void
    
    // Undo / Redo stacks
    @State private var undoStack: [[CaptionSegment]] = []
    @State private var redoStack: [[CaptionSegment]] = []
    @State private var selectedSegmentID: UUID?
    
    public init(
        segments: Binding<[CaptionSegment]>,
        currentTime: TimeInterval,
        onSeek: @escaping (TimeInterval) -> Void
    ) {
        self._segments = segments
        self.currentTime = currentTime
        self.onSeek = onSeek
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            // 1. Editor Header Toolbar (Undo, Redo, Add at Playhead)
            editorToolbar
                .padding(.horizontal)
            
            if segments.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "captions.bubble")
                        .font(.system(size: 36))
                        .foregroundColor(.gray)
                    Text("No Captions Detected")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    Text("Spoken words from your video appear here automatically. You can also manually add captions at the current timestamp.")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Button(action: addCaptionAtPlayhead) {
                        Label("Add Caption at Playhead", systemImage: "plus.circle.fill")
                            .font(.footnote.bold())
                            .foregroundColor(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.yellow))
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 30)
            } else {
                // 2. Scrollable Segment List
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 10) {
                            ForEach($segments) { $segment in
                                let isPlayingNow = currentTime >= segment.start && currentTime <= segment.end
                                let isSelected = selectedSegmentID == segment.id
                                
                                segmentRow(segment: $segment, isPlayingNow: isPlayingNow, isSelected: isSelected)
                                    .id(segment.id)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                    .onChange(of: currentTime) { time in
                        // Auto-scroll to current active segment if desired
                        if let active = segments.first(where: { time >= $0.start && time <= $0.end }) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(active.id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Editor Toolbar (Undo, Redo, Add)
    private var editorToolbar: some View {
        HStack(spacing: 12) {
            // Undo Button
            Button(action: performUndo) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.title3)
                    .foregroundColor(undoStack.isEmpty ? .gray : .white)
            }
            .disabled(undoStack.isEmpty)
            
            // Redo Button
            Button(action: performRedo) {
                Image(systemName: "arrow.uturn.forward.circle.fill")
                    .font(.title3)
                    .foregroundColor(redoStack.isEmpty ? .gray : .white)
            }
            .disabled(redoStack.isEmpty)
            
            Spacer()
            
            // Add Caption at Playhead
            Button(action: addCaptionAtPlayhead) {
                Label("Add at Playhead", systemImage: "plus.bubble.fill")
                    .font(.caption.bold())
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.yellow)
                    .cornerRadius(20)
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Segment Row
    @ViewBuilder
    private func segmentRow(
        segment: Binding<CaptionSegment>,
        isPlayingNow: Bool,
        isSelected: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: Timestamps + Operations
            HStack {
                // Seek Button
                Button(action: {
                    selectedSegmentID = segment.wrappedValue.id
                    onSeek(segment.wrappedValue.start)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isPlayingNow ? "speaker.wave.2.fill" : "play.circle.fill")
                            .foregroundColor(isPlayingNow ? .yellow : .white)
                        Text(formatTimingRange(start: segment.wrappedValue.start, end: segment.wrappedValue.end))
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(isPlayingNow ? .yellow : .gray)
                    }
                }
                
                Spacer()
                
                // Steppers for Start Time (+ / - 0.1s)
                HStack(spacing: 4) {
                    Text("Start:").font(.caption2).foregroundColor(.gray)
                    Button("-") { adjustStart(segment: segment, by: -0.1) }
                        .buttonStyle(.bordered).controlSize(.mini)
                    Button("+") { adjustStart(segment: segment, by: 0.1) }
                        .buttonStyle(.bordered).controlSize(.mini)
                }
                
                // Steppers for End Time (+ / - 0.1s)
                HStack(spacing: 4) {
                    Text("End:").font(.caption2).foregroundColor(.gray)
                    Button("-") { adjustEnd(segment: segment, by: -0.1) }
                        .buttonStyle(.bordered).controlSize(.mini)
                    Button("+") { adjustEnd(segment: segment, by: 0.1) }
                        .buttonStyle(.bordered).controlSize(.mini)
                }
                
                // Split, Merge, Delete Actions Menu
                Menu {
                    Button(action: { splitSegment(segment.wrappedValue) }) {
                        Label("Split at Playhead", systemImage: "scissors")
                    }
                    Button(action: { mergeWithNext(segment.wrappedValue) }) {
                        Label("Merge with Next", systemImage: "arrow.triangle.merge")
                    }
                    Button(role: .destructive, action: { deleteSegment(segment.wrappedValue) }) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.gray)
                        .padding(.horizontal, 4)
                }
            }
            
            // Interactive Words (Tap word to toggle isHighlighted)
            WrappingHStack(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(0..<segment.wrappedValue.words.count, id: \.self) { idx in
                    let word = segment.wrappedValue.words[idx]
                    Button(action: {
                        toggleWordHighlight(segment: segment, wordIndex: idx)
                    }) {
                        Text(word.text)
                            .font(.subheadline.bold())
                            .foregroundColor(word.isHighlighted ? .black : .white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(word.isHighlighted ? Color.yellow : Color.white.opacity(0.12))
                            )
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isPlayingNow ? Color.yellow : (isSelected ? Color.white.opacity(0.4) : Color.clear), lineWidth: 1.5)
                )
        )
    }
    
    // MARK: - Mutation & Undo/Redo Engine
    
    private func pushSnapshot() {
        undoStack.append(segments)
        redoStack.removeAll() // Clear redo on new action
        if undoStack.count > 30 { undoStack.removeFirst() } // 30 levels of undo
    }
    
    private func performUndo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(segments)
        segments = previous
    }
    
    private func performRedo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(segments)
        segments = next
    }
    
    private func toggleWordHighlight(segment: Binding<CaptionSegment>, wordIndex: Int) {
        pushSnapshot()
        segment.wrappedValue.words[wordIndex].isHighlighted.toggle()
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
    
    private func adjustStart(segment: Binding<CaptionSegment>, by delta: TimeInterval) {
        pushSnapshot()
        let newStart = max(0.0, segment.wrappedValue.start + delta)
        if newStart < segment.wrappedValue.end {
            segment.wrappedValue.start = newStart
            if let first = segment.wrappedValue.words.first {
                segment.wrappedValue.words[0].start = newStart
            }
        }
    }
    
    private func adjustEnd(segment: Binding<CaptionSegment>, by delta: TimeInterval) {
        pushSnapshot()
        let newEnd = segment.wrappedValue.end + delta
        if newEnd > segment.wrappedValue.start {
            segment.wrappedValue.end = newEnd
            if let lastIdx = segment.wrappedValue.words.indices.last {
                segment.wrappedValue.words[lastIdx].end = newEnd
            }
        }
    }
    
    private func addCaptionAtPlayhead() {
        pushSnapshot()
        let newStart = currentTime
        let newEnd = currentTime + 1.5
        let newWord = CaptionWord(text: "New Caption", start: newStart, end: newEnd)
        let newSegment = CaptionSegment(words: [newWord], start: newStart, end: newEnd)
        
        // Insert in chronological order
        if let insertIdx = segments.firstIndex(where: { $0.start > newStart }) {
            segments.insert(newSegment, at: insertIdx)
        } else {
            segments.append(newSegment)
        }
        selectedSegmentID = newSegment.id
    }
    
    private func splitSegment(_ segment: CaptionSegment) {
        guard let index = segments.firstIndex(where: { $0.id == segment.id }), segment.words.count > 1 else { return }
        pushSnapshot()
        
        let mid = segment.words.count / 2
        let firstHalfWords = Array(segment.words[0..<mid])
        let secondHalfWords = Array(segment.words[mid..<segment.words.count])
        
        let seg1 = CaptionSegment(words: firstHalfWords, start: firstHalfWords.first!.start, end: firstHalfWords.last!.end)
        let seg2 = CaptionSegment(words: secondHalfWords, start: secondHalfWords.first!.start, end: secondHalfWords.last!.end)
        
        segments.remove(at: index)
        segments.insert(seg2, at: index)
        segments.insert(seg1, at: index)
    }
    
    private func mergeWithNext(_ segment: CaptionSegment) {
        guard let index = segments.firstIndex(where: { $0.id == segment.id }), index + 1 < segments.count else { return }
        pushSnapshot()
        
        let nextSegment = segments[index + 1]
        let combinedWords = segment.words + nextSegment.words
        let merged = CaptionSegment(words: combinedWords, start: segment.start, end: nextSegment.end)
        
        segments.remove(at: index + 1)
        segments[index] = merged
    }
    
    private func deleteSegment(_ segment: CaptionSegment) {
        pushSnapshot()
        segments.removeAll(where: { $0.id == segment.id })
    }
    
    private func formatTimingRange(start: TimeInterval, end: TimeInterval) -> String {
        return String(format: "%.1fs - %.1fs", start, end)
    }
}

// MARK: - Wrapping HStack Layout for Words
private struct WrappingHStack: Layout {
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 6
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var height: CGFloat = 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var maxRowHeight: CGFloat = 0
        
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > width, currentX > 0 {
                currentX = 0
                currentY += maxRowHeight + verticalSpacing
                maxRowHeight = 0
            }
            currentX += size.width + horizontalSpacing
            maxRowHeight = max(maxRowHeight, size.height)
        }
        height = currentY + maxRowHeight
        return CGSize(width: width, height: height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var maxRowHeight: CGFloat = 0
        
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentX = bounds.minX
                currentY += maxRowHeight + verticalSpacing
                maxRowHeight = 0
            }
            view.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            currentX += size.width + horizontalSpacing
            maxRowHeight = max(maxRowHeight, size.height)
        }
    }
}
