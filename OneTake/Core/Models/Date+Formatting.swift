import Foundation

// MARK: - Date helpers

extension Date {
    var otDue: String { formatted(.dateTime.weekday(.abbreviated).hour().minute()) }
    var otDayMonth: String { formatted(.dateTime.day().month(.abbreviated)) }
}
