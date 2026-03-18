"""
Step 5: Generate Embeddings for Tax Scenarios

Generates vector embeddings for scenario summaries.

Usage:
    python 05_embed_scenarios.py
"""

import argparse
import json
import time
from pathlib import Path
from tqdm import tqdm
from openai import AzureOpenAI
from azure.identity import DefaultAzureCredential, get_bearer_token_provider

from config import (
    OUTPUT_DIR,
    EMBEDDING_BATCH_SIZE,
    AZURE_OPENAI_ENDPOINT,
    AZURE_OPENAI_EMBEDDING_DEPLOYMENT
)


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
    """Generate embeddings for a batch of texts."""
    response = client.embeddings.create(
        input=texts,
        model=deployment
    )
    
    embeddings = [item.embedding for item in sorted(response.data, key=lambda x: x.index)]
    return embeddings


def build_embedding_text(scenario: dict) -> str:
    """
    Build the text that will be embedded for a scenario.
    Combines summary, characteristics, and key resolution info.
    """
    parts = [
        scenario["scenario_summary"],
        f"Filing status: {scenario['taxpayer_profile']['filing_status']}",
        f"Key characteristics: {', '.join(scenario['key_characteristics'])}",
    ]
    
    # Add special situations
    if scenario.get("special_situations"):
        parts.append(f"Special situations: {', '.join(scenario['special_situations'])}")
    
    # Add resolution summary
    if scenario.get("resolution_notes", {}).get("summary"):
        parts.append(f"Resolution: {scenario['resolution_notes']['summary']}")
    
    return " ".join(parts)


def process_scenarios(input_file: Path, output_file: Path, endpoint: str, deployment: str, batch_size: int = EMBEDDING_BATCH_SIZE):
    """Process all scenarios and generate embeddings."""
    
    # Load scenarios
    print(f"\n📂 Loading scenarios from: {input_file}")
    with open(input_file, 'r', encoding='utf-8') as f:
        scenarios = json.load(f)
    
    print(f"   Loaded {len(scenarios)} scenarios")
    
    # Create client
    print(f"\n🔌 Connecting to Azure OpenAI (using Azure CLI credentials)...")
    print(f"   Endpoint: {endpoint}")
    print(f"   Deployment: {deployment}")
    client = create_client(endpoint)
    
    # Process in batches
    print(f"\n🚀 Generating embeddings (batch size: {batch_size})")
    
    failed_count = 0
    
    for i in tqdm(range(0, len(scenarios), batch_size), desc="Batches"):
        batch = scenarios[i:i + batch_size]
        texts = [build_embedding_text(s) for s in batch]
        
        try:
            embeddings = generate_embeddings_batch(client, texts, deployment)
            
            for j, embedding in enumerate(embeddings):
                scenarios[i + j]['embedding'] = embedding
                
        except Exception as e:
            tqdm.write(f"\n   ⚠️ Batch {i//batch_size} failed: {e}")
            for scenario in batch:
                scenario['embedding'] = None
                failed_count += 1
            
            if "rate" in str(e).lower():
                tqdm.write(f"   ⏳ Rate limited. Waiting 60 seconds...")
                time.sleep(60)
        
        time.sleep(0.5)
    
    # Save results
    print(f"\n💾 Saving results to: {output_file}  (UTF-16 LE for SQL Server NCLOB)")
    with open(output_file, 'w', encoding='utf-16-le') as f:
        f.write('\ufeff')  # BOM required by SQL Server SINGLE_NCLOB
        json.dump(scenarios, f, ensure_ascii=False)
    
    # Summary
    embedded_count = sum(1 for s in scenarios if s.get('embedding'))
    
    print(f"\n{'='*60}")
    print(f"📊 Embedding Summary")
    print(f"{'='*60}")
    print(f"   Total scenarios: {len(scenarios)}")
    print(f"   Successfully embedded: {embedded_count}")
    print(f"   Failed: {failed_count}")
    print(f"   Output file: {output_file}")


def main():
    parser = argparse.ArgumentParser(description="Generate embeddings for tax scenarios")
    parser.add_argument("--endpoint", type=str, default=AZURE_OPENAI_ENDPOINT,
                        help="Azure OpenAI endpoint (default: from .env)")
    parser.add_argument("--deployment", type=str, default=AZURE_OPENAI_EMBEDDING_DEPLOYMENT,
                        help="Embedding model deployment name (default: from .env)")
    parser.add_argument("--input", type=str, default="tax_scenarios.json",
                        help="Input JSON file with scenarios")
    parser.add_argument("--output", type=str, default="tax_scenarios_embedded.json",
                        help="Output JSON file with embeddings")
    parser.add_argument("--batch-size", type=int, default=EMBEDDING_BATCH_SIZE,
                        help="Batch size for API calls")
    
    args = parser.parse_args()

    if not args.endpoint:
        parser.error("--endpoint is required (or set AZURE_OPENAI_ENDPOINT in .env)")
    if not args.deployment:
        parser.error("--deployment is required (or set AZURE_OPENAI_EMBEDDING_DEPLOYMENT in .env)")
    
    input_file = OUTPUT_DIR / args.input
    output_file = OUTPUT_DIR / args.output
    
    if not input_file.exists():
        print(f"❌ Input file not found: {input_file}")
        print("   Run 04_generate_scenarios.py first")
        return
    
    process_scenarios(input_file, output_file, args.endpoint, args.deployment, args.batch_size)


if __name__ == "__main__":
    main()
