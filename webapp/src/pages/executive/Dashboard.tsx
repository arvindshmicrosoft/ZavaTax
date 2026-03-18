import { useQuery } from '@tanstack/react-query'
import { useState } from 'react'
import { 
  DollarSign, 
  Users, 
  FileText, 
  Building2,
  ArrowRight,
  Loader2,
  Database,
  Calendar
} from 'lucide-react'
import { Link } from 'react-router-dom'
import { api } from '../../lib/api'

function formatCurrency(amount: number): string {
  if (amount >= 1_000_000) return `$${(amount / 1_000_000).toFixed(1)}M`
  if (amount >= 1_000) return `$${(amount / 1_000).toFixed(0)}K`
  return `$${amount.toLocaleString()}`
}

export default function ExecutiveDashboard() {
  const currentYear = new Date().getFullYear()
  const [selectedYear, setSelectedYear] = useState<number>(2025)
  const yearOptions = Array.from({ length: 6 }, (_, i) => currentYear - i)

  const { data: kpis, isLoading: kpisLoading } = useQuery({
    queryKey: ['executive-kpis', selectedYear],
    queryFn: () => api.getExecutiveKPIs(selectedYear),
  })

  const { data: topBranches, isLoading: branchesLoading } = useQuery({
    queryKey: ['top-branches', selectedYear],
    queryFn: () => api.getTopBranches(5, selectedYear),
  })

  const { data: filingStatus, isLoading: filingLoading } = useQuery({
    queryKey: ['filing-status', selectedYear],
    queryFn: () => api.getFilingStatusDistribution(selectedYear),
  })

  const { data: replicaInfo } = useQuery({
    queryKey: ['replica-identity'],
    queryFn: () => api.getReplicaIdentity(),
  })

  const isLoading = kpisLoading || branchesLoading || filingLoading

  return (
    <div className="space-y-6">
      {/* Header with Actions */}
      <div className="flex flex-col lg:flex-row lg:items-start lg:justify-between gap-6">
        <div className="page-header mb-0">
          <h1 className="page-title">Executive Overview</h1>
          <p className="page-subtitle">Company-wide performance metrics — live from Hyperscale named replica</p>
        </div>
        <div className="flex flex-wrap items-center gap-3">
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
          <Link to="/executive/analytics" className="btn btn-primary flex items-center gap-2">
            <FileText className="w-4 h-4" />
            View Analytics
          </Link>
        </div>
      </div>

      {isLoading ? (
        <div className="flex items-center justify-center py-12">
          <Loader2 className="w-8 h-8 animate-spin text-amber-500" />
          <span className="ml-3 text-slate-500">Loading executive analytics...</span>
        </div>
      ) : kpis ? (
        <>
          {/* KPIs */}
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
            {[
              {
                name: 'Total Income Processed',
                value: formatCurrency(kpis.TotalIncomeProcessed || 0),
                detail: `${formatCurrency(kpis.IncomeLast30Days || 0)} last 30d`,
                icon: DollarSign,
                bgColor: 'bg-emerald-100',
                iconColor: 'text-emerald-600',
              },
              {
                name: 'Returns Processed',
                value: (kpis.TotalReturns || 0).toLocaleString(),
                detail: `${(kpis.ReturnsLast30Days || 0).toLocaleString()} last 30d`,
                icon: FileText,
                bgColor: 'bg-blue-100',
                iconColor: 'text-blue-600',
              },
              {
                name: 'Active Customers',
                value: (kpis.ActiveCustomers || 0).toLocaleString(),
                detail: `${formatCurrency(kpis.AvgIncomePerReturn || 0)} avg/return`,
                icon: Users,
                bgColor: 'bg-purple-100',
                iconColor: 'text-purple-600',
              },
              {
                name: 'Active Branches',
                value: (kpis.ActiveBranches || 0).toString(),
                detail: `${kpis.AvgProcessingMinutes || 0} min avg time`,
                icon: Building2,
                bgColor: 'bg-amber-100',
                iconColor: 'text-amber-600',
              },
            ].map((kpi) => (
              <div key={kpi.name} className="stat-card">
                <div className="flex items-center justify-between mb-3">
                  <div className={`w-12 h-12 rounded-lg ${kpi.bgColor} flex items-center justify-center`}>
                    <kpi.icon className={`w-5 h-5 ${kpi.iconColor}`} />
                  </div>
                  <span className="text-xs font-medium px-2 py-0.5 rounded-full bg-slate-100 text-slate-600">
                    {kpi.detail}
                  </span>
                </div>
                <p className="text-2xl font-bold text-slate-900">{kpi.value}</p>
                <p className="text-slate-500 text-sm">{kpi.name}</p>
              </div>
            ))}
          </div>

          {/* Main Content - Three Column Layout */}
          <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">
            {/* Financial Summary */}
            <div className="card">
              <div className="card-header">Financial Summary</div>
              <div className="card-body space-y-4">
                <div className="flex justify-between text-sm">
                  <span className="text-slate-600">Total Refunds</span>
                  <span className="font-semibold text-emerald-600">{formatCurrency(kpis.TotalRefunds || 0)}</span>
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-slate-600">Total Amount Owed</span>
                  <span className="font-semibold text-red-600">{formatCurrency(kpis.TotalAmountOwed || 0)}</span>
                </div>
                <div className="flex justify-between text-sm border-t pt-2">
                  <span className="text-slate-600">Avg Income/Return</span>
                  <span className="font-semibold text-slate-900">{formatCurrency(kpis.AvgIncomePerReturn || 0)}</span>
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-slate-600">Avg Processing Time</span>
                  <span className="font-semibold text-slate-900">{kpis.AvgProcessingMinutes || 0} min</span>
                </div>
              </div>
            </div>

            {/* Returns by Status */}
            <div className="card">
              <div className="card-header">Returns by Status</div>
              <div className="card-body space-y-4">
                {[
                  { status: 'Accepted', count: kpis.AcceptedReturns || 0, color: 'bg-emerald-500' },
                  { status: 'Filed', count: kpis.FiledReturns || 0, color: 'bg-blue-500' },
                  { status: 'In Progress', count: kpis.InProgressReturns || 0, color: 'bg-amber-500' },
                  { status: 'Rejected', count: kpis.RejectedReturns || 0, color: 'bg-red-500' },
                  { status: 'Draft', count: kpis.DraftReturns || 0, color: 'bg-slate-400' },
                ].map((item) => {
                  const total = kpis.TotalReturns || 1
                  const pct = ((item.count / total) * 100).toFixed(1)
                  return (
                    <div key={item.status}>
                      <div className="flex items-center justify-between text-sm mb-1">
                        <span className="text-slate-600">{item.status}</span>
                        <span className="font-medium text-slate-900">{item.count.toLocaleString()} ({pct}%)</span>
                      </div>
                      <div className="h-2 bg-slate-100 rounded-full overflow-hidden">
                        <div
                          className={`h-full ${item.color} rounded-full`}
                          style={{ width: `${pct}%` }}
                        />
                      </div>
                    </div>
                  )
                })}
              </div>
            </div>

            {/* Filing Status Distribution */}
            <div className="card">
              <div className="card-header">Filing Status Distribution</div>
              <div className="card-body space-y-3">
                {(filingStatus || []).map((fs: any, i: number) => {
                  const colors = ['bg-amber-500', 'bg-blue-500', 'bg-green-500', 'bg-purple-500', 'bg-rose-500']
                  return (
                    <div key={fs.FilingStatus} className="flex items-center justify-between p-2 rounded-md hover:bg-slate-50">
                      <div className="flex items-center gap-2">
                        <div className={`w-3 h-3 rounded-full ${colors[i % colors.length]}`} />
                        <span className="font-medium text-slate-900 text-sm">{fs.FilingStatus}</span>
                      </div>
                      <div className="text-right">
                        <span className="font-semibold text-slate-900 text-sm">{fs.Percentage}%</span>
                        <span className="text-xs text-slate-400 ml-2">({fs.ReturnCount?.toLocaleString()})</span>
                      </div>
                    </div>
                  )
                })}
              </div>
            </div>
          </div>

          {/* Top Branches - Full Width Table */}
          <div className="card">
            <div className="card-header flex items-center justify-between">
              <span>Top Performing Branches ({selectedYear})</span>
              <Link to="/executive/analytics" className="text-sm font-medium text-zava-600 hover:text-zava-700 flex items-center gap-1">
                View All <ArrowRight className="w-4 h-4" />
              </Link>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead>
                  <tr className="text-left text-xs font-semibold text-slate-500 uppercase tracking-wider border-b border-slate-200">
                    <th className="p-4">Rank</th>
                    <th className="p-4">Branch</th>
                    <th className="p-4 text-right">Returns</th>
                    <th className="p-4 text-right">Income Processed</th>
                    <th className="p-4 text-right">Staff</th>
                    <th className="p-4 text-right">Avg Time</th>
                  </tr>
                </thead>
                <tbody>
                  {(topBranches || []).map((branch: any, index: number) => (
                    <tr key={branch.BranchId} className="border-b border-slate-100 last:border-0 hover:bg-slate-50">
                      <td className="p-4">
                        <span className={`w-7 h-7 rounded-full flex items-center justify-center text-sm font-bold ${
                          index === 0 ? 'bg-amber-100 text-amber-700' :
                          index === 1 ? 'bg-slate-200 text-slate-700' :
                          index === 2 ? 'bg-orange-100 text-orange-700' :
                          'bg-slate-100 text-slate-500'
                        }`}>
                          {index + 1}
                        </span>
                      </td>
                      <td className="p-4">
                        <p className="font-medium text-slate-900">{branch.BranchName}</p>
                        <p className="text-xs text-slate-400">{branch.BranchLocation}</p>
                      </td>
                      <td className="p-4 text-right text-slate-600">{branch.TotalReturns?.toLocaleString()}</td>
                      <td className="p-4 text-right font-semibold text-slate-900">{formatCurrency(branch.TotalIncomeProcessed || 0)}</td>
                      <td className="p-4 text-right text-slate-600">{branch.StaffCount}</td>
                      <td className="p-4 text-right text-slate-600">{branch.AvgProcessingMinutes} min</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>

          {/* Tech Banner */}
          <div className="bg-amber-50 rounded-xl p-4 border border-amber-100 flex flex-col gap-3">
            <div className="flex items-start gap-3">
              <Database className="w-5 h-5 text-amber-600 mt-0.5 shrink-0" />
              <p className="text-sm text-amber-800">
                <strong>Hyperscale Named Replica + NCCI:</strong> All executive analytics are powered by
                real-time aggregation queries on a <strong>Hyperscale named replica with serverless compute</strong>.
                The Nonclustered Columnstore Index on TaxReturns enables sub-second full-table scans
                across {(kpis.TotalReturns || 0).toLocaleString()} returns and {(kpis.ActiveCustomers || 0).toLocaleString()} customers — 
                zero impact on OLTP transaction processing.
              </p>
            </div>
            {replicaInfo && (
              <div className="ml-8 flex flex-wrap gap-4 text-xs font-mono">
                <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md bg-amber-100 text-amber-900">
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
        <div className="text-center py-12 text-slate-500">No executive data available</div>
      )}
    </div>
  )
}
