import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { FileText, Eye, Filter, Calendar, X, DollarSign, Receipt, CreditCard, Pencil } from 'lucide-react'
import { api } from '../../lib/api'

interface TaxReturn {
  ReturnId: number
  TaxYear: number
  FilingStatus: string
  FilingDate: string
  GrossIncome: number
  AdjustedGrossIncome: number
  TotalDeductions: number
  TaxableIncome: number
  TaxLiability: number
  TotalWithheld: number  // Matches DB column name
  RefundAmount: number
  AmountOwed: number
  Status?: string
  CreatedAt?: string
}

export default function MyReturns() {
  const navigate = useNavigate()
  const [yearFilter, setYearFilter] = useState<string>('all')
  const [selectedReturn, setSelectedReturn] = useState<TaxReturn | null>(null)
  
  // In a real app, we'd filter by CustomerId of the logged-in user
  // For demo purposes, we limit to just a few returns for a specific user
  const { data: returns, isLoading } = useQuery({
    queryKey: ['my-returns', yearFilter],
    queryFn: () => api.getTaxReturns({
      // Filter to a specific customer (simulating logged-in user)
      // and optionally by year
      filter: yearFilter !== 'all' 
        ? `CustomerId eq 1 and TaxYear eq ${yearFilter}` 
        : 'CustomerId eq 1',
      orderby: 'TaxYear desc',
    }),
  })

  const years = ['all', '2024', '2023', '2022', '2021', '2020']

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-4">
        <div className="page-header mb-0">
          <h1 className="page-title">My Tax Returns</h1>
          <p className="page-subtitle">View and manage your tax filing history</p>
        </div>
        
        {/* Filters */}
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-2">
            <Filter className="w-4 h-4 text-slate-400" />
            <select
              value={yearFilter}
              onChange={(e) => setYearFilter(e.target.value)}
              className="input w-auto"
            >
              {years.map((year) => (
                <option key={year} value={year}>
                  {year === 'all' ? 'All Years' : `Tax Year ${year}`}
                </option>
              ))}
            </select>
          </div>
          <Link to="/filer/new-return" className="btn btn-primary flex items-center gap-2">
            <FileText className="w-4 h-4" />
            New Return
          </Link>
        </div>
      </div>

      {/* Returns Table */}
      <div className="card overflow-hidden">
        {isLoading ? (
          <div className="p-8">
            <div className="animate-pulse space-y-4">
              {[1, 2, 3, 4].map((i) => (
                <div key={i} className="h-16 bg-slate-100 rounded-lg" />
              ))}
            </div>
          </div>
        ) : returns?.value?.length > 0 ? (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="text-left text-xs font-semibold text-slate-500 uppercase tracking-wider border-b border-slate-200 bg-slate-50">
                  <th className="p-4">Tax Year</th>
                  <th className="p-4">Filing Status</th>
                  <th className="p-4">Status</th>
                  <th className="p-4">Date Filed</th>
                  <th className="p-4 text-right">Refund/Owed</th>
                  <th className="p-4 text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                {returns.value.map((ret: TaxReturn) => (
                  <tr key={ret.ReturnId} className="border-b border-slate-100 last:border-0 hover:bg-slate-50 cursor-pointer" onClick={() => setSelectedReturn(ret)}>
                    <td className="p-4">
                      <div className="flex items-center gap-3">
                        <div className="w-10 h-10 bg-slate-100 rounded-lg flex items-center justify-center">
                          <FileText className="w-5 h-5 text-slate-600" />
                        </div>
                        <span className="font-semibold text-slate-900">{ret.TaxYear}</span>
                      </div>
                    </td>
                    <td className="p-4 text-slate-600">{ret.FilingStatus}</td>
                    <td className="p-4">
                      <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${
                        ret.Status === 'Draft' ? 'bg-amber-100 text-amber-800' :
                        ret.Status === 'In Progress' ? 'bg-blue-100 text-blue-800' :
                        ret.Status === 'Filed' ? 'bg-indigo-100 text-indigo-800' :
                        ret.Status === 'Accepted' ? 'bg-green-100 text-green-800' :
                        ret.Status === 'Rejected' ? 'bg-red-100 text-red-800' :
                        'bg-slate-100 text-slate-800'
                      }`}>
                        {ret.Status || 'Filed'}
                      </span>
                    </td>
                    <td className="p-4">
                      <span className="flex items-center gap-1 text-slate-600">
                        <Calendar className="w-3 h-3" />
                        {new Date(ret.FilingDate).toLocaleDateString()}
                      </span>
                    </td>
                    <td className="p-4 text-right">
                      {ret.RefundAmount > 0 && (
                        <span className="text-emerald-600 font-medium">
                          +${ret.RefundAmount.toLocaleString()}
                        </span>
                      )}
                      {ret.AmountOwed > 0 && (
                        <span className="text-red-600 font-medium">
                          -${ret.AmountOwed.toLocaleString()}
                        </span>
                      )}
                      {(!ret.RefundAmount || ret.RefundAmount === 0) && (!ret.AmountOwed || ret.AmountOwed === 0) && (
                        <span className="text-slate-400">—</span>
                      )}
                    </td>
                    <td className="p-4">
                      <div className="flex items-center justify-end gap-1">
                        {ret.Status === 'Draft' && (
                          <button
                            onClick={(e) => { e.stopPropagation(); navigate(`/filer/edit-return/${ret.ReturnId}`); }}
                            className="p-2 text-amber-500 hover:text-amber-700 hover:bg-amber-50 rounded-md transition-colors"
                            title="Edit Draft"
                          >
                            <Pencil className="w-4 h-4" />
                          </button>
                        )}
                        <button
                          onClick={(e) => { e.stopPropagation(); setSelectedReturn(ret); }}
                          className="p-2 text-slate-400 hover:text-slate-600 hover:bg-slate-100 rounded-md transition-colors"
                          title="View Details"
                        >
                          <Eye className="w-4 h-4" />
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="p-12 text-center">
            <FileText className="w-12 h-12 text-slate-300 mx-auto mb-4" />
            <h3 className="text-lg font-medium text-slate-900 mb-2">No returns found</h3>
            <p className="text-slate-600">
              {yearFilter !== 'all' 
                ? `You don't have any returns for tax year ${yearFilter}`
                : "You haven't filed any tax returns yet"
              }
            </p>
          </div>
        )}
      </div>

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
                    Filed {new Date(selectedReturn.FilingDate).toLocaleDateString()} • {selectedReturn.FilingStatus}
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

              {/* Additional Info */}
              <div className="grid grid-cols-2 gap-4 text-sm">
                <div className="p-3 bg-slate-50 rounded-lg">
                  <span className="text-slate-500 block">Tax Year</span>
                  <span className="font-semibold">{selectedReturn.TaxYear}</span>
                </div>
                <div className="p-3 bg-slate-50 rounded-lg">
                  <span className="text-slate-500 block">Filing Status</span>
                  <span className="font-semibold">{selectedReturn.FilingStatus}</span>
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
