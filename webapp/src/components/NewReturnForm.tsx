import { useState } from 'react'
import { useMutation, useQueryClient, useQuery } from '@tanstack/react-query'
import ReactMarkdown from 'react-markdown'
import { 
  FileText, Save, DollarSign, User, 
  Briefcase, Home, Heart, GraduationCap, Loader2, CheckCircle,
  Send, Bot, X, Sparkles, HelpCircle, Maximize2, Minimize2, AlertTriangle,
  Globe, Building2, Landmark, AlertCircle
} from 'lucide-react'
import { api } from '../lib/api'

interface FormData {
  taxYear: number
  filingStatus: string
  // Income
  wages: number
  interestIncome: number
  dividendIncome: number
  businessIncome: number
  capitalGains: number
  otherIncome: number
  // Deductions
  standardDeduction: boolean
  mortgageInterest: number
  stateLocalTaxes: number
  charitableDonations: number
  medicalExpenses: number
  // Credits
  childTaxCredit: number
  educationCredits: number
  earnedIncomeCredit: boolean
  // Dependents
  numDependents: number
  // International & Advanced
  hasForeignAccounts: boolean
  foreignAccountValue: number
  hasPFIC: boolean
  pficValue: number
  pficIncome: number
  hasForeignTrust: boolean
  foreignTrustValue: number
  hasForeignCorporation: boolean
  foreignCorpOwnership: number
  hasForeignPartnership: boolean
  foreignGiftsReceived: number
  foreignTaxPaid: number
}

interface AssistantMessage {
  id: string
  role: 'user' | 'assistant'
  content: string
  isLLMAugmented?: boolean
}

interface NewReturnFormProps {
  customerId: number
  customerName?: string
  branchId?: number
  professionalId?: number
  mode: 'self' | 'professional'
  /** When editing an existing draft, pass the return ID */
  editReturnId?: number
  /** Pre-populate form with existing return data */
  initialData?: Partial<FormData>
  onSuccess: () => void
  onCancel: () => void
}

const initialFormData: FormData = {
  taxYear: 2025,
  filingStatus: 'Single',
  wages: 0,
  interestIncome: 0,
  dividendIncome: 0,
  businessIncome: 0,
  capitalGains: 0,
  otherIncome: 0,
  standardDeduction: true,
  mortgageInterest: 0,
  stateLocalTaxes: 0,
  charitableDonations: 0,
  medicalExpenses: 0,
  childTaxCredit: 0,
  educationCredits: 0,
  earnedIncomeCredit: false,
  numDependents: 0,
  // International & Advanced
  hasForeignAccounts: false,
  foreignAccountValue: 0,
  hasPFIC: false,
  pficValue: 0,
  pficIncome: 0,
  hasForeignTrust: false,
  foreignTrustValue: 0,
  hasForeignCorporation: false,
  foreignCorpOwnership: 0,
  hasForeignPartnership: false,
  foreignGiftsReceived: 0,
  foreignTaxPaid: 0,
}

// Context-aware suggested questions based on current step
const stepQuestions: Record<number, string[]> = {
  1: [
    "Which filing status should I choose?",
    "What's the difference between Single and Head of Household?",
    "Can I claim my child as a dependent?",
  ],
  2: [
    "What counts as taxable income?",
    "Do I need to report cryptocurrency gains?",
    "How do I report self-employment income?",
  ],
  3: [
    "Should I take the standard deduction or itemize?",
    "What home expenses can I deduct?",
    "Is there a limit on state and local tax deductions?",
  ],
  4: [
    "What is the Child Tax Credit and do I qualify?",
    "How does the Earned Income Credit work?",
    "Can I claim education credits?",
  ],
  5: [
    "What is Form 8938 and when is it required?",
    "How do I report PFIC investments on Form 8621?",
    "What is FBAR and how does it differ from Form 8938?",
    "Can I claim the Foreign Tax Credit?",
  ],
  6: [
    "How do I know if my return is correct?",
    "What happens after I submit?",
    "Can I amend my return later?",
  ],
}

