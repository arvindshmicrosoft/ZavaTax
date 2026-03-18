/**
 * Workload Routing Service for Azure SQL DB Hyperscale Read-Scale
 * 
 * This module implements CQRS-style routing where:
 * - Read/Write operations go to the PRIMARY database
 * - Read-only operations for Tax Filers and Tax Professionals use ApplicationIntent=ReadOnly
 * - Management analytics queries target a Hyperscale Named Replica
 * 
 * Connection String Attributes:
 * - Primary (R/W): No special attributes
 * - Read-Only Replica: ApplicationIntent=ReadOnly
 * - Named Replica: Server=<named-replica-fqdn>;ApplicationIntent=ReadOnly
 */

/**
 * Workload types that determine which database replica to use
 */
export enum WorkloadType {
  /** Transactional read/write - uses primary */
  Transactional = 'transactional',
  
  /** Read-only queries from tax filers viewing returns */
  TaxFilerReadOnly = 'tax-filer-readonly',
  
  /** Read-only queries from tax professionals viewing client data */
  TaxProfessionalReadOnly = 'tax-professional-readonly',
  
  /** RAG/Vector search queries - uses read replica */
  VectorSearch = 'vector-search',
  
  /** AI Assistant queries - uses read replica */
  AIAssistant = 'ai-assistant',
  
  /** Management analytics - uses named replica */
  Analytics = 'analytics',
  
  /** Executive dashboards - uses named replica */
  ExecutiveDashboard = 'executive-dashboard',
  
  /** DevOps/monitoring queries - uses named replica */
  DevOps = 'devops',
}

/**
 * Replica targets for Hyperscale read-scale
 */
export enum ReplicaTarget {
  /** Primary database - all writes and transactional reads */
  Primary = 'primary',
  
  /** Read-only replica using ApplicationIntent=ReadOnly */
  ReadOnlyReplica = 'readonly-replica',
  
  /** Named replica for management/analytics workloads */
  NamedReplica = 'named-replica',
}

/**
 * Maps workload types to their appropriate replica target
 */
export const WORKLOAD_TO_REPLICA: Record<WorkloadType, ReplicaTarget> = {
  [WorkloadType.Transactional]: ReplicaTarget.Primary,
  [WorkloadType.TaxFilerReadOnly]: ReplicaTarget.ReadOnlyReplica,
  [WorkloadType.TaxProfessionalReadOnly]: ReplicaTarget.ReadOnlyReplica,
  [WorkloadType.VectorSearch]: ReplicaTarget.ReadOnlyReplica,
  [WorkloadType.AIAssistant]: ReplicaTarget.ReadOnlyReplica,
  [WorkloadType.Analytics]: ReplicaTarget.NamedReplica,
  [WorkloadType.ExecutiveDashboard]: ReplicaTarget.NamedReplica,
  [WorkloadType.DevOps]: ReplicaTarget.NamedReplica,
}

/**
 * HTTP header used to communicate workload intent to the backend
 * The backend/DAB layer uses this to route to the appropriate connection
 */
export const WORKLOAD_HEADER = 'X-Workload-Type'
export const REPLICA_HEADER = 'X-Replica-Target'

/**
 * Determines the appropriate workload type based on user role and operation
 */
export function getWorkloadType(
  userRole: string,
  operation: 'read' | 'write',
  endpoint?: string
): WorkloadType {
  // All writes go to primary
  if (operation === 'write') {
    return WorkloadType.Transactional
  }
  
  // Route based on user role for reads
  switch (userRole.toLowerCase()) {
    case 'tax-filer':
      // Tax filers viewing their returns use read replica
      return WorkloadType.TaxFilerReadOnly
      
    case 'tax-professional':
      // Tax professionals have mixed workloads
      if (endpoint?.includes('ai-') || endpoint?.includes('search-')) {
        return WorkloadType.AIAssistant
      }
      return WorkloadType.TaxProfessionalReadOnly
      
    case 'branch-manager':
      // Branch managers use analytics for reporting
      if (endpoint?.includes('analytics') || endpoint?.includes('dashboard')) {
        return WorkloadType.Analytics
      }
      return WorkloadType.TaxProfessionalReadOnly
      
    case 'executive':
      // Executives use named replica for heavy analytics
      return WorkloadType.ExecutiveDashboard
      
    case 'devops':
      // DevOps uses named replica for monitoring
      return WorkloadType.DevOps
      
    default:
      // Default to primary for safety
      return WorkloadType.Transactional
  }
}

