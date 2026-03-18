# Security Architecture

## Overview

This document explains the authentication and authorization architecture for the ZavaTax application. **The current implementation uses a simplified mock authentication system suitable for demos and development only.** This document clearly outlines what's been simplified, why, and how to implement production-grade security.

## Current Demo Implementation

### ⚠️ Security Trade-offs

The demo intentionally bypasses several security best practices to simplify development and demonstration:

| Component | Demo Implementation | Security Impact | Production Required |
|-----------|-------------------|-----------------|-------------------|
| **Authentication** | Mock user selection without passwords | ❌ No identity verification | Azure AD B2C with OAuth 2.0 |
| **User Storage** | Plain text in localStorage | ❌ User selection persists but no secrets stored | JWT tokens in sessionStorage or memory |
| **Token Validation** | None - DAB accepts all requests | ❌ No authorization enforcement | DAB validates Azure AD JWT signatures |
| **CORS** | Allows all origins (`*`) | ❌ Any origin can call API | Restrict to specific domains |
| **Role Mapping** | Hardcoded in mockUsers.ts | ❌ Cannot be managed centrally | Azure AD App Roles or Groups |

### How Demo Authentication Works

1. **User Selection** ([webapp/src/lib/mockUsers.ts](webapp/src/lib/mockUsers.ts))
   - Users select a persona from 5 hardcoded options (tax-filer, tax-professional, branch-manager, executive, devops)
   - Selected user stored in localStorage (key: `zavatax_user`)
   - No password validation, no encryption
   - User IDs simulate Entra Object IDs but are not real

2. **API Calls** ([webapp/src/lib/api.ts](webapp/src/lib/api.ts))
   - `isDevMode = true` bypasses authentication entirely
   - `getAccessToken()` returns `null` in dev mode
   - No `Authorization` header sent to DAB
   - Workload routing headers (`X-Workload-Type`, `X-Replica-Target`) still sent for replica routing

3. **DAB Configuration** ([webapp/dab-config.json](webapp/dab-config.json))
   ```json
   {
     "host": {
       "authentication": {
         "provider": "Simulator"  // ⚠️ Not AzureAD
       },
       "mode": "development"       // ⚠️ Bypasses auth
     }
   }
   ```
   - `provider: "Simulator"` allows unauthenticated requests
   - All entities have `"role": "anonymous"` with `"actions": ["*"]`
   - No JWT validation, no claim checks

### Why These Trade-offs?

- **Demo Simplicity**: Focus on workload routing, read-scale, and application architecture without Azure AD tenant setup
- **Local Development**: No internet connection or Azure subscription required
- **Faster Onboarding**: New developers can run the app in minutes
- **Presentation Focus**: During demos, quickly switch between user personas to show different views

**🚨 Critical**: This implementation is NOT production-ready. Do not deploy to production without implementing the security measures below.

---

## Production Implementation Guide

### Step 1: Azure AD B2C Setup

1. **Create Azure AD B2C Tenant**
   ```bash
   az ad b2c tenant create --name zavatax --tenant-domain zavatax.onmicrosoft.com --location "United States"
   ```

2. **Register Application**
   - Navigate to Azure Portal → Azure AD B2C → App registrations
   - Click "New registration"
   - **Name**: ZavaTax Web App
   - **Supported account types**: Accounts in this organizational directory only (single tenant)
   - **Redirect URI**: `https://yourdomain.com` (SPA)
   - Note the **Application (client) ID** and **Directory (tenant) ID**

