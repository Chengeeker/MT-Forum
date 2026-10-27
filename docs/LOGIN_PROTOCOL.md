# 官网登录核对（2026-10-25）

通过独立的游客浏览器会话读取官网当前页面，并实际展开账号类型菜单；未提交账号密码、发送短信、确认 QQ 授权或修改用户现有浏览器会话。

来源：<https://bbs.binmt.cc/member.php?mod=logging&action=login>

## 当前可见入口

- 用户名＋密码：`loginfield=username`。
- Email＋密码：官网菜单显示 `Email`，选中后表单参数为 `loginfield=email`。其账号输入仍使用字段名 `username`。
- QQ 快捷登录：官网 `connect.php?mod=login&op=init`，经论坛生成动态 state 后转到 `graph.qq.com/oauth2.0/show`，页面内登录框来自 `xui.ptlogin2.qq.com`。用户在 QQ 官方界面授权，客户端不接触 QQ 密码；返回论坛并建立 auth Cookie 后完成。
- 安全提问及自动登录是账号密码方式的附加字段。当前登录页没有展示短信/手机号入口，页面加载的通用 comiis SMS 脚本不能作为已启用该方式的证据。

## 表单与响应

- form ID 为动态 `loginform_<hash>`，action 自带动态 loginhash；隐藏 formhash、referer 沿用官网，不能硬编码。
- 字段包括 `loginfield`、`username`、`password`、`questionid`、`answer`、`cookietime`、`loginsubmit`。
- 官网通过 onsubmit 中的 `ajaxpost(formId, returnMessageId, returnMessageId, 'onerror')` 提交。
- `returnmessage_<hash>` 实际是表单外的兄弟标题节点。旧代码在 form 内查询得到 null，观察整个 body 时仍从 null 读取文本，因而无法报告 AJAX 错误。
- Discuz 的 simulateSelect 把原始 select 转换为菜单，原 select 可能只保留当前 option。切换 Email 参数时需要确保已核对的 email option 存在。
- 本次使用官网表单的正常 requestSubmit，不提前清除 DOM 密码；响应、取消或超时后清除。JS 响应携带请求代次，迟到消息不能完成新请求。

## 运行边界

- 登录优先于已排队的正文读取；整个桥接事务限时 35 秒，原生表单另有 45 秒看门狗，并提供取消；取消清理最多额外 5 秒。页面加载、脚本调用、Cookie 读取、清理均有边界。
- QQ 仅放行 HTTPS 的已核对 QQ 登录主机；不向这些主机附加论坛 Cookie 或自制密码请求。未在官网确认的登录方式不伪造按钮。
- QQ 跨站 iframe 所需的第三方 Cookie 仅在专用授权 WebView 上启用，不更改普通论坛视图。授权视图不向 QQ 注入论坛样式或读取 QQ 表单。
- 当前游客登录页未展示验证码。若服务端动态增加验证码，当前原生表单没有适配验证码输入，会明确提示该限制并提示可尝试 QQ 授权；不得把这种情况宣称登录成功。真实账号成功登录、QQ 授权回调和触发风控后的验证码仍需账号/设备验收。

## 2026-10-26 状态同步修正
- 用户反馈官网已登录但原生仍等待。原生提交期每 500ms 读取 Android CookieManager，新建/变化的非空 auth 会话可独立结束等待；不只依赖网页提示文字。取消/返回后及进入“我的”时同步共享会话，已有会话不再打开登录表单；服务端明确返回登录页时可强制重新验证，防失效 Cookie 重载循环。
- 复核游客页面当前 returnmessage 初始文本为空；注册链接当前为 member.php?mod=register213。原生注册读取官网当次链接，不硬编码此后缀。
- Cookie 建立后的桥接无响应、迟到错误、已登录入口恢复均有自动化回归。没有用真实账号提交，不能把这些检查当作真机端到端验收。
