import password from '@inquirer/password';

export async function promptPasswordWithConfirmation(message = 'Enter password'): Promise<string> {
  const pass = await password({ message, mask: '*' });

  if (!pass || pass.length < 8) {
    throw new Error('Password must be at least 8 characters');
  }

  const confirm = await password({ message: 'Confirm password', mask: '*' });

  if (pass !== confirm) {
    throw new Error('Passwords do not match');
  }

  return pass;
}

export async function promptExistingPassword(message = 'Enter password'): Promise<string> {
  return password({ message, mask: '*' });
}
