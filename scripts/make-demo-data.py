#!/usr/bin/env python3
"""生成学习助手（SchoolisHelper）的演示数据文件夹（仅使用 Python 标准库）。

用法：
    python3 scripts/make-demo-data.py <输出文件夹>
"""

from __future__ import annotations

import json
import math
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

BEIJING_TZ = timezone(timedelta(hours=8))


def round1(x: float) -> float:
    """与 Grades.swift 的 GradeMath.round1 一致：保留 1 位小数（四舍五入）。"""
    return math.floor(x * 10.0 + 1e-6 + 0.5) / 10.0


def floor2(x: float) -> float:
    """与 Grades.swift 的 GradeMath.floor2 一致：舍去到 2 位小数。"""
    return math.floor(x * 100.0 + 1e-6) / 100.0


LEVEL_BANDS: list[dict[str, Any]] = [
    {"name": "A+", "gpa": 4.3, "min": 97.0, "max": 100.0},
    {"name": "A", "gpa": 4.0, "min": 93.0, "max": 96.9},
    {"name": "A-", "gpa": 3.7, "min": 90.0, "max": 92.9},
    {"name": "B+", "gpa": 3.3, "min": 87.0, "max": 89.9},
    {"name": "B", "gpa": 3.0, "min": 83.0, "max": 86.9},
    {"name": "B-", "gpa": 2.7, "min": 80.0, "max": 82.9},
    {"name": "C+", "gpa": 2.3, "min": 77.0, "max": 79.9},
    {"name": "C", "gpa": 2.0, "min": 73.0, "max": 76.9},
    {"name": "C-", "gpa": 1.7, "min": 70.0, "max": 72.9},
    {"name": "D+", "gpa": 1.3, "min": 67.0, "max": 69.9},
    {"name": "D", "gpa": 1.0, "min": 63.0, "max": 66.9},
    {"name": "D-", "gpa": 0.7, "min": 60.0, "max": 62.9},
    {"name": "F", "gpa": 0.0, "min": 0.0, "max": 59.9},
]


def find_band(score: float) -> dict[str, Any]:
    """与 GradeMath.band(for:in:) 一致。"""
    s = round1(score)
    for b in LEVEL_BANDS:
        if b["min"] <= s <= b["max"]:
            return b
    lower = [b for b in LEVEL_BANDS if b["min"] <= s]
    if lower:
        return max(lower, key=lambda b: b["min"])
    return LEVEL_BANDS[-1]


def compute_items_score(items: list[dict[str, Any]]) -> float | None:
    """与 GradeMath.score(_:) 一致：按已出分子项目加权平均，每层保留 1 位小数。"""
    weight = 0.0
    total = 0.0
    for item in items:
        prop = float(item["proportion"])
        if prop <= 0:
            continue
        s = item.get("score")
        if s is None:
            continue
        weight += prop
        total += prop * float(s)
    if weight <= 0:
        return None
    return round1(total / weight)


def fmt_school_dt(dt: datetime) -> str:
    """SchoolTime.parse 使用的北京时间格式：yyyy-MM-dd'T'HH:mm:ss。"""
    return dt.astimezone(BEIJING_TZ).strftime("%Y-%m-%dT%H:%M:%S")


def fmt_iso8601_utc(dt: datetime) -> str:
    """JSONDecoder.DateDecodingStrategy.iso8601 标准格式（不含毫秒）。"""
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def make_day_time(base_date: datetime, day_offset: int, hour: int, minute: int = 0) -> str:
    target = (base_date + timedelta(days=day_offset)).replace(
        hour=hour, minute=minute, second=0, microsecond=0, tzinfo=BEIJING_TZ
    )
    return fmt_school_dt(target)


def build_semester_name(now_bj: datetime) -> str:
    year = now_bj.year
    if now_bj.month >= 8:
        return f"{year}-{year + 1}学年第一学期"
    if now_bj.month == 1:
        return f"{year - 1}-{year}学年第一学期"
    return f"{year - 1}-{year}学年第二学期"


