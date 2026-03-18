import { msalInstance, apiScopes, isDevMode } from './auth'
import { 
  getWorkloadType, 
  getReplicaTarget,
  WORKLOAD_HEADER,
  REPLICA_HEADER,
  workloadTracker 
} from './workloadRouting'

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || ''

// Current user role (will be set by auth context)
let currentUserRole = 'authenticated'

/**
 * Set the current user role for workload routing decisions
 */
export function setCurrentUserRole(role: string): void {
  currentUserRole = role
}

/**
 * Get the current user role
 */
export function getCurrentUserRole(): string {
  return currentUserRole
}

// Fire-and-forget ledger logging — never blocks the caller
function logToLedger(params: Record<string, unknown>): void {
  // DAB requires ALL stored-procedure parameters in the request body
  // and does NOT accept null — use type-matching defaults from dab-config.json
  const body = {
    InteractionType: params.InteractionType ?? '',
    UserRole: params.UserRole ?? 'anonymous',
    UserId: params.UserId ?? '',
    BranchId: params.BranchId ?? 0,
    CustomerId: params.CustomerId ?? 0,
    PromptText: params.PromptText ?? '',
    ModelName: params.ModelName ?? '',
    ExternalEndpoint: params.ExternalEndpoint ?? '',
    TokensInput: params.TokensInput ?? 0,
    TokensOutput: params.TokensOutput ?? 0,
    ResponseSummary: params.ResponseSummary ?? '',
    ResultCount: params.ResultCount ?? 0,
    SimilarityScoreAvg: params.SimilarityScoreAvg ?? 0,
    LatencyMs: params.LatencyMs ?? 0,
    HttpStatusCode: params.HttpStatusCode ?? 0,
    ErrorMessage: params.ErrorMessage ?? '',
    IsSuccess: params.IsSuccess === true,
    SessionId: params.SessionId ?? '',
  }
  fetchWithAuth('/api/log-ai-interaction', {
    method: 'POST',
    body: JSON.stringify(body),
  }, 'write').catch(() => { /* swallow — logging must not break the app */ })
}

export interface HyperscaleResourceStats {
  DatabaseName: string
  SnapshotTime: string
  AvgCpuPercent: number | null
  AvgDataIoPercent: number | null
  AvgLogWritePercent: number | null
  AvgMemoryUsagePercent: number | null
  MaxWorkerPercent: number | null
  MaxSessionPercent: number | null
}

async function fetchHyperscaleStats(path: string): Promise<HyperscaleResourceStats | null> {
  try {
    const response = await fetchWithAuth(path, { method: 'POST' }, 'read')
    const data = await response.json()
    
    // DAB wraps stored procedure results in { value: [...] }
    const result = data?.value?.[0] || data?.[0] || data
    
    // Validate that we got a proper stats object with required fields
    if (!result || typeof result !== 'object' || !result.DatabaseName) {
      console.warn(`Invalid hyperscale stats from ${path}:`, result)
      return null
    }
    
    return result
  } catch (error) {
    console.error(`Failed to fetch hyperscale stats from ${path}:`, error)
    return null
  }
}

async function getAccessToken(): Promise<string | null> {
  // In dev mode, we use the DAB simulator which doesn't require a token
  if (isDevMode) {
    return null
  }

  const accounts = msalInstance.getAllAccounts()
  if (accounts.length === 0) {
    throw new Error('No authenticated user')
  }

  try {
    const response = await msalInstance.acquireTokenSilent({
      scopes: apiScopes.dabApi,
      account: accounts[0],
    })
    return response.accessToken
  } catch (error) {
    // If silent acquisition fails, try interactive
    const response = await msalInstance.acquireTokenPopup({
      scopes: apiScopes.dabApi,
    })
    return response.accessToken
  }
}

async function fetchWithAuth(
  url: string, 
  options: RequestInit = {},
  operation: 'read' | 'write' = 'read'
): Promise<Response> {
  const headers = new Headers(options.headers)
  headers.set('Content-Type', 'application/json')
  
  // Determine workload type and add routing headers
  const workloadType = getWorkloadType(currentUserRole, operation, url)
  const replicaTarget = getReplicaTarget(workloadType)
  headers.set(WORKLOAD_HEADER, workloadType)
  headers.set(REPLICA_HEADER, replicaTarget)
  
  // Track routing decision for observability
  workloadTracker.track(currentUserRole, operation, url)
  
  // Only add auth header in production mode
  if (!isDevMode) {
    const token = await getAccessToken()
    if (token) {
      headers.set('Authorization', `Bearer ${token}`)
    }
  } else {
    // For DAB Simulator, use a test role header
    headers.set('X-MS-API-ROLE', 'authenticated')
  }
  
  return fetch(`${API_BASE_URL}${url}`, {
    ...options,
    headers,
  })
}

