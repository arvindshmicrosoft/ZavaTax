import { useState } from 'react'
import { Calculator, Shield, Clock, MapPin, User, Briefcase, Building2, BarChart3, Settings } from 'lucide-react'
import { mockUsers, MockUser, setCurrentUser, getRoleDisplayInfo } from '../lib/mockUsers'
import { UserRole } from '../lib/auth'

interface LoginPageProps {
  onLoginComplete: (user: MockUser) => void
}

export default function LoginPage({ onLoginComplete }: LoginPageProps) {
  const [selectedUser, setSelectedUser] = useState<MockUser | null>(null)
  const [showUserSelect, setShowUserSelect] = useState(false)

  const getRoleIcon = (role: UserRole) => {
    switch (role) {
      case 'tax-filer': return User
      case 'tax-professional': return Briefcase
      case 'branch-manager': return Building2
      case 'executive': return BarChart3
      case 'devops': return Settings
    }
  }

  const handleMicrosoftLogin = () => {
    // Simulate Microsoft login - show user selection for demo
    setShowUserSelect(true)
  }

  const handleUserSelect = (user: MockUser) => {
    setSelectedUser(user)
  }

  const handleConfirmLogin = () => {
    if (selectedUser) {
      setCurrentUser(selectedUser)
      onLoginComplete(selectedUser)
    }
  }

  return (
    <div className="min-h-screen bg-zava-700 flex flex-col">
      {/* Header */}
      <header className="p-6">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 bg-white rounded-lg flex items-center justify-center">
            <span className="text-zava-700 font-bold text-xl">Z</span>
          </div>
          <div>
            <span className="text-xl font-bold text-white">Zava Tax</span>
            <p className="text-zava-200 text-sm">Tax Preparation Services</p>
          </div>
        </div>
      </header>

      {/* Main content */}
      <main className="flex-1 flex items-center justify-center p-6">
        <div className="max-w-4xl w-full grid lg:grid-cols-2 gap-12 items-center">
          {/* Left side - Info */}
          <div className="hidden lg:block space-y-6">
            <div className="space-y-4">
              <h1 className="text-4xl font-bold text-white leading-tight">
                Professional Tax Preparation Made Simple
              </h1>
              <p className="text-lg text-zava-100 leading-relaxed">
                Get expert help with your tax filing. Our certified professionals 
                ensure accuracy and maximize your refund.
              </p>
            </div>

            <div className="space-y-3">
              {[
                { icon: Shield, label: 'Secure & Confidential', desc: 'Your data is protected' },
                { icon: Clock, label: 'Fast Processing', desc: 'Quick turnaround times' },
                { icon: MapPin, label: '500+ Locations', desc: 'Offices nationwide' },
                { icon: Calculator, label: 'Expert Review', desc: 'CPA verified returns' },
              ].map((item) => (
                <div key={item.label} className="flex items-start gap-3 text-white">
                  <div className="w-10 h-10 bg-white/10 rounded-lg flex items-center justify-center flex-shrink-0">
                    <item.icon className="w-5 h-5 text-zava-200" />
                  </div>
                  <div>
                    <p className="font-medium">{item.label}</p>
                    <p className="text-sm text-zava-200">{item.desc}</p>
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Right side - Login card */}
          <div>
            <div className="bg-white rounded-lg shadow-xl p-8">
              {!showUserSelect ? (
                <>
                  <div className="text-center mb-8">
                    <div className="w-14 h-14 bg-zava-600 rounded-lg flex items-center justify-center mx-auto mb-4">
                      <span className="text-white font-bold text-2xl">Z</span>
                    </div>
                    <h2 className="text-2xl font-bold text-slate-900 mb-2">
                      Welcome Back
                    </h2>
                    <p className="text-slate-500">
                      Sign in to access your account
                    </p>
                  </div>

                  <button
                    onClick={handleMicrosoftLogin}
                    className="w-full bg-zava-600 text-white py-3 px-4 rounded-md font-medium
                      hover:bg-zava-700 transition-colors duration-150 
                      flex items-center justify-center gap-3"
                  >
                    <svg className="w-5 h-5" viewBox="0 0 21 21" fill="none">
                      <rect width="9" height="9" fill="currentColor" fillOpacity="0.9"/>
                      <rect x="11" width="9" height="9" fill="currentColor"/>
                      <rect y="11" width="9" height="9" fill="currentColor"/>
                      <rect x="11" y="11" width="9" height="9" fill="currentColor" fillOpacity="0.9"/>
                    </svg>
                    Sign in with Microsoft Entra ID
                  </button>

                  <p className="mt-6 text-center text-sm text-slate-500">
                    By signing in, you agree to our{' '}
                    <a href="#" className="text-zava-600 hover:underline">Terms</a>
                    {' '}and{' '}
                    <a href="#" className="text-zava-600 hover:underline">Privacy Policy</a>
                  </p>
                </>
              ) : (
                <>
                  <div className="text-center mb-6">
                    <h2 className="text-xl font-bold text-slate-900 mb-2">
                      Select Demo Account
                    </h2>
                    <p className="text-sm text-slate-500">
                      Choose a persona to experience the application
                    </p>
                  </div>

                  <div className="space-y-2 max-h-80 overflow-y-auto">
                    {mockUsers.map((user) => {
                      const RoleIcon = getRoleIcon(user.role)
                      const roleInfo = getRoleDisplayInfo(user.role)
                      const isSelected = selectedUser?.id === user.id
                      
                      return (
                        <button
                          key={user.id}
                          onClick={() => handleUserSelect(user)}
                          className={`w-full p-4 rounded-lg border-2 transition-all text-left
                            ${isSelected 
                              ? 'border-zava-600 bg-zava-50' 
                              : 'border-slate-200 hover:border-slate-300 hover:bg-slate-50'
                            }`}
                        >
                          <div className="flex items-center gap-3">
                            <div className={`w-10 h-10 rounded-lg flex items-center justify-center ${roleInfo.bgColor}`}>
                              <RoleIcon className={`w-5 h-5 ${roleInfo.color}`} />
                            </div>
                            <div className="flex-1 min-w-0">
                              <p className="font-medium text-slate-900">{user.name}</p>
                              <p className="text-sm text-slate-500">{user.title}</p>
                            </div>
                            {isSelected && (
                              <div className="w-5 h-5 bg-zava-600 rounded-full flex items-center justify-center">
                                <svg className="w-3 h-3 text-white" fill="currentColor" viewBox="0 0 20 20">
                                  <path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" />
                                </svg>
                              </div>
                            )}
                          </div>
                          <p className="mt-2 text-xs text-slate-400 truncate">
                            {user.email}
                          </p>
                        </button>
                      )
                    })}
                  </div>

                  <div className="mt-6 flex gap-3">
                    <button
                      onClick={() => {
                        setShowUserSelect(false)
                        setSelectedUser(null)
                      }}
                      className="flex-1 py-2.5 px-4 rounded-md border border-slate-300 text-slate-600 font-medium hover:bg-slate-50 transition-colors"
                    >
                      Back
                    </button>
                    <button
                      onClick={handleConfirmLogin}
                      disabled={!selectedUser}
                      className={`flex-1 py-2.5 px-4 rounded-md font-medium transition-colors
                        ${selectedUser 
                          ? 'bg-zava-600 text-white hover:bg-zava-700' 
                          : 'bg-slate-200 text-slate-400 cursor-not-allowed'
                        }`}
                    >
                      Sign In
                    </button>
                  </div>

                  <p className="mt-4 text-center text-xs text-slate-400">
                    Demo mode: Simulating Microsoft Entra ID authentication
                  </p>
                </>
              )}
            </div>

            {/* Mobile info */}
            <div className="lg:hidden mt-6 text-center text-white">
              <p className="text-zava-200 text-sm">
                Professional tax preparation with over 500 locations nationwide
              </p>
            </div>
          </div>
        </div>
      </main>

      {/* Footer */}
      <footer className="p-6">
        <div className="flex flex-col items-center gap-3 text-zava-200 text-sm">
          <div className="flex items-center gap-6">
            <a href="#" className="hover:text-white transition-colors">Privacy</a>
            <a href="#" className="hover:text-white transition-colors">Terms</a>
            <a href="#" className="hover:text-white transition-colors">Support</a>
          </div>
          <p className="text-xs text-zava-300/70 text-center max-w-2xl leading-relaxed">
            Demo only — not for production use. Not affiliated with or endorsed by the IRS.
            IRS content is public domain (17 U.S.C. § 105). All customer data is synthetic. Not tax advice.
          </p>
        </div>
      </footer>
    </div>
  )
}
