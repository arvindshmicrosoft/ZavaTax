"""
Zava Tax Load Simulator - Configuration

Environment-based configuration for the load simulator.
"""

import os
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class DatabaseConfig:
    """Database connection configuration using Azure AD authentication exclusively."""
    server: str = field(default_factory=lambda: os.getenv("SQL_SERVER", "localhost"))
    database: str = field(default_factory=lambda: os.getenv("SQL_DATABASE", "zavatax"))
    managed_identity_client_id: Optional[str] = field(default_factory=lambda: os.getenv("AZURE_CLIENT_ID"))
    connection_timeout: int = field(default_factory=lambda: int(os.getenv("SQL_CONNECTION_TIMEOUT", "30")))
    
    @property
    def connection_string(self) -> str:
        """Build connection string with Azure AD authentication for mssql-python native driver."""
        # mssql-python is a native driver and doesn't use ODBC - no DRIVER keyword
        conn_str = (
            f"Server={self.server};"
            f"Database={self.database};"
            f"Authentication=ActiveDirectoryDefault;"
            f"Encrypt=yes;"
        )
        return conn_str
    
    @property
    def readonly_connection_string(self) -> str:
        """Build connection string for HA read replica."""
        conn_str = (
            f"Server={self.server};"
            f"Database={self.database};"
            f"Authentication=ActiveDirectoryDefault;"
            f"ApplicationIntent=ReadOnly;"
            f"Encrypt=yes;"
        )
        return conn_str


@dataclass
class LoadConfig:
    """Load generation configuration for workflow simulation."""
    # Concurrency
    num_workers: int = field(default_factory=lambda: int(os.getenv("NUM_WORKERS", "10")))
    
    # Workflow settings
    batches_per_worker: int = field(default_factory=lambda: int(os.getenv("BATCHES_PER_WORKER", "100")))
    
    # Read/Write mix (percentage of operations that are reads from HA read replica)
    read_percentage: int = field(default_factory=lambda: int(os.getenv("READ_PERCENTAGE", "30")))
    
    # Throughput control
    target_throughput_mbps: float = field(default_factory=lambda: float(os.getenv("TARGET_THROUGHPUT_MBPS", "50")))
    max_throughput_mbps: float = field(default_factory=lambda: float(os.getenv("MAX_THROUGHPUT_MBPS", "150")))
    
    # Duration
    duration_seconds: int = field(default_factory=lambda: int(os.getenv("DURATION_SECONDS", "300")))
    warmup_seconds: int = field(default_factory=lambda: int(os.getenv("WARMUP_SECONDS", "30")))
    
    def __post_init__(self):
        """Validate configuration after initialization."""
        import platform
        # Windows ProcessPoolExecutor has a limit of 61 workers due to WaitForMultipleObjects API
        if platform.system() == 'Windows' and self.num_workers > 61:
            import warnings
            warnings.warn(
                f"num_workers={self.num_workers} exceeds Windows limit of 61. "
                "Capping at 61. For higher concurrency, run on Linux or use Azure Container Apps.",
                UserWarning
            )
            self.num_workers = 61
    
    # Data generation
    num_branches: int = field(default_factory=lambda: int(os.getenv("NUM_BRANCHES", "500")))
    num_professionals: int = field(default_factory=lambda: int(os.getenv("NUM_PROFESSIONALS", "2000")))


@dataclass
class Config:
    """Main configuration container."""
    db: DatabaseConfig = field(default_factory=DatabaseConfig)
    load: LoadConfig = field(default_factory=LoadConfig)
    
    log_level: str = field(default_factory=lambda: os.getenv("LOG_LEVEL", "INFO"))
    
    @classmethod
    def from_env(cls) -> "Config":
        """Create config from environment variables."""
        return cls()
    
    @classmethod
    def from_dict(cls, config_dict: dict) -> "Config":
        """Create config from dictionary (for ProcessPoolExecutor pickling)."""
        db_cfg = DatabaseConfig(
            server=config_dict['db']['server'],
            database=config_dict['db']['database'],
            managed_identity_client_id=config_dict['db']['managed_identity_client_id'],
            connection_timeout=config_dict['db']['connection_timeout']
        )
        
        load_cfg = LoadConfig(
            num_workers=config_dict['load']['num_workers'],
            batches_per_worker=config_dict['load']['batches_per_worker'],
            read_percentage=config_dict['load'].get('read_percentage', 30),
            target_throughput_mbps=config_dict['load']['target_throughput_mbps'],
            num_branches=config_dict['load']['num_branches'],
            num_professionals=config_dict['load']['num_professionals']
        )
        
        return cls(
            db=db_cfg,
            load=load_cfg,
            log_level=config_dict['log_level']
        )


# Singleton config instance
config = Config.from_env()
