import { initBedrock } from '@tectonic-labs/bedrock-wasm';
import { setBedrock } from '../utils/bedrock.js';
import type { Hook } from '@oclif/core';

const hook: Hook<'init'> = async function () {
  const bedrock = await initBedrock();
  setBedrock(bedrock);
};

export default hook;
