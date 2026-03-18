import { Link, useLocation } from 'react-router-dom'
import { LogOut, Menu, X } from 'lucide-react'
import { useState } from 'react'
import { MockUser } from '../lib/mockUsers'
import { getNavigationForRole, getRoleName, getRoleColor } from '../lib/navigation'

interface LayoutProps {
  children: React.ReactNode
  user: MockUser
  onLogout: () => void
}

export default function Layout({ children, user, onLogout }: LayoutProps) {
  const location = useLocation()
  const [sidebarOpen, setSidebarOpen] = useState(false)
  
  const navigation = getNavigationForRole(user.role)

  return (
    <div className="min-h-screen bg-slate-50">
      {/* Mobile sidebar backdrop */}
      {sidebarOpen && (
        <div 
          className="fixed inset-0 bg-slate-900/50 z-40 lg:hidden"
          onClick={() => setSidebarOpen(false)}
        />
      )}

      {/* Sidebar */}
      <aside className={`
        fixed top-0 left-0 z-50 h-full w-64 bg-white border-r border-slate-200
        transform transition-transform duration-200
        lg:translate-x-0
        ${sidebarOpen ? 'translate-x-0' : '-translate-x-full'}
      `}>
        {/* Logo */}
        <div className="h-16 flex items-center justify-between px-4 border-b border-slate-200">
          <Link to="/" className="flex items-center gap-3">
            <div className="w-9 h-9 bg-zava-600 rounded-lg flex items-center justify-center">
              <span className="text-white font-bold text-lg">Z</span>
            </div>
            <div>
              <span className="text-lg font-bold text-slate-900">Zava Tax</span>
              <p className="text-xs text-slate-500">{user.department}</p>
            </div>
          </Link>
          <button 
            className="lg:hidden p-2 text-slate-400 hover:text-slate-600 hover:bg-slate-100 rounded-md"
            onClick={() => setSidebarOpen(false)}
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Navigation */}
        <nav className="flex-1 px-3 py-4 space-y-6 overflow-y-auto">
          {navigation.map((section) => (
            <div key={section.title}>
              <h3 className="text-xs font-semibold text-slate-400 uppercase tracking-wider mb-2 px-3">
                {section.title}
              </h3>
              <ul className="space-y-1">
                {section.items.map((item) => {
                  const isActive = location.pathname === item.href
                  return (
                    <li key={item.name}>
                      <Link
                        to={item.href}
                        className={`sidebar-link ${isActive ? 'sidebar-link-active' : 'sidebar-link-inactive'}`}
                        onClick={() => setSidebarOpen(false)}
                      >
                        <item.icon className={`w-5 h-5 ${isActive ? 'text-zava-600' : 'text-slate-400'}`} />
                        <span>{item.name}</span>
                      </Link>
                    </li>
                  )
                })}
              </ul>
            </div>
          ))}
        </nav>

        {/* User info */}
        <div className="p-3 border-t border-slate-200">
          <div className="flex items-center gap-3 p-2">
            <div className="w-10 h-10 bg-zava-600 rounded-lg flex items-center justify-center">
              <span className="text-white font-semibold">
                {user.name.charAt(0)}
              </span>
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-slate-900 truncate">
                {user.name}
              </p>
              <p className="text-xs text-slate-500 truncate">
                {user.email}
              </p>
            </div>
            <button
              onClick={onLogout}
              className="p-2 text-slate-400 hover:text-red-500 rounded-md hover:bg-red-50"
              title="Sign out"
            >
              <LogOut className="w-5 h-5" />
            </button>
          </div>
        </div>
      </aside>

      {/* Main content */}
      <div className="lg:pl-64">
        {/* Top bar */}
        <header className="sticky top-0 z-30 h-16 bg-white border-b border-slate-200 flex items-center px-4 lg:px-6">
          <button
            className="lg:hidden p-2 -ml-2 text-slate-500 hover:text-slate-700 hover:bg-slate-100 rounded-md"
            onClick={() => setSidebarOpen(true)}
          >
            <Menu className="w-6 h-6" />
          </button>
          
          <div className="flex-1" />
          
          <div className="flex items-center gap-3">
            {/* Role badge */}
            <div className={`hidden sm:flex items-center gap-2 px-3 py-1.5 rounded-md text-sm font-medium ${getRoleColor(user.role)}`}>
              <div className={`w-2 h-2 rounded-full ${user.role === 'tax-filer' ? 'bg-emerald-500' : user.role === 'tax-professional' ? 'bg-blue-500' : user.role === 'branch-manager' ? 'bg-purple-500' : user.role === 'executive' ? 'bg-amber-500' : 'bg-slate-500'}`} />
              {getRoleName(user.role)}
            </div>
          </div>
        </header>

        {/* Page content */}
        <main className="p-4 lg:p-6">
          {children}
        </main>

        {/* Legal disclaimer footer */}
        <footer className="px-4 lg:px-6 py-3 border-t border-slate-200 bg-slate-50">
          <p className="text-xs text-slate-400 text-center leading-relaxed">
            Demo only — not for production use. Not affiliated with or endorsed by the IRS.
            IRS content is public domain (17 U.S.C. § 105). All customer data is synthetic. Not tax advice.
          </p>
        </footer>
      </div>
    </div>
  )
}