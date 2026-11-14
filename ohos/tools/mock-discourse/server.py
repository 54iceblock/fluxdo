#!/usr/bin/env python3
"""FluxDO 真机 mock 测试用的最小 Discourse 服务。

用途：把应用 baseUrl 指向本机（真机通过 `hdc rport` 端口转发），
       让「未登录 → 登录 → 已登录 UI / 发帖」链路可以在没有真实账号的情况下验证。

关键设计：
- 所有响应都带 `Set-Cookie: _t=mocktoken; cf_clearance=mockcf`，
  应用拿到 cookie 后会认为已登录，从而跳过登录页直接进入登录态。
- 返回结构与 Discourse API 对齐（topic_list / post_stream / current_user 等），
  应用侧解析代码无需改动。
- 每个请求都打印到 stdout，便于在 PC 侧确认应用真的打到了 mock。

启动：python tools/mock-discourse/server.py [--port 8080] [--auto-alert 30]

真机专项用例（审查报告 §7.2 / §7.3）：
- 话题 1004：首楼 EXIF 方向（/mock/exif-{0,1,3,6,8}.jpg），二楼大图
  （/mock/big-{4000x3000,8192x8192}.{jpg,avif}）。图片用 Pillow 现场生成并缓存到
  系统临时目录；8192² 首次生成较慢，装机前先预热：
    for f in exif-0.jpg exif-1.jpg exif-3.jpg exif-6.jpg exif-8.jpg \\
             big-4000x3000.jpg big-4000x3000.avif big-8192x8192.jpg big-8192x8192.avif; do
      curl -s -o /dev/null -w "%{http_code} $f\\n" http://127.0.0.1:8080/mock/$f; done
- 本地通知：MessageBus 长轮询 /message-bus/<id>/poll，PC 侧触发：
    curl "http://127.0.0.1:8080/mock/trigger-alert?topic_id=1001&post_number=2&type=2"
"""

import argparse
import io
import json
import sys
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

# 仓库根（本文件在 <repo>/ohos/tools/mock-discourse/ 下）
_ROOT = Path(__file__).resolve().parents[3]

MOCK_USER = {
    "id": 4242,
    "username": "mockuser",
    "name": "Mock 测试用户",
    "avatar_template": "/mock/avatar/{size}.png",
    "trust_level": 3,
    "admin": False,
    "moderator": False,
    "title": "Mock 测试",
    "bio_raw": "这是 mock 用户",
    "bio_excerpt": "这是 mock 用户",
    "created_at": "2025-01-01T00:00:00.000Z",
    "last_seen_at": "2026-10-23T00:00:00.000Z",
    "notification_count": 2,
    "unread_notifications": 2,
    "unread_high_priority_notifications": 0,
    "unread_pm_count": 0,
    "can_send_private_message_to_user": True,
    "primary_group_name": "成员",
    "groups": [{"id": 1, "name": "成员"}],
    "badges": [],
    "featured_user_badge_ids": [],
    "post_count": 12,
    "topic_count": 3,
    "likes_given": 8,
    "likes_received": 20,
    "time_read": 3600,
    "days_visited": 5,
    "email": "mock@example.com",
    "secondary_emails": [],
    "associated_accounts": [],
}

CATEGORIES = [
    {"id": 1, "name": "搞七捻三", "slug": "chat", "color": "0088CC", "text_color": "FFFFFF",
     "topic_count": 12, "post_count": 30, "description": "闲聊",
     "description_text": "闲聊", "permission": 1, "read_restricted": False,
     "parent_category_id": None, "notification_level": 1, "can_create_topic": True,
     "minimum_required_tags": 0, "allowed_tags": [], "allowed_tag_groups": [],
     "allow_global_tags": True, "required_tag_groups": [], "topic_template": None},
    {"id": 2, "name": "开发调优", "slug": "dev", "color": "25AAE2", "text_color": "FFFFFF",
     "topic_count": 8, "post_count": 20, "description": "开发",
     "description_text": "开发", "permission": 1, "read_restricted": False,
     "parent_category_id": None, "notification_level": 1, "can_create_topic": True,
     "minimum_required_tags": 0, "allowed_tags": [], "allowed_tag_groups": [],
     "allow_global_tags": True, "required_tag_groups": [], "topic_template": None},
    {"id": 3, "name": "福利羊毛", "slug": "deals", "color": "F7941D", "text_color": "FFFFFF",
     "topic_count": 5, "post_count": 12, "description": "羊毛",
     "description_text": "羊毛", "permission": 1, "read_restricted": False,
     "parent_category_id": None, "notification_level": 1, "can_create_topic": True,
     "minimum_required_tags": 0, "allowed_tags": [], "allowed_tag_groups": [],
     "allow_global_tags": True, "required_tag_groups": [], "topic_template": None},
]


