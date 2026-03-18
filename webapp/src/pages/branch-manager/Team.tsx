import { useQuery } from '@tanstack/react-query'
import { Users, Clock, TrendingUp, Award, MoreVertical, Loader2, Database, FileText } from 'lucide-react'
import { useState } from 'react'
import { api } from '../../lib/api'

function formatCurrency(amount: number): string {
  if (amount >= 1_000_000) return `$${(amount / 1_000_000).toFixed(1)}M`
  if (amount >= 1_000) return `$${(amount / 1_000).toFixed(0)}K`
  return `$${amount.toLocaleString()}`
}

export default function Team() {
  const currentYear = new Date().getFullYear()
  const [selectedYear, setSelectedYear] = useState<number>(2025)
  
  const { data: leaderboard, isLoading: leaderboardLoading } = useQuery({
    queryKey: ['branch-leaderboard-team', selectedYear],
    queryFn: () => api.getBranchLeaderboard(1, selectedYear),
  })

  const { data: analytics } = useQuery({
    queryKey: ['branch-analytics-team', selectedYear],
    queryFn: () => api.getBranchAnalytics(1, selectedYear),
  })

  const members: any[] = leaderboard || []

  // Derive summary stats from real data
  const totalMembers = analytics?.TeamMembers || members.length
  const totalReturns = members.reduce((s: number, m: any) => s + (m.TotalReturns || 0), 0)
  const avgProcessing = members.length > 0
    ? Math.round(members.reduce((s: number, m: any) => s + (m.AvgProcessingMinutes || 0), 0) / members.length)
    : 0
  const topPerformer = members.length > 0 ? members[0] : null

  // Generate year options (current year and 5 years back)
  const yearOptions = Array.from({ length: 6 }, (_, i) => currentYear - i)

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">My Team</h1>
          <p className="text-slate-600 mt-1">
            {analytics?.BranchName || 'Branch'} — team performance from Hyperscale named replica
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

      {leaderboardLoading ? (
        <div className="flex items-center justify-center py-12">
          <Loader2 className="w-8 h-8 animate-spin text-purple-500" />
          <span className="ml-3 text-slate-500">Loading team data from named replica...</span>
        </div>
      ) : (
        <>
          {/* Team Stats */}
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
            <div className="bg-white rounded-xl p-4 border border-slate-200">
              <Users className="w-6 h-6 text-purple-600 mb-2" />
              <p className="text-2xl font-bold text-slate-900">{totalMembers}</p>
              <p className="text-sm text-slate-600">Team Members</p>
            </div>
            <div className="bg-white rounded-xl p-4 border border-slate-200">
              <FileText className="w-6 h-6 text-blue-600 mb-2" />
              <p className="text-2xl font-bold text-slate-900">{totalReturns.toLocaleString()}</p>
              <p className="text-sm text-slate-600">Total Returns</p>
            </div>
            <div className="bg-white rounded-xl p-4 border border-slate-200">
              <Clock className="w-6 h-6 text-amber-600 mb-2" />
              <p className="text-2xl font-bold text-slate-900">{avgProcessing} min</p>
              <p className="text-sm text-slate-600">Avg Processing Time</p>
            </div>
            <div className="bg-white rounded-xl p-4 border border-slate-200">
              <TrendingUp className="w-6 h-6 text-green-600 mb-2" />
              <p className="text-2xl font-bold text-slate-900">{formatCurrency(members.reduce((s: number, m: any) => s + (m.TotalIncomeProcessed || 0), 0))}</p>
              <p className="text-sm text-slate-600">Total Income Processed</p>
            </div>
          </div>

          {/* Team Grid */}
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {members.map((member: any, index: number) => (
              <div
                key={member.ProfessionalId}
                className="bg-white rounded-xl border border-slate-200 p-6 hover:shadow-md transition-shadow"
              >
                <div className="flex items-start justify-between mb-4">
                  <div className="flex items-center gap-3">
                    <div className={`w-12 h-12 rounded-full flex items-center justify-center ${
                      index === 0 ? 'bg-amber-100' : 'bg-purple-100'
                    }`}>
                      <span className={`font-semibold ${index === 0 ? 'text-amber-600' : 'text-purple-600'}`}>
                        {member.Initials}
                      </span>
                    </div>
                    <div>
                      <h3 className="font-semibold text-slate-900">{member.ProfessionalName}</h3>
                      <p className="text-sm text-slate-500">{member.Certification || 'Tax Preparer'}</p>
                    </div>
                  </div>
                  <button className="p-1 text-slate-400 hover:text-slate-600 rounded">
                    <MoreVertical className="w-4 h-4" />
                  </button>
                </div>

                {index === 0 && (
                  <div className="flex items-center gap-2 mb-4">
                    <Award className="w-4 h-4 text-amber-500" />
                    <span className="text-xs font-medium text-amber-600">Top Performer</span>
                  </div>
                )}

                <div className="grid grid-cols-3 gap-2 pt-4 border-t border-slate-100">
                  <div className="text-center">
                    <p className="text-lg font-semibold text-slate-900">{member.TotalReturns}</p>
                    <p className="text-xs text-slate-500">Returns</p>
                  </div>
                  <div className="text-center">
                    <p className="text-lg font-semibold text-slate-900">{member.AvgProcessingMinutes} min</p>
                    <p className="text-xs text-slate-500">Avg Time</p>
                  </div>
                  <div className="text-center">
                    <p className="text-lg font-semibold text-emerald-600">{formatCurrency(member.TotalIncomeProcessed || 0)}</p>
                    <p className="text-xs text-slate-500">Income</p>
                  </div>
                </div>
              </div>
            ))}
          </div>

          {/* Top Performer */}
          {topPerformer && (
            <div className="bg-gradient-to-r from-purple-600 to-purple-700 rounded-xl p-6 text-white">
              <div className="flex items-center gap-4">
                <div className="w-16 h-16 bg-white/20 rounded-full flex items-center justify-center">
                  <Award className="w-8 h-8" />
                </div>
                <div>
                  <h3 className="text-lg font-semibold">Top Performer</h3>
                  <p className="text-purple-100">
                    {topPerformer.ProfessionalName} — {topPerformer.TotalReturns} returns,{' '}
                    {topPerformer.AvgProcessingMinutes} min avg processing, {formatCurrency(topPerformer.TotalIncomeProcessed || 0)} income processed
                  </p>
                </div>
              </div>
            </div>
          )}

          {/* Tech Banner */}
          <div className="bg-purple-50 rounded-xl p-4 border border-purple-100 flex items-start gap-3">
            <Database className="w-5 h-5 text-purple-600 mt-0.5 shrink-0" />
            <p className="text-sm text-purple-800">
              <strong>Live Data:</strong> Team performance is derived in real-time from the
              <strong> GetBranchLeaderboard</strong> stored procedure running on a Hyperscale named replica
              with NCCI-powered aggregation — zero impact on OLTP workloads.
            </p>
          </div>
        </>
      )}
    </div>
  )
}
