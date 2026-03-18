"""
Step 2: Parse and Chunk IRS Publications

Parses downloaded HTML files and chunks them for embedding.
Preserves section hierarchy and metadata.

IRS CONTENT NOTICE
------------------
Neither this application nor Microsoft is affiliated with or endorsed by the IRS.
IRS publications are U.S. Government Works (17 U.S.C. § 105) and may be freely
used per https://www.irs.gov/about-irs/use-of-content-from-irsgov

Usage:
    python 02_parse_and_chunk.py [--input raw/p587.html] [--all]

Examples:
    python 02_parse_and_chunk.py              # Process all downloaded files
    python 02_parse_and_chunk.py --file p587  # Process specific publication
"""

import argparse
import json
import re
from pathlib import Path
from dataclasses import dataclass, asdict
from typing import Generator
from bs4 import BeautifulSoup, NavigableString
from tqdm import tqdm

from config import RAW_DIR, PROCESSED_DIR, CHUNK_SIZE, CHUNK_OVERLAP


@dataclass
class Chunk:
    """Represents a single chunk of content for embedding."""
    chunk_id: str
    publication_id: str
    publication_title: str
    section: str
    subsection: str
    content: str
    token_estimate: int
    url: str
    chunk_index: int


def estimate_tokens(text: str) -> int:
    """
    Estimate token count for text.
    Rough estimate: 1 token ≈ 4 characters for English text.
    """
    return len(text) // 4


def clean_text(text: str) -> str:
    """Clean and normalize text content."""
    # Replace multiple whitespace with single space
    text = re.sub(r'\s+', ' ', text)
    # Remove leading/trailing whitespace
    text = text.strip()
    return text


def extract_sections_from_html(html_content: str, pub_id: str) -> list[dict]:
    """
    Extract sections from IRS publication HTML.
    
    Returns list of dicts with section info and content.
    """
    soup = BeautifulSoup(html_content, 'lxml')
    sections = []
    
    # Remove script, style, and nav elements
    for tag in soup.find_all(['script', 'style', 'nav', 'footer', 'header']):
        tag.decompose()
    
    # Find main content area
    main_content = (
        soup.find('div', class_='content') or 
        soup.find('div', id='main-content') or
        soup.find('main') or 
        soup.find('article') or
        soup.find('body')
    )
    
    if not main_content:
        tqdm.write(f"   ⚠️ Could not find main content for {pub_id}")
        return sections
    
    # Strategy: Find all heading elements and extract content between them
    current_section = "Introduction"
    current_subsection = ""
    current_content = []
    
    # Get all text-bearing elements
    for element in main_content.find_all(['h1', 'h2', 'h3', 'h4', 'p', 'li', 'td', 'th']):
        tag_name = element.name
        text = clean_text(element.get_text())
        
        if not text:
            continue
        
        # Handle headings
        if tag_name in ['h1', 'h2']:
            # Save previous section if it has content
            if current_content:
                sections.append({
                    'section': current_section,
                    'subsection': current_subsection,
                    'content': ' '.join(current_content)
                })
                current_content = []
            
            current_section = text
            current_subsection = ""
            
        elif tag_name in ['h3', 'h4']:
            # Save previous subsection if it has content
            if current_content:
                sections.append({
                    'section': current_section,
                    'subsection': current_subsection,
                    'content': ' '.join(current_content)
                })
                current_content = []
            
            current_subsection = text
            
        else:
            # Regular content
            current_content.append(text)
    
    # Don't forget the last section
    if current_content:
        sections.append({
            'section': current_section,
            'subsection': current_subsection,
            'content': ' '.join(current_content)
        })
    
    return sections


