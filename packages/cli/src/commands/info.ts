import { Command, Flags } from '@oclif/core';
import { SchemeId, isSchemeAllowed, isValidatorInitialized, getOwner } from '@pq-wallet/sdk';
import { formatEther } from 'viem';
import type { SchemeIdType } from '@pq-wallet/sdk';
import { getRequiredConfig, createRpcClient } from '../utils/account-helpers.js';
import { getAccountConfig } from '../utils/config.js';
import { formatSchemeId } from '../utils/signers.js';
import type { Address, Chain, PublicClient, Transport } from 'viem';

const ALL_SCHEMES: SchemeIdType[] = [
  SchemeId.ECDSA,
  SchemeId.ETHFALCON,
  SchemeId.MLDSAETH,
  SchemeId.ECDSA_ETHFALCON,
  SchemeId.ECDSA_MLDSAETH,
];

async function queryEnabledSchemes(
  publicClient: PublicClient<Transport, Chain>,
  validatorAddress: Address,
  accountAddress: Address
): Promise<string[]> {
  const enabled: string[] = [];
  for (const scheme of ALL_SCHEMES) {
    const allowed = await isSchemeAllowed(publicClient, validatorAddress, accountAddress, scheme);
    if (allowed) {
      enabled.push(formatSchemeId(scheme));
    }
  }
  return enabled;
}

export default class Info extends Command {
  static description = 'Display detailed account information (no password required)';

  static examples = [
    '<%= config.bin %> <%= command.id %> --account my-wallet',
    '<%= config.bin %> <%= command.id %> --account 0x1234...',
  ];

  static flags = {
    account: Flags.string({
      description: 'Account name or address',
      required: true,
      char: 'a',
    }),
  };

  async run(): Promise<void> {
    const { flags } = await this.parse(Info);

    try {
      const accountConfig = await getAccountConfig(flags.account);
      if (!accountConfig) {
        this.error(`Account "${flags.account}" not found. Run: pqwallet list`);
      }

      const { validatorAddress, chain, rpcUrl } = await getRequiredConfig();
      const publicClient = createRpcClient(chain, rpcUrl);

      const code = await publicClient.getCode({ address: accountConfig.address });
      const isDeployed = code !== undefined && code !== '0x';

      this.log('');
      this.log(`  Name:           ${accountConfig.name}`);
      this.log(`  Address:        ${accountConfig.address}`);
      this.log(`  ECDSA Signer:   ${accountConfig.ecdsaSigner}`);
      this.log(`  Chain:          ${accountConfig.chain}`);
      this.log(`  Key Index:      ${String(accountConfig.keyIndex)}`);
      this.log(`  Deployed:       ${isDeployed ? 'Yes' : 'No (counterfactual)'}`);
      this.log(`  Created:        ${new Date(accountConfig.createdAt).toLocaleString()}`);

      const balance = await publicClient.getBalance({ address: accountConfig.address });
      if (isDeployed || balance > 0n) {
        this.log(`  Balance:        ${formatEther(balance)} ETH`);
      }

      if (isDeployed) {
        const initialized = await isValidatorInitialized(
          publicClient,
          validatorAddress,
          accountConfig.address
        );
        this.log(`  Validator:      ${initialized ? 'Initialized' : 'Not initialized'}`);

        if (initialized) {
          const owner = await getOwner(publicClient, validatorAddress, accountConfig.address);
          this.log(`  On-chain Owner: ${owner}`);

          const enabledSchemes = await queryEnabledSchemes(
            publicClient,
            validatorAddress,
            accountConfig.address
          );
          this.log(
            `  Schemes:        ${enabledSchemes.length > 0 ? enabledSchemes.join(', ') : 'None'}`
          );
        }
      }

      this.log('');
    } catch (error) {
      if (error instanceof Error) {
        this.error(error.message);
      } else {
        this.error('An unknown error occurred');
      }
    }
  }
}
