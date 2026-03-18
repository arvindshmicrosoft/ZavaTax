"""
Zava Tax Load Simulator - Main Entry Point

Realistic OLTP load generator that simulates production workflow patterns:
- Customer creation via AddCustomer procedure
- Tax return draft creation via SaveTaxReturnDraft
- Edit cycles (0-5 random edits) via UpdateTaxReturn
- Final submission via SubmitTaxReturn

Demonstrates Azure SQL DB Hyperscale's high transaction throughput capabilities
using the same stored procedures the frontend would call.

Usage:
    python -m oltp.main --workers 10 --duration 300
    python -m oltp.main --target-mbps 50 --duration 600
"""

import asyncio
import signal
import sys
import time
import threading
from concurrent.futures import ProcessPoolExecutor, as_completed
from multiprocessing import Manager
from typing import Optional
import click
import structlog
from dotenv import load_dotenv

from .config import Config, config
from .db_worker import DatabaseWorker, create_worker

# Load environment variables
load_dotenv()

# Configure structured logging
structlog.configure(
    processors=[
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.add_log_level,
        structlog.dev.ConsoleRenderer()
    ],
    wrapper_class=structlog.make_filtering_bound_logger(config.log_level),
    context_class=dict,
    logger_factory=structlog.PrintLoggerFactory(),
)

logger = structlog.get_logger()

# Check if debug mode is enabled
IS_DEBUG = config.log_level == 'DEBUG'


def _worker_process_loop(config_dict: dict, worker_id: int, workflows: int, shared_stats: dict, end_time: float = None) -> dict:
    """
    Worker function for ProcessPoolExecutor. Each process creates its own DatabaseWorker
    and connection to avoid GIL contention during Azure AD authentication.
    
    Args:
        config_dict: Configuration as dict (for pickling)
        worker_id: Worker identifier
        workflows: Max number of workflows to execute (will stop early if end_time reached)
        shared_stats: Shared dict for real-time progress tracking
        end_time: Unix timestamp when to stop (None for no time limit)
    
    Returns:
        Dict with worker statistics
    """
    # Recreate config object from dict
    from .config import Config
    from .db_worker import create_worker
    import structlog
    
    # Configure logging in this process
    structlog.configure(
        processors=[
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.processors.add_log_level,
            structlog.dev.ConsoleRenderer()
        ],
        wrapper_class=structlog.make_filtering_bound_logger(config_dict['log_level']),
        context_class=dict,
        logger_factory=structlog.PrintLoggerFactory(),
    )
    
    logger = structlog.get_logger()
    
    # Create config from dict
    config = Config.from_dict(config_dict)
    
    # Create worker (this will create connection on first use)
    worker = create_worker(config, worker_id=worker_id)
    
    worker_stats = {
        'rows': 0,
        'bytes': 0,
        'batches': 0,
        'reads': 0,
        'errors': 0
    }
    
    try:
        # Connect explicitly at start
        worker.connect()
        
        # Execute workflows (stop early if time limit reached)
        for workflow_num in range(workflows):
            # Check if we should stop due to time limit
            if end_time is not None and time.time() >= end_time:
                break
            
            result = worker.execute_workflow()
            
            # Count operations
            operations = 3 + result.num_edits_executed
            
            if result.success:
                worker_stats['rows'] += operations
                worker_stats['bytes'] += result.bytes_written
                worker_stats['batches'] += 1
                worker_stats['reads'] += result.num_reads_executed
                
                # Update shared stats for real-time progress
                with shared_stats['lock']:
                    shared_stats['total_rows'] += operations
                    shared_stats['total_bytes'] += result.bytes_written
                    shared_stats['total_batches'] += 1
                    shared_stats['total_reads'] += result.num_reads_executed
            else:
                worker_stats['errors'] += 1
                with shared_stats['lock']:
                    shared_stats['failed_batches'] += 1
    
    finally:
        worker.close()
    
    return worker_stats


