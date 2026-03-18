import { useQuery } from '@tanstack/react-query'
import { Users, TrendingUp, DollarSign, Clock, ArrowRight, Loader2, Database, Target } from 'lucide-react'
import { Link } from 'react-router-dom'
import { useState } from 'react'
import { api } from '../../lib/api'

function formatCurrency(amount: number): string {
  if (amount >= 1_000_000) return `$${(amount / 1_000_000).toFixed(1)}M`
  if (amount >= 1_000) return `$${(amount / 1_000).toFixed(0)}K`
  return `$${amount.toLocaleString()}`
}

export default function BranchManagerDashboard() {
  const currentYear = new Date().getFullYear()
  const [selectedYear, setSelectedYear] = useState<number>(2025)
  
  const { data: analytics, isLoading: analyticsLoading } = useQuery({
    queryKey: ['branch-analytics', selectedYear],
    queryFn: () => api.getBranchAnalytics(1, selectedYear),
  })

  const { data: leaderboard, isLoading: leaderboardLoading } = useQuery({
    queryKey: ['branch-leaderboard', selectedYear],
    queryFn: () => api.getBranchLeaderboard(1, selectedYear),
  })

  const { data: replicaInfo } = useQuery({
    queryKey: ['replica-identity'],
    queryFn: () => api.getReplicaIdentity(),
  })

  const isLoading = analyticsLoading || leaderboardLoading

  // Generate year options (current year and 5 years back)
  const yearOptions = Array.from({ length: 6 }, (_, i) => currentYear - i)

  return (
    <div className="space-y-6">
      {/* Header with Actions */}
      <div className="flex flex-col lg:flex-row lg:items-start lg:justify-between gap-6">
        <div className="page-header mb-0">
          <h1 className="page-title">Branch Dashboard</h1>
          <p className="page-subtitle">
            {analytics?.BranchName || 'Loading...'} • {analytics?.BranchLocation || ''} • Real-time analytics
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-3">
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
          <Link to="/branch/team" className="btn btn-primary flex items-center gap-2">
            <Users className="w-4 h-4" />
            Manage Team
          </Link>
          <Link to="/branch/performance" className="btn btn-outline flex items-center gap-2">
            <Target className="w-4 h-4" />
            Analytics
          </Link>
        </div>
      </div>

      {/* Stats Grid */}
      {isLoading ? (
        <div className="flex items-center justify-center py-12">
          <Loader2 className="w-8 h-8 animate-spin text-blue-500" />
          <span className="ml-3 text-slate-500">Loading analytics from named replica...</span>
        </div>
      ) : analytics ? (
        <>
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
            <div className="stat-card">
              <div className="flex items-start justify-between">
                <div className="w-12 h-12 rounded-lg bg-blue-100 flex items-center justify-center">
                  <Users className="w-5 h-5 text-blue-600" />
                </div>
              </div>
              <p className="text-2xl font-bold text-slate-900 mt-3">{analytics.TeamMembers}</p>
              <p className="text-slate-500 text-sm">Team Members</p>
            </div>
            <div className="stat-card">
              <div className="flex items-start justify-between">
                <div className="w-12 h-12 rounded-lg bg-emerald-100 flex items-center justify-center">
                  <TrendingUp className="w-5 h-5 text-emerald-600" />
                </div>
                <span className="text-xs font-medium px-2 py-0.5 rounded-full bg-emerald-100 text-emerald-700">
                  {analytics.ReturnsLast7Days} this week
                </span>
              </div>
              <p className="text-2xl font-bold text-slate-900 mt-3">{analytics.TotalReturns?.toLocaleString()}</p>
              <p className="text-slate-500 text-sm">Total Returns</p>
            </div>
            <div className="stat-card">
              <div className="flex items-start justify-between">
                <div className="w-12 h-12 rounded-lg bg-amber-100 flex items-center justify-center">
                  <DollarSign className="w-5 h-5 text-amber-600" />
                </div>
                <span className="text-xs font-medium px-2 py-0.5 rounded-full bg-amber-100 text-amber-700">
                  {formatCurrency(analytics.IncomeLast30Days || 0)} MTD
                </span>
              </div>
              <p className="text-2xl font-bold text-slate-900 mt-3">{formatCurrency(analytics.TotalIncomeProcessed || 0)}</p>
              <p className="text-slate-500 text-sm">Income Processed</p>
            </div>
            <div className="stat-card">
              <div className="flex items-start justify-between">
                <div className="w-12 h-12 rounded-lg bg-purple-100 flex items-center justify-center">
                  <Clock className="w-5 h-5 text-purple-600" />
                </div>
              </div>
              <p className="text-2xl font-bold text-slate-900 mt-3">{analytics.AvgProcessingMinutes || 0} min</p>
              <p className="text-slate-500 text-sm">Avg. Processing Time</p>
            </div>
          </div>

          {/* Main Content - Two Column Layout */}
          <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">
            {/* Team Leaderboard - Takes 2 columns */}
            <div className="xl:col-span-2 card">
              <div className="card-header flex items-center justify-between">
                <h2 className="font-semibold">Team Leaderboard</h2>
                <Link to="/branch/team" className="text-sm text-zava-600 hover:text-zava-700 flex items-center gap-1">
                  View All <ArrowRight className="w-4 h-4" />
                </Link>
              </div>
              <div className="card-body">
                {leaderboardLoading ? (
                  <div className="flex items-center justify-center py-8">
                    <Loader2 className="w-6 h-6 animate-spin text-slate-400" />
                  </div>
                ) : (
                  <div className="overflow-x-auto">
                    <table className="w-full">
                      <thead>
                        <tr className="text-left text-xs font-semibold text-slate-500 uppercase tracking-wider border-b border-slate-200">
                          <th className="pb-3 pr-4">Rank</th>
                          <th className="pb-3 pr-4">Team Member</th>
                          <th className="pb-3 pr-4 text-right">Returns</th>
                          <th className="pb-3 pr-4 text-right">Avg Time</th>
                          <th className="pb-3 text-right">Income Processed</th>
                        </tr>
                      </thead>
                      <tbody>
                        {(leaderboard || []).map((member: any, index: number) => (
                          <tr key={member.ProfessionalId} className="border-b border-slate-100 last:border-0">
                            <td className="py-3 pr-4">
                              <span className={`w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold ${
                                index === 0 ? 'bg-amber-100 text-amber-700' :
                                index === 1 ? 'bg-slate-200 text-slate-700' :
                                index === 2 ? 'bg-orange-100 text-orange-700' :
                                'bg-slate-100 text-slate-500'
                              }`}>
                                {index + 1}
                              </span>
                            </td>
                            <td className="py-3 pr-4">
                              <div className="flex items-center gap-3">
                                <div className="w-8 h-8 bg-purple-100 rounded-full flex items-center justify-center">
                                  <span className="text-purple-600 font-medium text-xs">{member.Initials}</span>
                                </div>
                                <div>
                                  <span className="font-medium text-slate-900">{member.ProfessionalName}</span>
                                  {member.Certification && (
                                    <span className="ml-2 text-xs text-slate-400">{member.Certification}</span>
                                  )}
                                </div>
                              </div>
                            </td>
                            <td className="py-3 pr-4 text-right text-slate-600">{member.TotalReturns}</td>
                            <td className="py-3 pr-4 text-right text-slate-600">{member.AvgProcessingMinutes} min</td>
                            <td className="py-3 text-right font-medium text-emerald-600">{formatCurrency(member.TotalIncomeProcessed || 0)}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>
            </div>

            {/* Right Sidebar */}
            <div className="space-y-6">
              {/* Return Status Breakdown */}
              <div className="card">
                <div className="card-header">
                  <h2 className="font-semibold">Return Status</h2>
                </div>
                <div className="card-body space-y-4">
                  {[
                    { label: 'Accepted', value: analytics.AcceptedReturns || 0, color: 'bg-emerald-500' },
                    { label: 'Pending', value: analytics.PendingReturns || 0, color: 'bg-amber-500' },
                    { label: 'Rejected', value: analytics.RejectedReturns || 0, color: 'bg-red-500' },
                  ].map((status) => {
                    const total = analytics.TotalReturns || 1
                    const pct = ((status.value / total) * 100).toFixed(1)
                    return (
                      <div key={status.label}>
                        <div className="flex justify-between text-sm mb-1">
                          <span className="text-slate-600">{status.label}</span>
                          <span className="font-medium text-slate-900">{status.value.toLocaleString()} ({pct}%)</span>
                        </div>
                        <div className="h-2 bg-slate-100 rounded-full overflow-hidden">
                          <div className={`h-full ${status.color} rounded-full`} style={{ width: `${pct}%` }} />
                        </div>
                      </div>
                    )
                  })}
                </div>
              </div>

              {/* Financial Summary */}
              <div className="card">
                <div className="card-header">
                  <h2 className="font-semibold">Financial Summary</h2>
                </div>
                <div className="card-body space-y-3">
                  <div className="flex justify-between text-sm">
                    <span className="text-slate-600">Total Refunds</span>
                    <span className="font-semibold text-emerald-600">{formatCurrency(analytics.TotalRefunds || 0)}</span>
                  </div>
                  <div className="flex justify-between text-sm">
                    <span className="text-slate-600">Total Amount Owed</span>
                    <span className="font-semibold text-red-600">{formatCurrency(analytics.TotalAmountOwed || 0)}</span>
                  </div>
                  <div className="flex justify-between text-sm border-t pt-2">
                    <span className="text-slate-600">Avg Deductions</span>
                    <span className="font-semibold text-slate-900">{formatCurrency(analytics.AvgDeductions || 0)}</span>
                  </div>
                </div>
              </div>
            </div>
          </div>

          {/* Tech Banner */}
          <div className="bg-purple-50 rounded-xl p-4 border border-purple-100 flex flex-col gap-3">
            <div className="flex items-start gap-3">
              <Database className="w-5 h-5 text-purple-600 mt-0.5 shrink-0" />
              <p className="text-sm text-purple-800">
                <strong>Hyperscale Named Replica + NCCI:</strong> These analytics are powered by real-time
                aggregation queries running on a <strong>Hyperscale named replica with serverless compute</strong>.
                The Nonclustered Columnstore Index on TaxReturns enables sub-second analytical scans
                over {analytics.TotalReturns?.toLocaleString() || '0'} returns — zero impact on OLTP workloads.
              </p>
            </div>
            {replicaInfo && (
              <div className="ml-8 flex flex-wrap gap-4 text-xs font-mono">
                <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md bg-purple-100 text-purple-900">
                  <span className="font-semibold">DB_NAME():</span> {replicaInfo.DatabaseName}
                </span>
                <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md ${
                  replicaInfo.Updateability === 'READ_ONLY' ? 'bg-emerald-100 text-emerald-900' : 'bg-red-100 text-red-900'
                }`}>
                  <span className="font-semibold">Updateability:</span> {replicaInfo.Updateability}
                </span>
                <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md bg-slate-100 text-slate-700">
                  <span className="font-semibold">Server:</span> {replicaInfo.ServerName}
                </span>
              </div>
            )}
          </div>
        </>
      ) : (
        <div className="text-center py-12 text-slate-500">No analytics data available</div>
      )}
    </div>
  )
}