/**
 * Gets the replica target for a given workload type
 */
export function getReplicaTarget(workloadType: WorkloadType): ReplicaTarget {
  return WORKLOAD_TO_REPLICA[workloadType]
}

/**
 * Generates the appropriate headers for a request based on workload routing
 */
export function getWorkloadHeaders(
  userRole: string,
  operation: 'read' | 'write',
  endpoint?: string
): Record<string, string> {
  const workloadType = getWorkloadType(userRole, operation, endpoint)
  const replicaTarget = getReplicaTarget(workloadType)
  
  return {
    [WORKLOAD_HEADER]: workloadType,
    [REPLICA_HEADER]: replicaTarget,
  }
}

/**
 * Tracks workload routing decisions for observability
 */
export interface WorkloadRoutingDecision {
  timestamp: Date
  userRole: string
  operation: 'read' | 'write'
  endpoint: string
  workloadType: WorkloadType
  replicaTarget: ReplicaTarget
}

/**
 * In-memory store for recent routing decisions (for demo purposes)
 * In production, this would be sent to Application Insights
 */
class WorkloadRoutingTracker {
  private decisions: WorkloadRoutingDecision[] = []
  private maxDecisions = 100
  
  track(
    userRole: string,
    operation: 'read' | 'write',
    endpoint: string
  ): WorkloadRoutingDecision {
    const workloadType = getWorkloadType(userRole, operation, endpoint)
    const decision: WorkloadRoutingDecision = {
      timestamp: new Date(),
      userRole,
      operation,
      endpoint,
      workloadType,
      replicaTarget: getReplicaTarget(workloadType),
    }
    
    this.decisions.unshift(decision)
    if (this.decisions.length > this.maxDecisions) {
      this.decisions.pop()
    }
    
    return decision
  }
  
  getRecentDecisions(count = 20): WorkloadRoutingDecision[] {
    return this.decisions.slice(0, count)
  }
  
  getStats(): {
    total: number
    byReplica: Record<ReplicaTarget, number>
    byWorkload: Record<WorkloadType, number>
  } {
    const byReplica: Record<ReplicaTarget, number> = {
      [ReplicaTarget.Primary]: 0,
      [ReplicaTarget.ReadOnlyReplica]: 0,
      [ReplicaTarget.NamedReplica]: 0,
    }
    
    const byWorkload: Record<WorkloadType, number> = {} as Record<WorkloadType, number>
    
    for (const decision of this.decisions) {
      byReplica[decision.replicaTarget]++
      byWorkload[decision.workloadType] = (byWorkload[decision.workloadType] || 0) + 1
    }
    
    return {
      total: this.decisions.length,
      byReplica,
      byWorkload,
    }
  }
  
  clear(): void {
    this.decisions = []
  }
}

// Singleton tracker instance
export const workloadTracker = new WorkloadRoutingTracker()

/**
 * Human-readable descriptions for demo UI
 */
export const REPLICA_DESCRIPTIONS: Record<ReplicaTarget, string> = {
  [ReplicaTarget.Primary]: 'Primary Database (Read/Write)',
  [ReplicaTarget.ReadOnlyReplica]: 'Read-Only Replica (ApplicationIntent=ReadOnly)',
  [ReplicaTarget.NamedReplica]: 'Named Replica (Management Analytics)',
}

export const WORKLOAD_DESCRIPTIONS: Record<WorkloadType, string> = {
  [WorkloadType.Transactional]: 'Transactional (INSERT/UPDATE/DELETE)',
  [WorkloadType.TaxFilerReadOnly]: 'Tax Filer - View Returns',
  [WorkloadType.TaxProfessionalReadOnly]: 'Tax Professional - View Client Data',
  [WorkloadType.VectorSearch]: 'Vector Similarity Search',
  [WorkloadType.AIAssistant]: 'AI Tax Assistant (RAG)',
  [WorkloadType.Analytics]: 'Branch/Regional Analytics',
  [WorkloadType.ExecutiveDashboard]: 'Executive Dashboard',
  [WorkloadType.DevOps]: 'DevOps Monitoring',
}