class LoadSimulator:
    """
    Main load simulator orchestrator.
    
    Coordinates multiple workers to execute realistic OLTP workflows
    with stored procedure calls matching production patterns.
    """
    
    def __init__(self, cfg: Config):
        self.config = cfg
        self.executor: Optional[ProcessPoolExecutor] = None
        self.running = False
        self.start_time: Optional[float] = None
        
        # Multiprocessing manager for shared stats across processes
        self.manager = Manager()
        self.shared_stats = self.manager.dict()
        self.shared_stats['total_rows'] = 0
        self.shared_stats['total_bytes'] = 0
        self.shared_stats['total_batches'] = 0
        self.shared_stats['total_reads'] = 0
        self.shared_stats['failed_batches'] = 0
        self.shared_stats['lock'] = self.manager.Lock()
        
        # Throttle control
        self.throttle_delay = 0.0
    
    def _validate_procedures(self):
        """Validate that required stored procedures exist."""
        import mssql_python
        
        required_procs = ['AddCustomer', 'SaveTaxReturnDraft', 'UpdateTaxReturn', 'SubmitTaxReturn']
        
        try:
            logger.info("Validating stored procedures...")
            conn = mssql_python.connect(self.config.db.connection_string)
            cursor = conn.cursor()
            
            cursor.execute("""
                SELECT name FROM sys.procedures 
                WHERE name IN ('AddCustomer', 'SaveTaxReturnDraft', 'UpdateTaxReturn', 'SubmitTaxReturn')
            """)
            
            existing_procs = [row[0] for row in cursor.fetchall()]
            cursor.close()
            conn.close()
            
            missing_procs = [p for p in required_procs if p not in existing_procs]
            
            if missing_procs:
                logger.error(
                    "Missing required stored procedures",
                    missing=missing_procs,
                    found=existing_procs
                )
                print("\n" + "=" * 70)
                print("❌ ERROR: Missing Required Stored Procedures")
                print("=" * 70)
                print(f"\nMissing procedures: {', '.join(missing_procs)}")
                print(f"\nPlease run this script first:")
                print(f"  sqlcmd -S {self.config.db.server} -d {self.config.db.database} -G \\")
                print(f"         -i database/06_oltp_procedures.sql")
                print("\nOr from PowerShell:")
                print(f"  Invoke-Sqlcmd -ServerInstance {self.config.db.server} \\")
                print(f"                -Database {self.config.db.database} \\")
                print(f"                -AccessToken (Get-AzAccessToken -ResourceUrl https://database.windows.net).Token \\")
                print(f"                -InputFile database/06_oltp_procedures.sql")
                print("=" * 70 + "\n")
                sys.exit(1)
            
            logger.info("All required stored procedures found", procedures=existing_procs)
            
        except Exception as e:
            logger.error("Failed to validate stored procedures", error=str(e))
            print(f"\n⚠️  Warning: Could not validate stored procedures: {e}")
            print("Continuing anyway, but load test may fail if procedures don't exist.\n")
    
    def setup(self):
        """Initialize workers and connections."""
        logger.info(
            "Setting up load simulator",
            num_workers=self.config.load.num_workers,
            workflows_per_worker=self.config.load.batches_per_worker,
            target_mbps=self.config.load.target_throughput_mbps
        )
        
        # Validate required stored procedures exist
        self._validate_procedures()
        
        # Create process pool (avoids GIL contention during Azure AD auth)
        # Each worker process will create its own connection in parallel
        self.executor = ProcessPoolExecutor(
            max_workers=self.config.load.num_workers
        )
        logger.info("Using ProcessPoolExecutor to avoid GIL contention during connection auth",
                   max_workers=self.config.load.num_workers)
    
    def stop(self):
        """Stop the load test gracefully."""
        if not self.running:
            return
        
        logger.info("Stopping load test...")
        print("\n⚠️  Shutting down gracefully... (Press Ctrl-C again to force quit)")
        self.running = False
    
    def cleanup(self):
        """Clean up resources."""
        logger.info("Cleaning up...")
        self.running = False
        
        # Shutdown executor (processes will clean up their own connections)
        if self.executor:
            self.executor.shutdown(wait=False, cancel_futures=True)
        
        # Shutdown manager
        if hasattr(self, 'manager'):
            self.manager.shutdown()
        
        logger.info("Cleanup complete")
    
    def print_progress(self):
        """Print progress update."""
        if not self.start_time:
            return
        
        elapsed = time.time() - self.start_time
        
        # Read from shared stats (cross-process)
        total_rows = self.shared_stats.get('total_rows', 0)
        total_bytes = self.shared_stats.get('total_bytes', 0)
        total_batches = self.shared_stats.get('total_batches', 0)
        
        # Calculate rates
        throughput_mbps = (total_bytes / 1_000_000) / elapsed if elapsed > 0 else 0
        rows_per_sec = total_rows / elapsed if elapsed > 0 else 0
        
        # Log without color codes in structured fields
        logger.info(
            "Progress",
            elapsed_sec=f"{elapsed:.1f}",
            throughput_mbps=f"{throughput_mbps:.2f}",
            rows_per_sec=f"{rows_per_sec:.0f}",
            total_rows=total_rows,
            total_batches=total_batches,
            total_mb=f"{total_bytes/1_000_000:.1f}"
        )
    
    def run(self, duration_seconds: int = None):
        """
        Run the load test.
        
        Args:
            duration_seconds: How long to run in seconds (default from config)
        """
        duration = duration_seconds or self.config.load.duration_seconds
        workflows_per_worker = self.config.load.batches_per_worker
        
        # Calculate end time for duration-based testing
        end_time = time.time() + duration if duration > 0 else None
        
        # For duration-based tests, give workers more work than they can complete
        # They'll stop when time expires
        if duration > 0:
            # Assume ~2 workflows/sec per worker as reasonable estimate
            # Give them 2x buffer so they don't finish early
            estimated_workflows_capacity = int(duration * 2)
            workflows_per_worker = max(workflows_per_worker, estimated_workflows_capacity)
        
        logger.info(
            "Starting load test",
            duration_seconds=duration if duration > 0 else "unlimited",
            workflows_per_worker=workflows_per_worker,
            total_workers=self.config.load.num_workers,
            end_time=time.strftime('%H:%M:%S', time.localtime(end_time)) if end_time else "none"
        )
        
        self.running = True
        self.start_time = time.time()
        
        # Start progress reporter
        progress_thread = threading.Thread(target=self._progress_reporter, daemon=True)
        progress_thread.start()
        
        # Submit worker processes - each will connect independently in parallel
        # Using ProcessPoolExecutor avoids GIL contention during Azure AD auth
        logger.info("Submitting worker processes", num_workers=self.config.load.num_workers)
        print(f"\nStarting {self.config.load.num_workers} worker processes...")
        print("(Each worker will authenticate in parallel - no GIL contention)\n")
        
        # Convert config to dict for pickling across processes
        config_dict = {
            'db': {
                'server': self.config.db.server,
                'database': self.config.db.database,
                'managed_identity_client_id': self.config.db.managed_identity_client_id,
                'connection_timeout': self.config.db.connection_timeout,
            },
            'load': {
                'num_workers': self.config.load.num_workers,
                'batches_per_worker': self.config.load.batches_per_worker,
                'read_percentage': self.config.load.read_percentage,
                'target_throughput_mbps': self.config.load.target_throughput_mbps,
                'num_branches': self.config.load.num_branches,
                'num_professionals': self.config.load.num_professionals,
            },
            'log_level': self.config.log_level
        }
        
        futures = []
        for worker_id in range(self.config.load.num_workers):
            future = self.executor.submit(
                _worker_process_loop,
                config_dict,
                worker_id,
                workflows_per_worker,
                self.shared_stats,
                end_time
            )
            futures.append(future)
        
        logger.info("All workers submitted", num_futures=len(futures))
        # Wait for all workers to complete or be interrupted
        try:
            # Set timeout longer than duration to allow workers to finish gracefully
            timeout = (duration + 120) if duration > 0 else None
            
            for future in as_completed(futures, timeout=timeout):
                try:
                    # Worker stats are already accumulated in shared_stats during execution
                    # Just wait for completion
                    worker_stats = future.result(timeout=1.0)
                except Exception as e:
                    logger.error("Worker failed", error=str(e))
                
                # Check if interrupted
                if not self.running:
                    logger.info("Stopping workers...")
                    break
                    
        except KeyboardInterrupt:
            logger.info("Received keyboard interrupt")
            print("\n⚠️  Interrupted! Stopping workers...")
            self.running = False
            # Cancel remaining futures
            for future in futures:
                future.cancel()
        except Exception as e:
            logger.error("Load test error", error=str(e))
        finally:
            self.running = False
        
        # Print final summary
        self._print_summary()
    
    def _progress_reporter(self):
        """Background thread to report progress."""
        while self.running:
            time.sleep(5)
            if self.running:
                self.print_progress()
    
    def _print_summary(self):
        """Print final test summary."""
        elapsed = time.time() - self.start_time if self.start_time else 1
        
        # Read final stats from shared dict
        total_rows = self.shared_stats.get('total_rows', 0)
        total_bytes = self.shared_stats.get('total_bytes', 0)
        total_batches = self.shared_stats.get('total_batches', 0)
        total_reads = self.shared_stats.get('total_reads', 0)
        failed_batches = self.shared_stats.get('failed_batches', 0)
        
        avg_throughput = (total_bytes / 1_000_000) / elapsed
        avg_rows_per_sec = total_rows / elapsed
        
        print("\n" + "=" * 70)
        print("LOAD TEST COMPLETE")
        print("=" * 70)
        print(f"Duration:              {elapsed:.1f} seconds")
        print(f"Total Write Operations: {total_rows:,}")
        print(f"Total Read Operations:  {total_reads:,} (from HA read replica)")
        print(f"Total Data Written:     {total_bytes / 1_000_000:.2f} MB")
        print(f"Successful Workflows:   {total_batches:,}")
        print(f"Failed Workflows:       {failed_batches:,}")
        print("-" * 70)
        print(f"Avg Write Throughput:   {avg_throughput:.2f} MB/s")
        print(f"Avg Operations/sec:     {avg_rows_per_sec:.0f}")
        print(f"Target Throughput:      {self.config.load.target_throughput_mbps} MB/s")
        print(f"Read/Write Mix:         {self.config.load.read_percentage}% reads")
        print("=" * 70)
        
        # Assessment
        if avg_throughput >= 100:
            print("\n✅ EXCELLENT: Achieved 100+ MB/s throughput!")
        elif avg_throughput >= 50:
            print("\n⚠️  GOOD: Achieved 50+ MB/s throughput")
        else:
            print("\n❌ BELOW TARGET: Consider increasing workers")


