import { 
  Calculator, 
  Users, 
  BarChart3, 
  MessageSquare,
  FileText,
  Search,
  BookOpen,
  TrendingUp,
  Activity,
  Building2,
  Shield
} from 'lucide-react'
import { UserRole } from '../lib/auth'

export interface NavItem {
  name: string
  href: string
  icon: React.ComponentType<{ className?: string }>
}

export interface NavSection {
  title: string
  items: NavItem[]
}

export function getNavigationForRole(role: UserRole): NavSection[] {
  switch (role) {
    case 'tax-filer':
      return [
        {
          title: 'My Tax Center',
          items: [
            { name: 'Dashboard', href: '/filer', icon: Calculator },
            { name: 'Ask a Question', href: '/filer/ask', icon: MessageSquare },
            { name: 'My Returns', href: '/filer/returns', icon: FileText },
          ],
        },
      ]
    
    case 'tax-professional':
      return [
        {
          title: 'Client Services',
          items: [
            { name: 'Dashboard', href: '/professional', icon: Calculator },
            { name: 'My Clients', href: '/professional/clients', icon: Users },
            { name: 'Similar Cases', href: '/professional/cases', icon: Search },
            { name: 'Knowledge Base', href: '/professional/knowledge', icon: BookOpen },
          ],
        },
      ]
    
    case 'branch-manager':
      return [
        {
          title: 'Branch Operations',
          items: [
            { name: 'Dashboard', href: '/branch', icon: Building2 },
            { name: 'My Team', href: '/branch/team', icon: Users },
            { name: 'Performance', href: '/branch/performance', icon: TrendingUp },
          ],
        },
      ]
    
    case 'executive':
      return [
        {
          title: 'Executive View',
          items: [
            { name: 'Dashboard', href: '/executive', icon: BarChart3 },
            { name: 'Analytics', href: '/executive/analytics', icon: TrendingUp },
            { name: 'Filing Analytics', href: '/executive/filing-analytics', icon: FileText },
          ],
        },
      ]
    
    case 'devops':
      return [
        {
          title: 'System Operations',
          items: [
            { name: 'Dashboard', href: '/devops', icon: Activity },
            { name: 'Security', href: '/devops/security', icon: Shield },
          ],
        },
      ]
    
    default:
      return []
  }
}

export function getRoleName(role: UserRole): string {
  switch (role) {
    case 'tax-filer': return 'Tax Filer'
    case 'tax-professional': return 'Tax Professional'
    case 'branch-manager': return 'Branch Manager'
    case 'executive': return 'Executive'
    case 'devops': return 'DevOps'
    default: return 'User'
  }
}

export function getRoleColor(role: UserRole): string {
  switch (role) {
    case 'tax-filer': return 'bg-green-100 text-green-800'
    case 'tax-professional': return 'bg-blue-100 text-blue-800'
    case 'branch-manager': return 'bg-purple-100 text-purple-800'
    case 'executive': return 'bg-amber-100 text-amber-800'
    case 'devops': return 'bg-red-100 text-red-800'
    default: return 'bg-slate-100 text-slate-800'
  }
}
