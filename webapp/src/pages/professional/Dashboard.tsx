import { useQuery } from '@tanstack/react-query'
import { 
  Users, FileText, Clock, Search, BookOpen, ArrowRight, 
  AlertTriangle, CheckCircle, PlayCircle, Calendar,
  ChevronRight
} from 'lucide-react'
import { Link, useNavigate } from 'react-router-dom'
import { api } from '../../lib/api'
import { getCurrentUser } from '../../lib/mockUsers'

interface TaxReturn {
  ReturnId: number
  CustomerId: number
  TaxYear: number
  FilingStatus: string
  FilingDate: string | null
  GrossIncome: number
  RefundAmount: number
  AmountOwed: number
  Status?: string
  customer?: {
    FirstName: string
    LastName: string
    Email: string
  }
}

export default function ProfessionalDashboard() {
  const navigate = useNavigate()
  const user = getCurrentUser()
  const professionalId = user?.professionalId ?? 1

  // Fetch clients for count
  const { data: clients } = useQuery({
    queryKey: ['my-clients'],
    queryFn: () => api.getCustomers(),
  })

  // Fetch tax returns to derive stats
  const { data: taxReturns } = useQuery({
    queryKey: ['my-returns', professionalId],
    queryFn: () => api.getTaxReturns({ filter: `ProfessionalId eq ${professionalId}`, orderby: 'FilingDate desc' }),
  })

  // Calculate real stats from data
  const totalClients = clients?.value?.length || 0
  const allReturns = taxReturns?.value || []
  
  // Categorize returns by status (simulated based on data patterns)
  const pendingReturns = allReturns.filter((r: TaxReturn) => !r.FilingDate)
  const completedReturns = allReturns.filter((r: TaxReturn) => r.FilingDate)
  const currentYearReturns = allReturns.filter((r: TaxReturn) => r.TaxYear === 2025)
  
  // Get recent returns (last 5 with filing dates)
  const recentlyCompleted = completedReturns.slice(0, 5)
  
  // Simulate returns needing attention (those without filing dates or high amounts owed)
  const needsAttention = allReturns
    .filter((r: TaxReturn) => !r.FilingDate || r.AmountOwed > 5000)
    .slice(0, 4)

  const stats = [
    { 
      name: 'Active Clients', 
      value: totalClients, 
      icon: Users, 
      bgColor: 'bg-blue-100', 
      iconColor: 'text-blue-600',
      link: '/professional/clients'
    },
    { 
      name: 'Returns in Progress', 
      value: pendingReturns.length, 
      icon: PlayCircle, 
      bgColor: 'bg-amber-100', 
      iconColor: 'text-amber-600',
      link: '/professional/clients'
    },
    { 
      name: 'Completed (2025)', 
      value: currentYearReturns.filter((r: TaxReturn) => r.FilingDate).length, 
      icon: CheckCircle, 
      bgColor: 'bg-emerald-100', 
      iconColor: 'text-emerald-600',
      link: '/professional/clients'
    },
    { 
      name: 'Needs Review', 
      value: needsAttention.length, 
      icon: AlertTriangle, 
      bgColor: 'bg-red-100', 
      iconColor: 'text-red-600',
      link: '/professional/clients'
    },
  ]

  const handleReturnClick = (ret: TaxReturn) => {
    // Navigate to clients page and select this client
    navigate(`/professional/clients?clientId=${ret.CustomerId}`)
  }

  return (
    <div className="space-y-6">
      {/* Header with Actions */}
      <div className="flex flex-col lg:flex-row lg:items-start lg:justify-between gap-6">
        <div className="page-header mb-0">
          <h1 className="page-title">Dashboard</h1>
          <p className="page-subtitle">Welcome back! Here's your workload overview.</p>
        </div>
        <div className="flex flex-wrap gap-3">
          <Link to="/professional/clients" className="btn btn-primary flex items-center gap-2">
            <Plus className="w-4 h-4" />
            New Return
          </Link>
        </div>
      </div>

      {/* Stats Grid - Clickable */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        {stats.map((stat) => (
          <Link 
            key={stat.name} 
            to={stat.link}
            className="stat-card hover:shadow-md transition-shadow cursor-pointer group"
          >
            <div className="flex items-center gap-4">
              <div className={`w-12 h-12 rounded-lg ${stat.bgColor} flex items-center justify-center flex-shrink-0`}>
                <stat.icon className={`w-5 h-5 ${stat.iconColor}`} />
              </div>
              <div className="flex-1">
                <p className="text-2xl font-bold text-slate-900">{stat.value}</p>
                <p className="text-slate-500 text-sm">{stat.name}</p>
              </div>
              <ChevronRight className="w-4 h-4 text-slate-300 group-hover:text-slate-500 transition-colors" />
            </div>
          </Link>
        ))}
      </div>

      {/* Main Content - Two Column Layout */}
      <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">
        {/* Left Column - Action Items */}
        <div className="xl:col-span-2 space-y-6">
          {/* Needs Attention */}
          <div className="card">
            <div className="card-header flex items-center justify-between">
              <div className="flex items-center gap-2">
                <AlertTriangle className="w-5 h-5 text-amber-500" />
                <h2 className="font-semibold">Needs Attention</h2>
              </div>
              <span className="badge badge-warning">{needsAttention.length} items</span>
            </div>
            <div className="card-body">
              {needsAttention.length > 0 ? (
                <div className="space-y-3">
                  {needsAttention.map((ret: TaxReturn) => {
                    // Find client info
                    const client = clients?.value?.find((c: { CustomerId: number }) => c.CustomerId === ret.CustomerId)
                    return (
                      <div
                        key={ret.ReturnId}
                        onClick={() => handleReturnClick(ret)}
                        className="flex items-center justify-between p-4 bg-amber-50 border border-amber-100 rounded-lg hover:bg-amber-100 transition-colors cursor-pointer group"
                      >
                        <div className="flex items-center gap-4">
                          <div className="w-10 h-10 bg-amber-200 rounded-full flex items-center justify-center">
                            <FileText className="w-5 h-5 text-amber-700" />
                          </div>
                          <div>
                            <p className="font-medium text-slate-900">
                              {client ? `${client.FirstName} ${client.LastName}` : `Client #${ret.CustomerId}`}
                            </p>
                            <p className="text-sm text-slate-500">
                              {ret.TaxYear} Return • {!ret.FilingDate ? 'Not filed' : `Owes $${ret.AmountOwed.toLocaleString()}`}
                            </p>
                          </div>
                        </div>
                        <div className="flex items-center gap-3">
                          {ret.AmountOwed > 0 && (
                            <span className="text-sm font-medium text-red-600">
                              ${ret.AmountOwed.toLocaleString()} owed
                            </span>
                          )}
                          <ChevronRight className="w-5 h-5 text-slate-300 group-hover:text-slate-500" />
                        </div>
                      </div>
                    )
                  })}
                </div>
              ) : (
                <div className="text-center py-8 text-slate-500">
                  <CheckCircle className="w-12 h-12 mx-auto mb-3 text-emerald-300" />
                  <p>All caught up! No items need immediate attention.</p>
                </div>
              )}
            </div>
          </div>

          {/* Recently Completed */}
          <div className="card">
            <div className="card-header flex items-center justify-between">
              <div className="flex items-center gap-2">
                <Clock className="w-5 h-5 text-slate-400" />
                <h2 className="font-semibold">Recently Completed</h2>
              </div>
              <Link to="/professional/clients" className="text-sm text-zava-600 hover:text-zava-700 flex items-center gap-1">
                View All <ArrowRight className="w-4 h-4" />
              </Link>
            </div>
            <div className="card-body">
              {recentlyCompleted.length > 0 ? (
                <div className="space-y-2">
                  {recentlyCompleted.map((ret: TaxReturn) => {
                    const client = clients?.value?.find((c: { CustomerId: number }) => c.CustomerId === ret.CustomerId)
                    return (
                      <div
                        key={ret.ReturnId}
                        onClick={() => handleReturnClick(ret)}
                        className="flex items-center justify-between p-3 rounded-lg hover:bg-slate-50 transition-colors cursor-pointer group"
                      >
                        <div className="flex items-center gap-3">
                          <div className="w-8 h-8 bg-emerald-100 rounded-full flex items-center justify-center">
                            <CheckCircle className="w-4 h-4 text-emerald-600" />
                          </div>
                          <div>
                            <p className="font-medium text-slate-900">
                              {client ? `${client.FirstName} ${client.LastName}` : `Client #${ret.CustomerId}`}
                            </p>
                            <p className="text-xs text-slate-500">
                              {ret.TaxYear} • Filed {ret.FilingDate ? new Date(ret.FilingDate).toLocaleDateString() : 'N/A'}
                            </p>
                          </div>
                        </div>
                        <div className="flex items-center gap-3">
                          {ret.RefundAmount > 0 ? (
                            <span className="text-sm font-medium text-emerald-600">
                              +${ret.RefundAmount.toLocaleString()}
                            </span>
                          ) : ret.AmountOwed > 0 ? (
                            <span className="text-sm font-medium text-red-600">
                              -${ret.AmountOwed.toLocaleString()}
                            </span>
                          ) : null}
                          <ChevronRight className="w-4 h-4 text-slate-300 group-hover:text-slate-500" />
                        </div>
                      </div>
                    )
                  })}
                </div>
              ) : (
                <p className="text-slate-500 text-center py-8">No completed returns yet</p>
              )}
            </div>
          </div>
        </div>

        {/* Right Sidebar */}
        <div className="space-y-6">
          {/* Quick Actions */}
          <div className="card">
            <div className="card-header">
              <h2 className="font-semibold">Quick Actions</h2>
            </div>
            <div className="card-body space-y-2">
              <Link to="/professional/clients" className="flex items-center gap-3 p-3 rounded-lg hover:bg-slate-50 transition-colors">
                <div className="w-10 h-10 bg-zava-100 rounded-lg flex items-center justify-center">
                  <Users className="w-5 h-5 text-zava-600" />
                </div>
                <div className="flex-1">
                  <p className="font-medium text-slate-900">My Clients</p>
                  <p className="text-xs text-slate-500">{totalClients} clients</p>
                </div>
                <ArrowRight className="w-4 h-4 text-slate-400" />
              </Link>
              <Link to="/professional/cases" className="flex items-center gap-3 p-3 rounded-lg hover:bg-slate-50 transition-colors">
                <div className="w-10 h-10 bg-purple-100 rounded-lg flex items-center justify-center">
                  <Search className="w-5 h-5 text-purple-600" />
                </div>
                <div className="flex-1">
                  <p className="font-medium text-slate-900">Similar Cases</p>
                  <p className="text-xs text-slate-500">AI-powered search</p>
                </div>
                <ArrowRight className="w-4 h-4 text-slate-400" />
              </Link>
              <Link to="/professional/knowledge" className="flex items-center gap-3 p-3 rounded-lg hover:bg-slate-50 transition-colors">
                <div className="w-10 h-10 bg-emerald-100 rounded-lg flex items-center justify-center">
                  <BookOpen className="w-5 h-5 text-emerald-600" />
                </div>
                <div className="flex-1">
                  <p className="font-medium text-slate-900">Knowledge Base</p>
                  <p className="text-xs text-slate-500">Tax regulations</p>
                </div>
                <ArrowRight className="w-4 h-4 text-slate-400" />
              </Link>
            </div>
          </div>

          {/* Performance Summary */}
          <div className="card">
            <div className="card-header">
              <h2 className="font-semibold">2025 Summary</h2>
            </div>
            <div className="card-body space-y-4">
              <div className="flex justify-between items-center">
                <span className="text-sm text-slate-600">Total Returns</span>
                <span className="font-semibold text-slate-900">{currentYearReturns.length}</span>
              </div>
              <div className="flex justify-between items-center">
                <span className="text-sm text-slate-600">Completed</span>
                <span className="font-semibold text-emerald-600">
                  {currentYearReturns.filter((r: TaxReturn) => r.FilingDate).length}
                </span>
              </div>
              <div className="flex justify-between items-center">
                <span className="text-sm text-slate-600">In Progress</span>
                <span className="font-semibold text-amber-600">
                  {currentYearReturns.filter((r: TaxReturn) => !r.FilingDate).length}
                </span>
              </div>
              <div className="border-t pt-4 mt-4">
                <div className="flex justify-between items-center">
                  <span className="text-sm text-slate-600">Total Refunds</span>
                  <span className="font-semibold text-emerald-600">
                    ${currentYearReturns.reduce((sum: number, r: TaxReturn) => sum + (r.RefundAmount || 0), 0).toLocaleString()}
                  </span>
                </div>
              </div>
            </div>
          </div>

          {/* Upcoming Deadlines */}
          <div className="card">
            <div className="card-header">
              <h2 className="font-semibold">Key Dates</h2>
            </div>
            <div className="card-body space-y-3">
              <div className="flex items-center gap-3 p-2 bg-red-50 rounded-lg">
                <Calendar className="w-5 h-5 text-red-500" />
                <div>
                  <p className="text-sm font-medium text-slate-900">April 15, 2026</p>
                  <p className="text-xs text-slate-500">Federal Tax Deadline</p>
                </div>
              </div>
              <div className="flex items-center gap-3 p-2 bg-amber-50 rounded-lg">
                <Calendar className="w-5 h-5 text-amber-500" />
                <div>
                  <p className="text-sm font-medium text-slate-900">March 15, 2026</p>
                  <p className="text-xs text-slate-500">S-Corp & Partnership</p>
                </div>
              </div>
              <div className="flex items-center gap-3 p-2 bg-blue-50 rounded-lg">
                <Calendar className="w-5 h-5 text-blue-500" />
                <div>
                  <p className="text-sm font-medium text-slate-900">October 15, 2026</p>
                  <p className="text-xs text-slate-500">Extended Returns</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

// Plus icon component
function Plus({ className }: { className?: string }) {
  return (
    <svg className={className} fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M12 4v16m8-8H4" />
    </svg>
  )
}
