import { Command, Flags } from '@oclif/core';
import { createPQClient, SchemeId } from '@pq-wallet/sdk';
import { http } from 'viem';
import type { SchemeIdType } from '@pq-wallet/sdk';
import { setupAccount, getRequiredConfig } from '../utils/account-helpers.js';
import { promptExistingPassword } from '../utils/prompts.js';
import { formatSchemeId } from '../utils/signers.js';

const SCHEME_OPTIONS: Record<string, SchemeIdType> = {
  '0': SchemeId.ECDSA,
  '1': SchemeId.ETHFALCON,
  '2': SchemeId.MLDSAETH,
  '101': SchemeId.ECDSA_ETHFALCON,
  '102': SchemeId.ECDSA_MLDSAETH,
};

export default class Sign extends Command {
  static description = 'Sign a message with your account';

  static examples = [
    '<%= config.bin %> <%= command.id %> --message "Hello" --account my-wallet',
    '<%= config.bin %> <%= command.id %> --message "Hello" --account my-wallet --scheme 101',
  ];

  static flags = {
    message: Flags.string({
      description: 'Message to sign',
      required: true,
    }),
    account: Flags.string({
      description: 'Account name or address',
      required: true,
      char: 'a',
    }),
    password: Flags.string({
      description: 'Keystore password (prompts if omitted)',
    }),
    scheme: Flags.string({
      description:
        'Signature scheme: 0 (ECDSA), 1 (ETHFALCON), 2 (MLDSAETH), 101 (ECDSA+ETHFALCON), 102 (ECDSA+MLDSAETH)',
      options: ['0', '1', '2', '101', '102'],
    }),
  };

  async run(): Promise<void> {
    const { flags } = await this.parse(Sign);

    try {
      const password = flags.password ?? (await promptExistingPassword());

      this.log('Restoring account...');

      const { account, publicClient } = await setupAccount(flags.account, password);
      const { bundlerUrl } = await getRequiredConfig();

      const schemeId = flags.scheme ? SCHEME_OPTIONS[flags.scheme] : undefined;
      const effectiveScheme = schemeId ?? SchemeId.ECDSA;
      const schemeName = formatSchemeId(effectiveScheme);

      const client = createPQClient({
        account,
        client: publicClient,
        transport: http(bundlerUrl),
      });

      this.log(`Signing message with ${schemeName}...`);

      const signature = await client.signMessage(
        flags.message,
        schemeId !== undefined ? { schemeId } : undefined
      );

      this.log('');
      this.log('Message signed successfully!');
      this.log('');
      this.log(`  Message:   "${flags.message}"`);
      this.log(`  Account:   ${account.address}`);
      this.log(`  Scheme:    ${schemeName}`);
      this.log(`  Deployed:  ${account.isDeployed ? 'Yes' : 'No (counterfactual)'}`);
      this.log('');
      this.log('Signature:');
      this.log(`  ${signature}`);
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
