"""
Step 1: Download IRS Publications

Downloads HTML versions of IRS publications for parsing.
Skips files that have already been downloaded.
Uses parallel downloads with rate-limiting to be polite to IRS servers.

IRS CONTENT NOTICE
------------------
Content in this repository is for demonstration purposes only.  Neither this
demonstration application nor Microsoft is affiliated with or endorsed by the
IRS.  IRS publications are U.S. Government Works (17 U.S.C. § 105) and may be
freely used per https://www.irs.gov/about-irs/use-of-content-from-irsgov.
All customer data is synthetic.  This is not tax advice.

Usage:
    python 01_download_irs_pubs.py [--priority 1] [--all]

Examples:
    python 01_download_irs_pubs.py              # Download priority 1 only (fast)
    python 01_download_irs_pubs.py --all        # Download all publications
    python 01_download_irs_pubs.py --pub p587   # Download specific publication
    python 01_download_irs_pubs.py --all --force # Re-download everything
    python 01_download_irs_pubs.py --all --workers 8  # 8 parallel threads
"""

import argparse
import requests
import time
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from bs4 import BeautifulSoup
from tqdm import tqdm

from config import IRS_PUBLICATIONS, RAW_DIR

# Request headers to mimic browser
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.5",
}

# Thread-safe rate limiter
_rate_lock = threading.Lock()
_last_request_time = 0.0


def _rate_limit(min_interval: float):
    """Ensure at least min_interval seconds between requests (thread-safe)."""
    global _last_request_time
    with _rate_lock:
        now = time.monotonic()
        wait = _last_request_time + min_interval - now
        if wait > 0:
            time.sleep(wait)
        _last_request_time = time.monotonic()


def download_publication(pub: dict, output_dir: Path, force: bool = False, delay: float = 0.5) -> dict:
    """
    Download a single IRS publication. Skips if already downloaded unless force=True.
    
    Returns dict with status and file path.
    """
    pub_id = pub["id"]
    url = pub["url"]
    output_file = output_dir / f"{pub_id}.html"
    
    result = {
        "id": pub_id,
        "title": pub["title"],
        "url": url,
        "status": "unknown",
        "file_path": None,
        "file_size": 0,
        "error": None
    }

    # Skip if already downloaded
    if not force and output_file.exists() and output_file.stat().st_size > 0:
        result["status"] = "skipped"
        result["file_path"] = str(output_file)
        result["file_size"] = output_file.stat().st_size
        return result
    
    try:
        # Rate-limit requests across all threads
        _rate_limit(delay)
        
        response = requests.get(url, headers=HEADERS, timeout=60)
        response.raise_for_status()
        
        # IRS pages serve UTF-8 content but may not declare charset in headers.
        # requests defaults to ISO-8859-1 for text/html without charset, which
        # corrupts smart quotes and other multi-byte UTF-8 characters.
        response.encoding = 'utf-8'
        
        # Check if we got HTML content
        content_type = response.headers.get("Content-Type", "")
        if "text/html" not in content_type:
            result["status"] = "wrong_content_type"
            result["error"] = f"Expected HTML, got {content_type}"
            return result
        
        # Parse to validate HTML
        soup = BeautifulSoup(response.text, "lxml")
        
        main_content = soup.find("div", class_="content") or soup.find("main") or soup.find("article")
        if not main_content:
            main_content = soup.find("body")
        
        if not main_content:
            result["status"] = "no_content"
            result["error"] = "Could not find main content in page"
            return result
        
        # Save the raw HTML
        output_file.write_text(response.text, encoding="utf-8")
        
        result["status"] = "success"
        result["file_path"] = str(output_file)
        result["file_size"] = len(response.text)
        
    except requests.exceptions.Timeout:
        result["status"] = "timeout"
        result["error"] = "Request timed out"
        
    except requests.exceptions.HTTPError as e:
        result["status"] = "http_error"
        result["error"] = str(e)
        
    except Exception as e:
        result["status"] = "error"
        result["error"] = str(e)
    
    return result


