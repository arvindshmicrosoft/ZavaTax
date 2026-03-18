/**
 * Authentication Configuration
 * 
 * This file configures MSAL (Microsoft Authentication Library) for Azure AD authentication.
 * The configuration supports both development and production modes:
 * 
 * DEVELOPMENT MODE (VITE_DEV_MODE=true):
 * - Bypasses Azure AD authentication entirely
 * - Uses mock users from mockUsers.ts
 * - No JWT tokens generated or validated
 * - getAccessToken() returns null
 * - See mockUsers.ts for demo authentication implementation
 * 
 * PRODUCTION MODE (VITE_DEV_MODE=false):
 * - Full OAuth 2.0 + OIDC authentication with Azure AD B2C
 * - JWT tokens stored in sessionStorage (cleared on browser close)
 * - Token refresh handled automatically by MSAL
 * - Role-based access control using Azure AD App Roles
 * - DAB validates JWT signatures using Azure AD public keys
 * 
 * SECURITY NOTES:
 * ✅ sessionStorage used for token cache (more secure than localStorage)
 * ✅ PKCE flow for SPAs (Authorization Code Flow with Proof Key)
 * ✅ Tokens auto-refresh before expiration
 * ✅ Redirect URI validated by Azure AD
 * 
 * For complete production setup guide, see SECURITY.md
 */

import { PublicClientApplication, Configuration, LogLevel } from '@azure/msal-browser'

// Check if we're in dev mode (no Azure AD required)
export const isDevMode = import.meta.env.VITE_DEV_MODE === 'true'

// MSAL configuration - update these values for your Azure AD app registration
const msalConfig: Configuration = {
  auth: {
    clientId: import.meta.env.VITE_AZURE_AD_CLIENT_ID || 'dev-client-id',
    authority: `https://login.microsoftonline.com/${import.meta.env.VITE_AZURE_AD_TENANT_ID || 'common'}`,
    redirectUri: window.location.origin,
    postLogoutRedirectUri: window.location.origin,
  },
  cache: {
    cacheLocation: 'sessionStorage',
    storeAuthStateInCookie: false,
  },
  system: {
    loggerOptions: {
      loggerCallback: (level, message, containsPii) => {
        if (containsPii) return
        switch (level) {
          case LogLevel.Error:
            console.error(message)
            break
          case LogLevel.Warning:
            console.warn(message)
            break
          case LogLevel.Info:
            console.info(message)
            break
          case LogLevel.Verbose:
            console.debug(message)
            break
        }
      },
      logLevel: LogLevel.Warning,
    },
  },
}

export const msalInstance = new PublicClientApplication(msalConfig)

// Scopes for API access
export const apiScopes = {
  dabApi: isDevMode ? [] : [`api://${import.meta.env.VITE_AZURE_AD_CLIENT_ID}/access_as_user`],
}

// Login request
export const loginRequest = {
  scopes: isDevMode ? ['openid', 'profile', 'email'] : ['openid', 'profile', 'email', ...apiScopes.dabApi],
}

// User roles based on Azure AD groups/app roles
export type UserRole = 'tax-filer' | 'tax-professional' | 'branch-manager' | 'executive' | 'devops'

export interface UserInfo {
  name: string
  email: string
  roles: UserRole[]
  primaryRole: UserRole
}

// Dev mode mock account
export const devMockAccount = {
  name: 'Dev User',
  username: 'dev@zavatax.local',
  idTokenClaims: {
    roles: ['DevOps', 'Executive', 'BranchManager', 'TaxProfessional', 'TaxFiler']
  }
}

export function parseUserRoles(account: any): UserRole[] {
  const roles: UserRole[] = []
  
  // Check for app roles in the ID token claims
  const appRoles = account?.idTokenClaims?.roles || []
  
  if (appRoles.includes('DevOps')) roles.push('devops')
  if (appRoles.includes('Executive')) roles.push('executive')
  if (appRoles.includes('BranchManager')) roles.push('branch-manager')
  if (appRoles.includes('TaxProfessional')) roles.push('tax-professional')
  if (appRoles.includes('TaxFiler') || roles.length === 0) roles.push('tax-filer')
  
  return roles
}

export function getPrimaryRole(roles: UserRole[]): UserRole {
  // Priority: devops > executive > branch-manager > tax-professional > tax-filer
  const priority: UserRole[] = ['devops', 'executive', 'branch-manager', 'tax-professional', 'tax-filer']
  for (const role of priority) {
    if (roles.includes(role)) return role
  }
  return 'tax-filer'
}