# 偏好设置（/u/<username>/preferences/*）用的用户选项与资料字段。
# 与 Discourse UserUpdater::OPTION_ATTR 同名扁平键，便于验证读写链路。
MOCK_PREFERENCES = {
    "location": "Mock 城市",
    "website": "https://example.com",
    "user_fields": {"1": "mock 字段值"},
    "user_option": {
        "email_digests": True,
        "email_level": 1,
        "email_messages_level": 1,
        "mailing_list_mode": False,
        "email_in_reply_to": True,
        "allow_private_messages": True,
        "hide_presence": False,
        "hide_profile": False,
        "auto_track_topics_after_msecs": 300000,
        "notification_level_when_replying": 2,
        "like_notification_frequency": 2,
        "notify_on_linked_posts": True,
        "watched_precedence_over_muted": False,
        "text_size": 0,
        "enable_quoting": True,
        "enable_smart_lists": True,
        "external_links_in_new_tab": False,
        "automatically_unpin_topics": True,
    },
}


def make_topic(tid: int, title: str, posts: int = 5, cat: int = 1) -> dict:
    t0 = "2026-10-23T00:00:00.000Z"
    return {
        "id": tid,
        "title": title,
        "fancy_title": title,
        "slug": f"mock-topic-{tid}",
        "posts_count": posts,
        "reply_count": max(posts - 1, 0),
        "highest_post_number": posts,
        "created_at": t0,
        "last_posted_at": t0,
        "bumped_at": t0,
        "archetype": "regular",
        "unseen": False,
        "pinned": False,
        "unpinned": None,
        "excerpt": f"{title} 的摘要（mock 数据，用于真机联调）",
        "visible": True,
        "closed": False,
        "archived": False,
        "bookmarked": None,
        "liked": False,
        "tags": ["mock", "测试"],
        "category_id": cat,
        "views": 100 + tid,
        "like_count": 7,
        "has_summary": False,
        "posters": [
            {"extras": "latest", "description": MOCK_USER["name"],
             "user_id": MOCK_USER["id"], "primary_group_id": 1},
        ],
        "last_poster": {"id": MOCK_USER["id"], "username": MOCK_USER["username"],
                        "name": MOCK_USER["name"],
                        "avatar_template": MOCK_USER["avatar_template"]},
        "participant_count": 1,
        "word_count": 40,
        "pinned_globally": False,
        "image_url": None,
        "thumbnails": None,
    }


TOPICS = [
    make_topic(1001, "【Mock】HarmonyOS 真机测试帖 1", 12, 1),
    make_topic(1002, "【Mock】登录后功能验证帖 2", 8, 2),
    make_topic(1003, "【Mock】发帖/回复链路验证帖 3", 3, 3),
    make_topic(1004, "【Mock】图片方向（EXIF）与大图性能验证帖 4", 2, 2),
]

# 话题 1004 的测试 ID（审查报告 §7.3-3 图片方向、§7.2 大图降采样 / T10）
IMAGE_TOPIC_ID = 1004


def make_post(post_number: int, topic_id: int, cooked: str | None = None) -> dict:
    return {
        "id": 8000 + post_number,
        "username": MOCK_USER["username"],
        "name": MOCK_USER["name"],
        "avatar_template": MOCK_USER["avatar_template"],
        "created_at": "2026-10-23T00:00:00.000Z",
        "cooked": cooked or f"<p>【Mock】这是第 {post_number} 楼，用于真机联调。</p>",
        "raw": f"【Mock】这是第 {post_number} 楼，用于真机联调。",
        "post_number": post_number,
        "post_type": 1,
        "updated_at": "2026-10-23T00:00:00.000Z",
        "reply_count": 0,
        "cooked_hidden": False,
        "hidden": False,
        "quote_count": 0,
        "deleted_at": None,
        "user_id": MOCK_USER["id"],
        "topic_id": topic_id,
        "yours": True,
        "can_edit": True,
        "can_delete": True,
        "can_recover": False,
        "can_wiki": True,
        "reads": 1,
        "score": 1.0,
        "bookmarked": False,
        "bookmarks": [],
        "actions_summary": [{"id": 2, "count": 1, "hidden": False, "can_act": True}],
        "moderator": False,
        "admin": False,
        "staff": False,
        "user_title": MOCK_USER["title"],
        "trust_level": MOCK_USER["trust_level"],
        "reactions": [],
        "current_user_reaction": None,
        "reaction_users_count": 0,
    }


