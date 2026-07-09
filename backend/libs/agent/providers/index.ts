export type {
  FlowHint,
  ProviderConfig,
  ProviderName,
  ProviderOverrideOptions,
  ProviderRuntimeOptions,
  ProviderSelection,
} from './types.js'
export { createAnthropicProvider } from './anthropic.js'
export { createOpenAIProvider } from './openai.js'

import type { ProviderName } from './types.js'
import type { ProviderConfig, ProviderOverrideOptions, ProviderRuntimeOptions, ProviderSelection } from './types.js'
import {
  DEFAULT_LLM_PROVIDER,
  normalizeLlmModel,
  normalizeLlmProvider,
  normalizeReasoningEffortForProvider,
  normalizeServiceTierForProvider,
} from 'shared/llm-config'
import { createAnthropicProvider } from './anthropic.js'
import { createOpenAIProvider } from './openai.js'

type AgentProviderConfig = {
  anthropicApiKey?: string
  openaiApiKey?: string
  openaiBaseUrl?: string
}

export function createProvider(
  name: ProviderName,
  apiKey: string,
  overrides: ProviderOverrideOptions = {},
  runtimeOptions: ProviderRuntimeOptions = {},
  baseURL?: string
): ProviderConfig {
  switch (name) {
    case 'anthropic':
      return createAnthropicProvider(apiKey, overrides)
    case 'openai':
      return createOpenAIProvider(apiKey, overrides, runtimeOptions, baseURL)
    default:
      return assertNever(name)
  }
}

const API_KEY_MAP: Record<ProviderName, keyof AgentProviderConfig> = {
  anthropic: 'anthropicApiKey',
  openai: 'openaiApiKey',
}

const PROVIDER_ENV_KEY_PARTS: Record<ProviderName, string[]> = {
  anthropic: ['ANTHROPIC', 'API', 'KEY'],
  openai: ['OPENAI', 'API', 'KEY'],
}

function providerEnvKey(providerName: ProviderName): string {
  return PROVIDER_ENV_KEY_PARTS[providerName].join('_')
}

function hasValue(value: string | undefined): boolean {
  return Boolean(value && value.trim() !== '')
}

export function hasProviderApiKey(config: AgentProviderConfig, providerName: ProviderName): boolean {
  return hasValue(config[API_KEY_MAP[providerName]])
}

export function getConfiguredProviderNames(config: AgentProviderConfig): ProviderName[] {
  return (Object.keys(API_KEY_MAP) as ProviderName[]).filter((providerName) => hasProviderApiKey(config, providerName))
}

export function hasAnyProviderApiKey(config: AgentProviderConfig): boolean {
  return getConfiguredProviderNames(config).length > 0
}

function resolveProviderName(config: AgentProviderConfig, selection: ProviderSelection): ProviderName {
  const selectedProvider = normalizeLlmProvider(selection.provider)
  if (selectedProvider) {
    return selectedProvider
  }

  if (hasProviderApiKey(config, DEFAULT_LLM_PROVIDER)) {
    return DEFAULT_LLM_PROVIDER
  }

  return getConfiguredProviderNames(config)[0] ?? DEFAULT_LLM_PROVIDER
}

function buildMissingProviderCredentialMessage(providerName: ProviderName, wasExplicitlySelected: boolean): string {
  if (wasExplicitlySelected) {
    return `Missing credential for provider "${providerName}". Set ${providerEnvKey(providerName)} or choose another configured provider.`
  }

  return `AI agent is disabled because no LLM provider credential is configured. Set ${providerEnvKey('openai')} or ${providerEnvKey('anthropic')} to enable AI agent invocations.`
}

/**
 * Create a ProviderConfig from the agent config object.
 * If no provider is selected, prefer the default provider when configured,
 * otherwise fall back to any provider that has credentials.
 */
export function createProviderFromConfig(
  config: AgentProviderConfig,
  selection: ProviderSelection = {},
  runtimeOptions: ProviderRuntimeOptions = {}
): ProviderConfig {
  const normalizedProvider = normalizeLlmProvider(selection.provider)
  const providerName = resolveProviderName(config, selection)
  const keyField = API_KEY_MAP[providerName]
  const apiKey = config[keyField]

  if (!hasValue(apiKey)) {
    throw new Error(buildMissingProviderCredentialMessage(providerName, Boolean(normalizedProvider)))
  }

  const baseURL = providerName === 'openai' ? config.openaiBaseUrl : undefined

  return createProvider(
    providerName,
    apiKey,
    {
      model: normalizeLlmModel(selection.model),
      reasoningEffort: normalizeReasoningEffortForProvider(selection.reasoningEffort, providerName),
      serviceTier: normalizeServiceTierForProvider(selection.serviceTier, providerName),
    },
    runtimeOptions,
    baseURL
  )
}

function assertNever(value: never): never {
  throw new Error(`Unsupported provider: ${value}`)
}
