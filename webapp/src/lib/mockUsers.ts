/**
 * ⚠️ DEMO AUTHENTICATION ONLY - NOT PRODUCTION READY ⚠️
 * 
 * This file implements a simplified mock authentication system for demonstration
 * and local development purposes. It intentionally bypasses several security
 * best practices to simplify the demo experience.
 * 
 * SECURITY TRADE-OFFS:
 * ❌ No password validation - users selected by email only
 * ❌ No token-based authentication - no JWTs, no OAuth 2.0 flow
 * ❌ No identity verification - any user can impersonate any persona
 * ❌ Plain text storage - user selection stored in localStorage (no encryption)
 * ❌ No session expiration - selection persists indefinitely
 * 
 * WHY THESE TRADE-OFFS:
 * ✅ No Azure AD tenant required - works offline
 * ✅ Instant persona switching - great for demos showing different user views
 * ✅ Zero configuration - works immediately after git clone
 * 
 * FOR PRODUCTION:
 * See SECURITY.md for complete implementation guide using:
 * - Azure AD B2C with OAuth 2.0 + OIDC
 * - JWT tokens with signature validation
 * - Role-based access control (RBAC) with Azure AD App Roles
 * - DAB authentication provider set to "AzureAD"
 * 
 * This mock authentication is automatically bypassed when VITE_DEV_MODE=false.
 */

import { UserRole } from './auth'

export interface MockUser {
  id: string           // Simulated Entra Object ID
  name: string
  email: string
  role: UserRole
  title: string
  avatar?: string
  department: string
  customerId?: number  // For tax-filer persona
  professionalId?: number  // For tax-professional persona
  branchId?: number    // For branch-manager persona
}

export const mockUsers: MockUser[] = [
  {
    id: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    name: 'Sarah Johnson',
    email: 'sarah.johnson@outlook.com',
    role: 'tax-filer',
    title: 'Individual Tax Filer',
    department: 'Customer',
    customerId: 1,
  },
  {
    id: 'b2c3d4e5-f6a7-8901-bcde-f12345678901',
    name: 'Michael Chen',
    email: 'mchen@zavatax.com',
    role: 'tax-professional',
    title: 'Senior Tax Preparer',
    department: 'Tax Services',
    professionalId: 1,
    branchId: 1,
  },
  {
    id: 'c3d4e5f6-a7b8-9012-cdef-123456789012',
    name: 'Amanda Rodriguez',
    email: 'arodriguez@zavatax.com',
    role: 'branch-manager',
    title: 'Branch Manager',
    department: 'Operations',
    branchId: 1,
  },
  {
    id: 'd4e5f6a7-b8c9-0123-defa-234567890123',
    name: 'Robert Williams',
    email: 'rwilliams@zavatax.com',
    role: 'executive',
    title: 'Chief Operations Officer',
    department: 'Executive Leadership',
  },
  {
    id: 'e5f6a7b8-c9d0-1234-efab-345678901234',
    name: 'Jennifer Park',
    email: 'jpark@zavatax.com',
    role: 'devops',
    title: 'DevOps Engineer',
    department: 'Technology',
  },
]

// Auth storage keys
const AUTH_USER_KEY = 'zavatax_user'

export function getCurrentUser(): MockUser | null {
  try {
    const stored = localStorage.getItem(AUTH_USER_KEY)
    if (stored) {
      return JSON.parse(stored)
    }
  } catch (e) {
    console.error('Failed to parse stored user:', e)
  }
  return null
}

export function setCurrentUser(user: MockUser): void {
  localStorage.setItem(AUTH_USER_KEY, JSON.stringify(user))
}

export function clearCurrentUser(): void {
  localStorage.removeItem(AUTH_USER_KEY)
}

export function getUserByRole(role: UserRole): MockUser | undefined {
  return mockUsers.find(u => u.role === role)
}

export function getRoleDisplayInfo(role: UserRole): { color: string; bgColor: string; icon: string } {
  switch (role) {
    case 'tax-filer':
      return { color: 'text-emerald-700', bgColor: 'bg-emerald-100', icon: '👤' }
    case 'tax-professional':
      return { color: 'text-blue-700', bgColor: 'bg-blue-100', icon: '📋' }
    case 'branch-manager':
      return { color: 'text-purple-700', bgColor: 'bg-purple-100', icon: '🏢' }
    case 'executive':
      return { color: 'text-amber-700', bgColor: 'bg-amber-100', icon: '📊' }
    case 'devops':
      return { color: 'text-slate-700', bgColor: 'bg-slate-100', icon: '⚙️' }
  }
}
