import { useState, useEffect } from 'react'
import { useMutation } from '@tanstack/react-query'
import ReactMarkdown from 'react-markdown'
import { Search, FileText, DollarSign, Loader2, Sparkles, X, User, Receipt, CreditCard, AlertCircle, Bot, RefreshCw } from 'lucide-react'
import { api } from '../../lib/api'

interface SimilarCase {
  Id: number
  ScenarioId: string
  TaxYear: number
  ScenarioType: string
  TaxpayerProfile: string
  IncomeSources: string
  Deductions: string
  Credits: string
  SpecialSituations?: string
  ScenarioSummary: string
  SimilarityScore: number
}

// Helper to format values that might be nested objects
function formatValue(value: unknown): string {
  if (value === null || value === undefined) return 'N/A'
  if (typeof value === 'number') return value.toLocaleString()
  if (typeof value === 'boolean') return value ? 'Yes' : 'No'
  if (typeof value === 'string') return value
  if (Array.isArray(value)) return value.map(v => formatValue(v)).join(', ')
  if (typeof value === 'object') {
    // For nested objects, format as key: value pairs
    return Object.entries(value as Record<string, unknown>)
      .map(([k, v]) => `${k}: ${formatValue(v)}`)
      .join(', ')
  }
  return String(value)
}

// Helper to format currency values
function formatCurrency(value: unknown): string {
  if (typeof value === 'number') return `$${value.toLocaleString()}`
  if (typeof value === 'string' && !isNaN(Number(value))) return `$${Number(value).toLocaleString()}`
  return formatValue(value)
}

