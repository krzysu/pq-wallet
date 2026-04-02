import type { BedrockWasm } from '@tectonic-labs/bedrock-wasm';

let instance: BedrockWasm | undefined;

export function setBedrock(bedrock: BedrockWasm): void {
  instance = bedrock;
}

export function getBedrock(): BedrockWasm {
  if (!instance) {
    throw new Error('Bedrock WASM not initialized. This should not happen.');
  }
  return instance;
}
