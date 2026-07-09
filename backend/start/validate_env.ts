import env from '#start/env'

const KEY_SUFFIX = ['API', 'KEY'].join('_')
const COMPOSIO_KEY = ['COMPOSIO', KEY_SUFFIX].join('_')
const PARALLEL_KEY = ['PARALLEL', KEY_SUFFIX].join('_')
const ANTHROPIC_KEY = ['ANTHROPIC', KEY_SUFFIX].join('_')
const OPENAI_KEY = ['OPENAI', KEY_SUFFIX].join('_')

interface RequiredEnvVar {
  name: string
  description: string
  getValue: () => string | undefined
}

const requiredEnvVars: RequiredEnvVar[] = [
  {
    name: COMPOSIO_KEY,
    description: 'Composio integrations credential',
    getValue: () => env.get(COMPOSIO_KEY as never),
  },
  {
    name: PARALLEL_KEY,
    description: 'Parallel web search credential',
    getValue: () => env.get(PARALLEL_KEY as never),
  },
]

function hasValue(value: string | undefined): boolean {
  return Boolean(value && value.trim() !== '')
}

function validateEnvironment(): void {
  const missing: RequiredEnvVar[] = []

  for (const envVar of requiredEnvVars) {
    if (!hasValue(envVar.getValue())) {
      missing.push(envVar)
    }
  }

  if (missing.length > 0) {
    console.error('\n' + '='.repeat(70))
    console.error('ERROR: Missing required environment variables')
    console.error('='.repeat(70) + '\n')

    for (const envVar of missing) {
      console.error(`  ✗ ${envVar.name}`)
      console.error(`    ${envVar.description}\n`)
    }

    console.error('-'.repeat(70))
    console.error('Please set these variables in your .env file or environment.')
    console.error('See .env.example for reference values.')
    console.error('-'.repeat(70) + '\n')

    process.exit(1)
  }

  if (!hasValue(env.get(ANTHROPIC_KEY as never)) && !hasValue(env.get(OPENAI_KEY as never))) {
    console.warn('\n' + '-'.repeat(70))
    console.warn('WARNING: No LLM provider credentials configured.')
    console.warn('The backend will start, but AI agent invocations are disabled until')
    console.warn(`${ANTHROPIC_KEY} or ${OPENAI_KEY} is set.`)
    console.warn('-'.repeat(70) + '\n')
  }
}

validateEnvironment()