3. **Configure App Roles**
   
   In the app registration, add these app roles (Manifest → appRoles):
   ```json
   {
     "appRoles": [
       {
         "allowedMemberTypes": ["User"],
         "description": "Tax filers can submit returns",
         "displayName": "Tax Filer",
         "id": "00000000-0000-0000-0000-000000000001",
         "isEnabled": true,
         "value": "TaxFiler"
       },
       {
         "allowedMemberTypes": ["User"],
         "description": "Tax professionals manage client returns",
         "displayName": "Tax Professional",
         "id": "00000000-0000-0000-0000-000000000002",
         "isEnabled": true,
         "value": "TaxProfessional"
       },
       {
         "allowedMemberTypes": ["User"],
         "description": "Branch managers oversee branch operations",
         "displayName": "Branch Manager",
         "id": "00000000-0000-0000-0000-000000000003",
         "isEnabled": true,
         "value": "BranchManager"
       },
       {
         "allowedMemberTypes": ["User"],
         "description": "Executives view company-wide analytics",
         "displayName": "Executive",
         "id": "00000000-0000-0000-0000-000000000004",
         "isEnabled": true,
         "value": "Executive"
       },
       {
         "allowedMemberTypes": ["User"],
         "description": "DevOps engineers monitor system health",
         "displayName": "DevOps",
         "id": "00000000-0000-0000-0000-000000000005",
         "isEnabled": true,
         "value": "DevOps"
       }
     ]
   }
   ```

4. **Expose API Scope**
   - Navigate to "Expose an API" → "Add a scope"
   - **Scope name**: `access_as_user`
   - **Who can consent**: Admins and users
   - **Admin consent display name**: Access ZavaTax API as the signed-in user
   - **Admin consent description**: Allows the app to access the ZavaTax API on behalf of the signed-in user

5. **Assign Users to Roles**
   - Navigate to Enterprise applications → ZavaTax Web App → Users and groups
   - Add users and assign appropriate roles

### Step 2: Update Frontend Configuration

1. **Environment Variables** (`.env.production`)
   ```bash
   # Azure AD B2C Configuration
   VITE_AZURE_AD_CLIENT_ID=<your-client-id>
   VITE_AZURE_AD_TENANT_ID=<your-tenant-id>
   
   # Disable dev mode
   VITE_DEV_MODE=false
   
   # API endpoint
   VITE_API_URL=https://yourdomain.com/api
   ```

