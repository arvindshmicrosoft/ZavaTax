import { useState } from 'react'
import { useMutation } from '@tanstack/react-query'
import { BookOpen, Search, FileText, Tag, Loader2, X, ExternalLink } from 'lucide-react'
import { api } from '../../lib/api'

export default function KnowledgeBase() {
  const [searchQuery, setSearchQuery] = useState('')
  const [results, setResults] = useState<any[]>([])
  const [selectedArticle, setSelectedArticle] = useState<any | null>(null)

  const searchMutation = useMutation({
    mutationFn: async (question: string) => {
      return api.askTaxQuestion(question, 5)
    },
    onSuccess: (data) => {
      setResults(data.sources || [])
    },
  })

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault()
    if (searchQuery.trim()) {
      searchMutation.mutate(searchQuery)
    }
  }

  const categories = [
    { name: 'Deductions', count: 156, color: 'bg-green-100 text-green-700' },
    { name: 'Credits', count: 89, color: 'bg-blue-100 text-blue-700' },
    { name: 'Income', count: 124, color: 'bg-amber-100 text-amber-700' },
    { name: 'Filing Status', count: 45, color: 'bg-purple-100 text-purple-700' },
    { name: 'Self-Employment', count: 78, color: 'bg-red-100 text-red-700' },
    { name: 'Investments', count: 92, color: 'bg-indigo-100 text-indigo-700' },
  ]

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-slate-900">Knowledge Base</h1>
        <p className="text-slate-600 mt-1">
          Search tax regulations, guidelines, and best practices
        </p>
      </div>

      {/* Search */}
      <div className="bg-white rounded-xl border border-slate-200 p-6">
        <form onSubmit={handleSearch} className="flex gap-2">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-400" />
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="Ask a question or search for topics..."
              className="w-full pl-10 pr-4 py-3 border border-slate-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>
          <button
            type="submit"
            disabled={!searchQuery.trim() || searchMutation.isPending}
            className="px-6 py-3 bg-blue-600 text-white rounded-xl font-medium
              hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors
              flex items-center gap-2"
          >
            {searchMutation.isPending ? (
              <Loader2 className="w-5 h-5 animate-spin" />
            ) : (
              <Search className="w-5 h-5" />
            )}
            Search
          </button>
        </form>
      </div>

      {/* Results */}
      {results.length > 0 && (
        <div className="space-y-4">
          <h2 className="text-lg font-semibold text-slate-900">
            Search Results ({results.length})
          </h2>
          
          <div className="space-y-4">
            {results.map((result: any, index: number) => (
              <div
                key={index}
                onClick={() => setSelectedArticle(result)}
                className="bg-white rounded-xl border border-slate-200 p-6 hover:shadow-md hover:border-blue-300 transition-all cursor-pointer group"
              >
                <div className="flex items-start gap-4">
                  <div className="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center flex-shrink-0 group-hover:bg-blue-200 transition-colors">
                    <FileText className="w-5 h-5 text-blue-600" />
                  </div>
                  <div className="flex-1">
                    <div className="flex items-center gap-2 mb-2">
                      <h3 className="font-semibold text-slate-900 group-hover:text-blue-600 transition-colors">
                        {result.Title || result.Section || `Document ${index + 1}`}
                      </h3>
                      <ExternalLink className="w-4 h-4 text-slate-400 opacity-0 group-hover:opacity-100 transition-opacity" />
                    </div>
                    <p className="text-slate-600 text-sm mb-3">
                      {(result.Content || result.Answer || '')?.substring(0, 300)}
                      {(result.Content || result.Answer || '').length > 300 ? '...' : ''}
                    </p>
                    <div className="flex items-center gap-2">
                      {(result.Category || result.Source) && (
                        <span className="px-2 py-1 bg-slate-100 text-slate-600 rounded text-xs">
                          {result.Category || result.Source}
                        </span>
                      )}
                      {result.SimilarityScore != null && (
                        <span className="text-xs text-green-600">
                          {((1 - result.SimilarityScore) * 100).toFixed(0)}% relevant
                        </span>
                      )}
                      <span className="text-xs text-blue-600 ml-auto opacity-0 group-hover:opacity-100 transition-opacity">
                        Click to view full article →
                      </span>
                    </div>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Article Detail Modal */}
      {selectedArticle && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4" onClick={() => setSelectedArticle(null)}>
          <div 
            className="bg-white rounded-2xl max-w-3xl w-full max-h-[85vh] overflow-hidden shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            {/* Modal Header */}
            <div className="flex items-start justify-between p-6 border-b border-slate-200 bg-slate-50">
              <div className="flex items-start gap-4">
                <div className="w-12 h-12 bg-blue-100 rounded-xl flex items-center justify-center flex-shrink-0">
                  <FileText className="w-6 h-6 text-blue-600" />
                </div>
                <div>
                  <h2 className="text-xl font-bold text-slate-900">
                    {selectedArticle.Title || selectedArticle.Section || 'Article Details'}
                  </h2>
                  <div className="flex items-center gap-2 mt-2">
                    {(selectedArticle.Category || selectedArticle.Source) && (
                      <span className="px-2 py-1 bg-blue-100 text-blue-700 rounded text-xs font-medium">
                        {selectedArticle.Category || selectedArticle.Source}
                      </span>
                    )}
                    {selectedArticle.SimilarityScore != null && (
                      <span className="px-2 py-1 bg-green-100 text-green-700 rounded text-xs font-medium">
                        {((1 - selectedArticle.SimilarityScore) * 100).toFixed(0)}% relevant
                      </span>
                    )}
                  </div>
                </div>
              </div>
              <button 
                onClick={() => setSelectedArticle(null)}
                className="p-2 hover:bg-slate-200 rounded-lg transition-colors"
              >
                <X className="w-5 h-5 text-slate-500" />
              </button>
            </div>
            
            {/* Modal Body */}
            <div className="p-6 overflow-y-auto max-h-[60vh]">
              <div className="prose prose-slate max-w-none">
                <p className="text-slate-700 leading-relaxed whitespace-pre-wrap">
                  {selectedArticle.Content || selectedArticle.Answer || 'No content available.'}
                </p>
              </div>
              
              {/* Additional metadata if available */}
              {(selectedArticle.Reference || selectedArticle.IRSCode) && (
                <div className="mt-6 pt-6 border-t border-slate-200">
                  <h4 className="text-sm font-semibold text-slate-500 uppercase tracking-wide mb-3">References</h4>
                  <div className="flex flex-wrap gap-2">
                    {selectedArticle.Reference && (
                      <span className="px-3 py-1 bg-slate-100 text-slate-600 rounded-full text-sm">
                        {selectedArticle.Reference}
                      </span>
                    )}
                    {selectedArticle.IRSCode && (
                      <span className="px-3 py-1 bg-amber-100 text-amber-700 rounded-full text-sm">
                        IRS Code: {selectedArticle.IRSCode}
                      </span>
                    )}
                  </div>
                </div>
              )}
            </div>
            
            {/* Modal Footer */}
            <div className="p-4 border-t border-slate-200 bg-slate-50 flex justify-end">
              <button
                onClick={() => setSelectedArticle(null)}
                className="px-4 py-2 bg-slate-200 text-slate-700 rounded-lg font-medium hover:bg-slate-300 transition-colors"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Categories */}
      {results.length === 0 && !searchMutation.isPending && (
        <>
          <div>
            <h2 className="text-lg font-semibold text-slate-900 mb-4">Browse by Category</h2>
            <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4">
              {categories.map((category) => (
                <button
                  key={category.name}
                  onClick={() => {
                    setSearchQuery(category.name)
                    searchMutation.mutate(category.name)
                  }}
                  className="bg-white rounded-xl border border-slate-200 p-4 text-left hover:shadow-md hover:border-blue-200 transition-all"
                >
                  <Tag className="w-5 h-5 text-slate-400 mb-2" />
                  <p className="font-medium text-slate-900">{category.name}</p>
                  <span className={`inline-block px-2 py-0.5 rounded text-xs mt-2 ${category.color}`}>
                    {category.count} articles
                  </span>
                </button>
              ))}
            </div>
          </div>

          {/* Recent Articles */}
          <div>
            <h2 className="text-lg font-semibold text-slate-900 mb-4">Popular Articles</h2>
            <div className="bg-white rounded-xl border border-slate-200 divide-y divide-slate-200">
              {[
                'Understanding the Standard Deduction vs. Itemized Deductions',
                'Home Office Deduction Requirements for 2024',
                'Reporting Cryptocurrency Gains and Losses',
                'Qualifying for the Earned Income Tax Credit',
                'Self-Employment Tax: What You Need to Know',
              ].map((title, i) => (
                <div 
                  key={i} 
                  className="p-4 hover:bg-slate-50 transition-colors cursor-pointer"
                  onClick={() => {
                    setSearchQuery(title)
                    searchMutation.mutate(title)
                  }}
                >
                  <div className="flex items-center gap-3">
                    <BookOpen className="w-5 h-5 text-slate-400" />
                    <span className="text-slate-900">{title}</span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </>
      )}

      {/* Tech Info */}
      <div className="bg-blue-50 rounded-xl p-4 border border-blue-100">
        <p className="text-sm text-blue-800">
          <strong>Semantic Search:</strong> The knowledge base uses Azure OpenAI embeddings 
          stored in Azure SQL Hyperscale with vector indexes for fast semantic retrieval.
        </p>
      </div>
    </div>
  )
}
