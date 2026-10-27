import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import test from 'node:test';

const source = readFileSync(new URL('../assets/forum-login.js', import.meta.url), 'utf8');
function fixture({ error = '', unsafe = false } = {}) {
  const messages = [];
  let message = { innerText: '' };
  let notify;
  let submitted;
  let stopped = false;
  const fields = {
    username: { value: '' }, password: { value: '' },
    loginfield: { value: 'username', options: [{ value: 'username' }], add(o) { this.options.push(o); } },
    questionid: { value: '0' }, answer: { value: '' }, cookietime: { checked: false },
  };
  const button = {};
  const form = {
    id: 'loginform_fixture',
    action: unsafe ? 'https://evil.test/login' : 'https://bbs.binmt.cc/member.php?mod=logging&action=login',
    elements: { namedItem: name => fields[name] },
    querySelector: selector => selector === '[name="loginsubmit"]' ? button : null,
    requestSubmit(value) {
      assert.equal(value, button);
      submitted = { account: fields.username.value, password: fields.password.value, method: fields.loginfield.value };
      if (error) { message.innerText = error; notify(); }
    },
  };
  const window = { ForumLoginBridge: { postMessage: text => messages.push(JSON.parse(text)) } };
  const context = {
    window, URL,
    Option: function (text, value) { this.value = value; },
    location: { origin: 'https://bbs.binmt.cc', href: 'https://bbs.binmt.cc/member.php?mod=logging&action=login' },
    document: {
      body: {}, querySelector: selector => selector.startsWith('form[') ? form : null,
      getElementById: id => id === 'returnmessage_fixture' ? message : null,
    },
    MutationObserver: class { constructor(callback) { notify = callback; } observe() {} disconnect() { stopped = true; } },
    setInterval: () => 1, clearInterval: () => {},
  };
  return {
    fields, messages, window,
    run(method = 'username') {
      vm.runInNewContext(`${source}(${JSON.stringify({ attempt: 7, loginField: method, username: 'fixture@example.test', password: 'synthetic-only', questionId: 0, answer: '', remember: true })});`, context);
    },
    replaceResponse(text) { message = { innerText: text }; notify(); },
    get submitted() { return submitted; }, get stopped() { return stopped; },
  };
}

test('official sibling error node completes without waiting for a timeout', () => {
  const f = fixture({ error: '登录失败，密码或安全提问错误' });
  f.run();
  assert.equal(f.messages[0].success, false);
  assert.match(f.messages[0].message, /密码/);
  assert.equal(f.submitted.password, 'synthetic-only');
  assert.equal(f.fields.password.value, '');
  assert.equal(f.stopped, true);
});
test('Email survives the official simulateSelect single-option transformation', () => {
  const f = fixture();
  f.run('email');
  assert.equal(f.submitted.method, 'email');
  assert.equal(f.fields.password.value, 'synthetic-only');
  f.replaceResponse('欢迎您回来');
  assert.deepEqual(f.messages[0], { attempt: 7, success: true, message: '欢迎您回来' });
});
test('cancellation clears credentials and the response observer', () => {
  const f = fixture();
  f.run();
  f.window.__mtForumLoginCleanup();
  assert.equal(f.fields.password.value, '');
  assert.equal(f.stopped, true);
  assert.equal(f.messages.length, 0);
});
test('an off-site form action is rejected before any credential submission', () => {
  const f = fixture({ unsafe: true });
  f.run();
  assert.equal(f.submitted, undefined);
  assert.equal(f.messages[0].success, false);
});
