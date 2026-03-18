import { useQuery } from '@tanstack/react-query'
import { 
  Activity, 
  Database, 
  Zap, 
  HardDrive, 
  Cpu, 
  AlertTriangle,
  CheckCircle
} from 'lucide-react'
import { Link } from 'react-router-dom'
import { api } from '../../lib/api'

export default function DevOpsDashboard() {
  const { data, isLoading, error } = useQuery({
    queryKey: ['hyperscale-metrics'],
    queryFn: () => api.getHyperscaleResourceStatsAll(),
    refetchInterval: 5000,
  })

  const primary = data?.primary

  const systemStatus = [
    { name: 'Primary Database', status: 'healthy', latency: '2.1ms' },
    { name: 'Read Replica', status: 'healthy', latency: '3.4ms' },
    { name: 'Columnstore Indexes', status: 'healthy', latency: 'N/A' },
    { name: 'Vector Indexes', status: 'healthy', latency: '5.2ms' },
  ]

  const quickStats = [
    { name: 'CPU Utilization', value: primary?.AvgCpuPercent !== null && primary?.AvgCpuPercent !== undefined ? `${primary.AvgCpuPercent.toFixed(1)}%` : '—', icon: Cpu, bgColor: 'bg-purple-100', iconColor: 'text-purple-600' },
    { name: 'Data I/O', value: primary?.AvgDataIoPercent !== null && primary?.AvgDataIoPercent !== undefined ? `${primary.AvgDataIoPercent.toFixed(1)}%` : '—', icon: Database, bgColor: 'bg-blue-100', iconColor: 'text-blue-600' },
    { name: 'Log Write', value: primary?.AvgLogWritePercent !== null && primary?.AvgLogWritePercent !== undefined ? `${primary.AvgLogWritePercent.toFixed(1)}%` : '—', icon: Zap, bgColor: 'bg-emerald-100', iconColor: 'text-emerald-600' },
    { name: 'Worker Threads', value: primary?.MaxWorkerPercent !== null && primary?.MaxWorkerPercent !== undefined ? `${primary.MaxWorkerPercent.toFixed(1)}%` : '—', icon: HardDrive, bgColor: 'bg-amber-100', iconColor: 'text-amber-600' },
  ]

  if (error) {
    return (
      <div className="space-y-6">
        <div className="page-header">
          <h1 className="page-title">DevOps Dashboard</h1>
          <p className="page-subtitle">System monitoring and health</p>
        </div>
        <div className="bg-amber-50 border border-amber-200 rounded-lg p-6">
          <div className="flex items-start gap-3">
            <AlertTriangle className="w-5 h-5 text-amber-600 mt-0.5 shrink-0" />
            <div>
              <h3 className="font-semibold text-amber-900 mb-1">Unable to load metrics</h3>
              <p className="text-sm text-amber-800">
                The monitoring endpoints may not be configured or the database doesn't have recent activity.
                Metrics require the database to have been active for at least 15 seconds.
              </p>
            </div>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Header with Status */}
      <div className="flex flex-col lg:flex-row lg:items-start lg:justify-between gap-6">
        <div className="page-header mb-0">
          <h1 className="page-title">DevOps Dashboard</h1>
          <p className="page-subtitle">System monitoring and health</p>
        </div>
        <div className="flex flex-wrap items-center gap-3">
          <div className="flex items-center gap-2 px-3 py-1.5 bg-emerald-50 rounded-md">
            <span className="w-2 h-2 bg-emerald-500 rounded-full" />
            <span className="text-sm text-emerald-700 font-medium">All Systems Operational</span>
          </div>
          <Link to="/devops/metrics" className="btn btn-primary flex items-center gap-2">
            <Activity className="w-4 h-4" />
            Detailed Metrics
          </Link>
        </div>
      </div>

      {/* Info Banner if no data available yet */}
      {primary && primary.AvgCpuPercent === null && !isLoading && (
        <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
          <div className="flex items-start gap-3">
            <Database className="w-5 h-5 text-blue-600 mt-0.5 shrink-0" />
            <div>
              <h3 className="font-semibold text-blue-900 mb-1">Metrics Collecting</h3>
              <p className="text-sm text-blue-800">
                Database metrics are collected every 15 seconds. If this is a new database or hasn't been active recently,
                please wait a moment for the first metrics to appear. The dashboard will auto-refresh every 5 seconds.
              </p>
            </div>
          </div>
        </div>
      )}

      {/* Quick Stats */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        {quickStats.map((stat) => (
          <div key={stat.name} className="stat-card">
            <div className="flex items-center justify-start mb-3">
              <div className={`w-12 h-12 rounded-lg ${stat.bgColor} flex items-center justify-center`}>
                <stat.icon className={`w-5 h-5 ${stat.iconColor}`} />
              </div>
            </div>
            <p className="text-2xl font-bold text-slate-900">{stat.value}</p>
            <p className="text-sm text-slate-500">{stat.name}</p>
          </div>
        ))}
      </div>

      {/* Main Content - Two Column Layout */}
      <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">
        {/* System Status - Takes 2 columns */}
        <div className="xl:col-span-2 card">
          <div className="card-header">
            <h2 className="font-semibold">System Status</h2>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="text-left text-xs font-semibold text-slate-500 uppercase tracking-wider border-b border-slate-200">
                  <th className="p-4">Service</th>
                  <th className="p-4">Status</th>
                  <th className="p-4 text-right">Latency</th>
                  <th className="p-4 text-right">Uptime</th>
                </tr>
              </thead>
              <tbody>
                {systemStatus.map((system) => (
                  <tr key={system.name} className="border-b border-slate-100 last:border-0">
                    <td className="p-4">
                      <div className="flex items-center gap-3">
                        {system.status === 'healthy' ? (
                          <CheckCircle className="w-5 h-5 text-emerald-500" />
                        ) : (
                          <AlertTriangle className="w-5 h-5 text-amber-500" />
                        )}
                        <span className="font-medium text-slate-900">{system.name}</span>
                      </div>
                    </td>
                    <td className="p-4">
                      <span className={`badge ${
                        system.status === 'healthy' ? 'badge-success' : 'badge-warning'
                      }`}>
                        {system.status}
                      </span>
                    </td>
                    <td className="p-4 text-right text-slate-600">{system.latency}</td>
                    <td className="p-4 text-right text-emerald-600 font-medium">99.99%</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        {/* Architecture Overview - Sidebar */}
        <div className="card">
          <div className="card-header">Architecture</div>
          <div className="card-body space-y-4">
            <div className="p-3 bg-slate-50 rounded-lg">
              <Database className="w-6 h-6 text-blue-600 mb-2" />
              <h3 className="font-medium text-slate-900">Compute Tier</h3>
              <p className="text-sm text-slate-600 mt-1">
                Primary compute + read replicas
              </p>
            </div>
            <div className="p-3 bg-slate-50 rounded-lg">
              <HardDrive className="w-6 h-6 text-purple-600 mb-2" />
              <h3 className="font-medium text-slate-900">Storage Layer</h3>
              <p className="text-sm text-slate-600 mt-1">
                Distributed storage up to 100TB
              </p>
            </div>
            <div className="p-3 bg-slate-50 rounded-lg">
              <Zap className="w-6 h-6 text-amber-600 mb-2" />
              <h3 className="font-medium text-slate-900">Log Service</h3>
              <p className="text-sm text-slate-600 mt-1">
                High throughput transaction log
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
