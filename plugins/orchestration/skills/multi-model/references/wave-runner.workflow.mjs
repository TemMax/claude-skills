export const meta = {
  name: 'wave-runner',
  description: 'Reference supervised-wave runner: isolation, executors, supervision, escalation ladder',
  phases: [
    { title: 'Wave', detail: 'per task: executor → supervisor → ladder' },
  ],
}

// Escalation policy tested by tests/lib/wave-runner.test.mjs — change the
// numbers there and here together.
const MODELS = ['haiku', 'sonnet', 'opus', 'fable']
const EFFORTS = ['low', 'medium', 'high', 'xhigh', 'max']
const LADDER_ORDER = ['haiku', 'sonnet', 'opus']
const MAX_ATTEMPTS_PER_RUNG = 2
const MAX_ATTEMPTS_PER_TASK = 6

function invalid(errors) { return { status: 'invalid-args', errors, tasks: [] } }

// Fail closed: a bad wave returns named errors and spawns nothing. `args`
// arriving as a string (the caller stringified it) has shipped twice; it dies
// here by name instead of running to a plausible, meaningless result.
if (typeof args !== 'object' || args === null || Array.isArray(args)) {
  return invalid(['args must be a JSON object, not a ' +
    (typeof args === 'string' ? 'string (the caller JSON-encoded it)' : typeof args)])
}

const errors = []
if (typeof args.base !== 'string' || !/^[0-9a-f]{7,40}$/.test(args.base)) {
  errors.push('base: a 7-40 char lowercase hex sha is required')
}
if (typeof args.repoPath !== 'string' || !args.repoPath.startsWith('/')) {
  errors.push('repoPath: an absolute path is required')
}
if (typeof args.defaultBranch !== 'string' || args.defaultBranch === '') {
  errors.push('defaultBranch: required')
}
if (typeof args.supervisorPromptText !== 'string' || !args.supervisorPromptText.includes('verdict')) {
  errors.push('supervisorPromptText: must be the text of references/supervisor-prompt.md (missing, or the wrong file was read)')
}
if (!args.supervisor || !MODELS.includes(args.supervisor.model)) {
  errors.push('supervisor.model: one of ' + MODELS.join('/'))
}
if (args.supervisor && args.supervisor.effort !== undefined && !EFFORTS.includes(args.supervisor.effort)) {
  errors.push('supervisor.effort: one of ' + EFFORTS.join('/'))
}
if (!Array.isArray(args.tasks) || args.tasks.length === 0) {
  errors.push('tasks: a non-empty array is required')
} else {
  const seen = new Set()
  args.tasks.forEach((t, i) => {
    const at = 'tasks[' + i + ']'
    if (!t || typeof t !== 'object') {
      errors.push(at + ': task must be an object')
      return
    }
    if (typeof t.id !== 'string' || !/^[a-z0-9]+(-[a-z0-9]+)*$/.test(t.id)) {
      errors.push(at + '.id: kebab-case required')
    } else if (seen.has(t.id)) {
      errors.push(at + '.id: duplicate "' + t.id + '"')
    } else { seen.add(t.id) }
    if (typeof t.description !== 'string' || t.description.trim() === '') {
      errors.push(at + '.description: required')
    }
    const c = t.contract
    if (!c || typeof c !== 'object') {
      errors.push(at + '.contract: required, with all five keys')
    } else {
      for (const k of ['files_allowed', 'files_forbidden', 'forbidden_moves', 'report_must_answer']) {
        if (!Array.isArray(c[k])) errors.push(at + '.contract.' + k + ': array required')
      }
      if (!Array.isArray(c.must_run)) {
        errors.push(at + '.contract.must_run: array required')
      } else {
        c.must_run.forEach((m, j) => {
          if (!m || typeof m.cmd !== 'string' || m.cmd === '') {
            errors.push(at + '.contract.must_run[' + j + '].cmd: required')
          }
          if (!m || typeof m.evidence !== 'string') {
            errors.push(at + '.contract.must_run[' + j + '].evidence: required')
          }
        })
      }
    }
    if (!t.executor || !MODELS.includes(t.executor.model)) {
      errors.push(at + '.executor.model: one of ' + MODELS.join('/') + ' (short names only)')
    }
    if (t.executor && t.executor.effort !== undefined && !EFFORTS.includes(t.executor.effort)) {
      errors.push(at + '.executor.effort: one of ' + EFFORTS.join('/'))
    }
    if (t.ladder !== undefined && (!Array.isArray(t.ladder) || t.ladder.some((m) => !MODELS.includes(m)))) {
      errors.push(at + '.ladder: an array of ' + MODELS.join('/') + ' (short names only)')
    }
  })
}
if (errors.length > 0) return invalid(errors)

// Task 3 replaces this stub tail with the wave itself.
return { status: 'partial', errors: [], tasks: [] }
