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

启动：python tools/mock-discourse/server.py [--port 8080]
"""

import argparse
import json
import sys
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
]


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


def topic_detail(tid: int) -> dict:
    t = next((x for x in TOPICS if x["id"] == tid), TOPICS[0])
    posts = [make_post(i, t["id"]) for i in range(1, min(t["posts_count"], 6) + 1)]
    # 首帖插一张 AVIF：用于验证 OHOS 上的 AVIF 解码链路
    # （自研 libavif + dav1d + 后台 isolate + maxDim 降采样）。
    if posts:
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
    args = ap.parse_args()
    srv = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"[mock] listening on http://{args.host}:{args.port}", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
