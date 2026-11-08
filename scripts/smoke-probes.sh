# shellcheck shell=bash
# Mealie：sso=oidc（网关身份提供方登录，code 换会话）；清单没有 mcp。

_ml_origin() { # web_url 可能带路径和查询，拼 API 前取 origin
  local u="${SMOKE_WEB_URL%%\?*}" rest="${SMOKE_WEB_URL#*://}"
  printf '%s://%s' "${u%%://*}" "${rest%%/*}"
}

web_assert() { grep -qi 'mealie'; }   # stdin：打开 / 落到的 Mealie 页面（SSR 出的 HTML）

# Mealie 的 code 换会话由前端 JS 做：按浏览器的请求链自己走一遍，Cookie 存进 $SMOKE_JAR，
# 输出应用的 access_token（当前用户接口和写接口都要带）。
mealie_login() { # 诊断写 stderr（probes_hook 会收进日志）；access_token 走 stdout
  local rb code rurl final code_q state_q me at
  rb="$(mktemp)"
  code_rurl="$(curl -sS --noproxy '*' -o "$rb" -b "${SMOKE_JAR:-}" -c "${SMOKE_JAR:-}" \
    -w '%{http_code} %{redirect_url}' "${SMOKE_WEB_URL%/}/api/auth/oauth")" ||
    { echo "进不了 /api/auth/oauth（curl 失败）" >&2; rm -f "$rb"; return 1; }
  code="${code_rurl%% *}"; rurl="${code_rurl#* }"
  [[ "$code" == 30* && -n "$rurl" ]] ||
    { echo "/api/auth/oauth 返回 HTTP $code，无跳转（OIDC 配置或应用到身份提供方的链路问题）；响应：$(head -c 200 "$rb")" >&2; rm -f "$rb"; return 1; }
  rm -f "$rb"
  final="$(curl -sS --noproxy '*' -o /dev/null -L -b "${SMOKE_JAR:-}" -c "${SMOKE_JAR:-}" -H 'Accept: text/html' \
    -w '%{http_code} %{url_effective}' "$rurl")" || { echo "authorize 链失败：$rurl" >&2; return 1; }
  [[ "${final%% *}" == 2* ]] || { echo "authorize 链返回 HTTP ${final%% *}，停在：${final#* }" >&2; return 1; }
  final="${final#* }"
  code_q="$(qparam "$final" code)"
  state_q="$(qparam "$final" state)"
  [[ -n "$code_q" && -n "$state_q" ]] || { echo "回调里没有 code/state：$final" >&2; return 1; }
  me="$(curl -sS --noproxy '*' -b "${SMOKE_JAR:-}" -c "${SMOKE_JAR:-}" --fail-with-body \
    --get --data-urlencode "code=$code_q" --data-urlencode "state=$state_q" \
    "${SMOKE_WEB_URL%/}/api/auth/oauth/callback")" || { echo "换会话失败" >&2; return 1; }
  at="$(jq -r '.access_token // empty' <<<"$me")"
  [[ -n "$at" ]] || { echo "回调没发 access_token：$me" >&2; return 1; }
  printf '%s' "$at"
}

identity_check() { # 当前用户接口断言认出的是主人管理员
  local at me
  at="$(mealie_login)" || return 1
  # 网关认的是会话 Cookie，Bearer 只给 Mealie 自己；两个都要带。
  me="$(curl -sS --noproxy '*' --fail-with-body -b "$SMOKE_JAR" -H "Authorization: Bearer $at" "$(_ml_origin)/api/users/self")" ||
    { echo "/api/users/self 失败"; return 1; }
  jq -e --arg u "$SMOKE_OWNER" '.admin == true and .username == $u' <<<"$me" >/dev/null ||
    { echo "当前用户不是 $SMOKE_OWNER 管理员：$me"; return 1; }
}

marker_file() { # SMOKE_STATE 在套件里是状态目录（e2e 传的是标记文件本身），标记放对应路径
  if [[ -d "$SMOKE_STATE" ]]; then printf '%s' "$SMOKE_STATE/mealie-marker"; else printf '%s' "${SMOKE_STATE}.marker"; fi
}

# 数据：建一个名字带随机标记的菜谱（POST /api/recipes/create/html-or-json，v3.30 建谱端点；
# 体是 schema.org/Recipe 的 JSON 字符串），重装/升级后按 slug 读回核对名字。
data_write() {
  local at marker recipe_json body resp slug
  at="$(mealie_login)" || return 1
  marker="wonton-smoke-$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
  recipe_json="$(jq -nc --arg n "$marker" \
    '{"@context":"https://schema.org","@type":"Recipe","name":$n,"description":"云吞冒烟标记","recipeIngredient":["水 200 毫升"],"recipeInstructions":[{"@type":"HowToStep","text":"烧开"}]}')"
  body="$(jq -nc --arg d "$recipe_json" '{data:$d}')"
  resp="$(curl -sS --noproxy '*' --fail-with-body -b "$SMOKE_JAR" -H "Authorization: Bearer $at" \
    -H 'Content-Type: application/json' -d "$body" \
    "$(_ml_origin)/api/recipes/create/html-or-json")" || { echo "建菜谱失败：$resp"; return 1; }
  slug="$(jq -r <<<"$resp" 2>/dev/null)" && [[ -n "$slug" && "$slug" != null ]] ||
    { echo "建菜谱没回 slug：$(head -c 200 <<<"$resp")"; return 1; }
  jq -nc --arg s "$slug" --arg m "$marker" '{slug:$s,name:$m}' >"$(marker_file)"
}

data_check() {
  local at slug marker resp
  slug="$(jq -r '.slug // empty' "$(marker_file)" 2>/dev/null)" || true
  marker="$(jq -r '.name // empty' "$(marker_file)" 2>/dev/null)" || true
  [[ -n "$slug" && -n "$marker" ]] || { echo "没有 data_write 留下的 slug 标记"; return 1; }
  at="$(mealie_login)" || return 1
  resp="$(curl -sS --noproxy '*' --fail-with-body -b "$SMOKE_JAR" -H "Authorization: Bearer $at" \
    "$(_ml_origin)/api/recipes/$slug")" || { echo "菜谱 $slug 读不回来（数据丢了？）：$resp"; return 1; }
  jq -e --arg s "$slug" --arg m "$marker" '.slug == $s and .name == $m' <<<"$resp" >/dev/null ||
    { echo "菜谱对不上：$(head -c 200 <<<"$resp")"; return 1; }
}

qparam() { # <url> <名字>：取查询参数
  python3 -c 'import sys,urllib.parse;print((urllib.parse.parse_qs(urllib.parse.urlparse(sys.argv[1]).query).get(sys.argv[2]) or [""])[0])' "$1" "$2"
}
