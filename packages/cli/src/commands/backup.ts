import { Command, Flags } from '@oclif/core';
import { isWalletInitialized } from '../utils/config.js';
import { loadMnemonic } from '../utils/mnemonic-storage.js';
import { promptExistingPassword } from '../utils/prompts.js';

export default class Backup extends Command {
  static description = 'Display your mnemonic recovery phrase';

  static examples = ['<%= config.bin %> <%= command.id %>'];

  static flags = {
    password: Flags.string({
      description: 'Encryption password (prompts if omitted)',
    }),
  };

  async run(): Promise<void> {
    const { flags } = await this.parse(Backup);

    try {
      const initialized = await isWalletInitialized();
      if (!initialized) {
        this.error('Wallet not initialized. Run: pqwallet init');
      }

      const password = flags.password ?? (await promptExistingPassword());
      const mnemonic = await loadMnemonic(password);

      this.log('');
      this.log('=== RECOVERY PHRASE ===');
      this.log('');
      this.log('WARNING: Anyone with this phrase can access ALL your accounts.');
      this.log('Do not share this with anyone.');
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
    } catch (error) {
      if (error instanceof Error) {
        this.error(error.message);
      } else {
        this.error('An unknown error occurred');
      }
    }
  }
}
