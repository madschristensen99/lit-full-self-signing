import { type Admin as FssAdmin } from '@lit-protocol/full-self-signing';

import { logger } from '../../utils/logger';
import { FssCliError, FssCliErrorType } from '../../errors';
import { promptSelectDelegateesToAdd } from '../../prompts/admin';

const batchAddDelegatees = async (fssAdmin: FssAdmin, addresses: string[]) => {
  logger.loading('Adding delegatees...');
  await fssAdmin.batchAddDelegatees(addresses);
  logger.success('Successfully added delegatees');
};

export const handleBatchAddDelegatee = async (fssAdmin: FssAdmin) => {
  try {
    const addresses = await promptSelectDelegateesToAdd();
    await batchAddDelegatees(fssAdmin, addresses);
  } catch (error) {
    if (error instanceof FssCliError) {
      if (error.type === FssCliErrorType.ADMIN_BATCH_ADD_DELEGATEE_CANCELLED) {
        logger.error('Batch delegatee addition cancelled.');
        return;
      }
    }

    throw error;
  }
};