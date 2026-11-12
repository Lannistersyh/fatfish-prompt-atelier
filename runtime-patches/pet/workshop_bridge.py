# -*- coding: utf-8 -*-
"""与「大肥鱼提示词工坊」面板的进程间桥（仅 2合1 打包时启用）。

工作方式：工坊 App 在启动桌宠子进程时设置 ``DAFEIYU_WORKSHOP_NOTIFY=1``；
桌宠被点击时向 macOS 分布式通知中心投递 ``ai.local.fatfish.togglePanel``，
工坊侧（AppDelegate）已注册该通知的观察者，收到后开关面板。
（``showPanel`` 只用于第二次启动的单实例转交：把面板叫到前台，不改变开关状态。）

独立运行 1080P 桌宠（没有工坊进程）时该通知无人接收，静默忽略。
"""
from __future__ import annotations

import ctypes
import ctypes.util
import os

ENV_FLAG = "DAFEIYU_WORKSHOP_NOTIFY"
NOTIFICATION = b"ai.local.fatfish.togglePanel"

_UTF8 = 0x08000100  # kCFStringEncodingUTF8


def enabled() -> bool:
    return os.environ.get(ENV_FLAG) == "1"


def notify_toggle_panel() -> bool:
    """投递一次“开关面板”通知；未启用或平台不支持时返回 False。"""
    if not enabled():
        return False
    try:
        cf = ctypes.CDLL(ctypes.util.find_library("CoreFoundation"))
    except Exception:
        return False
    try:
        cf.CFStringCreateWithCString.restype = ctypes.c_void_p
        cf.CFStringCreateWithCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint32]
        cf.CFNotificationCenterGetDistributedCenter.restype = ctypes.c_void_p
        cf.CFNotificationCenterPostNotification.argtypes = [
            ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_bool,
        ]
        cf.CFRelease.argtypes = [ctypes.c_void_p]
        name = cf.CFStringCreateWithCString(None, NOTIFICATION, _UTF8)
        if not name:
            return False
        center = cf.CFNotificationCenterGetDistributedCenter()
        cf.CFNotificationCenterPostNotification(center, name, None, None, True)
        cf.CFRelease(name)
        return True
    except Exception:
        return False
