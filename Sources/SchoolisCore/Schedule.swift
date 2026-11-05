import Foundation

// MARK: - 课表

/// 课表里的一节课（或一个活动）
public struct ScheduleEntry: Codable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    /// 北京时间，比如 "2026-10-05T08:30:00"
    public let begin: String
    public let end: String
    public let room: String
    public let teachers: [String]
    public let isAllDay: Bool
    /// 3 = 课程（目前见到的都是 3）
    public let type: Int

    public var beginDate: Date? { SchoolTime.parse(begin) }
    public var endDate: Date? { SchoolTime.parse(end) }

    static func parse(_ value: Any?) -> [ScheduleEntry] {
        J.array(value).compactMap { d in
            guard let id = J.int(d["id"]), let begin = J.string(d["beginTime"]), let end = J.string(d["endTime"]) else { return nil }
            let teachers = J.array(d["teacherList"]).compactMap { J.string($0["name"]) }
            return ScheduleEntry(id: id, name: (J.string(d["name"]) ?? "").trimmingCharacters(in: .whitespaces),
                                 begin: begin, end: end, room: J.string(d["playgroundName"]) ?? "",
                                 teachers: teachers, isAllDay: J.bool(d["isAllDay"]) ?? false,
                                 type: J.int(d["scheduleType"]) ?? 0)
        }
    }
}

// MARK: - 考勤

public struct AttendanceSubject: Codable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let normal: Int
    public let late: Int
    public let earlyLeave: Int
    public let absent: Int

    public var total: Int { normal + late + earlyLeave + absent }
    /// 出勤率：和网页一样，按「正常出勤 ÷ 总次数」算（迟到不算正常出勤）
    public var rate: Double? { total > 0 ? Double(normal) / Double(total) * 100 : nil }
}

public struct AttendanceSummary: Codable, Hashable {
    /// 学校给的出勤率（%）
    public let rate: Double?
    public let total: Int
    public let normal: Int
    public let late: Int
    public let earlyLeave: Int
    public let absent: Int
    public let subjects: [AttendanceSubject]
    /// 统计的是哪段时间，比如 "2026-08-11 ~ 2026-10-08"
    public let range: String

    /// overall：GetAttendanceStatistic；bySubject：GetSubjectAttendanceStatistic
    static func parse(overall: Any?, bySubject: Any?, range: String) -> AttendanceSummary {
        let o = J.dict(overall)
        var counts: [Int: Int] = [:]
        // 字段名在接口里就拼错了（sataeCountList），照抄。状态：0 出勤，1 迟到，2 早退，3 缺勤
        for c in J.array(o["sataeCountList"]) {
            if let state = J.int(c["attendanceState"]) { counts[state] = J.int(c["count"]) ?? 0 }
        }
        let subjects = J.array(bySubject).compactMap { d -> AttendanceSubject? in
            guard let id = J.int(d["subjectId"]) else { return nil }
            return AttendanceSubject(id: id, name: J.string(d["subjectName"]) ?? "",
                                     normal: J.int(d["normalCount"]) ?? 0, late: J.int(d["lateCount"]) ?? 0,
                                     earlyLeave: J.int(d["earlyLeaveCount"]) ?? 0, absent: J.int(d["absentCount"]) ?? 0)
        }
        return AttendanceSummary(rate: J.double(o["attendanceRate"]), total: J.int(o["totalCount"]) ?? 0,
                                 normal: counts[0] ?? 0, late: counts[1] ?? 0, earlyLeave: counts[2] ?? 0,
                                 absent: counts[3] ?? 0, subjects: subjects, range: range)
    }
}
