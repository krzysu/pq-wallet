import { Command, Flags } from '@oclif/core';
import { SchemeId, createPQAccount } from '@pq-wallet/sdk';
import { getRequiredConfig, createRpcClient } from '../utils/account-helpers.js';
import { addAccount, getNextKeyIndex, isWalletInitialized, readConfig } from '../utils/config.js';
import { deriveKeysFromMnemonic } from '../utils/crypto.js';
import { saveKeystores } from '../utils/keys-storage.js';
import { loadMnemonic } from '../utils/mnemonic-storage.js';
import { getUniqueAccountName } from '../utils/naming.js';
import { promptExistingPassword } from '../utils/prompts.js';
import {
  createLocalAccount,
  createEthfalconSigner,
  createMldsaethSigner,
} from '../utils/signers.js';
import type { AccountConfig } from '../utils/config.js';

export default class Create extends Command {
  static description = 'Create a new account derived from your mnemonic';

  static examples = [
    '<%= config.bin %> <%= command.id %>',
    '<%= config.bin %> <%= command.id %> --name "my-wallet"',
  ];

  static flags = {
    name: Flags.string({
      description: 'Account name (optional, auto-generated if omitted)',
    }),
    password: Flags.string({
      description: 'Encryption password (prompts if omitted)',
    }),
  };

  async run(): Promise<void> {
    const { flags } = await this.parse(Create);

    try {
      const initialized = await isWalletInitialized();
      if (!initialized) {
        this.error('Wallet not initialized. Run: pqwallet init');
      }

      const password = flags.password ?? (await promptExistingPassword());

      this.log('');
      this.log('Loading wallet...');
      const mnemonic = await loadMnemonic(password);

      const config = await readConfig();
      const keyIndex = getNextKeyIndex(config);

      const { name: accountName, wasModified } = await getUniqueAccountName(flags.name);
      if (wasModified) {
        this.log(`Name "${flags.name}" already exists, using "${accountName}" instead`);
      }

      this.log('Deriving keys...');
      const keys = deriveKeysFromMnemonic(mnemonic, keyIndex);

      const { validatorAddress, chain, rpcUrl } = await getRequiredConfig();
      const publicClient = createRpcClient(chain, rpcUrl);

      const owner = createLocalAccount(keys.ecdsa.secret_key);

      const ethfalconSigner = createEthfalconSigner(
        keys.ethfalcon.public_key.value,
        keys.ethfalcon.secret_key.value
      );
      const mldsaethSigner = createMldsaethSigner(
        keys.mldsaeth.public_key.value,
        keys.mldsaeth.secret_key.value
      );

      this.log('Computing account address...');
      const account = await createPQAccount({
        client: publicClient,
        chain,
        owner,
        index: BigInt(keyIndex),
        validatorAddress,
        pqSigners: [ethfalconSigner, mldsaethSigner],
      });

      await saveKeystores(keys, account.address, password);

      const createdAt = new Date().toISOString();
      const accountConfig: AccountConfig = {
        name: accountName,
        address: account.address,
        ecdsaSigner: owner.address,
        chain: chain.name?.toLowerCase() ?? 'sepolia',
        keyIndex,
        schemes: [
          SchemeId.ECDSA,
          SchemeId.ETHFALCON,
          SchemeId.MLDSAETH,
          SchemeId.ECDSA_ETHFALCON,
          SchemeId.ECDSA_MLDSAETH,
        ],
        validatorAddress,
        createdAt,
      };
      await addAccount(accountConfig);

      this.log('');
      this.log('Account created successfully!');
      this.log('');
      this.log(`  Name:           ${accountName}`);
      this.log(`  Address:        ${account.address}`);
      this.log(`  ECDSA Signer:   ${owner.address}`);
      this.log(`  Chain:          ${chain.name}`);
      this.log(`  Key Index:      ${String(keyIndex)}`);
      this.log(`  Deployed:       ${account.isDeployed ? 'Yes' : 'No (counterfactual)'}`);
      this.log('');
      this.log('Deploy with: pqwallet deploy --account ' + accountName);
    } catch (error) {
      if (error instanceof Error) {
        this.error(error.message);
      } else {
        this.error('An unknown error occurred');
      }
    }
  }
}
