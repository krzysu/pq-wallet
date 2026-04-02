import { Command, Flags } from '@oclif/core';
import { isAddress } from 'viem';
import { validateChain } from '../utils/account-helpers.js';
import { readConfig, writeConfig } from '../utils/config.js';
import type { Config } from '../utils/config.js';

export default class Configure extends Command {
  static description = 'Configure wallet settings (bundler URL, validator address, chain, etc.)';

  static examples = [
    '<%= config.bin %> <%= command.id %> --bundler-url https://rpc.zerodev.app/...',
    '<%= config.bin %> <%= command.id %> --validator-address 0x1234...',
    '<%= config.bin %> <%= command.id %> --chain sepolia',
  ];

  static flags = {
    'bundler-url': Flags.string({
      description: 'ERC-4337 bundler URL',
    }),
    'paymaster-url': Flags.string({
      description: 'Paymaster URL for gas sponsorship',
    }),
    'validator-address': Flags.string({
      description: 'PQValidator contract address',
    }),
    'rpc-url': Flags.string({
      description: 'RPC URL for chain reads',
    }),
    chain: Flags.string({
      description: 'Chain name (e.g., sepolia)',
    }),
    show: Flags.boolean({
      description: 'Display current configuration',
      default: false,
    }),
  };

  private showConfig(config: Config): void {
    this.log('');
    this.log('Current configuration:');
    this.log(`  Bundler URL:        ${config.bundlerUrl ?? '(not set)'}`);
    this.log(`  Paymaster URL:      ${config.paymasterUrl ?? '(not set)'}`);
    this.log(`  Validator Address:  ${config.validatorAddress ?? '(not set)'}`);
    this.log(`  RPC URL:            ${config.rpcUrl ?? '(default)'}`);
    this.log(`  Chain:              ${config.chain ?? 'sepolia'}`);
    this.log(`  Accounts:           ${String(config.accounts.length)}`);
    this.log('');
  }

  private applyUpdates(
    config: Config,
    flags: Record<string, string | boolean | undefined>
  ): boolean {
    let updated = false;

    if (typeof flags['bundler-url'] === 'string') {
      config.bundlerUrl = flags['bundler-url'];
      this.log(`Bundler URL set to: ${flags['bundler-url']}`);
      updated = true;
    }

    if (typeof flags['paymaster-url'] === 'string') {
      config.paymasterUrl = flags['paymaster-url'];
      this.log(`Paymaster URL set to: ${flags['paymaster-url']}`);
      updated = true;
    }

    if (typeof flags['validator-address'] === 'string') {
      if (!isAddress(flags['validator-address'])) {
        this.error(`Invalid address: ${flags['validator-address']}`);
      }
      config.validatorAddress = flags['validator-address'];
      this.log(`Validator address set to: ${flags['validator-address']}`);
      updated = true;
    }

    if (typeof flags['rpc-url'] === 'string') {
      config.rpcUrl = flags['rpc-url'];
      this.log(`RPC URL set to: ${flags['rpc-url']}`);
      updated = true;
    }

    if (typeof flags.chain === 'string') {
      validateChain(flags.chain);
      config.chain = flags.chain;
      this.log(`Chain set to: ${flags.chain}`);
      updated = true;
    }

    return updated;
  }

  async run(): Promise<void> {
    const { flags } = await this.parse(Configure);

    try {
      const config = await readConfig();

      if (flags.show) {
        this.showConfig(config);
        return;
      }

      const updated = this.applyUpdates(config, flags);

      if (updated) {
        await writeConfig(config);
        this.log('Configuration saved.');
      } else {
        this.log('No changes specified. Use --show to view current configuration.');
      }
    } catch (error) {
      if (error instanceof Error) {
        this.error(error.message);
      } else {
        this.error('An unknown error occurred');
      }
    }
  }
}
