"""
Step 3: Generate Embeddings using Azure OpenAI

Generates vector embeddings for all knowledge base chunks derived from IRS
publications — U.S. Government Works (17 U.S.C. § 105), freely usable per
https://www.irs.gov/about-irs/use-of-content-from-irsgov.
Neither this application nor Microsoft is affiliated with or endorsed by the IRS.

Usage:
    python 03_generate_embeddings.py [--input processed/knowledge_base_chunks.json]

Prerequisites:
    - Azure OpenAI resource with text-embedding-ada-002 deployment
    - Set environment variables in .env file
"""

import argparse
import json
import time
from pathlib import Path
from tqdm import tqdm
from openai import AzureOpenAI
from azure.identity import DefaultAzureCredential, get_bearer_token_provider

from config import (
    PROCESSED_DIR,
    OUTPUT_DIR,
    EMBEDDING_BATCH_SIZE,
    EMBEDDING_DIMENSIONS,
    AZURE_OPENAI_ENDPOINT,
    AZURE_OPENAI_EMBEDDING_DEPLOYMENT
)

# Maximum tokens per embedding API call (model limit is 8192)
MAX_BATCH_TOKENS = 7500  # Leave headroom below 8192

# Module-level variables set from command line args
_endpoint = None
_deployment = None


def create_client(endpoint: str) -> AzureOpenAI:
    """Create Azure OpenAI client using Azure CLI credentials."""
    # Use DefaultAzureCredential - automatically uses Azure CLI credentials
    credential = DefaultAzureCredential()
    
    # Create token provider for Azure OpenAI
    token_provider = get_bearer_token_provider(
        credential,
        "https://cognitiveservices.azure.com/.default"
    )
    
    return AzureOpenAI(
        azure_endpoint=endpoint,
        azure_ad_token_provider=token_provider,
        api_version="2024-02-01"
    )


def generate_embeddings_batch(client: AzureOpenAI, texts: list[str], deployment: str) -> list[list[float]]:
    """
    Generate embeddings for a batch of texts.
    
    Returns list of embedding vectors.
    """
    response = client.embeddings.create(
        input=texts,
        model=deployment
    )
    
    # Extract embeddings in order
    embeddings = [item.embedding for item in sorted(response.data, key=lambda x: x.index)]
    return embeddings