export default function SimilarCases() {
  const [searchQuery, setSearchQuery] = useState('')
  const [filingStatus, setFilingStatus] = useState<string>('')
  const [results, setResults] = useState<SimilarCase[]>([])
  const [selectedCase, setSelectedCase] = useState<SimilarCase | null>(null)
  const [aiSummary, setAiSummary] = useState<string | null>(null)
  const [summaryFromCache, setSummaryFromCache] = useState(false)
  const [cacheHitCount, setCacheHitCount] = useState(0)

  // AI Summary mutation - generates a RAG-based analysis of the selected case
  const aiSummaryMutation = useMutation({
    mutationFn: async (caseData: SimilarCase) => {
      // First, check if we have a cached summary
      const cached = await api.getCachedCaseSummary(caseData.ScenarioId)
      
      if (cached.isCached && cached.summary) {
        // Return cached summary
        return {
          answer: cached.summary,
          fromCache: true,
          hitCount: cached.hitCount,
        }
      }
      
      // No cache - generate new summary with LLM
      const caseContext = `
Tax Year: ${caseData.TaxYear}
Scenario Type: ${caseData.ScenarioType}
Taxpayer Profile: ${caseData.TaxpayerProfile}
Income Sources: ${caseData.IncomeSources}
Deductions: ${caseData.Deductions}
Credits: ${caseData.Credits}
${caseData.SpecialSituations ? `Special Situations: ${caseData.SpecialSituations}` : ''}
Scenario Summary: ${caseData.ScenarioSummary}
`.trim()

      const prompt = `As a tax professional reviewing this historical case, provide a comprehensive analysis including:
1. **Case Overview** - Brief summary of the taxpayer's situation
2. **Key Income Analysis** - Notable income sources and their tax implications  
3. **Deduction Strategy** - What deductions were claimed and optimization opportunities
4. **Credits Applied** - Tax credits used and eligibility considerations
5. **Risk Factors** - Any audit red flags or compliance concerns
6. **Professional Recommendations** - What a tax preparer should consider for similar cases

Analyze this tax case:
${caseContext}`

      const result = await api.askTaxAssistant(prompt, 'Tax professional reviewing a similar historical case for reference')
      
      // Save to cache for future use
      if (result.answer && !result.answer.startsWith('Sorry')) {
        await api.saveCachedCaseSummary(caseData.ScenarioId, result.answer, 'gpt-5.2-chat')
      }
      
      return {
        answer: result.answer,
        fromCache: false,
        hitCount: 0,
      }
    },
    onSuccess: (data) => {
      setAiSummary(data.answer)
      setSummaryFromCache(data.fromCache)
      setCacheHitCount(data.hitCount)
    },
  })

  // Generate AI summary when a case is selected
  useEffect(() => {
    if (selectedCase) {
      setAiSummary(null) // Reset previous summary
      setSummaryFromCache(false)
      setCacheHitCount(0)
      aiSummaryMutation.mutate(selectedCase)
    }
  }, [selectedCase])

  const searchMutation = useMutation({
    mutationFn: async () => {
      // Server uses SQL Server 2025 AI_GENERATE_EMBEDDINGS to create vectors
      return api.searchSimilarCases(
        searchQuery,
        filingStatus || undefined,
        10
      )
    },
    onSuccess: (data) => {
      // Map the results to our interface
      const mappedResults = (data.results || []).map((r: any) => ({
        ...r,
        // Parse JSON fields if they're strings
        TaxpayerProfile: typeof r.TaxpayerProfile === 'string' ? r.TaxpayerProfile : JSON.stringify(r.TaxpayerProfile),
        IncomeSources: typeof r.IncomeSources === 'string' ? r.IncomeSources : JSON.stringify(r.IncomeSources),
        Deductions: typeof r.Deductions === 'string' ? r.Deductions : JSON.stringify(r.Deductions),
        Credits: typeof r.Credits === 'string' ? r.Credits : JSON.stringify(r.Credits),
      }))
      setResults(mappedResults)
    },
  })

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault()
    if (searchQuery.trim()) {
      searchMutation.mutate()
    }
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-slate-900">Find Similar Cases</h1>
        <p className="text-slate-600 mt-1">
          Use AI-powered vector search to find similar tax scenarios from historical data
        </p>
      </div>

      {/* Search Form */}
      <div className="bg-white rounded-xl border border-slate-200 p-6">
        <form onSubmit={handleSearch} className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-slate-700 mb-2">
              Describe the tax scenario
            </label>
            <textarea
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="e.g., Self-employed individual with home office, multiple 1099 forms, and significant business expenses..."
              className="w-full px-4 py-3 border border-slate-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-blue-500 min-h-[100px]"
            />
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-slate-700 mb-2">
                Filing Status (optional)
              </label>
              <select
                value={filingStatus}
                onChange={(e) => setFilingStatus(e.target.value)}
                className="w-full px-4 py-3 border border-slate-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-blue-500"
              >
                <option value="">Any Filing Status</option>
                <option value="Single">Single</option>
                <option value="Married Filing Jointly">Married Filing Jointly</option>
                <option value="Married Filing Separately">Married Filing Separately</option>
                <option value="Head of Household">Head of Household</option>
              </select>
            </div>
          </div>

          <button
            type="submit"
            disabled={!searchQuery.trim() || searchMutation.isPending}
            className="w-full md:w-auto px-6 py-3 bg-blue-600 text-white rounded-xl font-medium
              hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors
              flex items-center justify-center gap-2"
          >
            {searchMutation.isPending ? (
              <>
                <Loader2 className="w-5 h-5 animate-spin" />
                Searching...
              </>
            ) : (
              <>
                <Search className="w-5 h-5" />
                Find Similar Cases
              </>
            )}
          </button>
        </form>
      </div>

      {/* Results */}
      {results.length > 0 && (
        <div className="space-y-4">
          <h2 className="text-lg font-semibold text-slate-900">
            Found {results.length} Similar Cases
          </h2>
          
          <div className="grid gap-4">
            {results.map((result) => {
              // Parse taxpayer profile to get filing status
              let filingStatusDisplay = 'Unknown'
              try {
                const profile = JSON.parse(result.TaxpayerProfile || '{}')
                filingStatusDisplay = profile.filing_status || 'Unknown'
              } catch { /* ignore */ }
              
              // Calculate similarity as percentage (lower distance = better match)
              const similarityPct = Math.max(0, (1 - (result.SimilarityScore || 0)) * 100)
              
              return (
                <div
                  key={result.Id || result.ScenarioId}
                  onClick={() => setSelectedCase(result)}
                  className="bg-white rounded-xl border border-slate-200 p-6 hover:shadow-md hover:border-blue-300 transition-all cursor-pointer group"
                >
                  <div className="flex items-start justify-between mb-4">
                    <div className="flex items-center gap-3">
                      <div className="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center group-hover:bg-blue-200 transition-colors">
                        <FileText className="w-5 h-5 text-blue-600" />
                      </div>
                      <div>
                        <h3 className="font-semibold text-slate-900 group-hover:text-blue-600 transition-colors">
                          {result.ScenarioType || 'Tax Scenario'}
                        </h3>
                        <p className="text-sm text-slate-500">
                          Tax Year {result.TaxYear} • {filingStatusDisplay}
                        </p>
                      </div>
                    </div>
                    <div className="text-right">
                      <div className="flex items-center gap-1 text-green-600">
                        <Sparkles className="w-4 h-4" />
                        <span className="font-semibold">
                          {similarityPct.toFixed(1)}% match
                        </span>
                      </div>
                      <p className="text-xs text-slate-500 mt-1">
                        ID: {result.ScenarioId}
                      </p>
                    </div>
                  </div>

                  {/* Summary */}
                  {result.ScenarioSummary && (
                    <div className="mb-4 p-3 bg-slate-50 rounded-lg">
                      <p className="text-sm text-slate-700 line-clamp-2">{result.ScenarioSummary}</p>
                    </div>
                  )}

                  <div className="flex flex-wrap gap-2 pt-4 border-t border-slate-100">
                    {(() => {
                      try {
                        const inc = JSON.parse(result.IncomeSources || '{}')
                        return Object.keys(inc).slice(0, 3).map(key => (
                          <span key={key} className="px-2 py-1 bg-green-50 text-green-700 rounded text-xs">
                            {key}
                          </span>
                        ))
                      } catch { return null }
                    })()}
                    {(() => {
                      try {
                        const ded = JSON.parse(result.Deductions || '{}')
                        return Object.keys(ded).slice(0, 2).map(key => (
                          <span key={key} className="px-2 py-1 bg-amber-50 text-amber-700 rounded text-xs">
                            {key}
                          </span>
                        ))
                      } catch { return null }
                    })()}
                    <span className="text-xs text-blue-600 ml-auto opacity-0 group-hover:opacity-100 transition-opacity">
                      Click to view details →
                    </span>
                  </div>
                </div>
              )
            })}
          </div>
        </div>
      )}

      {/* Empty State */}
      {results.length === 0 && !searchMutation.isPending && (
        <div className="bg-slate-50 rounded-xl p-8 text-center">
          <Search className="w-12 h-12 text-slate-300 mx-auto mb-4" />
          <h3 className="text-lg font-medium text-slate-900 mb-2">
            Search for Similar Cases
          </h3>
          <p className="text-slate-600 max-w-md mx-auto">
            Describe a tax scenario above and our AI will find the most similar 
            historical cases using DiskANN vector indexes.
          </p>
        </div>
      )}

      {/* Tech Info */}
      <div className="bg-blue-50 rounded-xl p-4 border border-blue-100">
        <p className="text-sm text-blue-800">
          <strong>Vector Search:</strong> This search uses DiskANN indexes on Azure SQL Hyperscale 
          to perform fast approximate nearest neighbor searches across millions of tax scenarios.
        </p>
      </div>

      {/* Case Detail Modal */}
      {selectedCase && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-xl max-w-4xl w-full max-h-[90vh] overflow-y-auto shadow-2xl">
            <div className="sticky top-0 bg-white border-b border-slate-200 p-4 flex items-center justify-between z-10">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center">
                  <FileText className="w-5 h-5 text-blue-600" />
                </div>
                <div>
                  <h2 className="text-lg font-semibold text-slate-900">
                    {selectedCase.ScenarioType || 'Tax Scenario'}
                  </h2>
                  <p className="text-sm text-slate-500">
                    Tax Year {selectedCase.TaxYear} • ID: {selectedCase.ScenarioId}
                  </p>
                </div>
              </div>
              <button
                onClick={() => {
                  setSelectedCase(null)
                  setAiSummary(null)
                }}
                className="p-2 hover:bg-slate-100 rounded-lg transition-colors"
              >
                <X className="w-5 h-5 text-slate-500" />
              </button>
            </div>
            
            <div className="p-6 space-y-6">
              {/* AI-Generated Analysis Section */}
              <div className="bg-gradient-to-r from-purple-50 to-blue-50 rounded-xl border border-purple-200 overflow-hidden">
                <div className="bg-gradient-to-r from-purple-600 to-blue-600 px-4 py-3 flex items-center justify-between">
                  <div className="flex items-center gap-2 text-white">
                    <Bot className="w-5 h-5" />
                    <span className="font-semibold">AI Case Analysis</span>
                    {summaryFromCache ? (
                      <span className="text-xs bg-green-500/30 px-2 py-0.5 rounded-full flex items-center gap-1">
                        ⚡ Cached {cacheHitCount > 1 && `(${cacheHitCount} views)`}
                      </span>
                    ) : (
                      <span className="text-xs bg-white/20 px-2 py-0.5 rounded-full">RAG + LLM</span>
                    )}
                  </div>
                  {!aiSummaryMutation.isPending && aiSummary && (
                    <button
                      onClick={() => aiSummaryMutation.mutate(selectedCase)}
                      className="p-1 hover:bg-white/20 rounded transition-colors"
                      title="Regenerate analysis"
                    >
                      <RefreshCw className="w-4 h-4 text-white" />
                    </button>
                  )}
                </div>
                <div className="p-4">
                  {aiSummaryMutation.isPending ? (
                    <div className="flex items-center gap-3 text-purple-700 py-8 justify-center">
                      <Loader2 className="w-6 h-6 animate-spin" />
                      <span>
                        {summaryFromCache ? 'Loading cached analysis...' : 'Analyzing case with AI + Knowledge Base...'}
                      </span>
                    </div>
                  ) : aiSummary ? (
                    <div>
                      {summaryFromCache && (
                        <div className="mb-3 text-xs text-green-700 bg-green-100 px-3 py-1.5 rounded-lg inline-flex items-center gap-1">
                          <span>⚡</span> Loaded from cache - instant response
                        </div>
                      )}
                      <div className="prose prose-sm prose-slate max-w-none prose-headings:text-purple-800 prose-headings:font-semibold prose-p:text-slate-700 prose-li:text-slate-700 prose-strong:text-slate-800">
                        <ReactMarkdown>{aiSummary}</ReactMarkdown>
                      </div>
                    </div>
                  ) : aiSummaryMutation.isError ? (
                    <div className="text-red-600 py-4 text-center">
                      <p>Failed to generate AI analysis. Please try again.</p>
                      <button
                        onClick={() => aiSummaryMutation.mutate(selectedCase)}
                        className="mt-2 px-4 py-2 bg-purple-600 text-white rounded-lg hover:bg-purple-700 transition-colors text-sm"
                      >
                        Retry Analysis
                      </button>
                    </div>
                  ) : null}
                </div>
              </div>

              {/* Similarity Score */}
              <div className="flex items-center gap-2 text-green-600 bg-green-50 px-4 py-2 rounded-lg w-fit">
                <Sparkles className="w-5 h-5" />
                <span className="font-semibold">
                  {((1 - (selectedCase.SimilarityScore || 0)) * 100).toFixed(1)}% match
                </span>
              </div>

              {/* Summary */}
              {selectedCase.ScenarioSummary && (
                <div>
                  <h3 className="text-sm font-semibold text-slate-700 mb-2 flex items-center gap-2">
                    <AlertCircle className="w-4 h-4" /> Summary
                  </h3>
                  <p className="text-slate-700 bg-slate-50 p-4 rounded-lg">{selectedCase.ScenarioSummary}</p>
                </div>
              )}

              {/* Taxpayer Profile */}
              {selectedCase.TaxpayerProfile && (
                <div>
                  <h3 className="text-sm font-semibold text-slate-700 mb-2 flex items-center gap-2">
                    <User className="w-4 h-4" /> Taxpayer Profile
                  </h3>
                  <div className="bg-slate-50 p-4 rounded-lg">
                    {(() => {
                      try {
                        const profile = JSON.parse(selectedCase.TaxpayerProfile)
                        return (
                          <div className="grid grid-cols-2 gap-3 text-sm">
                            {Object.entries(profile).map(([key, value]) => (
                              <div key={key} className="flex justify-between">
                                <span className="text-slate-500 capitalize">{key.replace(/_/g, ' ')}:</span>
                                <span className="font-medium text-slate-700">{formatValue(value)}</span>
                              </div>
                            ))}
                          </div>
                        )
                      } catch {
                        return <p className="text-slate-700">{selectedCase.TaxpayerProfile}</p>
                      }
                    })()}
                  </div>
                </div>
              )}

              {/* Income Sources */}
              {selectedCase.IncomeSources && (
                <div>
                  <h3 className="text-sm font-semibold text-slate-700 mb-2 flex items-center gap-2">
                    <DollarSign className="w-4 h-4 text-green-600" /> Income Sources
                  </h3>
                  <div className="bg-green-50 p-4 rounded-lg">
                    {(() => {
                      try {
                        const income = JSON.parse(selectedCase.IncomeSources)
                        return (
                          <div className="space-y-2">
                            {Object.entries(income).map(([key, value]) => (
                              <div key={key} className="flex justify-between text-sm">
                                <span className="text-green-700 capitalize">{key.replace(/_/g, ' ')}</span>
                                <span className="font-semibold text-green-800">
                                  {formatCurrency(value)}
                                </span>
                              </div>
                            ))}
                          </div>
                        )
                      } catch {
                        return <p className="text-green-700">{selectedCase.IncomeSources}</p>
                      }
                    })()}
                  </div>
                </div>
              )}

              {/* Deductions */}
              {selectedCase.Deductions && (
                <div>
                  <h3 className="text-sm font-semibold text-slate-700 mb-2 flex items-center gap-2">
                    <Receipt className="w-4 h-4 text-amber-600" /> Deductions
                  </h3>
                  <div className="bg-amber-50 p-4 rounded-lg">
                    {(() => {
                      try {
                        const deductions = JSON.parse(selectedCase.Deductions)
                        return (
                          <div className="space-y-2">
                            {Object.entries(deductions).map(([key, value]) => (
                              <div key={key} className="flex justify-between text-sm">
                                <span className="text-amber-700 capitalize">{key.replace(/_/g, ' ')}</span>
                                <span className="font-semibold text-amber-800">
                                  {formatCurrency(value)}
                                </span>
                              </div>
                            ))}
                          </div>
                        )
                      } catch {
                        return <p className="text-amber-700">{selectedCase.Deductions}</p>
                      }
                    })()}
                  </div>
                </div>
              )}

              {/* Credits */}
              {selectedCase.Credits && (
                <div>
                  <h3 className="text-sm font-semibold text-slate-700 mb-2 flex items-center gap-2">
                    <CreditCard className="w-4 h-4 text-purple-600" /> Credits
                  </h3>
                  <div className="bg-purple-50 p-4 rounded-lg">
                    {(() => {
                      try {
                        const credits = JSON.parse(selectedCase.Credits)
                        return (
                          <div className="space-y-2">
                            {Object.entries(credits).map(([key, value]) => (
                              <div key={key} className="flex justify-between text-sm">
                                <span className="text-purple-700 capitalize">{key.replace(/_/g, ' ')}</span>
                                <span className="font-semibold text-purple-800">
                                  {formatCurrency(value)}
                                </span>
                              </div>
                            ))}
                          </div>
                        )
                      } catch {
                        return <p className="text-purple-700">{selectedCase.Credits}</p>
                      }
                    })()}
                  </div>
                </div>
              )}

              {/* Special Situations */}
              {selectedCase.SpecialSituations && (
                <div>
                  <h3 className="text-sm font-semibold text-slate-700 mb-2 flex items-center gap-2">
                    <AlertCircle className="w-4 h-4 text-red-600" /> Special Situations
                  </h3>
                  <div className="bg-red-50 p-4 rounded-lg">
                    {(() => {
                      try {
                        const situations = JSON.parse(selectedCase.SpecialSituations)
                        if (Array.isArray(situations)) {
                          return (
                            <ul className="list-disc list-inside text-sm text-red-700 space-y-1">
                              {situations.map((item, i) => <li key={i}>{String(item)}</li>)}
                            </ul>
                          )
                        }
                        return <p className="text-red-700">{JSON.stringify(situations)}</p>
                      } catch {
                        return <p className="text-red-700">{selectedCase.SpecialSituations}</p>
                      }
                    })()}
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