@click.command()
@click.option('--server', '-s', default=None, type=str, help='SQL Server hostname (overrides SQL_SERVER env var)')
@click.option('--database', default=None, type=str, help='Database name (overrides SQL_DATABASE env var)')
@click.option('--workers', '-w', default=None, type=int, help='Number of parallel workers')
@click.option('--duration', '-d', default=None, type=int, help='Test duration in seconds (0 for unlimited)')
@click.option('--read-pct', '-r', default=None, type=int, help='Percentage of operations that are reads from HA read replica (0-100)')
@click.option('--target-mbps', '-t', default=None, type=float, help='Target throughput in MB/s')
def main(server, database, workers, duration, read_pct, target_mbps):
    """
    Zava Tax OLTP Load Simulator
    
    Simulates realistic OLTP workflow patterns:
    - Customer creation (AddCustomer procedure)
    - Draft tax return creation (SaveTaxReturnDraft)
    - Edit cycles - 0-5 random edits (UpdateTaxReturn)
    - Final submission (SubmitTaxReturn)
    
    Uses stored procedures to match production frontend patterns.
    Works with Azure SQL Database using Azure CLI authentication (az login).
    
    Examples:
        # Local test with Azure SQL
        python -m oltp.main -s myserver.database.windows.net -d zavatax -w 10
        
        # High throughput test
        python -m oltp.main -w 20 -t 50 -d 600
    """
    # Override config with CLI args
    if server:
        config.db.server = server
    if database:
        config.db.database = database
    if workers:
        config.load.num_workers = workers
    if duration is not None:
        config.load.duration_seconds = duration
    if read_pct is not None:
        config.load.read_percentage = max(0, min(100, read_pct))  # Clamp to 0-100
    if target_mbps:
        config.load.target_throughput_mbps = target_mbps
    
    # Log connection details
    logger.info(
        "Starting OLTP load test",
        server=config.db.server,
        database=config.db.database,
        workers=config.load.num_workers,
        workflows_per_worker=config.load.batches_per_worker,
        duration_seconds=config.load.duration_seconds,
        read_percentage=config.load.read_percentage
    )
    
    # Create and run simulator
    simulator = LoadSimulator(config)
    
    # Handle graceful shutdown
    def signal_handler(sig, frame):
        logger.info("Received shutdown signal", signal=sig)
        simulator.stop()
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    try:
        simulator.setup()
        simulator.run()
    except KeyboardInterrupt:
        logger.info("Interrupted by user")
        print("\n\n⚠️  Load test interrupted by user")
    finally:
        simulator.cleanup()


if __name__ == "__main__":
    main()
