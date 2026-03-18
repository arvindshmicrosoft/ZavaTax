"""
Zava Tax Load Simulator - Prometheus Metrics

Exposes metrics for monitoring load test performance.
"""

from prometheus_client import Counter, Gauge, Histogram, Summary, start_http_server
import time


# Counters
ROWS_INSERTED = Counter(
    'zavatax_rows_inserted_total',
    'Total number of rows inserted',
    ['worker_id', 'status']
)

BATCHES_PROCESSED = Counter(
    'zavatax_batches_processed_total', 
    'Total number of batches processed',
    ['worker_id', 'status']
)

BYTES_WRITTEN = Counter(
    'zavatax_bytes_written_total',
    'Total bytes written to database',
    ['worker_id']
)

ERRORS = Counter(
    'zavatax_errors_total',
    'Total number of errors',
    ['worker_id', 'error_type']
)

# Gauges
ACTIVE_WORKERS = Gauge(
    'zavatax_active_workers',
    'Number of currently active workers'
)

CURRENT_THROUGHPUT_MBPS = Gauge(
    'zavatax_current_throughput_mbps',
    'Current throughput in MB/s'
)

CURRENT_ROWS_PER_SEC = Gauge(
    'zavatax_current_rows_per_second',
    'Current rows inserted per second'
)

TARGET_THROUGHPUT_MBPS = Gauge(
    'zavatax_target_throughput_mbps',
    'Target throughput in MB/s'
)

# Histograms
BATCH_DURATION = Histogram(
    'zavatax_batch_duration_seconds',
    'Time to insert a batch',
    ['worker_id'],
    buckets=(0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0)
)

BATCH_SIZE_BYTES = Histogram(
    'zavatax_batch_size_bytes',
    'Size of batches in bytes',
    buckets=(1000, 10000, 50000, 100000, 500000, 1000000, 5000000)
)

# Summaries
INSERT_LATENCY = Summary(
    'zavatax_insert_latency_seconds',
    'Insert latency summary',
    ['worker_id']
)


class MetricsCollector:
    """Collects and exposes load test metrics."""
    
    def __init__(self, port: int = 8000):
        self.port = port
        self.start_time = None
        self._total_bytes = 0
        self._total_rows = 0
        self._window_bytes = 0
        self._window_rows = 0
        self._window_start = None
        self._window_duration = 5.0  # 5 second sliding window
    
    def start(self):
        """Start the Prometheus HTTP server."""
        start_http_server(self.port)
        self.start_time = time.time()
        self._window_start = time.time()
    
    def record_batch(self, worker_id: int, success: bool, rows: int, 
                     bytes_written: int, duration_seconds: float, error: str = None):
        """Record metrics for a batch operation."""
        status = 'success' if success else 'failure'
        worker_label = str(worker_id)
        
        # Update counters
        BATCHES_PROCESSED.labels(worker_id=worker_label, status=status).inc()
        
        if success:
            ROWS_INSERTED.labels(worker_id=worker_label, status=status).inc(rows)
            BYTES_WRITTEN.labels(worker_id=worker_label).inc(bytes_written)
            
            # Update totals
            self._total_bytes += bytes_written
            self._total_rows += rows
            self._window_bytes += bytes_written
            self._window_rows += rows
        else:
            error_type = error[:50] if error else 'unknown'
            ERRORS.labels(worker_id=worker_label, error_type=error_type).inc()
        
        # Record histograms
        BATCH_DURATION.labels(worker_id=worker_label).observe(duration_seconds)
        BATCH_SIZE_BYTES.observe(bytes_written)
        INSERT_LATENCY.labels(worker_id=worker_label).observe(duration_seconds)
        
        # Update throughput gauges periodically
        self._update_throughput()
    
    def _update_throughput(self):
        """Update throughput gauges based on sliding window."""
        now = time.time()
        window_elapsed = now - self._window_start
        
        if window_elapsed >= self._window_duration:
            # Calculate throughput for the window
            throughput_mbps = (self._window_bytes / 1_000_000) / window_elapsed
            rows_per_sec = self._window_rows / window_elapsed
            
            CURRENT_THROUGHPUT_MBPS.set(throughput_mbps)
            CURRENT_ROWS_PER_SEC.set(rows_per_sec)
            
            # Reset window
            self._window_bytes = 0
            self._window_rows = 0
            self._window_start = now
    
    def set_target_throughput(self, mbps: float):
        """Set the target throughput gauge."""
        TARGET_THROUGHPUT_MBPS.set(mbps)
    
    def set_active_workers(self, count: int):
        """Set the active workers gauge."""
        ACTIVE_WORKERS.set(count)
    
    def get_stats(self) -> dict:
        """Get current statistics."""
        elapsed = time.time() - self.start_time if self.start_time else 1
        return {
            'total_bytes': self._total_bytes,
            'total_rows': self._total_rows,
            'elapsed_seconds': elapsed,
            'avg_throughput_mbps': (self._total_bytes / 1_000_000) / elapsed,
            'avg_rows_per_sec': self._total_rows / elapsed
        }


# Global metrics collector instance
metrics = MetricsCollector()