def build_tasks_and_grades(now_bj: datetime) -> tuple[list[dict[str, Any]], dict[str, Any], dict[str, list[int]]]:
    """构建作业列表、9 科成绩构成树及作业→评价项目映射，并按 Grades.swift 算法严格算分。"""
    subjects_meta = [
        {"id": 101, "name": "数学", "classId": 201, "teacher": "张老师", "room": "A101", "isInGrade": True},
        {"id": 102, "name": "语文", "classId": 202, "teacher": "李老师", "room": "A102", "isInGrade": True},
        {"id": 103, "name": "英语", "classId": 203, "teacher": "王老师", "room": "A201", "isInGrade": True},
        {"id": 104, "name": "科学", "classId": 204, "teacher": "陈老师", "room": "B203", "isInGrade": True},
        {"id": 105, "name": "历史", "classId": 205, "teacher": "刘老师", "room": "A103", "isInGrade": True},
        {"id": 106, "name": "地理", "classId": 206, "teacher": "赵老师", "room": "A104", "isInGrade": True},
        {"id": 107, "name": "信息技术", "classId": 207, "teacher": "周老师", "room": "C301", "isInGrade": True},
        {"id": 108, "name": "音乐", "classId": 208, "teacher": "吴老师", "room": "D102", "isInGrade": True},
        {"id": 109, "name": "体育", "classId": 209, "teacher": "郑老师", "room": "B101", "isInGrade": True},
    ]
    teacher_by_subject = {s["name"]: s["teacher"] for s in subjects_meta}

    # 成绩构成树定义（score 与 level 稍后根据叶子项目关联的已批改作业自动计算）
    subject_trees: dict[int, list[dict[str, Any]]] = {
        101: [  # 数学 -> 92.0 (A-, 3.7)
            {
                "id": 1010,
                "name": "平时作业",
                "proportion": 40.0,
                "children": [
                    {"id": 1011, "name": "作业与练习", "proportion": 60.0, "children": []},
                    {"id": 1012, "name": "课堂笔记", "proportion": 40.0, "children": []},
                ],
            },
            {"id": 1013, "name": "阶段测验", "proportion": 40.0, "children": []},
            {"id": 1014, "name": "期末考试", "proportion": 20.0, "children": []},
        ],
        102: [  # 语文 -> 91.8 (A-, 3.7)
            {
                "id": 1020,
                "name": "过程性评价",
                "proportion": 50.0,
                "children": [
                    {"id": 1021, "name": "古诗文背诵与默写", "proportion": 50.0, "children": []},
                    {"id": 1022, "name": "阅读与练笔", "proportion": 50.0, "children": []},
                ],
            },
            {"id": 1023, "name": "单元测验", "proportion": 30.0, "children": []},
            {"id": 1024, "name": "期末考试", "proportion": 20.0, "children": []},
        ],
        103: [  # 英语 -> 95.7 (A, 4.0)
            {
                "id": 1030,
                "name": "平时学业",
                "proportion": 40.0,
                "children": [
                    {"id": 1031, "name": "Notebooks & Homework", "proportion": 50.0, "children": []},
                    {"id": 1032, "name": "Speaking & Presentation", "proportion": 50.0, "children": []},
                ],
            },
            {"id": 1033, "name": "Quizzes & Tests", "proportion": 40.0, "children": []},
            {"id": 1034, "name": "Final Exam", "proportion": 20.0, "children": []},
        ],
        104: [  # 科学 -> 89.2 (B+, 3.3)
            {"id": 1041, "name": "实验与探究", "proportion": 35.0, "children": []},
            {"id": 1042, "name": "作业与练习", "proportion": 25.0, "children": []},
            {"id": 1043, "name": "单元测验", "proportion": 20.0, "children": []},
            {"id": 1044, "name": "期末考试", "proportion": 20.0, "children": []},
        ],
        105: [  # 历史 -> 85.8 (B, 3.0)，补交「历史材料分析：商鞅变法」拿满分可直上 98.3 (A+)，单作业让 GPA 达 4.02
            {
                "id": 1050,
                "name": "平时评价",
                "proportion": 50.0,
                "children": [
                    {"id": 1051, "name": "课堂笔记与练习", "proportion": 50.0, "children": []},
                    {"id": 1052, "name": "史料探究作业", "proportion": 50.0, "children": []},
                ],
            },
            {"id": 1053, "name": "阶段测验", "proportion": 30.0, "children": []},
            {"id": 1054, "name": "项目展示", "proportion": 20.0, "children": []},
        ],
        106: [  # 地理 -> 97.1 (A+, 4.3)
            {"id": 1061, "name": "地图册与填图作业", "proportion": 40.0, "children": []},
            {"id": 1062, "name": "随堂小测", "proportion": 40.0, "children": []},
            {"id": 1063, "name": "期末考查", "proportion": 20.0, "children": []},
        ],
        107: [  # 信息技术 -> 98.0 (A+, 4.3)
            {"id": 1071, "name": "上机实操与作品", "proportion": 60.0, "children": []},
            {"id": 1072, "name": "课堂表现与机房规范", "proportion": 40.0, "children": []},
        ],
        108: [  # 音乐 -> 98.6 (A+, 4.3)
            {"id": 1081, "name": "演唱与演奏展示", "proportion": 60.0, "children": []},
            {"id": 1082, "name": "课堂表现与乐理", "proportion": 40.0, "children": []},
        ],
        109: [  # 体育 -> 97.5 (A+, 4.3)
            {"id": 1091, "name": "体能与专项测评", "proportion": 60.0, "children": []},
            {"id": 1092, "name": "课堂考勤与参与", "proportion": 40.0, "children": []},
        ],
    }

    raw_tasks: list[dict[str, Any]] = [
        # ==================== 数学（6 条）====================
        {
            "id": 5001,
            "name": "第 1 章有理数练习册",
            "subjectName": "数学",
            "typeName": "家庭作业",
            # 开始时间 = 截止时间：老师建的登分格子（TaskMode.slot）
            "beginTime": make_day_time(now_bj, -18, 16, 0),
            "endTime": make_day_time(now_bj, -18, 16, 0),
            "score": 18.0,
            "totalScore": 20.0,
            "finishState": 1,
            "learningTaskState": 4,
            "isExempt": False,
            "itemIds": [1011],
        },
        {
            "id": 5002,
            "name": "第 2 章整式加减练习卷",
            "subjectName": "数学",
            "typeName": "家庭作业",
            "beginTime": make_day_time(now_bj, -11, 16, 0),
            "endTime": make_day_time(now_bj, -11, 16, 0),
            "score": 17.0,
            "totalScore": 20.0,
            "finishState": 1,
            "learningTaskState": 4,
            "isExempt": False,
            "itemIds": [1011],
        },
        {
            "id": 5003,
            "name": "第 4 章函数综合练习卷",
            "subjectName": "数学",
            "typeName": "家庭作业",
            # 今天 23:59 截止（要交的作业，拿满分数学 92.0 -> 93.9 升 A）
            "beginTime": make_day_time(now_bj, -2, 8, 30),
            "endTime": make_day_time(now_bj, 0, 23, 59),
            "score": None,
            "totalScore": 40.0,
            "finishState": None,
            "learningTaskState": 2,
            "isExempt": False,
            "itemIds": [1011],
        },
        {
            "id": 5004,
            "name": "第 3 单元练习册",
            "subjectName": "数学",
            "typeName": "家庭作业",
            # 3 天后截止（7 天内）
            "beginTime": make_day_time(now_bj, -1, 9, 0),
            "endTime": make_day_time(now_bj, 3, 21, 0),
            "score": None,
            "totalScore": 20.0,
            "finishState": None,
            "learningTaskState": 2,
            "isExempt": False,
            "itemIds": [1011],
        },
        {
            "id": 5005,
            "name": "数学错题本整理检查",
            "subjectName": "数学",
            "typeName": "平时成绩",
            "beginTime": make_day_time(now_bj, -9, 10, 0),
            "endTime": make_day_time(now_bj, -7, 17, 0),
            "score": 19.0,
            "totalScore": 20.0,
            "finishState": 1,
            "learningTaskState": 4,
            "isExempt": False,
            "itemIds": [1012],
        },
        {
            "id": 5006,
            "name": "第 1-2 章阶段数学测试",
            "subjectName": "数学",
            "typeName": "小测试",
            "beginTime": make_day_time(now_bj, -8, 10, 20),
            "endTime": make_day_time(now_bj, -8, 10, 20),
            "score": 93.5,
            "totalScore": 100.0,
            "finishState": 1,
            "learningTaskState": 4,
            "isExempt": False,
            "itemIds": [1013],
        },
        # ==================== 语文（6 条）====================
        {
            "id": 5007,
            "name": "古诗文背诵：岳阳楼记",
            "subjectName": "语文",
            "typeName": "平时成绩",
            # 开始时间 = 截止时间：登分格子（TaskMode.slot）
            "beginTime": make_day_time(now_bj, -15, 11, 0),
            "endTime": make_day_time(now_bj, -15, 11, 0),
            "score": 19.0,
            "totalScore": 20.0,
            "finishState": 1,
            "learningTaskState": 4,
            "isExempt": False,
            "itemIds": [1021],
        },
        {
            "id": 5008,
            "name": "提交古诗默写单（第三周）",
            "subjectName": "语文",
            "typeName": "家庭作业",
            "beginTime": make_day_time(now_bj, -12, 8, 30),
            "endTime": make_day_time(now_bj, -10, 20, 0),
            "score": 18.0,
            "totalScore": 20.0,
            "finishState": 1,
            "learningTaskState": 4,
            "isExempt": False,
            "itemIds": [1021],
        },
        {
            "id": 5009,
            "name": "提交古诗默写订正页",
            "subjectName": "语文",
            "typeName": "家庭作业",
            # 已过期未交（2 天前截止，要交的作业 -> overdue）
            "beginTime": make_day_time(now_bj, -5, 8, 30),
            "endTime": make_day_time(now_bj, -2, 21, 0),
            "score": None,
            "totalScore": 20.0,
            "finishState": None,
            "learningTaskState": 2,
            "isExempt": False,
            "itemIds": [1021],
        },
        {
            "id": 5010,
            "name": "周记练笔：秋日校园",
            "subjectName": "语文",
            "typeName": "作业",
            # 迟交但已批改（finishState = 3, learningTaskState = 4）
            "beginTime": make_day_time(now_bj, -14, 9, 0),
            "endTime": make_day_time(now_bj, -9, 21, 0),
            "score": 26.5,
            "totalScore": 30.0,
            "finishState": 3,
            "learningTaskState": 4,
            "isExempt": False,
            "itemIds": [1022],
        },
        {
            "id": 5011,
            "name": "名著阅读批注：朝花夕拾",
            "subjectName": "语文",
            "typeName": "名著阅读",
            # 已交、待批改（finishState = 1, learningTaskState = 5）
            "beginTime": make_day_time(now_bj, -6, 8, 30),
            "endTime": make_day_time(now_bj, -1, 20, 0),
            "score": None,
            "totalScore": 20.0,
            "finishState": 1,
            "learningTaskState": 5,
            "isExempt": False,
            "itemIds": [1022],
        },
        {
            "id": 5012,
            "name": "第一单元阅读与写作测评",
            "subjectName": "语文",
            "typeName": "小测试",
            "beginTime": make_day_time(now_bj, -7, 9, 20),
            "endTime": make_day_time(now_bj, -7, 10, 0),
            "score": 47.0,
            "totalScore": 50.0,
            "finishState": 1,
            "learningTaskState": 4,
            "isExempt": False,
            "itemIds": [1023],
        },
        # ==================== 英语（5 条）====================
        {
            "id": 5013,
            "name": "Unit 1 Workbook",
            "subjectName": "英语",
            "typeName": "General Homework",
            # 登分格子（beginTime == endTime）
            "beginTime": make_day_time(now_bj, -13, 15, 0),
            "endTime": make_day_time(now_bj, -13, 15, 0),
            "score": 38.5,
            "totalScore": 40.0,
            "finishState": 1,
            "learningTaskState": 4,
            "isExempt": False,
            "itemIds": [1031],
        },
        {
            "id": 5014,
            "name": "Notebook Check",
            "subjectName": "英语",
            "typeName": "Notebooks/HW",
            # 明天截止（课上检查 TaskMode.check）
            "beginTime": make_day_time(now_bj, -2, 9, 0),
            "endTime": make_day_time(now_bj, 1, 14, 10),
            "score": None,
            "totalScore": 20.0,
            "finishState": None,
            "learningTaskState": 2,
            "isExempt": False,
            "itemIds": [1031],
        },
        {
            "id": 5015,
            "name": "Oral Presentation: My Favorite Book",
            "subjectName": "英语",
            "typeName": "Project or Presentation",
            "beginTime": make_day_time(now_bj, -11, 9, 0),
            "endTime": make_day_time(now_bj, -6, 14, 50),
            "score": 28.5,
            "totalScore": 30.0,
            "finishState": 1,
            "learningTaskState": 4,
            "isExempt": False,
            "itemIds": [1032],
        },
        {
            "id": 5016,
            "name": "Unit 1 Grammar & Reading Test",
            "subjectName": "英语",
            "typeName": "Quiz",
            "beginTime": make_day_time(now_bj, -9, 10, 20),
            "endTime": make_day_time(now_bj, -9, 11, 0),
            "score": 47.8,
            "totalScore": 50.0,
            "finishState": 1,
            "learningTaskState": 4,
            "isExempt": False,
            "itemIds": [1033],
        },
        {
            "id": 5017,
            "name": "Unit 2 Vocabulary Quiz",
            "subjectName": "英语",
            "typeName": "Vocabulary",
            # 明天截止（课上考 TaskMode.test）
            "beginTime": make_day_time(now_bj, -3, 8, 30),
            "endTime": make_day_time(now_bj, 1, 10, 20),
            "score": None,
            "totalScore": 20.0,
            "finishState": None,
            "learningTaskState": 2,
            "isExempt": False,
            "itemIds": [1033],
        },
        # ==================== 科学（6 条）====================
        {
            "id": 5018,
            "name": "实验报告：光的折射",
            "subjectName": "科学",
            "typeName": "学习习惯",
            # TaskCategory.other + TaskMode.classwork，得分偏低(16/20)可重做提分
            "beginTime": make_day_time(now_bj, -10, 13, 20),
            "endTime": make_day_time(now_bj, -8, 18, 0),
            "score": 16.0,
            "totalScore": 20.0,
            "finishState": 1,
            "learningTaskState": 4,
            "isExempt": False,
            "itemIds": [1041],
        },
        {
            "id": 5019,
            "name": "提交实验探究单：凸透镜成像规律",
            "subjectName": "科学",
            "typeName": "动手操作",
            # 今天 23:50 截止（要交的作业，满分 30，拿满分科学 89.2 -> 94.4 从 B+ 升 A）
            "beginTime": make_day_time(now_bj, -3, 13, 20),
            "endTime": make_day_time(now_bj, 0, 23, 50),
            "score": None,
            "totalScore": 30.0,
            "finishState": None,
            "learningTaskState": 2,
            "isExempt": False,
            "itemIds": [1041],
        },
        {
            "id": 5020,
            "name": "第 2 章声现象课后练习",
            "subjectName": "科学",
            "typeName": "家庭作业",
            "beginTime": make_day_time(now_bj, -14, 8, 30),
            "endTime": make_day_time(now_bj, -12, 20, 0),
            "score": 19.0,
            "totalScore": 20.0,
            "finishState": 1,
            "learningTaskState": 4,
            "isExempt": False,
            "itemIds": [1042],
        },
        {
            "id": 5021,
            "name": "第 3 章物态变化练习册",
            "subjectName": "科学",
            "typeName": "家庭作业",
            # 过期未交（3 天前截止 -> overdue）
            "beginTime": make_day_time(now_bj, -6, 8, 30),
            "endTime": make_day_time(now_bj, -3, 21, 0),
            "score": None,
            "totalScore": 20.0,
            "finishState": None,
            "learningTaskState": 2,
            "isExempt": False,
            "itemIds": [1042],
        },
        {
            "id": 5022,
            "name": "第 4 章光现象作业单",
            "subjectName": "科学",
            "typeName": "家庭作业",
            # 明天 20:30 截止（TaskMode.submit）
            "beginTime": make_day_time(now_bj, -1, 10, 0),
            "endTime": make_day_time(now_bj, 1, 20, 30),
            "score": None,
            "totalScore": 20.0,
            "finishState": None,
            "learningTaskState": 2,
            "isExempt": False,
            "itemIds": [1042],
        },
        {
            "id": 5023,
            "name": "科学第 1-2 章阶段测试",
            "subjectName": "科学",
            "typeName": "小测试",
            "beginTime": make_day_time(now_bj, -7, 13, 20),
            "endTime": make_day_time(now_bj, -7, 14, 0),
            "score": 49.0,
            "totalScore": 50.0,
            "finishState": 1,
            "learningTaskState": 4,
            "isExempt": False,
            "itemIds": [1043],
        },
        # ==================== 历史（7 条）====================
        {
            "id": 5024,
            "name": "第 1 单元课堂笔记整理",
            "subjectName": "历史",
            "typeName": "平时成绩",
            "beginTime": make_day_time(now_bj, -16, 14, 10),
            "endTime": make_day_time(now_bj, -16, 14, 10),
            "score": 19.8,
            "totalScore": 20.0,
            "finishState": 1,
            "learningTaskState": 4,
            "isExempt": False,
            "itemIds": [1051],
        },
        {
            "id": 5025,
            "name": "第 2 单元随堂练习",
            "subjectName": "历史",
            "typeName": "平时成绩",
            # 课上做完的登分格子（begin==end，已过截止但等老师登分 -> awaitingTeacher）
            "beginTime": make_day_time(now_bj, -1, 14, 10),
            "endTime": make_day_time(now_bj, -1, 14, 10),
            "score": None,
            "totalScore": 20.0,
            "finishState": None,
            "learningTaskState": 2,
            "isExempt": False,
            "itemIds": [1051],
        },
        {
            "id": 5026,
            "name": "第 1 单元史料研读：百家争鸣",
            "subjectName": "历史",
            "typeName": "家庭作业",
            "beginTime": make_day_time(now_bj, -14, 9, 0),
            "endTime": make_day_time(now_bj, -11, 20, 0),
            "score": 24.0,
            "totalScore": 25.0,
            "finishState": 1,
            "learningTaskState": 4,
            "isExempt": False,
            "itemIds": [1052],
        },
        {
            "id": 5027,
            "name": "历史材料分析：商鞅变法",
            "subjectName": "历史",
            "typeName": "家庭作业",
            # 老师记为未完成且已批改 0/25（finishState=2, learningTaskState=4, totalScore=25）
            # 补交拿满分可让历史从 85.8(B) 升至 98.3(A+)，单作业让总 GPA 从 3.87 升至 4.02！
            "beginTime": make_day_time(now_bj, -8, 9, 0),
            "endTime": make_day_time(now_bj, -4, 20, 0),
            "score": 0.0,
            "totalScore": 25.0,
            "finishState": 2,
            "learningTaskState": 4,
            "isExempt": False,
            "itemIds": [1052],
        },
        {
            "id": 5028,
            "name": "中国古代史第一单元测验",
            "subjectName": "历史",
            "typeName": "小测试",
            "beginTime": make_day_time(now_bj, -6, 14, 10),
            "endTime": make_day_time(now_bj, -6, 14, 50),
            "score": 49.0,
            "totalScore": 50.0,
            "finishState": 1,
            "learningTaskState": 4,
            "isExempt": False,
            "itemIds": [1053],
        },
        {
            "id": 5029,
            "name": "历史人物卡片制作",
            "subjectName": "历史",
            "typeName": "项目学习及展示",
            "beginTime": make_day_time(now_bj, -15, 9, 0),
            "endTime": make_day_time(now_bj, -10, 18, 0),
            "score": 49.0,
            "totalScore": 50.0,
            "finishState": 1,
            "learningTaskState": 4,
            "isExempt": False,
            "itemIds": [1054],
        },
        {
            "id": 5030,
            "name": "小组展示：古代文明",
            "subjectName": "历史",
            "typeName": "项目学习及展示",
            # 4 天后截止（7 天内，TaskMode.present）
            "beginTime": make_day_time(now_bj, -2, 10, 0),
            "endTime": make_day_time(now_bj, 4, 14, 10),
            "score": None,
            "totalScore": 30.0,
            "finishState": None,
            "learningTaskState": 2,
            "isExempt": False,
            "itemIds": [1054],
        },
        # ==================== 地理（4 条）====================
        {
            "id": 5031,
            "name": "中国地形图填图练习",
            "subjectName": "地理",
            "typeName": "家庭作业",
            "beginTime": make_day_time(now_bj, -12, 8, 30),
            "endTime": make_day_time(now_bj, -9, 20, 0),
            "score": 19.5,
            "totalScore": 20.0,
            "finishState": 1,
            "learningTaskState": 4,
            "isExempt": False,
            "itemIds": [1061],
        },
        {
            "id": 5032,
            "name": "气候类型分布图绘制",
            "subjectName": "地理",
            "typeName": "家庭作业",
            # 2 天后截止（7 天内）
            "beginTime": make_day_time(now_bj, -1, 9, 0),
            "endTime": make_day_time(now_bj, 2, 20, 0),
            "score": None,
            "totalScore": 20.0,
            "finishState": None,
            "learningTaskState": 2,
            "isExempt": False,
            "itemIds": [1061],
        },
        {
            "id": 5033,
            "name": "选做：家乡地形考察记录",
            "subjectName": "地理",
            "typeName": "动手操作",
            # 免做作业（isExempt = True -> completed）
            "beginTime": make_day_time(now_bj, -10, 9, 0),
            "endTime": make_day_time(now_bj, -5, 20, 0),
            "score": None,
            "totalScore": 10.0,
            "finishState": 1,
            "learningTaskState": 2,
            "isExempt": True,
            "itemIds": [1061],
        },
        {
            "id": 5034,
            "name": "疆域与行政区划小测",
            "subjectName": "地理",
            "typeName": "小测试",
            "beginTime": make_day_time(now_bj, -6, 15, 5),
            "endTime": make_day_time(now_bj, -6, 15, 45),
            "score": 29.0,
            "totalScore": 30.0,
            "finishState": 1,
            "learningTaskState": 4,
            "isExempt": False,
            "itemIds": [1062],
        },
        # ==================== 信息技术（4 条）====================
        {
            "id": 5035,
            "name": "Python 基础：分支与循环作品",
            "subjectName": "信息技术",
            "typeName": "动手操作",
            "beginTime": make_day_time(now_bj, -14, 10, 0),
            "endTime": make_day_time(now_bj, -9, 18, 0),
            "score": 29.5,
            "totalScore": 30.0,
            "finishState": 1,
            "learningTaskState": 4,
            "isExempt": False,
            "itemIds": [1071],
        },
        {
            "id": 5036,
            "name": "数据分析小项目：气温变化图表",
            "subjectName": "信息技术",
            "typeName": "Project Work",
            # 已交、等老师批改（finishState = 1, learningTaskState = 5）
            "beginTime": make_day_time(now_bj, -5, 10, 0),
            "endTime": make_day_time(now_bj, -1, 18, 0),
            "score": None,
            "totalScore": 30.0,
            "finishState": 1,
            "learningTaskState": 5,
            "isExempt": False,
            "itemIds": [1071],
        },
        {
            "id": 5037,
            "name": "期末创意编程项目设计书",
            "subjectName": "信息技术",
            "typeName": "Summative Projects",
            # 10 天后截止（7 天以后 -> later）
            "beginTime": make_day_time(now_bj, 0, 9, 0),
            "endTime": make_day_time(now_bj, 10, 20, 0),
            "score": None,
            "totalScore": 40.0,
            "finishState": None,
            "learningTaskState": 2,
            "isExempt": False,
            "itemIds": [1071],
        },
        {
            "id": 5038,
            "name": "机房操作规范与器材整理",
            "subjectName": "信息技术",
            "typeName": "学习习惯",
            # TaskCategory.other
            "beginTime": make_day_time(now_bj, -15, 9, 0),
            "endTime": make_day_time(now_bj, -10, 17, 0),
            "score": 19.5,
            "totalScore": 20.0,
            "finishState": 1,
            "learningTaskState": 4,
            "isExempt": False,
            "itemIds": [1072],
        },
        # ==================== 音乐（3 条）====================
        {
            "id": 5039,
            "name": "合唱声部视唱考核",
            "subjectName": "音乐",
            "typeName": "项目学习及展示",
            "beginTime": make_day_time(now_bj, -12, 15, 5),
            "endTime": make_day_time(now_bj, -8, 15, 45),
            "score": 29.5,
            "totalScore": 30.0,
            "finishState": 1,
            "learningTaskState": 4,
            "isExempt": False,
            "itemIds": [1081],
        },
        {
            "id": 5040,
            "name": "乐理知识随堂小测",
            "subjectName": "音乐",
            "typeName": "小测试",
            "beginTime": make_day_time(now_bj, -9, 15, 5),
            "endTime": make_day_time(now_bj, -9, 15, 45),
            "score": 19.8,
            "totalScore": 20.0,
            "finishState": 1,
            "learningTaskState": 4,
            "isExempt": False,
            "itemIds": [1082],
        },
        {
            "id": 5041,
            "name": "音乐课堂表现评价",
            "subjectName": "音乐",
            "typeName": "课堂表现",
            # 课堂表现（TaskCategory.participation, TaskMode.teacher -> awaitingTeacher）
            "beginTime": make_day_time(now_bj, -15, 8, 30),
            "endTime": make_day_time(now_bj, 14, 18, 0),
            "score": None,
            "totalScore": 20.0,
            "finishState": None,
            "learningTaskState": 2,
            "isExempt": False,
            "itemIds": [1082],
        },
        # ==================== 体育（4 条）====================
        {
            "id": 5042,
            "name": "1000米耐力跑与立定跳远单元评估",
            "subjectName": "体育",
            "typeName": "体育单元评估",
            "beginTime": make_day_time(now_bj, -11, 15, 55),
            "endTime": make_day_time(now_bj, -7, 16, 35),
            "score": 58.5,
            "totalScore": 60.0,
            "finishState": 1,
            "learningTaskState": 4,
            "isExempt": False,
            "itemIds": [1091],
        },
        {
            "id": 5043,
            "name": "提交体质健康自测记录表",
            "subjectName": "体育",
            "typeName": "家庭作业",
            # 老师记为未完成但尚未批改出分（finishState = 2, learningTaskState = 2, totalScore = 10 > 0）
            "beginTime": make_day_time(now_bj, -6, 8, 30),
            "endTime": make_day_time(now_bj, -2, 18, 0),
            "score": None,
            "totalScore": 10.0,
            "finishState": 2,
            "learningTaskState": 2,
            "isExempt": False,
            "itemIds": [1091],
        },
        {
            "id": 5044,
            "name": "前半学期体育课出勤记录",
            "subjectName": "体育",
            "typeName": "中学考勤",
            # 考勤（TaskCategory.attendance, TaskMode.teacher）
            "beginTime": make_day_time(now_bj, -25, 8, 30),
            "endTime": make_day_time(now_bj, -5, 17, 0),
            "score": 19.5,
            "totalScore": 20.0,
            "finishState": 1,
            "learningTaskState": 4,
            "isExempt": False,
            "itemIds": [1092],
        },
        {
            "id": 5045,
            "name": "后半学期体育课堂考勤",
            "subjectName": "体育",
            "typeName": "中学考勤",
            # 考勤进行中（TaskCategory.attendance, TaskMode.teacher -> awaitingTeacher）
            "beginTime": make_day_time(now_bj, -4, 8, 30),
            "endTime": make_day_time(now_bj, 20, 17, 0),
            "score": None,
            "totalScore": 20.0,
            "finishState": None,
            "learningTaskState": 2,
            "isExempt": False,
            "itemIds": [1092],
        },
    ]

    tasks_out: list[dict[str, Any]] = []
    task_items_map: dict[str, list[int]] = {}
    graded_by_leaf: dict[int, list[tuple[float, float]]] = {}

    for t in raw_tasks:
        tid = int(t["id"])
        item_ids = list(t.get("itemIds", []))
        task_items_map[str(tid)] = item_ids

        if t["learningTaskState"] == 4 and (t.get("totalScore") or 0) > 0:
            earned = float(t.get("score") or 0.0)
            possible = float(t["totalScore"])
            for lid in item_ids:
                graded_by_leaf.setdefault(lid, []).append((earned, possible))

        tasks_out.append(
            {
                "id": tid,
                "name": t["name"],
                "subjectName": t["subjectName"],
                "typeName": t["typeName"],
                "beginTime": t["beginTime"],
                "endTime": t["endTime"],
                "score": t["score"],
                "totalScore": t["totalScore"],
                "finishState": t["finishState"],
                "learningTaskState": t["learningTaskState"],
                "isExempt": t["isExempt"],
                "lastEditorName": teacher_by_subject[t["subjectName"]],
            }
        )

    def populate_item_scores(item: dict[str, Any]) -> None:
        children = item.get("children", [])
        if not children:
            pairs = graded_by_leaf.get(int(item["id"]), [])
            if pairs:
                earned_sum = sum(p[0] for p in pairs)
                possible_sum = sum(p[1] for p in pairs)
                sc = round1(earned_sum / possible_sum * 100.0)
                item["score"] = sc
                item["level"] = find_band(sc)["name"]
            else:
                item["score"] = None
                item["level"] = ""
        else:
            for child in children:
                populate_item_scores(child)
            sc = compute_items_score(children)
            item["score"] = sc
            item["level"] = find_band(sc)["name"] if sc is not None else ""

    subjects_out: list[dict[str, Any]] = []
    for meta in subjects_meta:
        sid = meta["id"]
        items = subject_trees[sid]
        for item in items:
            populate_item_scores(item)
        subj_score = compute_items_score(items)
        subjects_out.append(
            {
                "id": sid,
                "name": meta["name"],
                "classId": meta["classId"],
                "score": subj_score,
                "isInGrade": meta["isInGrade"],
                "items": items,
            }
        )

    grades_data = {
        "subjects": subjects_out,
        "bands": LEVEL_BANDS,
    }
    return tasks_out, grades_data, task_items_map