# ---------------------------------------------------------------------------
# 测试图片（审查报告 §7.3-3 EXIF 方向、§7.2 / T10 大图降采样）
#
# 运行时用 Pillow 生成并缓存（内存 + 系统临时目录），不往仓库放大文件。
# 没装 Pillow 时这些路由返回 501，其余 mock 功能不受影响：
#   python -m pip install Pillow     # AVIF 需 Pillow >= 11.3
# ---------------------------------------------------------------------------

# EXIF Orientation 取值 → 说明。0 表示「不写 EXIF」（验证 orientation:401 是否只在
# 无 EXIF 时出现）。存储像素已做逆变换：查看器正确应用 EXIF 后，应看到
# 「红条在上、文字正立」；方向处理错误时红条会出现在下/左/右侧。
EXIF_CASES = {
    0: "无 EXIF",
    1: "Orientation=1（正常）",
    3: "Orientation=3（旋转 180°）",
    6: "Orientation=6（需顺时针 90°）",
    8: "Orientation=8（需逆时针 90°）",
}

# 大图：(宽, 高)。按扩展名决定格式（.jpg / .avif）。
LARGE_IMAGES = {
    "4000x3000": (4000, 3000),
    "8192x8192": (8192, 8192),
}

_IMAGE_CACHE: dict = {}
_IMAGE_LOCK = threading.Lock()
_IMAGE_DISK_CACHE = Path(__import__("tempfile").gettempdir()) / "fluxdo-mock-images"


def _require_pillow():
    try:
        from PIL import Image, ImageDraw  # noqa: F401
        return True
    except ImportError:
        return False


