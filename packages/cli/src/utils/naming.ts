import { getAllAccountNames } from './config.js';

export async function getUniqueAccountName(
  requestedName?: string
): Promise<{ name: string; wasModified: boolean }> {
  const existingNames = await getAllAccountNames();

  if (!requestedName) {
    const index = existingNames.length + 1;
    let name = `account-${String(index)}`;
    let counter = index;
    while (existingNames.includes(name)) {
      counter++;
      name = `account-${String(counter)}`;
    }
    return { name, wasModified: false };
  }

  if (!existingNames.includes(requestedName)) {
    return { name: requestedName, wasModified: false };
  }

  let counter = 2;
  let name = `${requestedName}-${String(counter)}`;
  while (existingNames.includes(name)) {
    counter++;
    name = `${requestedName}-${String(counter)}`;
  }
  return { name, wasModified: true };
}
