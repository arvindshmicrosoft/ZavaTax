import { useQuery } from '@tanstack/react-query'
import { useState } from 'react'
import { Download, Loader2, Database, AlertTriangle, Calendar } from 'lucide-react'
import { api } from '../../lib/api'

function formatCurrency(amount: number): string {
  if (amount >= 1_000_000) return `$${(amount / 1_000_000).toFixed(1)}M`
  if (amount >= 1_000) return `$${(amount / 1_000).toFixed(0)}K`
  return `$${amount.toLocaleString()}`
}

export default function Analytics() {
  const currentYear = new Date().getFullYear()
  const [selectedYear, setSelectedYear] = useState<number>(2025)
  const yearOptions = Array.from({ length: 6 }, (_, i) => currentYear - i)

  const { data: topBranches, isLoading: branchesLoading, error: branchesError } = useQuery({
    queryKey: ['top-branches-analytics', selectedYear],
    queryFn: () => api.getTopBranches(10, selectedYear),
    retry: 1,
    retryDelay: 1000,
  })

  const { data: filingStatus, isLoading: filingLoading, error: filingError } = useQuery({
    queryKey: ['filing-status-analytics', selectedYear],
    queryFn: () => api.getFilingStatusDistribution(selectedYear),
    retry: 1,
    retryDelay: 1000,
  })

  const { data: returnsByYear, isLoading: yearLoading, error: yearError } = useQuery({
    queryKey: ['returns-by-year'],
    queryFn: () => api.getReturnsByYear(),
    retry: 1,
    retryDelay: 1000,
  })

  const isLoading = branchesLoading || filingLoading || yearLoading
  const hasError = branchesError || filingError || yearError

  // Ensure we always have arrays to work with
  const safeBranches = Array.isArray(topBranches) ? topBranches : []
  const safeFilingStatus = Array.isArray(filingStatus) ? filingStatus : []
  const safeReturnsByYear = Array.isArray(returnsByYear) ? returnsByYear : []

  // Find max income for scaling the bar chart
  const maxIncome = Math.max(...safeBranches.map((b: any) => b.TotalIncomeProcessed || 0), 1)

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">Analytics</h1>
          <p className="text-slate-600 mt-1">Deep dive into company performance — NCCI-powered queries on named replica</p>
        </div>
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-2">
            <Calendar className="w-4 h-4 text-slate-400" />
            <select
              value={selectedYear}
              onChange={(e) => setSelectedYear(Number(e.target.value))}
              className="px-3 py-2 border border-slate-200 rounded-lg text-sm font-medium text-slate-700 bg-white hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-amber-500"
            >
              {yearOptions.map((y) => (
                <option key={y} value={y}>TY {y}</option>
              ))}
            </select>
          </div>
          <button className="px-4 py-2 bg-amber-600 text-white rounded-lg hover:bg-amber-700 flex items-center gap-2">
            <Download className="w-4 h-4" />
            Export
          </button>
        </div>
      </div>

      {isLoading ? (
        <div className="flex items-center justify-center py-12">
          <Loader2 className="w-8 h-8 animate-spin text-amber-500" />
          <span className="ml-3 text-slate-500">Loading analytics data...</span>
        </div>
      ) : hasError ? (
        <div className="flex items-center justify-center py-12">
          <div className="text-center">
            <AlertTriangle className="w-12 h-12 text-amber-500 mx-auto mb-3" />
            <h3 className="text-lg font-semibold text-slate-900 mb-2">Unable to Load Analytics</h3>
            <p className="text-slate-600 mb-4">The query may have timed out or encountered an error.</p>
            <button 
              onClick={() => window.location.reload()} 
              className="px-4 py-2 bg-amber-600 text-white rounded-lg hover:bg-amber-700"
            >
              Retry
            </button>
          </div>
        </div>
      ) : (
        <>
          {/* Branch Performance */}
          <div className="bg-white rounded-xl border border-slate-200 p-6">
            <h2 className="text-lg font-semibold text-slate-900 mb-6">Branch Performance (Top 10) — {selectedYear}</h2>
            <div className="space-y-4">
              {safeBranches.map((branch: any) => (
                <div key={branch.BranchId} className="flex items-center gap-4">
                  <div className="w-32 font-medium text-slate-900 text-sm truncate">{branch.BranchName}</div>
                  <div className="flex-1">
                    <div className="h-8 bg-slate-100 rounded-lg overflow-hidden flex">
                      <div
                        className="bg-gradient-to-r from-amber-500 to-amber-400 flex items-center justify-end px-3"
                        style={{ width: `${Math.max((branch.TotalIncomeProcessed / maxIncome) * 100, 10)}%` }}
                      >
                        <span className="text-white text-sm font-medium">{formatCurrency(branch.TotalIncomeProcessed || 0)}</span>
                      </div>
                    </div>
                  </div>
                  <div className="w-24 text-right">
                    <span className="text-slate-600 text-sm">{branch.TotalReturns?.toLocaleString()} returns</span>
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Metrics Grid */}
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {/* Filing Status Distribution */}
            <div className="bg-white rounded-xl border border-slate-200 p-6">
              <h3 className="font-semibold text-slate-900 mb-4">Filing Status Distribution</h3>
              <div className="space-y-3">
                {safeFilingStatus.map((fs: any, i: number) => {
                  const colors = ['bg-amber-500', 'bg-blue-500', 'bg-green-500', 'bg-purple-500', 'bg-rose-500']
                  return (
                    <div key={fs.FilingStatus}>
                      <div className="flex justify-between text-sm mb-1">
                        <span className="text-slate-600">{fs.FilingStatus}</span>
                        <span className="font-medium">{fs.Percentage}%</span>
                      </div>
                      <div className="h-2 bg-slate-100 rounded-full overflow-hidden">
                        <div
                          className={`h-full ${colors[i % colors.length]} rounded-full`}
                          style={{ width: `${fs.Percentage}%` }}
                        />
                      </div>
                      <div className="flex justify-between text-xs text-slate-400 mt-1">
                        <span>Avg Income: {formatCurrency(fs.AvgIncome || 0)}</span>
                        <span>Avg Refund: {formatCurrency(fs.AvgRefund || 0)}</span>
                      </div>
                    </div>
                  )
                })}
              </div>
            </div>

            {/* Income & Deductions by Filing Status */}
            <div className="bg-white rounded-xl border border-slate-200 p-6">
              <h3 className="font-semibold text-slate-900 mb-4">Avg Deductions by Filing Status</h3>
              <div className="space-y-3">
                {safeFilingStatus.map((fs: any) => {
                  const maxDed = Math.max(...safeFilingStatus.map((f: any) => f.AvgDeductions || 0), 1)
                  const pct = ((fs.AvgDeductions || 0) / maxDed) * 100
                  return (
                    <div key={fs.FilingStatus}>
                      <div className="flex justify-between text-sm mb-1">
                        <span className="text-slate-600">{fs.FilingStatus}</span>
                        <span className="font-medium">{formatCurrency(fs.AvgDeductions || 0)}</span>
                      </div>
                      <div className="h-2 bg-slate-100 rounded-full overflow-hidden">
                        <div
                          className="h-full bg-purple-500 rounded-full"
                          style={{ width: `${pct}%` }}
                        />
                      </div>
                    </div>
                  )
                })}
              </div>
            </div>

            {/* Return Count by Filing Status */}
            <div className="bg-white rounded-xl border border-slate-200 p-6">
              <h3 className="font-semibold text-slate-900 mb-4">Return Volume by Status</h3>
              <div className="space-y-3">
                {safeFilingStatus.map((fs: any) => {
                  const maxCount = Math.max(...safeFilingStatus.map((f: any) => f.ReturnCount || 0), 1)
                  const pct = ((fs.ReturnCount || 0) / maxCount) * 100
                  return (
                    <div key={fs.FilingStatus}>
                      <div className="flex justify-between text-sm mb-1">
                        <span className="text-slate-600">{fs.FilingStatus}</span>
                        <span className="font-medium">{fs.ReturnCount?.toLocaleString()}</span>
                      </div>
                      <div className="h-2 bg-slate-100 rounded-full overflow-hidden">
                        <div
                          className="h-full bg-blue-500 rounded-full"
                          style={{ width: `${pct}%` }}
                        />
                      </div>
                    </div>
                  )
                })}
              </div>
            </div>
          </div>

          {/* Year-over-Year Comparison */}
          <div className="bg-white rounded-xl border border-slate-200 p-6">
            <h2 className="text-lg font-semibold text-slate-900 mb-6">Year-over-Year Comparison</h2>
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead>
                  <tr className="border-b border-slate-200">
                    <th className="pb-3 text-left text-sm font-medium text-slate-500">Tax Year</th>
                    <th className="pb-3 text-right text-sm font-medium text-slate-500">Returns</th>
                    <th className="pb-3 text-right text-sm font-medium text-slate-500">Total Income Processed</th>
                    <th className="pb-3 text-right text-sm font-medium text-slate-500">Avg Income</th>
                    <th className="pb-3 text-right text-sm font-medium text-slate-500">Avg Time (min)</th>
                    <th className="pb-3 text-right text-sm font-medium text-slate-500">Itemized</th>
                    <th className="pb-3 text-right text-sm font-medium text-slate-500">Standard</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {safeReturnsByYear.map((row: any) => (
                    <tr key={row.TaxYear}>
                      <td className="py-3 text-slate-900 font-semibold">{row.TaxYear}</td>
                      <td className="py-3 text-right text-slate-900">{row.ReturnCount?.toLocaleString()}</td>
                      <td className="py-3 text-right text-slate-900 font-medium">{formatCurrency(row.TotalIncomeProcessed || 0)}</td>
                      <td className="py-3 text-right text-slate-600">{formatCurrency(row.AvgIncome || 0)}</td>
                      <td className="py-3 text-right text-slate-600">{row.AvgProcessingMinutes}</td>
                      <td className="py-3 text-right text-slate-600">{row.ItemizedCount?.toLocaleString()}</td>
                      <td className="py-3 text-right text-slate-600">{row.StandardCount?.toLocaleString()}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>

          {/* Tech Banner */}
          <div className="bg-amber-50 rounded-xl p-4 border border-amber-100 flex items-start gap-3">
            <Database className="w-5 h-5 text-amber-600 mt-0.5 shrink-0" />
            <p className="text-sm text-amber-800">
              <strong>HTAP with Hyperscale:</strong> All analytics queries on this page are executed on a
              <strong> Hyperscale named replica</strong> using <strong>Nonclustered Columnstore Indexes</strong> for
              sub-second aggregation over {safeReturnsByYear.reduce((s: number, r: any) => s + (r.ReturnCount || 0), 0).toLocaleString()} total
              returns across {safeReturnsByYear.length} tax years — completely isolated from OLTP write workloads on the primary.
            </p>
          </div>
        </>
      )}
    </div>
  )
}
