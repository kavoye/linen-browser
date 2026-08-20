// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct HistoryQuery: Equatable {
    let terms: String
    let dateRange: Range<Date>?

    static func parse(
        _ text: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> HistoryQuery {
        let dates = Dates(now: now, calendar: calendar)
        for pattern in patterns {
            guard let regex = try? Regex(pattern.source),
                  let match = text.firstMatch(of: regex)
            else { continue }
            let phrase = match.output[2].substring.map(String.init) ?? ""
            guard let range = pattern.range(phrase.lowercased(), dates) else { continue }
            var terms = text
            terms.removeSubrange(match.range)
            return HistoryQuery(
                terms: terms
                    .replacing(/\s+/, with: " ")
                    .trimmingCharacters(in: .whitespaces),
                dateRange: range
            )
        }
        return HistoryQuery(terms: text.trimmingCharacters(in: .whitespaces), dateRange: nil)
    }

    private struct Dates {
        let now: Date
        let calendar: Calendar

        var todayStart: Date {
            calendar.startOfDay(for: now)
        }
        var tomorrowStart: Date {
            calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
        }

        func day(_ start: Date) -> Range<Date>? {
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            return start..<end
        }

        func daysBack(_ count: Int) -> Range<Date>? {
            guard count > 0,
                  let lower = calendar.date(byAdding: .day, value: -count, to: tomorrowStart)
            else { return nil }
            return lower..<tomorrowStart
        }

        func lastPeriod(_ component: Calendar.Component) -> Range<Date>? {
            guard let thisStart = calendar.dateInterval(of: component, for: now)?.start,
                  let lower = calendar.date(byAdding: component, value: -1, to: thisStart)
            else { return nil }
            return lower..<tomorrowStart
        }

        func thisPeriod(_ component: Calendar.Component) -> Range<Date>? {
            guard let start = calendar.dateInterval(of: component, for: now)?.start else { return nil }
            return start..<tomorrowStart
        }

        private static let weekdayNumbers: [String: Int] = [
            "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
            "thursday": 5, "friday": 6, "saturday": 7,
        ]

        private static let monthNumbers: [String: Int] = [
            "january": 1, "february": 2, "march": 3, "april": 4,
            "may": 5, "june": 6, "july": 7, "august": 8,
            "september": 9, "october": 10, "november": 11, "december": 12,
        ]

        func weekday(named name: String, saidOnSameDayMeansToday: Bool) -> Range<Date>? {
            guard let target = Self.weekdayNumbers[name] else { return nil }
            let today = calendar.component(.weekday, from: todayStart)
            var delta = (today - target + 7) % 7
            if delta == 0, !saidOnSameDayMeansToday {
                delta = 7
            }
            guard let start = calendar.date(byAdding: .day, value: -delta, to: todayStart) else {
                return nil
            }
            return day(start)
        }

        func month(named name: String) -> Range<Date>? {
            guard let number = Self.monthNumbers[name] else { return nil }
            var components = calendar.dateComponents([.year], from: now)
            components.month = number
            components.day = 1
            guard var start = calendar.date(from: components) else { return nil }
            if start > now, let lastYear = calendar.date(byAdding: .year, value: -1, to: start) {
                start = lastYear
            }
            guard let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
            return start..<end
        }
    }

    private struct Pattern: Sendable {
        let source: String
        let range: @Sendable (String, Dates) -> Range<Date>?

        init(_ source: String, range: @escaping @Sendable (String, Dates) -> Range<Date>?) {
            self.source = source
            self.range = range
        }
    }

    private static let patterns: [Pattern] = [
        Pattern(#"(?i)\b(from\s+)?(today)\b"#) { _, dates in
            dates.day(dates.todayStart)
        },
        Pattern(#"(?i)\b(from\s+)?(yesterday)\b"#) { _, dates in
            guard let start = dates.calendar.date(
                byAdding: .day, value: -1, to: dates.todayStart
            ) else { return nil }
            return dates.day(start)
        },
        Pattern(#"(?i)\b(from\s+)?(this\s+week)\b"#) { _, dates in
            dates.thisPeriod(.weekOfYear)
        },
        Pattern(#"(?i)\b(from\s+)?(last\s+week)\b"#) { _, dates in
            dates.lastPeriod(.weekOfYear)
        },
        Pattern(#"(?i)\b(from\s+)?(this\s+month)\b"#) { _, dates in
            dates.thisPeriod(.month)
        },
        Pattern(#"(?i)\b(from\s+)?(last\s+month)\b"#) { _, dates in
            dates.lastPeriod(.month)
        },
        Pattern(#"(?i)\b(from\s+the\s+|from\s+)?((?:last|past)\s+\d+\s+days)\b"#) { phrase, dates in
            guard let count = Int(phrase.replacing(/\D/, with: "")) else { return nil }
            return dates.daysBack(count)
        },
        Pattern(#"(?i)\b(from\s+)?(\d+\s+days\s+ago)\b"#) { phrase, dates in
            guard let count = Int(phrase.replacing(/\D/, with: "")),
                  let start = dates.calendar.date(
                      byAdding: .day, value: -count, to: dates.todayStart
                  )
            else { return nil }
            return dates.day(start)
        },
        Pattern(#"(?i)\b(from\s+)?(last\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday))\b"#
        ) { phrase, dates in
            dates.weekday(
                named: phrase.replacing("last ", with: ""),
                saidOnSameDayMeansToday: false
            )
        },
        Pattern(#"(?i)\b(from\s+|on\s+)(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#
        ) { phrase, dates in
            dates.weekday(named: phrase, saidOnSameDayMeansToday: true)
        },
        Pattern(#"(?i)\b(from\s+|in\s+)(january|february|march|april|may|june|july|august|september|october|november|december)\b"#
        ) { phrase, dates in
            dates.month(named: phrase)
        },
    ]
}
