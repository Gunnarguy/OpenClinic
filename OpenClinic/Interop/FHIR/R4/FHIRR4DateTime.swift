//
//  FHIRR4DateTime.swift
//  OpenClinic
//
//  FHIR's date and dateTime strings, read by hand. A FHIR date may stop at the
//  year, the month or the day, and a dateTime must carry a time zone, so the
//  precision is kept beside the moment the string resolves to. Foundation's
//  formatters are not used: they are not Sendable, and the default ISO 8601
//  formatter rejects the fractional seconds most servers send.
//

import Foundation

/// One FHIR `date`, `dateTime` or `instant`, with how much of it the server stated.
nonisolated struct FHIRR4DateTime: Sendable, Hashable, Decodable {
    nonisolated enum Precision: String, Sendable, Hashable {
        case year, month, day, second
    }

    let date: Date
    let precision: Precision
    /// The string as the server sent it.
    let original: String

    /// Gregorian in the device's time zone. Only a calendar's time zone is ever used:
    /// FHIR dates are Gregorian whatever calendar the device shows.
    static var defaultCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// Carries the calendar for date-only values through a decoder's `userInfo`.
    static let calendarUserInfoKey = CodingUserInfoKey(rawValue: "FHIRR4DateTime.calendar")

    /// Accepts `YYYY`, `YYYY-MM`, `YYYY-MM-DD` and `YYYY-MM-DDThh:mm:ss[.fraction](Z|+hh:mm|-hh:mm)`,
    /// and nothing else. A value without a time resolves to noon of its first day in the
    /// calendar's time zone, so a date of birth never shows a day off.
    init?(_ string: String, calendar: Calendar = FHIRR4DateTime.defaultCalendar) {
        guard let parsed = Self.parse(string, timeZone: calendar.timeZone) else { return nil }
        date = parsed.date
        precision = parsed.precision
        original = string
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let parsed = FHIRR4DateTime(string, calendar: Self.calendar(for: decoder)) else {
            // The value stays out of the message: a date can be a date of birth.
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a FHIR date or dateTime.")
        }
        self = parsed
    }

    /// The calendar a decoder was given for date-only values, else the default.
    static func calendar(for decoder: Decoder) -> Calendar {
        guard let key = calendarUserInfoKey, let calendar = decoder.userInfo[key] as? Calendar else {
            return defaultCalendar
        }
        return calendar
    }

    // MARK: - Parsing

    private nonisolated enum ASCII {
        static let zero = UInt8(ascii: "0")
        static let nine = UInt8(ascii: "9")
        static let hyphen = UInt8(ascii: "-")
        static let plus = UInt8(ascii: "+")
        static let colon = UInt8(ascii: ":")
        static let period = UInt8(ascii: ".")
        static let t = UInt8(ascii: "T")
        static let z = UInt8(ascii: "Z")
    }

    private static func parse(_ string: String, timeZone: TimeZone) -> (date: Date, precision: Precision)? {
        let bytes = Array(string.utf8)
        let count = bytes.count
        guard let year = number(bytes, at: 0, width: 4), year >= 1 else { return nil }

        var month = 1
        var day = 1
        var precision = Precision.year
        if count > 4 {
            guard bytes[4] == ASCII.hyphen, let value = number(bytes, at: 5, width: 2), (1...12).contains(value) else {
                return nil
            }
            month = value
            precision = .month
        }
        if count > 7 {
            guard bytes[7] == ASCII.hyphen, let value = number(bytes, at: 8, width: 2),
                  (1...daysInMonth(month, year: year)).contains(value) else {
                return nil
            }
            day = value
            precision = .day
        }

        let days = daysSinceEpoch(year: year, month: month, day: day)
        guard count > 10 else {
            return (localNoon(onDay: days, in: timeZone), precision)
        }

        // From here the string must be a full dateTime: the shortest is 20 bytes, ending in "Z".
        guard count >= 20, bytes[10] == ASCII.t,
              let hour = number(bytes, at: 11, width: 2), hour <= 23, bytes[13] == ASCII.colon,
              let minute = number(bytes, at: 14, width: 2), minute <= 59, bytes[16] == ASCII.colon,
              let second = number(bytes, at: 17, width: 2), second <= 60 else {
            return nil
        }

        var index = 19
        var fraction = 0.0
        if bytes[index] == ASCII.period {
            index += 1
            let start = index
            var numerator = 0.0
            var scale = 1.0
            while index < count, let value = digit(bytes[index]) {
                // A Date cannot hold more than nanoseconds; later digits are checked and dropped.
                if index - start < 9 {
                    numerator = numerator * 10 + Double(value)
                    scale *= 10
                }
                index += 1
            }
            guard index > start else { return nil }
            fraction = numerator / scale
        }

        guard index < count else { return nil }
        var offset = 0
        if bytes[index] == ASCII.z {
            guard index + 1 == count else { return nil }
        } else {
            guard bytes[index] == ASCII.plus || bytes[index] == ASCII.hyphen, index + 6 == count,
                  let hours = number(bytes, at: index + 1, width: 2), bytes[index + 3] == ASCII.colon,
                  let minutes = number(bytes, at: index + 4, width: 2), minutes <= 59,
                  hours <= 13 || (hours == 14 && minutes == 0) else {
                return nil
            }
            offset = (hours * 3_600 + minutes * 60) * (bytes[index] == ASCII.plus ? 1 : -1)
        }

        let seconds = days * 86_400 + hour * 3_600 + minute * 60 + second - offset
        return (Date(timeIntervalSince1970: Double(seconds) + fraction), .second)
    }

    private static func digit(_ byte: UInt8) -> Int? {
        guard byte >= ASCII.zero, byte <= ASCII.nine else { return nil }
        return Int(byte - ASCII.zero)
    }

    /// A run of exactly `width` ASCII digits starting at `start`, or nil.
    private static func number(_ bytes: [UInt8], at start: Int, width: Int) -> Int? {
        guard start + width <= bytes.count else { return nil }
        var value = 0
        for index in start..<(start + width) {
            guard let next = digit(bytes[index]) else { return nil }
            value = value * 10 + next
        }
        return value
    }

    private static func daysInMonth(_ month: Int, year: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// Days from 1970-01-01 to a Gregorian date. Done with integers so the result
    /// does not depend on any calendar or locale setting of the device.
    private static func daysSinceEpoch(year: Int, month: Int, day: Int) -> Int {
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let monthFromMarch = (month + 9) % 12
        let dayOfYear = (153 * monthFromMarch + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    private static func localNoon(onDay days: Int, in timeZone: TimeZone) -> Date {
        let noonUTC = Double(days) * 86_400 + 43_200
        // The zone's offset is asked for twice: the first answer is for noon UTC, and the
        // second settles the days on which the offset changes between then and local noon.
        var offset = timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: noonUTC))
        offset = timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: noonUTC - Double(offset)))
        return Date(timeIntervalSince1970: noonUTC - Double(offset))
    }
}

/// A date field as a server sent it, readable or not. Servers do send strings FHIR does
/// not allow (the SMART sandbox has an Appointment whose start has no time zone), and one
/// such field must not cost the chart the whole resource, so this never fails to decode.
nonisolated struct FHIRR4LenientDateTime: Sendable, Hashable, Decodable {
    /// The string as sent, or nil when the field was not a string at all.
    let original: String?
    let value: FHIRR4DateTime?

    var date: Date? { value?.date }
    /// True when the server sent something here that is not a FHIR date.
    var isUnreadable: Bool { value == nil }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let string = try? container.decode(String.self) else {
            original = nil
            value = nil
            return
        }
        original = string
        value = FHIRR4DateTime(string, calendar: FHIRR4DateTime.calendar(for: decoder))
    }
}
