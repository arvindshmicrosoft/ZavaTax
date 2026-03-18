import { useNavigate, useParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { ArrowLeft, Loader2 } from 'lucide-react'
import NewReturnForm from '../../components/NewReturnForm'
import { api } from '../../lib/api'

export default function EditReturn() {
  const navigate = useNavigate()
  const { returnId } = useParams<{ returnId: string }>()
  const id = Number(returnId)

  const { data: taxReturn, isLoading, error } = useQuery({
    queryKey: ['tax-return', id],
    queryFn: () => api.getTaxReturn(id),
    enabled: !!id,
  })

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <Loader2 className="w-8 h-8 animate-spin text-blue-600" />
        <span className="ml-3 text-slate-600">Loading return...</span>
      </div>
    )
  }

  if (error || !taxReturn) {
    return (
      <div className="max-w-4xl mx-auto p-8 text-center">
        <h2 className="text-xl font-semibold text-red-600 mb-2">Return not found</h2>
        <p className="text-slate-600 mb-4">Could not load tax return #{returnId}</p>
        <button onClick={() => navigate('/filer/returns')} className="btn btn-primary">
          Back to My Returns
        </button>
      </div>
    )
  }

  // Only allow editing Draft returns
  if (taxReturn.Status && taxReturn.Status !== 'Draft') {
    return (
      <div className="max-w-4xl mx-auto p-8 text-center">
        <h2 className="text-xl font-semibold text-amber-600 mb-2">Cannot edit this return</h2>
        <p className="text-slate-600 mb-4">
          Only draft returns can be edited. This return has status: <strong>{taxReturn.Status}</strong>
        </p>
        <button onClick={() => navigate('/filer/returns')} className="btn btn-primary">
          Back to My Returns
        </button>
      </div>
    )
  }

  // Map DB fields back to form data shape
  const initialData = {
    taxYear: taxReturn.TaxYear,
    filingStatus: taxReturn.FilingStatus || 'Single',
    wages: taxReturn.GrossIncome || 0,
    interestIncome: 0,
    dividendIncome: 0,
    businessIncome: 0,
    capitalGains: 0,
    otherIncome: 0,
    standardDeduction: !taxReturn.IsItemized,
    mortgageInterest: 0,
    stateLocalTaxes: 0,
    charitableDonations: 0,
    medicalExpenses: 0,
    childTaxCredit: 0,
    educationCredits: 0,
    earnedIncomeCredit: false,
    numDependents: taxReturn.NumDependents || 0,
    hasForeignAccounts: !!taxReturn.HasForeignAccounts,
    foreignAccountValue: taxReturn.ForeignAccountMaxValue || 0,
    hasPFIC: !!taxReturn.HasPFIC,
    pficValue: taxReturn.PFICValue || 0,
    pficIncome: taxReturn.PFICIncome || 0,
    hasForeignTrust: !!taxReturn.HasForeignTrust,
    foreignTrustValue: taxReturn.ForeignTrustValue || 0,
    hasForeignCorporation: !!taxReturn.HasForeignCorporation,
    foreignCorpOwnership: taxReturn.ForeignCorpOwnershipPct || 0,
    hasForeignPartnership: !!taxReturn.HasForeignPartnership,
    foreignGiftsReceived: taxReturn.ForeignGiftsReceived || 0,
    foreignTaxPaid: taxReturn.ForeignTaxesPaid || 0,
  }

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      {/* Header */}
      <div className="flex items-center gap-4">
        <button
          onClick={() => navigate(-1)}
          className="p-2 hover:bg-slate-100 rounded-lg transition-colors"
        >
          <ArrowLeft className="w-5 h-5 text-slate-600" />
        </button>
        <div>
          <h1 className="text-2xl font-bold text-slate-900">Edit Draft Return</h1>
          <p className="text-slate-600">Tax Year {taxReturn.TaxYear} — Draft</p>
        </div>
      </div>

      <NewReturnForm
        customerId={taxReturn.CustomerId}
        branchId={taxReturn.BranchId}
        professionalId={taxReturn.ProfessionalId}
        mode="self"
        editReturnId={id}
        initialData={initialData}
        onSuccess={() => navigate('/filer/returns')}
        onCancel={() => navigate(-1)}
      />
    </div>
  )
}
