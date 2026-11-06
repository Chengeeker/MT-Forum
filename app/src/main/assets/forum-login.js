(function (args) {
  window.__mtForumLoginCleanup?.();
  let observer;
  let timer;
  let reported = false;
  const form = document.querySelector('form[id^="loginform_"]');
  const password = form?.elements.namedItem('password');
  const cleanup = () => {
    if (timer) clearInterval(timer);
    observer?.disconnect();
    if (password) password.value = '';
    delete window.__mtForumLoginCleanup;
  };
  window.__mtForumLoginCleanup = cleanup;
  const send = (success, message) => {
    if (reported) return;
    reported = true;
    cleanup();
    window.ForumLoginBridge.postMessage(JSON.stringify({
      attempt: args.attempt, success, message,
    }));
  };
  try {
    if (location.origin !== 'https://bbs.binmt.cc' || !form ||
        new URL(form.action, location.href).origin !== location.origin) {
      send(false, '论坛登录表单结构已变化，请重试。');
      return;
    }
    const account = form.elements.namedItem('username');
    const loginfield = form.elements.namedItem('loginfield');
    const question = form.elements.namedItem('questionid');
    const answer = form.elements.namedItem('answer');
    const cookie = form.elements.namedItem('cookietime');
    const button = form.querySelector('[name="loginsubmit"]');
    if (!account || !password || !button ||
        !['username', 'email'].includes(args.loginField)) {
      send(false, '论坛登录表单缺少必要字段。');
      return;
    }
    if (!loginfield && args.loginField !== 'username') {
      send(false, '当前官网表单没有提供邮箱登录。');
      return;
    }
    if (form.querySelector('[name="seccodeverify"], [name="secanswer"]')) {
      send(false, '官网要求额外验证码，当前原生表单无法完成该验证，可尝试 QQ 授权登录。');
      return;
    }
    if (loginfield) {
      // Discuz simulateSelect leaves only the selected option in the native select.
      if (loginfield.options && ![...loginfield.options].some(o => o.value === args.loginField)) {
        loginfield.add(new Option(args.loginField, args.loginField));
      }
      loginfield.value = args.loginField;
    }
    account.value = args.username;
    password.value = args.password;
    if (question) question.value = String(args.questionId);
    if (answer) answer.value = args.answer;
    if (cookie) cookie.checked = args.remember;
    // The official response heading is a sibling of the form, not its child.
    const messageId = form.id.replace('loginform_', 'returnmessage_');
    const readMessage = () => (document.getElementById(messageId)?.innerText ||
      document.querySelector('#messagetext')?.innerText || '').trim();
    const report = () => {
      const text = readMessage();
      if (!text || /^(正在提交|请稍候)/.test(text)) return;
      send(/欢迎您回来|登录成功|已登录/.test(text), text);
    };
    observer = new MutationObserver(report);
    observer.observe(document.body, { subtree: true, childList: true, characterData: true });
    timer = setInterval(report, 250);
    form.requestSubmit(button);
    report();
  } catch (_) {
    send(false, '登录提交失败，请重新连接论坛后重试。');
  }
})