export default function NewReturnForm({ 
  customerId, 
  customerName, 
  branchId = 1, 
  professionalId = 1,
  mode, 
  editReturnId,
  initialData,
  onSuccess, 
  onCancel 
}: NewReturnFormProps) {
  const queryClient = useQueryClient()
  const [step, setStep] = useState(1)
  const [formData, setFormData] = useState<FormData>({ ...initialFormData, ...initialData })
  const [showSuccess, setShowSuccess] = useState(false)
  const isEditMode = !!editReturnId
  
  // AI Assistant state
  const [showAssistant, setShowAssistant] = useState(false)
  const [assistantMaximized, setAssistantMaximized] = useState(false)
  const [assistantMessages, setAssistantMessages] = useState<AssistantMessage[]>([])
  const [assistantInput, setAssistantInput] = useState('')

  // Front-load validation: check for existing return when tax year changes (skip in edit mode)
  const { data: existingReturn, isFetching: checkingExisting } = useQuery({
    queryKey: ['check-existing-return', customerId, formData.taxYear],
    queryFn: () => api.checkExistingReturn(customerId, formData.taxYear),
    enabled: !isEditMode,
  })

  const duplicateError = !isEditMode && existingReturn 
    ? `${customerName || 'This customer'} already has a tax return for ${formData.taxYear}. Only one return per tax year is allowed.`
    : null

  // Build the payload from form data for create/update/save-as-draft
  const buildPayload = (data: FormData, status: string) => {
    const gi = data.wages + data.interestIncome + data.dividendIncome + 
              data.businessIncome + data.capitalGains + data.otherIncome
    const td = data.standardDeduction 
      ? getStandardDeduction(data.filingStatus)
      : data.mortgageInterest + data.stateLocalTaxes + data.charitableDonations + data.medicalExpenses
    const ti = Math.max(0, gi - td)
    const tl = calculateTax(ti, data.filingStatus)
    const tc = data.childTaxCredit + data.educationCredits
    const ft = Math.max(0, tl - tc)
    const ew = Math.round(data.wages * 0.22)
    const ro = ew - ft
    return {
      CustomerId: customerId,
      BranchId: branchId,
      ProfessionalId: professionalId,
      TaxYear: data.taxYear,
      FilingStatus: data.filingStatus,
      GrossIncome: gi,
      AdjustedGrossIncome: gi,
      TotalDeductions: td,
      TaxableIncome: ti,
      TaxLiability: ft,
      TotalWithheld: ew,
      RefundAmount: ro > 0 ? ro : 0,
      AmountOwed: ro < 0 ? Math.abs(ro) : 0,
      Status: status,
      FilingDate: status === 'Filed' ? new Date().toISOString() : null,
      IsItemized: !data.standardDeduction,
      NumDependents: data.numDependents,
      HasForeignAccounts: data.hasForeignAccounts,
      ForeignAccountMaxValue: data.foreignAccountValue || 0,
      HasPFIC: data.hasPFIC,
      PFICValue: data.pficValue || 0,
      PFICIncome: data.pficIncome || 0,
      HasForeignTrust: data.hasForeignTrust,
      ForeignTrustValue: data.foreignTrustValue || 0,
      HasForeignCorporation: data.hasForeignCorporation,
      ForeignCorpOwnershipPct: data.foreignCorpOwnership || 0,
      HasForeignPartnership: data.hasForeignPartnership,
      ForeignGiftsReceived: data.foreignGiftsReceived || 0,
      ForeignTaxesPaid: data.foreignTaxPaid || 0,
    }
  }

  const invalidateAndFinish = () => {
    queryClient.invalidateQueries({ queryKey: ['my-returns'] })
    queryClient.invalidateQueries({ queryKey: ['client-returns'] })
    queryClient.invalidateQueries({ queryKey: ['check-existing-return'] })
    queryClient.invalidateQueries({ queryKey: ['tax-return'] })
    setShowSuccess(true)
    setTimeout(() => onSuccess(), 2000)
  }

  // Create new return (status = Filed) and populate filing detail records
  const createMutation = useMutation({
    mutationFn: async (data: FormData) => {
      if (existingReturn) {
        throw new Error(`A tax return for ${data.taxYear} already exists. Only one return per tax year is allowed.`)
      }
      const result = await api.createTaxReturn(buildPayload(data, 'Filed'))
      // Trigger PopulateFilingDetails via SubmitTaxReturn stored proc
      // DAB may return ReturnId at different levels depending on response format
      const returnId = result?.ReturnId ?? result?.returnId ?? result?.value?.[0]?.ReturnId ?? result?.value?.ReturnId
      if (returnId) {
        await api.submitTaxReturn(returnId)
      } else {
        console.warn('[ZavaTax] Could not extract ReturnId — detail tables will not be populated')
      }
      return result
    },
    onSuccess: invalidateAndFinish,
    onError: (error: Error) => {
      console.error('Failed to create tax return:', error)
      alert(error.message || 'Failed to create tax return. Please try again.')
    },
  })

  // Save as draft (create with Status=Draft, or update existing draft)
  const saveDraftMutation = useMutation({
    mutationFn: async (data: FormData) => {
      if (isEditMode) {
        return api.updateTaxReturn(editReturnId!, buildPayload(data, 'Draft'))
      }
      if (existingReturn) {
        throw new Error(`A tax return for ${data.taxYear} already exists.`)
      }
      return api.createTaxReturn(buildPayload(data, 'Draft'))
    },
    onSuccess: invalidateAndFinish,
    onError: (error: Error) => {
      console.error('Failed to save draft:', error)
      alert(error.message || 'Failed to save draft. Please try again.')
    },
  })

  // Update existing return and submit (status = Filed) with filing detail records
  const updateMutation = useMutation({
    mutationFn: async (data: FormData) => {
      const result = await api.updateTaxReturn(editReturnId!, buildPayload(data, 'Filed'))
      // Trigger PopulateFilingDetails via SubmitTaxReturn stored proc
      await api.submitTaxReturn(editReturnId!)
      return result
    },
    onSuccess: invalidateAndFinish,
    onError: (error: Error) => {
      console.error('Failed to update tax return:', error)
      alert(error.message || 'Failed to update tax return. Please try again.')
    },
  })

  const isMutating = createMutation.isPending || saveDraftMutation.isPending || updateMutation.isPending

  // AI Assistant mutation
  const assistantMutation = useMutation({
    mutationFn: async (question: string) => {
      // Build context based on current step and form data
      const stepNames = ['', 'Filing Status', 'Income', 'Deductions', 'Credits', 'Review']
      let context = `User is on step ${step}: ${stepNames[step]}. `
      context += `Filing status: ${formData.filingStatus}. `
      if (formData.wages > 0) context += `Wages: $${formData.wages.toLocaleString()}. `
      if (grossIncome > 0) context += `Total income: $${grossIncome.toLocaleString()}. `
      if (totalDeductions > 0) context += `Deductions: $${totalDeductions.toLocaleString()} (${formData.standardDeduction ? 'standard' : 'itemized'}). `
      if (formData.numDependents > 0) context += `Dependents: ${formData.numDependents}. `
      
      return api.askTaxAssistant(question, context)
    },
    onSuccess: (data) => {
      const assistantMessage: AssistantMessage = {
        id: Date.now().toString(),
        role: 'assistant',
        content: data.answer,
        isLLMAugmented: data.isLLMAugmented,
      }
      setAssistantMessages(prev => [...prev, assistantMessage])
    },
    onError: (error: any) => {
      console.error('AI Assistant Error:', error)
      const errorMessage: AssistantMessage = {
        id: Date.now().toString(),
        role: 'assistant',
        content: 'Sorry, I encountered an error. Please try again or consult with a tax professional.',
      }
      setAssistantMessages(prev => [...prev, errorMessage])
    },
  })

  const handleAssistantSubmit = (question: string) => {
    if (!question.trim() || assistantMutation.isPending) return
    
    const userMessage: AssistantMessage = {
      id: Date.now().toString(),
      role: 'user',
      content: question,
    }
    setAssistantMessages(prev => [...prev, userMessage])
    setAssistantInput('')
    assistantMutation.mutate(question)
  }

  const getStandardDeduction = (status: string): number => {
    const deductions: Record<string, number> = {
      'Single': 14600,
      'Married Filing Jointly': 29200,
      'Married Filing Separately': 14600,
      'Head of Household': 21900,
      'Qualifying Widow(er)': 29200,
    }
    return deductions[status] || 14600
  }

  const calculateTax = (income: number, _status: string): number => {
    // Simplified 2025 tax brackets for Single filers
    const brackets = [
      { limit: 11600, rate: 0.10 },
      { limit: 47150, rate: 0.12 },
      { limit: 100525, rate: 0.22 },
      { limit: 191950, rate: 0.24 },
      { limit: 243725, rate: 0.32 },
      { limit: 609350, rate: 0.35 },
      { limit: Infinity, rate: 0.37 },
    ]

    let tax = 0
    let remaining = income
    let prevLimit = 0

    for (const bracket of brackets) {
      const taxableInBracket = Math.min(remaining, bracket.limit - prevLimit)
      if (taxableInBracket <= 0) break
      tax += taxableInBracket * bracket.rate
      remaining -= taxableInBracket
      prevLimit = bracket.limit
    }

    return Math.round(tax)
  }

  const updateField = (field: keyof FormData, value: any) => {
    setFormData(prev => ({ ...prev, [field]: value }))
  }

  const grossIncome = formData.wages + formData.interestIncome + formData.dividendIncome + 
                      formData.businessIncome + formData.capitalGains + formData.otherIncome

  const totalDeductions = formData.standardDeduction 
    ? getStandardDeduction(formData.filingStatus)
    : formData.mortgageInterest + formData.stateLocalTaxes + formData.charitableDonations + formData.medicalExpenses

  const taxableIncome = Math.max(0, grossIncome - totalDeductions)
  const estimatedTax = calculateTax(taxableIncome, formData.filingStatus)
  const estimatedWithholding = Math.round(formData.wages * 0.22)
  const estimatedRefund = estimatedWithholding - estimatedTax

  if (showSuccess) {
    return (
      <div className="max-w-2xl mx-auto py-12 text-center">
        <div className="w-20 h-20 bg-green-100 rounded-full flex items-center justify-center mx-auto mb-6">
          <CheckCircle className="w-10 h-10 text-green-600" />
        </div>
        <h1 className="text-2xl font-bold text-slate-900 mb-2">Return Created Successfully!</h1>
        <p className="text-slate-600">
          {mode === 'professional' 
            ? `Tax return for ${customerName} has been created.` 
            : 'Redirecting to your returns...'}
        </p>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Header - only show for professional mode since self mode has its own page header */}
      {mode === 'professional' && customerName && (
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-lg font-semibold text-slate-900">New Tax Return</h2>
            <p className="text-slate-600">For {customerName} • Tax Year {formData.taxYear}</p>
          </div>
          <button
            onClick={onCancel}
            className="p-2 hover:bg-slate-100 rounded-lg transition-colors"
          >
            <X className="w-5 h-5 text-slate-500" />
          </button>
        </div>
      )}

      {/* Duplicate Return Error */}
      {checkingExisting ? (
        <div className="bg-slate-50 border border-slate-200 rounded-xl p-4 flex items-center gap-3">
          <Loader2 className="w-5 h-5 text-slate-400 animate-spin" />
          <span className="text-slate-600">Checking for existing returns...</span>
        </div>
      ) : duplicateError && (
        <div className="bg-red-50 border border-red-200 rounded-xl p-4 flex items-start gap-3">
          <AlertTriangle className="w-5 h-5 text-red-600 flex-shrink-0 mt-0.5" />
          <div>
            <h3 className="font-medium text-red-800">Cannot Create Return</h3>
            <p className="text-red-700 text-sm mt-1">{duplicateError}</p>
          </div>
        </div>
      )}

      {/* Progress Steps */}
      <div className="flex items-center justify-between bg-white rounded-xl border border-slate-200 p-4 overflow-x-auto">
        {[
          { num: 1, label: 'Filing Status', icon: User },
          { num: 2, label: 'Income', icon: DollarSign },
          { num: 3, label: 'Deductions', icon: Home },
          { num: 4, label: 'Credits', icon: Heart },
          { num: 5, label: 'International', icon: Globe },
          { num: 6, label: 'Review', icon: FileText },
        ].map(({ num, label, icon: Icon }) => (
          <button
            key={num}
            onClick={() => setStep(num)}
            className={`flex items-center gap-2 px-4 py-2 rounded-lg transition-colors ${
              step === num 
                ? 'bg-blue-100 text-blue-700' 
                : step > num 
                  ? 'text-green-600' 
                  : 'text-slate-400'
            }`}
          >
            <div className={`w-8 h-8 rounded-full flex items-center justify-center ${
              step === num 
                ? 'bg-blue-600 text-white' 
                : step > num 
                  ? 'bg-green-100 text-green-600' 
                  : 'bg-slate-100'
            }`}>
              {step > num ? <CheckCircle className="w-5 h-5" /> : <Icon className="w-4 h-4" />}
            </div>
            <span className="hidden sm:block font-medium">{label}</span>
          </button>
        ))}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Main Form */}
        <div className="lg:col-span-2 bg-white rounded-xl border border-slate-200 p-6">
          {/* Step 1: Filing Status */}
          {step === 1 && (
            <div className="space-y-6">
              <h2 className="text-lg font-semibold text-slate-900 flex items-center gap-2">
                <User className="w-5 h-5 text-blue-600" />
                Filing Status & Basic Info
              </h2>

              <div>
                <label className="block text-sm font-medium text-slate-700 mb-2">Tax Year</label>
                <select
                  value={formData.taxYear}
                  onChange={(e) => updateField('taxYear', parseInt(e.target.value))}
                  className="w-full p-3 border border-slate-200 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                >
                  <option value={2026}>2026</option>
                  <option value={2025}>2025</option>
                  <option value={2024}>2024</option>
                  <option value={2023}>2023</option>
                  <option value={2022}>2022</option>
                  <option value={2021}>2021</option>
                  <option value={2020}>2020</option>
                </select>
              </div>

              <div>
                <label className="block text-sm font-medium text-slate-700 mb-2">Filing Status</label>
                <div className="space-y-2">
                  {['Single', 'Married Filing Jointly', 'Married Filing Separately', 'Head of Household', 'Qualifying Widow(er)'].map((status) => (
                    <label key={status} className="flex items-center gap-3 p-3 border border-slate-200 rounded-lg cursor-pointer hover:bg-slate-50">
                      <input
                        type="radio"
                        name="filingStatus"
                        value={status}
                        checked={formData.filingStatus === status}
                        onChange={(e) => updateField('filingStatus', e.target.value)}
                        className="w-4 h-4 text-blue-600"
                      />
                      <span className="text-slate-700">{status}</span>
                    </label>
                  ))}
                </div>
              </div>

              <div>
                <label className="block text-sm font-medium text-slate-700 mb-2">Number of Dependents</label>
                <input
                  type="text"
                  inputMode="numeric"
                  pattern="[0-9]*"
                  value={formData.numDependents || ''}
                  onChange={(e) => updateField('numDependents', parseInt(e.target.value.replace(/[^0-9]/g, '')) || 0)}
                  className="w-full p-3 border border-slate-200 rounded-lg focus:ring-2 focus:ring-blue-500"
                  placeholder="0"
                />
              </div>
            </div>
          )}

          {/* Step 2: Income */}
          {step === 2 && (
            <div className="space-y-6">
              <h2 className="text-lg font-semibold text-slate-900 flex items-center gap-2">
                <DollarSign className="w-5 h-5 text-green-600" />
                Income Information
              </h2>

              {[
                { field: 'wages', label: 'Wages & Salary (W-2)', icon: Briefcase },
                { field: 'interestIncome', label: 'Interest Income', icon: DollarSign },
                { field: 'dividendIncome', label: 'Dividend Income', icon: DollarSign },
                { field: 'businessIncome', label: 'Business/Self-Employment Income', icon: Briefcase },
                { field: 'capitalGains', label: 'Capital Gains', icon: DollarSign },
                { field: 'otherIncome', label: 'Other Income', icon: DollarSign },
              ].map(({ field, label, icon: Icon }) => (
                <div key={field}>
                  <label className="block text-sm font-medium text-slate-700 mb-2 flex items-center gap-2">
                    <Icon className="w-4 h-4 text-slate-400" />
                    {label}
                  </label>
                  <div className="relative">
                    <span className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400">$</span>
                    <input
                      type="text"
                      inputMode="numeric"
                      pattern="[0-9]*"
                      value={(formData[field as keyof FormData] as number) || ''}
                      onChange={(e) => updateField(field as keyof FormData, parseInt(e.target.value.replace(/[^0-9]/g, '')) || 0)}
                      className="w-full pl-8 p-3 border border-slate-200 rounded-lg focus:ring-2 focus:ring-blue-500"
                      placeholder="0"
                    />
                  </div>
                </div>
              ))}
            </div>
          )}

          {/* Step 3: Deductions */}
          {step === 3 && (
            <div className="space-y-6">
              <h2 className="text-lg font-semibold text-slate-900 flex items-center gap-2">
                <Home className="w-5 h-5 text-amber-600" />
                Deductions
              </h2>

              <div className="p-4 bg-blue-50 rounded-lg border border-blue-100">
                <label className="flex items-center gap-3 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={formData.standardDeduction}
                    onChange={(e) => updateField('standardDeduction', e.target.checked)}
                    className="w-5 h-5 text-blue-600 rounded"
                  />
                  <div>
                    <span className="font-medium text-slate-900">Take Standard Deduction</span>
                    <p className="text-sm text-slate-600">
                      ${getStandardDeduction(formData.filingStatus).toLocaleString()} for {formData.filingStatus}
                    </p>
                  </div>
                </label>
              </div>

              {!formData.standardDeduction && (
                <div className="space-y-4">
                  <p className="text-sm text-slate-600">Enter itemized deductions:</p>
                  {[
                    { field: 'mortgageInterest', label: 'Mortgage Interest' },
                    { field: 'stateLocalTaxes', label: 'State & Local Taxes (SALT)' },
                    { field: 'charitableDonations', label: 'Charitable Donations' },
                    { field: 'medicalExpenses', label: 'Medical Expenses (above 7.5% AGI)' },
                  ].map(({ field, label }) => (
                    <div key={field}>
                      <label className="block text-sm font-medium text-slate-700 mb-2">{label}</label>
                      <div className="relative">
                        <span className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400">$</span>
                        <input
                          type="text"
                          inputMode="numeric"
                          pattern="[0-9]*"
                          value={(formData[field as keyof FormData] as number) || ''}
                          onChange={(e) => updateField(field as keyof FormData, parseInt(e.target.value.replace(/[^0-9]/g, '')) || 0)}
                          className="w-full pl-8 p-3 border border-slate-200 rounded-lg focus:ring-2 focus:ring-blue-500"
                          placeholder="0"
                        />
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}

          {/* Step 4: Credits */}
          {step === 4 && (
            <div className="space-y-6">
              <h2 className="text-lg font-semibold text-slate-900 flex items-center gap-2">
                <Heart className="w-5 h-5 text-red-600" />
                Tax Credits
              </h2>

              <div>
                <label className="block text-sm font-medium text-slate-700 mb-2">
                  Child Tax Credit (per qualifying child)
                </label>
                <div className="relative">
                  <span className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400">$</span>
                  <input
                    type="text"
                    inputMode="numeric"
                    pattern="[0-9]*"
                    value={formData.childTaxCredit || ''}
                    onChange={(e) => updateField('childTaxCredit', Math.min(2000, parseInt(e.target.value.replace(/[^0-9]/g, '')) || 0))}
                    className="w-full pl-8 p-3 border border-slate-200 rounded-lg focus:ring-2 focus:ring-blue-500"
                    placeholder="0"
                  />
                </div>
                <p className="text-xs text-slate-500 mt-1">Up to $2,000 per qualifying child</p>
              </div>

              <div>
                <label className="block text-sm font-medium text-slate-700 mb-2 flex items-center gap-2">
                  <GraduationCap className="w-4 h-4 text-slate-400" />
                  Education Credits
                </label>
                <div className="relative">
                  <span className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400">$</span>
                  <input
                    type="text"
                    inputMode="numeric"
                    pattern="[0-9]*"
                    value={formData.educationCredits || ''}
                    onChange={(e) => updateField('educationCredits', parseInt(e.target.value.replace(/[^0-9]/g, '')) || 0)}
                    className="w-full pl-8 p-3 border border-slate-200 rounded-lg focus:ring-2 focus:ring-blue-500"
                    placeholder="0"
                  />
                </div>
              </div>

              <div className="p-4 bg-green-50 rounded-lg border border-green-100">
                <label className="flex items-center gap-3 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={formData.earnedIncomeCredit}
                    onChange={(e) => updateField('earnedIncomeCredit', e.target.checked)}
                    className="w-5 h-5 text-green-600 rounded"
                  />
                  <div>
                    <span className="font-medium text-slate-900">Check Earned Income Credit Eligibility</span>
                    <p className="text-sm text-slate-600">
                      For low to moderate income workers
                    </p>
                  </div>
                </label>
              </div>
            </div>
          )}

          {/* Step 5: International & Advanced */}
          {step === 5 && (
            <div className="space-y-6">
              <h2 className="text-lg font-semibold text-slate-900 flex items-center gap-2">
                <Globe className="w-5 h-5 text-indigo-600" />
                International & Advanced Tax Situations
              </h2>
              
              <p className="text-sm text-slate-600 bg-indigo-50 p-3 rounded-lg border border-indigo-100">
                These questions determine if additional IRS forms are required for international income, 
                foreign assets, and complex investment situations.
              </p>

              {/* Form 8938 - FATCA */}
              <div className="border border-slate-200 rounded-lg p-4 space-y-4">
                <div className="flex items-start gap-3">
                  <Landmark className="w-5 h-5 text-indigo-600 mt-0.5" />
                  <div className="flex-1">
                    <label className="flex items-center gap-3 cursor-pointer">
                      <input
                        type="checkbox"
                        checked={formData.hasForeignAccounts}
                        onChange={(e) => updateField('hasForeignAccounts', e.target.checked)}
                        className="w-5 h-5 text-indigo-600 rounded"
                      />
                      <div>
                        <span className="font-medium text-slate-900">Foreign Financial Accounts</span>
                        <p className="text-sm text-slate-500">
                          Bank accounts, securities, or financial assets held outside the US
                        </p>
                      </div>
                    </label>
                    {formData.hasForeignAccounts && (
                      <div className="mt-3 ml-8">
                        <label className="block text-sm font-medium text-slate-700 mb-1">
                          Maximum account value during {formData.taxYear}
                        </label>
                        <div className="relative">
                          <span className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400">$</span>
                          <input
                            type="text"
                            inputMode="numeric"
                            pattern="[0-9]*"
                            value={formData.foreignAccountValue || ''}
                            onChange={(e) => updateField('foreignAccountValue', parseInt(e.target.value.replace(/[^0-9]/g, '')) || 0)}
                            className="w-full pl-8 p-2 border border-slate-200 rounded-lg focus:ring-2 focus:ring-indigo-500"
                            placeholder="e.g., 75000"
                          />
                        </div>
                        {formData.foreignAccountValue >= 50000 && (
                          <div className="mt-2 p-2 bg-amber-50 border border-amber-200 rounded text-xs text-amber-800 flex items-center gap-2">
                            <AlertCircle className="w-4 h-4" />
                            <span><strong>Form 8938</strong> (FATCA) likely required. FBAR may also be needed if &gt;$10,000.</span>
                          </div>
                        )}
                      </div>
                    )}
                  </div>
                </div>
              </div>

              {/* Form 8621 - PFIC */}
              <div className="border border-slate-200 rounded-lg p-4 space-y-4">
                <div className="flex items-start gap-3">
                  <Building2 className="w-5 h-5 text-purple-600 mt-0.5" />
                  <div className="flex-1">
                    <label className="flex items-center gap-3 cursor-pointer">
                      <input
                        type="checkbox"
                        checked={formData.hasPFIC}
                        onChange={(e) => updateField('hasPFIC', e.target.checked)}
                        className="w-5 h-5 text-purple-600 rounded"
                      />
                      <div>
                        <span className="font-medium text-slate-900">Passive Foreign Investment Company (PFIC)</span>
                        <p className="text-sm text-slate-500">
                          Foreign mutual funds, ETFs, or investment companies held outside US tax-advantaged accounts
                        </p>
                      </div>
                    </label>
                    {formData.hasPFIC && (
                      <div className="mt-3 ml-8 space-y-3">
                        <div>
                          <label className="block text-sm font-medium text-slate-700 mb-1">Value of PFIC holdings</label>
                          <div className="relative">
                            <span className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400">$</span>
                            <input
                              type="text"
                              inputMode="numeric"
                              pattern="[0-9]*"
                              value={formData.pficValue || ''}
                              onChange={(e) => updateField('pficValue', parseInt(e.target.value.replace(/[^0-9]/g, '')) || 0)}
                              className="w-full pl-8 p-2 border border-slate-200 rounded-lg focus:ring-2 focus:ring-purple-500"
                              placeholder="e.g., 25000"
                            />
                          </div>
                        </div>
                        <div>
                          <label className="block text-sm font-medium text-slate-700 mb-1">Income/Distributions from PFIC</label>
                          <div className="relative">
                            <span className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400">$</span>
                            <input
                              type="text"
                              inputMode="numeric"
                              pattern="[0-9]*"
                              value={formData.pficIncome || ''}
                              onChange={(e) => updateField('pficIncome', parseInt(e.target.value.replace(/[^0-9]/g, '')) || 0)}
                              className="w-full pl-8 p-2 border border-slate-200 rounded-lg focus:ring-2 focus:ring-purple-500"
                              placeholder="e.g., 1500"
                            />
                          </div>
                        </div>
                        <div className="p-2 bg-purple-50 border border-purple-200 rounded text-xs text-purple-800 flex items-center gap-2">
                          <AlertCircle className="w-4 h-4" />
                          <span><strong>Form 8621</strong> required for each PFIC. Complex tax calculations apply.</span>
                        </div>
                      </div>
                    )}
                  </div>
                </div>
              </div>

              {/* Form 3520 - Foreign Trusts */}
              <div className="border border-slate-200 rounded-lg p-4 space-y-4">
                <div className="flex items-start gap-3">
                  <FileText className="w-5 h-5 text-teal-600 mt-0.5" />
                  <div className="flex-1">
                    <label className="flex items-center gap-3 cursor-pointer">
                      <input
                        type="checkbox"
                        checked={formData.hasForeignTrust}
                        onChange={(e) => updateField('hasForeignTrust', e.target.checked)}
                        className="w-5 h-5 text-teal-600 rounded"
                      />
                      <div>
                        <span className="font-medium text-slate-900">Foreign Trust Involvement</span>
                        <p className="text-sm text-slate-500">
                          Beneficiary of, grantor of, or transferred assets to a foreign trust
                        </p>
                      </div>
                    </label>
                    {formData.hasForeignTrust && (
                      <div className="mt-3 ml-8">
                        <label className="block text-sm font-medium text-slate-700 mb-1">Value or distributions received</label>
                        <div className="relative">
                          <span className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400">$</span>
                          <input
                            type="text"
                            inputMode="numeric"
                            pattern="[0-9]*"
                            value={formData.foreignTrustValue || ''}
                            onChange={(e) => updateField('foreignTrustValue', parseInt(e.target.value.replace(/[^0-9]/g, '')) || 0)}
                            className="w-full pl-8 p-2 border border-slate-200 rounded-lg focus:ring-2 focus:ring-teal-500"
                            placeholder="e.g., 50000"
                          />
                        </div>
                        <div className="mt-2 p-2 bg-teal-50 border border-teal-200 rounded text-xs text-teal-800 flex items-center gap-2">
                          <AlertCircle className="w-4 h-4" />
                          <span><strong>Form 3520/3520-A</strong> required. Significant penalties for non-filing.</span>
                        </div>
                      </div>
                    )}
                  </div>
                </div>
              </div>

              {/* Form 5471 - Foreign Corporation */}
              <div className="border border-slate-200 rounded-lg p-4 space-y-4">
                <div className="flex items-start gap-3">
                  <Building2 className="w-5 h-5 text-blue-600 mt-0.5" />
                  <div className="flex-1">
                    <label className="flex items-center gap-3 cursor-pointer">
                      <input
                        type="checkbox"
                        checked={formData.hasForeignCorporation}
                        onChange={(e) => updateField('hasForeignCorporation', e.target.checked)}
                        className="w-5 h-5 text-blue-600 rounded"
                      />
                      <div>
                        <span className="font-medium text-slate-900">Foreign Corporation Ownership</span>
                        <p className="text-sm text-slate-500">
                          Own 10% or more of a foreign corporation (CFC or specified foreign corporation)
                        </p>
                      </div>
                    </label>
                    {formData.hasForeignCorporation && (
                      <div className="mt-3 ml-8">
                        <label className="block text-sm font-medium text-slate-700 mb-1">Ownership percentage</label>
                        <div className="relative">
                          <span className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400">%</span>
                          <input
                            type="text"
                            inputMode="numeric"
                            pattern="[0-9]*"
                            value={formData.foreignCorpOwnership || ''}
                            onChange={(e) => updateField('foreignCorpOwnership', Math.min(100, parseInt(e.target.value.replace(/[^0-9]/g, '')) || 0))}
                            className="w-full p-2 border border-slate-200 rounded-lg focus:ring-2 focus:ring-blue-500"
                            placeholder="e.g., 25"
                          />
                        </div>
                        {formData.foreignCorpOwnership >= 10 && (
                          <div className="mt-2 p-2 bg-blue-50 border border-blue-200 rounded text-xs text-blue-800 flex items-center gap-2">
                            <AlertCircle className="w-4 h-4" />
                            <span><strong>Form 5471</strong> required. GILTI/Subpart F income may apply.</span>
                          </div>
                        )}
                      </div>
                    )}
                  </div>
                </div>
              </div>

              {/* Form 8865 - Foreign Partnership */}
              <div className="border border-slate-200 rounded-lg p-4 space-y-4">
                <div className="flex items-start gap-3">
                  <Building2 className="w-5 h-5 text-orange-600 mt-0.5" />
                  <div className="flex-1">
                    <label className="flex items-center gap-3 cursor-pointer">
                      <input
                        type="checkbox"
                        checked={formData.hasForeignPartnership}
                        onChange={(e) => updateField('hasForeignPartnership', e.target.checked)}
                        className="w-5 h-5 text-orange-600 rounded"
                      />
                      <div>
                        <span className="font-medium text-slate-900">Foreign Partnership Interest</span>
                        <p className="text-sm text-slate-500">
                          Own interest in a foreign partnership or transferred property to one
                        </p>
                      </div>
                    </label>
                    {formData.hasForeignPartnership && (
                      <div className="mt-2 ml-8 p-2 bg-orange-50 border border-orange-200 rounded text-xs text-orange-800 flex items-center gap-2">
                        <AlertCircle className="w-4 h-4" />
                        <span><strong>Form 8865</strong> may be required depending on ownership level and transactions.</span>
                      </div>
                    )}
                  </div>
                </div>
              </div>

              {/* Foreign Gifts & Tax Credit */}
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div className="border border-slate-200 rounded-lg p-4">
                  <label className="block text-sm font-medium text-slate-700 mb-2">
                    Foreign Gifts Received
                  </label>
                  <div className="relative">
                    <span className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400">$</span>
                    <input
                      type="text"
                      inputMode="numeric"
                      pattern="[0-9]*"
                      value={formData.foreignGiftsReceived || ''}
                      onChange={(e) => updateField('foreignGiftsReceived', parseInt(e.target.value.replace(/[^0-9]/g, '')) || 0)}
                      className="w-full pl-8 p-2 border border-slate-200 rounded-lg focus:ring-2 focus:ring-slate-500"
                      placeholder="0"
                    />
                  </div>
                  {formData.foreignGiftsReceived >= 100000 && (
                    <p className="mt-1 text-xs text-amber-700"><strong>Form 3520</strong> required for gifts &gt;$100k</p>
                  )}
                </div>
                <div className="border border-slate-200 rounded-lg p-4">
                  <label className="block text-sm font-medium text-slate-700 mb-2">
                    Foreign Taxes Paid
                  </label>
                  <div className="relative">
                    <span className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400">$</span>
                    <input
                      type="text"
                      inputMode="numeric"
                      pattern="[0-9]*"
                      value={formData.foreignTaxPaid || ''}
                      onChange={(e) => updateField('foreignTaxPaid', parseInt(e.target.value.replace(/[^0-9]/g, '')) || 0)}
                      className="w-full pl-8 p-2 border border-slate-200 rounded-lg focus:ring-2 focus:ring-slate-500"
                      placeholder="0"
                    />
                  </div>
                  {formData.foreignTaxPaid > 0 && (
                    <p className="mt-1 text-xs text-green-700"><strong>Form 1116</strong> for Foreign Tax Credit</p>
                  )}
                </div>
              </div>

              {/* Summary of Required Forms */}
              {(formData.hasForeignAccounts || formData.hasPFIC || formData.hasForeignTrust || 
                formData.hasForeignCorporation || formData.hasForeignPartnership || 
                formData.foreignGiftsReceived >= 100000 || formData.foreignTaxPaid > 0) && (
                <div className="p-4 bg-indigo-50 rounded-lg border border-indigo-200">
                  <h3 className="font-semibold text-indigo-900 mb-2 flex items-center gap-2">
                    <FileText className="w-4 h-4" />
                    Required International Tax Forms
                  </h3>
                  <div className="space-y-2 text-sm">
                    {formData.foreignAccountValue >= 50000 && (
                      <div className="flex items-center gap-2 text-indigo-800">
                        <span className="w-2 h-2 bg-indigo-600 rounded-full" />
                        <strong>Form 8938</strong> - Statement of Specified Foreign Financial Assets (FATCA)
                      </div>
                    )}
                    {formData.foreignAccountValue >= 10000 && (
                      <div className="flex items-center gap-2 text-indigo-800">
                        <span className="w-2 h-2 bg-indigo-600 rounded-full" />
                        <strong>FinCEN 114</strong> - FBAR (Report of Foreign Bank Accounts)
                      </div>
                    )}
                    {formData.hasPFIC && (
                      <div className="flex items-center gap-2 text-purple-800">
                        <span className="w-2 h-2 bg-purple-600 rounded-full" />
                        <strong>Form 8621</strong> - PFIC Annual Information Statement
                      </div>
                    )}
                    {formData.hasForeignTrust && (
                      <div className="flex items-center gap-2 text-teal-800">
                        <span className="w-2 h-2 bg-teal-600 rounded-full" />
                        <strong>Form 3520/3520-A</strong> - Foreign Trust Reporting
                      </div>
                    )}
                    {formData.hasForeignCorporation && formData.foreignCorpOwnership >= 10 && (
                      <div className="flex items-center gap-2 text-blue-800">
                        <span className="w-2 h-2 bg-blue-600 rounded-full" />
                        <strong>Form 5471</strong> - Information Return for Foreign Corporation
                      </div>
                    )}
                    {formData.hasForeignPartnership && (
                      <div className="flex items-center gap-2 text-orange-800">
                        <span className="w-2 h-2 bg-orange-600 rounded-full" />
                        <strong>Form 8865</strong> - Return of U.S. Persons With Respect to Foreign Partnerships
                      </div>
                    )}
                    {formData.foreignGiftsReceived >= 100000 && (
                      <div className="flex items-center gap-2 text-amber-800">
                        <span className="w-2 h-2 bg-amber-600 rounded-full" />
                        <strong>Form 3520</strong> - Part IV (Foreign Gifts)
                      </div>
                    )}
                    {formData.foreignTaxPaid > 0 && (
                      <div className="flex items-center gap-2 text-green-800">
                        <span className="w-2 h-2 bg-green-600 rounded-full" />
                        <strong>Form 1116</strong> - Foreign Tax Credit
                      </div>
                    )}
                  </div>
                </div>
              )}
            </div>
          )}

          {/* Step 6: Review */}
          {step === 6 && (
            <div className="space-y-6">
              <h2 className="text-lg font-semibold text-slate-900 flex items-center gap-2">
                <FileText className="w-5 h-5 text-blue-600" />
                Review {mode === 'professional' && customerName ? `${customerName}'s` : 'Your'} Return
              </h2>

              <div className="space-y-4">
                <div className="p-4 bg-slate-50 rounded-lg">
                  <h3 className="font-medium text-slate-700 mb-2">Filing Information</h3>
                  <div className="grid grid-cols-2 gap-2 text-sm">
                    <span className="text-slate-500">Tax Year:</span>
                    <span className="font-medium">{formData.taxYear}</span>
                    <span className="text-slate-500">Filing Status:</span>
                    <span className="font-medium">{formData.filingStatus}</span>
                    <span className="text-slate-500">Dependents:</span>
                    <span className="font-medium">{formData.numDependents}</span>
                  </div>
                </div>

                <div className="p-4 bg-green-50 rounded-lg">
                  <h3 className="font-medium text-green-700 mb-2">Income Summary</h3>
                  <div className="grid grid-cols-2 gap-2 text-sm">
                    <span className="text-green-600">Total Income:</span>
                    <span className="font-medium text-green-800">${grossIncome.toLocaleString()}</span>
                  </div>
                </div>

                <div className="p-4 bg-amber-50 rounded-lg">
                  <h3 className="font-medium text-amber-700 mb-2">Deductions</h3>
                  <div className="grid grid-cols-2 gap-2 text-sm">
                    <span className="text-amber-600">
                      {formData.standardDeduction ? 'Standard Deduction:' : 'Itemized Deductions:'}
                    </span>
                    <span className="font-medium text-amber-800">${totalDeductions.toLocaleString()}</span>
                    <span className="text-amber-600">Taxable Income:</span>
                    <span className="font-medium text-amber-800">${taxableIncome.toLocaleString()}</span>
                  </div>
                </div>

                {/* International Forms Summary in Review */}
                {(formData.hasForeignAccounts || formData.hasPFIC || formData.hasForeignTrust || 
                  formData.hasForeignCorporation || formData.hasForeignPartnership || 
                  formData.foreignGiftsReceived >= 100000 || formData.foreignTaxPaid > 0) && (
                  <div className="p-4 bg-indigo-50 rounded-lg">
                    <h3 className="font-medium text-indigo-700 mb-2 flex items-center gap-2">
                      <Globe className="w-4 h-4" />
                      International Tax Forms Required
                    </h3>
                    <div className="flex flex-wrap gap-2">
                      {formData.foreignAccountValue >= 50000 && (
                        <span className="px-2 py-1 bg-indigo-100 text-indigo-800 rounded text-xs font-medium">Form 8938</span>
                      )}
                      {formData.foreignAccountValue >= 10000 && (
                        <span className="px-2 py-1 bg-indigo-100 text-indigo-800 rounded text-xs font-medium">FBAR</span>
                      )}
                      {formData.hasPFIC && (
                        <span className="px-2 py-1 bg-purple-100 text-purple-800 rounded text-xs font-medium">Form 8621</span>
                      )}
                      {formData.hasForeignTrust && (
                        <span className="px-2 py-1 bg-teal-100 text-teal-800 rounded text-xs font-medium">Form 3520</span>
                      )}
                      {formData.hasForeignCorporation && formData.foreignCorpOwnership >= 10 && (
                        <span className="px-2 py-1 bg-blue-100 text-blue-800 rounded text-xs font-medium">Form 5471</span>
                      )}
                      {formData.hasForeignPartnership && (
                        <span className="px-2 py-1 bg-orange-100 text-orange-800 rounded text-xs font-medium">Form 8865</span>
                      )}
                      {formData.foreignTaxPaid > 0 && (
                        <span className="px-2 py-1 bg-green-100 text-green-800 rounded text-xs font-medium">Form 1116</span>
                      )}
                    </div>
                    {formData.foreignTaxPaid > 0 && (
                      <p className="mt-2 text-xs text-indigo-700">
                        Foreign Tax Credit available: ${formData.foreignTaxPaid.toLocaleString()}
                      </p>
                    )}
                  </div>
                )}
              </div>
            </div>
          )}

          {/* Navigation Buttons */}
          <div className="flex justify-between pt-6 mt-6 border-t border-slate-200">
            <button
              onClick={() => step === 1 ? onCancel() : setStep(Math.max(1, step - 1))}
              className="px-6 py-2 border border-slate-200 text-slate-600 rounded-lg hover:bg-slate-50"
            >
              {step === 1 ? 'Cancel' : 'Previous'}
            </button>
            <div className="flex items-center gap-3">
              {/* Save as Draft — available on any step */}
              <button
                onClick={() => saveDraftMutation.mutate(formData)}
                disabled={isMutating || !!duplicateError}
                className="px-5 py-2 border border-slate-300 text-slate-700 rounded-lg hover:bg-slate-50 disabled:opacity-50 flex items-center gap-2"
              >
                {saveDraftMutation.isPending ? (
                  <>
                    <Loader2 className="w-4 h-4 animate-spin" />
                    Saving...
                  </>
                ) : (
                  <>
                    <Save className="w-4 h-4" />
                    Save as Draft
                  </>
                )}
              </button>
              {step < 6 ? (
                <button
                  onClick={() => setStep(step + 1)}
                  className="px-6 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700"
                >
                  Continue
                </button>
              ) : (
                <button
                  onClick={() => isEditMode ? updateMutation.mutate(formData) : createMutation.mutate(formData)}
                  disabled={isMutating || !!duplicateError}
                  className="px-6 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 disabled:opacity-50 flex items-center gap-2"
                >
                  {(createMutation.isPending || updateMutation.isPending) ? (
                    <>
                      <Loader2 className="w-4 h-4 animate-spin" />
                      Submitting...
                    </>
                  ) : (
                    <>
                      <Send className="w-4 h-4" />
                      {isEditMode ? 'Update & Submit' : 'Submit Return'}
                    </>
                  )}
                </button>
              )}
            </div>
          </div>
        </div>

        {/* Summary Sidebar */}
        <div className="bg-white rounded-xl border border-slate-200 p-6 h-fit sticky top-6">
          <h3 className="font-semibold text-slate-900 mb-4">Estimated Summary</h3>
          
          <div className="space-y-3 text-sm">
            <div className="flex justify-between">
              <span className="text-slate-500">Gross Income</span>
              <span className="font-medium">${grossIncome.toLocaleString()}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-slate-500">Deductions</span>
              <span className="font-medium">-${totalDeductions.toLocaleString()}</span>
            </div>
            <div className="flex justify-between border-t border-slate-100 pt-3">
              <span className="text-slate-500">Taxable Income</span>
              <span className="font-medium">${taxableIncome.toLocaleString()}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-slate-500">Estimated Tax</span>
              <span className="font-medium">${estimatedTax.toLocaleString()}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-slate-500">Est. Withholding</span>
              <span className="font-medium">${estimatedWithholding.toLocaleString()}</span>
            </div>
          </div>

          <div className={`mt-4 p-4 rounded-lg ${estimatedRefund >= 0 ? 'bg-green-50' : 'bg-red-50'}`}>
            <div className="text-center">
              <span className="text-sm text-slate-600 block">
                {estimatedRefund >= 0 ? 'Estimated Refund' : 'Estimated Amount Owed'}
              </span>
              <span className={`text-2xl font-bold ${estimatedRefund >= 0 ? 'text-green-600' : 'text-red-600'}`}>
                ${Math.abs(estimatedRefund).toLocaleString()}
              </span>
            </div>
          </div>

          <p className="text-xs text-slate-400 mt-4 text-center">
            This is an estimate. Actual amounts may vary.
          </p>

          {/* Ask AI Button */}
          <button
            onClick={() => setShowAssistant(true)}
            className="mt-4 w-full flex items-center justify-center gap-2 px-4 py-3 bg-gradient-to-r from-purple-600 to-blue-600 text-white rounded-lg hover:from-purple-700 hover:to-blue-700 transition-all shadow-lg hover:shadow-xl"
          >
            <Sparkles className="w-4 h-4" />
            Ask AI Assistant
          </button>
        </div>
      </div>

      {/* AI Assistant Floating Panel */}
      {showAssistant && (
        <div className={`fixed ${assistantMaximized ? 'inset-4' : 'bottom-6 right-6 w-96 max-h-[80vh]'} bg-white rounded-xl shadow-2xl border border-slate-200 flex flex-col z-50 transition-all duration-300`}>
          {/* Assistant Header */}
          <div className="flex-shrink-0 flex items-center justify-between p-4 border-b border-slate-200 bg-gradient-to-r from-purple-600 to-blue-600 text-white rounded-t-xl">
            <div className="flex items-center gap-2">
              <Bot className="w-5 h-5" />
              <span className="font-semibold">Tax Assistant</span>
              <span className="text-xs bg-white/20 px-2 py-0.5 rounded-full">AI Powered</span>
            </div>
            <div className="flex items-center gap-1">
              <button
                onClick={() => setAssistantMaximized(!assistantMaximized)}
                className="p-1.5 hover:bg-white/20 rounded-lg transition-colors"
              >
                {assistantMaximized ? <Minimize2 className="w-4 h-4" /> : <Maximize2 className="w-4 h-4" />}
              </button>
              <button
                onClick={() => setShowAssistant(false)}
                className="p-1.5 hover:bg-white/20 rounded-lg transition-colors"
              >
                <X className="w-4 h-4" />
              </button>
            </div>
          </div>

          {/* Messages Area */}
          <div className={`flex-1 min-h-0 overflow-y-auto p-4 space-y-4 ${assistantMaximized ? '' : 'max-h-80'}`}>
            {assistantMessages.length === 0 ? (
              <div className="text-center py-8">
                <div className="w-12 h-12 bg-purple-100 rounded-full flex items-center justify-center mx-auto mb-3">
                  <HelpCircle className="w-6 h-6 text-purple-600" />
                </div>
                <p className="text-slate-600 text-sm mb-4">
                  I can help answer your tax questions as you complete this return.
                </p>
                <div className="space-y-2">
                  {stepQuestions[step]?.map((question, idx) => (
                    <button
                      key={idx}
                      onClick={() => handleAssistantSubmit(question)}
                      className="block w-full text-left text-sm p-2 bg-slate-50 hover:bg-slate-100 rounded-lg text-slate-700 transition-colors"
                    >
                      {question}
                    </button>
                  ))}
                </div>
              </div>
            ) : (
              assistantMessages.map((msg) => (
                <div key={msg.id} className={`flex ${msg.role === 'user' ? 'justify-end' : 'justify-start'}`}>
                  <div className={`max-w-[85%] rounded-lg p-3 ${
                    msg.role === 'user' 
                      ? 'bg-blue-600 text-white' 
                      : 'bg-slate-100 text-slate-800'
                  }`}>
                    {msg.role === 'assistant' ? (
                      <div className="prose prose-sm max-w-none prose-slate">
                        <ReactMarkdown>{msg.content}</ReactMarkdown>
                        {msg.isLLMAugmented && (
                          <div className="mt-2 pt-2 border-t border-slate-200">
                            <span className="text-xs text-purple-600 flex items-center gap-1">
                              <Sparkles className="w-3 h-3" />
                              AI-generated response
                            </span>
                          </div>
                        )}
                      </div>
                    ) : (
                      <p className="text-sm">{msg.content}</p>
                    )}
                  </div>
                </div>
              ))
            )}
            {assistantMutation.isPending && (
              <div className="flex justify-start">
                <div className="bg-slate-100 rounded-lg p-3 flex items-center gap-2">
                  <Loader2 className="w-4 h-4 animate-spin text-purple-600" />
                  <span className="text-sm text-slate-600">Thinking...</span>
                </div>
              </div>
            )}
          </div>

          {/* Input Area */}
          <div className="flex-shrink-0 p-4 border-t border-slate-200 rounded-b-xl">
            <div className="flex gap-2">
              <input
                type="text"
                value={assistantInput}
                onChange={(e) => setAssistantInput(e.target.value)}
                onKeyPress={(e) => e.key === 'Enter' && handleAssistantSubmit(assistantInput)}
                placeholder="Ask a tax question..."
                className="flex-1 p-2 border border-slate-200 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent text-sm"
              />
              <button
                onClick={() => handleAssistantSubmit(assistantInput)}
                disabled={!assistantInput.trim() || assistantMutation.isPending}
                className="p-2 bg-purple-600 text-white rounded-lg hover:bg-purple-700 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                <Send className="w-4 h-4" />
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
