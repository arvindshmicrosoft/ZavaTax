import { useQuery } from '@tanstack/react-query'
import { DollarSign, Users, FileText, Clock, Loader2, Database } from 'lucide-react'
import { useState } from 'react'
import { api } from '../../lib/api'

function formatCurrency(amount: number): string {
  if (amount >= 1_000_000) return `$${(amount / 1_000_000).toFixed(1)}M`
  if (amount >= 1_000) return `$${(amount / 1_000).toFixed(0)}K`
  return `$${amount.toLocaleString()}`
}

export default function Performance() {
  const currentYear = new Date().getFullYear()
  const [selectedYear, setSelectedYear] = useState<number>(2025)
  
  const { data: analytics, isLoading: analyticsLoading } = useQuery({
    queryKey: ['branch-analytics', selectedYear],
    queryFn: () => api.getBranchAnalytics(1, selectedYear),
  })

  const { data: topBranches, isLoading: branchesLoading } = useQuery({
    queryKey: ['top-branches-perf', selectedYear],
    queryFn: () => api.getTopBranches(5, selectedYear),
  })

  const { data: leaderboard, isLoading: leaderboardLoading } = useQuery({
    queryKey: ['branch-leaderboard', selectedYear],
    queryFn: () => api.getBranchLeaderboard(1, selectedYear),
  })

  const isLoading = analyticsLoading || branchesLoading

  // Generate year options (current year and 5 years back)
  const yearOptions = Array.from({ length: 6 }, (_, i) => currentYear - i)

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">Performance Analytics</h1>
          <p className="text-slate-600 mt-1">
            {analytics?.BranchName || 'Branch'} — real-time metrics from Hyperscale named replica
          </p>
        </div>
        <select
          value={selectedYear}
          onChange={(e) => setSelectedYear(Number(e.target.value))}
          className="px-3 py-2 border border-slate-200 rounded-lg text-sm font-medium text-slate-700 bg-white hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-purple-500"
        >
          {yearOptions.map((year) => (
            <option key={year} value={year}>
              Tax Year {year}
            </option>
          ))}
        </select>
      </div>

      {isLoading ? (
        <div className="flex items-center justify-center py-12">
          <Loader2 className="w-8 h-8 animate-spin text-purple-500" />
          <span className="ml-3 text-slate-500">Loading performance data...</span>
        </div>
      ) : analytics ? (
        <>
          {/* Metrics Grid */}
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            {[
              {
                name: 'Returns Completed',
                value: analytics.TotalReturns?.toLocaleString() || '0',
                detail: `${analytics.ReturnsLast30Days || 0} in last 30 days`,
                icon: FileText,
              },
              {
                name: 'Income Processed',
                value: formatCurrency(analytics.TotalIncomeProcessed || 0),
                detail: `${formatCurrency(analytics.IncomeLast30Days || 0)} MTD`,
                icon: DollarSign,
              },
              {
                name: 'Avg Processing Time',
                value: `${analytics.AvgProcessingMinutes || 0} min`,
                detail: `${analytics.AvgProcessingLast30Days || analytics.AvgProcessingMinutes || 0} min (30d avg)`,
                icon: Clock,
              },
              {
                name: 'Team Size',
                value: analytics.TeamMembers?.toString() || '0',
                detail: `${analytics.AcceptedReturns || 0} returns accepted`,
                icon: Users,
              },
            ].map((metric) => (
              <div key={metric.name} className="bg-white rounded-xl p-6 border border-slate-200">
                <div className="flex items-center justify-between mb-4">
                  <div className="w-10 h-10 bg-purple-100 rounded-lg flex items-center justify-center">
                    <metric.icon className="w-5 h-5 text-purple-600" />
                  </div>
                </div>
                <p className="text-2xl font-bold text-slate-900">{metric.value}</p>
                <p className="text-sm text-slate-600 mt-1">{metric.name}</p>
                <p className="text-xs text-slate-400 mt-2">{metric.detail}</p>
              </div>
            ))}
          </div>

          {/* Team Performance Table */}
          <div className="bg-white rounded-xl border border-slate-200 p-6">
            <h2 className="text-lg font-semibold text-slate-900 mb-6">Team Performance Breakdown</h2>
            {leaderboardLoading ? (
              <div className="flex items-center justify-center py-8">
                <Loader2 className="w-6 h-6 animate-spin text-slate-400" />
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full">
                  <thead className="bg-slate-50">
                    <tr>
                      <th className="px-4 py-3 text-left text-xs font-medium text-slate-500 uppercase">Professional</th>
                      <th className="px-4 py-3 text-right text-xs font-medium text-slate-500 uppercase">Returns</th>
                      <th className="px-4 py-3 text-right text-xs font-medium text-slate-500 uppercase">Income Processed</th>
                      <th className="px-4 py-3 text-right text-xs font-medium text-slate-500 uppercase">Avg Time</th>
                      <th className="px-4 py-3 text-right text-xs font-medium text-slate-500 uppercase">Avg Deductions</th>
                      <th className="px-4 py-3 text-right text-xs font-medium text-slate-500 uppercase">Refunds</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-200">
                    {(leaderboard || []).map((member: any) => (
                      <tr key={member.ProfessionalId} className="hover:bg-slate-50">
                        <td className="px-4 py-4">
                          <div className="flex items-center gap-3">
                            <div className="w-8 h-8 bg-purple-100 rounded-full flex items-center justify-center">
                              <span className="text-purple-600 font-medium text-xs">{member.Initials}</span>
                            </div>
                            <div>
                              <span className="font-medium text-slate-900">{member.ProfessionalName}</span>
                              {member.Certification && (
                                <p className="text-xs text-slate-400">{member.Certification}</p>
                              )}
                            </div>
                          </div>
                        </td>
                        <td className="px-4 py-4 text-right text-slate-900 font-semibold">{member.TotalReturns}</td>
                        <td className="px-4 py-4 text-right text-emerald-600 font-semibold">{formatCurrency(member.TotalIncomeProcessed || 0)}</td>
                        <td className="px-4 py-4 text-right text-slate-900">{member.AvgProcessingMinutes} min</td>
                        <td className="px-4 py-4 text-right text-slate-900">{formatCurrency(member.AvgDeductions || 0)}</td>
                        <td className="px-4 py-4 text-right text-slate-900">{formatCurrency(member.TotalRefunds || 0)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>

          {/* Branch Comparison Table */}
          <div className="bg-white rounded-xl border border-slate-200 overflow-hidden">
            <div className="p-4 border-b border-slate-200">
              <h2 className="text-lg font-semibold text-slate-900">Branch Comparison</h2>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead className="bg-slate-50">
                  <tr>
                    <th className="px-4 py-3 text-left text-xs font-medium text-slate-500 uppercase">Branch</th>
                    <th className="px-4 py-3 text-right text-xs font-medium text-slate-500 uppercase">Returns</th>
                    <th className="px-4 py-3 text-right text-xs font-medium text-slate-500 uppercase">Income Processed</th>
                    <th className="px-4 py-3 text-right text-xs font-medium text-slate-500 uppercase">Avg Time</th>
                    <th className="px-4 py-3 text-right text-xs font-medium text-slate-500 uppercase">Staff</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-200">
                  {(topBranches || []).map((branch: any) => {
                    const isCurrentBranch = branch.BranchId === 1
                    return (
                      <tr
                        key={branch.BranchId}
                        className={isCurrentBranch ? 'bg-purple-50' : 'hover:bg-slate-50'}
                      >
                        <td className="px-4 py-4">
                          <span className={`font-medium ${isCurrentBranch ? 'text-purple-700' : 'text-slate-900'}`}>
                            {branch.BranchName}
                            {isCurrentBranch && (
                              <span className="ml-2 text-xs bg-purple-100 text-purple-700 px-2 py-0.5 rounded-full">
                                Your Branch
                              </span>
                            )}
                          </span>
                          <p className="text-xs text-slate-400">{branch.BranchLocation}</p>
                        </td>
                        <td className="px-4 py-4 text-right text-slate-900">{branch.TotalReturns?.toLocaleString()}</td>
                        <td className="px-4 py-4 text-right text-slate-900">{formatCurrency(branch.TotalIncomeProcessed || 0)}</td>
                        <td className="px-4 py-4 text-right text-slate-900">{branch.AvgProcessingMinutes} min</td>
                        <td className="px-4 py-4 text-right text-slate-900">{branch.StaffCount}</td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          </div>

          {/* Tech Info */}
          <div className="bg-purple-50 rounded-xl p-4 border border-purple-100 flex items-start gap-3">
            <Database className="w-5 h-5 text-purple-600 mt-0.5 shrink-0" />
            <p className="text-sm text-purple-800">
              <strong>Columnstore Analytics:</strong> These metrics are computed in real-time using
              Nonclustered Columnstore Indexes on Azure SQL Hyperscale, routed to a <strong>named replica</strong> for
              zero-impact analytical workloads. Sub-second aggregations across all return records.
            </p>
          </div>
        </>
      ) : (
        <div className="text-center py-12 text-slate-500">No performance data available</div>
      )}
    </div>
  )
}
