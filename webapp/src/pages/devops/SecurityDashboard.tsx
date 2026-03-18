import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  Shield,
  Lock,
  Eye,
  EyeOff,
  BookOpen,
  Tag,
  RefreshCw,
  CheckCircle2,
  XCircle,
  ChevronDown,
  ChevronRight,
  Database,
  Fingerprint,
  AlertTriangle,
} from 'lucide-react'
import { api } from '../../lib/api'

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------
interface RLSRow {
  Persona: string
  PersonaName: string
  CustomerRows: number
  LedgerRows: number
}

interface DDMRow {
  ViewAs: string
  CustomerId: number
  FirstName: string
  LastName: string
  Email: string
  Phone: string
  SSNLastFour: string
  DateOfBirth: string
  Address: string
}

interface ClassificationRow {
  SchemaName: string
  TableName: string
  ColumnName: string
  InformationType: string
  SensitivityLabel: string
  DataType: string
  IsMasked: string
  MaskingFunction: string | null
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
const fmt = (n: number | null | undefined) =>
  n != null ? n.toLocaleString() : '—'

const badge = (label: string) => {
  const colors: Record<string, string> = {
    'Highly Confidential': 'bg-red-100 text-red-800',
    'Confidential - GDPR': 'bg-amber-100 text-amber-800',
    Confidential: 'bg-yellow-100 text-yellow-800',
    Enabled: 'bg-green-100 text-green-800',
    'Not Configured': 'bg-slate-100 text-slate-500',
    'Not Encrypted': 'bg-red-100 text-red-700',
  }
  return colors[label] || 'bg-slate-100 text-slate-700'
}

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------
function SectionCard({
  title,
  icon: Icon,
  children,
  defaultOpen = true,
}: {
  title: string
  icon: React.ComponentType<{ className?: string }>
  children: React.ReactNode
  defaultOpen?: boolean
}) {
  const [open, setOpen] = useState(defaultOpen)
  return (
    <div className="bg-white rounded-xl shadow-sm border border-slate-200 overflow-hidden">
      <button
        onClick={() => setOpen(!open)}
        className="w-full flex items-center gap-3 px-6 py-4 text-left hover:bg-slate-50 transition"
      >
        <Icon className="h-5 w-5 text-indigo-600 flex-shrink-0" />
        <h2 className="text-lg font-semibold text-slate-900 flex-1">{title}</h2>
        {open ? (
          <ChevronDown className="h-5 w-5 text-slate-400" />
        ) : (
          <ChevronRight className="h-5 w-5 text-slate-400" />
        )}
      </button>
      {open && <div className="px-6 pb-6">{children}</div>}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Main Component
// ---------------------------------------------------------------------------
export default function SecurityDashboard() {
  const {
    data: overview,
    isLoading: ovLoading,
    refetch: ovRefetch,
  } = useQuery({
    queryKey: ['security-overview'],
    queryFn: () => api.getSecurityOverview(),
  })

  const {
    data: rlsData,
    isLoading: rlsLoading,
    refetch: rlsRefetch,
  } = useQuery({
    queryKey: ['security-rls'],
    queryFn: () => api.getSecurityRLSDemo(),
  })

  const {
    data: ddmData,
    isLoading: ddmLoading,
    refetch: ddmRefetch,
  } = useQuery({
    queryKey: ['security-ddm'],
    queryFn: () => api.getSecurityDDMDemo(),
  })

  const {
    data: ledger,
    isLoading: ledgerLoading,
    refetch: ledgerRefetch,
  } = useQuery({
    queryKey: ['security-ledger'],
    queryFn: () => api.getSecurityLedger(),
  })

  const {
    data: classificationData,
    isLoading: classLoading,
    refetch: classRefetch,
  } = useQuery({
    queryKey: ['security-classification'],
    queryFn: () => api.getSecurityClassification(),
  })

  const refetchAll = () => {
    ovRefetch()
    rlsRefetch()
    ddmRefetch()
    ledgerRefetch()
    classRefetch()
  }

  // Parse overview result sets (DAB may flatten multi-result procs)
  const featureSummary = Array.isArray(overview) ? overview : []
  const rlsRows: RLSRow[] = Array.isArray(rlsData) ? rlsData : []
  const ddmRows: DDMRow[] = Array.isArray(ddmData) ? ddmData : []
  const classifications: ClassificationRow[] = Array.isArray(classificationData)
    ? classificationData
    : []

  // Ledger may arrive as array (flattened) or object w/ multiple result sets
  const ledgerInteractions: any[] = Array.isArray(ledger) ? ledger : []

  const anyLoading = ovLoading || rlsLoading || ddmLoading || ledgerLoading || classLoading

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-2xl font-bold text-slate-900 flex items-center gap-2">
            <Shield className="h-7 w-7 text-indigo-600" />
            Security Features Dashboard
          </h1>
          <p className="text-slate-500 mt-1">
            Azure SQL Hyperscale security capabilities — Ledger, RLS, DDM, Column Security, Classification
          </p>
        </div>
        <button
          onClick={refetchAll}
          disabled={anyLoading}
          className="flex items-center gap-2 px-4 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 disabled:opacity-50 transition"
        >
          <RefreshCw className={`h-4 w-4 ${anyLoading ? 'animate-spin' : ''}`} />
          Refresh All
        </button>
      </div>

      {/* ================================================================= */}
      {/* FEATURE OVERVIEW CARDS */}
      {/* ================================================================= */}
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3">
        {featureSummary.length > 0
          ? featureSummary.map((f: any, i: number) => (
              <div
                key={i}
                className="bg-white rounded-lg border border-slate-200 p-4 text-center"
              >
                <p className="text-xs font-medium text-slate-500 uppercase tracking-wider">
                  {f.Feature}
                </p>
                <p className="text-2xl font-bold text-slate-900 mt-1">
                  {f.Policies ?? f.Predicates ?? '—'}
                </p>
                <span
                  className={`inline-block mt-1 text-xs font-medium px-2 py-0.5 rounded-full ${badge(
                    f.Status
                  )}`}
                >
                  {f.Status}
                </span>
              </div>
            ))
          : !ovLoading && (
              <div className="col-span-full text-center py-4 text-slate-400">
                Run the security migration script to see overview data.
              </div>
            )}
      </div>

      {/* ================================================================= */}
      {/* 1. LEDGER TABLE */}
      {/* ================================================================= */}
      <SectionCard title="Ledger Table — AI Interaction Audit Trail" icon={Fingerprint}>
        <p className="text-sm text-slate-500 mb-4">
          Append-only ledger table with cryptographic hashing. Every AI interaction is immutable once recorded —
          no UPDATE or DELETE allowed. Auditors can verify data integrity via{' '}
          <code className="text-xs bg-slate-100 px-1 rounded">sys.database_ledger_blocks</code>.
        </p>
        {ledgerLoading ? (
          <div className="text-center py-6 text-slate-400">Loading ledger data…</div>
        ) : ledgerInteractions.length > 0 ? (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-slate-200 text-left text-xs font-medium text-slate-500 uppercase tracking-wider">
                  <th className="py-2 pr-3">ID</th>
                  <th className="py-2 pr-3">Type</th>
                  <th className="py-2 pr-3">Role</th>
                  <th className="py-2 pr-3">User</th>
                  <th className="py-2 pr-3">Prompt Preview</th>
                  <th className="py-2 pr-3">Model</th>
                  <th className="py-2 pr-3 text-right">Tokens</th>
                  <th className="py-2 pr-3 text-right">Latency</th>
                  <th className="py-2 text-center">Status</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {ledgerInteractions.map((row: any, i: number) => (
                  <tr key={i} className="hover:bg-slate-50">
                    <td className="py-2 pr-3 font-mono text-xs text-slate-500">
                      {row.InteractionId}
                    </td>
                    <td className="py-2 pr-3">
                      <span className="inline-block bg-indigo-50 text-indigo-700 text-xs font-medium px-2 py-0.5 rounded">
                        {row.InteractionType}
                      </span>
                    </td>
                    <td className="py-2 pr-3 text-slate-600">{row.UserRole}</td>
                    <td className="py-2 pr-3 text-slate-600 truncate max-w-[140px]">
                      {row.UserId}
                    </td>
                    <td className="py-2 pr-3 text-slate-700 truncate max-w-[220px]">
                      {row.PromptPreview || '—'}
                    </td>
                    <td className="py-2 pr-3 font-mono text-xs text-slate-500">
                      {row.ModelName}
                    </td>
                    <td className="py-2 pr-3 text-right font-mono text-xs">
                      {fmt(row.TokensTotal)}
                    </td>
                    <td className="py-2 pr-3 text-right font-mono text-xs">
                      {row.LatencyMs != null ? `${row.LatencyMs}ms` : '—'}
                    </td>
                    <td className="py-2 text-center">
                      {row.IsSuccess ? (
                        <CheckCircle2 className="h-4 w-4 text-green-500 inline" />
                      ) : (
                        <XCircle className="h-4 w-4 text-red-500 inline" />
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="text-center py-6 text-slate-400">
            No ledger entries yet.
          </div>
        )}
      </SectionCard>

      {/* ================================================================= */}
      {/* 2. ROW-LEVEL SECURITY */}
      {/* ================================================================= */}
      <SectionCard title="Row-Level Security — Persona Isolation" icon={Lock}>
        <p className="text-sm text-slate-500 mb-4">
          RLS on Customers and AIInteractionLedger — same query, dramatically different results.
          Executive sees all customers; DevOps sees none (no PII access); Branch Manager sees
          customers with returns in their branch; Professional sees only their assigned customers;
          Tax Filer sees only their own record.
        </p>
        {rlsLoading ? (
          <div className="text-center py-6 text-slate-400">Loading RLS demo…</div>
        ) : rlsRows.length > 0 ? (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-slate-200 text-left text-xs font-medium text-slate-500 uppercase tracking-wider">
                  <th className="py-2 pr-4">Persona</th>
                  <th className="py-2 pr-4 text-right">Customer Rows</th>
                  <th className="py-2 pr-4 text-right">Ledger Rows</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {rlsRows.map((row, i) => {
                  const colors: Record<string, string> = {
                    executive: 'bg-amber-50 border-l-4 border-l-amber-400',
                    devops: 'bg-red-50 border-l-4 border-l-red-400',
                    'branch-manager': 'bg-purple-50 border-l-4 border-l-purple-400',
                    'tax-professional': 'bg-blue-50 border-l-4 border-l-blue-400',
                    'tax-filer': 'bg-green-50 border-l-4 border-l-green-400',
                  }
                  return (
                    <tr key={i} className={colors[row.Persona] || ''}>
                      <td className="py-3 pr-4">
                        <p className="font-medium text-slate-900">{row.PersonaName}</p>
                        <p className="text-xs text-slate-500">{row.Persona}</p>
                      </td>
                      <td className="py-3 pr-4 text-right font-mono font-bold text-slate-900">
                        {fmt(row.CustomerRows)}
                      </td>
                      <td className="py-3 pr-4 text-right font-mono font-bold text-slate-900">
                        {fmt(row.LedgerRows)}
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="text-center py-6 text-slate-400">
            No RLS results. Deploy security script and re-run.
          </div>
        )}
        <div className="mt-4 bg-indigo-50 rounded-lg p-3 text-xs text-indigo-800">
          <strong>How it works:</strong> Each persona runs{' '}
          <code className="bg-indigo-100 px-1 rounded">SELECT COUNT(*) FROM Customers</code> — the
          exact same query — but RLS filter predicates transparently limit results based on role
          membership and <code className="bg-indigo-100 px-1 rounded">SESSION_CONTEXT</code> values.
          Branch Manager and Professional scoping uses an EXISTS subquery against TaxReturns.
          DevOps is intentionally excluded from customer PII access.
        </div>
      </SectionCard>

      {/* ================================================================= */}
      {/* 3. DYNAMIC DATA MASKING */}
      {/* ================================================================= */}
      <SectionCard title="Dynamic Data Masking — PII Protection" icon={EyeOff}>
        <p className="text-sm text-slate-500 mb-4">
          Same customer record, different visibility. Privileged roles see real data; unprivileged roles
          see masked values. No application code changes — masking is engine-level.
        </p>
        {ddmLoading ? (
          <div className="text-center py-6 text-slate-400">Loading DDM demo…</div>
        ) : ddmRows.length > 0 ? (
          <>
            {/* Group by ViewAs */}
            {['Executive (Unmasked)', 'Tax Filer (Masked)'].map((viewAs) => {
              const rows = ddmRows.filter((r) => r.ViewAs === viewAs)
              if (rows.length === 0) return null
              const isMasked = viewAs.includes('Masked')
              return (
                <div key={viewAs} className="mb-6 last:mb-0">
                  <h3 className="text-sm font-semibold text-slate-700 mb-2 flex items-center gap-2">
                    {isMasked ? (
                      <EyeOff className="h-4 w-4 text-red-500" />
                    ) : (
                      <Eye className="h-4 w-4 text-green-500" />
                    )}
                    {viewAs}
                  </h3>
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                      <thead>
                        <tr className="border-b border-slate-200 text-left text-xs font-medium text-slate-500 uppercase tracking-wider">
                          <th className="py-2 pr-3">ID</th>
                          <th className="py-2 pr-3">First Name</th>
                          <th className="py-2 pr-3">Last Name</th>
                          <th className="py-2 pr-3">Email</th>
                          <th className="py-2 pr-3">Phone</th>
                          <th className="py-2 pr-3">SSN-4</th>
                          <th className="py-2 pr-3">DOB</th>
                          <th className="py-2">Address</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-100">
                        {rows.map((row, i) => (
                          <tr
                            key={i}
                            className={isMasked ? 'bg-red-50' : 'bg-green-50'}
                          >
                            <td className="py-2 pr-3 font-mono text-xs">{row.CustomerId}</td>
                            <td className="py-2 pr-3">{row.FirstName}</td>
                            <td className="py-2 pr-3">{row.LastName}</td>
                            <td className="py-2 pr-3 font-mono text-xs">{row.Email}</td>
                            <td className="py-2 pr-3 font-mono text-xs">{row.Phone}</td>
                            <td className="py-2 pr-3 font-mono text-xs">{row.SSNLastFour}</td>
                            <td className="py-2 pr-3 font-mono text-xs">{row.DateOfBirth}</td>
                            <td className="py-2 truncate max-w-[200px] text-xs">{row.Address}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </div>
              )
            })}
          </>
        ) : (
          <div className="text-center py-6 text-slate-400">
            No DDM results. Deploy security script and re-run.
          </div>
        )}
        <div className="mt-4 bg-amber-50 rounded-lg p-3 text-xs text-amber-800">
          <strong>Masking functions applied:</strong>{' '}
          <code className="bg-amber-100 px-1 rounded">email()</code> on Email,{' '}
          <code className="bg-amber-100 px-1 rounded">partial(0,"XXX-XXX-",4)</code> on Phone,{' '}
          <code className="bg-amber-100 px-1 rounded">default()</code> on SSN/DOB,{' '}
          <code className="bg-amber-100 px-1 rounded">partial(1,"XXXXX",0)</code> on Names &amp; Address.
        </div>
      </SectionCard>

      {/* ================================================================= */}
      {/* 4. DATA CLASSIFICATION */}
      {/* ================================================================= */}
      <SectionCard title="Data Classification — Sensitivity Labels" icon={Tag} defaultOpen={false}>
        <p className="text-sm text-slate-500 mb-4">
          Columns tagged with sensitivity labels for Azure Purview governance and compliance reporting.
          SQL Audit captures access to classified columns automatically.
        </p>
        {classLoading ? (
          <div className="text-center py-6 text-slate-400">Loading classifications…</div>
        ) : classifications.length > 0 ? (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-slate-200 text-left text-xs font-medium text-slate-500 uppercase tracking-wider">
                  <th className="py-2 pr-3">Table</th>
                  <th className="py-2 pr-3">Column</th>
                  <th className="py-2 pr-3">Type</th>
                  <th className="py-2 pr-3">Info Type</th>
                  <th className="py-2 pr-3">Sensitivity</th>
                  <th className="py-2 pr-3">Masked?</th>
                  <th className="py-2">Mask Function</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {classifications.map((row, i) => (
                  <tr key={i} className="hover:bg-slate-50">
                    <td className="py-2 pr-3 font-mono text-xs text-slate-600">
                      {row.TableName}
                    </td>
                    <td className="py-2 pr-3 font-medium text-slate-900">{row.ColumnName}</td>
                    <td className="py-2 pr-3 text-xs text-slate-500">{row.DataType}</td>
                    <td className="py-2 pr-3 text-xs">{row.InformationType}</td>
                    <td className="py-2 pr-3">
                      <span
                        className={`inline-block text-xs font-medium px-2 py-0.5 rounded-full ${badge(
                          row.SensitivityLabel
                        )}`}
                      >
                        {row.SensitivityLabel}
                      </span>
                    </td>
                    <td className="py-2 pr-3 text-center">
                      {row.IsMasked === 'Yes' ? (
                        <CheckCircle2 className="h-4 w-4 text-green-500 inline" />
                      ) : (
                        <span className="text-slate-300">—</span>
                      )}
                    </td>
                    <td className="py-2 font-mono text-xs text-slate-500">
                      {row.MaskingFunction || '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="text-center py-6 text-slate-400">
            No classification data. Deploy security script and re-run.
          </div>
        )}
      </SectionCard>

      {/* ================================================================= */}
      {/* 5. COLUMN-LEVEL SECURITY + TDE INFO */}
      {/* ================================================================= */}
      <SectionCard title="Additional Security Features" icon={Database} defaultOpen={false}>
        <div className="grid md:grid-cols-2 gap-6">
          {/* Column-Level Security */}
          <div className="bg-slate-50 rounded-lg p-4">
            <h3 className="text-sm font-semibold text-slate-900 flex items-center gap-2 mb-3">
              <Lock className="h-4 w-4 text-red-500" />
              Column-Level Security (DENY)
            </h3>
            <p className="text-xs text-slate-500 mb-3">
              Specific columns are denied to certain roles — querying them raises an error, not masked
              data.
            </p>
            <div className="space-y-2 text-xs">
              <div className="flex justify-between bg-white rounded px-3 py-2 border">
                <span>
                  <code className="text-red-600">Customers.SSNLastFour</code>
                </span>
                <span className="text-red-600 font-medium">DENY → TaxFiler, BranchManager</span>
              </div>
              <div className="flex justify-between bg-white rounded px-3 py-2 border">
                <span>
                  <code className="text-red-600">TaxReturns.ForeignAccountMaxValue</code>
                </span>
                <span className="text-red-600 font-medium">DENY → TaxFiler</span>
              </div>
              <div className="flex justify-between bg-white rounded px-3 py-2 border">
                <span>
                  <code className="text-red-600">TaxReturns.ForeignAccountCount</code>
                </span>
                <span className="text-red-600 font-medium">DENY → TaxFiler</span>
              </div>
            </div>
          </div>

          {/* TDE */}
          <div className="bg-slate-50 rounded-lg p-4">
            <h3 className="text-sm font-semibold text-slate-900 flex items-center gap-2 mb-3">
              <Shield className="h-4 w-4 text-green-500" />
              Transparent Data Encryption (TDE)
            </h3>
            <p className="text-xs text-slate-500 mb-3">
              Azure SQL Hyperscale enables TDE by default — all data at rest is encrypted with AES-256.
              No configuration needed; it's always on.
            </p>
            <div className="bg-white rounded px-3 py-2 border text-xs flex items-center gap-2">
              <CheckCircle2 className="h-4 w-4 text-green-500" />
              <span className="font-medium text-green-700">
                TDE Active — AES-256 encryption at rest
              </span>
            </div>
            <div className="mt-3 bg-white rounded px-3 py-2 border text-xs flex items-center gap-2">
              <CheckCircle2 className="h-4 w-4 text-green-500" />
              <span className="font-medium text-green-700">
                TLS 1.2+ encryption in transit (enforced)
              </span>
            </div>
          </div>
        </div>

        {/* Architecture note */}
        <div className="mt-6 bg-indigo-50 rounded-lg p-4 text-xs text-indigo-800">
          <h4 className="font-semibold mb-2 flex items-center gap-1">
            <BookOpen className="h-4 w-4" /> Security Architecture Summary
          </h4>
          <div className="grid md:grid-cols-2 gap-x-8 gap-y-1">
            <div>• <strong>Ledger Tables</strong> — Tamper-evident AI audit trail (append-only, blockchain-hashed)</div>
            <div>• <strong>Row-Level Security</strong> — 2 predicates on Customers, AILedger (TaxReturns excluded for NCCI perf)</div>
            <div>• <strong>Dynamic Data Masking</strong> — 14 masked columns across 4 tables</div>
            <div>• <strong>Column-Level DENY</strong> — 4 column-role restrictions</div>
            <div>• <strong>Data Classification</strong> — 16 columns labeled (Highly Confidential, GDPR)</div>
            <div>• <strong>TDE + TLS</strong> — Always-on encryption at rest and in transit</div>
          </div>
        </div>
      </SectionCard>

      {/* ================================================================= */}
      {/* FOOTER NOTE */}
      {/* ================================================================= */}
      <div className="bg-amber-50 border border-amber-200 rounded-lg p-4 flex gap-3">
        <AlertTriangle className="h-5 w-5 text-amber-500 flex-shrink-0 mt-0.5" />
        <div className="text-sm text-amber-800">
          <strong>Demo Note:</strong> This dashboard uses{' '}
          <code className="bg-amber-100 px-1 rounded text-xs">EXECUTE AS USER</code> in stored
          procedures to simulate each persona's database context. In production, RLS and DDM are
          enforced automatically via Azure AD JWT tokens passed through DAB's{' '}
          <code className="bg-amber-100 px-1 rounded text-xs">set-session-context</code> feature.
        </div>
      </div>
    </div>
  )
}