2. **MSAL Configuration** ([webapp/src/lib/auth.ts](webapp/src/lib/auth.ts))
   
   The existing configuration is already production-ready! Just ensure `VITE_DEV_MODE=false`:
   
   ```typescript
   // auth.ts already has:
   export const isDevMode = import.meta.env.VITE_DEV_MODE === 'true'
   
   const msalConfig: Configuration = {
     auth: {
       clientId: import.meta.env.VITE_AZURE_AD_CLIENT_ID,
       authority: `https://login.microsoftonline.com/${import.meta.env.VITE_AZURE_AD_TENANT_ID}`,
       redirectUri: window.location.origin,
     },
     cache: {
       cacheLocation: 'sessionStorage',  // ✅ Secure: cleared on browser close
       storeAuthStateInCookie: false,
     },
   }
   ```

3. **Remove Mock Authentication** ([webapp/src/lib/mockUsers.ts](webapp/src/lib/mockUsers.ts))
   
   In production builds, mock authentication is automatically bypassed:
   ```typescript
   // api.ts → getAccessToken() already checks isDevMode
   if (isDevMode) {
     return null  // Bypass auth in dev mode
   }
   
   // In production (VITE_DEV_MODE=false), acquires real tokens:
   const response = await msalInstance.acquireTokenSilent({
     scopes: apiScopes.dabApi,
     account: accounts[0]
   })
   return response.accessToken
   ```

### Step 3: Configure DAB for Production

1. **Update dab-config.json**
   
   Replace the authentication section:
   
   ```json
   {
     "runtime": {
       "host": {
         "cors": {
           "origins": ["https://yourdomain.com"],  // ✅ Specific origin
           "allow-credentials": true               // ✅ Required for cookies
         },
         "authentication": {
           "provider": "AzureAD",                   // ✅ Changed from "Simulator"
           "jwt": {
             "audience": "api://<your-client-id>", // ✅ Validate audience
             "issuer": "https://login.microsoftonline.com/<tenant-id>/v2.0"
           }
         },
         "mode": "production"                       // ✅ Changed from "development"
       }
     }
   }
   ```

2. **Update Entity Permissions**
   
   Replace `"anonymous"` role with proper claims-based authorization:
   
   ```json
   {
     "entities": {
       "TaxReturn": {
         "permissions": [
           {
             "role": "TaxFiler",
             "actions": [
               {
                 "action": "read",
                 "policy": {
                   "database": "@claims.oid = @item.CustomerId"  // Users see only their returns
                 }
               },
               {
                 "action": "create",
                 "policy": {
                   "database": "@claims.oid = @item.CustomerId"
                 }
               }
             ]
           },
           {
             "role": "TaxProfessional",
             "actions": [
               {
                 "action": "*",
                 "policy": {
                   "database": "@claims.professional_id = @item.ProfessionalId"  // Pros see client returns
                 }
               }
             ]
           },
           {
             "role": "Executive",
             "actions": ["read"]  // Full read access for analytics
           },
           {
             "role": "DevOps",
             "actions": ["read"]  // Monitoring access
           }
         ]
       }
     }
   }
   ```

3. **Environment Variables**
   
   ```bash
   # DAB will automatically validate JWT signatures using Azure AD public keys
   DATABASE_CONNECTION_STRING="Server=tcp:<your-server>.database.windows.net,1433;Database=zavatax;Authentication=Active Directory Default;"
   ```

### Step 4: Token Security Best Practices

#### ✅ Recommended: SessionStorage (Already Configured)

The app already uses `sessionStorage` for MSAL tokens:

```typescript
cache: {
  cacheLocation: 'sessionStorage',  // Cleared on browser/tab close
}
```

**Pros**:
- Tokens cleared when user closes browser/tab
- Protected from XSS across tabs
- Built-in MSAL support

**Cons**:
- Tokens lost on page refresh (MSAL handles re-authentication automatically)
- Not shared across tabs (intentional security feature)

#### Alternative: In-Memory Storage (Most Secure)

For maximum security, store tokens only in memory:

```typescript
cache: {
  cacheLocation: 'memory',  // Never persisted to disk
}
```

**Pros**:
- Most secure - tokens never touch disk or localStorage
- Cleared on page refresh

**Cons**:
- User must re-authenticate on every page refresh
- Poor UX for SPAs

#### ❌ Not Recommended: LocalStorage

```typescript
cache: {
  cacheLocation: 'localStorage',  // ⚠️ Persists across browser sessions
}
```

**Cons**:
- Tokens persist indefinitely until explicitly cleared
- More vulnerable to XSS attacks
- Violates OAuth 2.0 best practices for browser-based apps

### Step 5: Enable SQL Row-Level Security (Optional)

For defense-in-depth, implement SQL RLS alongside DAB policies:

```sql
-- Create security function
CREATE FUNCTION dbo.fn_securitypredicate(@CustomerId uniqueidentifier)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS fn_securitypredicate_result
WHERE @CustomerId = CAST(SESSION_CONTEXT(N'user_id') AS uniqueidentifier)
GO

-- Apply to TaxReturns table
CREATE SECURITY POLICY CustomerFilter
ADD FILTER PREDICATE dbo.fn_securitypredicate(CustomerId) ON dbo.TaxReturns,
ADD BLOCK PREDICATE dbo.fn_securitypredicate(CustomerId) ON dbo.TaxReturns AFTER INSERT
WITH (STATE = ON)
GO
```

---

## Security Checklist

Before deploying to production:

- [ ] **Azure AD B2C tenant created and configured**
- [ ] **App roles defined and assigned to users**
- [ ] **`VITE_DEV_MODE=false` in production environment**
- [ ] **CORS restricted to specific domain(s)**
- [ ] **DAB authentication provider changed to `AzureAD`**
- [ ] **DAB mode changed to `production`**
- [ ] **Entity permissions updated from `anonymous` to role-based**
- [ ] **Database policies enforce row-level security**
- [ ] **Tokens stored in sessionStorage or memory (not localStorage)**
- [ ] **JWT audience and issuer validation enabled**
- [ ] **API scopes properly configured (`api://<client-id>/access_as_user`)**
- [ ] **All mock authentication code bypassed when `isDevMode=false`**

---

## Token Flow Diagram

### Production Authentication Flow

