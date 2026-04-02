import { Command, Flags } from '@oclif/core';
import { createPQClient, SchemeId } from '@pq-wallet/sdk';
import { formatEther, http, isAddress, parseEther } from 'viem';
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

export default class Send extends Command {
  static description = 'Send ETH to an address';

  static examples = [
    '<%= config.bin %> <%= command.id %> --from my-wallet --to 0x1234... --amount 0.01',
    '<%= config.bin %> <%= command.id %> --from my-wallet --to 0x1234... --amount 0.01 --sponsor',
  ];

  static flags = {
    from: Flags.string({
      description: 'Sender account name or address',
      required: true,
    }),
    to: Flags.string({
      description: 'Recipient address',
      required: true,
    }),
    amount: Flags.string({
      description: 'Amount in ETH (e.g., "0.01")',
      required: true,
    }),
    password: Flags.string({
      description: 'Encryption password (prompts if omitted)',
    }),
    sponsor: Flags.boolean({
      description: 'Use paymaster to sponsor gas fees',
      default: false,
    }),
    scheme: Flags.string({
      description:
        'Signature scheme: 0 (ECDSA), 1 (ETHFALCON), 2 (MLDSAETH), 101 (ECDSA+ETHFALCON), 102 (ECDSA+MLDSAETH)',
      options: ['0', '1', '2', '101', '102'],
    }),
  };

  async run(): Promise<void> {
    const { flags } = await this.parse(Send);

    try {
      if (!isAddress(flags.to)) {
        this.error(`Invalid recipient address: ${flags.to}`);
      }

      let amount: bigint;
      try {
        amount = parseEther(flags.amount);
        if (amount <= 0n) {
          this.error('Amount must be greater than 0');
        }
      } catch {
        this.error(`Invalid amount: ${flags.amount}`);
      }

      const password = flags.password ?? (await promptExistingPassword());

      this.log('Restoring account...');

      const { account, publicClient } = await setupAccount(flags.from, password);
      const { bundlerUrl } = await getRequiredConfig();

      // Check balance
      const balance = await publicClient.getBalance({ address: account.address });
      if (balance < amount) {
        this.error(
          `Insufficient balance: ${formatEther(balance)} ETH (trying to send ${flags.amount} ETH)`
        );
      }

      const schemeId = flags.scheme ? SCHEME_OPTIONS[flags.scheme] : undefined;
      const effectiveScheme = schemeId ?? SchemeId.ECDSA;
      const schemeName = formatSchemeId(effectiveScheme);
      const sponsorMessage = flags.sponsor ? ' (gas sponsored)' : '';

      this.log(
        `Sending ${flags.amount} ETH to ${flags.to} using ${schemeName}${sponsorMessage}...`
      );

      const client = createPQClient({
        account,
        client: publicClient,
        transport: http(bundlerUrl),
        paymaster: flags.sponsor ? true : undefined,
      });

      const sendOptions = schemeId !== undefined ? { schemeId } : undefined;
      const hash = await client.sendUserOperation(
        {
          calls: [
            {
              to: flags.to,
              value: amount,
              data: '0x',
            },
          ],
        },
        sendOptions
      );

      this.log(`UserOperation hash: ${hash}`);
      this.log('Waiting for confirmation...');

      await client.bundlerClient.waitForUserOperationReceipt({ hash });

      this.log('');
      this.log('Transaction confirmed!');
      this.log('');

      process.exit(0);
    } catch (error) {
      this.error(error instanceof Error ? error.message : 'Failed to send transaction');
    }
  }
}
