import SwiftUI
import SwiftData

/// Interactive 2D anatomical body map showing regions with clinical data
struct AnatomicalRealityView: View {
    let patient: PatientProfile
    @State private var selectedRegion: String?
    @State private var showRegionDetail = false
    @State private var pulseAnim = false

    private var records: [LocalClinicalRecord] {
        (patient.clinicalRecords ?? [])
    }
    private var photos: [ClinicalPhoto] {
        (patient.clinicalPhotos ?? [])
    }

    /// Regions that have at least one record or photo
    private var activeRegions: Set<String> {
        var set = Set<String>()
        for r in records {
            for zone in r.affectedAnatomicalZones ?? [] {
                set.insert(zone)
            }
        }
        for p in photos {
            set.insert(p.anatomicalRegion)
        }
        return set
    }

    /// Count of records per region
    private func recordCount(for region: String) -> Int {
        records.filter { ($0.affectedAnatomicalZones ?? []).contains(region) }.count
    }
    private func photoCount(for region: String) -> Int {
        photos.filter { $0.anatomicalRegion == region }.count
    }

    struct RegionHotspot: Identifiable {
        let id: String
        let name: String
        let x: CGFloat // Relative position (0.0 to 1.0)
        let y: CGFloat
    }

    // Precise relative coordinate positioning mapping anatomical nodes to the vector silhouette
    private let hotspots = [
        RegionHotspot(id: "scalp", name: "Scalp", x: 0.5, y: 0.05),
        RegionHotspot(id: "forehead", name: "Forehead", x: 0.5, y: 0.09),
        RegionHotspot(id: "left_ear", name: "L Ear", x: 0.38, y: 0.11),
        RegionHotspot(id: "right_ear", name: "R Ear", x: 0.62, y: 0.11),
        RegionHotspot(id: "left_cheek", name: "L Cheek", x: 0.44, y: 0.13),
        RegionHotspot(id: "right_cheek", name: "R Cheek", x: 0.56, y: 0.13),
        RegionHotspot(id: "facial_mesh_nose", name: "Nose", x: 0.5, y: 0.12),
        RegionHotspot(id: "lips", name: "Lips", x: 0.5, y: 0.15),
        RegionHotspot(id: "chin", name: "Chin", x: 0.5, y: 0.17),
        RegionHotspot(id: "neck", name: "Neck", x: 0.5, y: 0.20),
        RegionHotspot(id: "left_shoulder", name: "L Shoulder", x: 0.32, y: 0.23),
        RegionHotspot(id: "right_shoulder", name: "R Shoulder", x: 0.68, y: 0.23),
        RegionHotspot(id: "torso", name: "Chest", x: 0.5, y: 0.30),
        RegionHotspot(id: "upper_abdomen", name: "Abdomen", x: 0.5, y: 0.42),
        RegionHotspot(id: "lower_back", name: "Lower Back", x: 0.5, y: 0.52),
        RegionHotspot(id: "left_upper_extremity", name: "L Arm", x: 0.22, y: 0.40),
        RegionHotspot(id: "right_upper_extremity", name: "R Arm", x: 0.78, y: 0.40),
        RegionHotspot(id: "left_hand", name: "L Hand", x: 0.16, y: 0.52),
        RegionHotspot(id: "right_hand", name: "R Hand", x: 0.84, y: 0.52),
        RegionHotspot(id: "left_lower_extremity", name: "L Leg", x: 0.40, y: 0.68),
        RegionHotspot(id: "right_lower_extremity", name: "R Leg", x: 0.60, y: 0.68),
        RegionHotspot(id: "left_foot", name: "L Foot", x: 0.40, y: 0.93),
        RegionHotspot(id: "right_foot", name: "R Foot", x: 0.60, y: 0.93)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Summary widgets
                HStack(spacing: 16) {
                    summaryCard(value: "\(activeRegions.count)", label: "Active Regions", icon: "mappin.and.ellipse", color: .purple)
                    summaryCard(value: "\(records.count)", label: "Records", icon: "doc.text", color: .blue)
                    summaryCard(value: "\(photos.count)", label: "Photos", icon: "camera", color: .orange)
                }
                .padding(.horizontal)

                // Body map scanner
                bodyMapView
                    .padding(.horizontal)

                // Active region list
                if !activeRegions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Anatomical Clinical Indices")
                            .font(.system(.headline, design: .rounded))
                            .padding(.horizontal)
                        ForEach(activeRegions.sorted(), id: \.self) { region in
                            regionRow(region)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .background(ClinicGlowBackground())
        .navigationTitle("Anatomical Body Map")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showRegionDetail) {
            if let region = selectedRegion {
                NavigationStack {
                    regionDetailView(region)
                }
            }
        }
    }

