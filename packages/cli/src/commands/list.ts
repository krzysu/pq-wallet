import { Command } from '@oclif/core';
import { readConfig } from '../utils/config.js';

export default class List extends Command {
  static description = 'List all wallet accounts';

  static examples = ['<%= config.bin %> <%= command.id %>'];

  async run(): Promise<void> {
    await this.parse(List);

    try {
      const config = await readConfig();

      if (config.accounts.length === 0) {
        this.log('No accounts found.');
        this.log('');
        this.log('Create a new account with: pqwallet create');
        return;
      }

      this.log('');
      this.log(`Found ${String(config.accounts.length)} account(s):`);

      for (const account of config.accounts) {
        this.log('');
        this.log(`  Name:           ${account.name}`);
        this.log(`  Address:        ${account.address}`);
        this.log(`  ECDSA Signer:   ${account.ecdsaSigner}`);
        this.log(`  Chain:          ${account.chain}`);
        this.log(`  Key Index:      ${String(account.keyIndex)}`);
        this.log(`  Created:        ${new Date(account.createdAt).toLocaleString()}`);
      }

      this.log('');
      this.log('Use "pqwallet info --account <name>" for detailed on-chain information');
    } catch (error) {
      if (error instanceof Error) {
        this.error(error.message);
      } else {
        this.error('An unknown error occurred');
      }
    }
  }
}
