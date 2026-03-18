import { Routes, Route, Navigate } from 'react-router-dom'
import { useState, useEffect } from 'react'
import { MockUser, getCurrentUser, clearCurrentUser } from './lib/mockUsers'
import Layout from './components/Layout'
import LoginPage from './pages/LoginPage'

// Persona pages
import TaxFilerDashboard from './pages/tax-filer/Dashboard'
import TaxFilerAskQuestion from './pages/tax-filer/AskQuestion'
import TaxFilerMyReturns from './pages/tax-filer/MyReturns'
import TaxFilerNewReturn from './pages/tax-filer/NewReturn'
import TaxFilerEditReturn from './pages/tax-filer/EditReturn'

import ProfessionalDashboard from './pages/professional/Dashboard'
import ProfessionalClients from './pages/professional/Clients'
import ProfessionalSimilarCases from './pages/professional/SimilarCases'
import ProfessionalKnowledgeBase from './pages/professional/KnowledgeBase'

import BranchManagerDashboard from './pages/branch-manager/Dashboard'
import BranchManagerTeam from './pages/branch-manager/Team'
import BranchManagerPerformance from './pages/branch-manager/Performance'

import ExecutiveDashboard from './pages/executive/Dashboard'
import ExecutiveAnalytics from './pages/executive/Analytics'
import ExecutiveFilingAnalytics from './pages/executive/FilingAnalytics'

import DevOpsMetrics from './pages/devops/Metrics'
import DevOpsSecurityDashboard from './pages/devops/SecurityDashboard'

function App() {
  const [currentUser, setCurrentUser] = useState<MockUser | null>(null)
  const [isLoading, setIsLoading] = useState(true)

  // Check for existing session on mount
  useEffect(() => {
    const user = getCurrentUser()
    setCurrentUser(user)
    setIsLoading(false)
  }, [])

  const handleLogin = (user: MockUser) => {
    setCurrentUser(user)
  }

  const handleLogout = () => {
    clearCurrentUser()
    setCurrentUser(null)
  }

  // Show loading state while checking auth
  if (isLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-slate-50">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-zava-600 mx-auto"></div>
          <p className="mt-4 text-slate-600">Loading...</p>
        </div>
      </div>
    )
  }

  // Show login if not authenticated
  if (!currentUser) {
    return <LoginPage onLoginComplete={handleLogin} />
  }

  // Get default route based on user role
  const getDefaultRoute = () => {
    switch (currentUser.role) {
      case 'devops': return '/devops'
      case 'executive': return '/executive'
      case 'branch-manager': return '/branch'
      case 'tax-professional': return '/professional'
      default: return '/filer'
    }
  }

  // Render routes based on user role - each persona only sees their routes
  const renderRoutes = () => {
    switch (currentUser.role) {
      case 'tax-filer':
        return (
          <>
            <Route path="/filer" element={<TaxFilerDashboard />} />
            <Route path="/filer/ask" element={<TaxFilerAskQuestion />} />
            <Route path="/filer/returns" element={<TaxFilerMyReturns />} />
            <Route path="/filer/new-return" element={<TaxFilerNewReturn />} />
            <Route path="/filer/edit-return/:returnId" element={<TaxFilerEditReturn />} />
          </>
        )
      case 'tax-professional':
        return (
          <>
            <Route path="/professional" element={<ProfessionalDashboard />} />
            <Route path="/professional/clients" element={<ProfessionalClients />} />
            <Route path="/professional/cases" element={<ProfessionalSimilarCases />} />
            <Route path="/professional/knowledge" element={<ProfessionalKnowledgeBase />} />
          </>
        )
      case 'branch-manager':
        return (
          <>
            <Route path="/branch" element={<BranchManagerDashboard />} />
            <Route path="/branch/team" element={<BranchManagerTeam />} />
            <Route path="/branch/performance" element={<BranchManagerPerformance />} />
          </>
        )
      case 'executive':
        return (
          <>
            <Route path="/executive" element={<ExecutiveDashboard />} />
            <Route path="/executive/analytics" element={<ExecutiveAnalytics />} />
            <Route path="/executive/filing-analytics" element={<ExecutiveFilingAnalytics />} />
          </>
        )
      case 'devops':
        return (
          <>
            <Route path="/devops" element={<DevOpsMetrics />} />
            <Route path="/devops/security" element={<DevOpsSecurityDashboard />} />
          </>
        )
    }
  }

  return (
    <Layout user={currentUser} onLogout={handleLogout}>
      <Routes>
        {renderRoutes()}
        {/* Default redirect to user's home */}
        <Route path="/" element={<Navigate to={getDefaultRoute()} replace />} />
        <Route path="*" element={<Navigate to={getDefaultRoute()} replace />} />
      </Routes>
    </Layout>
  )
}

export default App
