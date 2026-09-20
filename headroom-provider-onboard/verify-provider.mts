/**
 * Verify that a settings.yaml provider route resolves into a serviceable pi-ai
 * provider and that its thinking-level menu matches what the upstream offers.
 *
 * Usage: cd ~/projects/MyAI/deepseek-harness && node --import tsx/esm <script> <route-key> [route-key ...]
 * HARNESS is process.cwd(); the script may live anywhere.
 */
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { pathToFileURL } from 'node:url'

const HARNESS = process.cwd()
const require = createRequire(pathToFileURL(`${HARNESS}/noop.js`).href)
const yaml = require('js-yaml') as typeof import('js-yaml')

const { Config, resolveProfiles } = await import(pathToFileURL(`${HARNESS}/packages/llm/llm-pi-ai/src/config.ts`).href)
const { getSupportedThinkingLevels } = await import(pathToFileURL(`${HARNESS}/packages/llm/llm-pi-ai/src/models.ts`).href)

const wanted = process.argv.slice(2)
if (wanted.length === 0) {
  console.error('usage: node --import tsx/esm verify-provider.ts <route-key> [route-key ...]')
  process.exit(2)
}

const src = readFileSync(`${process.env.HOME}/.dsh/settings.yaml`, 'utf8')
const doc = yaml.load(src, { schema: yaml.DEFAULT_SCHEMA })
const providers = doc?.['llm-pi-ai']?.providers

if (!providers) {
  console.error('FATAL: no llm-pi-ai.providers section in ~/.dsh/settings.yaml')
  process.exit(1)
}

let failed = false

try {
  const parsed = Config({ providers })
  console.log(`OK Config(): providers = ${Object.keys(parsed.providers).join(', ')}`)
  const resolved = resolveProfiles(parsed.providers, 'strict')
  console.log(`OK resolveProfiles(strict): routes = ${[...resolved.keys()].join(', ')}`)

  for (const key of wanted) {
    const profile = resolved.get(key)
    if (!profile) {
      console.error(`FAIL ${key}: route not found`)
      failed = true
      continue
    }
    console.log(`\n=== ${key} ===`)
    console.log(`  displayName   : ${profile.displayName}`)
    console.log(`  baseURL       : ${profile.baseURL}`)
    console.log(`  api           : ${profile.api}`)
    console.log(`  reasoning     : ${JSON.stringify(profile.reasoning)}  (route default)`)
    console.log(`  apiKeyEnv     : ${JSON.stringify(profile.apiKeyEnv)}`)
    console.log(`  compat        : ${JSON.stringify(profile.compat)}`)
    console.log(`  catalogError  : ${profile.catalogError ?? '(none)'}`)
    console.log(`  modelErrors   : ${profile.modelErrors.size === 0 ? '(none)' : JSON.stringify([...profile.modelErrors.entries()])}`)
    if (profile.catalogError || profile.modelErrors.size > 0 || !profile.piProvider) failed = true

    if (!profile.piProvider) {
      console.log('  piProvider    : (absent — route NOT serviceable)')
      continue
    }
    console.log(`  piProvider    : ${profile.piProvider.id}`)

    for (const model of profile.piProvider.getModels()) {
      const thinkingMap = (model as { thinkingLevelMap?: Record<string, unknown> }).thinkingLevelMap
      console.log(`\n  --- model ${model.id} ---`)
      console.log(`    name          : ${model.name}`)
      console.log(`    contextWindow : ${model.contextWindow} | maxTokens: ${model.maxTokens}`)
      console.log(`    input         : ${JSON.stringify(model.input)}`)
      console.log(`    reasoning     : ${model.reasoning}`)
      console.log(`    thinkingMap   : ${JSON.stringify(thinkingMap)}`)
      console.log(`    menu levels   : ${JSON.stringify(getSupportedThinkingLevels(model))}`)
      console.log(`    compat        : ${JSON.stringify((model as { compat?: unknown }).compat)}`)
    }
  }
} catch (err) {
  console.error(`FATAL: ${(err as Error).message}`)
  failed = true
}

process.exit(failed ? 1 : 0)
