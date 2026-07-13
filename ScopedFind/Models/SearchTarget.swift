import Foundation

enum SearchKind: String, CaseIterable, Identifiable {
    case names
    case contents

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .names:
            return "Names"
        case .contents:
            return "Contents"
        }
    }
}

enum SearchTarget: String, CaseIterable, Identifiable {
    case all
    case files
    case directories

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .all:
            return "Files and folders"
        case .files:
            return "Files only"
        case .directories:
            return "Folders/apps only"
        }
    }

    var findTypeArgument: String? {
        switch self {
        case .all:
            return nil
        case .files:
            return "f"
        case .directories:
            return "d"
        }
    }
}

enum SearchMatchMode: String, CaseIterable, Identifiable {
    case contains
    case regex
    case fuzzy

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .contains:
            return "Contains"
        case .regex:
            return "Regex"
        case .fuzzy:
            return "Fuzzy"
        }
    }

    var helpText: String {
        switch self {
        case .contains:
            return "Matches names containing the typed text."
        case .regex:
            return "Matches names using a regular expression."
        case .fuzzy:
            return "Matches names where typed characters appear in order, such as sf matching ScopedFind."
        }
    }
}

enum SearchDateFilter: String, CaseIterable, Identifiable {
    case any
    case modifiedLast5Minutes
    case modifiedLastHour
    case modifiedToday
    case modifiedLast7Days
    case modifiedOnDate
    case modifiedBeforeDate
    case modifiedSinceDate
    case modifiedBetweenDates

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .any:
            return "Any time"
        case .modifiedLast5Minutes:
            return "Last 5 min"
        case .modifiedLastHour:
            return "Last hour"
        case .modifiedToday:
            return "Today"
        case .modifiedLast7Days:
            return "Last 7 days"
        case .modifiedOnDate:
            return "On date..."
        case .modifiedBeforeDate:
            return "Before date..."
        case .modifiedSinceDate:
            return "Since date..."
        case .modifiedBetweenDates:
            return "Between dates (incl.)..."
        }
    }

    var usesCustomDate: Bool {
        switch self {
        case .modifiedOnDate, .modifiedBeforeDate, .modifiedSinceDate, .modifiedBetweenDates:
            return true
        case .any, .modifiedLast5Minutes, .modifiedLastHour, .modifiedToday, .modifiedLast7Days:
            return false
        }
    }

    var usesCustomEndDate: Bool {
        self == .modifiedBetweenDates
    }

    func matches(
        _ modificationDate: Date?,
        customDate: Date? = nil,
        customEndDate: Date? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        switch self {
        case .any:
            return true
        case .modifiedLast5Minutes:
            return matches(modificationDate, within: 5 * 60, now: now)
        case .modifiedLastHour:
            return matches(modificationDate, within: 60 * 60, now: now)
        case .modifiedToday:
            guard let modificationDate else {
                return false
            }
            return calendar.isDate(modificationDate, inSameDayAs: now)
        case .modifiedLast7Days:
            return matches(modificationDate, within: 7 * 24 * 60 * 60, now: now)
        case .modifiedOnDate:
            guard let modificationDate, let customDate else {
                return false
            }
            return calendar.isDate(modificationDate, inSameDayAs: customDate)
        case .modifiedBeforeDate:
            guard let modificationDate, let customDate else {
                return false
            }
            return modificationDate < calendar.startOfDay(for: customDate)
        case .modifiedSinceDate:
            guard let modificationDate, let customDate else {
                return false
            }
            return modificationDate >= calendar.startOfDay(for: customDate)
        case .modifiedBetweenDates:
            guard let modificationDate,
                  let customDate,
                  let customEndDate,
                  let inclusiveEnd = calendar.date(
                    byAdding: .day,
                    value: 1,
                    to: calendar.startOfDay(for: customEndDate)
                  ) else {
                return false
            }
            return modificationDate >= calendar.startOfDay(for: customDate) &&
                modificationDate < inclusiveEnd
        }
    }

    private func matches(_ modificationDate: Date?, within interval: TimeInterval, now: Date) -> Bool {
        guard let modificationDate else {
            return false
        }
        return modificationDate >= now.addingTimeInterval(-interval)
    }
}