```
┌─────────┐                                    ┌──────────┐
│ Browser │                                    │ Azure AD │
└────┬────┘                                    └────┬─────┘
     │                                              │
     │ 1. User clicks "Sign In"                     │
     ├──────────────────────────────────────────────>
     │    Redirect to login.microsoftonline.com    │
     │                                              │
     │ 2. User authenticates (username/password)    │
     │    Azure AD validates credentials            │
     │                                              │
     │ 3. Azure AD returns authorization code       │
     <──────────────────────────────────────────────┤
     │    (PKCE flow for SPAs)                      │
     │                                              │
     │ 4. MSAL exchanges code for tokens            │
     ├──────────────────────────────────────────────>
     │                                              │
     │ 5. JWT ID token + Access token               │
     <──────────────────────────────────────────────┤
     │    {                                         │
     │      "oid": "user-object-id",                │
     │      "roles": ["TaxProfessional"],           │
     │      "aud": "api://client-id",               │
     │      "iss": "https://sts.windows.net/..."    │
     │    }                                         │
     │                                              │
     │ 6. Store token in sessionStorage             │
     │    (managed by MSAL)                         │
     │                                              │
     │                                         ┌────▼────┐
     │ 7. API request with Bearer token        │   DAB   │
     ├─────────────────────────────────────────>         │
     │    Authorization: Bearer <jwt>          │         │
     │    X-Workload-Type: transactional       │         │
     │                                         │         │
     │ 8. DAB validates JWT signature          │         │
     │    - Fetches Azure AD public keys       │         │
     │    - Validates issuer, audience, exp    │         │
     │    - Extracts claims (oid, roles)       │         │
     │                                         │         │
     │                                         │    ┌────▼────┐
     │ 9. DAB applies authorization policies   │    │   SQL   │
     │    - Checks role (TaxProfessional)      ├────>         │
     │    - Applies @claims.oid filter         │    │         │
     │                                         │    └─────────┘
     │                                         │         │
     │ 10. Return filtered data                │         │
     <─────────────────────────────────────────┤         │
     │                                         └─────────┘
```

---

## Common Questions

### Q: Why not use HttpOnly cookies instead of sessionStorage?

**A**: HttpOnly cookies require a backend to set them. Since we're using DAB (which auto-generates APIs from the database), we don't have a custom backend layer to issue cookies. MSAL's sessionStorage approach is the recommended pattern for SPAs with stateless APIs.

### Q: How do we map Azure AD users to database entities (customers, professionals, branches)?

**A**: Two approaches:

1. **Custom Claims (Recommended)**: Add custom claims to the JWT during token issuance:
   ```json
   {
     "oid": "user-object-id",
     "roles": ["TaxProfessional"],
     "professional_id": "550e8400-e29b-41d4-a716-446655440003"
   }
   ```

2. **Database Mapping Table**: Store mapping in database:
   ```sql
   CREATE TABLE UserMappings (
     EntraObjectId uniqueidentifier PRIMARY KEY,
     CustomerId uniqueidentifier,
     ProfessionalId uniqueidentifier,
     BranchId int
   )
   ```
   DAB policies can join this table: `@claims.oid IN (SELECT EntraObjectId FROM UserMappings WHERE CustomerId = @item.CustomerId)`

### Q: What about refresh tokens?

**A**: MSAL automatically handles token refresh. Access tokens typically expire after 1 hour. MSAL will:
1. Try silent refresh using refresh token
2. If refresh token expired, prompt user to re-authenticate
3. Cache tokens to minimize network requests

### Q: Can we test production authentication locally?

**A**: Yes! Set environment variables:
```bash
VITE_DEV_MODE=false
VITE_AZURE_AD_CLIENT_ID=<your-dev-app-id>
VITE_AZURE_AD_TENANT_ID=<your-tenant-id>
```

Then run DAB with Azure AD authentication:
```bash
dab start --config dab-config.production.json
```

---

## Additional Resources

- [MSAL.js Documentation](https://github.com/AzureAD/microsoft-authentication-library-for-js/tree/dev/lib/msal-browser)
- [Azure AD B2C Documentation](https://learn.microsoft.com/azure/active-directory-b2c/)
- [Data API Builder Authentication](https://learn.microsoft.com/azure/data-api-builder/authentication-azure-ad)
- [OAuth 2.0 for Browser-Based Apps (RFC)](https://datatracker.ietf.org/doc/html/draft-ietf-oauth-browser-based-apps)
- [PKCE Flow (RFC 7636)](https://datatracker.ietf.org/doc/html/rfc7636)

---

**Last Updated**: January 2025
