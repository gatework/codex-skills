import { getCurrentScope, onScopeDispose, shallowRef } from 'vue';

// Teaching example: immutable response state. Adapt existing project primitives.
type RequestState<T> =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'success'; data: T }
  | { status: 'error'; error: unknown };

export function useLatestRequest<T>() {
  const state = shallowRef<RequestState<T>>({ status: 'idle' });
  let generation = 0;

  function invalidate() {
    generation += 1;
    state.value = { status: 'idle' };
  }

  async function run(request: () => Promise<T>): Promise<void> {
    const ticket = ++generation;
    state.value = { status: 'loading' };
    try {
      const data = await request(); // request must NOT write owner state
      if (ticket !== generation) return;
      state.value = { status: 'success', data };
    } catch (error) {
      if (ticket !== generation) return;
      state.value = { status: 'error', error };
    }
  }

  if (getCurrentScope()) onScopeDispose(invalidate);
  return { state, run, invalidate };
}