def compute_official_gpa(grades_data: dict[str, Any]) -> float:
    """与 GradeMath.floor2(GradeMath.gpa(...)) 完全一致。"""
    points: list[float] = []
    for subj in grades_data["subjects"]:
        if not subj.get("isInGrade", True):
            continue
        sc = subj.get("score")
        if sc is None:
            continue
        band = find_band(float(sc))
        points.append(float(band["gpa"]))
    raw_gpa = sum(points) / len(points) if points else 0.0
    return floor2(raw_gpa)


def build_schedule(now_bj: datetime) -> list[dict[str, Any]]:
    """生成本周和下周（周一至周五，每天 7～8 节课，08:30 起）的课表。"""
    subject_info = {
        "数学": ("A101", "张老师"),
        "语文": ("A102", "李老师"),
        "英语": ("A201", "王老师"),
        "科学": ("B203", "陈老师"),
        "历史": ("A103", "刘老师"),
        "地理": ("A104", "赵老师"),
        "信息技术": ("C301", "周老师"),
        "音乐": ("D102", "吴老师"),
        "体育": ("B101", "郑老师"),
    }

    periods = [
        ((8, 30), (9, 10)),
        ((9, 20), (10, 0)),
        ((10, 20), (11, 0)),
        ((11, 10), (11, 50)),
        ((13, 20), (14, 0)),
        ((14, 10), (14, 50)),
        ((15, 5), (15, 45)),
        ((15, 55), (16, 35)),
    ]

    # 周一到周四每天 8 节课，周五 7 节课
    weekly_plan: list[list[str]] = [
        ["数学", "语文", "英语", "科学", "历史", "地理", "信息技术", "体育"],
        ["英语", "数学", "科学", "语文", "地理", "历史", "音乐", "数学"],
        ["语文", "数学", "英语", "科学", "信息技术", "历史", "体育", "英语"],
        ["数学", "英语", "语文", "科学", "历史", "地理", "音乐", "科学"],
        ["英语", "语文", "数学", "科学", "地理", "体育", "历史"],
    ]

    today_start = now_bj.replace(hour=0, minute=0, second=0, microsecond=0)
    monday = today_start - timedelta(days=today_start.weekday())

    entries: list[dict[str, Any]] = []
    entry_id = 10001
    for week_offset in (0, 1):
        for weekday_idx, day_subjects in enumerate(weekly_plan):
            day_dt = monday + timedelta(days=week_offset * 7 + weekday_idx)
            for period_idx, subj_name in enumerate(day_subjects):
                (sh, sm), (eh, em) = periods[period_idx]
                begin_dt = day_dt.replace(hour=sh, minute=sm)
                end_dt = day_dt.replace(hour=eh, minute=em)
                room, teacher = subject_info[subj_name]
                entries.append(
                    {
                        "id": entry_id,
                        "name": subj_name,
                        "begin": fmt_school_dt(begin_dt),
                        "end": fmt_school_dt(end_dt),
                        "room": room,
                        "teachers": [teacher],
                        "isAllDay": False,
                        "type": 3,
                    }
                )
                entry_id += 1
    return entries


