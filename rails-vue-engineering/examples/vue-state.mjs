import assert from 'node:assert/strict';
import { test } from 'node:test';
import { computed, effectScope, reactive, ref, shallowRef, watch } from 'vue';
import { useLatestRequest } from './latest-request.js';

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

for (const outcome of ['resolve', 'reject']) {
  test(`old ${outcome} cannot replace new success`, async () => {
    const owner = useLatestRequest();
    const old = deferred();
    const first = owner.run(() => old.promise);
    await owner.run(() => Promise.resolve('new'));
    old[outcome](outcome === 'resolve' ? 'old' : new Error('old'));
    await first;
    assert.deepEqual(owner.state.value, { status: 'success', data: 'new' });
  });
}

test('old completion cannot finish the new loading state', async () => {
  const owner = useLatestRequest();
  const a = deferred();
  const b = deferred();
  const first = owner.run(() => a.promise);
  const second = owner.run(() => b.promise);
  a.resolve('old');
  await first;
  assert.equal(owner.state.value.status, 'loading');
  b.reject(new Error('current'));
  await second;
  assert.equal(owner.state.value.status, 'error');
});

test('scope disposal invalidates a late result', async () => {
  const scope = effectScope();
  const owner = scope.run(() => useLatestRequest());
  const pending = deferred();
  const work = owner.run(() => pending.promise);
  scope.stop();
  pending.resolve('disposed');
  await work;
  assert.equal(owner.state.value.status, 'idle');
});

test('identity invalidation protects replacement identity', async () => {
  const owner = useLatestRequest();
  const old = deferred();
  const work = owner.run(() => old.promise);
  owner.invalidate();
  await owner.run(() => Promise.resolve('new identity'));
  old.reject(new Error('old identity 401'));
  await work;
  assert.deepEqual(owner.state.value, { status: 'success', data: 'new identity' });
});

test('guarding return values cannot undo a callback side effect', async () => {
  const owner = useLatestRequest();
  const pending = deferred();
  const rows = ref('initial');
  const work = owner.run(async () => { rows.value = await pending.promise; return rows.value; });
  owner.invalidate();
  rows.value = 'current';
  pending.resolve('stale');
  await work;
  assert.equal(owner.state.value.status, 'idle');
  assert.equal(rows.value, 'stale'); // demonstrates the forbidden callback shape
});

test('shallow nested edits do not invalidate a computed view', () => {
  const shallow = shallowRef({ name: 'before' });
  const view = computed(() => shallow.value.name);
  assert.equal(view.value, 'before');
  shallow.value.name = 'after';
  assert.equal(view.value, 'before');
  shallow.value = { name: 'replacement' };
  assert.equal(view.value, 'replacement');
  const deep = ref({ name: 'before' });
  const deepView = computed(() => deep.value.name);
  assert.equal(deepView.value, 'before');
  deep.value.name = 'after';
  assert.equal(deepView.value, 'after');
});

test('draft initializes on edit identity, not option refresh', () => {
  const scope = effectScope();
  const props = reactive({ visible: true, record: { id: 1, name: 'saved' }, options: [] });
  const form = reactive({ name: '' });
  scope.run(() => watch(
    () => [props.visible, props.record.id],
    ([visible], previous) => {
      if (visible && (!previous || !previous[0] || previous[1] !== props.record.id)) {
        form.name = props.record.name;
      }
    },
    { immediate: true, flush: 'sync' },
  ));
  form.name = 'draft';
  props.options = ['new option'];
  props.record = { id: 1, name: 'server refresh' };
  assert.equal(form.name, 'draft');
  props.record = { id: 2, name: 'another record' };
  assert.equal(form.name, 'another record');
  scope.stop();
});
