// Self-test of the simulator harness against a tiny fixture script.
// Run: node tests/lib/workflow-sim.test.mjs
import assert from 'node:assert/strict'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { runWorkflow } from './workflow-sim.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const FIXTURE = join(here, 'fixtures', 'sim-smoke.workflow.mjs')

const tests = []
const test = (name, fn) => tests.push({ name, fn })

test('runs the real file text: agent stubbed, pipeline faithful, return captured', async () => {
  const { result, calls } = await runWorkflow(FIXTURE, {
    args: { greeting: 'hello' },
    agentStub: (prompt, opts) => {
      assert.equal(prompt, 'hello')
      assert.equal(opts.model, 'haiku')
      return 'world'
    },
  })
  assert.deepEqual(result, { r: 'world', doubled: [2, 4], broken: [null] })
  assert.equal(calls.length, 1)
})

test('a throwing pipeline stage drops the item to null, like the real tool', async () => {
  const { result } = await runWorkflow(FIXTURE, { args: { greeting: 'x' }, agentStub: () => 'y' })
  assert.deepEqual(result.broken, [null])
})

let failed = 0
for (const t of tests) {
  try { await t.fn(); console.log('ok -', t.name) }
  catch (e) { failed++; console.log('not ok -', t.name); console.log('   ', e.message) }
}
process.exit(failed ? 1 : 0)
