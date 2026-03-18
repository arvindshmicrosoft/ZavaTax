import { FileText, MessageSquare, ArrowRight, Eye, Calendar, DollarSign } from 'lucide-react'
import { Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { api } from '../../lib/api'

interface TaxReturn {
  ReturnId: number
  TaxYear: number
  FilingStatus: string
  FilingDate: string | null
  RefundAmount: number
  AmountOwed: number
  Status?: string
}

export default function TaxFilerDashboard() {
  const { data: returns, isLoading } = useQuery({
    queryKey: ['my-returns'],
    queryFn: () => api.getTaxReturns({ filter: 'CustomerId eq 1', orderby: 'FilingDate desc' }),
  })

  // Calculate stats from actual return data
  const myReturns: TaxReturn[] = returns?.value || []
  const latestReturn = myReturns[0]
  const taxYearsFiled = myReturns.length

  const stats = [
    { name: 'Tax Years Filed', value: taxYearsFiled, icon: FileText, bgColor: 'bg-emerald-100', iconColor: 'text-emerald-600' },
    { name: 'Latest Return', value: latestReturn?.TaxYear || '—', icon: Calendar, bgColor: 'bg-amber-100', iconColor: 'text-amber-600' },
    { name: 'Last Refund', value: latestReturn?.RefundAmount ? `$${latestReturn.RefundAmount.toLocaleString()}` : '—', icon: DollarSign, bgColor: 'bg-sky-100', iconColor: 'text-sky-600' },
  ]

  return (
    <div className="space-y-6">
      {/* Header with Quick Actions */}
      <div className="flex flex-col lg:flex-row lg:items-start lg:justify-between gap-6">
        <div className="page-header mb-0">
          <h1 className="page-title">Your Tax Dashboard</h1>
          <p className="page-subtitle">Manage your tax returns and get help</p>
        </div>
        <div className="flex flex-wrap gap-3">
          <Link to="/filer/new-return" className="btn btn-primary flex items-center gap-2">
            <FileText className="w-4 h-4" />
            Start New Return
          </Link>
          <Link to="/filer/returns" className="btn btn-outline flex items-center gap-2">
            <FileText className="w-4 h-4" />
            View Returns
          </Link>
        </div>
      </div>

      {/* Stats Row */}
      <div className="grid grid-cols-2 lg:grid-cols-3 gap-4">
        {stats.map((stat) => (
          <div key={stat.name} className="stat-card">
            <div className="flex items-center gap-4">
              <div className={`w-12 h-12 rounded-lg ${stat.bgColor} flex items-center justify-center flex-shrink-0`}>
                <stat.icon className={`w-6 h-6 ${stat.iconColor}`} />
              </div>
              <div>
                <p className="text-2xl font-bold text-slate-900">{stat.value}</p>
                <p className="text-sm text-slate-500">{stat.name}</p>
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* Main Content - Two Column Layout */}
      <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">
        {/* Recent Returns - Takes 2 columns */}
        <div className="xl:col-span-2 card">
          <div className="card-header flex items-center justify-between">
            <h2 className="font-semibold">Recent Returns</h2>
            <Link to="/filer/returns" className="text-sm font-medium text-zava-600 hover:text-zava-700 flex items-center gap-1">
              View all <ArrowRight className="w-4 h-4" />
            </Link>
          </div>
          <div className="card-body">
            {isLoading ? (
              <div className="space-y-3">
                {[1, 2, 3].map((i) => (
                  <div key={i} className="h-14 bg-slate-100 rounded-md animate-pulse" />
                ))}
              </div>
            ) : returns?.value?.length > 0 ? (
              <div className="space-y-3">
                {returns.value.map((ret: { ReturnId: number; TaxYear: number; FilingStatus: string; Status: string; RefundAmount?: number }) => (
                  <div
                    key={ret.ReturnId}
                    className="flex items-center justify-between p-4 bg-slate-50 hover:bg-slate-100 rounded-md"
                  >
                    <div className="flex items-center gap-3">
                      <div className="w-10 h-10 bg-white rounded-md flex items-center justify-center border border-slate-200">
                        <FileText className="w-5 h-5 text-slate-600" />
                      </div>
                      <div>
                        <p className="font-medium text-slate-900">Tax Year {ret.TaxYear}</p>
                        <p className="text-sm text-slate-500">{ret.FilingStatus}</p>
                      </div>
                    </div>
                    <div className="flex items-center gap-3">
                      {(ret.RefundAmount ?? 0) > 0 && (
                        <span className="text-emerald-600 font-medium">
                          +${ret.RefundAmount!.toLocaleString()}
                        </span>
                      )}
                      <Link
                        to="/filer/returns"
                        className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium text-zava-600 hover:text-zava-700 hover:bg-zava-50 rounded-md transition-colors"
                      >
                        <Eye className="w-4 h-4" />
                        View
                      </Link>
                    </div>
                  </div>
                ))}
              </div>
            ) : (
              <div className="text-center py-8">
                <div className="w-14 h-14 bg-slate-100 rounded-lg flex items-center justify-center mx-auto mb-3">
                  <FileText className="w-7 h-7 text-slate-400" />
                </div>
                <p className="text-slate-600 font-medium">No returns found</p>
                <p className="text-slate-400 text-sm mt-1">Start by asking about your taxes</p>
              </div>
            )}
          </div>
        </div>

        {/* Right Sidebar */}
        <div className="space-y-6">
          {/* AI Tax Assistant */}
          <div className="card bg-gradient-to-br from-zava-50 to-purple-50 border-zava-200">
            <div className="card-body">
              <div className="flex items-start gap-3">
                <div className="w-10 h-10 bg-zava-100 rounded-lg flex items-center justify-center flex-shrink-0">
                  <MessageSquare className="w-5 h-5 text-zava-600" />
                </div>
                <div>
                  <h3 className="font-semibold text-slate-900">AI Tax Assistant</h3>
                  <p className="text-sm text-slate-600 mt-1">
                    Get instant help understanding deductions, credits, filing requirements, and more.
                  </p>
                  <Link to="/filer/ask" className="btn btn-primary mt-3 inline-flex items-center gap-2 text-sm">
                    <MessageSquare className="w-4 h-4" />
                    Ask a Question
                  </Link>
                </div>
              </div>
            </div>
          </div>

          {/* Quick Links */}
          <div className="card">
            <div className="card-header">
              <h2 className="font-semibold">Quick Links</h2>
            </div>
            <div className="card-body space-y-2">
              <Link to="/filer/new-return" className="flex items-center gap-3 p-2 rounded-lg hover:bg-slate-50 transition-colors">
                <FileText className="w-5 h-5 text-emerald-600" />
                <span className="text-sm font-medium text-slate-700">Start New Return</span>
              </Link>
              <Link to="/filer/returns" className="flex items-center gap-3 p-2 rounded-lg hover:bg-slate-50 transition-colors">
                <Eye className="w-5 h-5 text-blue-600" />
                <span className="text-sm font-medium text-slate-700">View All Returns</span>
              </Link>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
