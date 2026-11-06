# shellcheck shell=bash
# Mealie：sso=oidc（网关身份提供方登录，code 换会话）；清单没有 mcp。

web_assert() { grep -qi 'mealie'; }   # stdin：打开 / 落到的 Mealie 页面（SSR 出的 HTML）

identity_check() { # Mealie 的 code 换会话由前端 JS 做：按浏览器的请求链自己走一遍，再调当前用户接口
  local start final code state at me
  start="$(curl -sS --noproxy '*' -o /dev/null -b "$SMOKE_JAR" -c "$SMOKE_JAR" \
    -w '%{redirect_url}' "$SMOKE_WEB_URL/api/auth/oauth")" || { echo "进不了 /api/auth/oauth"; return 1; }
  [[ -n "$start" ]] || { echo "/api/auth/oauth 没有跳到身份提供方"; return 1; }
  final="$(curl -sS --noproxy '*' -o /dev/null -L -b "$SMOKE_JAR" -c "$SMOKE_JAR" -H 'Accept: text/html' \
    -w '%{url_effective}' "$start")" || { echo "authorize 链失败：$start"; return 1; }
  code="$(qparam "$final" code)"
  state="$(qparam "$final" state)"
  [[ -n "$code" && -n "$state" ]] || { echo "回调里没有 code/state：$final"; return 1; }
  me="$(curl -sS --noproxy '*' -b "$SMOKE_JAR" -c "$SMOKE_JAR" --fail-with-body \
    --get --data-urlencode "code=$code" --data-urlencode "state=$state" \
    "$SMOKE_WEB_URL/api/auth/oauth/callback")" || { echo "换会话失败"; return 1; }
  at="$(jq -r '.access_token // empty' <<<"$me")"
  [[ -n "$at" ]] || { echo "回调没发 access_token：$me"; return 1; }
  # 网关认的是会话 Cookie，Bearer 只给 Mealie 自己；两个都要带。
  me="$(curl -sS --noproxy '*' --fail-with-body -b "$SMOKE_JAR" -H "Authorization: Bearer $at" "$SMOKE_WEB_URL/api/users/self")" ||
    { echo "/api/users/self 失败"; return 1; }
  jq -e --arg u "$SMOKE_OWNER" '.admin == true and .username == $u' <<<"$me" >/dev/null ||
    { echo "当前用户不是 $SMOKE_OWNER 管理员：$me"; return 1; }
}

qparam() { # <url> <名字>：取查询参数
  python3 -c 'import sys,urllib.parse;print((urllib.parse.parse_qs(urllib.parse.urlparse(sys.argv[1]).query).get(sys.argv[2]) or [""])[0])' "$1" "$2"
}