def process_chunks(input_file: Path, output_file: Path, endpoint: str, deployment: str, batch_size: int = EMBEDDING_BATCH_SIZE):
    """
    Process all chunks and generate embeddings.
    """
    # Load chunks
    print(f"\n📂 Loading chunks from: {input_file}")
    with open(input_file, 'r', encoding='utf-8') as f:
        chunks = json.load(f)
    
    print(f"   Loaded {len(chunks)} chunks")
    
    # Create client
    print(f"\n🔌 Connecting to Azure OpenAI (using Azure CLI credentials)...")
    client = create_client(endpoint)
    print(f"   Endpoint: {endpoint}")
    print(f"   Deployment: {deployment}")
    
    # Build token-aware batches (embedding API limit is 8192 tokens per request)
    batches = []
    current_batch = []
    current_tokens = 0
    for idx, chunk in enumerate(chunks):
        chunk_tokens = chunk.get('token_estimate', 500)
        # If a single chunk exceeds limit, it goes alone (will be truncated by API)
        if current_batch and current_tokens + chunk_tokens > MAX_BATCH_TOKENS:
            batches.append((current_batch, current_tokens))
            current_batch = []
            current_tokens = 0
        current_batch.append(idx)
        current_tokens += chunk_tokens
    if current_batch:
        batches.append((current_batch, current_tokens))

    print(f"\n🚀 Generating embeddings ({len(batches)} batches, max {MAX_BATCH_TOKENS} tokens/batch)")
    
    total_tokens = 0
    failed_chunks = []
    
    for batch_indices, batch_tokens in tqdm(batches, desc="Batches"):
        texts = [chunks[i]['content'] for i in batch_indices]
        
        try:
            embeddings = generate_embeddings_batch(client, texts, deployment)
            
            for j, embedding in enumerate(embeddings):
                chunks[batch_indices[j]]['embedding'] = embedding
            
            total_tokens += batch_tokens
            
        except Exception as e:
            error_str = str(e)
            batch_num = batches.index((batch_indices, batch_tokens))
            
            # Token limit exceeded — retry chunks individually
            if "maximum context length" in error_str or "too many tokens" in error_str.lower():
                tqdm.write(f"\n   ⚠️ Batch {batch_num} exceeded token limit ({len(batch_indices)} chunks, ~{batch_tokens} est). Retrying individually...")
                for i in batch_indices:
                    try:
                        emb = generate_embeddings_batch(client, [chunks[i]['content']], deployment)
                        chunks[i]['embedding'] = emb[0]
                        total_tokens += chunks[i].get('token_estimate', 500)
                        time.sleep(0.2)
                    except Exception as e2:
                        tqdm.write(f"      ❌ Chunk {chunks[i]['chunk_id']} failed individually: {e2}")
                        chunks[i]['embedding'] = None
                        failed_chunks.append(chunks[i]['chunk_id'])
            else:
                tqdm.write(f"\n   ⚠️ Batch {batch_num} failed ({len(batch_indices)} chunks, ~{batch_tokens} tokens): {e}")
                for i in batch_indices:
                    chunks[i]['embedding'] = None
                    failed_chunks.append(chunks[i]['chunk_id'])
            
            # Rate limit handling - wait and retry
            if "rate" in error_str.lower():
                tqdm.write(f"   ⏳ Rate limited. Waiting 60 seconds...")
                time.sleep(60)
        
        # Small delay between batches to avoid rate limits
        time.sleep(0.5)
    
    # Save results
    print(f"\n💾 Saving results to: {output_file}  (UTF-16 LE for SQL Server NCLOB)")
    with open(output_file, 'w', encoding='utf-16-le') as f:
        f.write('\ufeff')  # BOM required by SQL Server SINGLE_NCLOB
        json.dump(chunks, f, ensure_ascii=False)
    
    # Summary
    embedded_count = sum(1 for c in chunks if c.get('embedding'))
    
    print(f"\n{'='*60}")
    print(f"📊 Embedding Summary")
    print(f"{'='*60}")
    print(f"   Total chunks: {len(chunks)}")
    print(f"   Successfully embedded: {embedded_count}")
    print(f"   Failed: {len(failed_chunks)}")
    print(f"   Estimated tokens used: {total_tokens:,}")
    print(f"   Estimated cost: ${total_tokens * 0.0001 / 1000:.4f}")
    print(f"   Output file: {output_file}")
    print(f"   File size: {output_file.stat().st_size:,} bytes")
    
    if failed_chunks:
        print(f"\n   Failed chunk IDs:")
        for chunk_id in failed_chunks[:10]:
            print(f"   - {chunk_id}")
        if len(failed_chunks) > 10:
            print(f"   ... and {len(failed_chunks) - 10} more")


def main():
    parser = argparse.ArgumentParser(description="Generate embeddings for knowledge base chunks")
    parser.add_argument("--endpoint", type=str, default=AZURE_OPENAI_ENDPOINT,
                        help="Azure OpenAI endpoint (default: from .env)")
    parser.add_argument("--deployment", type=str, default=AZURE_OPENAI_EMBEDDING_DEPLOYMENT,
                        help="Embedding model deployment name (default: from .env)")
    parser.add_argument("--input", type=str, default="knowledge_base_chunks.json",
                        help="Input JSON file with chunks")
    parser.add_argument("--output", type=str, default="knowledge_base_embedded.json",
                        help="Output JSON file with embeddings")
    parser.add_argument("--batch-size", type=int, default=EMBEDDING_BATCH_SIZE,
                        help="Batch size for API calls")
    
    args = parser.parse_args()

    if not args.endpoint:
        parser.error("--endpoint is required (or set AZURE_OPENAI_ENDPOINT in .env)")
    if not args.deployment:
        parser.error("--deployment is required (or set AZURE_OPENAI_EMBEDDING_DEPLOYMENT in .env)")
    
    input_file = PROCESSED_DIR / args.input
    output_file = OUTPUT_DIR / args.output
    
    if not input_file.exists():
        print(f"❌ Input file not found: {input_file}")
        print("   Run 02_parse_and_chunk.py first")
        return
    
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    
    process_chunks(input_file, output_file, args.endpoint, args.deployment, args.batch_size)


if __name__ == "__main__":
    main()
