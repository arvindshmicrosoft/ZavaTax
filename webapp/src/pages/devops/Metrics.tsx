import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { 
  Activity, 
  Database,
  Zap, 
  Clock,
  RefreshCw,
  AlertTriangle
} from 'lucide-react'
import { api, type HyperscaleResourceStats } from '../../lib/api'

interface MetricCard {
  name: string
  value: string | number
  unit: string
  icon: React.ComponentType<{ className?: string }>
}

export default function Metrics() {
  const [autoRefresh, setAutoRefresh] = useState(true)

  const { isLoading, error, refetch, data } = useQuery({
    queryKey: ['hyperscale-metrics-detail'],
    queryFn: () => api.getHyperscaleResourceStatsAll(),
    refetchInterval: autoRefresh ? 5000 : false,
  })

  const primary = data?.primary
  const readOnly = data?.readOnly
  const analytics = data?.analytics

  const formatPercent = (value: number | null | undefined) => {
    if (value === null || value === undefined) return '—'
    return `${value.toFixed(1)}%`
  }

  const formatSnapshot = (value: string | null | undefined) =>
    value ? new Date(value).toLocaleString() : '—'

  const metricCards: MetricCard[] = [
    {
      name: 'CPU Usage (Primary)',
      value: primary?.AvgCpuPercent !== null && primary?.AvgCpuPercent !== undefined ? primary.AvgCpuPercent.toFixed(1) : '—',
      unit: '%',
      icon: Activity,
    },
    {
      name: 'Data I/O (Primary)',
      value: primary?.AvgDataIoPercent !== null && primary?.AvgDataIoPercent !== undefined ? primary.AvgDataIoPercent.toFixed(1) : '—',
      unit: '%',
      icon: Database,
    },
    {
      name: 'Log Write (Primary)',
      value: primary?.AvgLogWritePercent !== null && primary?.AvgLogWritePercent !== undefined ? primary.AvgLogWritePercent.toFixed(1) : '—',
      unit: '%',
      icon: Zap,
    },
    {
      name: 'Worker Thread % (Primary)',
      value: primary?.MaxWorkerPercent !== null && primary?.MaxWorkerPercent !== undefined ? primary.MaxWorkerPercent.toFixed(1) : '—',
      unit: '%',
      icon: Clock,
    },
  ]

  const endpointRows: Array<{ name: string; stats: HyperscaleResourceStats | null | undefined }> = [
    { name: 'Primary (Read/Write)', stats: primary },
    { name: 'HA Read Replica', stats: readOnly },
    { name: 'Named Replica (Analytics)', stats: analytics },
  ]

  // Check if we have data but all metrics are null (not just 0)
  const hasNoMetrics = data && primary && (
    primary.AvgCpuPercent === null && 
    primary.AvgDataIoPercent === null && 
    primary.AvgLogWritePercent === null && 
    primary.MaxWorkerPercent === null
  )

  if (error) {
    return (
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">Hyperscale Metrics</h1>
          <p className="text-slate-600 mt-1">Real-time database performance monitoring</p>
        </div>
        <div className="bg-amber-50 border border-amber-200 rounded-lg p-6">
          <div className="flex items-start gap-3">
            <AlertTriangle className="w-5 h-5 text-amber-600 mt-0.5 shrink-0" />
            <div>
              <h3 className="font-semibold text-amber-900 mb-1">Unable to load metrics</h3>
              <p className="text-sm text-amber-800 mb-3">
                The monitoring endpoints may not be configured or the database doesn't have recent activity.
                Metrics require the database to have been active for at least 15 seconds.
              </p>
              <button
                onClick={() => refetch()}
                className="btn btn-primary btn-sm flex items-center gap-2"
              >
                <RefreshCw className="w-4 h-4" />
                Try Again
              </button>
            </div>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">Hyperscale Metrics</h1>
          <p className="text-slate-600 mt-1">Real-time database performance monitoring</p>
        </div>
        <div className="flex items-center gap-3">
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={autoRefresh}
              onChange={(e) => setAutoRefresh(e.target.checked)}
              className="rounded border-slate-300 text-red-600 focus:ring-red-500"
            />
            Auto-refresh (5s)
          </label>
          <button
            onClick={() => refetch()}
            className="p-2 text-slate-600 hover:text-red-600 rounded-lg hover:bg-slate-100"
          >
            <RefreshCw className={`w-5 h-5 ${isLoading ? 'animate-spin' : ''}`} />
          </button>
        </div>
      </div>

      {/* Metric Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        {metricCards.map((metric) => (
          <div key={metric.name} className="bg-white rounded-xl p-6 border border-slate-200">
            <div className="flex items-center justify-start mb-4">
              <div className="w-10 h-10 bg-red-100 rounded-lg flex items-center justify-center">
                <metric.icon className="w-5 h-5 text-red-600" />
              </div>
            </div>
            <p className="text-3xl font-bold text-slate-900">
              {metric.value}
              <span className="text-lg text-slate-500 ml-1">{metric.unit}</span>
            </p>
            <p className="text-sm text-slate-600 mt-1">{metric.name}</p>
          </div>
        ))}
      </div>

      {/* Info banner if metrics not available yet */}
      {hasNoMetrics && (
        <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
          <div className="flex items-start gap-3">
            <AlertTriangle className="w-5 h-5 text-blue-600 mt-0.5 shrink-0" />
            <div>
              <h3 className="font-semibold text-blue-900 mb-1">Metrics Collection Starting</h3>
              <p className="text-sm text-blue-800">
                The system dynamic management views (DMVs) need about 15 seconds of database activity 
                before metrics become available. Start using the application or run some queries to 
                generate activity, then metrics will appear automatically.
              </p>
            </div>
          </div>
        </div>
      )}

      {/* DMV Metrics by Endpoint */}
      <div className="bg-white rounded-xl border border-slate-200">
        <div className="p-4 border-b border-slate-200">
          <h2 className="text-lg font-semibold text-slate-900">DMV Metrics by Endpoint</h2>
          <p className="text-sm text-slate-500">Near-real-time data from sys.dm_db_resource_stats</p>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-slate-50">
              <tr>
                <th className="px-4 py-3 text-left text-xs font-medium text-slate-500 uppercase">Endpoint</th>
                <th className="px-4 py-3 text-right text-xs font-medium text-slate-500 uppercase">Snapshot</th>
                <th className="px-4 py-3 text-right text-xs font-medium text-slate-500 uppercase">CPU %</th>
                <th className="px-4 py-3 text-right text-xs font-medium text-slate-500 uppercase">Data I/O %</th>
                <th className="px-4 py-3 text-right text-xs font-medium text-slate-500 uppercase">Log Write %</th>
                <th className="px-4 py-3 text-right text-xs font-medium text-slate-500 uppercase">Worker %</th>
                <th className="px-4 py-3 text-right text-xs font-medium text-slate-500 uppercase">Memory %</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-200">
              {endpointRows.map((row) => (
                <tr key={row.name} className="hover:bg-slate-50">
                  <td className="px-4 py-3 font-medium text-slate-900">{row.name}</td>
                  <td className="px-4 py-3 text-right text-slate-600">{formatSnapshot(row.stats?.SnapshotTime)}</td>
                  <td className="px-4 py-3 text-right text-slate-600">{formatPercent(row.stats?.AvgCpuPercent)}</td>
                  <td className="px-4 py-3 text-right text-slate-600">{formatPercent(row.stats?.AvgDataIoPercent)}</td>
                  <td className="px-4 py-3 text-right text-slate-600">{formatPercent(row.stats?.AvgLogWritePercent)}</td>
                  <td className="px-4 py-3 text-right text-slate-600">{formatPercent(row.stats?.MaxWorkerPercent)}</td>
                  <td className="px-4 py-3 text-right text-slate-600">{formatPercent(row.stats?.AvgMemoryUsagePercent)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Query Performance */}
      <div className="bg-red-50 rounded-xl p-4 border border-red-100">
        <p className="text-sm text-red-800">
          <strong>Performance Tip:</strong> Vector search queries are routed to the HA read replica 
          (using ApplicationIntent=ReadOnly) to avoid impacting OLTP workloads on the primary. 
          Management analytics queries use the named replica with columnstore indexes for batch mode execution.
        </p>
      </div>
    </div>
  )
}
