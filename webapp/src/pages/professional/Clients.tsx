import { useState, useEffect } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Users, Search, Phone, Mail, MapPin, Plus, X, FileText, Calendar, Loader2, Eye, DollarSign, Receipt, CreditCard, Sparkles } from 'lucide-react'
import { api } from '../../lib/api'
import NewReturnForm from '../../components/NewReturnForm'

interface Client {
  CustomerId: number
  FirstName: string
  LastName: string
  Email: string
  Phone: string
  Address: string
  City: string
  State: string
  ZipCode: string
  DateOfBirth: string
  PreferredBranchId?: number
  CreatedAt: string
}

interface TaxReturn {
  ReturnId: number
  TaxYear: number
  FilingStatus: string
  FilingDate: string
  GrossIncome: number
  AdjustedGrossIncome?: number
  TotalDeductions?: number
  TaxableIncome?: number
  TaxLiability?: number
  TotalWithheld?: number
  RefundAmount: number
  AmountOwed: number
  Status?: string
}

export default function Clients() {
  const queryClient = useQueryClient()
  const [searchTerm, setSearchTerm] = useState('')
  const [selectedClient, setSelectedClient] = useState<Client | null>(null)
  const [selectedReturn, setSelectedReturn] = useState<TaxReturn | null>(null)
  const [showAddModal, setShowAddModal] = useState(false)
  const [showNewReturnModal, setShowNewReturnModal] = useState(false)
  const [aiSummary, setAiSummary] = useState<string>('')
  const [aiSummaryLoading, setAiSummaryLoading] = useState(false)
  const [newClient, setNewClient] = useState({
    FirstName: '',
    LastName: '',
    Email: '',
    Phone: '',
    Address: '',
    City: '',
    State: '',
    ZipCode: '',
    DateOfBirth: '',
  })
  
  const { data: clients, isLoading } = useQuery({
    queryKey: ['clients', searchTerm],
    queryFn: () => api.getCustomers({
      filter: searchTerm ? `contains(LastName, '${searchTerm}') or contains(FirstName, '${searchTerm}')` : undefined,
    }),
  })

  const { data: clientReturns, isLoading: returnsLoading } = useQuery({
    queryKey: ['client-returns', selectedClient?.CustomerId],
    queryFn: () => api.getTaxReturns({
      filter: `CustomerId eq ${selectedClient?.CustomerId}`,
      orderby: 'TaxYear desc',
    }),
    enabled: !!selectedClient,
  })

  // Generate AI summary when return is selected
  useEffect(() => {
    async function generateSummary() {
      if (!selectedReturn) {
        setAiSummary('')
        return
      }

      setAiSummaryLoading(true)
      try {
        // Build context from return data
        const context = `Tax Year: ${selectedReturn.TaxYear}
Filing Status: ${selectedReturn.FilingStatus}
Gross Income: $${selectedReturn.GrossIncome.toLocaleString()}
Adjusted Gross Income: $${(selectedReturn.AdjustedGrossIncome || 0).toLocaleString()}
Total Deductions: $${(selectedReturn.TotalDeductions || 0).toLocaleString()}
Taxable Income: $${(selectedReturn.TaxableIncome || 0).toLocaleString()}
Tax Liability: $${(selectedReturn.TaxLiability || 0).toLocaleString()}
Total Withholding: $${(selectedReturn.TotalWithheld || 0).toLocaleString()}
Refund: $${(selectedReturn.RefundAmount || 0).toLocaleString()}
Amount Owed: $${(selectedReturn.AmountOwed || 0).toLocaleString()}`

        const result = await api.askTaxAssistant(
          'Provide a professional analysis and summary of this tax return, highlighting key insights, potential optimization opportunities, and any notable items.',
          context,
          3
        )

        if (result.answer) {
          setAiSummary(result.answer)
        }
      } catch (error) {
        console.error('Failed to generate AI summary:', error)
        setAiSummary('Unable to generate AI summary at this time.')
      } finally {
        setAiSummaryLoading(false)
      }
    }

    generateSummary()
  }, [selectedReturn])

  const createClientMutation = useMutation({
    mutationFn: (data: typeof newClient) => api.createCustomer(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['clients'] })
      setShowAddModal(false)
      setNewClient({
        FirstName: '',
        LastName: '',
        Email: '',
        Phone: '',
        Address: '',
        City: '',
        State: '',
        ZipCode: '',
        DateOfBirth: '',
      })
    },
    onError: (error) => {
      console.error('Failed to create client:', error)
      alert('Failed to create client. Please try again.')
    },
  })

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">My Clients</h1>
          <p className="text-slate-600 mt-1">Manage your client relationships</p>
        </div>
        <button
          onClick={() => setShowAddModal(true)}
          className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
        >
          <Plus className="w-4 h-4" />
          Add Client
        </button>
      </div>

      {/* Search */}
      <div className="relative">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-400" />
        <input
          type="text"
          value={searchTerm}
          onChange={(e) => setSearchTerm(e.target.value)}
          placeholder="Search clients by name..."
          className="w-full pl-10 pr-4 py-3 border border-slate-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-blue-500"
        />
      </div>

      {/* Client Grid */}
      {isLoading ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {[1, 2, 3, 4, 5, 6].map((i) => (
            <div key={i} className="bg-white rounded-xl border border-slate-200 p-6 animate-pulse">
              <div className="flex items-center gap-4 mb-4">
                <div className="w-12 h-12 bg-slate-100 rounded-full" />
                <div className="flex-1">
                  <div className="h-4 bg-slate-100 rounded w-3/4 mb-2" />
                  <div className="h-3 bg-slate-100 rounded w-1/2" />
                </div>
              </div>
              <div className="space-y-2">
                <div className="h-3 bg-slate-100 rounded" />
                <div className="h-3 bg-slate-100 rounded w-2/3" />
              </div>
            </div>
          ))}
        </div>
      ) : clients?.value?.length > 0 ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {clients.value.map((client: Client) => (
            <div
              key={client.CustomerId}
              onClick={() => setSelectedClient(client)}
              className="bg-white rounded-xl border border-slate-200 p-6 hover:shadow-md hover:border-blue-200 transition-all cursor-pointer"
            >
              <div className="flex items-center gap-4 mb-4">
                <div className="w-12 h-12 bg-blue-100 rounded-full flex items-center justify-center">
                  <span className="text-blue-600 font-semibold text-lg">
                    {client.FirstName?.charAt(0)}{client.LastName?.charAt(0)}
                  </span>
                </div>
                <div>
                  <h3 className="font-semibold text-slate-900">
                    {client.FirstName} {client.LastName}
                  </h3>
                  <span className="text-sm text-slate-500">Client</span>
                </div>
              </div>

              <div className="space-y-2 text-sm">
                {client.Email && (
                  <div className="flex items-center gap-2 text-slate-600">
                    <Mail className="w-4 h-4 text-slate-400" />
                    <span className="truncate">{client.Email}</span>
                  </div>
                )}
                {client.Phone && (
                  <div className="flex items-center gap-2 text-slate-600">
                    <Phone className="w-4 h-4 text-slate-400" />
                    <span>{client.Phone}</span>
                  </div>
                )}
                {client.City && client.State && (
                  <div className="flex items-center gap-2 text-slate-600">
                    <MapPin className="w-4 h-4 text-slate-400" />
                    <span>{client.City}, {client.State}</span>
                  </div>
                )}
              </div>

              <div className="mt-4 pt-4 border-t border-slate-100 flex items-center justify-between">
                <span className="text-xs text-slate-500">
                  ID: {client.CustomerId}
                </span>
                <span className="text-sm text-blue-600 font-medium">
                  View Details →
                </span>
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div className="bg-white rounded-xl border border-slate-200 p-12 text-center">
          <Users className="w-12 h-12 text-slate-300 mx-auto mb-4" />
          <h3 className="text-lg font-medium text-slate-900 mb-2">No clients found</h3>
          <p className="text-slate-600 mb-4">
            {searchTerm ? 'Try a different search term' : 'You have no clients assigned yet'}
          </p>
          <button
            onClick={() => setShowAddModal(true)}
            className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700"
          >
            Add Your First Client
          </button>
        </div>
      )}

      {/* Client Detail Modal */}
      {selectedClient && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-xl max-w-2xl w-full max-h-[90vh] overflow-y-auto shadow-2xl">
            <div className="sticky top-0 bg-white border-b border-slate-200 p-4 flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="w-12 h-12 bg-blue-100 rounded-full flex items-center justify-center">
                  <span className="text-blue-600 font-semibold text-lg">
                    {selectedClient.FirstName?.charAt(0)}{selectedClient.LastName?.charAt(0)}
                  </span>
                </div>
                <div>
                  <h2 className="text-lg font-semibold text-slate-900">
                    {selectedClient.FirstName} {selectedClient.LastName}
                  </h2>
                  <p className="text-sm text-slate-500">Client ID: {selectedClient.CustomerId}</p>
                </div>
              </div>
              <button
                onClick={() => setSelectedClient(null)}
                className="p-2 hover:bg-slate-100 rounded-lg transition-colors"
              >
                <X className="w-5 h-5 text-slate-500" />
              </button>
            </div>
            
            <div className="p-6 space-y-6">
              {/* Contact Info */}
              <div>
                <h3 className="text-sm font-semibold text-slate-700 mb-3">Contact Information</h3>
                <div className="grid grid-cols-2 gap-4 text-sm">
                  <div>
                    <span className="text-slate-500">Email</span>
                    <p className="font-medium">{selectedClient.Email || 'N/A'}</p>
                  </div>
                  <div>
                    <span className="text-slate-500">Phone</span>
                    <p className="font-medium">{selectedClient.Phone || 'N/A'}</p>
                  </div>
                  <div className="col-span-2">
                    <span className="text-slate-500">Address</span>
                    <p className="font-medium">
                      {selectedClient.Address && `${selectedClient.Address}, `}
                      {selectedClient.City}{selectedClient.State && `, ${selectedClient.State}`} {selectedClient.ZipCode}
                    </p>
                  </div>
                  <div>
                    <span className="text-slate-500">Date of Birth</span>
                    <p className="font-medium">{selectedClient.DateOfBirth ? new Date(selectedClient.DateOfBirth).toLocaleDateString() : 'N/A'}</p>
                  </div>
                  <div>
                    <span className="text-slate-500">Client Since</span>
                    <p className="font-medium">{selectedClient.CreatedAt ? new Date(selectedClient.CreatedAt).toLocaleDateString() : 'N/A'}</p>
                  </div>
                </div>
              </div>

              {/* Tax Returns */}
              <div>
                <div className="flex items-center justify-between mb-3">
                  <h3 className="text-sm font-semibold text-slate-700 flex items-center gap-2">
                    <FileText className="w-4 h-4" />
                    Tax Return History
                  </h3>
                  <button
                    onClick={() => setShowNewReturnModal(true)}
                    className="flex items-center gap-1 px-3 py-1.5 text-sm bg-blue-600 text-white rounded-lg hover:bg-blue-700"
                  >
                    <Plus className="w-3 h-3" />
                    New Return
                  </button>
                </div>
                {returnsLoading ? (
                  <div className="flex items-center justify-center py-8">
                    <Loader2 className="w-6 h-6 animate-spin text-blue-600" />
                  </div>
                ) : clientReturns?.value?.length > 0 ? (
                  <div className="space-y-3">
                    {clientReturns.value.map((ret: TaxReturn) => (
                      <div 
                        key={ret.ReturnId} 
                        className="p-4 bg-slate-50 rounded-lg flex items-center justify-between hover:bg-slate-100 cursor-pointer transition-colors"
                        onClick={() => setSelectedReturn(ret)}
                      >
                        <div className="flex items-center gap-4">
                          <div className="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center">
                            <Calendar className="w-5 h-5 text-blue-600" />
                          </div>
                          <div>
                            <p className="font-medium text-slate-900">Tax Year {ret.TaxYear}</p>
                            <p className="text-sm text-slate-500">
                              Filed {new Date(ret.FilingDate).toLocaleDateString()} • {ret.FilingStatus}
                            </p>
                          </div>
                        </div>
                        <div className="flex items-center gap-4">
                          <div className="text-right">
                            {ret.RefundAmount > 0 && (
                              <span className="text-green-600 font-semibold">
                                +${ret.RefundAmount.toLocaleString()}
                              </span>
                            )}
                            {ret.AmountOwed > 0 && (
                              <span className="text-red-600 font-semibold">
                                -${ret.AmountOwed.toLocaleString()}
                              </span>
                            )}
                            <p className="text-xs text-slate-500">
                              Income: ${ret.GrossIncome?.toLocaleString() || '0'}
                            </p>
                          </div>
                          <button
                            onClick={(e) => { e.stopPropagation(); setSelectedReturn(ret); }}
                            className="p-2 text-slate-400 hover:text-blue-600 hover:bg-blue-50 rounded-lg transition-colors"
                            title="View Details"
                          >
                            <Eye className="w-5 h-5" />
                          </button>
                        </div>
                      </div>
                    ))}
                  </div>
                ) : (
                  <div className="text-center py-8 bg-slate-50 rounded-lg">
                    <FileText className="w-8 h-8 text-slate-300 mx-auto mb-2" />
                    <p className="text-slate-500">No tax returns on file</p>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Add Client Modal */}
      {showAddModal && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-xl max-w-lg w-full max-h-[90vh] overflow-y-auto shadow-2xl">
            <div className="sticky top-0 bg-white border-b border-slate-200 p-4 flex items-center justify-between">
              <h2 className="text-lg font-semibold text-slate-900">Add New Client</h2>
              <button
                onClick={() => setShowAddModal(false)}
                className="p-2 hover:bg-slate-100 rounded-lg transition-colors"
              >
                <X className="w-5 h-5 text-slate-500" />
              </button>
            </div>
            
            <form
              onSubmit={(e) => {
                e.preventDefault()
                createClientMutation.mutate(newClient)
              }}
              className="p-6 space-y-4"
            >
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-slate-700 mb-1">First Name *</label>
                  <input
                    type="text"
                    required
                    value={newClient.FirstName}
                    onChange={(e) => setNewClient(prev => ({ ...prev, FirstName: e.target.value }))}
                    className="w-full p-2 border border-slate-200 rounded-lg focus:ring-2 focus:ring-blue-500"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-slate-700 mb-1">Last Name *</label>
                  <input
                    type="text"
                    required
                    value={newClient.LastName}
                    onChange={(e) => setNewClient(prev => ({ ...prev, LastName: e.target.value }))}
                    className="w-full p-2 border border-slate-200 rounded-lg focus:ring-2 focus:ring-blue-500"
                  />
                </div>
              </div>

              <div>
                <label className="block text-sm font-medium text-slate-700 mb-1">Email</label>
                <input
                  type="email"
                  value={newClient.Email}
                  onChange={(e) => setNewClient(prev => ({ ...prev, Email: e.target.value }))}
                  className="w-full p-2 border border-slate-200 rounded-lg focus:ring-2 focus:ring-blue-500"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-slate-700 mb-1">Phone</label>
                <input
                  type="tel"
                  value={newClient.Phone}
                  onChange={(e) => setNewClient(prev => ({ ...prev, Phone: e.target.value }))}
                  className="w-full p-2 border border-slate-200 rounded-lg focus:ring-2 focus:ring-blue-500"
                  placeholder="(555) 555-5555"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-slate-700 mb-1">Address</label>
                <input
                  type="text"
                  value={newClient.Address}
                  onChange={(e) => setNewClient(prev => ({ ...prev, Address: e.target.value }))}
                  className="w-full p-2 border border-slate-200 rounded-lg focus:ring-2 focus:ring-blue-500"
                />
              </div>

              <div className="grid grid-cols-3 gap-4">
                <div>
                  <label className="block text-sm font-medium text-slate-700 mb-1">City</label>
                  <input
                    type="text"
                    value={newClient.City}
                    onChange={(e) => setNewClient(prev => ({ ...prev, City: e.target.value }))}
                    className="w-full p-2 border border-slate-200 rounded-lg focus:ring-2 focus:ring-blue-500"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-slate-700 mb-1">State</label>
                  <input
                    type="text"
                    maxLength={2}
                    value={newClient.State}
                    onChange={(e) => setNewClient(prev => ({ ...prev, State: e.target.value.toUpperCase() }))}
                    className="w-full p-2 border border-slate-200 rounded-lg focus:ring-2 focus:ring-blue-500"
                    placeholder="CA"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-slate-700 mb-1">ZIP</label>
                  <input
                    type="text"
                    maxLength={10}
                    value={newClient.ZipCode}
                    onChange={(e) => setNewClient(prev => ({ ...prev, ZipCode: e.target.value }))}
                    className="w-full p-2 border border-slate-200 rounded-lg focus:ring-2 focus:ring-blue-500"
                  />
                </div>
              </div>

              <div>
                <div>
                  <label className="block text-sm font-medium text-slate-700 mb-1">Date of Birth</label>
                  <input
                    type="date"
                    value={newClient.DateOfBirth}
                    onChange={(e) => setNewClient(prev => ({ ...prev, DateOfBirth: e.target.value }))}
                    className="w-full p-2 border border-slate-200 rounded-lg focus:ring-2 focus:ring-blue-500"
                  />
                </div>
              </div>

              <div className="flex justify-end gap-3 pt-4 border-t border-slate-200">
                <button
                  type="button"
                  onClick={() => setShowAddModal(false)}
                  className="px-4 py-2 border border-slate-200 rounded-lg hover:bg-slate-50"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={createClientMutation.isPending}
                  className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50 flex items-center gap-2"
                >
                  {createClientMutation.isPending && <Loader2 className="w-4 h-4 animate-spin" />}
                  Add Client
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Create Return for Client Modal - Full Workflow */}
      {showNewReturnModal && selectedClient && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4 overflow-y-auto">
          <div className="bg-white rounded-xl max-w-5xl w-full max-h-[95vh] overflow-y-auto shadow-2xl my-4">
            <div className="p-6">
              <NewReturnForm
                customerId={selectedClient.CustomerId}
                customerName={`${selectedClient.FirstName} ${selectedClient.LastName}`}
                branchId={1}
                professionalId={1}
                mode="professional"
                onSuccess={() => {
                  queryClient.invalidateQueries({ queryKey: ['client-returns', selectedClient.CustomerId] })
                  setShowNewReturnModal(false)
                }}
                onCancel={() => setShowNewReturnModal(false)}
              />
            </div>
          </div>
        </div>
      )}

      {/* Return Detail Modal */}
      {selectedReturn && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-xl max-w-2xl w-full max-h-[90vh] overflow-y-auto shadow-2xl">
            <div className="sticky top-0 bg-white border-b border-slate-200 p-4 flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center">
                  <FileText className="w-5 h-5 text-blue-600" />
                </div>
                <div>
                  <h2 className="text-lg font-semibold text-slate-900">
                    Tax Year {selectedReturn.TaxYear}
                  </h2>
                  <p className="text-sm text-slate-500">
                    {selectedClient ? `${selectedClient.FirstName} ${selectedClient.LastName}` : 'Client Return'} • {selectedReturn.FilingStatus}
                  </p>
                </div>
              </div>
              <button
                onClick={() => setSelectedReturn(null)}
                className="p-2 hover:bg-slate-100 rounded-lg transition-colors"
              >
                <X className="w-5 h-5 text-slate-500" />
              </button>
            </div>
            
            <div className="p-6 space-y-6">
              {/* Refund/Owed Banner */}
              <div className={`p-4 rounded-lg ${selectedReturn.RefundAmount > 0 ? 'bg-green-50' : selectedReturn.AmountOwed > 0 ? 'bg-red-50' : 'bg-slate-50'}`}>
                <div className="text-center">
                  <span className="text-sm text-slate-600 block">
                    {selectedReturn.RefundAmount > 0 ? 'Refund Amount' : selectedReturn.AmountOwed > 0 ? 'Amount Owed' : 'Balance'}
                  </span>
                  <span className={`text-3xl font-bold ${selectedReturn.RefundAmount > 0 ? 'text-green-600' : selectedReturn.AmountOwed > 0 ? 'text-red-600' : 'text-slate-600'}`}>
                    ${(selectedReturn.RefundAmount || selectedReturn.AmountOwed || 0).toLocaleString()}
                  </span>
                </div>
              </div>

              {/* Income Summary */}
              <div>
                <h3 className="text-sm font-semibold text-slate-700 mb-3 flex items-center gap-2">
                  <DollarSign className="w-4 h-4 text-green-600" />
                  Income
                </h3>
                <div className="bg-green-50 p-4 rounded-lg space-y-2">
                  <div className="flex justify-between text-sm">
                    <span className="text-green-700">Gross Income</span>
                    <span className="font-semibold text-green-800">${(selectedReturn.GrossIncome || 0).toLocaleString()}</span>
                  </div>
                  <div className="flex justify-between text-sm">
                    <span className="text-green-700">Adjusted Gross Income</span>
                    <span className="font-semibold text-green-800">${(selectedReturn.AdjustedGrossIncome || 0).toLocaleString()}</span>
                  </div>
                </div>
              </div>

              {/* Deductions */}
              <div>
                <h3 className="text-sm font-semibold text-slate-700 mb-3 flex items-center gap-2">
                  <Receipt className="w-4 h-4 text-amber-600" />
                  Deductions
                </h3>
                <div className="bg-amber-50 p-4 rounded-lg space-y-2">
                  <div className="flex justify-between text-sm">
                    <span className="text-amber-700">Total Deductions</span>
                    <span className="font-semibold text-amber-800">${(selectedReturn.TotalDeductions || 0).toLocaleString()}</span>
                  </div>
                  <div className="flex justify-between text-sm border-t border-amber-200 pt-2">
                    <span className="text-amber-700">Taxable Income</span>
                    <span className="font-semibold text-amber-800">${(selectedReturn.TaxableIncome || 0).toLocaleString()}</span>
                  </div>
                </div>
              </div>

              {/* Tax Calculation */}
              <div>
                <h3 className="text-sm font-semibold text-slate-700 mb-3 flex items-center gap-2">
                  <CreditCard className="w-4 h-4 text-blue-600" />
                  Tax Calculation
                </h3>
                <div className="bg-blue-50 p-4 rounded-lg space-y-2">
                  <div className="flex justify-between text-sm">
                    <span className="text-blue-700">Tax Liability</span>
                    <span className="font-semibold text-blue-800">${(selectedReturn.TaxLiability || 0).toLocaleString()}</span>
                  </div>
                  <div className="flex justify-between text-sm">
                    <span className="text-blue-700">Total Withholding</span>
                    <span className="font-semibold text-blue-800">${(selectedReturn.TotalWithheld || 0).toLocaleString()}</span>
                  </div>
                </div>
              </div>

              {/* AI Summary */}
              <div className="border-t border-slate-200 pt-6">
                <h3 className="text-sm font-semibold text-slate-700 mb-3 flex items-center gap-2">
                  <Sparkles className="w-4 h-4 text-purple-600" />
                  AI Analysis
                </h3>
                {aiSummaryLoading ? (
                  <div className="flex items-center gap-2 text-slate-500 p-4 bg-purple-50 rounded-lg">
                    <Loader2 className="w-4 h-4 animate-spin" />
                    <span className="text-sm">Generating AI analysis...</span>
                  </div>
                ) : aiSummary ? (
                  <div className="bg-purple-50 p-4 rounded-lg">
                    <p className="text-sm text-slate-700 whitespace-pre-wrap leading-relaxed">{aiSummary}</p>
                  </div>
                ) : null}
              </div>

              {/* Additional Info */}
              <div className="grid grid-cols-2 gap-4 text-sm">
                <div className="p-3 bg-slate-50 rounded-lg">
                  <span className="text-slate-500 block">Filing Date</span>
                  <span className="font-semibold">{new Date(selectedReturn.FilingDate).toLocaleDateString()}</span>
                </div>
                <div className="p-3 bg-slate-50 rounded-lg">
                  <span className="text-slate-500 block">Status</span>
                  <span className="font-semibold">{selectedReturn.Status || 'Accepted'}</span>
                </div>
              </div>

              {/* Action Buttons */}
              <div className="flex gap-3 pt-4 border-t border-slate-200">
                <button 
                  onClick={() => setSelectedReturn(null)}
                  className="flex-1 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700"
                >
                  Close
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