def build_attendance(now_bj: datetime) -> dict[str, Any]:
    """生成本学期考勤统计（AttendanceSummary）。"""
    rows = [
        {"id": 101, "name": "数学", "normal": 35, "late": 0, "earlyLeave": 0, "absent": 0},
        {"id": 102, "name": "语文", "normal": 34, "late": 1, "earlyLeave": 0, "absent": 0},
        {"id": 103, "name": "英语", "normal": 35, "late": 0, "earlyLeave": 0, "absent": 0},
        {"id": 104, "name": "科学", "normal": 28, "late": 0, "earlyLeave": 0, "absent": 0},
        {"id": 105, "name": "历史", "normal": 21, "late": 0, "earlyLeave": 0, "absent": 0},
        {"id": 106, "name": "地理", "normal": 20, "late": 0, "earlyLeave": 0, "absent": 0},
        {"id": 107, "name": "信息技术", "normal": 14, "late": 0, "earlyLeave": 0, "absent": 0},
        {"id": 108, "name": "音乐", "normal": 14, "late": 0, "earlyLeave": 0, "absent": 0},
        {"id": 109, "name": "体育", "normal": 21, "late": 0, "earlyLeave": 0, "absent": 0},
    ]
    normal = sum(r["normal"] for r in rows)
    late = sum(r["late"] for r in rows)
    early_leave = sum(r["earlyLeave"] for r in rows)
    absent = sum(r["absent"] for r in rows)
    total = normal + late + early_leave + absent
    rate = round(normal / total * 100.0, 2)

    start_date = (now_bj - timedelta(days=60)).strftime("%Y-%m-%d")
    end_date = now_bj.strftime("%Y-%m-%d")
    return {
        "rate": rate,
        "total": total,
        "normal": normal,
        "late": late,
        "earlyLeave": early_leave,
        "absent": absent,
        "subjects": rows,
        "range": f"{start_date} ~ {end_date}",
    }


