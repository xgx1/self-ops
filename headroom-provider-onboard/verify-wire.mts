/**
 * Capture the exact JSON body pi-ai would send upstream for each thinking
 * level, without touching the network. Monkey-patches globalThis.fetch, feeds a
 * canned SSE reply, and prints reasoning_effort / max-token field / role order.
 *
 * Usage: cd ~/projects/MyAI/deepseek-harness && node --import tsx/esm <script> <route-key> [model-id]
 * HARNESS is process.cwd(); the script may live anywhere.
 */
import { readFileSync, readdirSync } from 'node:fs'
import { createRequire } from 'node:module'
import { pathToFileURL } from 'node:url'

const HARNESS = process.cwd()
const require = createRequire(pathToFileURL(`${HARNESS}/noop.js`).href)
const yaml = require('js-yaml') as typeof import('js-yaml')

const { Config, resolveProfiles } = await import(pathToFileURL(`${HARNESS}/packages/llm/llm-pi-ai/src/config.ts`).href)
const { getSupportedThinkingLevels } = await import(pathToFileURL(`${HARNESS}/packages/llm/llm-pi-ai/src/models.ts`).href)

const [routeKey, modelId] = process.argv.slice(2)
if (!routeKey) {
  console.error('usage: node --import tsx/esm verify-wire.ts <route-key> [model-id]')
  process.exit(2)
}

const src = readFileSync(`${process.env.HOME}/.dsh/settings.yaml`, 'utf8')
const doc = yaml.load(src, { schema: yaml.DEFAULT_SCHEMA })
const resolved = resolveProfiles(Config({ providers: doc?.['llm-pi-ai']?.providers }).providers, 'strict')
const profile = resolved.get(routeKey)
if (!profile?.piProvider) {
  console.error(`FATAL: route "${routeKey}" has no serviceable piProvider`)
  process.exit(1)
}
const model = profile.piProvider.getModels().find(m => m.id === modelId) ?? profile.piProvider.getModels()[0]
const menu = getSupportedThinkingLevels(model)

// pi-ai is a transitive dependency with no top-level node_modules link.
const pkg = readdirSync(`${HARNESS}/node_modules/.pnpm`).find(n => n.startsWith('@earendil-works+pi-ai@'))
if (!pkg) {
  console.error('FATAL: @earendil-works/pi-ai not found under node_modules/.pnpm')
  process.exit(1)
}
const { streamSimple } = await import(
  pathToFileURL(`${HARNESS}/node_modules/.pnpm/${pkg}/node_modules/@earendil-works/pi-ai/dist/api/openai-completions.js`).href
)

const context = {
  systemPrompt: 'You are terse.',
  messages: [{ role: 'user', content: [{ type: 'text', text: 'Say hi.' }] }],
}
const sseBody = `data: ${JSON.stringify({ choices: [{ delta: { content: 'ok' }, finish_reason: 'stop' }] })}\n\n`

async function captureWire(reasoning: string | undefined): Promise<Record<string, unknown> | null> {
  let body: Record<string, unknown> | null = null
  const prev = globalThis.fetch
  globalThis.fetch = (async (_url, init: RequestInit) => {
    body = JSON.parse(String(init.body))
    return new Response(sseBody, { status: 200, headers: { 'content-type': 'text/event-stream' } })
  }) as typeof fetch
  try {
    for await (const _chunk of streamSimple(model, context, {
      reasoning,
      apiKey: 'dummy',
      fetch: globalThis.fetch,
    } as never)) {
      // drain so the request is actually issued
    }
  } catch (err) {
    console.log(`  (stream note: ${String((err as Error).message ?? err).slice(0, 100)})`)
  } finally {
    globalThis.fetch = prev
  }
  return body
}

console.log(`route=${routeKey}  model=${model.id}  menu=${JSON.stringify(menu)}`)
console.log('')

const thinkingMap = (model as { thinkingLevelMap?: Record<string, unknown> }).thinkingLevelMap
const s = (v: unknown): string => (v === undefined ? 'undefined' : JSON.stringify(v))

let failed = false
for (const level of [undefined, ...menu]) {
  const body = await captureWire(level)
  if (!body) {
    console.log(`reasoning=${s(level).padEnd(10)} FAILED: no request captured`)
    failed = true
    continue
  }
  const effort = body.reasoning_effort
  const maxField = 'max_tokens' in body ? 'max_tokens' : 'max_completion_tokens'
  const roles = ((body.messages as { role: string }[]) ?? []).map(m => m.role)

  // The wire value is the thinkingLevelMap dispatch, not the level label: an
  // "off" level may legitimately map to "none". When nothing is selected,
  // pi-ai dispatches the "off" entry — so a provider that declares "off"
  // legitimately sends a value even with no level chosen.
  const mapped = level === undefined ? thinkingMap?.off : thinkingMap?.[level]
  const expected = typeof mapped === 'string' ? mapped : undefined

  // Hard failures: the level you selected must dispatch to what the config
  // declared. Everything else is advisory — other providers legitimately use
  // max_completion_tokens or the developer role.
  const problems: string[] = []
  if (effort !== expected) problems.push(`expected reasoning_effort=${s(expected)}, got ${s(effort)}`)

  const notes: string[] = []
  if (level === undefined && effort !== undefined) {
    notes.push(`note: 未选档位仍发 reasoning_effort=${s(effort)}（因为声明了 "off" 映射，思考会被静默关掉）`)
  }
  if (maxField !== 'max_tokens') notes.push('note: 上游用 max_completion_tokens（非 headroom+OpenAI 兼容默认）')
  if (roles.includes('developer')) notes.push('note: 发 developer role（supportsDeveloperRole 未设 false）')

  if (problems.length > 0) failed = true
  console.log(
    `reasoning=${s(level).padEnd(10)} reasoning_effort=${s(effort).padEnd(10)} maxTokens=${maxField}`
    + ` roles=${JSON.stringify(roles)}`
    + (problems.length === 0 ? '' : `  ❌ ${problems.join('; ')}`)
    + (notes.length === 0 ? '' : `\n    ${notes.join('\n    ')}`),
  )
}

console.log('')
console.log(failed ? '❌ wire check FAILED' : '✅ wire check passed')
process.exit(failed ? 1 : 0)