def chunk_sections(sections: list[dict], pub_id: str, pub_title: str, 
                   chunk_size: int = CHUNK_SIZE, overlap: int = CHUNK_OVERLAP) -> list[Chunk]:
    """
    Split sections into chunks of approximately chunk_size tokens.
    
    Uses a sliding window with overlap to preserve context.
    """
    chunks = []
    chunk_index = 0
    
    for section in sections:
        content = section['content']
        section_name = section['section']
        subsection_name = section['subsection']
        
        # Split content into sentences (rough approximation)
        sentences = re.split(r'(?<=[.!?])\s+', content)
        
        current_chunk = []
        current_tokens = 0
        
        for sentence in sentences:
            sentence_tokens = estimate_tokens(sentence)
            
            # If single sentence exceeds chunk size, split it
            if sentence_tokens > chunk_size:
                # Save current chunk if not empty
                if current_chunk:
                    chunk_text = ' '.join(current_chunk)
                    chunks.append(Chunk(
                        chunk_id=f"{pub_id}_chunk_{chunk_index:04d}",
                        publication_id=pub_id,
                        publication_title=pub_title,
                        section=section_name,
                        subsection=subsection_name,
                        content=chunk_text,
                        token_estimate=estimate_tokens(chunk_text),
                        url=f"https://www.irs.gov/publications/{pub_id}",
                        chunk_index=chunk_index
                    ))
                    chunk_index += 1
                    current_chunk = []
                    current_tokens = 0
                
                # Split long sentence by words
                words = sentence.split()
                word_chunk = []
                word_tokens = 0
                for word in words:
                    word_tokens += estimate_tokens(word + ' ')
                    if word_tokens > chunk_size:
                        chunk_text = ' '.join(word_chunk)
                        chunks.append(Chunk(
                            chunk_id=f"{pub_id}_chunk_{chunk_index:04d}",
                            publication_id=pub_id,
                            publication_title=pub_title,
                            section=section_name,
                            subsection=subsection_name,
                            content=chunk_text,
                            token_estimate=estimate_tokens(chunk_text),
                            url=f"https://www.irs.gov/publications/{pub_id}",
                            chunk_index=chunk_index
                        ))
                        chunk_index += 1
                        word_chunk = []
                        word_tokens = 0
                    word_chunk.append(word)
                
                if word_chunk:
                    current_chunk = word_chunk
                    current_tokens = word_tokens
                continue
            
            # Check if adding this sentence exceeds chunk size
            if current_tokens + sentence_tokens > chunk_size and current_chunk:
                # Save current chunk
                chunk_text = ' '.join(current_chunk)
                chunks.append(Chunk(
                    chunk_id=f"{pub_id}_chunk_{chunk_index:04d}",
                    publication_id=pub_id,
                    publication_title=pub_title,
                    section=section_name,
                    subsection=subsection_name,
                    content=chunk_text,
                    token_estimate=estimate_tokens(chunk_text),
                    url=f"https://www.irs.gov/publications/{pub_id}",
                    chunk_index=chunk_index
                ))
                chunk_index += 1
                
                # Start new chunk with overlap (keep last few sentences)
                overlap_tokens = 0
                overlap_start = len(current_chunk)
                for i in range(len(current_chunk) - 1, -1, -1):
                    overlap_tokens += estimate_tokens(current_chunk[i])
                    if overlap_tokens >= overlap:
                        overlap_start = i
                        break
                
                current_chunk = current_chunk[overlap_start:]
                current_tokens = sum(estimate_tokens(s) for s in current_chunk)
            
            current_chunk.append(sentence)
            current_tokens += sentence_tokens
        
        # Save remaining content as final chunk for this section
        if current_chunk:
            chunk_text = ' '.join(current_chunk)
            if estimate_tokens(chunk_text) > 50:  # Only save if substantial
                chunks.append(Chunk(
                    chunk_id=f"{pub_id}_chunk_{chunk_index:04d}",
                    publication_id=pub_id,
                    publication_title=pub_title,
                    section=section_name,
                    subsection=subsection_name,
                    content=chunk_text,
                    token_estimate=estimate_tokens(chunk_text),
                    url=f"https://www.irs.gov/publications/{pub_id}",
                    chunk_index=chunk_index
                ))
                chunk_index += 1
    
    return chunks


def process_publication(html_file: Path, pub_title: str = None) -> list[Chunk]:
    """
    Process a single publication HTML file into chunks.
    """
    pub_id = html_file.stem  # e.g., "p587"
    
    if not pub_title:
        pub_title = f"IRS Publication {pub_id.upper()}"
    
    tqdm.write(f"\n📄 Processing: {pub_id}")
    
    # Read HTML content
    html_content = html_file.read_text(encoding='utf-8')
    tqdm.write(f"   HTML size: {len(html_content):,} bytes")
    
    # Extract sections
    sections = extract_sections_from_html(html_content, pub_id)
    tqdm.write(f"   Sections found: {len(sections)}")
    
    # Chunk sections
    chunks = chunk_sections(sections, pub_id, pub_title)
    tqdm.write(f"   Chunks created: {len(chunks)}")
    
    # Statistics
    if chunks:
        avg_tokens = sum(c.token_estimate for c in chunks) / len(chunks)
        tqdm.write(f"   Avg tokens per chunk: {avg_tokens:.0f}")
    
    return chunks


def main():
    parser = argparse.ArgumentParser(description="Parse and chunk IRS publications")
    parser.add_argument("--file", type=str, help="Process specific publication by ID (e.g., p587)")
    parser.add_argument("--all", action="store_true", help="Process all downloaded files")
    
    args = parser.parse_args()
    
    # Load publication metadata
    from config import IRS_PUBLICATIONS
    pub_titles = {p["id"]: p["title"] for p in IRS_PUBLICATIONS}
    
    # Find files to process
    if args.file:
        files = list(RAW_DIR.glob(f"{args.file}.html"))
        if not files:
            print(f"❌ File not found: {args.file}.html in {RAW_DIR}")
            return
    else:
        files = list(RAW_DIR.glob("*.html"))
    
    if not files:
        print(f"❌ No HTML files found in {RAW_DIR}")
        print("   Run 01_download_irs_pubs.py first")
        return
    
    print(f"\n{'='*60}")
    print(f"📚 Processing {len(files)} IRS Publications")
    print(f"{'='*60}")
    
    all_chunks = []
    
    for html_file in tqdm(files, desc="Processing"):
        pub_id = html_file.stem
        pub_title = pub_titles.get(pub_id, f"IRS Publication {pub_id.upper()}")
        
        chunks = process_publication(html_file, pub_title)
        all_chunks.extend(chunks)
    
    # Save all chunks to JSON
    output_file = PROCESSED_DIR / "knowledge_base_chunks.json"
    chunks_data = [asdict(c) for c in all_chunks]
    
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(chunks_data, f, indent=2, ensure_ascii=False)
    
    print(f"\n{'='*60}")
    print(f"📊 Processing Summary")
    print(f"{'='*60}")
    print(f"   Total chunks: {len(all_chunks)}")
    print(f"   Output file: {output_file}")
    print(f"   File size: {output_file.stat().st_size:,} bytes")
    
    # Breakdown by publication
    from collections import Counter
    pub_counts = Counter(c.publication_id for c in all_chunks)
    print(f"\n   Chunks by publication:")
    for pub_id, count in sorted(pub_counts.items()):
        print(f"   - {pub_id}: {count} chunks")


if __name__ == "__main__":
    main()