enum SearchSizeFilter: String, CaseIterable, Identifiable {
    case any
    case smallerThan1MB
    case largerThan1MB
    case largerThan100MB
    case largerThan1GB
    case smallerThanCustom
    case largerThanCustom
    case exactCustom
    case betweenCustom

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .any:
            return "Any size"
        case .smallerThan1MB:
            return "< 1 MB"
        case .largerThan1MB:
            return "> 1 MB"
        case .largerThan100MB:
            return "> 100 MB"
        case .largerThan1GB:
            return "> 1 GB"
        case .smallerThanCustom:
            return "Less than..."
        case .largerThanCustom:
            return "More than..."
        case .exactCustom:
            return "Exact size..."
        case .betweenCustom:
            return "Between sizes (incl.)..."
        }
    }

    var usesCustomSize: Bool {
        switch self {
        case .smallerThanCustom, .largerThanCustom, .exactCustom, .betweenCustom:
            return true
        case .any, .smallerThan1MB, .largerThan1MB, .largerThan100MB, .largerThan1GB:
            return false
        }
    }

    var usesCustomMaximumSize: Bool {
        self == .betweenCustom
    }

    func matches(
        _ byteCount: UInt64?,
        customByteCount: UInt64? = nil,
        customMaximumByteCount: UInt64? = nil
    ) -> Bool {
        switch self {
        case .any:
            return true
        case .smallerThan1MB:
            guard let byteCount else {
                return false
            }
            return byteCount < Self.oneMegabyte
        case .largerThan1MB:
            guard let byteCount else {
                return false
            }
            return byteCount > Self.oneMegabyte
        case .largerThan100MB:
            guard let byteCount else {
                return false
            }
            return byteCount > 100 * Self.oneMegabyte
        case .largerThan1GB:
            guard let byteCount else {
                return false
            }
            return byteCount > Self.oneGigabyte
        case .smallerThanCustom:
            guard let byteCount, let customByteCount else {
                return false
            }
            return byteCount < customByteCount
        case .largerThanCustom:
            guard let byteCount, let customByteCount else {
                return false
            }
            return byteCount > customByteCount
        case .exactCustom:
            guard let byteCount, let customByteCount else {
                return false
            }
            return byteCount == customByteCount
        case .betweenCustom:
            guard let byteCount, let customByteCount, let customMaximumByteCount else {
                return false
            }
            return byteCount >= customByteCount && byteCount <= customMaximumByteCount
        }
    }

    // Displayed KB, MB, and GB values use decimal (base-10) units.
    private static let oneMegabyte: UInt64 = 1_000 * 1_000
    private static let oneGigabyte: UInt64 = 1_000 * 1_000 * 1_000
}

enum SearchSizeUnit: String, CaseIterable, Identifiable {
    case bytes
    case kilobytes
    case megabytes
    case gigabytes

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .bytes:
            return "B"
        case .kilobytes:
            return "KB"
        case .megabytes:
            return "MB"
        case .gigabytes:
            return "GB"
        }
    }

    var multiplier: Double {
        switch self {
        case .bytes:
            return 1
        case .kilobytes:
            return 1_000
        case .megabytes:
            return 1_000 * 1_000
        case .gigabytes:
            return 1_000 * 1_000 * 1_000
        }
    }

    func byteCount(from value: String) -> UInt64? {
        let normalizedValue = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let numericValue = Double(normalizedValue),
              numericValue >= 0,
              numericValue.isFinite else {
            return nil
        }

        let bytes = (numericValue * multiplier).rounded()
        guard bytes <= Double(UInt64.max) else {
            return nil
        }
        return UInt64(bytes)
    }
}

struct SearchFilters: Equatable {
    var dateFilter: SearchDateFilter = .any
    var customDate: Date?
    var customEndDate: Date?
    var sizeFilter: SearchSizeFilter = .any
    var customSizeBytes: UInt64?
    var customMaximumSizeBytes: UInt64?

    var isActive: Bool {
        dateFilter != .any || sizeFilter != .any
    }

    var validationMessage: String? {
        if dateFilter.usesCustomDate && customDate == nil {
            return "Choose a custom modified date."
        }

        if dateFilter.usesCustomEndDate && customEndDate == nil {
            return "Choose a custom modified date range."
        }

        if dateFilter.usesCustomEndDate,
           let customDate,
           let customEndDate,
           customEndDate < Calendar.current.startOfDay(for: customDate) {
            return "Choose a custom modified date range with the end date on or after the start date."
        }

        if sizeFilter.usesCustomSize && customSizeBytes == nil {
            return "Enter a valid custom size."
        }

        if sizeFilter.usesCustomMaximumSize && customMaximumSizeBytes == nil {
            return "Enter a valid custom size range."
        }

        if sizeFilter.usesCustomMaximumSize,
           let customSizeBytes,
           let customMaximumSizeBytes,
           customMaximumSizeBytes < customSizeBytes {
            return "Enter a custom size range with the maximum size greater than or equal to the minimum size."
        }

        return nil
    }

    func matches(_ url: URL, now: Date = Date(), fileManager: FileManager = .default) -> Bool {
        guard isActive else {
            return true
        }

        guard validationMessage == nil else {
            return false
        }

        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return false
        }

        let modificationDate = attributes[.modificationDate] as? Date
        guard dateFilter.matches(
            modificationDate,
            customDate: customDate,
            customEndDate: customEndDate,
            now: now
        ) else {
            return false
        }

        return sizeFilter.matches(
            Self.byteCount(from: attributes[.size]),
            customByteCount: customSizeBytes,
            customMaximumByteCount: customMaximumSizeBytes
        )
    }

    private static func byteCount(from value: Any?) -> UInt64? {
        if let number = value as? NSNumber {
            return number.uint64Value
        }

        if let value = value as? UInt64 {
            return value
        }

        if let value = value as? Int, value >= 0 {
            return UInt64(value)
        }

        return nil
    }
}