def next_school_day_first_class(schedule: list[dict[str, Any]], now_bj: datetime) -> tuple[str, str, str]:
    """根据运行当天计算明天或下一个上学日的首堂课标题、时间和详情。"""
    tomorrow_date = (now_bj + timedelta(days=1)).date()
    weekday_names = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    by_date: dict[Any, list[dict[str, Any]]] = {}
    for entry in schedule:
        dt = datetime.strptime(entry["begin"][:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=BEIJING_TZ)
        by_date.setdefault(dt.date(), []).append(entry)

    if tomorrow_date in by_date:
        first = sorted(by_date[tomorrow_date], key=lambda e: e["begin"])[0]
        return "明日首堂课", first["begin"][11:16], f"{first['name']}（{first['room']}）"

    future_dates = sorted(d for d in by_date if d > now_bj.date())
    if future_dates:
        next_d = future_dates[0]
        first = sorted(by_date[next_d], key=lambda e: e["begin"])[0]
        wname = weekday_names[next_d.weekday()]
        return f"{wname}首堂课", first["begin"][11:16], f"{first['name']}（{first['room']}）"

    return "明日首堂课", "08:30", "数学（A101）"


def build_ai_advice(synced_at_iso: str, schedule: list[dict[str, Any]], now_bj: datetime) -> dict[str, Any]:
    """生成能被 AIAdvice 与 AISummary 解码的 ai-advice.json 数据。"""
    sched_title, sched_time, sched_detail = next_school_day_first_class(schedule, now_bj)

    structured = {
        "headline": "今晚先搞定两项今日截止作业，冲刺 4.0 很稳！",
        "blocks": [
            {
                "type": "todo",
                "title": "今日必做",
                "items": [
                    {
                        "action": "完成凸透镜实验探究单",
                        "task": "提交实验探究单：凸透镜成像规律",
                        "subject": "科学",
                        "due": "今天 23:50",
                        "why": "满分这科 +5.2，升到 A",
                    },
                    {
                        "action": "做完第 4 章函数练习卷",
                        "task": "第 4 章函数综合练习卷",
                        "subject": "数学",
                        "due": "今天 23:59",
                        "why": "满分这科 +1.9，升到 A",
                    },
                    {
                        "action": "复习第 2 单元英语词汇",
                        "task": "Unit 2 Vocabulary Quiz",
                        "subject": "英语",
                        "due": "明天 10:20",
                        "why": "课上小测，满分保住 A",
                    },
                ],
            },
            {
                "type": "boost",
                "title": "提分捷径",
                "action": "历史：补交「历史材料分析：商鞅变法」拿满分",
                "result": "GPA 3.87 → 4.02",
            },
            {
                "type": "schedule",
                "title": sched_title,
                "time": sched_time,
                "detail": sched_detail,
            },
            {
                "type": "tip",
                "title": "贴士",
                "detail": "历史有一项记为未完成的作业，找刘老师问问能否补交，一举跨上 4.0。",
            },
        ],
    }

    return {
        "text": json.dumps(structured, ensure_ascii=False, indent=2),
        "createdAt": synced_at_iso,
        "model": "demo",
        "target": 4.0,
        "provider": "演示数据",
        "basedOn": synced_at_iso,
        "structured": structured,
    }


def build_settings() -> dict[str, Any]:
    """生成能被 AppSettings 解码的 settings.json 数据。"""
    return {
        "schoolURL": "https://demo.schoolis.cn",
        "schoolAccount": "demo",
        "nickname": "同学",
        "autoSync": False,
        "syncTimes": [
            {"hour": 7, "minute": 0},
            {"hour": 18, "minute": 30},
        ],
        "urgentStyle": "popup",
        "summaryStyle": "system",
        "targetGPA": 4.0,
    }


def write_json(path: Path, payload: Any) -> None:
    text = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    path.write_text(text, encoding="utf-8")


def main() -> None:
    if len(sys.argv) != 2:
        print(f"用法: python3 {sys.argv[0]} <输出文件夹>", file=sys.stderr)
        sys.exit(1)

    out_dir = Path(sys.argv[1]).expanduser().resolve()
    os.makedirs(out_dir, mode=0o700, exist_ok=True)

    now_bj = datetime.now(BEIJING_TZ)
    # 今天 07:05（北京时间）作为快照同步时间
    synced_at_bj = now_bj.replace(hour=7, minute=5, second=0, microsecond=0)
    synced_at_iso = fmt_iso8601_utc(synced_at_bj)

    tasks, grades, task_items = build_tasks_and_grades(now_bj)
    gpa = compute_official_gpa(grades)
    schedule = build_schedule(now_bj)
    attendance = build_attendance(now_bj)

    snapshot = {
        "syncedAt": synced_at_iso,
        "semesterName": build_semester_name(now_bj),
        "gpa": gpa,
        "tasks": tasks,
        "unreadableTasks": 0,
        "grades": grades,
        "schedule": schedule,
        "attendance": attendance,
        "taskItems": task_items,
    }
    settings = build_settings()
    ai_advice = build_ai_advice(synced_at_iso, schedule, now_bj)

    snapshot_path = out_dir / "snapshot.json"
    settings_path = out_dir / "settings.json"
    ai_advice_path = out_dir / "ai-advice.json"

    write_json(snapshot_path, snapshot)
    write_json(settings_path, settings)
    write_json(ai_advice_path, ai_advice)

    blocks = ai_advice["structured"]["blocks"]
    todo_items = next((b.get("items", []) for b in blocks if b.get("type") == "todo"), [])

    print(f"已生成演示数据文件夹：{out_dir}")
    print(
        f"- {snapshot_path.name}: 作业 {len(tasks)} 条，科目 {len(grades['subjects'])} 科（GPA {gpa:.2f}），"
        f"分数段 {len(grades['bands'])} 档，课表 {len(schedule)} 节，"
        f"考勤科目 {len(attendance['subjects'])} 科，作业归属映射 {len(task_items)} 条"
    )
    print(f"- {settings_path.name}: 设置项 {len(settings)} 条（autoSync={settings['autoSync']}, targetGPA={settings['targetGPA']}）")
    print(f"- {ai_advice_path.name}: AI 总结卡片 {len(blocks)} 块（其中 todo 清单 {len(todo_items)} 条）")


if __name__ == "__main__":
    main()
