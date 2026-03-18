import { useQuery } from '@tanstack/react-query'
import { useState } from 'react'
import { 
  FileText, 
  Send, 
  DollarSign, 
  Briefcase,
  Loader2, 
  Database, 
  AlertTriangle,
  TrendingUp,
  Building2,
  Home,
  Landmark,
  FolderOpen
} from 'lucide-react'
import { api } from '../../lib/api'

function formatCurrency(amount: number): string {
  if (amount >= 1_000_000_000) return `$${(amount / 1_000_000_000).toFixed(1)}B`
  if (amount >= 1_000_000) return `$${(amount / 1_000_000).toFixed(1)}M`
  if (amount >= 1_000) return `$${(amount / 1_000).toFixed(0)}K`
  return `$${amount.toLocaleString()}`
}

function formatNumber(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`
  return n.toLocaleString()
}

export default function FilingAnalytics() {
  const currentYear = new Date().getFullYear()
  const [selectedYear, setSelectedYear] = useState<number>(2025)
  const yearOptions = Array.from({ length: 6 }, (_, i) => currentYear - i)

  // Fetch all filing detail analytics
  const { data: overview, isLoading: overviewLoading, error: overviewError } = useQuery({
    queryKey: ['filing-overview', selectedYear],
    queryFn: () => api.getFilingDetailOverview(selectedYear),
    retry: 1,
    retryDelay: 1000,
  })

  const { data: efileStatus, isLoading: efileLoading, error: efileError } = useQuery({
    queryKey: ['efile-status', selectedYear],
    queryFn: () => api.getEFileStatusSummary(selectedYear),
    retry: 1,
    retryDelay: 1000,
  })

  const { data: w2Summary, isLoading: w2Loading, error: w2Error } = useQuery({
    queryKey: ['w2-summary', selectedYear],
    queryFn: () => api.getW2Summary(selectedYear),
    retry: 1,
    retryDelay: 1000,
  })

  const { data: form1099, isLoading: f1099Loading, error: f1099Error } = useQuery({
    queryKey: ['1099-summary', selectedYear],
    queryFn: () => api.getForm1099Summary(selectedYear),
    retry: 1,
    retryDelay: 1000,
  })

  const { data: capitalGains, isLoading: cgLoading, error: cgError } = useQuery({
    queryKey: ['capital-gains', selectedYear],
    queryFn: () => api.getCapitalGainsSummary(selectedYear),
    retry: 1,
    retryDelay: 1000,
  })

  const { data: scheduleC, isLoading: scLoading, error: scError } = useQuery({
    queryKey: ['schedule-c', selectedYear],
    queryFn: () => api.getScheduleCSummary(selectedYear),
    retry: 1,
    retryDelay: 1000,
  })

  const { data: stateTax, isLoading: stLoading, error: stError } = useQuery({
    queryKey: ['state-tax', selectedYear],
    queryFn: () => api.getStateTaxSummary(selectedYear),
    retry: 1,
    retryDelay: 1000,
  })

  const { data: scheduleE, isLoading: seLoading, error: seError } = useQuery({
    queryKey: ['schedule-e', selectedYear],
    queryFn: () => api.getScheduleESummary(selectedYear),
    retry: 1,
    retryDelay: 1000,
  })

  const { data: scheduleB, isLoading: sbLoading, error: sbError } = useQuery({
    queryKey: ['schedule-b', selectedYear],
    queryFn: () => api.getScheduleBSummary(selectedYear),
    retry: 1,
    retryDelay: 1000,
  })

  const { data: documents, isLoading: docLoading, error: docError } = useQuery({
    queryKey: ['documents', selectedYear],
    queryFn: () => api.getDocumentSummary(selectedYear),
    retry: 1,
    retryDelay: 1000,
  })

  const isLoading = overviewLoading || efileLoading || w2Loading || f1099Loading || cgLoading || scLoading || stLoading || seLoading || sbLoading || docLoading
  const hasError = overviewError || efileError || w2Error || f1099Error || cgError || scError || stError || seError || sbError || docError

  const safeEfileStatus = Array.isArray(efileStatus) ? efileStatus : []
  const safeForm1099 = Array.isArray(form1099) ? form1099 : []
  const safeStateTax = Array.isArray(stateTax) ? stateTax : []

  // E-file status colors
  const efileColors: Record<string, string> = {
    'Accepted': 'bg-green-500',
    'Pending': 'bg-amber-500',
    'Rejected': 'bg-red-500',
    'Error': 'bg-slate-500',
    'Transmitted': 'bg-blue-500',
  }

  const totalEfileCount = safeEfileStatus.reduce((s: number, e: any) => s + (e.StatusCount || 0), 0) || 1

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">Filing Analytics</h1>
          <p className="text-slate-600 mt-1">Detailed filing data — form line items, income documents, schedules &amp; e-file tracking</p>
        </div>
        <div className="flex items-center gap-3">
          <select
            value={selectedYear}
            onChange={(e) => setSelectedYear(Number(e.target.value))}
            className="px-3 py-2 border border-slate-200 rounded-lg text-sm font-medium text-slate-700 bg-white hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-amber-500"
          >
            {yearOptions.map((year) => (
              <option key={year} value={year}>
                Tax Year {year}
              </option>
            ))}
          </select>
        </div>
      </div>

      {isLoading ? (
        <div className="flex items-center justify-center py-12">
          <Loader2 className="w-8 h-8 animate-spin text-amber-500" />
          <span className="ml-3 text-slate-500">Loading filing analytics from named replica...</span>
        </div>
      ) : hasError ? (
        <div className="flex items-center justify-center py-12">
          <div className="text-center">
            <AlertTriangle className="w-12 h-12 text-amber-500 mx-auto mb-3" />
            <h3 className="text-lg font-semibold text-slate-900 mb-2">Unable to Load Filing Analytics</h3>
            <p className="text-slate-600 mb-4">The analytics query may have timed out or the filing detail tables may not be populated yet.</p>
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
          {/* KPI Stat Cards */}
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
            <div className="stat-card">
              <div className="flex items-start justify-between">
                <div>
                  <p className="text-sm font-medium text-slate-500">Form Line Items</p>
                  <p className="text-2xl font-bold text-slate-900 mt-1">
                    {formatNumber(overview?.FormLineItemRows || overview?.TotalFormLineItems || 0)}
                  </p>
                </div>
                <div className="p-2.5 bg-amber-50 rounded-xl">
                  <FileText className="w-5 h-5 text-amber-600" />
                </div>
              </div>
              <p className="text-xs text-slate-400 mt-2">1040 line items across all returns</p>
            </div>

            <div className="stat-card">
              <div className="flex items-start justify-between">
                <div>
                  <p className="text-sm font-medium text-slate-500">E-File Submissions</p>
                  <p className="text-2xl font-bold text-slate-900 mt-1">
                    {formatNumber(overview?.EFileRows || overview?.TotalEFileSubmissions || 0)}
                  </p>
                </div>
                <div className="p-2.5 bg-green-50 rounded-xl">
                  <Send className="w-5 h-5 text-green-600" />
                </div>
              </div>
              <p className="text-xs text-slate-400 mt-2">Electronic filings transmitted</p>
            </div>

            <div className="stat-card">
              <div className="flex items-start justify-between">
                <div>
                  <p className="text-sm font-medium text-slate-500">W-2 Documents</p>
                  <p className="text-2xl font-bold text-slate-900 mt-1">
                    {formatNumber(w2Summary?.TotalW2s || 0)}
                  </p>
                </div>
                <div className="p-2.5 bg-blue-50 rounded-xl">
                  <DollarSign className="w-5 h-5 text-blue-600" />
                </div>
              </div>
              <p className="text-xs text-slate-400 mt-2">
                Avg wages: {formatCurrency(w2Summary?.AvgWages || 0)}
              </p>
            </div>

            <div className="stat-card">
              <div className="flex items-start justify-between">
                <div>
                  <p className="text-sm font-medium text-slate-500">1099 Forms</p>
                  <p className="text-2xl font-bold text-slate-900 mt-1">
                    {formatNumber(overview?.Form1099Rows || overview?.Total1099s || 0)}
                  </p>
                </div>
                <div className="p-2.5 bg-purple-50 rounded-xl">
                  <Briefcase className="w-5 h-5 text-purple-600" />
                </div>
              </div>
              <p className="text-xs text-slate-400 mt-2">Non-employment income documents</p>
            </div>
          </div>

          {/* E-File Status + W-2 Summary Row */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {/* E-File Status Breakdown */}
            <div className="bg-white rounded-xl border border-slate-200 p-6">
              <h3 className="font-semibold text-slate-900 mb-4">E-File Status Breakdown</h3>
              <div className="space-y-3">
                {safeEfileStatus.map((status: any) => {
                  const pct = ((status.StatusCount || 0) / totalEfileCount) * 100
                  const colorClass = efileColors[status.Status] || 'bg-slate-400'
                  return (
                    <div key={status.Status}>
                      <div className="flex justify-between text-sm mb-1">
                        <span className="text-slate-600 flex items-center gap-2">
                          <span className={`inline-block w-2.5 h-2.5 rounded-full ${colorClass}`} />
                          {status.Status}
                        </span>
                        <span className="font-medium">{formatNumber(status.StatusCount || 0)}</span>
                      </div>
                      <div className="h-2 bg-slate-100 rounded-full overflow-hidden">
                        <div
                          className={`h-full ${colorClass} rounded-full transition-all`}
                          style={{ width: `${pct}%` }}
                        />
                      </div>
                      {status.AvgProcessingHours != null && (
                        <p className="text-xs text-slate-400 mt-0.5">
                          Avg processing: {Number(status.AvgProcessingHours).toFixed(1)} hours
                        </p>
                      )}
                    </div>
                  )
                })}
                {safeEfileStatus.length === 0 && (
                  <p className="text-sm text-slate-400 italic">No e-file data available for this tax year</p>
                )}
              </div>
            </div>

            {/* W-2 Income Summary */}
            <div className="bg-white rounded-xl border border-slate-200 p-6">
              <h3 className="font-semibold text-slate-900 mb-4">W-2 Income Summary</h3>
              {w2Summary && (w2Summary.TotalW2s || 0) > 0 ? (
                <div className="space-y-4">
                  <div className="grid grid-cols-2 gap-4">
                    <div className="bg-slate-50 rounded-lg p-3">
                      <p className="text-xs text-slate-500 uppercase tracking-wide">Total W-2s</p>
                      <p className="text-lg font-bold text-slate-900">{formatNumber(w2Summary.TotalW2s)}</p>
                    </div>
                    <div className="bg-slate-50 rounded-lg p-3">
                      <p className="text-xs text-slate-500 uppercase tracking-wide">Avg Wages</p>
                      <p className="text-lg font-bold text-slate-900">{formatCurrency(w2Summary.AvgWages || 0)}</p>
                    </div>
                    <div className="bg-slate-50 rounded-lg p-3">
                      <p className="text-xs text-slate-500 uppercase tracking-wide">Total Wages</p>
                      <p className="text-lg font-bold text-slate-900">{formatCurrency(w2Summary.TotalWages || 0)}</p>
                    </div>
                    <div className="bg-slate-50 rounded-lg p-3">
                      <p className="text-xs text-slate-500 uppercase tracking-wide">Avg Fed Withheld</p>
                      <p className="text-lg font-bold text-slate-900">{formatCurrency(w2Summary.AvgFederalWithheld || 0)}</p>
                    </div>
                  </div>
                  <div className="bg-slate-50 rounded-lg p-3">
                    <p className="text-xs text-slate-500 uppercase tracking-wide mb-1">Top Employers (sample)</p>
                    <p className="text-sm text-slate-700">{w2Summary.TopEmployers || 'N/A'}</p>
                  </div>
                </div>
              ) : (
                <p className="text-sm text-slate-400 italic">No W-2 data available for this tax year</p>
              )}
            </div>
          </div>

          {/* 1099 + Capital Gains Row */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {/* 1099 Breakdown */}
            <div className="bg-white rounded-xl border border-slate-200 p-6">
              <h3 className="font-semibold text-slate-900 mb-4">1099 Forms by Type</h3>
              {safeForm1099.length > 0 ? (
                <div className="overflow-x-auto">
                  <table className="w-full">
                    <thead>
                      <tr className="border-b border-slate-200">
                        <th className="pb-2 text-left text-xs font-medium text-slate-500 uppercase tracking-wide">Type</th>
                        <th className="pb-2 text-right text-xs font-medium text-slate-500 uppercase tracking-wide">Count</th>
                        <th className="pb-2 text-right text-xs font-medium text-slate-500 uppercase tracking-wide">Avg Amount</th>
                        <th className="pb-2 text-right text-xs font-medium text-slate-500 uppercase tracking-wide">Total</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-slate-100">
                      {safeForm1099.map((row: any) => (
                        <tr key={row.FormType || row.Form1099Type} className="hover:bg-slate-50">
                          <td className="py-2.5 text-sm font-medium text-slate-900">{row.FormType || row.Form1099Type}</td>
                          <td className="py-2.5 text-sm text-right text-slate-600">{formatNumber(row.FormCount || row.Count || 0)}</td>
                          <td className="py-2.5 text-sm text-right text-slate-600">{formatCurrency(row.AvgGrossAmount || row.AvgAmount || 0)}</td>
                          <td className="py-2.5 text-sm text-right font-medium text-slate-900">{formatCurrency(row.TotalGrossAmount || row.TotalAmount || 0)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              ) : (
                <p className="text-sm text-slate-400 italic">No 1099 data available for this tax year</p>
              )}
            </div>

            {/* Capital Gains Summary */}
            <div className="bg-white rounded-xl border border-slate-200 p-6">
              <h3 className="font-semibold text-slate-900 mb-4">Capital Gains &amp; Losses</h3>
              {capitalGains && (capitalGains.TotalTransactions || capitalGains.TotalTrades || 0) > 0 ? (
                <div className="space-y-4">
                  <div className="grid grid-cols-2 gap-4">
                    <div className="bg-slate-50 rounded-lg p-3">
                      <p className="text-xs text-slate-500 uppercase tracking-wide">Total Trades</p>
                      <p className="text-lg font-bold text-slate-900">{formatNumber(capitalGains.TotalTransactions || capitalGains.TotalTrades || 0)}</p>
                    </div>
                    <div className="bg-slate-50 rounded-lg p-3">
                      <p className="text-xs text-slate-500 uppercase tracking-wide">Net Gain/Loss</p>
                      <p className={`text-lg font-bold ${(capitalGains.NetGainLoss || 0) >= 0 ? 'text-green-600' : 'text-red-600'}`}>
                        {formatCurrency(capitalGains.NetGainLoss || 0)}
                      </p>
                    </div>
                  </div>
                  {/* Short-term vs Long-term split */}
                  {(capitalGains.ShortTermCount || capitalGains.LongTermCount) && (
                    <div>
                      <p className="text-xs text-slate-500 uppercase tracking-wide mb-2">Short-Term vs Long-Term</p>
                      <div className="flex gap-2 items-center">
                        <div className="flex-1">
                          <div className="h-4 bg-slate-100 rounded-full overflow-hidden flex">
                            {(() => {
                              const total = (capitalGains.ShortTermCount || 0) + (capitalGains.LongTermCount || 0)
                              const shortPct = total > 0 ? ((capitalGains.ShortTermCount || 0) / total) * 100 : 50
                              return (
                                <>
                                  <div className="bg-amber-500 h-full" style={{ width: `${shortPct}%` }} />
                                  <div className="bg-blue-500 h-full" style={{ width: `${100 - shortPct}%` }} />
                                </>
                              )
                            })()}
                          </div>
                        </div>
                      </div>
                      <div className="flex justify-between text-xs text-slate-500 mt-1">
                        <span className="flex items-center gap-1">
                          <span className="inline-block w-2 h-2 rounded-full bg-amber-500" />
                          Short-term: {formatNumber(capitalGains.ShortTermCount || 0)}
                        </span>
                        <span className="flex items-center gap-1">
                          <span className="inline-block w-2 h-2 rounded-full bg-blue-500" />
                          Long-term: {formatNumber(capitalGains.LongTermCount || 0)}
                        </span>
                      </div>
                    </div>
                  )}
                  <div className="grid grid-cols-2 gap-4">
                    <div className="bg-green-50 rounded-lg p-3">
                      <p className="text-xs text-green-600 uppercase tracking-wide">Total Gains</p>
                      <p className="text-lg font-bold text-green-700">{formatCurrency(capitalGains.TotalGains || 0)}</p>
                    </div>
                    <div className="bg-red-50 rounded-lg p-3">
                      <p className="text-xs text-red-600 uppercase tracking-wide">Total Losses</p>
                      <p className="text-lg font-bold text-red-700">{formatCurrency(capitalGains.TotalLosses || 0)}</p>
                    </div>
                  </div>
                </div>
              ) : (
                <p className="text-sm text-slate-400 italic">No capital gains data available for this tax year</p>
              )}
            </div>
          </div>

          {/* Schedule C + State Tax Row */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {/* Schedule C Self-Employment */}
            <div className="bg-white rounded-xl border border-slate-200 p-6">
              <h3 className="font-semibold text-slate-900 mb-4 flex items-center gap-2">
                <TrendingUp className="w-4 h-4 text-amber-600" />
                Schedule C — Self-Employment
              </h3>
              {scheduleC && (scheduleC.TotalBusinesses || 0) > 0 ? (
                <div className="space-y-4">
                  <div className="grid grid-cols-2 gap-4">
                    <div className="bg-slate-50 rounded-lg p-3">
                      <p className="text-xs text-slate-500 uppercase tracking-wide">Businesses</p>
                      <p className="text-lg font-bold text-slate-900">{formatNumber(scheduleC.TotalBusinesses)}</p>
                    </div>
                    <div className="bg-slate-50 rounded-lg p-3">
                      <p className="text-xs text-slate-500 uppercase tracking-wide">Total Revenue</p>
                      <p className="text-lg font-bold text-slate-900">{formatCurrency(scheduleC.TotalGrossReceipts || scheduleC.TotalRevenue || 0)}</p>
                    </div>
                    <div className="bg-slate-50 rounded-lg p-3">
                      <p className="text-xs text-slate-500 uppercase tracking-wide">Total Expenses</p>
                      <p className="text-lg font-bold text-slate-900">{formatCurrency(scheduleC.TotalExpenses || 0)}</p>
                    </div>
                    <div className={`rounded-lg p-3 ${(scheduleC.TotalNetProfit || scheduleC.NetIncome || 0) >= 0 ? 'bg-green-50' : 'bg-red-50'}`}>
                      <p className="text-xs text-slate-500 uppercase tracking-wide">Net Income</p>
                      <p className={`text-lg font-bold ${(scheduleC.TotalNetProfit || scheduleC.NetIncome || 0) >= 0 ? 'text-green-700' : 'text-red-700'}`}>
                        {formatCurrency(scheduleC.TotalNetProfit || scheduleC.NetIncome || 0)}
                      </p>
                    </div>
                  </div>
                  {(scheduleC.AvgGrossReceipts || scheduleC.AvgRevenue) && (
                    <div className="flex items-center gap-4 text-sm text-slate-500">
                      <span>Avg revenue/business: {formatCurrency(scheduleC.AvgGrossReceipts || scheduleC.AvgRevenue || 0)}</span>
                      {(scheduleC.AvgNetProfit || scheduleC.AvgNetIncome) && (
                        <span>Avg net: {formatCurrency(scheduleC.AvgNetProfit || scheduleC.AvgNetIncome || 0)}</span>
                      )}
                    </div>
                  )}
                </div>
              ) : (
                <p className="text-sm text-slate-400 italic">No Schedule C data available for this tax year</p>
              )}
            </div>

            {/* State Tax Summary */}
            <div className="bg-white rounded-xl border border-slate-200 p-6">
              <h3 className="font-semibold text-slate-900 mb-4 flex items-center gap-2">
                <Building2 className="w-4 h-4 text-blue-600" />
                State Tax Filings — Top States
              </h3>
              {safeStateTax.length > 0 ? (
                <div className="overflow-x-auto">
                  <table className="w-full">
                    <thead>
                      <tr className="border-b border-slate-200">
                        <th className="pb-2 text-left text-xs font-medium text-slate-500 uppercase tracking-wide">State</th>
                        <th className="pb-2 text-right text-xs font-medium text-slate-500 uppercase tracking-wide">Returns</th>
                        <th className="pb-2 text-right text-xs font-medium text-slate-500 uppercase tracking-wide">Avg Tax</th>
                        <th className="pb-2 text-right text-xs font-medium text-slate-500 uppercase tracking-wide">Total Tax</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-slate-100">
                      {safeStateTax.slice(0, 10).map((row: any) => (
                        <tr key={row.StateCode || row.State || row.StateAbbr} className="hover:bg-slate-50">
                          <td className="py-2 text-sm font-medium text-slate-900">{row.StateCode || row.State || row.StateAbbr}</td>
                          <td className="py-2 text-sm text-right text-slate-600">{formatNumber(row.ReturnCount || row.Returns || 0)}</td>
                          <td className="py-2 text-sm text-right text-slate-600">{formatCurrency(row.AvgTaxLiability || row.AvgStateTax || row.AvgTax || 0)}</td>
                          <td className="py-2 text-sm text-right font-medium text-slate-900">{formatCurrency(row.TotalTaxLiability || row.TotalStateTax || row.TotalTax || 0)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              ) : (
                <p className="text-sm text-slate-400 italic">No state tax data available for this tax year</p>
              )}
            </div>
          </div>

          {/* Schedule E + Schedule B Row */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {/* Schedule E Rental Properties */}
            <div className="bg-white rounded-xl border border-slate-200 p-6">
              <h3 className="font-semibold text-slate-900 mb-4 flex items-center gap-2">
                <Home className="w-4 h-4 text-teal-600" />
                Schedule E — Rental &amp; Royalty
              </h3>
              {scheduleE && (scheduleE.TotalProperties || 0) > 0 ? (
                <div className="space-y-4">
                  <div className="grid grid-cols-2 gap-4">
                    <div className="bg-slate-50 rounded-lg p-3">
                      <p className="text-xs text-slate-500 uppercase tracking-wide">Properties</p>
                      <p className="text-lg font-bold text-slate-900">{formatNumber(scheduleE.TotalProperties)}</p>
                    </div>
                    <div className="bg-slate-50 rounded-lg p-3">
                      <p className="text-xs text-slate-500 uppercase tracking-wide">Total Rents</p>
                      <p className="text-lg font-bold text-slate-900">{formatCurrency(scheduleE.TotalRents || 0)}</p>
                    </div>
                    <div className="bg-slate-50 rounded-lg p-3">
                      <p className="text-xs text-slate-500 uppercase tracking-wide">Mortgage Interest</p>
                      <p className="text-lg font-bold text-slate-900">{formatCurrency(scheduleE.TotalMortgageInterest || 0)}</p>
                    </div>
                    <div className={`rounded-lg p-3 ${(scheduleE.TotalNetRentalIncome || 0) >= 0 ? 'bg-green-50' : 'bg-red-50'}`}>
                      <p className="text-xs text-slate-500 uppercase tracking-wide">Net Income</p>
                      <p className={`text-lg font-bold ${(scheduleE.TotalNetRentalIncome || 0) >= 0 ? 'text-green-700' : 'text-red-700'}`}>
                        {formatCurrency(scheduleE.TotalNetRentalIncome || 0)}
                      </p>
                    </div>
                  </div>
                  <div className="flex flex-wrap gap-3 text-xs text-slate-500">
                    <span>Single Family: {formatNumber(scheduleE.SingleFamilyCount || 0)}</span>
                    <span>Multi-Family: {formatNumber(scheduleE.MultiFamilyCount || 0)}</span>
                    <span>Commercial: {formatNumber(scheduleE.CommercialCount || 0)}</span>
                    <span>Royalty: {formatNumber(scheduleE.RoyaltyCount || 0)}</span>
                  </div>
                </div>
              ) : (
                <p className="text-sm text-slate-400 italic">No Schedule E data available for this tax year</p>
              )}
            </div>

            {/* Schedule B Interest & Dividends */}
            <div className="bg-white rounded-xl border border-slate-200 p-6">
              <h3 className="font-semibold text-slate-900 mb-4 flex items-center gap-2">
                <Landmark className="w-4 h-4 text-indigo-600" />
                Schedule B — Interest &amp; Dividends
              </h3>
              {scheduleB && (scheduleB.TotalEntries || 0) > 0 ? (
                <div className="space-y-4">
                  <div className="grid grid-cols-2 gap-4">
                    <div className="bg-blue-50 rounded-lg p-3">
                      <p className="text-xs text-blue-600 uppercase tracking-wide">Interest Income</p>
                      <p className="text-lg font-bold text-blue-700">{formatCurrency(scheduleB.TotalInterestIncome || 0)}</p>
                    </div>
                    <div className="bg-purple-50 rounded-lg p-3">
                      <p className="text-xs text-purple-600 uppercase tracking-wide">Dividend Income</p>
                      <p className="text-lg font-bold text-purple-700">{formatCurrency(scheduleB.TotalDividendIncome || 0)}</p>
                    </div>
                    <div className="bg-slate-50 rounded-lg p-3">
                      <p className="text-xs text-slate-500 uppercase tracking-wide">Total Entries</p>
                      <p className="text-lg font-bold text-slate-900">{formatNumber(scheduleB.TotalEntries)}</p>
                    </div>
                    <div className="bg-slate-50 rounded-lg p-3">
                      <p className="text-xs text-slate-500 uppercase tracking-wide">Foreign Accounts</p>
                      <p className="text-lg font-bold text-slate-900">{formatNumber(scheduleB.ForeignAccountCount || 0)}</p>
                    </div>
                  </div>
                  {scheduleB.TotalTaxExempt > 0 && (
                    <p className="text-xs text-slate-500">
                      Tax-exempt: {formatCurrency(scheduleB.TotalTaxExempt)} • Foreign tax paid: {formatCurrency(scheduleB.TotalForeignTaxPaid || 0)}
                    </p>
                  )}
                </div>
              ) : (
                <p className="text-sm text-slate-400 italic">No Schedule B data available for this tax year</p>
              )}
            </div>
          </div>

          {/* Document Summary Row */}
          <div className="bg-white rounded-xl border border-slate-200 p-6">
            <h3 className="font-semibold text-slate-900 mb-4 flex items-center gap-2">
              <FolderOpen className="w-4 h-4 text-orange-600" />
              Tax Form Documents
            </h3>
            {documents && (documents.TotalDocuments || 0) > 0 ? (
              <div className="space-y-4">
                <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                  <div className="bg-slate-50 rounded-lg p-3">
                    <p className="text-xs text-slate-500 uppercase tracking-wide">Total Documents</p>
                    <p className="text-lg font-bold text-slate-900">{formatNumber(documents.TotalDocuments)}</p>
                  </div>
                  <div className="bg-slate-50 rounded-lg p-3">
                    <p className="text-xs text-slate-500 uppercase tracking-wide">Total Pages</p>
                    <p className="text-lg font-bold text-slate-900">{formatNumber(documents.TotalPages || 0)}</p>
                  </div>
                  <div className="bg-slate-50 rounded-lg p-3">
                    <p className="text-xs text-slate-500 uppercase tracking-wide">Storage</p>
                    <p className="text-lg font-bold text-slate-900">{documents.TotalStorageGB || 0} GB</p>
                  </div>
                  <div className="bg-slate-50 rounded-lg p-3">
                    <p className="text-xs text-slate-500 uppercase tracking-wide">Returns Covered</p>
                    <p className="text-lg font-bold text-slate-900">{formatNumber(documents.ReturnCount || 0)}</p>
                  </div>
                </div>
                <div className="flex flex-wrap gap-4 text-xs text-slate-500">
                  <span className="flex items-center gap-1">
                    <span className="inline-block w-2 h-2 rounded-full bg-green-500" />
                    Submitted: {formatNumber(documents.SubmittedCount || 0)}
                  </span>
                  <span className="flex items-center gap-1">
                    <span className="inline-block w-2 h-2 rounded-full bg-blue-500" />
                    Signed: {formatNumber(documents.SignedCount || 0)}
                  </span>
                  <span className="flex items-center gap-1">
                    <span className="inline-block w-2 h-2 rounded-full bg-amber-500" />
                    Generated: {formatNumber(documents.GeneratedCount || 0)}
                  </span>
                  <span className="flex items-center gap-1">
                    <span className="inline-block w-2 h-2 rounded-full bg-slate-400" />
                    Archived: {formatNumber(documents.ArchivedCount || 0)}
                  </span>
                </div>
                <div className="flex flex-wrap gap-4 text-xs text-slate-500">
                  <span>1040s: {formatNumber(documents.Form1040Count || 0)}</span>
                  <span>W-2 copies: {formatNumber(documents.W2CopyCount || 0)}</span>
                  <span>Schedules: {formatNumber(documents.ScheduleCount || 0)}</span>
                </div>
              </div>
            ) : (
              <p className="text-sm text-slate-400 italic">No document data available for this tax year</p>
            )}
          </div>

          {/* Tech Banner */}
          <div className="bg-amber-50 rounded-xl p-4 border border-amber-100 flex items-start gap-3">
            <Database className="w-5 h-5 text-amber-600 mt-0.5 shrink-0" />
            <p className="text-sm text-amber-800">
              <strong>HTAP with Hyperscale:</strong> All filing analytics queries are executed on a
              <strong> Hyperscale named replica</strong> using <strong>Nonclustered Columnstore Indexes (NCCIs)</strong> across
              18 detail tables — form line items, income documents, e-file tracking, schedules, rental properties, investment income, tax form documents, and audit logs —
              completely isolated from OLTP write workloads on the primary.
            </p>
          </div>
        </>
      )}
    </div>
  )
}
