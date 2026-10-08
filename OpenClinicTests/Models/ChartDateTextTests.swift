import XCTest
@testable import OpenClinic

/// A date the source stated only to the year or the month is written that way.
final class ChartDateTextTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let english = Locale(identifier: "en_US")
    /// 2015-03-30 12:00 UTC.
    private let date = Date(timeIntervalSince1970: 1_427_716_800)

    func testAYearAloneIsWrittenAsAYear() {
        XCTAssertEqual(ChartDateText.text(date, precision: "year", calendar: utc, locale: english), "2015")
    }

    func testAMonthIsWrittenWithoutADay() {
        XCTAssertEqual(ChartDateText.text(date, precision: "month", calendar: utc, locale: english), "Mar 2015")
    }

    func testAFullDateIsWrittenInFull() {
        XCTAssertEqual(ChartDateText.text(date, precision: nil, calendar: utc, locale: english), "Mar 30, 2015")
        XCTAssertEqual(ChartDateText.text(date, precision: "day", calendar: utc, locale: english), "Mar 30, 2015")
    }
}
