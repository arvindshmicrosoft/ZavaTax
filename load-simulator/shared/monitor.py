"""
Zava Tax Load Simulator - Live Monitor

Real-time monitoring of load test progress and Hyperscale metrics.

Usage:
    python monitor.py --sql-server your-server.database.windows.net
"""

import time
import os
import sys
import click
from datetime import datetime
from dotenv import load_dotenv

try:
    import mssql_python
except ImportError:
    print("❌ mssql-python not installed. Install with: pip install mssql-python")
    exit(1)

load_dotenv()


def clear_screen():
    os.system('cls' if os.name == 'nt' else 'clear')


def format_bytes(bytes_val):
    """Format bytes to human readable."""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_val < 1024:
            return f"{bytes_val:.2f} {unit}"
        bytes_val /= 1024
    return f"{bytes_val:.2f} PB"


def get_hyperscale_metrics(cursor) -> dict:
    """Get resource stats from sys.dm_db_resource_stats."""
    try:
        cursor.execute("""
            SELECT TOP 1
                avg_cpu_percent,
                avg_data_io_percent,
                avg_log_write_percent,
                max_worker_percent,
                max_session_percent
            FROM sys.dm_db_resource_stats
            ORDER BY end_time DESC
        """)
        row = cursor.fetchone()
        if row:
            return {
                'avg_cpu_percent': row[0] or 0,
                'avg_data_io_percent': row[1] or 0,
                'avg_log_write_percent': row[2] or 0,
                'max_worker_percent': row[3] or 0,
                'max_session_percent': row[4] or 0
            }
    except:
        pass
    return {}


def get_ingestion_metrics(cursor) -> dict:
    """Get recent ingestion activity."""
    try:
        cursor.execute("""
            SELECT 
                COUNT(*) AS RecentRows
            FROM TaxReturns
            WHERE CreatedAt >= DATEADD(MINUTE, -1, SYSUTCDATETIME())
        """)
        row = cursor.fetchone()
        if row:
            return {
                'recent_rows': row[0] or 0
            }
    except:
        pass
    return {'recent_rows': 0}


def get_total_counts(cursor) -> dict:
    """Get total row counts."""
    try:
        cursor.execute("""
            SELECT 
                (SELECT COUNT(*) FROM TaxReturns) AS FactRows,
                (SELECT COUNT(*) FROM TaxKnowledgeBase) AS KnowledgeRows,
                (SELECT COUNT(*) FROM TaxScenarios) AS ScenarioRows
        """)
        row = cursor.fetchone()
        if row:
            return {
                'fact_rows': row[0] or 0,
                'knowledge_rows': row[1] or 0,
                'scenario_rows': row[2] or 0
            }
    except:
        pass
    return {}


def display_dashboard(metrics: dict, ingestion: dict, totals: dict, elapsed: float):
    """Display the monitoring dashboard."""
    clear_screen()
    
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    print("╔══════════════════════════════════════════════════════════════════════╗")
    print("║            ZAVA TAX - HYPERSCALE LOAD TEST MONITOR                   ║")
    print(f"║            {now}                                    ║")
    print("╠══════════════════════════════════════════════════════════════════════╣")
    
    # Resource utilization metrics from sys.dm_db_resource_stats
    if metrics:
        print("║  DATABASE RESOURCE UTILIZATION                                       ║")
        print(f"║    CPU:               {metrics.get('avg_cpu_percent', 0):.1f}%                                          ║")
        print(f"║    Data I/O:          {metrics.get('avg_data_io_percent', 0):.1f}%                                          ║")
        print(f"║    Log Write:         {metrics.get('avg_log_write_percent', 0):.1f}%                                          ║")
        print(f"║    Worker Threads:    {metrics.get('max_worker_percent', 0):.1f}%                                          ║")
        print(f"║    Sessions:          {metrics.get('max_session_percent', 0):.1f}%                                          ║")
    else:
        print("║  RESOURCE METRICS: Not available (waiting for activity)              ║")
    
    print("╠══════════════════════════════════════════════════════════════════════╣")
    
    # Ingestion activity (last minute)
    rows_per_sec = ingestion.get('recent_rows', 0) / 60
    print("║  INGESTION ACTIVITY (Last 60 seconds)                                ║")
    print(f"║    Rows Inserted:     {ingestion.get('recent_rows', 0):,}                                      ║")
    print(f"║    Rate:              {rows_per_sec:.0f} rows/sec                                      ║")
    
    print("╠══════════════════════════════════════════════════════════════════════╣")
    
    # Total counts
    print("║  TABLE ROW COUNTS                                                    ║")
    print(f"║    TaxReturns:     {totals.get('fact_rows', 0):>12,}                                   ║")
    print(f"║    TaxKnowledgeBase:   {totals.get('knowledge_rows', 0):>12,}                                   ║")
    print(f"║    TaxScenarios:       {totals.get('scenario_rows', 0):>12,}                                   ║")
    
    print("╠══════════════════════════════════════════════════════════════════════╣")
    
    # Resource utilization indicator (based on log write %)
    target_pct = 80
    achieved = metrics.get('avg_log_write_percent', 0) if metrics else 0
    pct = min((achieved / target_pct) * 100, 100)
    bar_width = 50
    filled = int(bar_width * pct / 100)
    bar = '█' * filled + '░' * (bar_width - filled)
    
    print(f"║  LOG WRITE: {achieved:.1f}% / {target_pct}%  [{bar}] {pct:.0f}%   ║")
    print("╚══════════════════════════════════════════════════════════════════════╝")
    print("\nPress Ctrl+C to stop monitoring")


@click.command()
@click.option('--sql-server', envvar='SQL_SERVER', required=True, help='SQL Server hostname')
@click.option('--database', envvar='SQL_DATABASE', default='zavatax', help='Database name')
@click.option('--interval', default=5, help='Refresh interval in seconds')
def main(sql_server, database, interval):
    """Monitor Hyperscale load test in real-time.
    
    Authentication uses Azure AD via DefaultAzureCredential.
    This supports managed identity, Azure CLI (az login), VS Code, etc.
    """
    
    # Build connection string with Azure AD authentication for mssql-python
    conn_str = (
        f"SERVER={sql_server};"
        f"DATABASE={database};"
        f"Authentication=ActiveDirectoryDefault;"
        f"Encrypt=yes;TrustServerCertificate=no;"
    )
    
    print(f"Connecting to {sql_server}/{database} using Azure AD...")
    
    try:
        conn = mssql_python.connect(conn_str)
        cursor = conn.cursor()
        
        start_time = time.time()
        
        while True:
            try:
                elapsed = time.time() - start_time
                
                # Gather metrics
                hs_metrics = get_hyperscale_metrics(cursor)
                ingestion = get_ingestion_metrics(cursor)
                totals = get_total_counts(cursor)
                
                # Display
                display_dashboard(hs_metrics, ingestion, totals, elapsed)
                
                time.sleep(interval)
                
            except KeyboardInterrupt:
                break
            except Exception as e:
                print(f"\nError: {e}")
                time.sleep(interval)
        
        cursor.close()
        conn.close()
        print("\nMonitoring stopped.")
        
    except Exception as e:
        print(f"Connection failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
