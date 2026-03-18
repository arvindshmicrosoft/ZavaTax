import { useNavigate } from 'react-router-dom'
import { ArrowLeft } from 'lucide-react'
import NewReturnForm from '../../components/NewReturnForm'

export default function NewReturn() {
  const navigate = useNavigate()
  const customerId = 1 // In a real app, this would be the logged-in user's customerId

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
          <h1 className="text-2xl font-bold text-slate-900">New Tax Return</h1>
          <p className="text-slate-600">Complete your tax return step by step</p>
        </div>
      </div>

      {/* Shared New Return Form */}
      <NewReturnForm
        customerId={customerId}
        mode="self"
        onSuccess={() => navigate('/filer/returns')}
        onCancel={() => navigate(-1)}
      />
    </div>
  )
}
