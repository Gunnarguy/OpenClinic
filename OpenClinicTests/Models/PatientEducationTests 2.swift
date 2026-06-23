import XCTest
@testable import OpenClinic

final class PatientEducationTests: XCTestCase {

    func testBasalCellCarcinomaMatches() {
        // Test by keyword
        let links1 = PatientEducation.links(for: "basal cell carcinoma")
        XCTAssertEqual(links1.count, 2)
        XCTAssertEqual(links1[0].title, "Basal Cell Carcinoma")
        XCTAssertEqual(links1[1].title, "Sun Protection Guide")

        let links2 = PatientEducation.links(for: "I have bcc on my nose")
        XCTAssertEqual(links2.count, 2)
        XCTAssertEqual(links2[0].title, "Basal Cell Carcinoma")

        // Test by ICD10
        let links3 = PatientEducation.links(for: "unknown", icd10: "C44.311")
        XCTAssertEqual(links3.count, 2)
        XCTAssertEqual(links3[0].title, "Basal Cell Carcinoma")
    }

    func testMelanomaMatches() {
        // Test by keyword
        let links1 = PatientEducation.links(for: "malignant melanoma")
        XCTAssertEqual(links1.count, 3)
        XCTAssertEqual(links1[0].title, "Melanoma Awareness")
        XCTAssertEqual(links1[1].title, "Post-Excision Care")
        XCTAssertEqual(links1[2].title, "Skin Self-Exam Guide")

        // Test by ICD10
        let links2 = PatientEducation.links(for: "unknown", icd10: "C43.9")
        XCTAssertEqual(links2.count, 3)
        XCTAssertEqual(links2[0].title, "Melanoma Awareness")

        let links3 = PatientEducation.links(for: "unknown", icd10: "D03.9")
        XCTAssertEqual(links3.count, 3)
        XCTAssertEqual(links3[0].title, "Melanoma Awareness")
    }

    func testDysplasticNevusMatches() {
        let links1 = PatientEducation.links(for: "dysplastic nevus syndrome")
        XCTAssertEqual(links1.count, 2)
        XCTAssertEqual(links1[0].title, "Atypical Moles")

        let links2 = PatientEducation.links(for: "atypical mole")
        XCTAssertEqual(links2.count, 2)
        XCTAssertEqual(links2[0].title, "Atypical Moles")

        let links3 = PatientEducation.links(for: "unknown", icd10: "D22.9")
        XCTAssertEqual(links3.count, 2)
        XCTAssertEqual(links3[0].title, "Atypical Moles")
    }

    func testActinicKeratosisMatches() {
        let links1 = PatientEducation.links(for: "actinic keratosis")
        XCTAssertEqual(links1.count, 2)
        XCTAssertEqual(links1[0].title, "Actinic Keratosis")

        let links2 = PatientEducation.links(for: "unknown", icd10: "L57.0")
        XCTAssertEqual(links2.count, 2)
        XCTAssertEqual(links2[0].title, "Actinic Keratosis")
    }

    func testAcneMatches() {
        let links1 = PatientEducation.links(for: "severe acne")
        XCTAssertEqual(links1.count, 2)
        XCTAssertEqual(links1[0].title, "Acne Treatment Guide")

        let links2 = PatientEducation.links(for: "unknown", icd10: "L70.0")
        XCTAssertEqual(links2.count, 2)
        XCTAssertEqual(links2[0].title, "Acne Treatment Guide")
    }

    func testRosaceaMatches() {
        let links1 = PatientEducation.links(for: "rosacea")
        XCTAssertEqual(links1.count, 2)
        XCTAssertEqual(links1[0].title, "Rosacea Triggers")

        let links2 = PatientEducation.links(for: "unknown", icd10: "L71.9")
        XCTAssertEqual(links2.count, 2)
        XCTAssertEqual(links2[0].title, "Rosacea Triggers")
    }

    func testEczemaMatches() {
        let links1 = PatientEducation.links(for: "eczema")
        XCTAssertEqual(links1.count, 3)
        XCTAssertEqual(links1[0].title, "Eczema Management")

        let links2 = PatientEducation.links(for: "atopic dermatitis")
        XCTAssertEqual(links2.count, 3)
        XCTAssertEqual(links2[0].title, "Eczema Management")

        let links3 = PatientEducation.links(for: "unknown", icd10: "L20.9")
        XCTAssertEqual(links3.count, 3)
        XCTAssertEqual(links3[0].title, "Eczema Management")
    }

    func testContactDermatitisMatches() {
        let links1 = PatientEducation.links(for: "allergic contact dermatitis")
        XCTAssertEqual(links1.count, 2)
        XCTAssertEqual(links1[0].title, "Contact Dermatitis")

        let links2 = PatientEducation.links(for: "unknown", icd10: "L23.9")
        XCTAssertEqual(links2.count, 2)
        XCTAssertEqual(links2[0].title, "Contact Dermatitis")

        let links3 = PatientEducation.links(for: "unknown", icd10: "L24.9")
        XCTAssertEqual(links3.count, 2)
        XCTAssertEqual(links3[0].title, "Contact Dermatitis")
    }

    func testPsoriasisMatches() {
        let links1 = PatientEducation.links(for: "plaque psoriasis")
        XCTAssertEqual(links1.count, 3)
        XCTAssertEqual(links1[0].title, "Psoriasis Overview")

        let links2 = PatientEducation.links(for: "unknown", icd10: "L40.0")
        XCTAssertEqual(links2.count, 3)
        XCTAssertEqual(links2[0].title, "Psoriasis Overview")
    }

    func testWartsMatches() {
        let links1 = PatientEducation.links(for: "plantar wart")
        XCTAssertEqual(links1.count, 2)
        XCTAssertEqual(links1[0].title, "Wart Treatment")

        let links2 = PatientEducation.links(for: "verruca vulgaris")
        XCTAssertEqual(links2.count, 2)
        XCTAssertEqual(links2[0].title, "Wart Treatment")

        let links3 = PatientEducation.links(for: "unknown", icd10: "B07.9")
        XCTAssertEqual(links3.count, 2)
        XCTAssertEqual(links3[0].title, "Wart Treatment")
    }

    func testGenericFallback() {
        // Test condition that shouldn't match anything specific
        let links = PatientEducation.links(for: "completely unknown condition", icd10: "Z99.9")
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links[0].title, "Skin Health Basics")
    }
}
