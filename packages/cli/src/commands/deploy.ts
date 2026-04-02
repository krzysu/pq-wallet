import { Command, Flags } from '@oclif/core';
import { createPQClient } from '@pq-wallet/sdk';
import { http } from 'viem';
import { setupAccount, getRequiredConfig } from '../utils/account-helpers.js';
import { promptExistingPassword } from '../utils/prompts.js';

export default class Deploy extends Command {
  static description = 'Deploy a smart account on-chain';

  static examples = ['<%= config.bin %> <%= command.id %> --account my-wallet'];

  static flags = {
    account: Flags.string({
      description: 'Account name or address to deploy',
      required: true,
      char: 'a',
    }),
    password: Flags.string({
      description: 'Encryption password (prompts if omitted)',
    }),
    sponsor: Flags.boolean({
      description: 'Use paymaster to sponsor gas fees',
      default: false,
    }),
  };

  async run(): Promise<void> {
    const { flags } = await this.parse(Deploy);

    try {
      const password = flags.password ?? (await promptExistingPassword());

      this.log('Restoring account...');

      const { account, publicClient } = await setupAccount(flags.account, password);

      if (account.isDeployed) {
        this.log('');
        this.log('Account is already deployed on-chain.');
        return;
      }

      const { bundlerUrl } = await getRequiredConfig();

      const sponsorMessage = flags.sponsor ? ' (gas sponsored)' : '';
      this.log(`Deploying account${sponsorMessage}...`);

      const client = createPQClient({
        account,
        client: publicClient,
        transport: http(bundlerUrl),
        paymaster: flags.sponsor ? true : undefined,
      });

      const hash = await client.sendUserOperation({
        calls: [
          {
            to: account.address,
            value: 0n,
            data: '0x',
          },
        ],
      });

      this.log(`UserOperation hash: ${hash}`);
      this.log('Waiting for confirmation...');

      await client.bundlerClient.waitForUserOperationReceipt({ hash });

      this.log('');
      this.log('Account deployed successfully!');
      this.log(`  Address: ${account.address}`);
      this.log('');

      process.exit(0);
    } catch (error) {
      this.error(error instanceof Error ? error.message : 'Failed to deploy account');
    }
  }
}