def _draw_upright(w: int, h: int, label: str):
    """画一张「方向一眼可辨」的图：顶部红条 + 左上角绿块 + 中央文字。"""
    from PIL import Image, ImageDraw, ImageFont

    img = Image.new("RGB", (w, h), (235, 235, 235))
    d = ImageDraw.Draw(img)
    bar = max(h // 8, 8)
    d.rectangle([0, 0, w, bar], fill=(220, 40, 40))           # 顶部红条
    d.rectangle([0, 0, w // 6, bar * 2], fill=(40, 170, 60))  # 左上绿块
    step = max(min(w, h) // 16, 16)
    for x in range(0, w, step):
        d.line([(x, bar), (x, h)], fill=(200, 200, 200), width=max(step // 64, 1))
    for y in range(bar, h, step):
        d.line([(0, y), (w, y)], fill=(200, 200, 200), width=max(step // 64, 1))
    try:
        font = ImageFont.load_default(size=max(min(w, h) // 12, 12))
    except TypeError:  # Pillow < 10.1 不支持 size
        font = ImageFont.load_default()
    d.text((w // 10, h // 2), f"TOP {label}", fill=(20, 20, 20), font=font)
    return img


def _encode(img, fmt: str, exif_orientation: int = 0) -> bytes:
    from PIL import Image

    buf = io.BytesIO()
    if fmt == "jpg":
        kwargs = {"quality": 85}
        if exif_orientation:
            exif = Image.Exif()
            exif[0x0112] = exif_orientation  # Orientation
            kwargs["exif"] = exif.tobytes()
        img.save(buf, "JPEG", **kwargs)
    elif fmt == "avif":
        img.save(buf, "AVIF", quality=60, speed=10)
    else:
        raise ValueError(fmt)
    return buf.getvalue()


def make_exif_image(orientation: int) -> bytes:
    """生成 EXIF 方向用例：像素按方向做逆变换，正确显示时应正立。"""
    from PIL import Image

    upright = _draw_upright(800, 600, f"EXIF {orientation}")
    # exif_transpose 对 3/6/8 分别做 ROTATE_180 / ROTATE_270 / ROTATE_90，
    # 存储像素取其逆：3→ROTATE_180，6→ROTATE_90，8→ROTATE_270。
    inverse = {
        3: Image.Transpose.ROTATE_180,
        6: Image.Transpose.ROTATE_90,
        8: Image.Transpose.ROTATE_270,
    }.get(orientation)
    stored = upright.transpose(inverse) if inverse is not None else upright
    return _encode(stored, "jpg", exif_orientation=orientation)


def make_large_image(key: str, fmt: str) -> bytes:
    w, h = LARGE_IMAGES[key]
    return _encode(_draw_upright(w, h, f"{key} {fmt}"), fmt)


def cached_image(name: str, factory) -> bytes:
    """内存 + 临时目录两级缓存（8192² AVIF 编码可能要十几秒）。"""
    with _IMAGE_LOCK:
        if name in _IMAGE_CACHE:
            return _IMAGE_CACHE[name]
        disk = _IMAGE_DISK_CACHE / name
        if disk.exists():
            data = disk.read_bytes()
        else:
            t0 = time.time()
            data = factory()
            _IMAGE_DISK_CACHE.mkdir(parents=True, exist_ok=True)
            disk.write_bytes(data)
            sys.stdout.write(f"[mock] 生成 {name}: {len(data)} B, {time.time() - t0:.1f}s\n")
            sys.stdout.flush()
        _IMAGE_CACHE[name] = data
        return data


def image_topic_cooked_exif() -> str:
    items = "".join(
        f'<p>{desc}：</p><p><img src="/mock/exif-{o}.jpg" alt="exif-{o}" '
        f'width="400" height="300"></p>'
        for o, desc in EXIF_CASES.items()
    )
    return (
        "<p>【Mock】EXIF 方向验证（审查报告 §7.3-3）。</p>"
        "<p>判定：每张图都应「红条在上、绿块在左上、文字正立」。"
        "依次检查：正文显示 → 大图查看器 → 保存到相册后在图库打开。</p>"
        + items
    )


def image_topic_cooked_large() -> str:
    items = "".join(
        f'<p>{key} {fmt.upper()}：</p><p><img src="/mock/big-{key}.{fmt}" '
        f'alt="big-{key}-{fmt}" width="{w}" height="{h}"></p>'
        for key, (w, h) in LARGE_IMAGES.items()
        for fmt in ("jpg", "avif")
    )
    return (
        "<p>【Mock】大图降采样性能验证（T10）。</p>"
        "<p>记录：首屏出图耗时、打开大图查看器耗时、PSS 峰值与退出后回落"
        "（hidumper --mem &lt;pid&gt;）。首次请求时服务端现场生成，可能较慢，"
        "先用 curl 预热：见 server.py 顶部说明。</p>"
        + items
    )


# ---------------------------------------------------------------------------
# MessageBus 长轮询（审查报告 §7.2 本地通知）
#
# 应用订阅 /notification-alert/{userId}，收到后调 LocalNotificationService.show()。
# 从 PC 侧触发一条提醒：
#   curl "http://127.0.0.1:8080/mock/trigger-alert?topic_id=1001&post_number=2&type=2"
#   type: 1=提及 2=回复 6=私信（private_message 走 message: payload）
# 或启动时加 --auto-alert 30 每 30 秒自动推一条。
# ---------------------------------------------------------------------------

ALERT_CHANNEL = f"/notification-alert/{MOCK_USER['id']}"
_BUS_COND = threading.Condition()
_BUS_MESSAGES: list = []  # [{"channel", "message_id", "data"}]
LONG_POLL_SECONDS = 25


def bus_last_id(channel: str) -> int:
    # 空频道记 0（而非 -1）：客户端拿到 /__status=0 后不再是「首次订阅」，
    # 之后的消息 id 从 1 开始，`> last` 判断才成立。
    ids = [m["message_id"] for m in _BUS_MESSAGES if m["channel"] == channel]
    return max(ids) if ids else 0


def bus_publish_alert(topic_id: int = 1001, post_number: int = 2, ntype: int = 2,
                      excerpt: str = "") -> dict:
    t = next((x for x in TOPICS if x["id"] == topic_id), TOPICS[0])
    with _BUS_COND:
        msg = {
            "channel": ALERT_CHANNEL,
            "message_id": bus_last_id(ALERT_CHANNEL) + 1,
            "data": {
                "notification_type": ntype,
                "post_number": post_number,
                "topic_title": t["title"],
                "topic_id": t["id"],
                "excerpt": excerpt or f"【Mock】本地通知测试 {datetime.now(timezone.utc):%H:%M:%S}",
                "username": "mock_sender",
                "post_url": f"/t/{t['slug']}/{t['id']}/{post_number}",
            },
        }
        _BUS_MESSAGES.append(msg)
        _BUS_COND.notify_all()
    sys.stdout.write(f"[mock] 推送提醒 #{msg['message_id']} -> {ALERT_CHANNEL}\n")
    sys.stdout.flush()
    return msg


def bus_collect(subs: dict) -> list:
    """按客户端 {channel: last_id} 计算要回的消息（需持有 _BUS_COND）。"""
    out = []
    status = {}
    for ch, last in subs.items():
        current = bus_last_id(ch)
        if last < 0:
            # 首次订阅：只告诉客户端当前位置，不回放历史（与 Discourse 一致）
            status[ch] = current
            continue
        out.extend(m for m in _BUS_MESSAGES
                   if m["channel"] == ch and m["message_id"] > last)
    if status:
        out.insert(0, {"channel": "/__status", "message_id": -1, "data": status})
    return out


def topic_detail(tid: int) -> dict:
    t = next((x for x in TOPICS if x["id"] == tid), TOPICS[0])
    posts = [make_post(i, t["id"]) for i in range(1, min(t["posts_count"], 6) + 1)]
    if posts and t["id"] == IMAGE_TOPIC_ID:
        posts[0]["cooked"] = image_topic_cooked_exif()
        if len(posts) > 1:
            posts[1]["cooked"] = image_topic_cooked_large()
    # 首帖插一张 AVIF：用于验证 OHOS 上的 AVIF 解码链路
    # （自研 libavif + dav1d + 后台 isolate + maxDim 降采样）。
    elif posts:
        posts[0]["cooked"] = (
            "<p>【Mock】AVIF 解码验证：下面这张图是 AVIF 格式。</p>"
            '<p><img src="/mock/avif.avif" alt="avif" width="600"></p>'
            "<p>如果能看到图片，说明解码与渲染链路正常。</p>"
            "<p>链接用例：</p>"
            "<ul>"
            '<li><a href="https://example.com/">外部 https 链接</a>'
            "（实测：弹「即将离开」确认框 → 继续访问 → 系统浏览器打开 example.com）</li>"
            '<li><a href="mailto:test@example.com">mailto 链接</a>'
            "（实测：正文渲染层不生成可点 span，点它无响应）</li>"
            '<li><a href="javascript:alert(1)">javascript 链接</a>'
            "（实测：同上不响应；白名单拦截另有单测覆盖）</li>"
            '<li><a href="flutterdev://demo/path">自定义 scheme 链接</a>'
            "（实测：同上不响应）</li>"
            "</ul>"
            "<p>结论：正文里只有 http(s) 链接可点；其它 scheme 是纯文本，"
            "不会触发外部打开（安全默认），ArkTS 桥的白名单是第二道防线。</p>"
        )
    t = dict(t)
    t["post_stream"] = {
        "posts": posts,
        "stream": list(range(1, t["posts_count"] + 1)),
    }
    t["details"] = {
        "can_edit": True,
        "created_by": {"id": MOCK_USER["id"], "username": MOCK_USER["username"],
                       "name": MOCK_USER["name"],
                       "avatar_template": MOCK_USER["avatar_template"]},
        "participants": [{"id": MOCK_USER["id"], "username": MOCK_USER["username"],
                          "name": MOCK_USER["name"],
                          "avatar_template": MOCK_USER["avatar_template"],
                          "post_count": t["posts_count"]}],
        "notification_level": 1,
        "can_create_post": True,
    }
    return t


def make_home_html() -> bytes:
    """构造带 data-preloaded 的首页 HTML。

    Discourse 首页把首屏数据以「外层 JSON + 内层 JSON 字符串」的形式嵌在
    `<script type="application/json" id="data-preloaded">` 中，应用
    `preloaded_data_service` 正是按这个结构解析（currentUser/siteSettings/site
    会被再解码一次）。这里保持一致，应用即可跳过登录直接进入已登录态。
    """
    inner = {
        "currentUser": MOCK_USER,
        "siteSettings": {
            "title": "Mock Discourse",
            "discourse_reactions_enabled_reactions": "heart|+1|tada",
            "long_polling_base_url": "/",
            "enable_badges": True,
            "min_post_length": 1,
            "min_topic_title_length": 2,
            "max_topic_title_length": 255,
            "allow_uncategorized_topics": True,
        },
        "site": {
            "default_archetype": "regular",
            "categories": CATEGORIES,
            "top_tags": ["mock", "测试"],
            "can_create_tag": True,
            "can_tag_topics": True,
        },
        "topicTrackingStateMeta": {"messageBusLastId": 1},
        "topicTrackingStates": [],
        "customEmoji": [],
        "topic_list": {
            "can_create_topic": True,
            "per_page": 30,
            "topics": TOPICS,
        },
        "users": [{"id": MOCK_USER["id"], "username": MOCK_USER["username"],
                   "name": MOCK_USER["name"],
                   "avatar_template": MOCK_USER["avatar_template"]}],
    }
    # 外层每个 value 再 json.dumps 成字符串，还原 Discourse 的「双层 JSON」
    outer = {k: json.dumps(v, ensure_ascii=False) for k, v in inner.items()}
    payload = json.dumps(outer, ensure_ascii=False)
    html = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>Mock Discourse</title>
<meta name="csrf-token" content="mockcsrftoken">
<meta name="discourse-base-uri" content="">
<meta name="shared_session_key" content="mock-session-key">
</head>
<body>
<h1>Mock Discourse</h1>
<p>用于 FluxDO 真机联调，当前用户：{MOCK_USER['username']}</p>
<script type="application/json" id="data-preloaded">{payload}</script>
</body>
</html>"""
    return html.encode("utf-8")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # noqa: D401
        sys.stdout.write("[mock] %s - %s\n" % (self.address_string(), fmt % args))
        sys.stdout.flush()

    # ---------- helpers ----------

    def _cookies(self) -> str:
        return ("_t=mocktoken; Path=/; Max-Age=86400, "
                "cf_clearance=mockcf; Path=/; Max-Age=86400")

    def _send(self, obj, status: int = 200, content_type: str = "application/json"):
        body = obj if isinstance(obj, bytes) else json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Set-Cookie", self._cookies())
        self.send_header("X-Mock", "fluxdo")
        self.end_headers()
        self.wfile.write(body)

    def _read_form(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length).decode("utf-8", "replace") if length else ""
        out = {}
        for pair in raw.split("&"):
            if "=" in pair:
                k, v = pair.split("=", 1)
                out[k] = v
        return out

    # ---------- routing ----------

    def do_GET(self):  # noqa: N802
        u = urlparse(self.path)
        path = u.path.rstrip("/") or "/"
        q = parse_qs(u.query)

        if path in ("/", "/index.html"):
            self._send(make_home_html(), content_type="text/html; charset=utf-8")
            return

        if path == "/session/csrf":
            self._send({"csrf": "mockcsrftoken"})
            return

        if path == "/session/current.json":
            self._send({"current_user": MOCK_USER})
            return

        if path in ("/latest.json", "/top.json", "/new.json", "/unread.json",
                    "/c/latest.json", "/latest", "/top"):
            self._send({
                "users": [{"id": MOCK_USER["id"], "username": MOCK_USER["username"],
                           "name": MOCK_USER["name"],
                           "avatar_template": MOCK_USER["avatar_template"]}],
                "primary_groups": [],
                "flair_groups": [],
                "topic_list": {
                    "can_create_topic": True,
                    "per_page": 30,
                    "topics": TOPICS,
                },
            })
            return

        if path == "/categories.json":
            self._send({"category_list": {"categories": CATEGORIES,
                                          "can_create_category": False,
                                          "can_create_topic": True}})
            return

        if path == "/site.json":
            self._send({"site": {
                "default_archetype": "regular",
                "notification_types": {},
                "post_action_types": [],
                "topic_flag_types": [],
                "categories": CATEGORIES,
                "filters": [],
                "top_tags": ["mock", "测试"],
                "can_create_tag": True,
                "can_tag_topics": True,
            }})
            return

        if path.startswith("/t/") and path.endswith("/posts.json"):
            tid = _int_between(path, "/t/", "/posts.json")
            self._send(topic_detail(tid))
            return

        if path.startswith("/t/") and path.endswith(".json"):
            tid = _int_between(path, "/t/", ".json")
            self._send(topic_detail(tid))
            return

        if path in ("/notifications", "/notifications.json", "/u/mockuser/notifications.json", "/u/mockuser/notifications"):
            def _notif(nid: int, read: bool, ntype: int, title: str, fid: int) -> dict:
                return {
                    "id": nid,
                    "user_id": MOCK_USER["id"],
                    "notification_type": ntype,
                    "read": read,
                    "high_priority": False,
                    "created_at": "2026-10-23T00:00:00.000Z",
                    "post_number": 2,
                    "topic_id": fid,
                    "slug": f"mock-topic-{fid}",
                    "fancy_title": title,
                    "data": {
                        "topic_title": title,
                        "slug": f"mock-topic-{fid}",
                        "original_post_id": 8001,
                        "original_username": MOCK_USER["username"],
                        "display_username": MOCK_USER["username"],
                        "original_post_number": 1,
                        "count": 1,
                    },
                    "acting_user_avatar_template": MOCK_USER["avatar_template"],
                    "name": MOCK_USER["name"],
                    "group_id": None,
                }

            self._send({
                "notifications": [
                    _notif(1, False, 1, "【Mock】有人在话题里提到了你", 1001),
                    _notif(2, False, 2, "【Mock】有人回复了你的帖子", 1002),
                    _notif(3, True, 5, "【Mock】有人给你点了赞", 1003),
                ],
                "total_rows_notifications": 3,
                "seen_notification_id": 3,
                "load_more_notifications": "/notifications?offset=60",
            })
            return

        # 偏好设置：电子邮件子页（邮箱 + 关联账号）
        # 必须排在通用 `/u/<username>.json` 之前，否则会被当成 username 的一部分。
        if path.startswith("/u/") and path.endswith("/preferences/email.json"):
            self._send({
                "email": "mockuser@example.com",
                "secondary_emails": [],
                "unconfirmed_emails": [],
                "associated_accounts": [
                    {"provider_name": "github", "provider_uid": "mockuser"},
                ],
            })
            return

        # 偏好设置：站点自定义字段
        if path == "/user_fields.json":
            self._send({"user_fields": [{
                "id": 1,
                "name": "Mock 自定义字段",
                "description": "用于验证自定义字段读写",
                "field_type": "text",
                "required": False,
                "editable": True,
            }]})
            return

        if path.startswith("/u/") and path.endswith(".json"):
            username = path[len("/u/"):-len(".json")]
            self._send({"user": dict(MOCK_USER, username=username or MOCK_USER["username"],
                                     can_edit=True, can_change_username=False,
                                     **MOCK_PREFERENCES)})
            return

        if path == "/presence/get":
            self._send({"users": []})
            return

        if path.startswith("/u/recent-searches"):
            self._send({"recent_searches": []})
            return

        if path.startswith("/mock/avatar"):
            # 1x1 透明 PNG
            import base64
            png = base64.b64decode(
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
            )
            self._send(png, content_type="image/png")
            return

        if path.startswith("/mock/exif-") and path.endswith(".jpg"):
            try:
                orientation = int(path[len("/mock/exif-"):-len(".jpg")])
            except ValueError:
                orientation = -1
            if orientation not in EXIF_CASES:
                self._send({}, status=404)
                return
            if not _require_pillow():
                self._send({"error": "需要 Pillow：python -m pip install Pillow"}, status=501)
                return
            data = cached_image(f"exif-{orientation}.jpg",
                                lambda: make_exif_image(orientation))
            self._send(data, content_type="image/jpeg")
            return

        if path.startswith("/mock/big-"):
            name = path[len("/mock/big-"):]
            key, _, fmt = name.rpartition(".")
            if key not in LARGE_IMAGES or fmt not in ("jpg", "avif"):
                self._send({}, status=404)
                return
            if not _require_pillow():
                self._send({"error": "需要 Pillow：python -m pip install Pillow"}, status=501)
                return
            try:
                data = cached_image(f"big-{key}.{fmt}", lambda: make_large_image(key, fmt))
            except Exception as e:  # 旧版 Pillow 无 AVIF 编码器
                self._send({"error": f"生成失败：{e}"}, status=501)
                return
            self._send(data, content_type="image/jpeg" if fmt == "jpg" else "image/avif")
            return

        if path == "/mock/trigger-alert":
            def _qi(name: str, default: int) -> int:
                try:
                    return int(q.get(name, [default])[0])
                except ValueError:
                    return default
            msg = bus_publish_alert(
                topic_id=_qi("topic_id", 1001),
                post_number=_qi("post_number", 2),
                ntype=_qi("type", 2),
                excerpt=q.get("excerpt", [""])[0],
            )
            self._send(msg)
            return

        if path.startswith("/mock/avif"):
            # AVIF 用例图：直接复用仓库里的探针样图 assets/probe/avif-probe.avif。
            # 用途：在 OHOS 上验证 AVIF 解码链路（自研 libavif + dav1d + 后台 isolate）。
            # 注意路径要带 `.avif` 后缀：应用按 URL 扩展名决定是否走 AVIF 解码器，
            # 裸 `/mock/avif` 会被当成未知格式（实测图片破损）。
            for cand in (
                _ROOT / "assets" / "probe" / "avif-probe.avif",
                _ROOT / "ohos" / "tools" / "mock-discourse" / "avif-probe.avif",
            ):
                if cand.exists():
                    self._send(cand.read_bytes(), content_type="image/avif")
                    return
            self._send({}, status=404)
            return

        # 其它一律 200 空对象，避免应用因未 mock 的接口崩溃
        self._send({})

    def do_POST(self):  # noqa: N802
        u = urlparse(self.path)
        path = u.path.rstrip("/") or "/"

        # MessageBus 长轮询：POST /message-bus/<clientId>/poll，表单为 {channel: last_id}
        # （键是 URL 编码的频道名，需 parse_qs 解码）。统一回 application/json，
        # 客户端据此走整体读取分支，不需要实现 chunked 分隔符。
        if path.startswith("/message-bus/") and path.endswith("/poll"):
            length = int(self.headers.get("Content-Length") or 0)
            raw = self.rfile.read(length).decode("utf-8", "replace") if length else ""
            subs = {}
            for k, v in parse_qs(raw).items():
                if k.startswith("__"):
                    continue
                try:
                    subs[k] = int(v[0])
                except (ValueError, IndexError):
                    pass
            with _BUS_COND:
                out = bus_collect(subs)
                if not out:
                    _BUS_COND.wait(LONG_POLL_SECONDS)
                    out = bus_collect(subs)
            self._send(out)
            return

        form = self._read_form()

        if path == "/session.json":
            login = form.get("login", "")
            password = form.get("password", "")
            self.log_message("login attempt login=%s password_len=%d", login, len(password))
            # 任意账号密码都成功（便于测试），空密码返回错误
            if not login or not password:
                self._send({"errors": ["请输入账号和密码"], "error": "账号或密码为空"})
                return
            self._send({"user": MOCK_USER})
            return

        if path == "/posts.json":
            topic_id = int(form.get("topic_id") or 1001)
            raw = form.get("raw") or ""
            self.log_message("create post topic=%s raw_len=%d", topic_id, len(raw))
            post = make_post(99, topic_id, cooked=f"<p>{raw or '【Mock】新回复'}</p>")
            self._send(post)
            return

        if path == "/topics.json":
            title = form.get("title") or "【Mock】新话题"
            raw = form.get("raw") or ""
            self.log_message("create topic title=%s raw_len=%d", title, len(raw))
            new_topic = make_topic(2001, title, 1, 1)
            new_topic["post_stream"] = {"posts": [make_post(1, 2001, f"<p>{raw}</p>")],
                                        "stream": [1]}
            self._send(new_topic)
            return

        if path == "/session/csrf":
            self._send({"csrf": "mockcsrftoken"})
            return

        self._send({})

    def do_DELETE(self):  # noqa: N802
        self._send({"success": "OK"})

    def do_PUT(self):  # noqa: N802
        u = urlparse(self.path)
        path = u.path.rstrip("/") or "/"
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length).decode("utf-8", "replace") if length else ""
        try:
            payload = json.loads(raw) if raw.strip() else {}
        except Exception:
            payload = {"_raw": raw}
        # 偏好保存：PUT /u/<username>.json，参数扁平（name/bio_raw/email_digests…）
        if path.startswith("/u/") and path.endswith(".json"):
            self.log_message("update preferences keys=%s", ",".join(sorted(payload.keys())))
            merged = {k: v for k, v in payload.items()
                      if k in ("name", "bio_raw", "location", "website")}
            self._send({"user": dict(MOCK_USER, **merged)})
            return
        self.log_message("put %s len=%d", path, len(raw))
        self._send({})


def _int_between(s: str, prefix: str, suffix: str) -> int:
    try:
        inner = s[len(prefix):] if s.startswith(prefix) else s
        if suffix and inner.endswith(suffix):
            inner = inner[: -len(suffix)]
        return int(inner.split("/")[0])
    except Exception:
        return 1001


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--auto-alert", type=int, default=0, metavar="SECONDS",
                    help="每隔 N 秒自动推一条 /notification-alert（0=关闭）")
    args = ap.parse_args()
    srv = ThreadingHTTPServer((args.host, args.port), Handler)
    srv.daemon_threads = True  # 长轮询线程不阻塞 Ctrl+C 退出
    if args.auto_alert > 0:
        def _loop():
            while True:
                time.sleep(args.auto_alert)
                bus_publish_alert()
        threading.Thread(target=_loop, daemon=True).start()
    print(f"[mock] listening on http://{args.host}:{args.port}", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
