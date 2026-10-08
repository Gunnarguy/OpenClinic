import Foundation
import XCTest
@testable import OpenClinic

final class FHIRR4DateTimeTests: XCTestCase {

    private func calendar(secondsFromGMT seconds: Int) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: seconds))
        return calendar
    }

    private func calendar(zone identifier: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: identifier))
        return calendar
    }

    // MARK: - Accepted forms

    func testAcceptsEveryFHIRFormWithTheRightMoment() throws {
        // Expected seconds since 1970 were worked out with Python's datetime, not with this parser.
        let utc = try calendar(secondsFromGMT: 0)
        let cases: [(string: String, precision: FHIRR4DateTime.Precision, seconds: TimeInterval)] = [
            ("2015", .year, 1_420_113_600),
            ("2015-04", .month, 1_427_889_600),
            ("1967-01-21", .day, -92_923_200),
            ("2024-02-29", .day, 1_709_208_000),
            ("2015-04-26T00:52:41+00:00", .second, 1_430_009_561),
            ("2026-09-30T14:00:00Z", .second, 1_790_776_800),
            ("2026-09-30T15:30:00.250Z", .second, 1_790_782_200.25),
            ("2020-01-26T00:52:41.832+00:00", .second, 1_579_999_961.832),
            ("2026-10-07T21:30:26.251-04:00", .second, 1_791_423_026.251),
            ("2021-04-06T03:01:32.632-04:00", .second, 1_617_692_492.632),
            ("2020-06-15T10:00:00+05:30", .second, 1_592_195_400),
            ("0001-01-01T00:00:00Z", .second, -62_135_596_800),
            ("9999-12-31T23:59:59+14:00", .second, 253_402_250_399),
        ]
        for expected in cases {
            let parsed = try XCTUnwrap(FHIRR4DateTime(expected.string, calendar: utc), expected.string)
            XCTAssertEqual(parsed.precision, expected.precision, expected.string)
            XCTAssertEqual(parsed.date.timeIntervalSince1970, expected.seconds, accuracy: 0.0005, expected.string)
            XCTAssertEqual(parsed.original, expected.string)
        }
    }

    func testFractionalSecondsOfAnyLengthAreRead() throws {
        let whole = try XCTUnwrap(FHIRR4DateTime("2026-09-30T15:30:00Z")).date
        let fractions: [(String, TimeInterval)] = [
            ("2026-09-30T15:30:00.2Z", 0.2),
            ("2026-09-30T15:30:00.25Z", 0.25),
            ("2026-09-30T15:30:00.250Z", 0.25),
            ("2026-09-30T15:30:00.999999Z", 0.999999),
            // More digits than a Date can hold are accepted and the extra ones dropped.
            ("2026-09-30T15:30:00.123456789012Z", 0.123456789),
        ]
        for (string, fraction) in fractions {
            let parsed = try XCTUnwrap(FHIRR4DateTime(string), string)
            XCTAssertEqual(parsed.date.timeIntervalSince(whole), fraction, accuracy: 0.00001, string)
        }
    }

    func testZuluAndBothOffsetSignsNameTheSameMoment() throws {
        let zulu = try XCTUnwrap(FHIRR4DateTime("2015-04-26T00:52:41Z"))
        let plus = try XCTUnwrap(FHIRR4DateTime("2015-04-26T00:52:41+00:00"))
        let minusZero = try XCTUnwrap(FHIRR4DateTime("2015-04-26T00:52:41-00:00"))
        let west = try XCTUnwrap(FHIRR4DateTime("2015-04-25T20:52:41-04:00"))
        let east = try XCTUnwrap(FHIRR4DateTime("2015-04-26T06:22:41+05:30"))

        XCTAssertEqual(zulu.date, Date(timeIntervalSince1970: 1_430_009_561))
        XCTAssertEqual(plus.date, zulu.date)
        XCTAssertEqual(minusZero.date, zulu.date)
        XCTAssertEqual(west.date, zulu.date)
        XCTAssertEqual(east.date, zulu.date)
    }

    // MARK: - Rejected forms

    func testRejectsEverythingFHIRDoesNotAllow() {
        let rejected = [
            "",
            "15",
            "20150426",
            "2015-4-26",
            "2015-04-2",
            "2015-00-10",
            "2015-13-01",
            "2015-04-00",
            "2015-04-31",
            "2023-02-29",
            "0000-01-01",
            "2015-04-26T",
            "2015-04-26T00:52:41",          // a time with no zone, which the sandbox really sends
            "2025-09-27T09:00:00",
            "2015-04-26T00:52Z",            // seconds are required
            "2015-04-26T00:52:41.Z",        // an empty fraction
            "2015-04-26T00:52:41+0000",
            "2015-04-26T00:52:41+00",
            "2015-04-26T00:52:41+15:00",
            "2015-04-26T00:52:41+14:30",
            "2015-04-26T00:52:41+05:60",
            "2015-04-26T24:00:00Z",
            "2015-04-26T00:60:00Z",
            "2015-04-26T00:00:61Z",
            "2015-04-26 00:52:41Z",
            "2015-04-26t00:52:41z",
            "2015-04-26T00:52:41Zjunk",
            " 2015-04-26",
            "2015-04-26\n",
            "٢٠١٥-٠٤-٢٦",
            "April 26, 2015",
        ]
        for string in rejected {
            XCTAssertNil(FHIRR4DateTime(string), "\"\(string)\" should not parse")
        }
    }

    // MARK: - Date-only values

    func testADateWithoutATimeIsLocalNoonInTheCalendarsZone() throws {
        // Fixed zones from the far west to the far east: the day must be the 21st in each.
        for seconds in [-12 * 3_600, -5 * 3_600, 0, 5 * 3_600 + 1_800, 14 * 3_600] {
            let zoned = try calendar(secondsFromGMT: seconds)
            let parsed = try XCTUnwrap(FHIRR4DateTime("1967-01-21", calendar: zoned))
            let parts = zoned.dateComponents([.year, .month, .day, .hour, .minute, .second], from: parsed.date)
            XCTAssertEqual(parts.year, 1967, "offset \(seconds)")
            XCTAssertEqual(parts.month, 1, "offset \(seconds)")
            XCTAssertEqual(parts.day, 21, "offset \(seconds)")
            XCTAssertEqual(parts.hour, 12, "offset \(seconds)")
            XCTAssertEqual(parts.minute, 0, "offset \(seconds)")
            XCTAssertEqual(parts.second, 0, "offset \(seconds)")
            XCTAssertEqual(parsed.precision, .day)
        }

        // Noon five hours west of Greenwich is 17:00 UTC.
        let eastern = try calendar(secondsFromGMT: -5 * 3_600)
        XCTAssertEqual(
            FHIRR4DateTime("1967-01-21", calendar: eastern)?.date,
            Date(timeIntervalSince1970: -92_905_200)
        )
    }

    func testADateOnADaylightSavingChangeIsStillNoonThatDay() throws {
        // Clocks change on these days in these zones; Kiritimati is 14 hours ahead of UTC.
        let cases = [
            ("America/New_York", "2026-03-08"),
            ("America/New_York", "2026-11-01"),
            ("Australia/Sydney", "2026-10-04"),
            ("Pacific/Kiritimati", "2026-01-01"),
        ]
        for (zone, string) in cases {
            let zoned = try calendar(zone: zone)
            let parsed = try XCTUnwrap(FHIRR4DateTime(string, calendar: zoned))
            let parts = zoned.dateComponents([.day, .hour, .minute], from: parsed.date)
            XCTAssertEqual(parts.day, Int(string.suffix(2)), "\(zone) \(string)")
            XCTAssertEqual(parts.hour, 12, "\(zone) \(string)")
            XCTAssertEqual(parts.minute, 0, "\(zone) \(string)")
        }
    }

    func testYearAndMonthResolveToTheirFirstDay() throws {
        let utc = try calendar(secondsFromGMT: 0)
        let year = try XCTUnwrap(FHIRR4DateTime("2015", calendar: utc))
        let month = try XCTUnwrap(FHIRR4DateTime("2015-04", calendar: utc))

        XCTAssertEqual(year.precision, .year)
        XCTAssertEqual(month.precision, .month)

        let yearParts = utc.dateComponents([.year, .month, .day, .hour], from: year.date)
        XCTAssertEqual([yearParts.year, yearParts.month, yearParts.day, yearParts.hour], [2015, 1, 1, 12])
        let monthParts = utc.dateComponents([.year, .month, .day, .hour], from: month.date)
        XCTAssertEqual([monthParts.year, monthParts.month, monthParts.day, monthParts.hour], [2015, 4, 1, 12])
    }

    func testOnlyTheTimeZoneOfTheCalendarIsUsed() throws {
        // A device set to the Buddhist calendar must not read 1967 as a Buddhist year.
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let gregorian = try calendar(secondsFromGMT: 0)

        XCTAssertEqual(
            FHIRR4DateTime("1967-01-21", calendar: buddhist)?.date,
            FHIRR4DateTime("1967-01-21", calendar: gregorian)?.date
        )
    }

    // MARK: - Decoding

    func testDecodesFromAJSONString() throws {
        let decoded = try JSONDecoder().decode([FHIRR4DateTime].self, from: Data(#"["2015-04-26T00:52:41+00:00", "1967-01-21"]"#.utf8))
        XCTAssertEqual(decoded.map(\.precision), [.second, .day])
        XCTAssertEqual(decoded.first?.date, Date(timeIntervalSince1970: 1_430_009_561))
    }

    func testDecodingAStringThatIsNotADateThrowsDataCorrupted() {
        XCTAssertThrowsError(
            try JSONDecoder().decode([FHIRR4DateTime].self, from: Data(#"["2025-09-27T09:00:00"]"#.utf8))
        ) { error in
            guard case DecodingError.dataCorrupted = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
        }
    }

    func testDecoderCalendarPlacesDateOnlyValues() throws {
        let key = try XCTUnwrap(FHIRR4DateTime.calendarUserInfoKey)
        let tokyo = try calendar(zone: "Asia/Tokyo")
        let decoder = JSONDecoder()
        decoder.userInfo[key] = tokyo

        let decoded = try decoder.decode([FHIRR4DateTime].self, from: Data(#"["1967-01-21"]"#.utf8))
        let parts = tokyo.dateComponents([.day, .hour], from: try XCTUnwrap(decoded.first).date)
        XCTAssertEqual(parts.day, 21)
        XCTAssertEqual(parts.hour, 12)
    }

    func testLenientDateNeverFailsToDecode() throws {
        let json = Data(#"["2025-09-27T09:00:00", "2025-09-27T09:00:00Z", 5]"#.utf8)
        let decoded = try JSONDecoder().decode([FHIRR4LenientDateTime].self, from: json)

        guard decoded.count == 3 else { return XCTFail("Expected 3 values, got \(decoded.count)") }
        XCTAssertNil(decoded[0].date)
        XCTAssertTrue(decoded[0].isUnreadable)
        XCTAssertEqual(decoded[0].original, "2025-09-27T09:00:00")

        XCTAssertEqual(decoded[1].date, Date(timeIntervalSince1970: 1_758_963_600))
        XCTAssertFalse(decoded[1].isUnreadable)

        XCTAssertNil(decoded[2].date)
        XCTAssertNil(decoded[2].original)
        XCTAssertTrue(decoded[2].isUnreadable)
    }
}
