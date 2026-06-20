import SwiftUI
import SwiftData

/// Shows lesion progression photos grouped by anatomical region in a timeline
struct LesionTrackingView: View {
    let patient: PatientProfile

    private var photos: [ClinicalPhoto] {
        (patient.clinicalPhotos ?? []).sorted { $0.captureDate > $1.captureDate }
    }

    private var groupedByRegion: [(region: String, photos: [ClinicalPhoto])] {
        let dict = Dictionary(grouping: photos) { $0.anatomicalRegion }
        return dict.map { (region: $0.key, photos: $0.value.sorted { $0.captureDate < $1.captureDate }) }
            .sorted { $0.region < $1.region }
    }

    var body: some View {
        Group {
            if photos.isEmpty {
                ContentUnavailableView(
                    "No Lesion Data",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Capture clinical photos over time to track lesion progression by anatomical region.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(groupedByRegion, id: \.region) { group in
                            regionTimeline(group.region, photos: group.photos)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Lesion Tracking")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private func regionTimeline(_ region: String, photos: [ClinicalPhoto]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(.purple)
                Text(region.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.headline)
                Spacer()
                Text("\(photos.count) photo\(photos.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .clinicalFinePrint()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(photos) { photo in
                        timelineCard(photo)
                    }
                }
            }

            // Date range
            if let first = photos.first, let last = photos.last, photos.count > 1 {
                HStack {
                    Text(first.captureDate, format: .dateTime.month(.abbreviated).day().year())
                    Image(systemName: "arrow.right")
                    Text(last.captureDate, format: .dateTime.month(.abbreviated).day().year())
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .clinicalFinePrint()
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func timelineCard(_ photo: ClinicalPhoto) -> some View {
        VStack(spacing: 6) {
            #if canImport(UIKit)
            if let image = UIImage(contentsOfFile: photo.filePath) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                placeholderCard
            }
            #else
            if let image = NSImage(contentsOfFile: photo.filePath) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                placeholderCard
            }
            #endif
            
            Text(photo.captureDate, format: .dateTime.month(.abbreviated).day())
                .font(.caption2.bold())
                .clinicalMicroLabel(weight: .bold)
            if let notes = photo.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .clinicalFinePrint()
                    .clinicalRowSummaryText(lines: 2)
                    .frame(width: 100)
            }
        }
    }

    private var placeholderCard: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.gray.opacity(0.15))
            .frame(width: 100, height: 100)
            .overlay(Image(systemName: "photo").foregroundColor(.gray))
    }
}