    // MARK: - Body Map

    private var bodyMapView: some View {
        VStack(spacing: 12) {
            Text("Tap a glowing hotspot on the anatomical scanner to view clinical data")
                .font(.caption)
                .foregroundColor(.secondary)
                .clinicalFinePrint()
                .padding(.bottom, 4)

            ZStack {
                // High-tech scanner grid line details
                scannerGridBackground
                    .opacity(0.12)
                
                // Human anatomy line-art vector silhouette
                AnatomicalSilhouette()
                    .foregroundColor(Color.clinicalSlate.opacity(0.4))
                    .padding(16)
                
                // Hotspot radar overlays
                GeometryReader { geo in
                    ForEach(hotspots) { spot in
                        let isActive = activeRegions.contains(spot.id)
                        let isSelected = selectedRegion == spot.id
                        let rCount = recordCount(for: spot.id)
                        let pCount = photoCount(for: spot.id)
                        
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                selectedRegion = spot.id
                                if isActive {
                                    showRegionDetail = true
                                }
                            }
                        } label: {
                            ZStack {
                                if isActive {
                                    // Pulsating radar wave
                                    Circle()
                                        .stroke(Color.criticalRed, lineWidth: 1.5)
                                        .frame(width: isSelected ? 24 : 16, height: isSelected ? 24 : 16)
                                        .scaleEffect(pulseAnim ? 1.5 : 0.75)
                                        .opacity(pulseAnim ? 0.0 : 0.8)
                                    
                                    // Glowing red scanner pin
                                    Circle()
                                        .fill(isSelected ? Color.criticalRed : Color.criticalRed.opacity(0.85))
                                        .frame(width: isSelected ? 11 : 8, height: isSelected ? 11 : 8)
                                        .shadow(color: .criticalRed.opacity(0.6), radius: 3)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: 1.2)
                                        )
                                } else {
                                    // Small inactive scanner marker
                                    Circle()
                                        .fill(Color.secondary.opacity(0.35))
                                        .frame(width: 5, height: 5)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
                                        )
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .position(x: geo.size.width * spot.x, y: geo.size.height * spot.y)
                        .popover(isPresented: Binding(
                            get: { isSelected && !showRegionDetail },
                            set: { if !$0 { selectedRegion = nil } }
                        )) {
                            VStack(spacing: 5) {
                                Text(spot.name)
                                    .font(.system(.caption, design: .rounded).bold())
                                if isActive {
                                    Text("\(rCount) Records · \(pCount) Photos")
                                        .font(.system(size: 9))
                                        .foregroundColor(.criticalRed)
                                    Button("Inspect Data") {
                                        showRegionDetail = true
                                    }
                                    .font(.system(size: 9.5, weight: .bold))
                                    .buttonStyle(.borderedProminent)
                                    .tint(.criticalRed)
                                    .controlSize(.mini)
                                } else {
                                    Text("No documented findings")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(8)
                        }
                    }
                }
            }
            .frame(width: 240, height: 380)
            .background(
                Color.clear
                    .liquidGlassCard(cornerRadius: 24, borderColor: Color.primary.opacity(0.06), shadowRadius: 8)
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulseAnim = true
                }
            }
        }
    }
    
    private var scannerGridBackground: some View {
        VStack {
            ForEach(0..<10) { _ in
                Divider().background(Color.primary.opacity(0.2))
                Spacer()
            }
        }
        .overlay(
            HStack {
                ForEach(0..<6) { _ in
                    Divider().background(Color.primary.opacity(0.2))
                    Spacer()
                }
            }
        )
    }

    // MARK: - Region Detail

    private func regionDetailView(_ region: String) -> some View {
        let regionRecords = records.filter { ($0.affectedAnatomicalZones ?? []).contains(region) }
            .sorted { $0.dateRecorded > $1.dateRecorded }
        let regionPhotos = photos.filter { $0.anatomicalRegion == region }
            .sorted { $0.captureDate > $1.captureDate }

        return List {
            Section(header: Text("Clinical Records (\(regionRecords.count))")) {
                ForEach(regionRecords) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.conditionName).font(.subheadline.bold())
                        Text(record.dateRecorded, format: .dateTime.month().day().year())
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .clinicalFinePrint()
                        if let icd10 = record.icd10Code {
                            Text(icd10)
                                .font(.caption2.monospaced())
                                .foregroundColor(.blue)
                                .clinicalFinePrintMonospaced()
                        }
                    }
                }
            }
            Section(header: Text("Clinical Photos (\(regionPhotos.count))")) {
                if regionPhotos.isEmpty {
                    Text("No photos for this region")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(regionPhotos) { photo in
                        HStack {
                            if let img = UIImage(contentsOfFile: photo.filePath) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 50, height: 50)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            VStack(alignment: .leading) {
                                Text(photo.captureDate, format: .dateTime.month().day().year())
                                    .font(.caption)
                                    .clinicalFinePrint()
                                if let notes = photo.notes {
                                    Text(notes)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .clinicalFinePrint()
                                        .clinicalRowSummaryText(lines: 2)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(AnatomicalRegion.displayName(for: region))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { showRegionDetail = false }
            }
        }
    }

    // MARK: - Helpers

    private func summaryCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            Text(value)
                .font(.title2.bold().monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .clinicalMicroLabel()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            Color.clear
                .liquidGlassCard(cornerRadius: 10, borderColor: color.opacity(0.15), shadowRadius: 3, glowColor: color)
        )
    }

    private func regionRow(_ region: String) -> some View {
        Button {
            selectedRegion = region
            showRegionDetail = true
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.criticalRed.opacity(0.15))
                    .frame(width: 32, height: 32)
                    .overlay(Image(systemName: "mappin").font(.caption).foregroundColor(.criticalRed))
                VStack(alignment: .leading, spacing: 2) {
                    Text(AnatomicalRegion.displayName(for: region))
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    Text("\(recordCount(for: region)) records · \(photoCount(for: region)) photos")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .clinicalFinePrint()
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(
                Color.clear
                    .liquidGlassCard(cornerRadius: 12, borderColor: Color.primary.opacity(0.04), shadowRadius: 2)
            )
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Human Line-Art Vector Silhouette View
private struct AnatomicalSilhouette: View {
    var body: some View {
        Canvas { context, size in
            // Draw head
            let headRect = CGRect(x: size.width/2 - 20, y: 15, width: 40, height: 40)
            context.fill(Path(ellipseIn: headRect), with: .color(Color.primary.opacity(0.06)))
            context.stroke(Path(ellipseIn: headRect), with: .color(Color.primary.opacity(0.2)), lineWidth: 1.5)
            
            // Draw neck
            let neckPath = Path(roundedRect: CGRect(x: size.width/2 - 6, y: 55, width: 12, height: 16), cornerRadius: 2)
            context.fill(neckPath, with: .color(Color.primary.opacity(0.06)))
            context.stroke(neckPath, with: .color(Color.primary.opacity(0.2)), lineWidth: 1)
            
            // Draw torso (Chest + Abdomen)
            var torso = Path()
            torso.move(to: CGPoint(x: size.width/2 - 38, y: 71))
            torso.addLine(to: CGPoint(x: size.width/2 + 38, y: 71))
            torso.addQuadCurve(to: CGPoint(x: size.width/2 + 28, y: 190), control: CGPoint(x: size.width/2 + 34, y: 130))
            torso.addLine(to: CGPoint(x: size.width/2 - 28, y: 190))
            torso.addQuadCurve(to: CGPoint(x: size.width/2 - 38, y: 71), control: CGPoint(x: size.width/2 - 34, y: 130))
            torso.closeSubpath()
            context.fill(torso, with: .color(Color.primary.opacity(0.04)))
            context.stroke(torso, with: .color(Color.primary.opacity(0.2)), lineWidth: 1.5)
            
            // Draw arms
            // Left arm
            var leftArm = Path()
            leftArm.move(to: CGPoint(x: size.width/2 - 38, y: 74))
            leftArm.addLine(to: CGPoint(x: size.width/2 - 58, y: 160))
            leftArm.addLine(to: CGPoint(x: size.width/2 - 50, y: 160))
            leftArm.addLine(to: CGPoint(x: size.width/2 - 30, y: 80))
            leftArm.closeSubpath()
            context.fill(leftArm, with: .color(Color.primary.opacity(0.03)))
            context.stroke(leftArm, with: .color(Color.primary.opacity(0.15)), lineWidth: 1)
            
            // Left hand
            let leftHandRect = CGRect(x: size.width/2 - 62, y: 160, width: 14, height: 18)
            context.fill(Path(ellipseIn: leftHandRect), with: .color(Color.primary.opacity(0.04)))
            context.stroke(Path(ellipseIn: leftHandRect), with: .color(Color.primary.opacity(0.15)), lineWidth: 0.8)

            // Right arm
            var rightArm = Path()
            rightArm.move(to: CGPoint(x: size.width/2 + 38, y: 74))
            rightArm.addLine(to: CGPoint(x: size.width/2 + 58, y: 160))
            rightArm.addLine(to: CGPoint(x: size.width/2 + 50, y: 160))
            rightArm.addLine(to: CGPoint(x: size.width/2 + 30, y: 80))
            rightArm.closeSubpath()
            context.fill(rightArm, with: .color(Color.primary.opacity(0.03)))
            context.stroke(rightArm, with: .color(Color.primary.opacity(0.15)), lineWidth: 1)
            
            // Right hand
            let rightHandRect = CGRect(x: size.width/2 + 48, y: 160, width: 14, height: 18)
            context.fill(Path(ellipseIn: rightHandRect), with: .color(Color.primary.opacity(0.04)))
            context.stroke(Path(ellipseIn: rightHandRect), with: .color(Color.primary.opacity(0.15)), lineWidth: 0.8)

            // Left leg
            var leftLeg = Path()
            leftLeg.move(to: CGPoint(x: size.width/2 - 25, y: 191))
            leftLeg.addLine(to: CGPoint(x: size.width/2 - 20, y: 310))
            leftLeg.addLine(to: CGPoint(x: size.width/2 - 5, y: 310))
            leftLeg.addLine(to: CGPoint(x: size.width/2 - 7, y: 191))
            leftLeg.closeSubpath()
            context.fill(leftLeg, with: .color(Color.primary.opacity(0.03)))
            context.stroke(leftLeg, with: .color(Color.primary.opacity(0.15)), lineWidth: 1)
            
            // Left foot
            let leftFootRect = CGRect(x: size.width/2 - 22, y: 310, width: 18, height: 10)
            context.fill(Path(roundedRect: leftFootRect, cornerRadius: 2), with: .color(Color.primary.opacity(0.04)))
            context.stroke(Path(roundedRect: leftFootRect, cornerRadius: 2), with: .color(Color.primary.opacity(0.15)), lineWidth: 0.8)

            // Right leg
            var rightLeg = Path()
            rightLeg.move(to: CGPoint(x: size.width/2 + 25, y: 191))
            rightLeg.addLine(to: CGPoint(x: size.width/2 + 20, y: 310))
            rightLeg.addLine(to: CGPoint(x: size.width/2 + 5, y: 310))
            rightLeg.addLine(to: CGPoint(x: size.width/2 + 7, y: 191))
            rightLeg.closeSubpath()
            context.fill(rightLeg, with: .color(Color.primary.opacity(0.03)))
            context.stroke(rightLeg, with: .color(Color.primary.opacity(0.15)), lineWidth: 1)
            
            // Right foot
            let rightFootRect = CGRect(x: size.width/2 + 4, y: 310, width: 18, height: 10)
            context.fill(Path(roundedRect: rightFootRect, cornerRadius: 2), with: .color(Color.primary.opacity(0.04)))
            context.stroke(Path(roundedRect: rightFootRect, cornerRadius: 2), with: .color(Color.primary.opacity(0.15)), lineWidth: 0.8)
        }
    }
}
