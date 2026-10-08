//
//  ChartDateText.swift
//  OpenClinic
//
//  How the chart writes a date the source stated only to the year or the month.
//  A problem with onset "2015" is shown as "2015", never as "Jan 1, 2015".
//

import Foundation

nonisolated enum ChartDateText {
    /// Stored as a patient's date-of-birth precision when the source gave no date of birth at all.
    static let unknown = "unknown"

    /// "2015" for year precision, "Mar 2015" for month precision, "Mar 30, 2015" otherwise.
    /// `precision` is the stored raw value of `ImportedDatePrecision`, or nil for a full date.
    static func text(_ date: Date, precision: String?, calendar: Calendar = .current, locale: Locale = .current) -> String {
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        switch precision {
        case "year":
            style = style.year()
        case "month":
            style = style.month(.abbreviated).year()
        default:
            style = style.month(.abbreviated).day().year()
        }
        return date.formatted(style)
    }
}

extension ChartProblem {
    /// The onset as the source stated it, falling back to the day the problem was recorded.
    var sortDateText: String? {
        if let onsetDate { return ChartDateText.text(onsetDate, precision: onsetPrecision) }
        return recordedDate.map { ChartDateText.text($0, precision: nil) }
    }

    var abatementDateText: String? {
        abatementDate.map { ChartDateText.text($0, precision: abatementPrecision) }
    }
}

extension ChartProcedure {
    var performedDateText: String? {
        performedStart.map { ChartDateText.text($0, precision: performedPrecision) }
    }
}

extension ChartImmunization {
    var occurrenceDateText: String? {
        occurrenceDate.map { ChartDateText.text($0, precision: occurrencePrecision) }
    }
}
