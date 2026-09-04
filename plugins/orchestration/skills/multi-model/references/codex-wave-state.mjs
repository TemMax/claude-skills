#!/usr/bin/env node
// Deterministic state and mechanical verification for Codex-native waves.
// This helper never calls a model or the network. It prints one JSON object.
import {
  existsSync, mkdirSync, readFileSync, renameSync, writeFileSync,
} from 'node:fs'
import { spawnSync } from 'node:child_process'
import { basename, dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

export const CODEX_MODELS = ['gpt-5.6-sol', 'gpt-5.6-terra', 'gpt-5.6-luna']
export const EFFORTS = ['low', 'medium', 'high', 'xhigh', 'max']
export const ACTIONS = ['spawn-executor', 'verify', 'spawn-supervisor', 'merge-ready', 'stop']

const CLAUDE_MODELS = ['haiku', 'sonnet', 'opus', 'fable', 'claude-opus-4-8']
const CONTRACT_KEYS = ['files_allowed', 'files_forbidden', 'must_run',
  'forbidden_moves', 'report_must_answer']
const AGENT_ERRORS = ['null-result', 'transport', 'tool-unavailable']
const COMMANDS = {
  init: ['plan', 'wave', 'repo', 'base'],
  next: ['state'],
  'record-executor': ['state', 'task'],
  verify: ['state', 'task'],
  'supervisor-prompt': ['state', 'task'],
  'record-verdict': ['state', 'task'],
  summary: ['state'],
}
const KEBAB = /^[a-z0-9]+(?:-[a-z0-9]+)*$/
const SHA = /^[0-9a-f]{40}$/
const MAX_EXECUTOR_ATTEMPTS = 6
const TASK_STATUSES = ['ready', 'reported', 'verified', 'merge-ready',
  'contract-unsatisfiable', 'failed', 'error']
const ESCALATIONS = [null, 'same-rule-repeat', 'rung-exhausted',
  'paste-two-strikes', 'raised-effort']
const STATE_KEYS = ['schema', 'planPath', 'wave', 'repoPath', 'base',
  'supervisor', 'tasks']
const TASK_KEYS = ['status', 'branch', 'worktree', 'rungs', 'rung',
  'attemptOnRung', 'totalAttempts', 'pasteStrikes', 'reports',
  'verifierFacts', 'verdicts', 'agentFailures']

class NamedError extends Error {
  constructor(name, message) {
    super(name + ': ' + message)
    this.name = name
  }
}

const clone = (value) => JSON.parse(JSON.stringify(value))
const ownKeysAre = (value, keys) => value && typeof value === 'object' && !Array.isArray(value)
  && Object.keys(value).sort().join('\0') === [...keys].sort().join('\0')

export function atomicWrite(path, value) {
  const tmp = path + '.tmp'
  writeFileSync(tmp, JSON.stringify(value, null, 2) + '\n', { mode: 0o600 })
  renameSync(tmp, path)
}

export function parseCli(argv) {
  if (!Array.isArray(argv) || argv.length === 0 || !COMMANDS[argv[0]]) {
    throw new NamedError('usage', 'expected one of ' + Object.keys(COMMANDS).join('|'))
  }
  const command = argv[0]
  const allowed = COMMANDS[command]
  const options = {}
  for (let i = 1; i < argv.length; i += 2) {
    const flag = argv[i]
    const value = argv[i + 1]
    if (!flag || !flag.startsWith('--') || value === undefined) {
      throw new NamedError('usage', command + ': options must be --name value pairs')
    }
    const key = flag.slice(2)
    if (!allowed.includes(key)) throw new NamedError('usage', command + ': unknown option --' + key)
    if (Object.hasOwn(options, key)) throw new NamedError('usage', command + ': duplicate option --' + key)
    options[key] = value
  }
  const missing = allowed.filter((key) => !Object.hasOwn(options, key))
  if (missing.length) throw new NamedError('usage', command + ': missing --' + missing.join(', --'))
  return { command, options }
}

export function extractWavePlan(markdown) {
  if (typeof markdown !== 'string') throw new NamedError('plan-parse', 'plan must be Markdown text')
  const blocks = [...markdown.matchAll(/```json wave-plan\r?\n([\s\S]*?)\r?\n```/g)]
  if (blocks.length !== 1) {
    throw new NamedError('plan-parse', 'expected exactly one ```json wave-plan block, found ' + blocks.length)
  }
  let plan
  try { plan = JSON.parse(blocks[0][1]) } catch (error) {
    throw new NamedError('plan-parse', 'wave-plan JSON does not parse: ' + error.message)
  }
  if (!plan || typeof plan !== 'object' || Array.isArray(plan) || !Array.isArray(plan.waves)) {
    throw new NamedError('plan-parse', '`waves` must be an array')
  }
  return plan
}

export function validateCodexWave(wave, index) {
  const at = 'waves[' + index + ']'
  const errors = []
  if (!wave || typeof wave !== 'object' || Array.isArray(wave)) return [at + ': must be an object']
  const supervisor = wave.supervisor
  if (!supervisor || typeof supervisor !== 'object' || Array.isArray(supervisor)) {
    errors.push(at + '.supervisor: required')
  } else {
    if (!CODEX_MODELS.includes(supervisor.model)) {
      errors.push(at + '.supervisor.model: ' + (CLAUDE_MODELS.includes(supervisor.model)
        ? 'host-mismatch: Claude model in Codex wave'
        : 'one of ' + CODEX_MODELS.join('/')))
    }
    if (supervisor.effort !== undefined && !EFFORTS.includes(supervisor.effort)) {
      errors.push(at + '.supervisor.effort: one of ' + EFFORTS.join('/'))
    }
  }
  if (!Array.isArray(wave.tasks) || wave.tasks.length === 0) {
    errors.push(at + '.tasks: non-empty array required')
    return errors
  }
  const ids = []
  wave.tasks.forEach((task, taskIndex) => {
    const tat = at + '.tasks[' + taskIndex + ']'
    if (!task || typeof task !== 'object' || Array.isArray(task)) {
      errors.push(tat + ': must be an object')
      return
    }
    if (typeof task.id !== 'string' || !KEBAB.test(task.id)) {
      errors.push(tat + '.id: kebab-case required')
    } else {
      ids.push(task.id)
      if (task.branch !== 'wave/' + task.id) errors.push(tat + '.branch: must be "wave/' + task.id + '"')
    }
    const executor = task.executor
    if (!executor || typeof executor !== 'object' || Array.isArray(executor)) {
      errors.push(tat + '.executor: required')
    } else {
      if (!CODEX_MODELS.includes(executor.model)) {
        errors.push(tat + '.executor.model: ' + (CLAUDE_MODELS.includes(executor.model)
          ? 'host-mismatch: Claude model in Codex wave'
          : 'one of ' + CODEX_MODELS.join('/')))
      }
      if (executor.effort !== undefined && !EFFORTS.includes(executor.effort)) {
        errors.push(tat + '.executor.effort: one of ' + EFFORTS.join('/'))
      }
    }
    if (task.ladder !== undefined && (!Array.isArray(task.ladder)
      || task.ladder.some((model) => !CODEX_MODELS.includes(model)))) {
      const hostMismatch = Array.isArray(task.ladder)
        && task.ladder.some((model) => CLAUDE_MODELS.includes(model))
      errors.push(tat + '.ladder: ' + (hostMismatch ? 'host-mismatch: Claude model in Codex wave'
        : 'array of ' + CODEX_MODELS.join('/')))
    }
    if (supervisor && executor
      && [executor.model, ...(Array.isArray(task.ladder) ? task.ladder : [])]
        .includes(supervisor.model)) {
      errors.push(tat + ': supervisor model also appears as executor or ladder rung')
    }
    const contract = task.contract
    if (!contract || typeof contract !== 'object' || Array.isArray(contract)) {
      errors.push(tat + '.contract: required, with all five keys')
    } else {
      for (const key of CONTRACT_KEYS) {
        if (!Array.isArray(contract[key])) errors.push(tat + '.contract.' + key + ': array required')
      }
      if (Array.isArray(contract.must_run)) contract.must_run.forEach((item, itemIndex) => {
        if (!item || typeof item !== 'object' || typeof item.cmd !== 'string' || item.cmd === '') {
          errors.push(tat + '.contract.must_run[' + itemIndex + '].cmd: required')
        }
        if (!item || typeof item !== 'object' || typeof item.evidence !== 'string') {
          errors.push(tat + '.contract.must_run[' + itemIndex + '].evidence: required')
        }
      })
    }
  })
  for (const id of new Set(ids.filter((value, i) => ids.indexOf(value) !== i))) {
    errors.push(at + ': duplicate task id "' + id + '"')
  }
  return errors
}

export function makeState({ planPath, waveNumber, repoPath, base, wave }) {
  const tasks = {}
  for (const task of wave.tasks) {
    tasks[task.id] = {
      status: 'ready',
      branch: task.branch,
      worktree: join(repoPath, '.worktrees', 'wave-' + task.id),
      rungs: [task.executor.model, ...(task.ladder ?? [])],
      rung: 0,
      attemptOnRung: 0,
      totalAttempts: 0,
      pasteStrikes: 0,
      reports: [],
      verifierFacts: [],
      verdicts: [],
      agentFailures: [],
    }
  }
  return {
    schema: 1,
    planPath,
    wave: waveNumber,
    repoPath,
    base,
    supervisor: {
      model: wave.supervisor.model,
      effort: wave.supervisor.effort ?? 'high',
    },
    tasks,
  }
}

function readPlanWave(state) {
  let markdown
  try { markdown = readFileSync(state.planPath, 'utf8') } catch (error) {
    throw new NamedError('plan-read', error.message)
  }
  const plan = extractWavePlan(markdown)
  const wave = plan.waves[state.wave - 1]
  if (!wave) throw new NamedError('state-schema', 'selected wave no longer exists in plan')
  return wave
}

function taskSpec(state, id) {
  const wave = readPlanWave(state)
  const task = wave.tasks.find((candidate) => candidate && candidate.id === id)
  if (!task) throw new NamedError('state-schema', 'task "' + id + '" no longer exists in plan')
  return task
}

const nonemptyString = (value) => typeof value === 'string' && value.length > 0
const boundedInteger = (value, max) => Number.isInteger(value) && value >= 0 && value <= max

function validProcessFact(fact) {
  if (!fact || typeof fact !== 'object' || Array.isArray(fact)) return false
  const keys = Object.keys(fact)
  if (!keys.every((key) => ['exit', 'stdout', 'stderr', 'error'].includes(key))) return false
  return Object.hasOwn(fact, 'exit') && Object.hasOwn(fact, 'stdout')
    && Object.hasOwn(fact, 'stderr')
    && (fact.exit === null || boundedInteger(fact.exit, Number.MAX_SAFE_INTEGER))
    && typeof fact.stdout === 'string' && typeof fact.stderr === 'string'
    && (fact.error === undefined || typeof fact.error === 'string')
}

function validMechanicalViolation(violation) {
  return ownKeysAre(violation, ['class', 'rule', 'evidence'])
    && nonemptyString(violation.class) && nonemptyString(violation.rule)
    && typeof violation.evidence === 'string'
}

function validVerifierFact(fact, state, task) {
  if (!ownKeysAre(fact, ['base', 'branch', 'currentBranch', 'baseIsAncestor',
    'worktreeStatus', 'preflightPassed', 'changedPaths', 'commitCount', 'diff',
    'git', 'mustRun', 'violations'])) return false
  if (fact.base !== state.base || fact.branch !== task.branch
    || (fact.currentBranch !== null && typeof fact.currentBranch !== 'string')
    || typeof fact.baseIsAncestor !== 'boolean' || typeof fact.worktreeStatus !== 'string'
    || typeof fact.preflightPassed !== 'boolean'
    || !Array.isArray(fact.changedPaths) || fact.changedPaths.some((path) => !nonemptyString(path))
    || (fact.commitCount !== null && !boundedInteger(fact.commitCount, Number.MAX_SAFE_INTEGER))
    || typeof fact.diff !== 'string' || !Array.isArray(fact.mustRun)
    || !Array.isArray(fact.violations)
    || fact.violations.some((violation) => !validMechanicalViolation(violation))) return false
  if (!ownKeysAre(fact.git, ['branch', 'ancestor', 'status', 'names', 'diff', 'count'])
    || Object.values(fact.git).some((entry) => !validProcessFact(entry))) return false
  return fact.mustRun.every((entry) => {
    const normal = ownKeysAre(entry, ['cmd', 'evidence', 'attempts'])
    const skipped = ownKeysAre(entry, ['cmd', 'evidence', 'attempts', 'skipped'])
      && entry.skipped === 'safety-preflight'
    return (normal || skipped) && nonemptyString(entry.cmd) && typeof entry.evidence === 'string'
      && Array.isArray(entry.attempts) && entry.attempts.length <= 2
      && entry.attempts.every(validProcessFact)
      && (!skipped || entry.attempts.length === 0)
  })
}

function validVerdictHistoryEntry(entry, task) {
  return ownKeysAre(entry, ['rung', 'attemptOnRung', 'model', 'effort', 'verdict', 'escalation'])
    && boundedInteger(entry.rung, task.rungs.length - 1)
    && boundedInteger(entry.attemptOnRung, 2)
    && entry.model === task.rungs[entry.rung] && EFFORTS.includes(entry.effort)
    && validVerdict(entry.verdict) && ESCALATIONS.includes(entry.escalation)
}

function validateStoredState(state, statePath) {
  const errors = []
  const err = (field, message) => errors.push(field + ': ' + message)
  if (!ownKeysAre(state, STATE_KEYS)) {
    return ['state: expected exact schema-1 top-level fields']
  }
  if (state.schema !== 1) err('schema', 'expected 1')
  if (!nonemptyString(state.planPath)) err('planPath', 'non-empty string required')
  if (!nonemptyString(state.repoPath)) err('repoPath', 'non-empty string required')
  if (!Number.isInteger(state.wave) || state.wave < 1) err('wave', 'positive integer required')
  if (!SHA.test(state.base)) err('base', 'full lowercase 40-hex SHA required')
  if (!ownKeysAre(state.supervisor, ['model', 'effort'])) {
    err('supervisor', 'exact model and effort required')
  } else {
    if (!CODEX_MODELS.includes(state.supervisor.model)) err('supervisor.model', 'unsupported Codex model')
    if (!EFFORTS.includes(state.supervisor.effort)) err('supervisor.effort', 'unsupported effort')
  }
  if (!state.tasks || typeof state.tasks !== 'object' || Array.isArray(state.tasks)
    || Object.keys(state.tasks).length === 0) err('tasks', 'non-empty object required')
  if (errors.length) return errors

  const planName = basename(state.planPath).replace(/\.[^.]+$/, '')
  const expectedStatePath = join(state.repoPath, '.worktrees', 'codex-wave',
    planName + '-w' + state.wave + '-' + state.base.slice(0, 12) + '.json')
  if (resolve(statePath) !== resolve(expectedStatePath)) err('state path', 'does not match schema fields')

  let wave
  let planWaveValid = false
  try {
    const plan = extractWavePlan(readFileSync(state.planPath, 'utf8'))
    wave = plan.waves[state.wave - 1]
    if (!wave) err('wave', 'selected plan wave does not exist')
    else {
      const waveErrors = validateCodexWave(wave, state.wave - 1)
      if (waveErrors.length) err('plan wave', waveErrors.join('; '))
      else planWaveValid = true
    }
  } catch (error) {
    err('planPath', error.message)
  }
  if (!wave || !planWaveValid) return errors
  const expectedSupervisor = {
    model: wave.supervisor.model,
    effort: wave.supervisor.effort ?? 'high',
  }
  if (state.supervisor.model !== expectedSupervisor.model
    || state.supervisor.effort !== expectedSupervisor.effort) {
    err('supervisor', 'does not match selected plan wave')
  }
  const planIds = wave.tasks.map((task) => task.id)
  const stateIds = Object.keys(state.tasks)
  if (planIds.length !== stateIds.length || planIds.some((id, index) => id !== stateIds[index])) {
    err('tasks', 'ids/order do not match selected plan wave')
  }
  for (const id of stateIds) {
    const task = state.tasks[id]
    const spec = wave.tasks.find((candidate) => candidate.id === id)
    if (!KEBAB.test(id)) err('tasks.' + id, 'kebab id required')
    if (!ownKeysAre(task, TASK_KEYS)) {
      err('tasks.' + id, 'expected exact schema-1 task fields')
      continue
    }
    if (!TASK_STATUSES.includes(task.status)) err('tasks.' + id + '.status', 'unsupported status')
    if (task.branch !== 'wave/' + id || (spec && task.branch !== spec.branch)) {
      err('tasks.' + id + '.branch', 'must be wave/' + id + ' and match plan')
    }
    const expectedWorktree = join(state.repoPath, '.worktrees', 'wave-' + id)
    if (task.worktree !== expectedWorktree) err('tasks.' + id + '.worktree', 'does not match repo/task')
    const rungsValid = Array.isArray(task.rungs) && task.rungs.length > 0
      && task.rungs.every((model) => CODEX_MODELS.includes(model))
    if (!rungsValid
      || task.rungs.some((model) => !CODEX_MODELS.includes(model))) {
      err('tasks.' + id + '.rungs', 'non-empty supported Codex models required')
    } else {
      if (task.rungs.includes(state.supervisor.model)) {
        err('tasks.' + id + '.rungs', 'supervisor model also appears as executor or ladder rung')
      }
      if (spec) {
        const expectedRungs = [spec.executor.model, ...(spec.ladder ?? [])]
        if (JSON.stringify(task.rungs) !== JSON.stringify(expectedRungs)) {
          err('tasks.' + id + '.rungs', 'do not match selected plan task')
        }
      }
    }
    const rungMax = Array.isArray(task.rungs) && task.rungs.length ? task.rungs.length - 1 : -1
    if (!boundedInteger(task.rung, rungMax)) err('tasks.' + id + '.rung', 'out of bounds')
    const attemptOnRungValid = boundedInteger(task.attemptOnRung, 2)
    const totalAttemptsValid = boundedInteger(task.totalAttempts, MAX_EXECUTOR_ATTEMPTS)
    if (!attemptOnRungValid) err('tasks.' + id + '.attemptOnRung', '0..2 required')
    if (!totalAttemptsValid) {
      err('tasks.' + id + '.totalAttempts', '0..' + MAX_EXECUTOR_ATTEMPTS + ' required')
    }
    if (attemptOnRungValid && totalAttemptsValid && task.attemptOnRung > task.totalAttempts) {
      err('tasks.' + id + '.attemptOnRung', 'cannot exceed totalAttempts')
    }
    if (totalAttemptsValid && task.status === 'ready'
      && task.totalAttempts === MAX_EXECUTOR_ATTEMPTS) {
      err('tasks.' + id + '.status', 'ready at executor attempt cap')
    }
    if (!boundedInteger(task.pasteStrikes, 2)) err('tasks.' + id + '.pasteStrikes', '0..2 required')
    if (!Array.isArray(task.reports) || task.reports.some((report) => typeof report !== 'string')) {
      err('tasks.' + id + '.reports', 'string array required')
    } else if (task.reports.length !== task.totalAttempts) {
      err('tasks.' + id + '.reports', 'length must equal totalAttempts')
    }
    if (!Array.isArray(task.verifierFacts)
      || task.verifierFacts.some((fact) => !validVerifierFact(fact, state, task))) {
      err('tasks.' + id + '.verifierFacts', 'invalid verifier history')
    }
    if (!Array.isArray(task.verdicts) || (!rungsValid && task.verdicts.length > 0)
      || (rungsValid && task.verdicts.some((entry) => !validVerdictHistoryEntry(entry, task)))) {
      err('tasks.' + id + '.verdicts', 'invalid verdict history')
    }
    if (!Array.isArray(task.agentFailures) || task.agentFailures.some((failure) =>
      !ownKeysAre(failure, ['point', 'kind', 'attempt'])
      || !['executor', 'supervisor'].includes(failure.point)
      || !AGENT_ERRORS.includes(failure.kind)
      || !Number.isInteger(failure.attempt) || failure.attempt < 1
      || failure.attempt > MAX_EXECUTOR_ATTEMPTS)) {
      err('tasks.' + id + '.agentFailures', 'invalid typed failure history')
    }
    if (Array.isArray(task.verifierFacts) && Array.isArray(task.reports)
      && task.verifierFacts.length > task.reports.length) {
      err('tasks.' + id + '.verifierFacts', 'cannot outnumber reports')
    }
    if (Array.isArray(task.verdicts) && Array.isArray(task.verifierFacts)
      && task.verdicts.length > task.verifierFacts.length) {
      err('tasks.' + id + '.verdicts', 'cannot outnumber verifier facts')
    }
  }
  return errors
}

function requireTask(state, id) {
  const task = state.tasks && state.tasks[id]
  if (!task) throw new NamedError('task-not-found', id)
  return task
}

function baseEffort(state, id, task) {
  const spec = taskSpec(state, id)
  return task.rung === 0 ? (spec.executor.effort ?? 'medium') : 'high'
}

function nextHigherEffort(effort) {
  const supported = EFFORTS.slice(0, EFFORTS.indexOf('max'))
  const index = supported.indexOf(effort)
  return index === -1 ? null : (supported[index + 1] ?? null)
}

function currentEffort(state, id, task) {
  const normal = baseEffort(state, id, task)
  const latest = task.verdicts.at(-1)
  return latest && latest.rung === task.rung && latest.escalation === 'raised-effort'
    ? nextHigherEffort(latest.effort)
    : normal
}

function executorPrompt(state, id, task, spec) {
  const prior = task.verdicts.at(-1)
  return [
    'Implement task ' + id + ' in the existing task worktree.',
    'BASE: ' + state.base,
    'BRANCH: ' + task.branch,
    'WORKTREE: ' + task.worktree,
    '',
    'CONTRACT:',
    JSON.stringify(spec.contract, null, 2),
    prior ? '' : null,
    prior ? 'PRIOR VERDICT:' : null,
    prior ? JSON.stringify(prior.verdict, null, 2) : null,
    prior ? 'Continue in the same worktree and branch; fix the violations.' : null,
  ].filter((line) => line !== null).join('\n')
}

export function nextAction(state) {
  const entries = Object.entries(state.tasks ?? {})
  let firstMergeReady = null
  const mergeReadyIds = []
  for (const [id, task] of entries) {
    const common = { status: 'ok', task: id, branch: task.branch, worktree: task.worktree }
    if (task.status === 'ready') {
      const spec = taskSpec(state, id)
      const latest = task.verdicts.at(-1)
      return {
        ...common,
        action: 'spawn-executor',
        model: task.rungs[task.rung],
        effort: currentEffort(state, id, task),
        ...(latest && latest.escalation ? { reason: latest.escalation } : {}),
        prompt: executorPrompt(state, id, task, spec),
      }
    }
    if (task.status === 'reported') return { ...common, action: 'verify' }
    if (task.status === 'verified') {
      return {
        ...common,
        action: 'spawn-supervisor',
        model: state.supervisor.model,
        effort: state.supervisor.effort,
      }
    }
    if (task.status === 'merge-ready') {
      firstMergeReady ??= common
      mergeReadyIds.push(id)
      continue
    }
    if (['contract-unsatisfiable', 'failed', 'error'].includes(task.status)) {
      return { ...common, action: 'stop', reason: task.status }
    }
    throw new NamedError('state-schema', 'unknown task status "' + task.status + '"')
  }
  if (entries.length > 0 && mergeReadyIds.length === entries.length) {
    return { ...firstMergeReady, action: 'merge-ready', tasks: mergeReadyIds }
  }
  throw new NamedError('state-schema', 'state has no tasks')
}

function isAgentError(result) {
  return ownKeysAre(result, ['error']) && ownKeysAre(result.error, ['kind'])
    && AGENT_ERRORS.includes(result.error.kind)
}

function appendAgentFailure(task, point, kind, attempt) {
  task.agentFailures.push({ point, kind, attempt })
  let consecutive = 0
  for (let i = task.agentFailures.length - 1; i >= 0; i--) {
    const failure = task.agentFailures[i]
    if (failure.point !== point || failure.attempt !== attempt) break
    consecutive++
  }
  if (consecutive >= 2) task.status = 'error'
}

export function recordExecutor(state, id, result) {
  const updated = clone(state)
  const task = requireTask(updated, id)
  if (task.status !== 'ready') throw new NamedError('state-transition', id + ': executor not expected')
  if (task.totalAttempts >= MAX_EXECUTOR_ATTEMPTS) {
    throw new NamedError('state-transition', id + ': executor attempt cap reached')
  }
  if (isAgentError(result)) {
    appendAgentFailure(task, 'executor', result.error.kind, task.totalAttempts + 1)
    return updated
  }
  if (!ownKeysAre(result, ['report']) || typeof result.report !== 'string') {
    throw new NamedError('executor-result', 'expected exactly {"report":"..."} or a fixed typed error')
  }
  task.reports.push(result.report)
  task.totalAttempts++
  task.attemptOnRung++
  task.status = 'reported'
  return updated
}

function runGit(cwd, args) {
  const result = spawnSync('git', args, { cwd, encoding: 'utf8' })
  return {
    exit: result.status,
    stdout: result.stdout ?? '',
    stderr: result.stderr ?? '',
    ...(result.error ? { error: result.error.code ?? result.error.message } : {}),
  }
}

function globRegex(glob) {
  let expression = ''
  for (let i = 0; i < glob.length; i++) {
    const char = glob[i]
    if (char === '*' && glob[i + 1] === '*') { expression += '.*'; i++ }
    else if (char === '*') expression += '[^/]*'
    else if (char === '?') expression += '[^/]'
    else expression += char.replace(/[|\\{}()[\]^$+?.]/g, '\\$&')
  }
  return new RegExp('^' + expression + '$')
}

const matchesAny = (path, globs) => globs.some((glob) => typeof glob === 'string'
  && globRegex(glob).test(path))

function runContractCommand(cmd, cwd) {
  const result = spawnSync(cmd, { cwd, encoding: 'utf8', shell: true })
  return {
    exit: result.status,
    stdout: result.stdout ?? '',
    stderr: result.stderr ?? '',
    ...(result.error ? { error: result.error.code ?? result.error.message } : {}),
  }
}

export function verifyTask(state, id) {
  const updated = clone(state)
  const task = requireTask(updated, id)
  if (task.status !== 'reported') throw new NamedError('state-transition', id + ': verify not expected')
  const spec = taskSpec(updated, id)
  const branch = runGit(task.worktree, ['branch', '--show-current'])
  const ancestor = runGit(task.worktree,
    ['merge-base', '--is-ancestor', updated.base, 'HEAD'])
  const status = runGit(task.worktree, ['status', '--porcelain', '--untracked-files=all'])
  const currentBranch = branch.exit === 0 ? branch.stdout.trim() : null
  const baseIsAncestor = ancestor.exit === 0
  const worktreeStatus = status.stdout
  const preflightViolations = []
  if (branch.exit !== 0 || currentBranch !== task.branch) preflightViolations.push({
    class: 'git',
    rule: 'current branch must equal ' + task.branch,
    evidence: currentBranch ?? branch.stderr ?? branch.error ?? '',
  })
  if (!baseIsAncestor) preflightViolations.push({
    class: 'git',
    rule: 'base must be an ancestor of HEAD',
    evidence: 'git merge-base --is-ancestor exited ' + String(ancestor.exit)
      + (ancestor.stderr || ancestor.error || ''),
  })
  if (status.exit !== 0) preflightViolations.push({
    class: 'git',
    rule: 'git status must establish task worktree state',
    evidence: status.stderr || status.error || '',
  })
  else if (worktreeStatus !== '') preflightViolations.push({
    class: 'worktree',
    rule: 'task worktree must be clean before verification',
    evidence: worktreeStatus,
  })
  const preflightPassed = preflightViolations.length === 0
  const names = runGit(task.worktree, ['diff', '--name-only', updated.base + '..HEAD'])
  const binaryDiff = runGit(task.worktree,
    ['diff', '--no-ext-diff', '--binary', updated.base + '..HEAD'])
  const count = runGit(task.worktree, ['rev-list', '--count', updated.base + '..HEAD'])
  const changedPaths = names.exit === 0
    ? names.stdout.split(/\r?\n/).filter(Boolean)
    : []
  const commitCount = count.exit === 0 && /^\d+\s*$/.test(count.stdout)
    ? Number(count.stdout.trim())
    : null
  const violations = [...preflightViolations]
  if (names.exit !== 0) violations.push({
    class: 'git', rule: 'git diff --name-only must succeed', evidence: names.stderr || names.error || '',
  })
  if (binaryDiff.exit !== 0) violations.push({
    class: 'git', rule: 'git diff --binary must succeed', evidence: binaryDiff.stderr || binaryDiff.error || '',
  })
  if (count.exit !== 0) violations.push({
    class: 'git', rule: 'git rev-list --count must succeed', evidence: count.stderr || count.error || '',
  })
  else if (commitCount === 0) violations.push({
    class: 'commits', rule: 'branch must contain at least one commit', evidence: 'commit count: 0',
  })
  for (const path of changedPaths) {
    const allowed = matchesAny(path, spec.contract.files_allowed)
    const forbidden = matchesAny(path, spec.contract.files_forbidden)
    if (!allowed || forbidden) violations.push({
      class: 'files',
      rule: forbidden ? 'files_forbidden' : 'files_allowed',
      evidence: path,
    })
  }
  const mustRun = spec.contract.must_run.map((entry) => {
    if (!preflightPassed) {
      return { cmd: entry.cmd, evidence: entry.evidence, attempts: [], skipped: 'safety-preflight' }
    }
    const attempts = [runContractCommand(entry.cmd, task.worktree)]
    if (attempts[0].exit !== 0) attempts.push(runContractCommand(entry.cmd, task.worktree))
    if (attempts.at(-1).exit !== 0) violations.push({
      class: 'must_run',
      rule: entry.cmd,
      evidence: 'exit ' + String(attempts.at(-1).exit) + '\n'
        + attempts.at(-1).stdout + attempts.at(-1).stderr,
    })
    return { cmd: entry.cmd, evidence: entry.evidence, attempts }
  })
  const facts = {
    base: updated.base,
    branch: task.branch,
    currentBranch,
    baseIsAncestor,
    worktreeStatus,
    preflightPassed,
    changedPaths,
    commitCount,
    diff: binaryDiff.stdout,
    git: { branch, ancestor, status, names, diff: binaryDiff, count },
    mustRun,
    violations,
  }
  task.verifierFacts.push(facts)
  task.status = 'verified'
  return updated
}

export function buildSupervisorPrompt(state, id, promptText) {
  const task = requireTask(state, id)
  if (task.status !== 'verified') {
    throw new NamedError('state-transition', id + ': supervisor prompt not expected before verification')
  }
  if (typeof promptText !== 'string' || promptText === '') {
    throw new NamedError('supervisor-prompt', 'prompt text is required')
  }
  const spec = taskSpec(state, id)
  const executorModel = task.rungs[task.rung]
  const report = String(task.reports.at(-1)).split(executorModel)
    .join('[executor-model-redacted]')
  return promptText + [
    '',
    '',
    'CONTRACT:',
    JSON.stringify(spec.contract, null, 2),
    '',
    'REPO: ' + state.repoPath,
    'BASE: ' + state.base,
    'BRANCH: ' + task.branch,
    '',
    'VERIFIER FACTS:',
    JSON.stringify(task.verifierFacts.at(-1), null, 2),
    '',
    'REPORT:',
    report,
  ].join('\n')
}

function validVerdict(verdict) {
  if (!ownKeysAre(verdict, ['ok', 'violations', 'remarks'])
    || typeof verdict.ok !== 'boolean' || !Array.isArray(verdict.violations)
    || !Array.isArray(verdict.remarks) || verdict.remarks.some((remark) => typeof remark !== 'string')) {
    return false
  }
  if (verdict.ok !== (verdict.violations.length === 0)) return false
  return verdict.violations.every((violation) => violation && typeof violation === 'object'
    && typeof violation.rule === 'string' && typeof violation.class === 'string'
    && typeof violation.evidence === 'string'
    && (violation.quote === undefined || typeof violation.quote === 'string')
    && (violation.pasteReproduced === undefined || typeof violation.pasteReproduced === 'boolean')
    && (violation.satisfiable === undefined || typeof violation.satisfiable === 'boolean'))
}

function sameRuleRepeat(previous, current) {
  if (!previous) return false
  return current.violations.some((violation) => previous.violations.some((prior) =>
    prior.class === violation.class && prior.rule === violation.rule))
}

export function recordVerdict(state, id, result) {
  const updated = clone(state)
  const task = requireTask(updated, id)
  if (task.status !== 'verified') throw new NamedError('state-transition', id + ': verdict not expected')
  if (isAgentError(result)) {
    appendAgentFailure(task, 'supervisor', result.error.kind, task.totalAttempts)
    return updated
  }
  if (!validVerdict(result)) {
    throw new NamedError('supervisor-result', 'expected the fixed verdict schema or a fixed typed error')
  }
  const model = task.rungs[task.rung]
  const effort = currentEffort(updated, id, task)
  const previousEntry = [...task.verdicts].reverse().find((entry) => entry.rung === task.rung)
  const entry = {
    rung: task.rung,
    attemptOnRung: task.attemptOnRung,
    model,
    effort,
    verdict: clone(result),
    escalation: null,
  }
  task.verdicts.push(entry)
  if (result.ok === true) {
    task.status = 'merge-ready'
    return updated
  }
  if (result.violations.some((violation) => violation.satisfiable === false)) {
    task.status = 'contract-unsatisfiable'
    return updated
  }
  if (result.violations.some((violation) => violation.pasteReproduced === false)) {
    task.pasteStrikes++
  }
  const terminalSol = model === 'gpt-5.6-sol' && task.rung === task.rungs.length - 1
  if (task.pasteStrikes >= 2) {
    entry.escalation = 'paste-two-strikes'
  } else if (terminalSol && task.attemptOnRung === 1 && nextHigherEffort(effort)) {
    entry.escalation = 'raised-effort'
  } else if (!terminalSol && task.attemptOnRung >= 2) {
    entry.escalation = sameRuleRepeat(previousEntry && previousEntry.verdict, result)
      ? 'same-rule-repeat'
      : 'rung-exhausted'
  }
  if (task.totalAttempts >= MAX_EXECUTOR_ATTEMPTS) {
    task.status = 'failed'
    return updated
  }
  if (task.pasteStrikes >= 2) {
    if (task.rung + 1 < task.rungs.length) {
      task.rung++
      task.attemptOnRung = 0
      task.status = 'ready'
    } else {
      task.status = 'failed'
    }
    return updated
  }
  if (terminalSol) {
    if (entry.escalation === 'raised-effort') {
      task.status = 'ready'
    } else {
      task.status = 'failed'
    }
    return updated
  }
  if (task.attemptOnRung < 2) {
    task.status = 'ready'
    return updated
  }
  if (task.rung + 1 < task.rungs.length) {
    task.rung++
    task.attemptOnRung = 0
    task.status = 'ready'
  } else {
    task.status = 'failed'
  }
  return updated
}

export function summarize(state) {
  const stateTasks = Object.entries(state.tasks ?? {})
  const tasks = stateTasks.map(([id, task]) => ({
    id,
    status: task.status === 'merge-ready' ? 'ok' : task.status,
    branch: task.branch,
    attempts: clone(task.verdicts),
  }))
  return {
    status: stateTasks.length > 0 && stateTasks.every(([, task]) => task.status === 'merge-ready')
      ? 'done'
      : 'partial',
    tasks,
  }
}

function readState(path) {
  let parsed
  try { parsed = JSON.parse(readFileSync(path, 'utf8')) } catch (error) {
    throw new NamedError('state-read', error.message)
  }
  const errors = validateStoredState(parsed, path)
  if (errors.length) throw new NamedError('state-schema', errors.join('; '))
  return parsed
}

function parseStdin() {
  let text
  try { text = readFileSync(0, 'utf8') } catch (error) {
    throw new NamedError('stdin-json', error.message)
  }
  try { return JSON.parse(text) } catch (error) {
    throw new NamedError('stdin-json', error.message)
  }
}

function gitAt(repo, args) {
  return spawnSync('git', ['-C', repo, ...args], { encoding: 'utf8' })
}

function initCommand(options) {
  const waveNumber = Number(options.wave)
  if (!Number.isInteger(waveNumber) || waveNumber < 1) {
    throw new NamedError('wave-number', 'must be a positive integer')
  }
  if (!SHA.test(options.base)) throw new NamedError('base-sha', 'must be a full lowercase 40-hex SHA')
  let markdown
  try { markdown = readFileSync(options.plan, 'utf8') } catch (error) {
    throw new NamedError('plan-read', error.message)
  }
  const plan = extractWavePlan(markdown)
  const wave = plan.waves[waveNumber - 1]
  if (!wave) throw new NamedError('wave-number', 'wave ' + waveNumber + ' does not exist')
  const errors = validateCodexWave(wave, waveNumber - 1)
  if (errors.length) throw new NamedError('wave-schema', errors.join('; '))
  if (!existsSync(options.repo)) throw new NamedError('repo', 'path does not exist: ' + options.repo)
  const resolved = gitAt(options.repo, ['rev-parse', '--verify', options.base + '^{commit}'])
  if (resolved.status !== 0 || resolved.stdout.trim() !== options.base) {
    throw new NamedError('base-sha', 'commit is not present in repository')
  }
  const state = makeState({
    planPath: options.plan,
    waveNumber,
    repoPath: options.repo,
    base: options.base,
    wave,
  })
  const stateDir = join(options.repo, '.worktrees', 'codex-wave')
  const planName = basename(options.plan).replace(/\.[^.]+$/, '')
  const statePath = join(stateDir, planName + '-w' + waveNumber + '-' + options.base.slice(0, 12) + '.json')
  if (existsSync(statePath)) throw new NamedError('state-conflict', statePath + ' already exists')
  for (const task of Object.values(state.tasks)) {
    const branchExists = gitAt(options.repo, ['show-ref', '--verify', '--quiet',
      'refs/heads/' + task.branch]).status === 0
    if (existsSync(task.worktree) || branchExists) {
      throw new NamedError('worktree-conflict', task.worktree + ' or ' + task.branch + ' already exists')
    }
  }
  for (const task of Object.values(state.tasks)) {
    mkdirSync(dirname(task.worktree), { recursive: true })
    const created = spawnSync('git', ['-C', options.repo, 'worktree', 'add', task.worktree,
      '-b', task.branch, options.base], { encoding: 'utf8' })
    if (created.status !== 0) {
      throw new NamedError('worktree-conflict', created.stderr || created.error?.message || task.worktree)
    }
  }
  mkdirSync(stateDir, { recursive: true })
  atomicWrite(statePath, state)
  return { status: 'ok', state: statePath, wave: waveNumber, tasks: Object.keys(state.tasks) }
}

function runCli(argv) {
  const { command, options } = parseCli(argv)
  if (command === 'init') return initCommand(options)
  const state = readState(options.state)
  if (command === 'next') return nextAction(state)
  if (command === 'summary') return summarize(state)
  if (command === 'record-executor') {
    const updated = recordExecutor(state, options.task, parseStdin())
    atomicWrite(options.state, updated)
    return { status: 'ok', task: options.task, next: nextAction(updated) }
  }
  if (command === 'verify') {
    const updated = verifyTask(state, options.task)
    atomicWrite(options.state, updated)
    return {
      status: 'ok', task: options.task,
      facts: updated.tasks[options.task].verifierFacts.at(-1),
    }
  }
  if (command === 'supervisor-prompt') {
    const promptPath = join(dirname(fileURLToPath(import.meta.url)), 'supervisor-prompt.md')
    return {
      status: 'ok', task: options.task,
      prompt: buildSupervisorPrompt(state, options.task, readFileSync(promptPath, 'utf8')),
    }
  }
  if (command === 'record-verdict') {
    const updated = recordVerdict(state, options.task, parseStdin())
    atomicWrite(options.state, updated)
    return { status: 'ok', task: options.task, next: nextAction(updated) }
  }
  throw new NamedError('usage', 'unknown command')
}

function main() {
  try {
    process.stdout.write(JSON.stringify(runCli(process.argv.slice(2))) + '\n')
  } catch (error) {
    process.stdout.write(JSON.stringify({ status: 'invalid', errors: [error.message] }) + '\n')
    process.exitCode = error.name === 'usage' ? 2 : 1
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main()