def download_all(publications: list, output_dir: Path, delay: float = 0.5,
                 force: bool = False, max_workers: int = 4) -> list:
    """
    Download all specified publications in parallel.
    
    Args:
        publications: List of publication configs
        output_dir: Directory to save files
        delay: Minimum seconds between requests (shared across threads)
        force: Re-download even if file exists
        max_workers: Number of parallel download threads
    
    Returns:
        List of result dicts
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    results = []

    print(f"\n{'='*60}")
    print(f"📚 Downloading {len(publications)} IRS Publications")
    print(f"   Output directory: {output_dir}")
    print(f"   Workers: {max_workers}  |  Rate limit: {delay}s between requests")
    if not force:
        print(f"   Skipping already-downloaded files (use --force to re-download)")
    print(f"{'='*60}\n")

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {
            executor.submit(download_publication, pub, output_dir, force, delay): pub
            for pub in publications
        }

        with tqdm(total=len(futures), desc="Downloading", unit="pub") as pbar:
            for future in as_completed(futures):
                result = future.result()
                results.append(result)

                # Inline status indicator
                status = result["status"]
                icon = {"success": "✅", "skipped": "⏭️", "http_error": "❌",
                        "timeout": "⏰", "error": "❌"}.get(status, "⚠️")
                pbar.set_postfix_str(f"{icon} {result['id']}")
                pbar.update(1)

    # Summary
    successful = [r for r in results if r["status"] == "success"]
    skipped = [r for r in results if r["status"] == "skipped"]
    failed = [r for r in results if r["status"] not in ("success", "skipped")]
    
    print(f"\n{'='*60}")
    print(f"📊 Download Summary")
    print(f"{'='*60}")
    print(f"   ✅ Downloaded: {len(successful)}")
    print(f"   ⏭️  Skipped (already exists): {len(skipped)}")
    print(f"   ❌ Failed: {len(failed)}")
    
    if failed:
        print(f"\n   Failed downloads:")
        for r in failed:
            print(f"   - {r['id']}: {r['error']}")
    
    total_size = sum(r["file_size"] for r in successful)
    print(f"\n   New data downloaded: {total_size:,} bytes ({total_size/1024/1024:.2f} MB)")
    
    return results


def main():
    parser = argparse.ArgumentParser(description="Download IRS publications")
    parser.add_argument("--all", action="store_true", help="Download all publications")
    parser.add_argument("--priority", type=int, default=1, help="Download publications up to this priority level")
    parser.add_argument("--pub", type=str, help="Download specific publication by ID (e.g., p587)")
    parser.add_argument("--delay", type=float, default=0.5, help="Min delay between requests in seconds (default: 0.5)")
    parser.add_argument("--force", action="store_true", help="Re-download even if file already exists")
    parser.add_argument("--workers", type=int, default=4, help="Number of parallel download threads (default: 4)")
    
    args = parser.parse_args()
    
    # Filter publications based on arguments
    if args.pub:
        pubs = [p for p in IRS_PUBLICATIONS if p["id"] == args.pub]
        if not pubs:
            print(f"❌ Publication '{args.pub}' not found in config")
            print(f"   Available: {[p['id'] for p in IRS_PUBLICATIONS]}")
            return
    elif args.all:
        pubs = IRS_PUBLICATIONS
    else:
        pubs = [p for p in IRS_PUBLICATIONS if p["priority"] <= args.priority]
    
    # Download
    results = download_all(pubs, RAW_DIR, delay=args.delay,
                           force=args.force, max_workers=args.workers)
    
    # Save results log
    import json
    log_file = RAW_DIR / "download_log.json"
    with open(log_file, "w") as f:
        json.dump(results, f, indent=2)
    print(f"\n📝 Download log saved to: {log_file}")


if __name__ == "__main__":
    main()
