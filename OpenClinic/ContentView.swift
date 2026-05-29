import SwiftUI
import SwiftData
import os

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var patients: [PatientProfile]

    var body: some View {
        EHRMainShellView()
            .onAppear {
                AppLogger.data.info("ContentView appeared — \(patients.count) patients in database")
                if patients.isEmpty {
                    AppLogger.data.info("🌱 First launch detected — seeding mock data")
                    addMockData()
                }
                AppLogger.data.info("📋 Refreshing supplemental data for today's timeline")
                refreshSupplementalDemoData()
            }
    }

    // swiftlint:disable function_body_length
    private func addMockData() {
        let cal = Calendar.current
        let todayBase = cal.startOfDay(for: Date())
        func todayAt(_ h: Int, _ m: Int) -> Date {
            cal.date(bySettingHour: h, minute: m, second: 0, of: todayBase)!
        }
        func futureAt(_ days: Int, _ h: Int, _ m: Int) -> Date {
            let target = cal.date(byAdding: .day, value: days, to: todayBase)!
            return cal.date(bySettingHour: h, minute: m, second: 0, of: target)!
        }

        // ──────────────────────────────────────────────
        // MARK: – Patients
        // ──────────────────────────────────────────────

        let janeDoe = PatientProfile(medicalRecordNumber: "MM-1001", firstName: "Catherine", lastName: "Hartley",
            dateOfBirth: Date(timeIntervalSince1970: 181872000), // Oct 7 1975
            gender: "Female", isSmoker: true)

        let mariaSantos = PatientProfile(medicalRecordNumber: "MM-1002", firstName: "Maria", lastName: "Santos",
            dateOfBirth: Date(timeIntervalSince1970: 315532800), // Jan 1 1980
            gender: "Female", isSmoker: false)

        let robertChen = PatientProfile(medicalRecordNumber: "MM-1003", firstName: "Robert", lastName: "Chen",
            dateOfBirth: Date(timeIntervalSince1970: 86400000), // Sep 9 1972
            gender: "Male", isSmoker: false)

        let sarahJohnson = PatientProfile(medicalRecordNumber: "MM-1004", firstName: "Sarah", lastName: "Johnson",
            dateOfBirth: Date(timeIntervalSince1970: 631152000), // Jan 1 1990
            gender: "Female", isSmoker: false)

        let davidWilliams = PatientProfile(medicalRecordNumber: "MM-1005", firstName: "David", lastName: "Williams",
            dateOfBirth: Date(timeIntervalSince1970: 473385600), // Jan 1 1985
            gender: "Male", isSmoker: true)

        // ──────────────────────────────────────────────
        // MARK: – Catherine Hartley — BCC history, hyperlipidemia
        // ──────────────────────────────────────────────

        let janeMed1 = LocalMedication(rxID: "RX-001", medicationName: "Simvastatin 20mg",
            writtenBy: "Dr. Smith", writtenDate: Date().addingTimeInterval(-86400 * 30),
            quantityInfo: "Take 1 tablet daily at bedtime", refills: 2)
        let janeMed2 = LocalMedication(rxID: "RX-002", medicationName: "Fluorouracil 5% Cream",
            writtenBy: "Dr. Smith", writtenDate: Date().addingTimeInterval(-86400 * 60),
            quantityInfo: "Apply to affected area twice daily x 4 weeks", refills: 0)
        let janeMed3 = LocalMedication(rxID: "RX-003", medicationName: "Tretinoin 0.05% Cream",
            writtenBy: "Dr. Smith", writtenDate: Date().addingTimeInterval(-86400 * 90),
            quantityInfo: "Apply thin layer to face nightly", refills: 3)

        let janeRec1 = LocalClinicalRecord(
            recordID: "REC-001", dateRecorded: Date().addingTimeInterval(-86400 * 365),
            conditionName: "Basal Cell Carcinoma", status: "Final", isHiddenFromPortal: false,
            ccHPI: "Patient presents with a pearly papule on the right upper extremity noted during routine skin exam. Lesion has been present for approximately 6 months with intermittent bleeding. Patient reports occasional itching but no pain. History of significant sun exposure as a lifeguard in her 20s.",
            reviewOfSystems: "Denies fever, chills, weight loss, fatigue, or night sweats. No new lesions noted by patient.",
            examFindings: "3mm pearly, translucent papule with telangiectasia on the right dorsal forearm. Well-circumscribed borders. No ulceration currently. No palpable lymphadenopathy in axillary or epitrochlear nodes.",
            impressionsAndPlan: "Basal Cell Carcinoma — nodular subtype. Recommend surgical excision with 4mm margins. Referral to Mohs surgery if margins not clear on pathology. Follow-up in 6 weeks post-excision. Discussed sun protection, daily SPF 50+. Patient verbalized understanding.",
            affectedAnatomicalZones: ["right_upper_extremity"],
            providerSignature: "Dr. Smith, MD")

        let janeRec2 = LocalClinicalRecord(
            recordID: "REC-002", dateRecorded: Date().addingTimeInterval(-86400 * 180),
            conditionName: "Actinic Keratosis", status: "Final", isHiddenFromPortal: false,
            ccHPI: "Multiple rough, scaly patches on the forehead and scalp identified during comprehensive skin exam. Patient reports these have been present for 2-3 months and are mildly tender when rubbed.",
            reviewOfSystems: "Denies bleeding from lesions. Reports occasional mild headaches, unrelated.",
            examFindings: "Three erythematous, rough, scaly papules on the forehead measuring 4mm, 6mm, and 3mm. Two similar lesions on the vertex scalp. All lesions have a sandpaper-like texture on palpation. No induration or ulceration.",
            impressionsAndPlan: "Actinic Keratoses, multiple — forehead and scalp. Cryotherapy applied to all 5 lesions today. Prescribed Fluorouracil 5% cream for field treatment of the forehead. Return in 8 weeks to assess treatment response. If lesions persist, consider biopsy to rule out SCC.",
            affectedAnatomicalZones: ["forehead", "scalp"],
            providerSignature: "Dr. Smith, MD")

        let janeRec3 = LocalClinicalRecord(
            recordID: "REC-003", dateRecorded: Date().addingTimeInterval(-86400 * 30),
            conditionName: "Annual Skin Exam", status: "Final", isHiddenFromPortal: false,
            ccHPI: "Annual comprehensive skin examination. Patient with history of BCC (excised 12 months ago) and actinic keratoses. Currently using tretinoin 0.05% nightly. Reports good compliance with sun protection.",
            reviewOfSystems: "No new moles or changing lesions noted by patient. Denies pruritus, rashes, or skin pain.",
            examFindings: "Full body skin exam performed. BCC excision site on right forearm: well-healed linear scar, no recurrence. Forehead AKs largely resolved after fluorouracil course — one residual 2mm AK on right forehead. Scattered lentigines on bilateral upper extremities. One 5mm symmetric, uniformly brown nevus on left scapula — stable per patient. No concerning lesions identified.",
            impressionsAndPlan: "1. BCC excision site — no recurrence, continue annual surveillance. 2. Residual AK on right forehead — cryotherapy applied today. 3. Continue tretinoin 0.05% nightly for photoaging and AK prophylaxis. 4. Return in 12 months for annual exam, sooner if new or changing lesions.",
            affectedAnatomicalZones: ["right_upper_extremity", "forehead"],
            providerSignature: "Dr. Smith, MD")

        let janeAppt1 = Appointment(appointmentID: "APT-001",
            scheduledTime: todayAt(8, 30),
            reasonForVisit: "Post-cryo AK follow-up", status: "Ready for Checkout")
        let janeAppt2 = Appointment(appointmentID: "APT-002",
            scheduledTime: futureAt(365, 10, 0),
            reasonForVisit: "Annual skin exam", status: "Scheduled")

        // ──────────────────────────────────────────────
        // MARK: – Maria Santos — Acne, early rosacea
        // ──────────────────────────────────────────────

        let mariaMed1 = LocalMedication(rxID: "RX-004", medicationName: "Tretinoin 0.025% Cream",
            writtenBy: "Dr. Smith", writtenDate: Date().addingTimeInterval(-86400 * 14),
            quantityInfo: "Apply thin layer to face nightly", refills: 3)
        let mariaMed2 = LocalMedication(rxID: "RX-005", medicationName: "Benzoyl Peroxide 5% Gel",
            writtenBy: "Dr. Smith", writtenDate: Date().addingTimeInterval(-86400 * 14),
            quantityInfo: "Apply to affected areas every morning", refills: 5)
        let mariaMed3 = LocalMedication(rxID: "RX-006", medicationName: "Doxycycline 100mg",
            writtenBy: "Dr. Smith", writtenDate: Date().addingTimeInterval(-86400 * 14),
            quantityInfo: "Take 1 capsule twice daily with food x 3 months", refills: 0)
        let mariaMed4 = LocalMedication(rxID: "RX-007", medicationName: "Metronidazole 0.75% Gel",
            writtenBy: "Dr. Jones", writtenDate: Date().addingTimeInterval(-86400 * 7),
            quantityInfo: "Apply thin layer to nose and cheeks twice daily", refills: 2)

        let mariaRec1 = LocalClinicalRecord(
            recordID: "REC-004", dateRecorded: Date().addingTimeInterval(-86400 * 90),
            conditionName: "Acne Vulgaris", status: "Final", isHiddenFromPortal: false,
            ccHPI: "25-year-old female presents with moderate inflammatory acne on face and upper back. Reports onset approximately 3 months ago coinciding with starting a new job. Has tried OTC benzoyl peroxide wash with minimal improvement. No prior prescription treatment. Denies any new cosmetics or dietary changes.",
            reviewOfSystems: "Reports mild stress and occasional insomnia. Denies fevers, weight changes, or menstrual irregularity.",
            examFindings: "Bilateral cheeks: numerous open and closed comedones with 15-20 inflammatory papules and 3-4 pustules. Forehead: scattered closed comedones. Upper back: 5-6 inflammatory papules. No nodules or cysts. No scarring noted. Mild post-inflammatory hyperpigmentation on left cheek.",
            impressionsAndPlan: "Acne Vulgaris, moderate inflammatory. 1. Start tretinoin 0.025% cream nightly (counsel on purging phase, sun sensitivity). 2. Continue benzoyl peroxide 5% gel AM. 3. Add doxycycline 100mg BID x 3 months for inflammatory component. 4. Follow-up in 8 weeks to assess response.",
            affectedAnatomicalZones: ["left_cheek", "right_cheek", "forehead"],
            providerSignature: "Dr. Smith, MD")

        let mariaRec2 = LocalClinicalRecord(
            recordID: "REC-005", dateRecorded: Date().addingTimeInterval(-86400 * 7),
            conditionName: "Rosacea", status: "Preliminary", isHiddenFromPortal: false,
            ccHPI: "Patient returns for 8-week acne follow-up. Reports significant improvement in acne — fewer breakouts, comedones clearing. However, notes persistent redness across nose and central cheeks that worsens with hot beverages, spicy food, and after exercise. Occasional stinging sensation.",
            reviewOfSystems: "Denies eye irritation, blurry vision. Reports occasional facial flushing lasting 10-15 minutes.",
            examFindings: "Acne: marked improvement — 3-4 residual comedones on forehead, 2 small papules on right cheek. Rosacea: diffuse centrofacial erythema involving nose and medial cheeks. Scattered telangiectasias on nasal ala. No papulopustular lesions of rosacea at this time. No ocular involvement.",
            impressionsAndPlan: "1. Acne Vulgaris — good response. Taper doxycycline to 100mg daily x 1 month then discontinue. Continue topical retinoid and BP. 2. Rosacea, erythematotelangiectatic subtype — new diagnosis. Start metronidazole 0.75% gel BID. Counsel on trigger avoidance (sun, heat, alcohol, spicy foods). Consider brimonidine for acute flushing episodes if needed. Follow-up in 6 weeks.",
            affectedAnatomicalZones: ["facial_mesh_nose", "left_cheek", "right_cheek"],
            providerSignature: "Dr. Jones, MD")

        let mariaAppt1 = Appointment(appointmentID: "APT-003",
            scheduledTime: todayAt(9, 30),
            reasonForVisit: "Acne/rosacea follow-up", status: "Checked In")
        let mariaAppt2 = Appointment(appointmentID: "APT-004",
            scheduledTime: futureAt(42, 11, 15),
            reasonForVisit: "Rosacea 6-week check", status: "Scheduled")

        // ──────────────────────────────────────────────
        // MARK: – Robert Chen — Psoriasis, melanoma history
        // ──────────────────────────────────────────────

        let robertMed1 = LocalMedication(rxID: "RX-008", medicationName: "Clobetasol 0.05% Ointment",
            writtenBy: "Dr. Smith", writtenDate: Date().addingTimeInterval(-86400 * 45),
            quantityInfo: "Apply to plaques twice daily x 2 weeks, then weekends only", refills: 1)
        let robertMed2 = LocalMedication(rxID: "RX-009", medicationName: "Calcipotriene 0.005% Cream",
            writtenBy: "Dr. Smith", writtenDate: Date().addingTimeInterval(-86400 * 45),
            quantityInfo: "Apply to affected areas daily", refills: 3)
        let robertMed3 = LocalMedication(rxID: "RX-010", medicationName: "Methotrexate 15mg",
            writtenBy: "Dr. Smith", writtenDate: Date().addingTimeInterval(-86400 * 20),
            quantityInfo: "Take once weekly on Mondays with folic acid", refills: 5)
        let robertMed4 = LocalMedication(rxID: "RX-011", medicationName: "Folic Acid 1mg",
            writtenBy: "Dr. Smith", writtenDate: Date().addingTimeInterval(-86400 * 20),
            quantityInfo: "Take 1 tablet daily except Mondays", refills: 5)

        let robertRec1 = LocalClinicalRecord(
            recordID: "REC-006", dateRecorded: Date().addingTimeInterval(-86400 * 730),
            conditionName: "Melanoma In Situ", status: "Final", isHiddenFromPortal: false,
            ccHPI: "Patient referred by PCP for evaluation of a changing mole on the left upper back. Reports the lesion has been darkening and growing over the past 4 months. No bleeding or itching. Family history: father had melanoma at age 60.",
            reviewOfSystems: "Denies weight loss, fatigue, bone pain, or neurological symptoms.",
            examFindings: "Left scapular region: 8mm irregularly bordered, asymmetric macule with variegated brown-black coloration. ABCDE criteria: Asymmetry (+), Border irregularity (+), Color variation (+), Diameter >6mm (+), Evolution (+). No satellite lesions. No palpable lymphadenopathy in axillary or cervical chains. Dermatoscopy: irregular pigment network, regression structures, blue-white veil absent.",
            impressionsAndPlan: "Melanoma In Situ — clinical suspicion high. Excisional biopsy performed today with 2mm margins. Rush pathology ordered. If confirmed melanoma in situ, will need wide local excision with 5mm margins. Sentinel lymph node biopsy not indicated for in situ disease. Urgent follow-up in 1 week for path results. Full body photography at next visit.",
            affectedAnatomicalZones: ["left_upper_extremity"],
            providerSignature: "Dr. Smith, MD")

        let robertRec2 = LocalClinicalRecord(
            recordID: "REC-007", dateRecorded: Date().addingTimeInterval(-86400 * 700),
            conditionName: "Melanoma In Situ — Post-Excision", status: "Final", isHiddenFromPortal: false,
            ccHPI: "Follow-up for melanoma in situ excision. Pathology confirmed melanoma in situ, lentigo maligna type. Margins clear on excisional biopsy. Patient here for wide local excision.",
            examFindings: "Left scapular biopsy site: well-healing, no signs of infection. Wide local excision performed with 5mm surgical margins. Specimen sent to pathology. No new suspicious lesions on limited exam.",
            impressionsAndPlan: "Wide local excision of melanoma in situ — completed. Await final pathology for margin confirmation. Established q6mo full-body skin exams for 2 years, then annual. Patient counseled on sun protection, monthly self-exams, and warning signs of recurrence.",
            affectedAnatomicalZones: ["left_upper_extremity"],
            providerSignature: "Dr. Smith, MD")

        let robertRec3 = LocalClinicalRecord(
            recordID: "REC-008", dateRecorded: Date().addingTimeInterval(-86400 * 45),
            conditionName: "Plaque Psoriasis", status: "Final", isHiddenFromPortal: false,
            ccHPI: "Patient presents with worsening psoriasis flare over the past 2 months. Reports thick, itchy plaques on bilateral elbows, knees, and scalp. Has been using OTC moisturizers only. PASI score estimated at 12. New joint stiffness in fingers and toes for 3 weeks — concerning for psoriatic arthritis.",
            reviewOfSystems: "Reports morning stiffness lasting 45 minutes in bilateral hands. Mild fatigue. Denies nail changes, eye redness, or GI symptoms.",
            examFindings: "Well-demarcated, erythematous plaques with thick silvery scale on bilateral elbows (8cm x 6cm), bilateral knees (5cm x 4cm), and scalp (diffuse involvement of vertex and occipital regions). BSA approximately 8%. Nails: fine pitting on bilateral thumbnails, no onycholysis. Joints: mild dactylitis of right 3rd toe. No enthesitis detected. Skin of the face, trunk clear.",
            impressionsAndPlan: "1. Plaque Psoriasis — moderate, worsening. Start clobetasol 0.05% ointment for acute flare (2 weeks active, then weekends). Add calcipotriene daily for maintenance. 2. Possible Psoriatic Arthritis — start methotrexate 15mg weekly with folic acid supplementation. Order CBC, CMP, hepatitis panel before first dose. 3. Refer to rheumatology for joint evaluation. 4. Follow-up in 6 weeks for methotrexate labs and response assessment.",
            affectedAnatomicalZones: ["left_upper_extremity", "right_upper_extremity", "scalp"],
            providerSignature: "Dr. Smith, MD")

        let robertAppt1 = Appointment(appointmentID: "APT-005",
            scheduledTime: todayAt(8, 15),
            reasonForVisit: "Psoriasis — methotrexate labs review", status: "Completed")
        let robertAppt2 = Appointment(appointmentID: "APT-006",
            scheduledTime: futureAt(180, 14, 30),
            reasonForVisit: "6-month melanoma surveillance", status: "Scheduled")

        // ──────────────────────────────────────────────
        // MARK: – Sarah Johnson — Eczema, contact dermatitis
        // ──────────────────────────────────────────────

        let sarahMed1 = LocalMedication(rxID: "RX-012", medicationName: "Triamcinolone 0.1% Cream",
            writtenBy: "Dr. Jones", writtenDate: Date().addingTimeInterval(-86400 * 60),
            quantityInfo: "Apply to affected areas twice daily x 2 weeks", refills: 2)
        let sarahMed2 = LocalMedication(rxID: "RX-013", medicationName: "Tacrolimus 0.1% Ointment",
            writtenBy: "Dr. Jones", writtenDate: Date().addingTimeInterval(-86400 * 60),
            quantityInfo: "Apply to face and neck twice daily as needed", refills: 3)
        let sarahMed3 = LocalMedication(rxID: "RX-014", medicationName: "Hydroxyzine 25mg",
            writtenBy: "Dr. Jones", writtenDate: Date().addingTimeInterval(-86400 * 60),
            quantityInfo: "Take 1 tablet at bedtime as needed for itch", refills: 1)
        let sarahMed4 = LocalMedication(rxID: "RX-015", medicationName: "Dupilumab 300mg",
            writtenBy: "Dr. Jones", writtenDate: Date().addingTimeInterval(-86400 * 30),
            quantityInfo: "Inject subcutaneously every 2 weeks", refills: 5)
        let sarahMed5 = LocalMedication(rxID: "RX-016", medicationName: "CeraVe Moisturizing Cream",
            writtenBy: "Dr. Jones", writtenDate: Date().addingTimeInterval(-86400 * 60),
            quantityInfo: "Apply liberally after bathing and as needed", refills: 99)

        let sarahRec1 = LocalClinicalRecord(
            recordID: "REC-009", dateRecorded: Date().addingTimeInterval(-86400 * 120),
            conditionName: "Atopic Dermatitis", status: "Final", isHiddenFromPortal: false,
            ccHPI: "30-year-old female with childhood history of eczema, now with severe flare over the past 6 weeks. Reports intense pruritus disrupting sleep (waking 3-4 times nightly). Affecting bilateral antecubital fossae, neck, and periorbital areas. Has been using OTC hydrocortisone 1% with no relief. History of asthma and allergic rhinitis (atopic triad). Current triggers: stress from grad school finals, recent cold weather.",
            reviewOfSystems: "Reports poor sleep quality due to itching. Mild asthma exacerbation — using rescue inhaler 3x/week. Denies eye discharge or visual changes. Reports dry, cracking skin on hands.",
            examFindings: "Bilateral antecubital fossae: erythematous, lichenified plaques with excoriation marks and serous weeping. Neck: diffuse erythema with fine papules and excoriations. Periorbital: mild eczematous changes with Dennie-Morgan infraorbital folds. Hands: xerosis with fissures on bilateral palms. BSA approximately 15%. EASI score: 24 (severe). No signs of secondary infection (no honey crusting, pustules, or lymphangitic streaking).",
            impressionsAndPlan: "Atopic Dermatitis, severe — IGA 4. 1. Triamcinolone 0.1% cream for body areas BID x 2 weeks, then PRN flares. 2. Tacrolimus 0.1% ointment for face/neck areas BID. 3. Hydroxyzine 25mg QHS for nocturnal pruritus. 4. Emollient therapy (CeraVe cream) — soak and smear technique discussed. 5. Given severity and impact on QoL, initiate Dupilumab — loading dose 600mg, then 300mg q2weeks. Prior auth submitted. Follow-up in 4 weeks.",
            affectedAnatomicalZones: ["left_upper_extremity", "right_upper_extremity", "neck"],
            providerSignature: "Dr. Jones, MD")

        let sarahRec2 = LocalClinicalRecord(
            recordID: "REC-010", dateRecorded: Date().addingTimeInterval(-86400 * 30),
            conditionName: "Contact Dermatitis — Nickel", status: "Final", isHiddenFromPortal: false,
            ccHPI: "Patient returns for Dupilumab 4-week check. Reports significant improvement in atopic dermatitis — sleeping through the night, pruritus reduced from 9/10 to 3/10. However, notes a new itchy, blistering rash on the abdomen at the belt buckle line for 5 days. No new detergents or topicals.",
            reviewOfSystems: "Overall improved mood and energy with better sleep. Asthma well-controlled.",
            examFindings: "Atopic dermatitis: marked improvement. Antecubital fossae — mild residual lichen, no active inflammation. Neck and periorbital areas clear. EASI score: 6 (mild). New finding: sharply demarcated, rectangular erythematous plaque with vesicles on periumbilical area corresponding exactly to belt buckle contact. Classic morphology for allergic contact dermatitis.",
            impressionsAndPlan: "1. Atopic Dermatitis — excellent response to Dupilumab. Continue current regimen. EASI improved 24→6. 2. Allergic Contact Dermatitis to nickel — clinical diagnosis. Patch testing to be scheduled for confirmation and extended allergen panel. Counsel: avoid nickel-containing jewelry and belt buckles, use buckle covers or nickel-free alternatives. Triamcinolone 0.1% to the affected area BID x 1 week. Follow-up in 8 weeks.",
            affectedAnatomicalZones: ["chin"],
            providerSignature: "Dr. Jones, MD")

        let sarahAppt1 = Appointment(appointmentID: "APT-007",
            scheduledTime: todayAt(8, 45),
            reasonForVisit: "Dupilumab injection + 8-week check", status: "In Exam")
        let sarahAppt2 = Appointment(appointmentID: "APT-008",
            scheduledTime: futureAt(14, 9, 30),
            reasonForVisit: "Patch testing — nickel panel", status: "Scheduled")

        // ──────────────────────────────────────────────
        // MARK: – David Williams — Rosacea, skin cancer screening
        // ──────────────────────────────────────────────

        let davidMed1 = LocalMedication(rxID: "RX-017", medicationName: "Ivermectin 1% Cream",
            writtenBy: "Dr. Smith", writtenDate: Date().addingTimeInterval(-86400 * 21),
            quantityInfo: "Apply thin layer to face once daily", refills: 2)
        let davidMed2 = LocalMedication(rxID: "RX-018", medicationName: "Azelaic Acid 15% Gel",
            writtenBy: "Dr. Smith", writtenDate: Date().addingTimeInterval(-86400 * 21),
            quantityInfo: "Apply to affected areas twice daily", refills: 3)
        let davidMed3 = LocalMedication(rxID: "RX-019", medicationName: "Brimonidine 0.33% Gel",
            writtenBy: "Dr. Smith", writtenDate: Date().addingTimeInterval(-86400 * 21),
            quantityInfo: "Apply to face once daily for flushing episodes", refills: 1)
        let davidMed4 = LocalMedication(rxID: "RX-020", medicationName: "Imiquimod 5% Cream",
            writtenBy: "Dr. Smith", writtenDate: Date().addingTimeInterval(-86400 * 10),
            quantityInfo: "Apply to wart at bedtime Mon/Wed/Fri x 8 weeks", refills: 0)

        let davidRec1 = LocalClinicalRecord(
            recordID: "REC-011", dateRecorded: Date().addingTimeInterval(-86400 * 21),
            conditionName: "Rosacea", status: "Final", isHiddenFromPortal: false,
            ccHPI: "41-year-old male presents with persistent facial redness, flushing, and papulopustular lesions for the past 4 months. Reports triggers include alcohol (craft beer), sun exposure, and hot showers. Has tried OTC redness-reducing creams without benefit. Family history of rosacea in mother.",
            reviewOfSystems: "Reports mild eye grittiness and redness in mornings — possible ocular rosacea. Denies visual changes. Occasional headaches.",
            examFindings: "Centrofacial erythema with prominent telangiectasias on bilateral nasal ala and medial cheeks. Approximately 12 inflammatory papules and 4 pustules distributed on cheeks and chin. No comedones (distinguishing from acne). Mild rhinophyma — early thickening of nasal skin. Eyes: bilateral conjunctival injection, mild blepharitis with collarettes on lashes.",
            impressionsAndPlan: "Rosacea, papulopustular subtype with early phymatous changes and ocular involvement. 1. Ivermectin 1% cream daily for papulopustular component. 2. Azelaic acid 15% gel BID as adjunct. 3. Brimonidine 0.33% gel PRN for acute flushing. 4. Trigger counseling: reduce alcohol, use SPF 50+ daily, lukewarm showers. 5. Ophthalmology referral for ocular rosacea — warm compresses and lid hygiene in the interim. 6. Follow-up in 6 weeks.",
            affectedAnatomicalZones: ["facial_mesh_nose", "left_cheek", "right_cheek", "chin"],
            providerSignature: "Dr. Smith, MD")

        let davidRec2 = LocalClinicalRecord(
            recordID: "REC-012", dateRecorded: Date().addingTimeInterval(-86400 * 10),
            conditionName: "Verruca Vulgaris", status: "Final", isHiddenFromPortal: false,
            ccHPI: "Patient returns for rosacea follow-up and also reports a persistent wart on the right hand present for 6 months. Has tried OTC salicylic acid and duct tape with minimal response. The wart is enlarging and now has two satellite lesions nearby.",
            examFindings: "Rosacea: improving — papulopustular component reduced by approximately 60%, erythema mildly improved. Right dorsal hand, 2nd MCP joint: 7mm verrucous papule with characteristic thrombosed capillaries (black dots) and loss of dermatoglyphics. Two 2mm satellite verrucae at adjacent sites.",
            impressionsAndPlan: "1. Rosacea — responding well. Continue current regimen. Reassess in 6 more weeks. 2. Verruca Vulgaris, right hand — cryotherapy applied to all three lesions today (2 freeze-thaw cycles). Additionally prescribing imiquimod 5% cream 3x/week for 8 weeks. Counsel on HPV transmission and handwashing. Return in 4 weeks for retreatment if needed.",
            affectedAnatomicalZones: ["right_upper_extremity"],
            providerSignature: "Dr. Smith, MD")

        let davidRec3 = LocalClinicalRecord(
            recordID: "REC-013", dateRecorded: Date().addingTimeInterval(-86400 * 500),
            conditionName: "Dysplastic Nevus", status: "Final", isHiddenFromPortal: false,
            ccHPI: "Patient presents for full body skin exam. Reports a mole on the upper back that has changed color slightly over the past year. No family history of melanoma. Significant sun exposure history — worked outdoor construction for 10 years. Current smoker.",
            examFindings: "Full body skin exam performed. Left upper back: 6mm asymmetric nevus with slightly irregular borders and two-tone brown coloring. Dermoscopy shows irregular pigment network at periphery but no blue-white veil or regression structures. Multiple acquired nevi scattered on trunk, all appearing banal. No other concerning lesions.",
            impressionsAndPlan: "Dysplastic Nevus, left upper back — mildly atypical appearing. Shave biopsy performed today for histological assessment. Await pathology. If moderately or severely dysplastic, will need re-excision. Baseline total body photography recommended. Return in 7 days for suture removal and path results. Annual skin exams given sun exposure history and atypical nevi.",
            affectedAnatomicalZones: ["left_upper_extremity"],
            providerSignature: "Dr. Smith, MD")

        let davidAppt1 = Appointment(appointmentID: "APT-009",
            scheduledTime: futureAt(7, 15, 0),
            reasonForVisit: "Wart cryo retreatment + rosacea check", status: "Scheduled")
        let davidAppt2 = Appointment(appointmentID: "APT-010",
            scheduledTime: todayAt(9, 0),
            reasonForVisit: "Urgent: new rapidly growing lesion", status: "In Exam")

        // ──────────────────────────────────────────────
        // MARK: – Schedule-Only Patients (realistic daily volume ~10)
        // ──────────────────────────────────────────────

        let thomasRandall = PatientProfile(medicalRecordNumber: "MM-2001", firstName: "Thomas", lastName: "Randall",
            dateOfBirth: Date(timeIntervalSince1970: 220924800), gender: "Male", isSmoker: false)
        let margaretLiu = PatientProfile(medicalRecordNumber: "MM-2002", firstName: "Margaret", lastName: "Liu",
            dateOfBirth: Date(timeIntervalSince1970: 157766400), gender: "Female", isSmoker: false)
        let patriciaOkafor = PatientProfile(medicalRecordNumber: "MM-2003", firstName: "Patricia", lastName: "Okafor",
            dateOfBirth: Date(timeIntervalSince1970: 347155200), gender: "Female", isSmoker: false)
        let carlosRivera = PatientProfile(medicalRecordNumber: "MM-2004", firstName: "Carlos", lastName: "Rivera",
            dateOfBirth: Date(timeIntervalSince1970: 126230400), gender: "Male", isSmoker: true)
        let helenWhitfield = PatientProfile(medicalRecordNumber: "MM-2005", firstName: "Helen", lastName: "Whitfield",
            dateOfBirth: Date(timeIntervalSince1970: 63072000), gender: "Female", isSmoker: false)

        let schedAppt11 = Appointment(appointmentID: "APT-011",
            scheduledTime: todayAt(7, 45), reasonForVisit: "Psoriasis biologic injection", status: "Completed")
        let schedAppt12 = Appointment(appointmentID: "APT-012",
            scheduledTime: todayAt(10, 0), reasonForVisit: "Annual skin exam", status: "Confirmed")
        let schedAppt13 = Appointment(appointmentID: "APT-013",
            scheduledTime: todayAt(10, 30), reasonForVisit: "Mohs surgery consult", status: "Checked In")
        let schedAppt14 = Appointment(appointmentID: "APT-014",
            scheduledTime: todayAt(13, 0), reasonForVisit: "AK cryotherapy session", status: "Scheduled")
        let schedAppt15 = Appointment(appointmentID: "APT-015",
            scheduledTime: todayAt(14, 0), reasonForVisit: "New patient: suspicious mole evaluation", status: "Scheduled")

        let schedulePatients = [thomasRandall, margaretLiu, patriciaOkafor, carlosRivera, helenWhitfield]
        let scheduleAppts = [schedAppt11, schedAppt12, schedAppt13, schedAppt14, schedAppt15]

        // ──────────────────────────────────────────────
        // MARK: – Insert All Entities
        // ──────────────────────────────────────────────

        let corePatients = [janeDoe, mariaSantos, robertChen, sarahJohnson, davidWilliams]
        let allPatients = corePatients + schedulePatients
        let allMeds = [janeMed1, janeMed2, janeMed3,
                       mariaMed1, mariaMed2, mariaMed3, mariaMed4,
                       robertMed1, robertMed2, robertMed3, robertMed4,
                       sarahMed1, sarahMed2, sarahMed3, sarahMed4, sarahMed5,
                       davidMed1, davidMed2, davidMed3, davidMed4]
        let allRecords = [janeRec1, janeRec2, janeRec3,
                          mariaRec1, mariaRec2,
                          robertRec1, robertRec2, robertRec3,
                          sarahRec1, sarahRec2,
                          davidRec1, davidRec2, davidRec3]
        let allAppts = [janeAppt1, janeAppt2,
                        mariaAppt1, mariaAppt2,
                        robertAppt1, robertAppt2,
                        sarahAppt1, sarahAppt2,
                        davidAppt1, davidAppt2] + scheduleAppts

        configureDemoData(patients: allPatients, medications: allMeds, records: allRecords, appointments: allAppts)

        // ICD-10 codes for clinical records
        janeRec1.icd10Code = "C44.11"   // BCC of skin of eyelid/canthus (upper extremity variant)
        janeRec2.icd10Code = "L57.0"    // Actinic keratosis
        janeRec3.icd10Code = "Z12.83"   // Encounter for screening for malignant neoplasm of skin
        mariaRec1.icd10Code = "L70.0"   // Acne vulgaris
        mariaRec2.icd10Code = "L71.9"   // Rosacea, unspecified
        robertRec1.icd10Code = "D03.59"  // Melanoma in situ of other part of trunk
        robertRec2.icd10Code = "D03.59"  // Melanoma in situ — post-excision
        robertRec3.icd10Code = "L40.0"   // Psoriasis vulgaris
        sarahRec1.icd10Code = "L20.89"   // Other atopic dermatitis
        sarahRec2.icd10Code = "L23.0"    // ACD due to metals (nickel)
        davidRec1.icd10Code = "L71.1"    // Rhinophyma / papulopustular rosacea
        davidRec2.icd10Code = "B07.9"    // Viral wart, unspecified
        davidRec3.icd10Code = "D22.5"    // Melanocytic nevi of trunk

        for p in allPatients { modelContext.insert(p) }
        for m in allMeds { modelContext.insert(m) }
        for r in allRecords { modelContext.insert(r) }
        for a in allAppts { modelContext.insert(a) }

        // ──────────────────────────────────────────────
        // MARK: – Wire Relationships
        // ──────────────────────────────────────────────

        janeDoe.medications = [janeMed1, janeMed2, janeMed3]
        janeDoe.clinicalRecords = [janeRec1, janeRec2, janeRec3]
        janeDoe.appointments = [janeAppt1, janeAppt2]

        mariaSantos.medications = [mariaMed1, mariaMed2, mariaMed3, mariaMed4]
        mariaSantos.clinicalRecords = [mariaRec1, mariaRec2]
        mariaSantos.appointments = [mariaAppt1, mariaAppt2]

        robertChen.medications = [robertMed1, robertMed2, robertMed3, robertMed4]
        robertChen.clinicalRecords = [robertRec1, robertRec2, robertRec3]
        robertChen.appointments = [robertAppt1, robertAppt2]

        sarahJohnson.medications = [sarahMed1, sarahMed2, sarahMed3, sarahMed4, sarahMed5]
        sarahJohnson.clinicalRecords = [sarahRec1, sarahRec2]
        sarahJohnson.appointments = [sarahAppt1, sarahAppt2]

        davidWilliams.medications = [davidMed1, davidMed2, davidMed3, davidMed4]
        davidWilliams.clinicalRecords = [davidRec1, davidRec2, davidRec3]
        davidWilliams.appointments = [davidAppt1, davidAppt2]

        // Schedule-only patients — just appointment relationships
        thomasRandall.appointments = [schedAppt11]
        margaretLiu.appointments = [schedAppt12]
        patriciaOkafor.appointments = [schedAppt13]
        carlosRivera.appointments = [schedAppt14]
        helenWhitfield.appointments = [schedAppt15]

        try? modelContext.save()
    }

    private func refreshSupplementalDemoData() {
        let cal = Calendar.current
        let now = Date()
        let todayBase = cal.startOfDay(for: now)

        // Clinicians expect schedules to be exactly on the 10, 15, 20, or 30-minute marks.
        // We establish a "demo anchor time" that mimics the exact moment the clinician is
        // viewing their schedule during an active clinic day.
        var anchorHour = cal.component(.hour, from: now)
        // Clamp the hour to mid-day (10 AM to 2 PM) so looking forwards/backwards 2 hours
        // always stays within 8 AM - 5 PM clinic hours perfectly.
        if anchorHour < 10 || anchorHour >= 15 {
            anchorHour = 14
        }

        let currentMinute = cal.component(.minute, from: now)
        // Round to nearest 15-minute block (0, 15, 30, or 45)
        let roundedMinute = (currentMinute / 15) * 15

        let demoAnchorTime = cal.date(bySettingHour: anchorHour, minute: roundedMinute, second: 0, of: todayBase) ?? now

        // Align patient slots to strict 15 or 30-minute intervals.
        // This stops the schedule from having random slots like 9:03 AM and 9:33 AM.
        let dynamicTodayOffsets: [String: (offsetMinutes: Int, targetStatus: String)] = [
            "APT-011": (-120, "Completed"),            // 2 hours ago
            "APT-005": (-90, "Completed"),             // 1.5 hours ago
            "APT-001": (-60, "Ready for Checkout"),    // 1 hour ago
            "APT-007": (-30, "In Exam"),               // 30 mins ago
            "APT-010": (-15, "In Exam"),               // Squeezed-in urgent visit (15 mins ago)
            "APT-003": (0, "Roomed"),                  // Appointment happening right now!
            "APT-012": (30, "Checked In"),             // In waiting room for 30 mins from now
            "APT-013": (60, "Confirmed"),              // In 1 hour
            "APT-014": (120, "Scheduled"),             // In 2 hours
            "APT-015": (150, "Scheduled"),             // In 2.5 hours
        ]

        var movedCount = 0
        var fixedFutureCount = 0
        for patient in patients {
            for appt in patient.appointments ?? [] {
                if let dynamic = dynamicTodayOffsets[appt.appointmentID] {
                    // Update the time relative to the anchored demo time
                    let newDate = cal.date(byAdding: .minute, value: dynamic.offsetMinutes, to: demoAnchorTime)!
                    appt.scheduledTime = newDate
                    appt.status = dynamic.targetStatus
                    movedCount += 1
                } else {
                    // These are expected to be FUTURE or PAST appointments not on today's strict agenda.
                    // If they slipped into the past or are at weird hours (like 10 PM), reset them safely.
                    if appt.status == "Scheduled" {
                        let comps = cal.dateComponents([.hour], from: appt.scheduledTime)
                        let isWeirdHour = (comps.hour ?? 0) >= 17 || (comps.hour ?? 0) < 7
                        let isPast = appt.scheduledTime < now

                        if isPast || isWeirdHour {
                            // Push them 7 to 30 days out at a normal clinical time
                            let daysOut = Int.random(in: 7...30)
                            if let fresh = cal.date(byAdding: .day, value: daysOut, to: todayBase),
                               let cleanTime = cal.date(bySettingHour: [9, 10, 11, 14, 15].randomElement()!, minute: [0, 15, 30].randomElement()!, second: 0, of: fresh) {
                                appt.scheduledTime = cleanTime
                                fixedFutureCount += 1
                            }
                        }
                    }
                }
            }
        }
        AppLogger.data.info("🔄 Refreshed appts for rolling timeline: \(movedCount) moved dynamic, \(fixedFutureCount) future fixed")

        // --- CLEANUP LEGACY HEALTHKIT DUPLICATES ---
        // Ensure any duplicated data from previous builds using the now-removed HealthKit fallback is wiped out permanently.
        do {
            let allMeds = try modelContext.fetch(FetchDescriptor<LocalMedication>())
            let medsToDelete = allMeds.filter { ($0.pharmacyName ?? "").contains("HealthKit") }
            for med in medsToDelete {
                modelContext.delete(med)
            }

            let allRecords = try modelContext.fetch(FetchDescriptor<LocalClinicalRecord>())
            let recordsToDelete = allRecords.filter { ($0.carePlanSummary ?? "").contains("HealthKit") || ($0.conditionName).contains("HealthKit") }
            for rec in recordsToDelete {
                modelContext.delete(rec)
            }
            if !medsToDelete.isEmpty || !recordsToDelete.isEmpty {
                AppLogger.data.info("🗑️ Cleaned up \(medsToDelete.count) duplicated HealthKit meds and \(recordsToDelete.count) records")
            }
        } catch {
            AppLogger.data.error("Error cleaning up HealthKit duplicates: \(error.localizedDescription)")
        }

        let medications = patients.flatMap { $0.medications ?? [] }
        let appointments = patients.flatMap { $0.appointments ?? [] }

        // ── Closed-Loop Dynamic Clinical Note Generation ──
        struct ClinicalNoteTemplate {
            let conditionName: String
            let affectedAnatomicalZones: [String]
            let ccHPI: String
            let examFindings: String
            let impressionsAndPlan: String
            let icd10Code: String
            let visitType: String
            let severity: String
            let patientInstructions: String
            let followUpPlan: String
            let recommendedOrders: [String]
            let carePlanSummary: String
        }

        let noteTemplates: [String: ClinicalNoteTemplate] = [
            "APT-011": ClinicalNoteTemplate(
                conditionName: "Psoriasis Vulgaris",
                affectedAnatomicalZones: ["right_upper_extremity"],
                ccHPI: "Thomas Randall is a 56-year-old male presenting for scheduled biologic injection for psoriasis. He reports stable skin condition, no new flares, and no side effects since his last injection.",
                examFindings: "No active psoriatic plaques on trunk or extremities. Injection site (right thigh) clean, no erythema or induration.",
                impressionsAndPlan: "1. Psoriasis vulgaris — stable. Administered Tremfya 100mg SQ in right thigh. Patient tolerated procedure well. No immediate adverse reaction. Next injection in 8 weeks.",
                icd10Code: "L40.0",
                visitType: "Biologic therapy visit",
                severity: "Stable",
                patientInstructions: "Monitor injection site for redness. Keep skin well hydrated with thick emollients.",
                followUpPlan: "Return in 8 weeks for scheduled Tremfya injection.",
                recommendedOrders: ["Tremfya 100mg subcutaneous refill"],
                carePlanSummary: "Biologic therapy maintenance for plaque psoriasis."
            ),
            "APT-005": ClinicalNoteTemplate(
                conditionName: "Psoriasis Vulgaris",
                affectedAnatomicalZones: ["left_upper_extremity", "right_upper_extremity"],
                ccHPI: "Robert Chen is a 53-year-old male presenting for follow-up of psoriasis vulgaris. He has been on a biologic (Skyrizi) for 6 months. Reports significant clearing of plaques, decreased scaling, and no joint pain. Tolerating treatment well.",
                examFindings: "Bilateral upper extremities show minimal erythema at previous plaque sites. Plaque burden reduced from 12% BSA to < 1% BSA. No active joint swelling or nail pitting.",
                impressionsAndPlan: "1. Psoriasis vulgaris — excellent response to Skyrizi. Continue Skyrizi 150mg SQ every 12 weeks. Next dose scheduled at the infusion center. 2. Return in 6 months for routine safety monitoring.",
                icd10Code: "L40.0",
                visitType: "Biologic follow-up",
                severity: "Mild residual plaque",
                patientInstructions: "Continue Skyrizi maintenance, monitor for joint symptoms, and report any signs of systemic infection.",
                followUpPlan: "Return in 6 months for checkup and routine safety monitoring labs.",
                recommendedOrders: ["CBC with differential", "Comprehensive metabolic panel"],
                carePlanSummary: "Routine safety monitoring during systemic immunomodulatory treatment."
            ),
            "APT-001": ClinicalNoteTemplate(
                conditionName: "History of Melanoma",
                affectedAnatomicalZones: ["right_upper_extremity"],
                ccHPI: "Catherine Hartley is a 50-year-old female with a history of melanoma on the right upper extremity, presenting for a routine skin check. She reports no new changing moles, pruritus, or bleeding. She uses daily sun protection.",
                examFindings: "Full-body skin check reveals a well-healed scar on the right upper extremity (previous melanoma site) with no evidence of local recurrence, satellite lesions, or in-transit metastases. No suspicious atypical nevi or irregular pigmented macules detected elsewhere.",
                impressionsAndPlan: "1. History of cutaneous melanoma, right upper arm — stable, no recurrence. Continue sun safety precautions (SPF 50+, wide-brimmed hats) and strict daily sun protection. 2. Await next routine check in 6 months.",
                icd10Code: "Z12.83",
                visitType: "Melanoma surveillance",
                severity: "No evidence of disease",
                patientInstructions: "Perform monthly self-skin exams, report any new or changing lesions immediately, and use SPF 50+ daily.",
                followUpPlan: "Reassess in 6 months for full-body surveillance exam.",
                recommendedOrders: ["Baseline total body photography update"],
                carePlanSummary: "Strict oncology dermatological surveillance."
            ),
            "APT-007": ClinicalNoteTemplate(
                conditionName: "Atopic Dermatitis",
                affectedAnatomicalZones: ["left_upper_extremity"],
                ccHPI: "Sarah Johnson is a 51-year-old female presenting with an acute flare of atopic dermatitis on bilateral hands and wrists. Reports intense pruritus, sleep disruption. Flare started 4 days ago after using a new dish soap.",
                examFindings: "Bilateral hands and wrists show erythematous plaques with mild lichenification, excoriations, and occasional serous crusting. No signs of secondary bacterial infection.",
                impressionsAndPlan: "1. Atopic dermatitis, bilateral hands — acute flare. Prescribed Triamcinolone 0.1% ointment twice daily for 2 weeks, then transition to Tacrolimus 0.1% ointment PRN. 2. Counsel on gentle skin care, thick emollients, and avoidance of triggers.",
                icd10Code: "L20.89",
                visitType: "Acute flare visit",
                severity: "Moderate-to-severe hands flare",
                patientInstructions: "Apply Triamcinolone ointment BID to hand lesions. Avoid scented soaps and wear cotton gloves at night over emollients.",
                followUpPlan: "Follow up in 3 weeks, or sooner if no improvement seen.",
                recommendedOrders: ["Triamcinolone 0.1% ointment refill"],
                carePlanSummary: "Barrier repair and active topical flare management."
            ),
            "APT-010": ClinicalNoteTemplate(
                conditionName: "Dysplastic Nevus",
                affectedAnatomicalZones: ["left_upper_extremity"],
                ccHPI: "David Williams is a 41-year-old male presenting for an urgent evaluation of a new, rapidly growing dark lesion on his left forearm. He noticed it 3 weeks ago. It is occasionally itchy but denies bleeding.",
                examFindings: "Left dorsal forearm: 6mm asymmetrical dark brown to black macule with irregular borders and color variegation. No ulceration. Dermoscopy shows atypical network and off-center hyperpigmented focus.",
                impressionsAndPlan: "1. Suspicious pigmented lesion, left forearm — rule out melanoma. Performed 6mm punch biopsy today under local anesthesia (1% lidocaine with epinephrine). Sent to pathology. 2. Return in 7-10 days for suture removal and results.",
                icd10Code: "D22.5",
                visitType: "Urgent diagnostic biopsy",
                severity: "High atypia / susp. melanoma",
                patientInstructions: "Keep biopsy site dry for 24 hours, change dressing daily, and call immediately if significant bleeding or infection signs appear.",
                followUpPlan: "Return in 7 days for suture removal and pathology discussion.",
                recommendedOrders: ["Dermatopathology specimen review - RUSH"],
                carePlanSummary: "Urgent diagnostic pathway for suspicious pigmented lesion."
            ),
            "APT-003": ClinicalNoteTemplate(
                conditionName: "Acne Vulgaris",
                affectedAnatomicalZones: ["left_cheek", "right_cheek", "chin"],
                ccHPI: "Maria Santos is a 46-year-old female presenting for a follow-up of acne vulgaris. She has been on Doxycycline and Tretinoin. She reports moderate improvement in inflammatory lesions. Mild dryness noted on cheeks, but overall tolerated well.",
                examFindings: "Face: approximately 4 inflammatory papules on bilateral cheeks, down from 15 at last visit. No nodulocystic lesions. Mild erythema and scaling on cheeks and chin consistent with retinoid use.",
                impressionsAndPlan: "1. Acne vulgaris — responding well. Continue Tretinoin 0.05% cream at night, reduce Doxycycline to 50mg daily for 4 more weeks then taper off. 2. Recommended oil-free non-comedogenic moisturizer for dryness.",
                icd10Code: "L70.0",
                visitType: "Acne checkup",
                severity: "Improving moderate",
                patientInstructions: "Continue nightly Tretinoin. Transition Doxycycline to daily dosing. Use oil-free SPF 30+ daily.",
                followUpPlan: "Follow up in 6 weeks.",
                recommendedOrders: ["Tretinoin 0.05% cream refill"],
                carePlanSummary: "Acne vulgaris topical and systemic maintenance."
            ),
            "APT-012": ClinicalNoteTemplate(
                conditionName: "Healthy Skin Exam",
                affectedAnatomicalZones: [],
                ccHPI: "Margaret Liu is an 86-year-old female presenting for her annual full-body skin screening. She reports no new, changing, or symptomatic moles. History of extensive sun exposure.",
                examFindings: "Full-body skin screening performed. Normal age-related changes including seborrheic keratoses and cherry angiomas. No atypical nevi or signs of malignancy.",
                impressionsAndPlan: "1. Normal full-body skin screening. Reassured patient. Return in 12 months for routine annual screening, or sooner if any changing lesions are noted.",
                icd10Code: "Z12.83",
                visitType: "Annual screening",
                severity: "Routine / benign",
                patientInstructions: "Maintain standard sun safety and perform monthly self skin exams.",
                followUpPlan: "Return in 12 months for routine screening.",
                recommendedOrders: ["None"],
                carePlanSummary: "Annual full-body skin screening routine."
            ),
            "APT-013": ClinicalNoteTemplate(
                conditionName: "Basal Cell Carcinoma",
                affectedAnatomicalZones: ["facial_mesh_nose"],
                ccHPI: "Patricia Okafor is a 73-year-old female presenting for Mohs surgery consultation regarding biopsy-proven basal cell carcinoma of the nasal tip.",
                examFindings: "Nasal tip shows a 5mm erythematous, pearly papule with telangiectasias and central crusting, consistent with previous biopsy site.",
                impressionsAndPlan: "1. Basal Cell Carcinoma, nasal tip. Scheduled for Mohs micrographic surgery next Tuesday. Counseled on the procedure, risks, benefits, and expected wound healing.",
                icd10Code: "C44.311",
                visitType: "Mohs surgery consult",
                severity: "Biopsy proven carcinoma",
                patientInstructions: "Understand Mohs procedure steps. Hold blood thinners only if cleared by primary physician.",
                followUpPlan: "Mohs surgery scheduled for next Tuesday at 8:00 AM.",
                recommendedOrders: ["Mohs micrographic surgical packet", "Pre-op clearance check"],
                carePlanSummary: "Surgical intervention path for cutaneous malignancy."
            ),
            "APT-014": ClinicalNoteTemplate(
                conditionName: "Actinic Keratosis",
                affectedAnatomicalZones: ["facial_mesh_nose"],
                ccHPI: "Carlos Rivera is a 56-year-old male presenting for follow-up and cryotherapy of actinic keratosis on the nose. Reports mild tenderness at treatment sites from 2 months ago, but otherwise doing well.",
                examFindings: "Nose shows three discrete erythematous, scaly, sandpaper-like papules measuring 3-4mm. No evidence of infiltration or induration.",
                impressionsAndPlan: "1. Actinic keratosis, nose. Liquid nitrogen cryotherapy applied to three lesions (single freeze-thaw cycle of 10 seconds). Tolerated well. Counselled on sun protection and monitoring.",
                icd10Code: "L57.0",
                visitType: "Cryotherapy session",
                severity: "Mild actinic damage",
                patientInstructions: "Expect blistering or crusting at treated sites on the nose. Do not pick crusts.",
                followUpPlan: "Return in 3 months for skin surveillance check.",
                recommendedOrders: ["None"],
                carePlanSummary: "Destruction of precancerous skin lesions."
            ),
            "APT-015": ClinicalNoteTemplate(
                conditionName: "Dysplastic Nevus",
                affectedAnatomicalZones: ["left_upper_extremity"],
                ccHPI: "Helen Whitfield is a 63-year-old female presenting for evaluation of a suspicious mole on her left arm. She reports the lesion has been present for years but recently seems darker and slightly irregular.",
                examFindings: "Left upper arm: 5mm slightly asymmetric macule, tan/brown with irregular borders. Dermoscopy shows atypical network without regression structures.",
                impressionsAndPlan: "1. Atypical nevus, left upper arm. Performed shave biopsy today for pathology. Will call patient with results. Re-excision will be planned if moderate or severe dysplasia is reported.",
                icd10Code: "D22.6",
                visitType: "Lesion evaluation",
                severity: "Atypical nevus",
                patientInstructions: "Keep bandage on for 24 hours, monitor for bleeding, and await pathology results.",
                followUpPlan: "Return in 10 days for wound check and pathology discussion.",
                recommendedOrders: ["Shave biopsy specimen pathology review"],
                carePlanSummary: "Biopsy and surveillance for atypical melanocytic nevi."
            )
        ]

        for patient in patients {
            for appt in patient.appointments ?? [] {
                guard let template = noteTemplates[appt.appointmentID] else { continue }
                
                let docStatus: String
                let recordStatus: String
                switch appt.status.lowercased() {
                case "completed":
                    docStatus = "signed"
                    recordStatus = "Final"
                case "ready for checkout", "readyforcheckout":
                    docStatus = "reviewed"
                    recordStatus = "Final"
                case "in exam", "inexam", "roomed":
                    docStatus = "draft"
                    recordStatus = "Preliminary"
                default:
                    continue
                }
                
                let existingRecord = (patient.clinicalRecords ?? []).first { rec in
                    cal.isDateInToday(rec.dateRecorded) && rec.conditionName == template.conditionName
                }
                
                if let rec = existingRecord {
                    rec.dateRecorded = appt.scheduledTime
                    rec.documentationStatus = docStatus
                    rec.status = recordStatus
                    rec.documentationSignedAt = docStatus == "signed" ? appt.scheduledTime : nil
                } else {
                    let newRec = LocalClinicalRecord(
                        recordID: "REC-TODAY-\(appt.appointmentID)",
                        dateRecorded: appt.scheduledTime,
                        conditionName: template.conditionName,
                        status: recordStatus,
                        isHiddenFromPortal: false,
                        ccHPI: template.ccHPI,
                        reviewOfSystems: "Gen: Constitutional symptoms denied. Derm: No other active skin issues reported.",
                        examFindings: template.examFindings,
                        impressionsAndPlan: template.impressionsAndPlan,
                        affectedAnatomicalZones: template.affectedAnatomicalZones,
                        providerSignature: "Dr. Smith, MD",
                        documentationStatus: docStatus,
                        documentationSignedAt: docStatus == "signed" ? appt.scheduledTime : nil
                    )
                    newRec.icd10Code = template.icd10Code
                    newRec.visitType = template.visitType
                    newRec.severity = template.severity
                    newRec.patientInstructions = template.patientInstructions
                    newRec.followUpPlan = template.followUpPlan
                    newRec.recommendedOrders = template.recommendedOrders
                    newRec.carePlanSummary = template.carePlanSummary
                    newRec.sourceKind = ClinicalSourceKind.demoLocalCache.rawValue
                    newRec.sourceSystemName = "OpenClinic Demo Dataset"
                    newRec.sourceRecordIdentifier = newRec.recordID
                    newRec.sourceLastSyncedAt = .now
                    newRec.sourceOfTruth = false
                    
                    newRec.patient = patient
                    modelContext.insert(newRec)
                    if patient.clinicalRecords == nil {
                        patient.clinicalRecords = []
                    }
                    patient.clinicalRecords?.append(newRec)
                }
            }
        }

        let updatedRecords = patients.flatMap { $0.clinicalRecords ?? [] }
        AppLogger.data.info("📊 Demo data totals after dynamic note sync: \(patients.count) patients, \(medications.count) meds, \(updatedRecords.count) records, \(appointments.count) appointments")
        configureDemoData(patients: patients, medications: medications, records: updatedRecords, appointments: appointments)
        try? modelContext.save()
    }

    private func configureDemoData(
        patients: [PatientProfile],
        medications: [LocalMedication],
        records: [LocalClinicalRecord],
        appointments: [Appointment]
    ) {
        for patient in patients {
            applyPatientProvenance(patient)
            switch patient.fullName {
            case "Catherine Hartley":
                applyPatientMetadata(
                    patient,
                    primaryClinician: "Dr. Elizabeth Smith, MD",
                    preferredPharmacy: "Harbor Care Pharmacy",
                    allergies: ["Sulfonamide antibiotics", "Adhesive tape"],
                    riskFlags: ["Current smoker", "High cumulative UV exposure", "History of basal cell carcinoma"],
                    carePlanSummary: "Annual full-body surveillance with expedited review for any bleeding or non-healing lesion.",
                    emergencyContactName: "Michael Hartley",
                    emergencyContactPhone: "(555) 010-1001",
                    bloodType: "A+"
                )
            case "Maria Santos":
                applyPatientMetadata(
                    patient,
                    primaryClinician: "Dr. Natalie Jones, MD",
                    preferredPharmacy: "Downtown Family Pharmacy",
                    allergies: ["No known drug allergies"],
                    riskFlags: ["Rosacea triggers: heat, spicy food, exertion", "Post-inflammatory hyperpigmentation risk"],
                    carePlanSummary: "Continue acne maintenance while controlling rosacea triggers and monitoring for ocular symptoms.",
                    emergencyContactName: "Elena Santos",
                    emergencyContactPhone: "(555) 010-1002",
                    bloodType: "O+"
                )
            case "Robert Chen":
                applyPatientMetadata(
                    patient,
                    primaryClinician: "Dr. Elizabeth Smith, MD",
                    preferredPharmacy: "Northside Specialty Pharmacy",
                    allergies: ["Penicillin"],
                    riskFlags: ["Melanoma history", "Possible psoriatic arthritis", "Immunomodulator monitoring required"],
                    carePlanSummary: "Maintain q6mo melanoma surveillance while monitoring methotrexate safety labs and joint symptoms.",
                    emergencyContactName: "Angela Chen",
                    emergencyContactPhone: "(555) 010-1003",
                    bloodType: "B+"
                )
            case "Sarah Johnson":
                applyPatientMetadata(
                    patient,
                    primaryClinician: "Dr. Natalie Jones, MD",
                    preferredPharmacy: "Northside Specialty Pharmacy",
                    allergies: ["Nickel", "Fragrance mix"],
                    riskFlags: ["Severe atopic dermatitis history", "Atopic triad", "Biologic prior authorization in progress"],
                    carePlanSummary: "Sustain Dupilumab response, maintain barrier repair, and avoid confirmed contact allergens.",
                    emergencyContactName: "Alex Johnson",
                    emergencyContactPhone: "(555) 010-1004",
                    bloodType: "AB+"
                )
            case "David Williams":
                applyPatientMetadata(
                    patient,
                    primaryClinician: "Dr. Elizabeth Smith, MD",
                    preferredPharmacy: "Harbor Care Pharmacy",
                    allergies: ["No known drug allergies"],
                    riskFlags: ["Current smoker", "Occupational sun exposure", "Possible ocular rosacea"],
                    carePlanSummary: "Continue rosacea control, monitor ocular symptoms, and keep a low threshold for lesion biopsy.",
                    emergencyContactName: "Lisa Williams",
                    emergencyContactPhone: "(555) 010-1005",
                    bloodType: "O-"
                )
            default:
                break
            }
        }

        for medication in medications {
            switch medication.rxID {
            case "RX-001":
                applyMedicationMetadata(medication, genericName: "Simvastatin", dose: "20 mg", route: "Oral", frequency: "Nightly", indication: "Hyperlipidemia", status: "Active", lastFilledDaysAgo: 12, nextRefillInDays: 18, pharmacyName: "Harbor Care Pharmacy", safetyNotes: ["Monitor for myalgias", "Avoid grapefruit excess"])
            case "RX-002":
                applyMedicationMetadata(medication, genericName: "Fluorouracil", dose: "5%", route: "Topical", frequency: "Twice daily for 4 weeks", indication: "Field treatment of actinic keratoses", status: "Completed", lastFilledDaysAgo: 58, nextRefillInDays: nil, pharmacyName: "Harbor Care Pharmacy", safetyNotes: ["Expect brisk inflammatory reaction", "Avoid healthy surrounding skin"])
            case "RX-003":
                applyMedicationMetadata(medication, genericName: "Tretinoin", dose: "0.05%", route: "Topical", frequency: "Nightly", indication: "Photoaging and AK prophylaxis", status: "Active", lastFilledDaysAgo: 20, nextRefillInDays: 10, pharmacyName: "Harbor Care Pharmacy", safetyNotes: ["Use moisturizer to reduce irritation", "Strict daily sunscreen"])
            case "RX-004":
                applyMedicationMetadata(medication, genericName: "Tretinoin", dose: "0.025%", route: "Topical", frequency: "Nightly", indication: "Comedonal acne", status: "Active", lastFilledDaysAgo: 7, nextRefillInDays: 23, pharmacyName: "Downtown Family Pharmacy", safetyNotes: ["May worsen dryness initially"])
            case "RX-005":
                applyMedicationMetadata(medication, genericName: "Benzoyl Peroxide", dose: "5%", route: "Topical", frequency: "Every morning", indication: "Inflammatory acne", status: "Active", lastFilledDaysAgo: 7, nextRefillInDays: 21, pharmacyName: "Downtown Family Pharmacy", safetyNotes: ["Bleaches fabrics", "Use non-comedogenic moisturizer"])
            case "RX-006":
                applyMedicationMetadata(medication, genericName: "Doxycycline", dose: "100 mg", route: "Oral", frequency: "Twice daily", indication: "Inflammatory acne flare", status: "Tapering", lastFilledDaysAgo: 7, nextRefillInDays: nil, pharmacyName: "Downtown Family Pharmacy", safetyNotes: ["Take with food and water", "Photosensitivity counseling"])
            case "RX-007":
                applyMedicationMetadata(medication, genericName: "Metronidazole", dose: "0.75%", route: "Topical", frequency: "Twice daily", indication: "Rosacea", status: "Active", lastFilledDaysAgo: 3, nextRefillInDays: 27, pharmacyName: "Downtown Family Pharmacy", safetyNotes: ["Monitor for burning or dryness"])
            case "RX-008":
                applyMedicationMetadata(medication, genericName: "Clobetasol", dose: "0.05%", route: "Topical", frequency: "Twice daily for flare, then weekends", indication: "Plaque psoriasis", status: "Active", lastFilledDaysAgo: 10, nextRefillInDays: 20, pharmacyName: "Northside Specialty Pharmacy", safetyNotes: ["Avoid face/groin", "Limit continuous use due to atrophy risk"])
            case "RX-009":
                applyMedicationMetadata(medication, genericName: "Calcipotriene", dose: "0.005%", route: "Topical", frequency: "Daily", indication: "Psoriasis maintenance", status: "Active", lastFilledDaysAgo: 10, nextRefillInDays: 20, pharmacyName: "Northside Specialty Pharmacy", safetyNotes: ["Do not exceed weekly topical amount guidance"])
            case "RX-010":
                applyMedicationMetadata(medication, genericName: "Methotrexate", dose: "15 mg", route: "Oral", frequency: "Weekly on Mondays", indication: "Psoriasis with joint symptoms", status: "Active", lastFilledDaysAgo: 5, nextRefillInDays: 25, pharmacyName: "Northside Specialty Pharmacy", safetyNotes: ["CBC/CMP monitoring", "Avoid alcohol excess", "Confirm folic acid adherence"])
            case "RX-011":
                applyMedicationMetadata(medication, genericName: "Folic Acid", dose: "1 mg", route: "Oral", frequency: "Daily except Mondays", indication: "Methotrexate supplementation", status: "Active", lastFilledDaysAgo: 5, nextRefillInDays: 25, pharmacyName: "Northside Specialty Pharmacy", safetyNotes: ["Hold on methotrexate day unless instructed otherwise"])
            case "RX-012":
                applyMedicationMetadata(medication, genericName: "Triamcinolone", dose: "0.1%", route: "Topical", frequency: "Twice daily for flares", indication: "Atopic dermatitis body flares", status: "Active", lastFilledDaysAgo: 9, nextRefillInDays: 21, pharmacyName: "Northside Specialty Pharmacy", safetyNotes: ["Avoid prolonged uninterrupted use"])
            case "RX-013":
                applyMedicationMetadata(medication, genericName: "Tacrolimus", dose: "0.1%", route: "Topical", frequency: "Twice daily as needed", indication: "Face and neck eczema", status: "Active", lastFilledDaysAgo: 9, nextRefillInDays: 21, pharmacyName: "Northside Specialty Pharmacy", safetyNotes: ["Transient burning common in first week"])
            case "RX-014":
                applyMedicationMetadata(medication, genericName: "Hydroxyzine", dose: "25 mg", route: "Oral", frequency: "At bedtime as needed", indication: "Nocturnal pruritus", status: "Active", lastFilledDaysAgo: 15, nextRefillInDays: 15, pharmacyName: "Northside Specialty Pharmacy", safetyNotes: ["Sedating", "Avoid driving after dosing"])
            case "RX-015":
                applyMedicationMetadata(medication, genericName: "Dupilumab", dose: "300 mg", route: "Subcutaneous", frequency: "Every 2 weeks", indication: "Severe atopic dermatitis", status: "Active", lastFilledDaysAgo: 2, nextRefillInDays: 12, pharmacyName: "Northside Specialty Pharmacy", safetyNotes: ["Monitor for conjunctivitis", "Prior authorization on file"])
            case "RX-016":
                applyMedicationMetadata(medication, genericName: "Ceramide moisturizer", dose: nil, route: "Topical", frequency: "Liberally after bathing and as needed", indication: "Skin barrier repair", status: "Active", lastFilledDaysAgo: 5, nextRefillInDays: 25, pharmacyName: "Northside Specialty Pharmacy", safetyNotes: ["Use immediately after bathing"])
            case "RX-017":
                applyMedicationMetadata(medication, genericName: "Ivermectin", dose: "1%", route: "Topical", frequency: "Daily", indication: "Papulopustular rosacea", status: "Active", lastFilledDaysAgo: 6, nextRefillInDays: 24, pharmacyName: "Harbor Care Pharmacy", safetyNotes: ["Apply to dry skin only"])
            case "RX-018":
                applyMedicationMetadata(medication, genericName: "Azelaic Acid", dose: "15%", route: "Topical", frequency: "Twice daily", indication: "Rosacea erythema and papules", status: "Active", lastFilledDaysAgo: 6, nextRefillInDays: 24, pharmacyName: "Harbor Care Pharmacy", safetyNotes: ["May sting on broken skin"])
            case "RX-019":
                applyMedicationMetadata(medication, genericName: "Brimonidine", dose: "0.33%", route: "Topical", frequency: "Once daily as needed", indication: "Rosacea flushing", status: "Active", lastFilledDaysAgo: 6, nextRefillInDays: 24, pharmacyName: "Harbor Care Pharmacy", safetyNotes: ["Counsel about rebound erythema"])
            case "RX-020":
                applyMedicationMetadata(medication, genericName: "Imiquimod", dose: "5%", route: "Topical", frequency: "Mon/Wed/Fri at bedtime", indication: "Recalcitrant verruca vulgaris", status: "Active", lastFilledDaysAgo: 4, nextRefillInDays: 26, pharmacyName: "Harbor Care Pharmacy", safetyNotes: ["Wash off after overnight dwell time", "Expected local irritation"])
            default:
                break
            }
        }

        for record in records {
            switch record.recordID {
            case "REC-001":
                applyRecordMetadata(record, visitType: "Lesion evaluation", severity: "High suspicion", patientInstructions: "Use daily SPF 50+, avoid smoking during wound healing, and report any new bleeding lesions.", followUpPlan: "Surgical excision with 6-week postoperative check.", recommendedOrders: ["Dermatopathology specimen review", "Mohs referral if margins positive"], carePlanSummary: "Confirmed skin cancer pathway with definitive excision and surveillance.")
            case "REC-002":
                applyRecordMetadata(record, visitType: "Procedure follow-up", severity: "Moderate", patientInstructions: "Expect crusting after cryotherapy and complete the fluorouracil course unless severe erosion occurs.", followUpPlan: "Return in 8 weeks for field-treatment response check.", recommendedOrders: ["None beyond current cryotherapy session"], carePlanSummary: "Reduce actinic burden and reassess for any persistent SCC concern.")
            case "REC-003":
                applyRecordMetadata(record, visitType: "Annual surveillance", severity: "Routine surveillance", patientInstructions: "Perform monthly self-skin checks and return earlier for changing lesions.", followUpPlan: "Annual visit unless a new concerning lesion appears sooner.", recommendedOrders: ["Spot cryotherapy completed in clinic"], carePlanSummary: "Stable surveillance visit with minor residual AK treatment.")
            case "REC-004":
                applyRecordMetadata(record, visitType: "New patient acne consult", severity: "Moderate inflammatory", patientInstructions: "Use pea-sized tretinoin, continue benzoyl peroxide in the morning, and avoid lesion picking.", followUpPlan: "Reassess response in 8 weeks.", recommendedOrders: ["Consider hormonal workup only if acne becomes refractory"], carePlanSummary: "Combination topical and oral regimen initiated for inflammatory acne.")
            case "REC-005":
                applyRecordMetadata(record, visitType: "Acne follow-up", severity: "Mild rosacea activity", patientInstructions: "Track flushing triggers, use sun protection daily, and report ocular irritation promptly.", followUpPlan: "Rosacea check in 6 weeks with doxycycline taper.", recommendedOrders: ["Ophthalmology evaluation if ocular symptoms emerge"], carePlanSummary: "Acne improved; rosacea added to active problem list.")
            case "REC-006":
                applyRecordMetadata(record, visitType: "Pigmented lesion workup", severity: "Urgent oncology workup", patientInstructions: "Keep biopsy site clean, avoid soaking, and await expedited pathology communication.", followUpPlan: "One-week pathology review with likely wide local excision planning.", recommendedOrders: ["Rush pathology"], carePlanSummary: "High-risk pigmented lesion moved to expedited melanoma workflow.")
            case "REC-007":
                applyRecordMetadata(record, visitType: "Post-biopsy oncology follow-up", severity: "Cancer surveillance", patientInstructions: "Maintain sun avoidance, perform monthly self-exams, and continue scheduled surveillance.", followUpPlan: "q6mo full-body skin exams for 2 years.", recommendedOrders: ["Final pathology margin confirmation"], carePlanSummary: "Definitive melanoma in situ excision completed with ongoing surveillance.")
            case "REC-008":
                applyRecordMetadata(record, visitType: "Chronic disease flare visit", severity: "Moderate-to-severe", patientInstructions: "Complete baseline labs before first methotrexate dose and report fever, cough, or oral ulcers immediately.", followUpPlan: "6-week methotrexate safety and response visit.", recommendedOrders: ["CBC", "CMP", "Hepatitis panel", "Rheumatology referral"], carePlanSummary: "Escalated psoriasis treatment with systemic therapy due to joint symptoms.")
            case "REC-009":
                applyRecordMetadata(record, visitType: "Severe eczema flare", severity: "Severe", patientInstructions: "Use soak-and-smear technique nightly, continue emollients aggressively, and monitor for conjunctivitis after Dupilumab start.", followUpPlan: "4-week biologic response check.", recommendedOrders: ["Dupilumab prior authorization", "Baseline photo documentation"], carePlanSummary: "Biologic therapy initiated for uncontrolled atopic dermatitis affecting sleep and quality of life.")
            case "REC-010":
                applyRecordMetadata(record, visitType: "Biologic follow-up", severity: "Mild residual eczema plus contact dermatitis", patientInstructions: "Avoid nickel-containing buckles and continue Dupilumab and barrier care.", followUpPlan: "Patch testing and 8-week dermatitis follow-up.", recommendedOrders: ["Extended allergen patch testing"], carePlanSummary: "Strong biologic response with a superimposed localized nickel dermatitis.")
            case "REC-011":
                applyRecordMetadata(record, visitType: "Rosacea evaluation", severity: "Moderate with ocular involvement", patientInstructions: "Reduce alcohol and heat triggers, use sunscreen daily, and begin warm compresses and lid hygiene.", followUpPlan: "6-week rosacea reassessment plus ophthalmology evaluation.", recommendedOrders: ["Ophthalmology referral"], carePlanSummary: "Multimodal rosacea regimen started because of ocular and early phymatous features.")
            case "REC-012":
                applyRecordMetadata(record, visitType: "Rosacea follow-up and procedure visit", severity: "Improving rosacea with localized wart disease", patientInstructions: "Expect blistering after cryotherapy and keep wart sites clean and dry.", followUpPlan: "Return in 4 weeks for possible wart retreatment.", recommendedOrders: ["Repeat cryotherapy if lesions persist"], carePlanSummary: "Rosacea is improving; wart treatment added for hand lesions.")
            case "REC-013":
                applyRecordMetadata(record, visitType: "Skin cancer screening", severity: "Moderate atypia concern", patientInstructions: "Leave biopsy dressing in place for 24 hours and report drainage or redness.", followUpPlan: "7-day pathology review and wound check.", recommendedOrders: ["Shave biopsy pathology"], carePlanSummary: "Atypical nevus biopsied with annual surveillance reinforced due to sun exposure history.")
            default:
                break
            }
        }

        for appointment in appointments {
            switch appointment.appointmentID {
            case "APT-001":
                applyAppointmentMetadata(appointment, encounterType: "Procedure follow-up", clinicianName: "Dr. Elizabeth Smith, MD", location: "Derm Suite 3", durationMinutes: 20, checkInStatus: "Confirmed", prepInstructions: "Bring wound care questions and current topical medications.", linkedDiagnoses: ["Actinic Keratosis", "Basal Cell Carcinoma surveillance"])
            case "APT-002":
                applyAppointmentMetadata(appointment, encounterType: "Annual surveillance", clinicianName: "Dr. Elizabeth Smith, MD", location: "Derm Preventive Clinic", durationMinutes: 30, checkInStatus: "Confirmed", prepInstructions: "Arrive without nail polish or full-body makeup for complete skin exam.", linkedDiagnoses: ["History of basal cell carcinoma"])
            case "APT-003":
                applyAppointmentMetadata(appointment, encounterType: "Chronic disease follow-up", clinicianName: "Dr. Natalie Jones, MD", location: "Acne and Rosacea Center", durationMinutes: 25, checkInStatus: "Confirmed", prepInstructions: "Bring photos of worst flare if available.", linkedDiagnoses: ["Acne Vulgaris", "Rosacea"])
            case "APT-004":
                applyAppointmentMetadata(appointment, encounterType: "Rosacea follow-up", clinicianName: "Dr. Natalie Jones, MD", location: "Acne and Rosacea Center", durationMinutes: 20, checkInStatus: "Confirmed", prepInstructions: "Avoid applying brimonidine before visit so baseline erythema can be assessed.", linkedDiagnoses: ["Rosacea"])
            case "APT-005":
                applyAppointmentMetadata(appointment, encounterType: "Medication safety visit", clinicianName: "Dr. Elizabeth Smith, MD", location: "Derm Infusion and Biologic Clinic", durationMinutes: 25, checkInStatus: "Confirmed", prepInstructions: "Complete CBC/CMP at least 24 hours before visit.", linkedDiagnoses: ["Plaque Psoriasis", "Possible Psoriatic Arthritis"])
            case "APT-006":
                applyAppointmentMetadata(appointment, encounterType: "Cancer surveillance", clinicianName: "Dr. Elizabeth Smith, MD", location: "Pigmented Lesion Clinic", durationMinutes: 30, checkInStatus: "Confirmed", prepInstructions: "Bring prior mole maps or outside dermatology records if available.", linkedDiagnoses: ["History of melanoma in situ"])
            case "APT-007":
                applyAppointmentMetadata(appointment, encounterType: "Biologic therapy follow-up", clinicianName: "Dr. Natalie Jones, MD", location: "Derm Infusion and Biologic Clinic", durationMinutes: 30, checkInStatus: "Confirmed", prepInstructions: "Bring injection log and note any eye irritation.", linkedDiagnoses: ["Atopic Dermatitis"])
            case "APT-008":
                applyAppointmentMetadata(appointment, encounterType: "Patch testing", clinicianName: "Dr. Natalie Jones, MD", location: "Allergy Patch Lab", durationMinutes: 40, checkInStatus: "Pending instructions", prepInstructions: "Avoid topical steroids on the back for 5 days before testing.", linkedDiagnoses: ["Allergic Contact Dermatitis"])
            case "APT-009":
                applyAppointmentMetadata(appointment, encounterType: "Procedure follow-up", clinicianName: "Dr. Elizabeth Smith, MD", location: "Derm Procedure Clinic", durationMinutes: 20, checkInStatus: "Confirmed", prepInstructions: "Do not apply wart medication the night before visit.", linkedDiagnoses: ["Verruca Vulgaris", "Rosacea"])
            case "APT-010":
                applyAppointmentMetadata(appointment, encounterType: "Urgent lesion evaluation", clinicianName: "Dr. Elizabeth Smith, MD", location: "Rapid Access Derm Clinic", durationMinutes: 15, checkInStatus: "Waiting triage", prepInstructions: "Keep lesion uncovered if possible for photography and measurement.", linkedDiagnoses: ["New rapidly growing lesion"])
            case "APT-011":
                applyAppointmentMetadata(appointment, encounterType: "Biologic injection", clinicianName: "Dr. Elizabeth Smith, MD", location: "Derm Infusion and Biologic Clinic", durationMinutes: 15, checkInStatus: "Completed", prepInstructions: "Bring injection log.", linkedDiagnoses: ["Plaque Psoriasis"])
            case "APT-012":
                applyAppointmentMetadata(appointment, encounterType: "Annual skin exam", clinicianName: "Dr. Natalie Jones, MD", location: "Derm Preventive Clinic", durationMinutes: 30, checkInStatus: "Confirmed", prepInstructions: "Remove nail polish for nail exam.", linkedDiagnoses: ["Skin cancer screening"])
            case "APT-013":
                applyAppointmentMetadata(appointment, encounterType: "New patient consult", clinicianName: "Dr. Elizabeth Smith, MD", location: "Mohs Surgery Suite", durationMinutes: 45, checkInStatus: "Checked In", prepInstructions: "Bring outside pathology reports.", linkedDiagnoses: ["Basal Cell Carcinoma"])
            case "APT-014":
                applyAppointmentMetadata(appointment, encounterType: "Procedure", clinicianName: "Dr. Elizabeth Smith, MD", location: "Derm Procedure Clinic", durationMinutes: 20, checkInStatus: "Scheduled", prepInstructions: "No blood thinners for 72 hours prior.", linkedDiagnoses: ["Actinic Keratoses"])
            case "APT-015":
                applyAppointmentMetadata(appointment, encounterType: "New patient consult", clinicianName: "Dr. Elizabeth Smith, MD", location: "Pigmented Lesion Clinic", durationMinutes: 30, checkInStatus: "Scheduled", prepInstructions: "Complete new patient forms online before arrival.", linkedDiagnoses: ["Suspicious melanocytic lesion"])
            default:
                break
            }
        }
    }

    private func applyPatientMetadata(
        _ patient: PatientProfile,
        primaryClinician: String,
        preferredPharmacy: String,
        allergies: [String],
        riskFlags: [String],
        carePlanSummary: String,
        emergencyContactName: String,
        emergencyContactPhone: String,
        bloodType: String
    ) {
        patient.primaryClinician = primaryClinician
        patient.preferredPharmacy = preferredPharmacy
        patient.allergies = allergies
        patient.riskFlags = riskFlags
        patient.carePlanSummary = carePlanSummary
        patient.emergencyContactName = emergencyContactName
        patient.emergencyContactPhone = emergencyContactPhone
        patient.bloodType = bloodType
    }

    private func applyPatientProvenance(_ patient: PatientProfile) {
        patient.sourceKind = ClinicalSourceKind.demoLocalCache.rawValue
        patient.sourceSystemName = "OpenClinic Demo Dataset"
        patient.sourceRecordIdentifier = patient.medicalRecordNumber
        patient.sourceLastSyncedAt = .now
        patient.sourceOfTruth = false
    }

    private func applyMedicationMetadata(
        _ medication: LocalMedication,
        genericName: String,
        dose: String?,
        route: String,
        frequency: String,
        indication: String,
        status: String,
        lastFilledDaysAgo: Int,
        nextRefillInDays: Int?,
        pharmacyName: String,
        safetyNotes: [String]
    ) {
        medication.genericName = genericName
        medication.dose = dose
        medication.route = route
        medication.frequency = frequency
        medication.indication = indication
        medication.status = status
        medication.startDate = medication.writtenDate
        medication.lastFilledDate = Calendar.current.date(byAdding: .day, value: -lastFilledDaysAgo, to: .now)
        medication.nextRefillEligibleDate = nextRefillInDays.map { Calendar.current.date(byAdding: .day, value: $0, to: .now) ?? .now }
        medication.pharmacyName = pharmacyName
        medication.safetyNotes = safetyNotes
        medication.sourceKind = ClinicalSourceKind.demoLocalCache.rawValue
        medication.sourceSystemName = "OpenClinic Demo Dataset"
        medication.sourceRecordIdentifier = medication.rxID
        medication.sourceLastSyncedAt = .now
        medication.sourceOfTruth = false
    }

    private func applyRecordMetadata(
        _ record: LocalClinicalRecord,
        visitType: String,
        severity: String,
        patientInstructions: String,
        followUpPlan: String,
        recommendedOrders: [String],
        carePlanSummary: String
    ) {
        record.visitType = visitType
        record.severity = severity
        record.patientInstructions = patientInstructions
        record.followUpPlan = followUpPlan
        record.recommendedOrders = recommendedOrders
        record.carePlanSummary = carePlanSummary
        record.documentationStatus = record.status == "Final"
            ? DocumentationLifecycleStatus.signed.rawValue
            : DocumentationLifecycleStatus.reviewed.rawValue
        record.documentationSignedAt = record.status == "Final" ? record.dateRecorded : nil
        record.sourceKind = ClinicalSourceKind.demoLocalCache.rawValue
        record.sourceSystemName = "OpenClinic Demo Dataset"
        record.sourceRecordIdentifier = record.recordID
        record.sourceLastSyncedAt = .now
        record.sourceOfTruth = false
    }

    private func applyAppointmentMetadata(
        _ appointment: Appointment,
        encounterType: String,
        clinicianName: String,
        location: String,
        durationMinutes: Int,
        checkInStatus: String,
        prepInstructions: String,
        linkedDiagnoses: [String]
    ) {
        appointment.encounterType = encounterType
        appointment.clinicianName = clinicianName
        appointment.location = location
        appointment.durationMinutes = durationMinutes
        appointment.checkInStatus = checkInStatus
        appointment.prepInstructions = prepInstructions
        appointment.linkedDiagnoses = linkedDiagnoses
        appointment.sourceKind = ClinicalSourceKind.demoLocalCache.rawValue
        appointment.sourceSystemName = "OpenClinic Demo Dataset"
        appointment.sourceRecordIdentifier = appointment.appointmentID
        appointment.sourceLastSyncedAt = .now
        appointment.sourceOfTruth = false
    }
    // swiftlint:enable function_body_length
}
