// Account creation
export { createPQAccount } from './accounts/index.js';
export type { CreatePQAccountParams, PQAccount, PQSmartAccount } from './accounts/index.js';

// Client
export { createPQClient } from './clients/index.js';
export type {
  PQClient,
  CreatePQClientParams,
  SigningOptions,
  SendUserOperationOptions,
} from './clients/index.js';

// Key ID computation
export { computeKeyId, computeEcdsaKeyId, computeComposedKeyId } from './signatures/index.js';

// Validator management (call builders)
export {
  buildRegisterKeyCall,
  buildRevokeKeyCall,
  buildSetSchemeAllowedCall,
  buildDisableEcdsaCall,
  buildRegisterComposedKeyCall,
} from './validator/index.js';

// Validator queries
export {
  getOwner,
  isKeyApproved,
  isSchemeAllowed,
  isValidatorInitialized,
} from './validator/index.js';

// Constants
export { SchemeId } from './constants.js';

// Types
export type { SchemeIdType, PQSigner, ComposedSigner, Call } from './types.js';

// ABI (for advanced contract interactions)
export { pqValidatorAbi } from './abis/pqValidatorAbi.js';
