import { Command, Flags } from '@oclif/core';
import { isWalletInitialized } from '../utils/config.js';
import { generateMnemonic } from '../utils/crypto.js';
import { saveMnemonic } from '../utils/mnemonic-storage.js';
import { promptPasswordWithConfirmation } from '../utils/prompts.js';

export default class Init extends Command {
  static description = 'Initialize wallet by generating a new mnemonic (one-time setup)';

  static examples = ['<%= config.bin %> <%= command.id %>'];

  static flags = {
    password: Flags.string({
      description: 'Encryption password (prompts if omitted, min 8 characters)',
    }),
    force: Flags.boolean({
      description: 'Overwrite existing mnemonic',
      default: false,
    }),
  };

  async run(): Promise<void> {
    const { flags } = await this.parse(Init);

    try {
      const initialized = await isWalletInitialized();
      if (initialized && !flags.force) {
        this.error(
          'Wallet already initialized. Use --force to overwrite (WARNING: this will make existing accounts unrecoverable).'
        );
      }

      const password = flags.password ?? (await promptPasswordWithConfirmation());

      this.log('');
      this.log('Generating 24-word mnemonic...');

      const mnemonic = generateMnemonic();
      await saveMnemonic(mnemonic, password);

      this.log('');
      this.log('=== RECOVERY PHRASE ===');
      this.log('');
      this.log('Write down these 24 words and store them safely.');
      this.log('Anyone with this phrase can access ALL your accounts.');
      this.log('');

      const words = mnemonic.split(' ');
      for (let i = 0; i < words.length; i += 4) {
        const line = words
          .slice(i, i + 4)
          .map((w, j) => `${String(i + j + 1).padStart(2, ' ')}. ${w.padEnd(12)}`)
          .join('  ');
        this.log(`  ${line}`);
      }

      this.log('');
      this.log('======================');
      this.log('');
      this.log('Wallet initialized. Create your first account with: pqwallet create');
    } catch (error) {
      if (error instanceof Error) {
        this.error(error.message);
      } else {
        this.error('An unknown error occurred');
      }
    }
  }
}