// REST API client
export const api = {
  // Branches (reads go to replica)
  async getBranches(params?: { filter?: string; orderby?: string; top?: number }) {
    try {
      const searchParams = new URLSearchParams()
      if (params?.filter) searchParams.set('$filter', params.filter)
      if (params?.orderby) searchParams.set('$orderby', params.orderby)
      if (params?.top) searchParams.set('$top', params.top.toString())
      
      const response = await fetchWithAuth(`/api/branches-read?${searchParams}`, {}, 'read')
      if (!response.ok) {
        console.error('Failed to fetch branches:', response.status, response.statusText)
        return { value: [] }
      }
      const data = await response.json()
      return data
    } catch (error) {
      console.error('Error fetching branches:', error)
      return { value: [] }
    }
  },

  async getBranch(id: number) {
    try {
      const response = await fetchWithAuth(`/api/branches-read/BranchId/${id}`, {}, 'read')
      if (!response.ok) {
        console.error('Failed to fetch branch:', response.status, response.statusText)
        return null
      }
      return response.json()
    } catch (error) {
      console.error('Error fetching branch:', error)
      return null
    }
  },

  // Tax Returns (reads go to replica, writes go to primary)
  async getTaxReturns(params?: { filter?: string; orderby?: string }) {
    try {
      const searchParams = new URLSearchParams()
      if (params?.filter) searchParams.set('$filter', params.filter)
      if (params?.orderby) searchParams.set('$orderby', params.orderby)
      
      const response = await fetchWithAuth(`/api/returns-read?${searchParams}`, {}, 'read')
      if (!response.ok) {
        console.error('Failed to fetch tax returns:', response.status, response.statusText)
        return { value: [] }
      }
      return response.json()
    } catch (error) {
      console.error('Error fetching tax returns:', error)
      return { value: [] }
    }
  },

  async checkExistingReturn(customerId: number, taxYear: number): Promise<boolean> {
    try {
      const response = await fetchWithAuth(
        `/api/returns-read?$filter=CustomerId eq ${customerId} and TaxYear eq ${taxYear}`,
        {},
        'read'
      )
      if (!response.ok) {
        console.error('Failed to check existing return:', response.status, response.statusText)
        return false
      }
      const data = await response.json()
      return data.value && data.value.length > 0
    } catch (error) {
      console.error('Error checking existing return:', error)
      return false
    }
  },

  async getTaxReturn(id: number) {
    try {
      const response = await fetchWithAuth(`/api/returns-read/ReturnId/${id}`, {}, 'read')
      if (!response.ok) {
        console.error('Failed to fetch tax return:', response.status, response.statusText)
        return null
      }
      return response.json()
    } catch (error) {
      console.error('Error fetching tax return:', error)
      return null
    }
  },

  async createTaxReturn(data: any) {
    const response = await fetchWithAuth('/api/returns', {
      method: 'POST',
      body: JSON.stringify(data),
    }, 'write')
    if (!response.ok) {
      const error = await response.json().catch(() => ({ message: response.statusText }))
      throw new Error(error.error?.message || error.message || 'Failed to create tax return')
    }
    return response.json()
  },

  async updateTaxReturn(id: number, data: any) {
    const response = await fetchWithAuth(`/api/returns/ReturnId/${id}`, {
      method: 'PATCH',
      body: JSON.stringify(data),
    }, 'write')
    if (!response.ok) {
      const error = await response.json().catch(() => ({ message: response.statusText }))
      throw new Error(error.error?.message || error.message || 'Failed to update tax return')
    }
    return response.json()
  },

  // Submit a tax return (triggers PopulateFilingDetails to generate all detail records)
  async submitTaxReturn(returnId: number) {
    const response = await fetchWithAuth('/api/submit-return', {
      method: 'POST',
      body: JSON.stringify({ ReturnId: returnId }),
    }, 'write')
    if (!response.ok) {
      const error = await response.json().catch(() => ({ message: response.statusText }))
      throw new Error(error.error?.message || error.message || 'Failed to submit tax return')
    }
    return response.json()
  },

  // Customers (reads go to replica, writes go to primary)
  async getCustomers(params?: { filter?: string }) {
    try {
      const searchParams = new URLSearchParams()
      if (params?.filter) searchParams.set('$filter', params.filter)
      
      const response = await fetchWithAuth(`/api/customers-read?${searchParams}`, {}, 'read')
      if (!response.ok) {
        console.error('Failed to fetch customers:', response.status, response.statusText)
        return { value: [] }
      }
      return response.json()
    } catch (error) {
      console.error('Error fetching customers:', error)
      return { value: [] }
    }
  },

  async getCustomer(id: number) {
    try {
      const response = await fetchWithAuth(`/api/customers-read/CustomerId/${id}`, {}, 'read')
      if (!response.ok) {
        console.error('Failed to fetch customer:', response.status, response.statusText)
        return null
      }
      return response.json()
    } catch (error) {
      console.error('Error fetching customer:', error)
      return null
    }
  },

  async createCustomer(data: any) {
    const response = await fetchWithAuth('/api/customers', {
      method: 'POST',
      body: JSON.stringify(data),
    }, 'write')
    if (!response.ok) {
      const error = await response.json().catch(() => ({ message: response.statusText }))
      throw new Error(error.error?.message || error.message || 'Failed to create customer')
    }
    return response.json()
  },

  async updateCustomer(id: number, data: any) {
    const response = await fetchWithAuth(`/api/customers/CustomerId/${id}`, {
      method: 'PATCH',
      body: JSON.stringify(data),
    }, 'write')
    return response.json()
  },

  // AI/Search endpoints (READ operations - use replica for vector search workloads)
  async askTaxQuestion(question: string, topK: number = 5) {
    const start = performance.now()
    try {
      const response = await fetchWithAuth('/api/ai-ask', {
        method: 'POST',
        body: JSON.stringify({ Question: question, TopK: topK }),
      }, 'read') // Vector search uses read replica
      const latency = Math.round(performance.now() - start)
      if (!response.ok) {
        console.error('Failed to ask tax question:', response.status, response.statusText)
        logToLedger({ InteractionType: 'RAG_Search', UserRole: currentUserRole, PromptText: question,
          ModelName: 'text-embedding-3-small', LatencyMs: latency, HttpStatusCode: response.status,
          ErrorMessage: response.statusText, IsSuccess: false })
        return { sources: [] }
      }
      const data = await response.json()
      const result = data.value || data
      const sources = Array.isArray(result) ? result : []
      logToLedger({ InteractionType: 'RAG_Search', UserRole: currentUserRole, PromptText: question,
        ModelName: 'text-embedding-3-small', ResultCount: sources.length,
        LatencyMs: latency, HttpStatusCode: 200, IsSuccess: true })
      return { sources }
    } catch (error) {
      console.error('Error asking tax question:', error)
      logToLedger({ InteractionType: 'RAG_Search', UserRole: currentUserRole, PromptText: question,
        ModelName: 'text-embedding-3-small', LatencyMs: Math.round(performance.now() - start),
        HttpStatusCode: 0, ErrorMessage: String(error), IsSuccess: false })
      return { sources: [] }
    }
  },

  // RAG + LLM augmented assistant (READ - uses read replica)
  async askTaxAssistant(question: string, context?: string, topK: number = 3) {
    const start = performance.now()
    try {
      const response = await fetchWithAuth('/api/ai-assistant', {
        method: 'POST',
        body: JSON.stringify({ 
          Question: question, 
          Context: context || null,
          TopK: topK 
        }),
      }, 'read') // AI assistant uses read replica
      const latency = Math.round(performance.now() - start)
      if (!response.ok) {
        console.error('Failed to ask tax assistant:', response.status, response.statusText)
        logToLedger({ InteractionType: 'ChatCompletion', UserRole: currentUserRole, PromptText: question,
          ModelName: 'gpt-5.2-chat', LatencyMs: latency, HttpStatusCode: response.status,
          ErrorMessage: response.statusText, IsSuccess: false })
        return {
          answer: 'Sorry, the assistant is temporarily unavailable. Please try again.',
          sourceContent: '',
          isLLMAugmented: false,
        }
      }
      const data = await response.json()
      const result = data.value?.[0] || data[0] || data
      const answer = result.Answer || result.answer || 'Sorry, I could not generate a response.'
      logToLedger({ InteractionType: 'ChatCompletion', UserRole: currentUserRole, PromptText: question,
        ModelName: 'gpt-5.2-chat', ResponseSummary: answer.substring(0, 500),
        LatencyMs: latency, HttpStatusCode: 200, IsSuccess: true })
      return {
        answer,
        sourceContent: result.SourceContent || result.sourceContent || '',
        isLLMAugmented: result.IsLLMAugmented || result.isLLMAugmented || false,
      }
    } catch (error) {
      console.error('Error asking tax assistant:', error)
      logToLedger({ InteractionType: 'ChatCompletion', UserRole: currentUserRole, PromptText: question,
        ModelName: 'gpt-5.2-chat', LatencyMs: Math.round(performance.now() - start),
        HttpStatusCode: 0, ErrorMessage: String(error), IsSuccess: false })
      return {
        answer: 'Sorry, the assistant encountered an error. Please try again.',
        sourceContent: '',
        isLLMAugmented: false,
      }
    }
  },

  async searchKnowledge(embedding: number[], topK: number = 5) {
    const start = performance.now()
    try {
      // DAB stored proc expects embedding as JSON string
      const response = await fetchWithAuth('/api/search-knowledge', {
        method: 'POST',
        body: JSON.stringify({ EmbeddingJson: JSON.stringify(embedding), TopK: topK }),
      }, 'read') // Vector search uses read replica
      const latency = Math.round(performance.now() - start)
      if (!response.ok) {
        console.error('Failed to search knowledge:', response.status, response.statusText)
        logToLedger({ InteractionType: 'RAG_Search', UserRole: currentUserRole,
          ModelName: 'text-embedding-3-small', LatencyMs: latency, HttpStatusCode: response.status,
          ErrorMessage: response.statusText, IsSuccess: false })
        return { results: [] }
      }
      const data = await response.json()
      const result = data.value || data
      const results = Array.isArray(result) ? result : []
      logToLedger({ InteractionType: 'RAG_Search', UserRole: currentUserRole,
        ModelName: 'text-embedding-3-small', ResultCount: results.length,
        LatencyMs: latency, HttpStatusCode: 200, IsSuccess: true })
      return { results }
    } catch (error) {
      console.error('Error searching knowledge:', error)
      logToLedger({ InteractionType: 'RAG_Search', UserRole: currentUserRole,
        ModelName: 'text-embedding-3-small', LatencyMs: Math.round(performance.now() - start),
        HttpStatusCode: 0, ErrorMessage: String(error), IsSuccess: false })
      return { results: [] }
    }
  },

  async searchSimilarCases(query: string, filingStatus?: string, topK: number = 10) {
    const start = performance.now()
    try {
      // Uses SQL Server 2025 AI_GENERATE_EMBEDDINGS on the server side
      const response = await fetchWithAuth('/api/search-cases', {
        method: 'POST',
        body: JSON.stringify({ 
          Query: query, 
          FilingStatus: filingStatus || null,
          TopK: topK 
        }),
      }, 'read') // Vector search uses read replica
      const latency = Math.round(performance.now() - start)
      if (!response.ok) {
        console.error('Failed to search similar cases:', response.status, response.statusText)
        logToLedger({ InteractionType: 'RAG_Search', UserRole: currentUserRole, PromptText: query,
          ModelName: 'text-embedding-3-small', LatencyMs: latency, HttpStatusCode: response.status,
          ErrorMessage: response.statusText, IsSuccess: false })
        return { results: [] }
      }
      const data = await response.json()
      const result = data.value || data
      const results = Array.isArray(result) ? result : []
      logToLedger({ InteractionType: 'RAG_Search', UserRole: currentUserRole, PromptText: query,
        ModelName: 'text-embedding-3-small', ResultCount: results.length,
        LatencyMs: latency, HttpStatusCode: 200, IsSuccess: true })
      return { results }
    } catch (error) {
      console.error('Error searching similar cases:', error)
      logToLedger({ InteractionType: 'RAG_Search', UserRole: currentUserRole, PromptText: query,
        ModelName: 'text-embedding-3-small', LatencyMs: Math.round(performance.now() - start),
        HttpStatusCode: 0, ErrorMessage: String(error), IsSuccess: false })
      return { results: [] }
    }
  },

  // Text-based search (fallback without embeddings) - uses read replica
  async searchKnowledgeText(searchText: string, topK: number = 5) {
    const start = performance.now()
    try {
      const response = await fetchWithAuth('/api/search-text', {
        method: 'POST',
        body: JSON.stringify({ SearchText: searchText, TopN: topK }),
      }, 'read')
      const latency = Math.round(performance.now() - start)
      if (!response.ok) {
        console.error('Failed to search knowledge text:', response.status, response.statusText)
        logToLedger({ InteractionType: 'RAG_Search', UserRole: currentUserRole, PromptText: searchText,
          LatencyMs: latency, HttpStatusCode: response.status,
          ErrorMessage: response.statusText, IsSuccess: false })
        return { results: [] }
      }
      const data = await response.json()
      const result = data.value || data
      const results = Array.isArray(result) ? result : []
      logToLedger({ InteractionType: 'RAG_Search', UserRole: currentUserRole, PromptText: searchText,
        ResultCount: results.length,
        LatencyMs: latency, HttpStatusCode: 200, IsSuccess: true })
      return { results }
    } catch (error) {
      console.error('Error searching knowledge text:', error)
      logToLedger({ InteractionType: 'RAG_Search', UserRole: currentUserRole, PromptText: searchText,
        LatencyMs: Math.round(performance.now() - start),
        HttpStatusCode: 0, ErrorMessage: String(error), IsSuccess: false })
      return { results: [] }
    }
  },

  // Case Summary Cache - avoid repeated LLM calls (READ uses replica, WRITE uses primary)
  async getCachedCaseSummary(scenarioId: string) {
    try {
      // Note: DAB stored procedures use exact parameter names (ScenarioId, not scenarioId)
      const response = await fetchWithAuth(`/api/case-summary-cache?ScenarioId=${encodeURIComponent(scenarioId)}`, {}, 'read')
      if (!response.ok) {
        console.error('Failed to get cached case summary:', response.status, response.statusText)
        return {
          scenarioId,
          summary: null,
          model: null,
          generatedAt: null,
          hitCount: 0,
          isCached: false,
        }
      }
      const data = await response.json()
      const result = data.value?.[0] || data[0] || data
      
      // Handle IsCached: SQL BIT can come as 0/1 (int) or true/false (boolean) or "0"/"1" (string)
      const isCached = result.IsCached === 1 || result.IsCached === true || result.IsCached === '1' ||
                       result.isCached === 1 || result.isCached === true || result.isCached === '1'
      
      return {
        scenarioId: result.ScenarioId || result.scenarioId,
        summary: result.Summary || result.summary || null,
        model: result.Model || result.model,
        generatedAt: result.GeneratedAt || result.generatedAt,
        hitCount: result.HitCount || result.hitCount || 0,
        isCached: isCached && !!(result.Summary || result.summary),
      }
    } catch (error) {
      console.error('Error getting cached case summary:', error)
      return {
        scenarioId,
        summary: null,
        model: null,
        generatedAt: null,
        hitCount: 0,
        isCached: false,
      }
    }
  },

  async saveCachedCaseSummary(scenarioId: string, summary: string, model: string = 'gpt-5.2-chat') {
    try {
      const response = await fetchWithAuth('/api/case-summary-cache-save', {
        method: 'POST',
        body: JSON.stringify({ 
          ScenarioId: scenarioId, 
          Summary: summary,
          Model: model 
        }),
      }, 'write') // Cache write uses primary
      if (!response.ok) {
        console.error('Failed to save cached case summary:', response.status, response.statusText)
        return { saved: false, data: null }
      }
      const data = await response.json()
      return { saved: true, data: data.value?.[0] || data }
    } catch (error) {
      console.error('Error saving cached case summary:', error)
      return { saved: false, data: null }
    }
  },

  // =========================================================================
  // Analytics (routed to Hyperscale Named Replica via CCI analytical queries)
  // =========================================================================

  async getBranchAnalytics(branchId: number = 1, taxYear?: number) {
    try {
      const body: any = { BranchId: branchId }
      if (taxYear) {
        body.TaxYear = taxYear
      }
      const response = await fetchWithAuth('/api/analytics-branch', {
        method: 'POST',
        body: JSON.stringify(body),
      }, 'read')
      if (!response.ok) {
        console.error('Failed to fetch branch analytics:', response.status, response.statusText)
        return null
      }
      const data = await response.json()
      return data.value?.[0] || data[0] || data
    } catch (error) {
      console.error('Error fetching branch analytics:', error)
      return null
    }
  },

  async getBranchLeaderboard(branchId: number = 1, taxYear?: number) {
    try {
      const body: any = { BranchId: branchId }
      if (taxYear) {
        body.TaxYear = taxYear
      }
      const response = await fetchWithAuth('/api/analytics-leaderboard', {
        method: 'POST',
        body: JSON.stringify(body),
      }, 'read')
      if (!response.ok) {
        console.error('Failed to fetch branch leaderboard:', response.status, response.statusText)
        return []
      }
      const data = await response.json()
      const result = data.value || data
      return Array.isArray(result) ? result : []
    } catch (error) {
      console.error('Error fetching branch leaderboard:', error)
      return []
    }
  },

  async getExecutiveKPIs(taxYear?: number) {
    try {
      const body: Record<string, number> = {}
      if (taxYear) body.TaxYear = taxYear
      const response = await fetchWithAuth('/api/analytics-executive-kpis', {
        method: 'POST',
        body: JSON.stringify(body),
      }, 'read')
      if (!response.ok) {
        console.error('Failed to fetch executive KPIs:', response.status, response.statusText)
        return null
      }
      const data = await response.json()
      return data.value?.[0] || data[0] || data
    } catch (error) {
      console.error('Error fetching executive KPIs:', error)
      return null
    }
  },

  async getTopBranches(topN: number = 10, taxYear?: number) {
    try {
      const body: Record<string, number> = { TopN: topN }
      if (taxYear) body.TaxYear = taxYear
      const response = await fetchWithAuth('/api/analytics-top-branches', {
        method: 'POST',
        body: JSON.stringify(body),
      }, 'read')
      if (!response.ok) {
        console.error('Failed to fetch top branches:', response.status, response.statusText)
        return []
      }
      const data = await response.json()
      const result = data.value || data
      return Array.isArray(result) ? result : []
    } catch (error) {
      console.error('Error fetching top branches:', error)
      return []
    }
  },

  async getFilingStatusDistribution(taxYear?: number) {
    try {
      const body: Record<string, number> = {}
      if (taxYear) body.TaxYear = taxYear
      const response = await fetchWithAuth('/api/analytics-filing-status', {
        method: 'POST',
        body: JSON.stringify(body),
      }, 'read')
      if (!response.ok) {
        console.error('Failed to fetch filing status distribution:', response.status, response.statusText)
        return []
      }
      const data = await response.json()
      const result = data.value || data
      return Array.isArray(result) ? result : []
    } catch (error) {
      console.error('Error fetching filing status distribution:', error)
      return []
    }
  },

  async getReturnsByYear() {
    try {
      const response = await fetchWithAuth('/api/analytics-returns-by-year', {
        method: 'POST',
      }, 'read')
      if (!response.ok) {
        console.error('Failed to fetch returns by year:', response.status, response.statusText)
        return []
      }
      const data = await response.json()
      const result = data.value || data
      return Array.isArray(result) ? result : []
    } catch (error) {
      console.error('Error fetching returns by year:', error)
      return []
    }
  },

  async getReplicaIdentity() {
    try {
      const response = await fetchWithAuth('/api/analytics-replica-info', {
        method: 'POST',
      }, 'read')
      if (!response.ok) {
        console.error('Failed to get replica identity:', response.status, response.statusText)
        return null
      }
      const data = await response.json()
      return data.value?.[0] || data[0] || data
    } catch (error) {
      console.error('Error getting replica identity:', error)
      return null
    }
  },

  // =========================================================================
  // Filing Detail Analytics (new P0+P1 tables — named replica NCCI queries)
  // =========================================================================

  async getFilingDetailOverview(taxYear?: number) {
    try {
      const body: any = {}
      if (taxYear) body.TaxYear = taxYear
      const response = await fetchWithAuth('/api/analytics-filing-overview', {
        method: 'POST',
        body: JSON.stringify(body),
      }, 'read')
      if (!response.ok) {
        console.error('Failed to fetch filing detail overview:', response.status, response.statusText)
        return null
      }
      const data = await response.json()
      return data.value?.[0] || data[0] || data
    } catch (error) {
      console.error('Error fetching filing detail overview:', error)
      return null
    }
  },

  async getEFileStatusSummary(taxYear?: number) {
    try {
      const body: any = {}
      if (taxYear) body.TaxYear = taxYear
      const response = await fetchWithAuth('/api/analytics-efile-status', {
        method: 'POST',
        body: JSON.stringify(body),
      }, 'read')
      if (!response.ok) {
        console.error('Failed to fetch e-file status summary:', response.status, response.statusText)
        return []
      }
      const data = await response.json()
      const result = data.value || data
      return Array.isArray(result) ? result : []
    } catch (error) {
      console.error('Error fetching e-file status summary:', error)
      return []
    }
  },

  async getW2Summary(taxYear?: number, branchId?: number) {
    try {
      const body: any = {}
      if (taxYear) body.TaxYear = taxYear
      if (branchId) body.BranchId = branchId
      const response = await fetchWithAuth('/api/analytics-w2-summary', {
        method: 'POST',
        body: JSON.stringify(body),
      }, 'read')
      if (!response.ok) {
        console.error('Failed to fetch W-2 summary:', response.status, response.statusText)
        return null
      }
      const data = await response.json()
      return data.value?.[0] || data[0] || data
    } catch (error) {
      console.error('Error fetching W-2 summary:', error)
      return null
    }
  },

  async getForm1099Summary(taxYear?: number) {
    try {
      const body: any = {}
      if (taxYear) body.TaxYear = taxYear
      const response = await fetchWithAuth('/api/analytics-1099-summary', {
        method: 'POST',
        body: JSON.stringify(body),
      }, 'read')
      if (!response.ok) {
        console.error('Failed to fetch 1099 summary:', response.status, response.statusText)
        return []
      }
      const data = await response.json()
      const result = data.value || data
      return Array.isArray(result) ? result : []
    } catch (error) {
      console.error('Error fetching 1099 summary:', error)
      return []
    }
  },

  async getCapitalGainsSummary(taxYear?: number) {
    try {
      const body: any = {}
      if (taxYear) body.TaxYear = taxYear
      const response = await fetchWithAuth('/api/analytics-capital-gains', {
        method: 'POST',
        body: JSON.stringify(body),
      }, 'read')
      if (!response.ok) {
        console.error('Failed to fetch capital gains summary:', response.status, response.statusText)
        return null
      }
      const data = await response.json()
      return data.value?.[0] || data[0] || data
    } catch (error) {
      console.error('Error fetching capital gains summary:', error)
      return null
    }
  },

  async getScheduleCSummary(taxYear?: number) {
    try {
      const body: any = {}
      if (taxYear) body.TaxYear = taxYear
      const response = await fetchWithAuth('/api/analytics-schedule-c', {
        method: 'POST',
        body: JSON.stringify(body),
      }, 'read')
      if (!response.ok) {
        console.error('Failed to fetch Schedule C summary:', response.status, response.statusText)
        return null
      }
      const data = await response.json()
      return data.value?.[0] || data[0] || data
    } catch (error) {
      console.error('Error fetching Schedule C summary:', error)
      return null
    }
  },

  async getStateTaxSummary(taxYear?: number) {
    try {
      const body: any = {}
      if (taxYear) body.TaxYear = taxYear
      const response = await fetchWithAuth('/api/analytics-state-tax', {
        method: 'POST',
        body: JSON.stringify(body),
      }, 'read')
      if (!response.ok) {
        console.error('Failed to fetch state tax summary:', response.status, response.statusText)
        return []
      }
      const data = await response.json()
      const result = data.value || data
      return Array.isArray(result) ? result : []
    } catch (error) {
      console.error('Error fetching state tax summary:', error)
      return []
    }
  },

  async getScheduleESummary(taxYear?: number) {
    try {
      const body: any = {}
      if (taxYear) body.TaxYear = taxYear
      const response = await fetchWithAuth('/api/analytics-schedule-e', {
        method: 'POST',
        body: JSON.stringify(body),
      }, 'read')
      if (!response.ok) {
        console.error('Failed to fetch Schedule E summary:', response.status, response.statusText)
        return null
      }
      const data = await response.json()
      return data.value?.[0] || data[0] || data
    } catch (error) {
      console.error('Error fetching Schedule E summary:', error)
      return null
    }
  },

  async getScheduleBSummary(taxYear?: number) {
    try {
      const body: any = {}
      if (taxYear) body.TaxYear = taxYear
      const response = await fetchWithAuth('/api/analytics-schedule-b', {
        method: 'POST',
        body: JSON.stringify(body),
      }, 'read')
      if (!response.ok) {
        console.error('Failed to fetch Schedule B summary:', response.status, response.statusText)
        return null
      }
      const data = await response.json()
      return data.value?.[0] || data[0] || data
    } catch (error) {
      console.error('Error fetching Schedule B summary:', error)
      return null
    }
  },

  async getDocumentSummary(taxYear?: number) {
    try {
      const body: any = {}
      if (taxYear) body.TaxYear = taxYear
      const response = await fetchWithAuth('/api/analytics-documents', {
        method: 'POST',
        body: JSON.stringify(body),
      }, 'read')
      if (!response.ok) {
        console.error('Failed to fetch document summary:', response.status, response.statusText)
        return null
      }
      const data = await response.json()
      return data.value?.[0] || data[0] || data
    } catch (error) {
      console.error('Error fetching document summary:', error)
      return null
    }
  },

  // Legacy wrappers (keep for backwards compatibility)
  async getBranchPerformance() {
    return this.getBranchAnalytics()
  },

  async getExecutiveDashboard() {
    return this.getExecutiveKPIs()
  },

  // =========================================================================
  // Security Demo Endpoints
  // =========================================================================

  async getSecurityOverview() {
    try {
      const response = await fetchWithAuth('/api/security-overview', { method: 'POST' }, 'read')
      if (!response.ok) {
        console.error('Failed to fetch security overview:', response.status)
        return null
      }
      const data = await response.json()
      return data.value || data
    } catch (error) {
      console.error('Error fetching security overview:', error)
      return null
    }
  },

  async getSecurityRLSDemo() {
    try {
      const response = await fetchWithAuth('/api/security-rls', { method: 'POST' }, 'read')
      if (!response.ok) {
        console.error('Failed to fetch RLS demo:', response.status)
        return []
      }
      const data = await response.json()
      const result = data.value || data
      return Array.isArray(result) ? result : []
    } catch (error) {
      console.error('Error fetching RLS demo:', error)
      return []
    }
  },

  async getSecurityDDMDemo() {
    try {
      const response = await fetchWithAuth('/api/security-ddm', { method: 'POST' }, 'read')
      if (!response.ok) {
        console.error('Failed to fetch DDM demo:', response.status)
        return []
      }
      const data = await response.json()
      const result = data.value || data
      return Array.isArray(result) ? result : []
    } catch (error) {
      console.error('Error fetching DDM demo:', error)
      return []
    }
  },

  async getSecurityLedger() {
    try {
      const response = await fetchWithAuth('/api/security-ledger', { method: 'POST' }, 'read')
      if (!response.ok) {
        console.error('Failed to fetch ledger info:', response.status)
        return null
      }
      const data = await response.json()
      return data.value || data
    } catch (error) {
      console.error('Error fetching ledger info:', error)
      return null
    }
  },

  async getSecurityClassification() {
    try {
      const response = await fetchWithAuth('/api/security-classification', { method: 'POST' }, 'read')
      if (!response.ok) {
        console.error('Failed to fetch classification:', response.status)
        return []
      }
      const data = await response.json()
      const result = data.value || data
      return Array.isArray(result) ? result : []
    } catch (error) {
      console.error('Error fetching classification:', error)
      return []
    }
  },

  // DevOps (READ - uses named replica for monitoring)
  async getHyperscaleResourceStatsAll(): Promise<{
    primary: HyperscaleResourceStats | null
    readOnly: HyperscaleResourceStats | null
    analytics: HyperscaleResourceStats | null
  }> {
    const [primary, readOnly, analytics] = await Promise.all([
      fetchHyperscaleStats('/api/hyperscale-stats-primary'),
      fetchHyperscaleStats('/api/hyperscale-stats-read'),
      fetchHyperscaleStats('/api/hyperscale-stats-analytics'),
    ])

    return { primary, readOnly, analytics }
  },

  // Legacy wrapper (kept for backwards compatibility)
  async getHyperscaleMetrics() {
    return this.getHyperscaleResourceStatsAll()
  },

  // Tax Professionals (reads go to replica)
  async getProfessionals(branchId?: number) {
    try {
      const searchParams = new URLSearchParams()
      if (branchId) searchParams.set('$filter', `BranchId eq ${branchId}`)
      
      const response = await fetchWithAuth(`/api/professionals-read?${searchParams}`, {}, 'read')
      if (!response.ok) {
        console.error('Failed to fetch professionals:', response.status, response.statusText)
        return { value: [] }
      }
      return response.json()
    } catch (error) {
      console.error('Error fetching professionals:', error)
      return { value: [] }
    }
  },

  // Scenarios (reads go to replica)
  async getScenarios(params?: { filter?: string; top?: number }) {
    try {
      const searchParams = new URLSearchParams()
      if (params?.filter) searchParams.set('$filter', params.filter)
      if (params?.top) searchParams.set('$top', params.top.toString())
      
      const response = await fetchWithAuth(`/api/scenarios-read?${searchParams}`, {}, 'read')
      if (!response.ok) {
        console.error('Failed to fetch scenarios:', response.status, response.statusText)
        return { value: [] }
      }
      return response.json()
    } catch (error) {
      console.error('Error fetching scenarios:', error)
      return { value: [] }
    }
  },
}

// GraphQL client for more complex queries (READ operations)
export async function graphqlQuery<T>(query: string, variables?: Record<string, any>): Promise<T> {
  const response = await fetchWithAuth('/graphql', {
    method: 'POST',
    body: JSON.stringify({ query, variables }),
  }, 'read')
  
  const result = await response.json()
  
  if (result.errors) {
    throw new Error(result.errors[0].message)
  }
  
  return result.data
}
