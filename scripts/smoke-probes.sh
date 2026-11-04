# scripts/smoke.sh 的一项一项探测，跟着插件走。没写的项会 FAIL 并给出写法，不会默认放行。
#
# 页面：web_assert 从标准输入读页面，命中的确是应用的真实页面时返回 0。
# 身份：identity_check 用应用自己的“当前用户”接口断言认出的是用户管理员。没有用户体系时写 IDENTITY_NA=1，
#       并在 SMOKE_NOTE 里写原因。dweb / web_get 是带用户会话的请求助手，可继续走应用自己的登录链。
# 工具：MCP_TOOL 写一个只读工具名（可带插件前缀），MCP_ARGS 是 JSON 参数；mcp_assert 从标准输入读调用结果。
#       要断言多个工具时改成写 mcp_check；调用前要备数据时写 before_mcp。
# 装之前要准备（如先配出口代理）：写 before_install。

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
  me="$(curl -sS --noproxy '*' --fail-with-body -H "Authorization: Bearer $at" "$SMOKE_WEB_URL/api/users/self")" ||
    { echo "/api/users/self 失败"; return 1; }
  jq -e --arg u "$SMOKE_OWNER" '.admin == true and .username == $u' <<<"$me" >/dev/null ||
    { echo "当前用户不是 $SMOKE_OWNER 管理员：$me"; return 1; }
}

qparam() { # <url> <名字>：取查询参数
  python3 -c 'import sys,urllib.parse;print((urllib.parse.parse_qs(urllib.parse.urlparse(sys.argv[1]).query).get(sys.argv[2]) or [""])[0])' "$1" "$2"
}
